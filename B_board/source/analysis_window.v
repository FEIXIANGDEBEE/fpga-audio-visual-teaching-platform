`timescale 1ns/1ps

module analysis_window #(
 parameter MS_CYCLES=50000, WINDOW_MS=6000, DRAIN_MS=2000, RESULT_MS=2000,
 INTERNAL_PREP=0, READY_MS=750, PREPARE_MS=2000
)(
 input wire clk,rst_n,new_epoch,arm,cancel,link_ok,fault,prepared,prepare_failed,mic_ready,
 input wire [31:0] control_generation,
 input wire feedback_valid,feedback_ok,input wire [31:0] feedback_control,
 input wire [1:0] feedback_command,
 output wire mic_request,session_open,capture,auto_inhibit,output reg active,
 output reg [31:0] window_control,output reg changed,
 output wire [2:0] ui_state,output reg [1:0] last_command,
 output wire prep_listen,prep_blocked,output wire [1:0] prep_state
);
 localparam IDLE=0,WARM=1,LISTEN=2,DRAIN=3,RESULT=4;
 localparam DW=MS_CYCLES<2 ? 1:$clog2(MS_CYCLES);
 localparam EW=$clog2(WINDOW_MS+DRAIN_MS+RESULT_MS+1);
 reg [2:0] state;reg [DW-1:0] divider;reg [EW-1:0] elapsed;reg result_ok;
 localparam RW=READY_MS<2 ? 1:$clog2(READY_MS+1);
 reg [RW-1:0] ready_count;reg warm_failed;
 wire tick=divider==MS_CYCLES-1;
// The deadline stops admission, not the transaction A already owns.
// Repeated terminal feedback must still match this window_control.
 wire terminal=feedback_valid && feedback_control==window_control;
 assign session_open=active;
 assign capture=state==LISTEN && mic_ready && link_ok && !fault && !cancel && !arm;
 assign mic_request=active;
 assign auto_inhibit=active;
 assign prep_listen=(state==LISTEN || state==DRAIN) && mic_ready && link_ok && !fault && !new_epoch;
 assign prep_blocked=warm_failed && state==RESULT;
 assign prep_state=state==WARM ? 2'd1:prep_listen ? 2'd2:2'd0;
 wire warm_done=INTERNAL_PREP ? tick && mic_ready && ready_count==READY_MS-1:prepared;
 wire warm_timeout=INTERNAL_PREP ? tick && elapsed>=PREPARE_MS-1:prepare_failed;
 assign ui_state=state==WARM ? 3'd1:state==LISTEN ? 3'd2:state==DRAIN ? 3'd4:state==RESULT ? (result_ok ? 3'd5:3'd6):3'd0;
 always @(posedge clk or negedge rst_n)begin
  if(!rst_n)begin active<=0;state<=IDLE;divider<=0;elapsed<=0;result_ok<=0;window_control<=0;changed<=0;last_command<=0;ready_count<=0;warm_failed<=0;end
  else begin
   changed<=0;
   if(tick)divider<=0;else divider<=divider+1'b1;
   if(tick && state!=IDLE)elapsed<=elapsed+1'b1;
   if(new_epoch || !link_ok || fault)begin
    if(active)changed<=1;
    state<=IDLE;active<=0;elapsed<=0;last_command<=0;result_ok<=0;ready_count<=0;warm_failed<=0;
   end else if(active && (cancel || arm))begin
    // Cancel wins this edge. Drain what the scene controller accepted;
    // do not let A submit another transaction.
    state<=state==WARM ? RESULT:DRAIN;active<=state!=WARM;elapsed<=0;divider<=0;result_ok<=0;last_command<=0;changed<=1;
   end else case(state)
    IDLE,RESULT:begin
     if(arm)begin state<=WARM;active<=1;window_control<=control_generation;elapsed<=0;divider<=0;last_command<=0;result_ok<=0;changed<=1;ready_count<=0;warm_failed<=0;end
     else if(state==RESULT && tick && elapsed>=RESULT_MS-1)begin state<=IDLE;elapsed<=0;end
    end
    WARM:begin
     if(!mic_ready)ready_count<=0;
     else if(tick)ready_count<=ready_count+1'b1;
     if(warm_done)begin state<=LISTEN;elapsed<=0;divider<=0;changed<=1;end
     else if(warm_timeout)begin state<=RESULT;active<=0;elapsed<=0;result_ok<=0;changed<=1;warm_failed<=1;end
    end
    LISTEN:begin
     if(terminal)begin state<=RESULT;active<=0;elapsed<=0;result_ok<=feedback_ok;last_command<=feedback_ok ? feedback_command:0;changed<=1;end
     else if(!mic_ready || (tick && elapsed>=WINDOW_MS-1))begin state<=DRAIN;elapsed<=0;divider<=0;changed<=1;end
    end
    DRAIN:begin
     if(terminal)begin state<=RESULT;active<=0;elapsed<=0;result_ok<=feedback_ok;last_command<=feedback_ok ? feedback_command:0;changed<=1;end
     else if(tick && elapsed>=DRAIN_MS-1)begin state<=RESULT;active<=0;elapsed<=0;result_ok<=0;last_command<=0;changed<=1;end
    end
    default:begin state<=IDLE;active<=0;elapsed<=0;end
   endcase
  end
 end
endmodule
