`timescale 1ns/1ps
`include "card_layout.vh"
`include "scene_protocol.vh"
`include "ui_protocol.vh"
module scene_a_top(
 input wire sys_clk,sys_rst_n,uart_rx,output wire uart_tx,output wire [3:0] led,
 output wire [7:0] f_data,output wire f_clk,f_valid,input wire f_ready,
 input wire [7:0] r_data,input wire r_clk,r_valid,output wire r_ready,
 output wire HDMI_CLK_P,HDMI_D2_P,HDMI_D1_P,HDMI_D0_P,HDMI_DDC_SCL,inout wire HDMI_DDC_SDA,
 input wire key1,key2,key3,sw1,sw2,sw3,sw4,
 output wire audio_mclk,input wire audio_bclk,audio_lrck,audio_data
);
 wire rst_n;power_reset_seq startup(sys_clk,rst_n);reg [31:0] heartbeat;
 always @(posedge sys_clk)if(!rst_n)heartbeat<=0;else heartbeat<=heartbeat+1'b1;
 reg [15:0] ms_div;reg [31:0] now_ms;
 always @(posedge sys_clk)if(!rst_n)begin ms_div<=0;now_ms<=0;end else if(ms_div==49999)begin ms_div<=0;now_ms<=now_ms+1'b1;end else ms_div<=ms_div+1'b1;
 wire [7:0] command;wire command_valid;wire [7:0] query;
 wire [3:0] short_key,long_key,switches;wire input_activity,input_blocked;
 board_inputs #(.LONG_MASK(3)) inputs(sys_clk,rst_n,{key3,key2,key1,sys_rst_n},{sw4,sw3,sw2,sw1},short_key,long_key,switches,input_activity,input_blocked);
 wire demo_reset;
 wire auto_req,text_req;wire [1:0] filter_req;
 wire [3:0] display_switches={switches[3:2]!=0 ? switches[3:2]:filter_req,switches[1],switches[0] || auto_req};
 wire panel;wire [2:0] menu;wire [1:0] effect,notice_kind;wire [2:0] brightness,contrast;wire [26:0] notice;
 assign notice=0;assign notice_kind=0;
 wire [127:0] ui_view;wire [15:0] ui_generation,ui_probe_id;
 wire ui_online,ui_status_valid,ui_event,ui_send_ready,ui_action,ui_result_valid;wire [7:0] ui_event_id,ui_event_flags,ui_op,ui_value,ui_result,ui_result_op;
 wire [63:0] ui_event_body;wire [351:0] ui_status;wire [31:0] ui_last_action,ui_session;wire [7:0] ui_drops;
 wire rxvalid,txready,txdone;wire [7:0] rxtype,rxid,rxflags,rxdata;wire [31:0] rxepoch,rxoffset;wire [9:0] rxlength;
 wire [8:0] rxaddr;wire [31:0] packets,crc_errors,format_errors,packet_timeouts,tx_timeouts;
 // Keep the visible transaction independent of the held loader transaction.
 reg [31:0] epoch,load_epoch,load_size;reg [3:0] page,current_page,load_page;
 reg have_epoch,current_valid,busy,fault;reg [2:0] state;
 menu_control controls(.clk(sys_clk),.rst_n(rst_n),.ms_tick(ms_div==49999),.key_id(ui_event_id[4:0]),.key_flags(ui_event_flags[2:0]),.key_valid(ui_event && (ui_event_id<17 || ui_event_id==20) && (ui_event_flags==1 || ui_event_flags==2 || ui_event_flags==4)),
 .short_key(short_key),.long_key(long_key),.switches(switches),.command(command),.command_valid(command_valid),.demo_prepare(demo_reset),
 .online(ui_online),.status_valid(ui_status_valid),.status(ui_status),.current_page(current_page),.current_valid(current_valid),.local_busy(busy),.local_fault(fault),
 .brightness(brightness),.contrast(contrast),.effect(effect),.auto_req(auto_req),.text_req(text_req),.filter_req(filter_req),.panel(panel),.menu(menu),
 .action_valid(ui_action),.action_ready(ui_send_ready),.action_op(ui_op),.action_value(ui_value),.result_valid(ui_result_valid),.result(ui_result),.view(ui_view),.generation(ui_generation),.result_op(ui_result_op),.probe_id(ui_probe_id));
 localparam IDLE=0,WAIT_CACHE=2,DISPLAY=3,WAIT_DISPLAY=4,FAILED=5;
 reg [1:0] load_state,load_slot,current_slot,previous_slot,display_slot;
 reg [3:0] slot_valid;reg [3:0] tag0,tag1,tag2,tag3;reg [31:0] crc0,crc1,crc2,crc3;reg previous_valid;
 reg [31:0] display_base_crc,display_id;reg [20:0] display_base;reg display_swap;
 reg begin_file,abort_load,loader_start;wire loader_rst_n=rst_n && !abort_load;
 reg [31:0] applied,failures,timer;reg [7:0] error_code;
 wire packet_ready,reply_valid,reply_retry,can_request,stream_valid,stream_ready,stream_last,file_done;
 wire [31:0] reply_offset,next_offset,source_crc,published,duplicates,rejections,stales;wire [7:0] stream_data;
 reg tx_active;reg [2:0] tx_owner;reg request_sent;reg [31:0] request_offset,request_timer;
 reg result_pending,result_error,pref_result_pending;reg [31:0] pref_result_epoch;reg [3:0] pref_result_page;
 reg [22:0] auto_timer;reg auto_pending,auto_old,menu_old;reg [7:0] auto_status;
 wire voice_reply,voice_reply_take;wire [31:0] voice_control;wire [7:0] voice_flags;wire [255:0] voice_stats;
 wire remote_mute,remote_pause,voice_rx_ready;wire [8:0] voice_rx_addr;wire end_known;wire [31:0] end_start;
 reg [2:0] end_status;reg [31:0] end_elapsed,end_epoch,retained_end;reg end_tracking,retained_known;
 wire observed,transition_commit,transition_idle;wire [7:0] transition_status;wire [255:0] video_stats,audio_stats,fx_stats;
 reg swap_pending;reg [20:0] transition_base;reg [31:0] transition_id,transition_crc;reg [1:0] active_effect;
 wire accept_offer=offer && (!have_epoch || rxepoch!=epoch) && (state==IDLE || state==FAILED) && transition_idle && memory_ready && !tx_active && !result_pending;
 wire offer=rxvalid && rxtype==8'he0 && rxid<10;
 assign demo_reset=accept_offer && rxid==0 && rxflags[6] && rxoffset==offered_size;
 wire prefetch_offer=rxvalid && rxtype==8'he1 && rxid<10 && have_epoch && rxepoch==epoch;
 wire [31:0] offered_size=`CARD_SIZES >> (rxid[3:0]*32);
 wire [31:0] expected_crc=`CARD_CRCS >> (load_page*32);
 wire cache_hit=(slot_valid[0] && tag0==page)||(slot_valid[1] && tag1==page)||(slot_valid[2] && tag2==page)||(slot_valid[3] && tag3==page);
 wire [1:0] hit_slot=slot_valid[0] && tag0==page ? 0:slot_valid[1] && tag1==page ? 1:slot_valid[2] && tag2==page ? 2:3;
 wire offered_hit=(slot_valid[0] && tag0==rxid[3:0])||(slot_valid[1] && tag1==rxid[3:0])||(slot_valid[2] && tag2==rxid[3:0])||(slot_valid[3] && tag3==rxid[3:0]);
 // E1 flag 0 selects lookahead direction. Preserve the nearer prefetched frame
 // while filling the second; displayed and previous frames keep their slots.
 wire [3:0] near_page=rxflags[0] ? (current_page==0 ? 4'd9:current_page-1'b1):(current_page==9 ? 4'd0:current_page+1'b1);
 wire protect_near=prefetch_offer && state==IDLE && rxid[3:0]!=near_page;
 wire [3:0] slot_protected={
  (current_valid && current_slot==3)||(previous_valid && previous_slot==3)||(protect_near && slot_valid[3] && tag3==near_page),
  (current_valid && current_slot==2)||(previous_valid && previous_slot==2)||(protect_near && slot_valid[2] && tag2==near_page),
  (current_valid && current_slot==1)||(previous_valid && previous_slot==1)||(protect_near && slot_valid[1] && tag1==near_page),
  (current_valid && current_slot==0)||(previous_valid && previous_slot==0)||(protect_near && slot_valid[0] && tag0==near_page)};
 reg [1:0] free_slot;
 always @*begin
  if(!slot_valid[0] && !slot_protected[0])free_slot=0;
  else if(!slot_valid[1] && !slot_protected[1])free_slot=1;
  else if(!slot_valid[2] && !slot_protected[2])free_slot=2;
  else if(!slot_valid[3] && !slot_protected[3])free_slot=3;
  else if(!slot_protected[0])free_slot=0;
  else if(!slot_protected[1])free_slot=1;
  else if(!slot_protected[2])free_slot=2;
  else free_slot=3;
 end
 function [20:0] base;input [1:0] slot;begin base=slot==0 ? 614400:slot==1 ? 921600:slot==2 ? 1228800:1536000;end endfunction
 function [31:0] saved_crc;input [1:0] slot;begin saved_crc=slot==0 ? crc0:slot==1 ? crc1:slot==2 ? crc2:crc3;end endfunction
 voice_rx voice(sys_clk,rst_n,fault,epoch,rxvalid,rxtype,rxflags,rxepoch,rxoffset,rxlength,voice_rx_ready,voice_rx_addr,rxdata,
 voice_reply,voice_control,voice_reply_take,voice_flags,voice_stats,end_known,end_start,now_ms,remote_mute,remote_pause);
 wire ui_txvalid,ui_txready,ui_txdone,ui_rxready;wire [7:0] ui_txtype,ui_txid,ui_txflags,ui_txdata;wire [31:0] ui_txepoch,ui_txoffset;wire [9:0] ui_txlength;wire [8:0] ui_rxaddr,tx_payload_addr;
 wire ui_packet=rxtype>=`UI_KEY && rxtype<=`UI_SYNC;
 ui_link #(.HOST(1)) ui_link(.clk(sys_clk),.rst_n(rst_n),.ms_tick(ms_div==49999),.uptime(now_ms),
 .rx_valid(rxvalid && ui_packet),.rx_type(rxtype),.rx_id(rxid),.rx_flags(rxflags),.rx_epoch(rxepoch),.rx_offset(rxoffset),.rx_length(rxlength),.rx_ready(ui_rxready),.rx_addr(ui_rxaddr),.rx_data(rxdata),
 .tx_valid(ui_txvalid),.tx_ready(ui_txready),.tx_done(ui_txdone),.tx_type(ui_txtype),.tx_id(ui_txid),.tx_flags(ui_txflags),.tx_epoch(ui_txepoch),.tx_offset(ui_txoffset),.tx_length(ui_txlength),.tx_addr(tx_payload_addr),.tx_data(ui_txdata),
 .send_valid(ui_action),.send_ready(ui_send_ready),.send_id(8'd0),.send_flags(8'd0),.send_body({`UI_VERSION,ui_op,ui_value,24'd0,ui_op==`UI_PROBE ? ui_probe_id:ui_generation}),
 .event_valid(ui_event),.event_ready(1'b1),.event_result((ui_event_id>=17 && ui_event_id!=20) || (ui_event_flags!=1 && ui_event_flags!=2 && ui_event_flags!=4) ? `UI_BAD:(|short_key) || (|long_key) || command_valid ? `UI_BUSY:`UI_OK),.event_id(ui_event_id),.event_flags(ui_event_flags),.event_body(ui_event_body),
 .status_in(352'd0),.status_out(ui_status),.status_valid(ui_status_valid),.online(ui_online),.result(ui_result),.result_valid(ui_result_valid),.last_action(ui_last_action),.drops(ui_drops),.session_out(ui_session),.result_op(ui_result_op));
 wire tx_reply=reply_valid;
 wire tx_result=!tx_reply && result_pending;
 wire tx_voice=!tx_reply && !tx_result && voice_reply;
 wire tx_pref=!tx_reply && !tx_result && !tx_voice && pref_result_pending;
 reg ui_turn;
 wire image_req_wait=load_state==3 && can_request && (!request_sent || request_offset!=next_offset || request_timer>=4999999);
 wire tx_request=!tx_ui && !tx_reply && !tx_result && !tx_voice && !tx_pref && image_req_wait;
 wire tx_ui=!tx_reply && !tx_result && !tx_voice && !tx_pref && ui_txvalid && (!image_req_wait || ui_turn);
 always @(posedge sys_clk or negedge rst_n)if(!rst_n)ui_turn<=1;else if(txvalid && txready && (tx_ui || tx_request))ui_turn<=!tx_ui;
 wire tx_auto=!tx_ui && !tx_reply && !tx_result && !tx_voice && !tx_pref && !tx_request && auto_pending;
 wire txvalid=!tx_active && (tx_reply || tx_result || tx_voice || tx_pref || tx_request || tx_auto || tx_ui);
 wire [7:0] txtype=tx_ui ? ui_txtype:tx_reply ? (reply_retry ? `SCENE_IMAGE_RETRY:`SCENE_IMAGE_ACK):tx_result ? (result_error ? 8'he4:8'he2):tx_voice ? 8'hea:tx_pref ? 8'he3:tx_request ? `SCENE_IMAGE_REQ:8'he7;
 wire [31:0] txoffset=tx_ui ? ui_txoffset:tx_reply ? reply_offset:tx_result ? display_id:tx_voice ? voice_control:tx_request ? next_offset:0;
 wire [31:0] txepoch=tx_ui ? ui_txepoch:tx_reply || tx_request ? load_epoch:tx_pref ? pref_result_epoch:epoch;
 wire [7:0] txfile=tx_ui ? ui_txid:{4'd0,tx_reply || tx_request ? load_page:tx_pref ? pref_result_page:page};
 wire [7:0] txflags=tx_ui ? ui_txflags:tx_result ? error_code:tx_voice ? voice_flags:tx_auto ? {2'd0,display_switches,panel,display_switches[0]}:0;
 assign ui_txready=txready && !tx_active && tx_ui;assign ui_txdone=txdone && tx_owner==6;
 assign voice_reply_take=txdone && tx_owner==0;
 scene_link link(sys_clk,rst_n,r_data,r_clk,r_valid,r_ready,f_data,f_clk,f_valid,f_ready,
 txvalid,txready,txdone,txtype,txfile,txflags,txepoch,txoffset,tx_ui ? ui_txlength:10'd0,tx_payload_addr,ui_txdata,
 rxvalid,rxtype==`SCENE_IMAGE_DATA ? packet_ready:rxtype==8'he9 ? voice_rx_ready:ui_packet ? ui_rxready:1'b1,rxtype,rxid,rxflags,rxepoch,rxoffset,rxlength,
 rxtype==8'he9 ? voice_rx_addr:ui_packet ? ui_rxaddr:rxaddr,rxdata,packets,crc_errors,format_errors,packet_timeouts,tx_timeouts);
 scene_image_buffer buffer(sys_clk,loader_rst_n,begin_file,load_epoch,load_size,{4'd0,load_page},
 rxvalid && rxtype==`SCENE_IMAGE_DATA,packet_ready,rxepoch,rxoffset,rxid,rxlength,rxaddr,rxdata,
 reply_valid,txvalid && txready && tx_reply,reply_retry,reply_offset,can_request,next_offset,
 stream_valid,stream_ready,stream_data,stream_last,file_done,source_crc,published,duplicates,rejections,stales);
 wire memory_ready,req_valid,req_write,req_ready,rsp_valid,rsp_error;wire [20:0] req_addr;wire [31:0] req_data,rsp_data;
 wire image_ready,image_fault,ingest_busy;wire [3:0] trusted;wire [31:0] qualified_crc;wire [127:0] source_crcs,geometries;
 wire [69:0] qualified_geometry;reg [279:0] slot_geometries;wire [7:0] ingest_error;wire [31:0] words_written,max_wait;wire [351:0] header_diagnostics;
 wire atlas_published,layer_fault_status,layer_running_status;wire [7:0] layer_missed_status;reg atlas_ready;
 always @(posedge sys_clk or negedge rst_n)if(!rst_n)atlas_ready<=0;else if(loader_start && load_page==3)atlas_ready<=0;else if(atlas_published)atlas_ready<=1;
 layered_image_ingest ingest(sys_clk,loader_rst_n,memory_ready,loader_start,load_slot,load_size,
 stream_valid,stream_data,stream_ready,file_done,source_crc,ingest_busy,image_ready,trusted,qualified_crc,source_crcs,geometries,
 image_fault,ingest_error,req_valid,req_write,req_addr,req_data,req_ready,rsp_valid,rsp_data,rsp_error,words_written,max_wait,header_diagnostics,qualified_geometry,load_page==3,atlas_published);
 wire [63:0] subtitle_stats;
 reg [69:0] visible_geometry;
 wire [95:0] geometry_bcd;wire geometry_bcd_ready;
 geometry_display geometry_view(sys_clk,rst_n,current_valid,visible_geometry,geometry_bcd,geometry_bcd_ready);
 wire [2:0] load_phase=!have_epoch ? 3'd1:fault ? 3'd6:!busy ? 3'd0:state==DISPLAY || state==WAIT_DISPLAY ? 3'd5:
  load_state!=3 || load_page!=page || load_epoch!=epoch ? 3'd2:file_done ? 3'd4:3'd3;
 wire [3:0] load_segments;
 load_progress load_progress(sys_clk,rst_n,load_phase==3,epoch,next_offset,load_size,load_segments);
 wire [111:0] display_record={geometry_bcd_ready,geometry_bcd,current_page,page,load_phase,(load_phase==4 || load_phase==5 ? 4'd8:load_phase==3 ? load_segments:4'd0)};

 image_media media(sys_clk,rst_n,req_valid,req_write,req_addr,req_data,req_ready,rsp_valid,rsp_data,rsp_error,memory_ready,
 current_valid || state==WAIT_DISPLAY,display_base,display_id,display_base_crc,display_swap,state==WAIT_DISPLAY,observed,
 HDMI_CLK_P,HDMI_D2_P,HDMI_D1_P,HDMI_D0_P,video_stats,audio_mclk,audio_bclk,audio_lrck,audio_data,HDMI_DDC_SCL,HDMI_DDC_SDA,audio_stats,
 swap_pending,active_effect,transition_base,transition_id,transition_crc,transition_commit,transition_idle,transition_status,
 display_switches,brightness,contrast,notice!=0,current_page,{end_status,end_elapsed[10:0]},fx_stats,remote_mute,remote_pause,auto_status,subtitle_stats,menu,notice_kind,effect,fault,busy || !transition_idle,display_record,ui_view,
 atlas_ready && ((display_base==614400 && slot_valid[0] && tag0==3)||(display_base==921600 && slot_valid[1] && tag1==3)||(display_base==1228800 && slot_valid[2] && tag2==3)||(display_base==1536000 && slot_valid[3] && tag3==3)),layer_fault_status,layer_running_status,layer_missed_status);
 task fail;input [7:0] code;
  begin error_code<=code;fault<=1;busy<=0;failures<=failures+1'b1;result_error<=1;result_pending<=1;abort_load<=1;state<=FAILED;load_state<=0;end
 endtask
 task start_load;input [3:0] id;input [31:0] ticket,bytes;
  begin
   if(id==3 && current_valid && current_page==3)fail(8'hc9);
   else begin load_page<=id;load_epoch<=ticket;load_size<=bytes;load_slot<=free_slot;slot_valid[free_slot]<=0;
    load_state<=1;request_sent<=0;end
  end
 endtask
 always @(posedge sys_clk or negedge rst_n)begin
  if(!rst_n)begin
   epoch<=0;load_epoch<=0;load_size<=0;page<=0;current_page<=0;load_page<=0;have_epoch<=0;current_valid<=0;busy<=0;fault<=0;
   load_state<=0;load_slot<=0;current_slot<=0;previous_slot<=0;previous_valid<=0;display_slot<=0;slot_valid<=0;tag0<=0;tag1<=0;tag2<=0;tag3<=0;crc0<=0;crc1<=0;crc2<=0;crc3<=0;
   display_base_crc<=0;display_base<=614400;display_id<=0;display_swap<=0;begin_file<=0;abort_load<=0;loader_start<=0;state<=IDLE;
   applied<=0;failures<=0;timer<=0;error_code<=0;
   tx_active<=0;tx_owner<=0;request_sent<=0;request_offset<=0;request_timer<=0;result_pending<=0;result_error<=0;
   pref_result_pending<=0;pref_result_epoch<=0;pref_result_page<=0;swap_pending<=0;transition_base<=614400;transition_id<=0;transition_crc<=0;active_effect<=2;
   auto_timer<=0;auto_pending<=1;auto_old<=0;menu_old<=0;auto_status<=0;visible_geometry<=0;slot_geometries<=0;
  end else begin
   begin_file<=0;abort_load<=0;loader_start<=0;auto_old<=display_switches[0];menu_old<=panel;
   if(auto_timer==4999999)begin auto_timer<=0;auto_pending<=1;end else auto_timer<=auto_timer+1'b1;
   if(auto_old!=display_switches[0] || menu_old!=panel)auto_pending<=1;
   if(rxvalid && rxtype==8'he6)auto_status<=rxflags;
   if(swap_pending && transition_commit)begin display_base<=transition_base;display_base_crc<=transition_crc;display_id<=transition_id;display_swap<=!display_swap;swap_pending<=0;end
   if(txvalid && txready)begin
    tx_active<=1;tx_owner<=tx_ui ? 6:tx_reply ? 1:tx_result ? 2:tx_voice ? 0:tx_pref ? 4:tx_auto ? 5:3;
    if(tx_result)result_pending<=0;if(tx_pref)pref_result_pending<=0;if(tx_auto)auto_pending<=0;
    if(tx_request)begin request_sent<=1;request_offset<=next_offset;request_timer<=0;end
   end else if(request_timer<5000000)request_timer<=request_timer+1'b1;
   if(txdone)begin tx_active<=0;tx_owner<=0;end
   // Show progress for the held prefetch while the new target waits.
   if(busy)begin if(stream_valid && stream_ready)timer<=0;else timer<=timer+1'b1;end
   if(accept_offer)begin
    epoch<=rxepoch;have_epoch<=1;page<=rxid[3:0];fault<=0;error_code<=0;busy<=1;timer<=0;state<=WAIT_CACHE;
    if(rxoffset!=offered_size)begin error_code<=8'h81;fault<=1;busy<=0;result_error<=1;result_pending<=1;state<=FAILED;end

   end
   if(offer && have_epoch && rxepoch==epoch && rxid=={4'd0,page} && current_valid && state==IDLE && !tx_active)begin result_error<=0;result_pending<=1;end
   if(prefetch_offer && state==IDLE && transition_idle && load_state==0 && !pref_result_pending && !reply_valid && !tx_active && !offer && !fault && memory_ready && rxoffset==offered_size)begin
    if(offered_hit)begin pref_result_pending<=1;pref_result_epoch<=rxepoch;pref_result_page<=rxid[3:0];end
    else begin start_load(rxid[3:0],rxepoch,rxoffset);end
   end
   case(load_state)
    1:begin begin_file<=1;loader_start<=1;load_state<=2;end
    2:load_state<=3;
    3:if(image_fault)fail(ingest_error);else if(image_ready)begin
     if(source_crc!=expected_crc)fail(8'h82);
     else begin
      slot_valid[load_slot]<=1;
      // Publish metadata with the qualified cache tag/CRC. Loader abort clears
      // its working record while cached records remain valid.
      slot_geometries[load_slot*70+:70]<=qualified_geometry;
      case(load_slot)0:begin tag0<=load_page;crc0<=qualified_crc;end
       1:begin tag1<=load_page;crc1<=qualified_crc;end
       2:begin tag2<=load_page;crc2<=qualified_crc;end
       default:begin tag3<=load_page;crc3<=qualified_crc;end endcase
      load_state<=0;pref_result_pending<=1;pref_result_epoch<=load_epoch;pref_result_page<=load_page;
     end
    end
   endcase
   if(!fault && !(load_state==3 && (image_fault || (image_ready && source_crc!=expected_crc))))case(state)
    WAIT_CACHE:if(cache_hit)begin display_slot<=hit_slot;state<=DISPLAY;end
     else if(load_state==0 && !pref_result_pending && !reply_valid && !tx_active)start_load(page,epoch,`CARD_SIZES >> (page*32));
    DISPLAY:begin
     transition_base<=base(display_slot);transition_id<=epoch;transition_crc<=saved_crc(display_slot);active_effect<=effect;
     if(!current_valid)begin display_base<=base(display_slot);display_base_crc<=saved_crc(display_slot);display_id<=epoch;display_swap<=!display_swap;end
     else swap_pending<=1;state<=WAIT_DISPLAY;
    end
    WAIT_DISPLAY:if(observed)begin visible_geometry<=slot_geometries[display_slot*70+:70];current_page<=page;if(current_valid && current_slot!=display_slot)begin previous_slot<=current_slot;previous_valid<=1;end current_slot<=display_slot;current_valid<=1;busy<=0;applied<=applied+1'b1;result_error<=0;result_pending<=1;state<=IDLE;end
   endcase
   if(busy && timer>=1500000000)fail(8'h83);
  end
 end
 always @(posedge sys_clk or negedge rst_n)begin
  if(!rst_n)begin end_status<=0;end_elapsed<=0;end_epoch<=0;end_tracking<=0;retained_end<=0;retained_known<=0;end
  else begin
   if(voice_reply_take && voice_flags[2] && voice_flags[1:0]==1 && end_known)begin retained_end<=end_start;retained_known<=1;end
   if(accept_offer)begin
    if(rxflags[7] && retained_known)begin end_epoch<=rxepoch;end_tracking<=1;end_status<=2;retained_known<=0;end
    else if(end_tracking)begin end_tracking<=0;end_status<=4;end
   end
   if(end_tracking && observed && epoch==end_epoch)begin end_elapsed<=now_ms-retained_end;end_tracking<=0;end_status<=now_ms-retained_end<=2047 ? 3'd3:3'd7;end
   if(fault && end_tracking)begin end_tracking<=0;end_status<=4;end
  end
 end
 reg [3:0] led_q;always @(posedge sys_clk)if(!rst_n)led_q<=0;else led_q<={fault,busy,current_valid,heartbeat[25]};
 wire [1024:0] native_donors;assign native_donors[0]=led_q[0];genvar nd;
 generate for(nd=0;nd<1024;nd=nd+1)begin:g_native_hold
  (* keep="true" *) AL_MAP_LUT1 #(.EQN("(A)"),.INIT(2'b10)) u_buf(.a(native_donors[nd]),.o(native_donors[nd+1]));
 end endgenerate
 assign led={led_q[3:1],native_donors[1024]};
 wire [31:0] status={error_code,5'd0,slot_valid,load_slot,current_slot,state,current_valid,busy,fault,memory_ready,current_page};
 wire [127:0] release_q={epoch,status,crc_errors,failures};
 // A does not consume query I; debug_select treats it as unsupported.
 wire [127:0] release_i=128'd0;
 wire [127:0] release_p=audio_stats[255:128];
 wire [127:0] release_s={{ui_view[58:51],ui_view[66:59],ui_view[50:47],ui_view[46:43],auto_status},{28'd0,display_switches},{4'd0,ui_online,ui_status_valid,ui_view[17:0],menu,panel,notice_kind,effect},{16'd0,layer_missed_status,layer_running_status,layer_fault_status,brightness,contrast}};
 wire [127:0] stats;
 debug_select #(.LAST_QUERY("S"),.HAS_I(0)) debug_select(sys_clk,rst_n,command,command_valid,release_q,release_i,release_p,release_s,query,stats);
 scene_uart #(.BOARD(8'h41)) diagnostics(sys_clk,rst_n,uart_rx,uart_tx,stats,query,command,command_valid);
endmodule
