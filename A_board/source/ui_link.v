`timescale 1ns/1ps
`include "ui_protocol.vh"
// Retain active and pending events until acknowledged. scene_packet_tx holds
// the accepted header; session challenges belong to the host. Uptime runs
// continuously across protocol reconnects.
module ui_link #(parameter HOST=1)(
 input wire clk,rst_n,ms_tick,input wire [31:0] uptime,
 input wire rx_valid,input wire [7:0] rx_type,rx_id,rx_flags,input wire [31:0] rx_epoch,rx_offset,
 input wire [9:0] rx_length,output wire rx_ready,output wire [8:0] rx_addr,input wire [7:0] rx_data,
 output wire tx_valid,input wire tx_ready,tx_done,output reg [7:0] tx_type,tx_id,tx_flags,
 output reg [31:0] tx_epoch,tx_offset,output reg [9:0] tx_length,input wire [8:0] tx_addr,output wire [7:0] tx_data,
 input wire send_valid,output wire send_ready,input wire [7:0] send_id,send_flags,input wire [63:0] send_body,
 output reg event_valid,input wire event_ready,input wire [7:0] event_result,
 output wire [7:0] event_id,event_flags,output wire [63:0] event_body,
 input wire [351:0] status_in,output reg [351:0] status_out,output reg status_valid,
 output reg online,output reg [7:0] result,output reg result_valid,output reg [31:0] last_action,
 output reg [7:0] drops,output wire [31:0] session_out,output wire [7:0] result_op);
 reg [31:0] session,challenge,peer_challenge;assign session_out=session;
 // Hold the active body through ACK. Let the consumer sample result_valid
 // before the queued body replaces it on the following clock.
 assign result_op=HOST ? out_body[55:48] : 8'd0;
 reg [2:0] sync_state;reg [9:0] sync_age,alive_age;reg [6:0] status_age;
 reg sync_pending,ack_pending,status_pending,tx_busy;
 reg [7:0] ack_id,ack_result;reg [31:0] ack_seq;
 reg occupied,queued;reg [7:0] out_id,out_flags,queue_id,queue_flags;
 reg [63:0] out_body,queue_body;reg [31:0] out_seq,next_seq;reg [7:0] retry_age;reg [1:0] attempts;
 reg seen;reg [31:0] accepted_seq;reg [7:0] accepted_result;
 reg [351:0] tx_body,rx_body;reg [5:0] read_count;reg [1:0] read_phase;reg retire;
 // scene_packet_rx holds header and payload through event_ready. Read the
 // action body from that held packet; a separate 94-bit header copy is unnecessary.
 wire [7:0] captured_type=rx_type,captured_id=rx_id,captured_flags=rx_flags;
 wire [31:0] captured_epoch=rx_epoch,captured_offset=rx_offset;wire [9:0] captured_length=rx_length;
 assign event_id=captured_id;assign event_flags=captured_flags;assign event_body=rx_body[351:288];
 wire ui=rx_type>=`UI_KEY && rx_type<=`UI_SYNC;
 assign rx_ready=!ui || retire;
 assign rx_addr={3'd0,read_count};
 assign send_ready=online && !queued;
 wire want_sync=sync_pending;
 wire want_ack=!want_sync && ack_pending && online;
 wire want_out=!want_sync && !want_ack && occupied && online && (attempts==0 || retry_age==200 && attempts<3);
 wire want_status=!want_sync && !want_ack && !want_out && status_pending && online && !HOST;
 assign tx_valid=!tx_busy && (want_sync || want_ack || want_out || want_status);
 // scene_packet_tx captures header and payload together on tx_ready,
 // then holds both through tx_done.
 always @*begin
  tx_type=0;tx_id=0;tx_flags=0;tx_epoch=session;tx_offset=0;tx_length=0;
  if(want_sync)begin
   tx_type=`UI_SYNC;tx_id=`UI_VERSION;tx_flags=HOST ? (sync_state==3 ? 3:1):(online ? 4:2);
   tx_epoch=HOST ? (sync_state==3 ? session:challenge):(online ? session:challenge);tx_offset=peer_challenge;
  end else if(want_ack)begin tx_type=`UI_ACK;tx_id=ack_id;tx_flags=ack_result;tx_offset=ack_seq;end
  else if(want_out)begin tx_type=HOST ? `UI_ACTION:`UI_KEY;tx_id=out_id;tx_flags=out_flags;tx_offset=out_seq;tx_length=HOST ? 8:0;end
  else if(want_status)begin tx_type=`UI_STATUS;tx_length=44;end
 end
 assign tx_data=tx_addr<44 ? tx_body[351-tx_addr*8-:8]:8'd0;
 wire newer=$signed(captured_offset-accepted_seq)>0;
 wire expected=captured_type==(HOST ? `UI_KEY:`UI_ACTION);
 wire [31:0] mixed=challenge ^ peer_challenge ^ 32'h111ac39d;
 task disconnect;begin
  online<=0;status_valid<=0;occupied<=0;queued<=0;event_valid<=0;seen<=0;
  sync_state<=0;sync_pending<=0;ack_pending<=0;status_pending<=0;sync_age<=0;result<=`UI_UNKNOWN;result_valid<=1;
 end endtask
 always @(posedge clk or negedge rst_n)begin
  if(!rst_n)begin
   session<=0;challenge<=0;peer_challenge<=0;sync_state<=0;sync_age<=0;alive_age<=0;status_age<=0;
   sync_pending<=0;ack_pending<=0;status_pending<=0;tx_busy<=0;occupied<=0;queued<=0;
   out_id<=0;out_flags<=0;queue_id<=0;queue_flags<=0;out_body<=0;queue_body<=0;out_seq<=0;next_seq<=1;
   retry_age<=0;attempts<=0;seen<=0;accepted_seq<=0;accepted_result<=0;tx_body<=0;rx_body<=0;
   read_count<=0;read_phase<=0;retire<=0;
   ack_id<=0;ack_result<=0;ack_seq<=0;event_valid<=0;
   online<=0;
   result<=`UI_UNKNOWN;result_valid<=0;last_action<=0;drops<=0;status_out<=0;status_valid<=0;
  end else begin
   result_valid<=0;
   if(ms_tick)begin
    if(sync_age<1000)sync_age<=sync_age+1'b1;
    if(online)begin
     if(alive_age==999)disconnect();else alive_age<=alive_age+1'b1;
     if(status_age==99)begin status_age<=0;if(!HOST)status_pending<=1;end else status_age<=status_age+1'b1;
    end
    if(occupied && attempts!=0 && retry_age<200)retry_age<=retry_age+1'b1;
   end
   // Use free-running milliseconds for reconnect challenges.
   if(HOST && !online && sync_age>=250 && !tx_busy)begin
    if(sync_state==0)begin challenge<=uptime;peer_challenge<=0;sync_state<=1;ack_pending<=0;status_pending<=0;end
    sync_pending<=1;sync_age<=0;
   end
   if(send_valid && send_ready)begin
    if(!occupied)begin occupied<=1;out_id<=send_id;out_flags<=send_flags;out_body<=send_body;out_seq<=next_seq;next_seq<=next_seq+1'b1;attempts<=0;retry_age<=0;end
    else begin queued<=1;queue_id<=send_id;queue_flags<=send_flags;queue_body<=send_body;end
   end else if(send_valid && !send_ready && send_flags!=4)drops<=drops+1'b1;
   if(!occupied && queued && online)begin
    occupied<=1;queued<=0;out_id<=queue_id;out_flags<=queue_flags;out_body<=queue_body;out_seq<=next_seq;next_seq<=next_seq+1'b1;attempts<=0;retry_age<=0;
   end
   if(occupied && attempts==3 && retry_age==200 && !tx_busy)disconnect();
   if(event_valid && event_ready)begin
    event_valid<=0;seen<=1;accepted_seq<=captured_offset;accepted_result<=event_result;
    ack_pending<=1;ack_id<=HOST ? `UI_KEY:`UI_ACTION;ack_seq<=captured_offset;ack_result<=event_result;
    if(!HOST)last_action<=captured_offset;
    read_phase<=0;retire<=1;
   end
   if(retire)begin retire<=0;read_phase<=0;end
   else if(rx_valid && ui && !event_valid)case(read_phase)
    0:begin
     read_count<=0;read_phase<=rx_length==0 ? 3:1;
    end
    1:read_phase<=2;
    2:begin
     rx_body[351-read_count*8-:8]<=rx_data;
     if(read_count+1>=captured_length || read_count==43)read_phase<=3;
     else begin read_count<=read_count+1'b1;read_phase<=1;end
    end
    3:begin
     read_phase<=0;retire<=1;
     if(captured_type==`UI_SYNC && captured_length==0)begin
      if(!HOST && captured_flags==1 && captured_id==`UI_VERSION)begin
       if(sync_state==0 || captured_epoch!=challenge)begin
        online<=0;status_valid<=0;occupied<=0;queued<=0;seen<=0;ack_pending<=0;status_pending<=0;challenge<=captured_epoch;peer_challenge<=uptime;sync_state<=2;
       end
       sync_pending<=1;
      end else if(HOST && captured_flags==2 && sync_state==1 && captured_epoch==challenge && captured_id==`UI_VERSION)begin
       peer_challenge<=captured_offset;session<=challenge ^ captured_offset ^ 32'h111ac39d;sync_state<=3;sync_pending<=1;
      end else if(!HOST && captured_flags==3 && (sync_state==2 || sync_state==4) && captured_epoch==mixed && captured_offset==peer_challenge)begin
       session<=mixed;sync_state<=4;online<=1;alive_age<=0;sync_pending<=1;status_pending<=1;
      end else if(HOST && captured_flags==4 && sync_state==3 && captured_epoch==session)begin online<=1;sync_state<=4;alive_age<=0;end
     end else if(online && captured_epoch==session)begin
      alive_age<=0;
      if(captured_type==`UI_ACK && captured_length==0 && occupied && captured_offset==out_seq && captured_id==(HOST ? `UI_ACTION:`UI_KEY))begin
       occupied<=0;result<=captured_flags;result_valid<=1;
      end else if(HOST && captured_type==`UI_STATUS && captured_length==44 && rx_body[351:344]==`UI_VERSION)begin status_out<=rx_body;status_valid<=1;end
      else if(expected && captured_length==(HOST ? 0:8))begin
       if(seen && captured_offset==accepted_seq)begin ack_pending<=1;ack_id<=captured_type;ack_seq<=captured_offset;ack_result<=accepted_result;end
       else if(!seen || newer)begin
        event_valid<=1;retire<=0;read_phase<=3;
       end else begin ack_pending<=1;ack_id<=captured_type;ack_seq<=captured_offset;ack_result<=`UI_BAD;end
      end
     end
    end
   endcase
   if(tx_valid && tx_ready)begin
    tx_busy<=1;
    if(want_sync)sync_pending<=0;
    else if(want_ack)ack_pending<=0;
    else if(want_out)begin if(HOST)tx_body<={out_body,288'd0};attempts<=attempts+1'b1;retry_age<=0;end
    else if(want_status)begin tx_body<=status_in;status_pending<=0;end
   end else if(tx_busy && tx_done)tx_busy<=0;
  end
 end
endmodule
