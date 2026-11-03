`timescale 1ns/1ps
module image_media(
 input wire sys_clk,sys_rst_n,
 input wire load_req_valid,load_req_write,input wire [20:0] load_req_addr,input wire [31:0] load_req_data,
 output wire load_req_ready,load_rsp_valid,output wire [31:0] load_rsp_data,output wire load_rsp_error,output reg memory_ready,
 input wire display_enable,input wire [20:0] display_base,input wire [31:0] display_id,display_crc,input wire display_swap,waiting,
 output wire video_committed,output wire HDMI_CLK_P,HDMI_D2_P,HDMI_D1_P,HDMI_D0_P,output wire [255:0] video_stats,
 output wire audio_mclk,input wire audio_bclk,audio_lrck,audio_data,output wire HDMI_DDC_SCL,inout wire HDMI_DDC_SDA,output wire [255:0] audio_stats,
 input wire swap_pending,input wire [1:0] effect,input wire [20:0] target_base,input wire [31:0] target_id,target_crc,
 output wire transition_commit,transition_idle,output wire [7:0] transition_status,input wire [3:0] switches,input wire [2:0] brightness,contrast,input wire panel,input wire [3:0] page,
 input wire [13:0] end_record,output wire [255:0] fx_stats,input wire remote_mute,remote_pause,input wire [7:0] auto_status,output wire [63:0] subtitle_stats,
 input wire [2:0] menu,input wire [1:0] notice_kind,selected_effect,input wire ui_fault,ui_hide,input wire [111:0] display_record,input wire [127:0] ui_view,input wire atlas_ready,output wire layer_fault_status,
 output wire layer_running_status,output wire [7:0] layer_missed_status
);
 localparam IMAGE_WORDS=307200;
 wire tf_clk=sys_clk,tf_reset_n=sys_rst_n,f_clk=sys_clk;
 wire mem_ready;wire [3:0] load_req_dm=0;
 wire c1_req_valid,c1_req_write,c1_req_ready,c1_rsp_valid,c1_rsp_error,c1_rsp_ready;
 wire [20:0] c1_req_addr;wire [31:0] c1_req_data,c1_rsp_data;wire [3:0] c1_req_dm;
 assign c1_req_valid=0;assign c1_req_write=0;assign c1_rsp_ready=1;
 assign c1_req_addr=0;assign c1_req_data=0;assign c1_req_dm=0;
 wire video_mem_clk,video_mem_reset_n,video_req,video_req_ready,video_valid,video_done,video_error;
 wire [20:0] video_addr;wire [31:0] video_data,mem_service_count,mem_service_errors;
 wire [31:0] probe_stream_data;wire [20:0] probe_stream_addr;wire probe_stream_valid;
 wire wipe_busy,wipe_commit;wire [1:0] reader_phase;wire [5:0] reader_step;wire [31:0] video_mixed;
 wire video_swap_ack;
 wire layer_req,layer_req_ready,layer_valid,layer_done,layer_error,layer_mode;
 wire [20:0] layer_addr;wire [31:0] layer_data;
    media_memory #(.VIDEO_WORDS(IMAGE_WORDS)) memory(
        .sys_clk(sys_clk), .sys_rst_n(sys_rst_n),
        .c0_clk(tf_clk), .c0_req_valid(load_req_valid), .c0_req_write(load_req_write),
        .c0_req_addr(load_req_addr), .c0_req_data(load_req_data), .c0_req_dm(load_req_dm),
        .c0_req_ready(load_req_ready), .c0_rsp_valid(load_rsp_valid),
        .c0_rsp_data(load_rsp_data), .c0_rsp_error(load_rsp_error), .c0_rsp_ready(1'b1),
        .c1_clk(f_clk), .c1_req_valid(c1_req_valid), .c1_req_write(c1_req_write),
        .c1_req_addr(c1_req_addr), .c1_req_data(c1_req_data), .c1_req_dm(c1_req_dm),
        .c1_req_ready(c1_req_ready), .c1_rsp_valid(c1_rsp_valid), .c1_rsp_data(c1_rsp_data),
        .c1_rsp_error(c1_rsp_error), .c1_rsp_ready(c1_rsp_ready),
        .video_clk(video_mem_clk), .video_reset_n(video_mem_reset_n),
        .video_req(video_req), .video_addr(video_addr), .video_req_ready(video_req_ready),
        .video_valid(video_valid), .video_data(video_data), .video_done(video_done),
        .video_error(video_error), .memory_ready(mem_ready),
        .service_count(mem_service_count), .service_errors(mem_service_errors),
        .probe_stream_data(probe_stream_data),.probe_stream_addr(probe_stream_addr),.probe_stream_valid(probe_stream_valid),
        .layer_mode(layer_mode),.layer_req(layer_req),.layer_addr(layer_addr),.layer_req_ready(layer_req_ready),.layer_valid(layer_valid),.layer_data(layer_data),.layer_done(layer_done),.layer_error(layer_error));

    // Synchronize memory_ready from the SDRAM PLL domain into SYS. The request
    // and response buses use the mem_client toggle handshake and bundled-data limits.
    (* ASYNC_REG="TRUE" *) reg mem_ready_meta;
    always @(posedge tf_clk or negedge tf_reset_n) begin
        if (!tf_reset_n) begin
            mem_ready_meta <= 1'b0;
            memory_ready <= 1'b0;
        end else begin
            mem_ready_meta <= mem_ready;
            memory_ready <= mem_ready_meta;
        end
    end


    wire pixel_clk, serial_clk, video_locked, video_reset_n;
    video_pll video_clock(sys_clk, ~sys_rst_n, serial_clk, pixel_clk, video_locked);
    reset_sync video_reset(pixel_clk, sys_rst_n && video_locked && video_mem_reset_n, video_reset_n);
    wire hs, vs, de, video_active;
    wire [9:0] video_x, video_y;
    wire [31:0] video_active_id;
    wire [31:0] video_frames, video_good, video_bad, video_uf, video_crc, video_min, video_max, video_read_errors;
    wire [31:0] video_last_id, video_commits;
    wire [23:0] video_raw_rgb;
    wire observe_frame_wipe;wire [20:0] observe_new_base;
    wire motion_safe,layer_fault,layer_running;wire [7:0] layer_missed;
 cdc_snapshot #(.WIDTH(9)) layer_diag_snapshot(pixel_clk,video_reset_n,{layer_running,layer_missed},sys_clk,sys_rst_n,1'b1,{layer_running_status,layer_missed_status});
 layer_fault_cdc layer_fault_diag(sys_clk,sys_rst_n,layer_fault,layer_fault_status);(* ASYNC_REG="TRUE" *) reg safe_m1,safe_sys;
    always @(posedge sys_clk or negedge sys_rst_n)if(!sys_rst_n)begin safe_m1<=1;safe_sys<=1;end else begin safe_m1<=motion_safe;safe_sys<=safe_m1;end
    video_burst_reader reader(
        .ctrl_clk(sys_clk),.ctrl_rst_n(sys_rst_n),.wipe_pending(swap_pending && effect<3 && safe_sys),.effect_mode(effect),
        .target_base(target_base),.target_id(target_id),.target_crc(target_crc),
        .wipe_busy(wipe_busy),.wipe_commit(wipe_commit),.wipe_phase(reader_phase),.wipe_step(reader_step),.mixed_frames(video_mixed),
        .mclk(video_mem_clk), .mrst_n(video_mem_reset_n), .enable(display_enable),
        .display_base(display_base), .swap_toggle(display_swap), .swap_ack(video_swap_ack),
        .display_id(display_id), .last_id(video_last_id), .commits(video_commits),
        .request(video_req), .address(video_addr), .request_ready(video_req_ready),
        .data_valid(video_valid), .data(video_data), .burst_done(video_done), .burst_error(video_error),
        .pclk(pixel_clk), .prst_n(video_reset_n), .expected_crc(display_crc),
        .hs(hs), .vs(vs), .de(de), .rgb(video_raw_rgb), .pixel_x(video_x), .pixel_y(video_y),
        .active_id(video_active_id), .frames(video_frames), .good_frames(video_good),
        .bad_frames(video_bad), .underflows(video_uf), .last_crc(video_crc),
        .fifo_min(video_min), .fifo_max(video_max), .read_errors(video_read_errors), .active(video_active),
        .probe_stream_data(probe_stream_data),.probe_stream_addr(probe_stream_addr),.probe_stream_valid(probe_stream_valid),
        .observe_frame_wipe(observe_frame_wipe),.observe_new_base(observe_new_base));

 wire [111:0] record_snapshot;
 // Publish the mailbox in vertical blank and hold it during active video.
 wire [111:0] record_pixel=record_snapshot;
 cdc_snapshot #(.WIDTH(112)) geometry_snapshot(sys_clk,sys_rst_n,display_record,pixel_clk,video_reset_n,video_x==0 && video_y==480,record_snapshot);
 wire [174:0] settings_pending;reg [174:0] frame_settings;wire [46:0] settings=frame_settings[46:0];
 always @(posedge pixel_clk or negedge video_reset_n)if(!video_reset_n)frame_settings<=0;else if(video_x==0 && video_y==480)frame_settings<=settings_pending;
 cdc_snapshot #(.WIDTH(175)) settings_snapshot(sys_clk,sys_rst_n,{ui_view,ui_fault,ui_hide,remote_pause || auto_status[2],auto_status,notice_kind,menu,switches,selected_effect,end_record,page,panel,contrast,brightness},pixel_clk,video_reset_n,video_x==0 && video_y==480,settings_pending);
 wire [7:0] bright_value=settings[2:0]==0 ? 8'd128:settings[2:0]==1 ? 8'd192:settings[2:0]==3 ? 8'd253:settings[2:0]==4 ? 8'd254:8'd255;
 wire [7:0] contrast_value=settings[5:3]==0 ? 8'd64:settings[5:3]==1 ? 8'd96:settings[5:3]==3 ? 8'd160:settings[5:3]==4 ? 8'd192:8'd128;
 wire fx_hs,fx_vs,fx_de;wire [23:0] fx_rgb,fade_rgb;wire fade_commit,fade_busy;wire [1:0] fade_phase;
 wire [33:0] layer_context;wire layer_hs,layer_vs,layer_de,layer_active;wire [9:0] layer_x,layer_y;wire [23:0] layer_rgb;wire [31:0] layer_id;
 cdc_snapshot #(.WIDTH(34)) layer_snapshot(sys_clk,sys_rst_n,{swap_pending,atlas_ready && display_enable,display_id},pixel_clk,video_reset_n,video_x==0 && video_y==480,layer_context);
 layer_compositor layers(pixel_clk,video_reset_n,video_mem_clk,video_mem_reset_n,layer_context[32] && video_active_id==layer_context[31:0] && !observe_frame_wipe,layer_context[33],
 hs,vs,de,video_x,video_y,video_raw_rgb,video_active,video_active_id,layer_hs,layer_vs,layer_de,layer_x,layer_y,layer_rgb,layer_active,layer_id,
 layer_req,layer_addr,layer_req_ready,layer_valid,layer_data,layer_done,layer_error,motion_safe,layer_fault,layer_mode,frame_settings[156:155],layer_running,layer_missed);
 video_fx #(.FADE_FRAMES(0),.EXTERNAL_OSD(1),.PRESET_ONLY(1),.FRAME_AT_ACTIVE(1)) picture_fx(
 pixel_clk,video_reset_n,layer_hs,layer_vs,layer_de,layer_x,layer_y,layer_rgb,layer_id,bright_value,contrast_value,1'b0,display_enable,
 fx_hs,fx_vs,fx_de,fx_rgb,,,,);
 fade_transition fade(sys_clk,sys_rst_n,swap_pending && effect==3 && safe_sys,fade_commit,fade_busy,
 pixel_clk,video_reset_n,display_enable,layer_x==0 && layer_y==480,video_swap_ack,fx_rgb,fade_rgb,,,fade_phase);
 assign transition_commit=wipe_commit || fade_commit;
 assign transition_idle=!wipe_busy && !fade_busy && !swap_pending;
 assign transition_status={4'd0,swap_pending,fade_busy,wipe_busy,transition_idle};
 wire final_hs,final_vs,final_de;wire [23:0] final_rgb;reg [12:0] filter_display;wire [4:0] meter_level;wire [5:0] meter_end;
 wire [63:0] scroll_pixel;
 assign subtitle_stats=64'd0;
 a_osd osd(pixel_clk,video_reset_n,fx_hs,fx_vs,fx_de,layer_x,layer_y,fade_rgb,
 settings[33:31],settings[6],settings[35:34],settings[30:27],settings[10:7],settings[26:25],settings[2:0],settings[5:3],settings[24:11],filter_display,settings[43:36],settings[44] || layer_fault,settings[45],settings[46],final_hs,final_vs,final_de,final_rgb,scroll_pixel,record_pixel,frame_settings[174:47],meter_end);
 wire audio_locked,audio_reset_n,pcm_valid;wire [31:0] pcm_frame,pcm_frames,pcm_errors;
 PLL_HDMI_AUDIO audio_clock(sys_clk,!sys_rst_n,audio_locked,,,audio_mclk);
 reset_sync audio_reset(pixel_clk,sys_rst_n && video_locked && audio_locked,audio_reset_n);
 scene_i2s_rx audio_rx(pixel_clk,audio_reset_n,audio_bclk,audio_lrck,audio_data,pcm_valid,pcm_frame,pcm_frames,pcm_errors);
 wire [68:0] pcm_status;
 cdc_snapshot #(.WIDTH(69)) audio_snapshot(pixel_clk,audio_reset_n,
  {meter_level,pcm_frames,pcm_errors},sys_clk,sys_rst_n,1'b1,pcm_status);
 // Diagnostic P word 3 exposes the meter level in its low five bits.
 assign audio_stats={32'h031a0001,pcm_status[63:0],27'd0,pcm_status[68:64],128'd0};
 wire [7:0] audio_config;wire [1:0] page_song=page<=6 ? page-3:0;
 wire [7:0] audio_cfg_src={page>=3 && page<=9,page_song,remote_pause,remote_mute,1'b0,switches[3:2]};
 cdc_snapshot #(.WIDTH(8)) fx_configuration(sys_clk,sys_rst_n,audio_cfg_src,pixel_clk,audio_reset_n,1'b1,audio_config);
 wire fx_valid,fx_ready,fx_fault,fx_warm,metric_valid;wire signed [15:0] left_fx,right_fx;wire [1:0] active_mode,active_scene;
 wire [31:0] fx_epoch,fx_frames,fx_clips;
 audio_fx audio_fx(pixel_clk,audio_reset_n,pcm_valid,$signed(pcm_frame[15:0]),$signed(pcm_frame[31:16]),audio_config[1:0],audio_config[6:5],
 audio_config[4],audio_config[3],audio_config[7],fx_valid,left_fx,right_fx,active_mode,fx_epoch,fx_frames,fx_clips,fx_warm,metric_valid,fx_fault,active_scene,fx_ready);
 wire metrics_fault,filter_current,filter_commit;wire [12:0] filter_record;wire [15:0] metric_block;wire [31:0] power_pre,power_post;
 wire [15:0] left_public=fx_fault || metrics_fault || audio_config[3] || audio_config[4] || !audio_config[7] ? 16'd0:left_fx;
 wire [15:0] right_public=fx_fault || metrics_fault || audio_config[3] || audio_config[4] || !audio_config[7] ? 16'd0:right_fx;
 reg signed [15:0] pre_left;
 always @(posedge pixel_clk or negedge audio_reset_n)if(!audio_reset_n)pre_left<=0;else if(pcm_valid)pre_left<=pcm_frame[15:0];
 wire metric_eligible=!fx_fault && !metrics_fault && !audio_config[3] && !audio_config[4] && audio_config[7] && !fx_warm && active_mode==audio_config[1:0] && active_scene==audio_config[6:5];
 filter_metrics filter_metrics(pixel_clk,audio_reset_n,fx_valid,metric_valid,metric_eligible,pre_left,$signed(left_public),fx_epoch,fx_clips,
 {active_scene,active_mode},audio_config[3],audio_config[4],audio_config[7],fx_warm,metrics_fault,filter_record,filter_current,metric_block,power_pre,power_post,filter_commit);
 wire [12:0] stable_filter_record;wire [1:0] filter_confirmations;wire filter_pending;wire [15:0] filter_commits;
 wire [2:0] unavailable_filter_status=fx_fault || metrics_fault ? 3'd4:audio_config[3] || audio_config[4] ? 3'd6:!audio_config[7] ? 3'd7:3'd5;
 filter_display filter_view(pixel_clk,audio_reset_n,fx_epoch,{active_scene,active_mode},metric_eligible,unavailable_filter_status,
 filter_commit,filter_record,stable_filter_record,filter_confirmations,filter_pending,filter_commits);
 always @(posedge pixel_clk or negedge audio_reset_n)if(!audio_reset_n)filter_display<={3'd7,10'd0};else if(video_x==0 && video_y==480)filter_display<=stable_filter_record;
 // Meter input is audible HDMI PCM: zero on pause, mute, an inactive page or fault.
 audio_level_meter meter(pixel_clk,audio_reset_n,fx_valid,video_x==0 && video_y==480,left_public,right_public,meter_level,meter_end);
 assign fx_stats=256'd0;
 wire axis_user,axis_valid,axis_last,axis_ready,edid_trig,edid_valid;wire [23:0] axis_data;wire [7:0] edid_data;
 wire [9:0] ch0,ch1,ch2,chclk;wire acr_valid;wire [19:0] acr_cts,acr_n;
 video_rgb_to_axis_640x480 video_axis(pixel_clk,!video_reset_n,final_vs,final_de,final_rgb,axis_user,axis_valid,axis_last,axis_data);
 startup_pulse #(.CNT_MAX(20'd100000)) edid_start(pixel_clk,!video_reset_n,edid_trig);
 audio_arc_calculate #(.ACR_N(20'd6144)) acr(pixel_clk,!audio_reset_n,fx_valid,acr_valid,acr_cts,acr_n);
 hdmi_1_4b_transmitter_core_wrapper #(.DEVICE("EG"),.HTOTAL(800),.HSA(96),.HFP(16),.HBP(48),.HACTIVE(640),
 .VTOTAL(525),.VSA(2),.VFP(10),.VBP(33),.VACTIVE(480),.VIDEO_VIC(1),.VIDEO_TPG("Disable"),.VIDEO_FORMAT("RGB"),.AUDIO_SAMPLE_RATE("48K"),.IIC_SCL_DIV(250)) hdmi_audio_tx(
 .I_pixel_clk(pixel_clk),.I_rst(!video_reset_n),.I_edid_read_trig(edid_trig),.O_edid_read_valid(edid_valid),.O_edid_read_data(edid_data),
 .I_axis_s_user(axis_user),.I_axis_s_valid(axis_valid),.I_axis_s_last(axis_last),.I_axis_s_data(axis_data),.O_axis_s_ready(axis_ready),
 .I_audio_valid(fx_valid),.I_audio_left_data({left_public,8'd0}),.I_audio_right_data({right_public,8'd0}),
 .I_acr_valid(acr_valid),.I_acr_cts(acr_cts),.I_acr_n(acr_n),.O_video_locked(),.O_ddc_scl(HDMI_DDC_SCL),.IO_ddc_sda(HDMI_DDC_SDA),
 .O_ch0_tmds_data(ch0),.O_ch1_tmds_data(ch1),.O_ch2_tmds_data(ch2),.O_clk_tmds_data(chclk));
 hdmi_phy_wrapper #(.DEVICE("EG")) hdmi_phy(pixel_clk,serial_clk,!video_reset_n,ch0,ch1,ch2,chclk,HDMI_D0_P,HDMI_D1_P,HDMI_D2_P,HDMI_CLK_P);
 scene_video_observer observer(pixel_clk,video_reset_n,layer_de,layer_x,layer_y,layer_active,layer_id,
 sys_clk,sys_rst_n,waiting,display_id,video_committed);
 assign video_stats=256'd0;
endmodule
