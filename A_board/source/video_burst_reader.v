`timescale 1ns/1ps
// Read ahead through the official asynchronous FIFO interface.
module video_burst_reader #(
    parameter WIDTH=640, HEIGHT=480, H_TOTAL=800, V_TOTAL=525,
    parameter H_SYNC=656, H_SYNC_END=752, V_SYNC=490, V_SYNC_END=492,
    parameter BASE=921600, LOW_WATER=512, START_WATER=512, FIFO_AW=10
)(
    input wire mclk, mrst_n, enable,
    input wire [20:0] display_base,
    input wire swap_toggle,
    input wire ctrl_clk, ctrl_rst_n, wipe_pending,
    input wire [1:0] effect_mode,
    input wire [20:0] target_base,
    input wire [31:0] target_id, target_crc,
    output wire wipe_busy,
    output wire wipe_commit,
    output wire [1:0] wipe_phase,
    output reg [31:0] mixed_frames,
    output wire [5:0] wipe_step,
    output reg swap_ack,
    input wire [31:0] display_id,
    output reg [31:0] last_id, commits,
    output wire request,
    output wire [20:0] address,
    input wire request_ready, data_valid,
    input wire [31:0] data,
    input wire burst_done, burst_error,
    input wire pclk, prst_n,
    input wire [31:0] expected_crc,
    output reg hs, vs, de,
    output reg [23:0] rgb,
    output wire [9:0] pixel_x, pixel_y,
    output wire [31:0] active_id,
    output reg [31:0] frames, good_frames, bad_frames, underflows, last_crc,
    output reg [31:0] fifo_min, fifo_max,
    output reg [31:0] read_errors,
    output reg active,
    output wire [31:0] probe_stream_data,
    output wire [20:0] probe_stream_addr,
    output wire probe_stream_valid,
    output wire observe_frame_wipe,output wire [20:0] observe_new_base
);
    localparam WORDS=WIDTH*HEIGHT;
    (* ASYNC_REG="TRUE" *) reg en1,en2,epoch1,epoch2;
    (* ASYNC_REG="TRUE" *) reg rflush_m1,rflush_m2;
    reg epoch_seen, clean_epoch, mflush, running;
    // The FIFO asserts reset asynchronously and releases it in each domain.
    // Wait four additional mclk edges after shared reset release before writing
    // the first SDRAM burst.
    reg [3:0] flush_cycles;
    reg [20:0] base_q;
    reg outstanding;
    reg [19:0] offset;
    wire full,empty;
    wire [FIFO_AW:0] wcount,rcount;
    wire [31:0] pixel;
    reg [9:0] x,y;
    reg [9:0] pixel_x_q,pixel_y_q;
    // Capture the frame bundle at a raster boundary. Keep it held until both
    // SDRAM prefetch and pixel CRC complete.
    reg [20:0] frame_base;
    reg [31:0] frame_id,frame_crc;
    reg frame_swap;
    reg [20:0] frame_new_base;
    reg [31:0] frame_new_crc, frame_new_id;
    reg [9:0] frame_bound;
    reg [1:0] frame_mode;
    reg frame_wipe, wait_commit, commit_toggle;
    reg [5:0] step;
    (* ASYNC_REG="TRUE" *) reg pending_p1,pending_p2;
    (* ASYNC_REG="TRUE" *) reg busy_c1,busy_c2,commit_c1,commit_c2;
    reg commit_seen;
    assign observe_frame_wipe=frame_wipe;assign observe_new_base=frame_new_base;
    assign wipe_step=step;
    assign wipe_phase=(frame_wipe || wait_commit) ? 2'd1 : 2'd0;
    assign wipe_busy=busy_c2;
    assign wipe_commit=commit_c2^commit_seen;
    always @(posedge ctrl_clk or negedge ctrl_rst_n) begin
        if(!ctrl_rst_n) begin busy_c1<=0;busy_c2<=0;commit_c1<=0;commit_c2<=0;commit_seen<=0;end
        else begin busy_c1<=frame_wipe || wait_commit;busy_c2<=busy_c1;commit_c1<=commit_toggle;commit_c2<=commit_c1;commit_seen<=commit_c2;end
    end
    (* ASYNC_REG="TRUE" *) reg en1_p,en2_p,swap_p1,swap_p2,clean1,clean2,read_fault_p1,read_fault_p2;
    reg frame_epoch, rflush, have_image, started;
    reg [2:0] settle;
    reg [31:0] current_crc, current_id, crc, words;
    wire visible=x<WIDTH && y<HEIGHT;
    wire start_now=x==0 && y==0 && en2_p && have_image && !rflush && rcount>=START_WATER;
    wire pop=visible && (active || start_now);
    // Reflected CRC32 transform, checked independently against zlib.
    function [31:0] crc_word;
        input [31:0] c,w;reg [31:0] z;
        begin
            z=c^{w[7:0],w[15:8],w[23:16],w[31:24]};
            crc_word[0]=^(z & 32'h04d101df);
            crc_word[1]=^(z & 32'h09a203be);
            crc_word[2]=^(z & 32'h1344077d);
            crc_word[3]=^(z & 32'h26880efa);
            crc_word[4]=^(z & 32'h4d101df4);
            crc_word[5]=^(z & 32'h9a203be9);
            crc_word[6]=^(z & 32'h3091760d);
            crc_word[7]=^(z & 32'h6122ec1a);
            crc_word[8]=^(z & 32'hc245d835);
            crc_word[9]=^(z & 32'h805ab1b5);
            crc_word[10]=^(z & 32'h046462b5);
            crc_word[11]=^(z & 32'h08c8c56a);
            crc_word[12]=^(z & 32'h11918ad4);
            crc_word[13]=^(z & 32'h232315a9);
            crc_word[14]=^(z & 32'h46462b53);
            crc_word[15]=^(z & 32'h8c8c56a6);
            crc_word[16]=^(z & 32'h1dc9ac92);
            crc_word[17]=^(z & 32'h3b935924);
            crc_word[18]=^(z & 32'h7726b249);
            crc_word[19]=^(z & 32'hee4d6493);
            crc_word[20]=^(z & 32'hd84bc8f9);
            crc_word[21]=^(z & 32'hb446902d);
            crc_word[22]=^(z & 32'h6c5c2184);
            crc_word[23]=^(z & 32'hd8b84309);
            crc_word[24]=^(z & 32'hb5a187cc);
            crc_word[25]=^(z & 32'h6f920e46);
            crc_word[26]=^(z & 32'hdf241c8c);
            crc_word[27]=^(z & 32'hba9938c7);
            crc_word[28]=^(z & 32'h71e37051);
            crc_word[29]=^(z & 32'he3c6e0a3);
            crc_word[30]=^(z & 32'hc35cc098);
            crc_word[31]=^(z & 32'h826880ef);
        end
    endfunction
    wire [31:0] next_crc=crc_word(crc,pixel);
    wire frame_complete=!read_fault_p2 && !empty && words==WORDS-1 &&
        (!(frame_wipe && (step==0 || step==32)) || (next_crc^32'hffffffff)==current_crc);
    assign request=en2 && running && !outstanding && !mflush && !rflush_m2 && epoch2==epoch_seen &&
                   offset<WORDS && wcount<=LOW_WATER && read_errors==0;
    // Emit ordered runs from aligned 256-word blocks. Advance only when the
    // beat and locked source match the next pixel. Restart the block at a
    // source boundary, discarding emitted prefixes and wrong-source suffixes.
    // Left/top wipe needs at most three runs per block, including row wrap.
    reg [31:0] stream_data;
    reg pipeline_valid,source_new;
    reg [8:0] received,emitted;
    reg [9:0] emit_x,emit_y;
    reg [20:0] new_base_q;
    reg [9:0] bound_q;
    reg [1:0] mode_q;
    reg wipe_q,cross_new;
    reg [5:0] step_q;
    function [8:0] eased_alpha;
        input integer index;
        begin
            case(index)
                0: eased_alpha=9'd0;
                1: eased_alpha=9'd1;
                2: eased_alpha=9'd3;
                3: eased_alpha=9'd6;
                4: eased_alpha=9'd11;
                5: eased_alpha=9'd17;
                6: eased_alpha=9'd24;
                7: eased_alpha=9'd31;
                8: eased_alpha=9'd40;
                9: eased_alpha=9'd49;
                10: eased_alpha=9'd59;
                11: eased_alpha=9'd70;
                12: eased_alpha=9'd81;
                13: eased_alpha=9'd92;
                14: eased_alpha=9'd104;
                15: eased_alpha=9'd116;
                16: eased_alpha=9'd128;
                17: eased_alpha=9'd140;
                18: eased_alpha=9'd152;
                19: eased_alpha=9'd164;
                20: eased_alpha=9'd175;
                21: eased_alpha=9'd186;
                22: eased_alpha=9'd197;
                23: eased_alpha=9'd207;
                24: eased_alpha=9'd216;
                25: eased_alpha=9'd225;
                26: eased_alpha=9'd232;
                27: eased_alpha=9'd239;
                28: eased_alpha=9'd245;
                29: eased_alpha=9'd250;
                30: eased_alpha=9'd253;
                31: eased_alpha=9'd255;
                32: eased_alpha=9'd256;
                default:eased_alpha=9'd256;
            endcase
        end
    endfunction
    wire cross_active=wipe_q && mode_q==2 && step_q!=0 && step_q!=32;
    wire cross_valid;
    wire [23:0] cross_rgb;
    wire cross_beat=data_valid && outstanding && received<256 && cross_active;
    crossfade_blend blend(.clk(mclk),.rst_n(mrst_n),.flush(mflush || epoch2!=epoch_seen),
      .old_valid(cross_beat && !source_new),.new_valid(cross_beat && source_new),
      .beat(received[7:0]),.data(data[23:0]),.alpha(eased_alpha(step_q)),.valid(cross_valid),.rgb(cross_rgb));
    wire choose_new=wipe_q && (mode_q==2 ? (step_q==32 || cross_new) : (mode_q==1 ? emit_y<bound_q : emit_x<bound_q));
    // Zero-cycle buffer protects the routed FF-to-EMB data hold path.
    wire [31:0] stream_data_buffered; /* fehdl keep="true" */
    genvar sd;
    generate for(sd=0;sd<32;sd=sd+1)begin:g_stream_delay
        AL_MAP_LUT1 #(.EQN("(A)"),.INIT(2'b10)) u_buf(.a(stream_data[sd]),.o(stream_data_buffered[sd]));
    end endgenerate
    wire fifo_push=pipeline_valid;
    // Between requests, the read-only client may sample the last complete
    // ordinary burst. Exclude epoch/flush and mixed-image bursts; observation
    // does not stall the pixel or FIFO path.
    assign probe_stream_data=stream_data_buffered;
    assign probe_stream_addr=base_q+offset-1'b1;
    assign probe_stream_valid=en2 && running && !outstanding && !mflush &&
        !rflush_m2 && epoch2==epoch_seen && offset>=256 && !wipe_q && read_errors==0;
    assign address=(choose_new ? new_base_q : base_q)+offset;
    assign pixel_x=pixel_x_q;
    assign pixel_y=pixel_y_q;
    assign active_id=current_id;
    video_fifo #(.AW(FIFO_AW)) fifo(
        .wclk(mclk),.wrst_n(mrst_n),.wflush(mflush),.push(fifo_push),.wdata(stream_data_buffered),
        .full(full),.wcount(wcount),.rclk(pclk),.rrst_n(prst_n),.rflush(rflush),
        .pop(pop),.rdata(pixel),.empty(empty),.rcount(rcount));
    always @(posedge mclk or negedge mrst_n) begin
        if(!mrst_n) begin
            en1<=0; en2<=0; rflush_m1<=1; rflush_m2<=1; outstanding<=0; offset<=0; read_errors<=0;
            pipeline_valid<=0;stream_data<=0;source_new<=0;received<=0;emitted<=0;
            emit_x<=0;emit_y<=0;new_base_q<=BASE;bound_q<=0;mode_q<=0;wipe_q<=0;cross_new<=0;step_q<=0;
            base_q<=BASE; epoch1<=0; epoch2<=0; epoch_seen<=0; clean_epoch<=0;
            mflush<=0; flush_cycles<=0; running<=0;
        end else begin
            epoch1<=frame_epoch; epoch2<=epoch1;
            en1<=enable; en2<=en1;
            rflush_m1<=rflush; rflush_m2<=rflush_m1;
            pipeline_valid<=0;
            if(cross_valid)begin stream_data<={8'd0,cross_rgb};pipeline_valid<=1;end
            if(request && request_ready) begin
                outstanding<=1;received<=0;source_new<=choose_new;
            end
            if(data_valid && outstanding && received<256) begin
                received<=received+1'b1;
                if(cross_active)begin
                    if(source_new)emitted<=emitted+1'b1;
                end else if(received==emitted && source_new==choose_new) begin
                    stream_data<=data;pipeline_valid<=1;emitted<=emitted+1'b1;
                    if(emit_x==WIDTH-1) begin emit_x<=0;emit_y<=emit_y+1'b1;end
                    else emit_x<=emit_x+1'b1;
                end
            end
            if((fifo_push && full) || (data_valid && (!outstanding || received>=256))) read_errors<=read_errors+1'b1;
            if(burst_done) begin
                outstanding<=0;
                if(burst_error || received!=256 || (emitted==0 && !(cross_active && !source_new))) read_errors<=read_errors+1'b1;
                else if(cross_active && !source_new)cross_new<=1;
                else if(emitted==256) begin offset<=offset+256;emitted<=0;cross_new<=0;end
            end
            if(epoch2!=epoch_seen && !outstanding) begin
                epoch_seen<=epoch2; base_q<=frame_base; offset<=0;
                new_base_q<=frame_new_base; bound_q<=frame_bound; mode_q<=frame_mode; wipe_q<=frame_wipe;step_q<=step;cross_new<=0;
                emit_x<=0;emit_y<=0;emitted<=0;pipeline_valid<=0;
                mflush<=1; running<=0; flush_cycles<=8;
            end else if(mflush) begin
                if(flush_cycles==0) begin mflush<=0; running<=1; clean_epoch<=epoch_seen; end
                else flush_cycles<=flush_cycles-1'b1;
            end
        end
    end
    always @(posedge pclk or negedge prst_n) begin
        if(!prst_n) begin
            x<=0; y<=0; hs<=1; vs<=1; de<=0; rgb<=0; active<=0;
            pending_p1<=0;pending_p2<=0;frame_new_base<=BASE;frame_new_crc<=0;frame_new_id<=0;
            frame_bound<=0;frame_mode<=0;frame_wipe<=0;wait_commit<=0;commit_toggle<=0;step<=0;mixed_frames<=0;
            pixel_x_q<=0; pixel_y_q<=0; frame_base<=BASE; frame_id<=0; frame_crc<=0; frame_swap<=0;
            en1_p<=0; en2_p<=0; swap_p1<=0; swap_p2<=0; swap_ack<=0;read_fault_p1<=0;read_fault_p2<=0;
            frame_epoch<=0; rflush<=0; have_image<=0; started<=0;
            clean1<=0; clean2<=0; settle<=0;
            last_id<=0; commits<=0; current_id<=0;
            frames<=0; good_frames<=0; bad_frames<=0; underflows<=0; last_crc<=0;
            crc<=32'hffffffff; words<=0; fifo_min<=32'hffffffff; fifo_max<=0; current_crc<=0;
        end else begin
            en1_p<=enable; en2_p<=en1_p; pending_p1<=wipe_pending;pending_p2<=pending_p1;
            swap_p1<=swap_toggle; swap_p2<=swap_p1;
            clean1<=clean_epoch; clean2<=clean1;
            read_fault_p1<=read_errors!=0;read_fault_p2<=read_fault_p1;
            if(x==H_TOTAL-1) begin x<=0; y<=(y==V_TOTAL-1)?0:y+1'b1; end
            else x<=x+1'b1;
            hs<=!(x>=H_SYNC && x<H_SYNC_END);
            vs<=!(y>=V_SYNC && y<V_SYNC_END);
            de<=visible;
            pixel_x_q<=x; pixel_y_q<=y;
            rgb<=(x<WIDTH/3)?24'hff0000:(x<WIDTH*2/3)?24'h00ff00:24'h0000ff;
            if(en2_p && !started && x==WIDTH-1 && y==HEIGHT-1) begin
                frame_base<=display_base; frame_id<=display_id; frame_crc<=expected_crc; frame_swap<=swap_p2;
                started<=1; frame_epoch<=~frame_epoch; rflush<=1; settle<=0;
            end
            if(rflush && clean2==frame_epoch) begin
                if(settle==4) begin
                    rflush<=0; have_image<=1;
                    current_crc<=frame_wipe && step==32 ? frame_new_crc : frame_crc; current_id<=frame_id;
                    swap_ack<=frame_swap;
                end else settle<=settle+1'b1;
            end
            if(start_now) active<=1;
            if(pop) begin
                if(rcount<fifo_min) fifo_min<=rcount;
                if(rcount>fifo_max) fifo_max<=rcount;
                if(empty) begin underflows<=underflows+1'b1; rgb<=24'hff00ff; end
                else begin rgb<=pixel[23:0]; crc<=next_crc; words<=words+1'b1; end
            end
            if(x==WIDTH-1 && y==HEIGHT-1 && active) begin
                if(swap_p2!=swap_ack) begin
                    wait_commit<=0;
                    frame_base<=display_base; frame_id<=display_id; frame_crc<=expected_crc; frame_swap<=swap_p2;
                end
                if(frame_wipe && frame_complete) begin
                    if(step<32) begin
                        step<=step+1'b1;
                        if(frame_mode!=2)frame_bound<=frame_bound+(frame_mode==1 ? HEIGHT/32 : WIDTH/32);
                    end else begin
                        commit_toggle<=~commit_toggle;frame_wipe<=0;wait_commit<=1;
                        frame_base<=frame_new_base;frame_crc<=frame_new_crc;
                        // Change ID with the final player swap bundle.
                    end
                end else if(!frame_wipe && !wait_commit && pending_p2 && effect_mode<3 && swap_p2==swap_ack) begin
                    frame_new_base<=target_base;frame_new_crc<=target_crc;frame_new_id<=target_id;
                    frame_mode<=effect_mode;frame_bound<=0;step<=0;frame_wipe<=1;
                end
                last_crc<=next_crc^32'hffffffff; frames<=frames+1'b1;
                if(current_id!=last_id) commits<=commits+1'b1;
                last_id<=current_id;
                if(!read_fault_p2 && !empty && words==WORDS-1) begin
                    if(frame_wipe && step!=0 && step!=32) mixed_frames<=mixed_frames+1'b1;
                    else if((next_crc^32'hffffffff)==current_crc) good_frames<=good_frames+1'b1;
                    else bad_frames<=bad_frames+1'b1;
                end else bad_frames<=bad_frames+1'b1;
                crc<=32'hffffffff; words<=0; active<=0; have_image<=0;
                frame_epoch<=~frame_epoch; rflush<=1; settle<=0;
            end
        end
    end
endmodule
