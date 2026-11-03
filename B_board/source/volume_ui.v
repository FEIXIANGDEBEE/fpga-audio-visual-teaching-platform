`timescale 1ns/1ps

module volume_ui #(
 parameter ENTER_MS=1500,REPEAT_START_MS=600,REPEAT_MS=200,IDLE_MS=10000,IR_IDLE_MS=2000
)(
 input wire clk,rst_n,ms_tick,input wire [3:0] down,
 input wire all_released,chord_blocked,input wire [3:0] short_key,long_key,
 input wire music_valid,ready,request_mic,window_active,hard_fault,demo_prepare,
 input wire [7:0] command,input wire command_valid,
 input wire ir_volume_valid,ir_volume_up,
 output reg [3:0] routed_short,routed_long,output reg [1:0] mode,
 output reg [3:0] target,output reg [7:0] generation,
 output wire [15:0] steps,output wire activity,output reg rejected,
 input wire ir_volume_refresh,input wire set_valid,input wire [3:0] set_level,input wire demo_snapshot,demo_restore
);
 localparam NORMAL=0,ENTRY=1,VOLUME=2,EXIT=3;
 // steps exposes the 8-bit change generation, modulo 256.
 assign steps={8'd0,generation};
 reg activity_q;
 reg holding,plus,repeated;reg [9:0] held_ms;reg [7:0] repeat_ms;reg [13:0] idle_ms;
 reg ir_timeout;reg [3:0] demo_saved_target;
 wire external_action=command_valid && ((command>="0" && command<="9") ||
  command=="b" || command=="n" || command=="p" || command=="r" || command=="c" ||
  command=="v" || command=="z" || command=="m" || command=="j" || command=="x");
 wire can_enter=music_valid && ready && !request_mic && !window_active && !hard_fault;
 // Expose accepted IR activity combinationally so it wins over a simultaneous
 // stale voice result or AUTO request when the volume target changes.
 assign activity=activity_q || (ir_volume_valid && can_enter && (mode==NORMAL || mode==VOLUME));
 always @*begin
  routed_short=0;routed_long=0;
  if(mode==NORMAL)begin
   routed_short=short_key;routed_long=long_key;
   if(music_valid)routed_long[2]=0;
  end else begin
   routed_long[0]=long_key[0];
   if(mode==VOLUME)routed_long[2]=short_key[0];
  end
 end
 task adjust;input increase;begin
  activity_q<=1;idle_ms<=0;
  if((increase && target<9) || (!increase && target>0))begin
   target<=increase ? target+1'b1:target-1'b1;
   generation<=generation+1'b1;
  end
 end endtask
 always @(posedge clk or negedge rst_n)begin
  if(!rst_n)begin mode<=NORMAL;target<=7;generation<=0;demo_saved_target<=7;
   activity_q<=0;rejected<=0;holding<=0;plus<=0;repeated<=0;held_ms<=0;repeat_ms<=0;idle_ms<=0;ir_timeout<=0;end
  else begin
   activity_q<=0;rejected<=0;if(demo_snapshot)demo_saved_target<=target;
   if(demo_prepare || long_key[0] || (command_valid && command=="z"))begin
    mode<=EXIT;holding<=0;repeated<=0;held_ms<=0;repeat_ms<=0;idle_ms<=0;
    if(target!=7)begin target<=7;generation<=generation+1'b1;end
    activity_q<=1;
   end else if(demo_restore && !hard_fault)begin
    mode<=EXIT;holding<=0;repeated<=0;idle_ms<=0;activity_q<=1;
    if(target!=demo_saved_target)begin target<=demo_saved_target;generation<=generation+1'b1;end
   end else if(set_valid && set_level<=9 && !hard_fault && all_released && !chord_blocked && !(|short_key) && !(|long_key))begin
    activity_q<=1;if(target!=set_level)begin target<=set_level;generation<=generation+1'b1;end
   end else if((mode==ENTRY || mode==VOLUME) && (hard_fault || !music_valid || request_mic || window_active || external_action))begin
    mode<=EXIT;holding<=0;repeated<=0;idle_ms<=0;activity_q<=1;
    if(ir_volume_valid)rejected<=1;
   end else if(ir_volume_valid || ir_volume_refresh)begin
    holding<=0;repeated<=0;held_ms<=0;repeat_ms<=0;
    if(can_enter && (mode==NORMAL || mode==VOLUME))begin
     mode<=VOLUME;ir_timeout<=1;idle_ms<=0;
     if(ir_volume_valid)adjust(ir_volume_up);
     activity_q<=0;
    end else if(ir_volume_valid)rejected<=1;
   end else case(mode)
    NORMAL:begin
     holding<=0;repeated<=0;held_ms<=0;repeat_ms<=0;idle_ms<=0;
     if(long_key[2] && music_valid)begin
      activity_q<=1;
      if(can_enter)begin mode<=ENTRY;ir_timeout<=0;end else rejected<=1;
     end
    end
    ENTRY:begin
     holding<=0;idle_ms<=0;
     if(all_released)begin mode<=VOLUME;activity_q<=1;end
    end
    VOLUME:begin
     if(down[3])begin mode<=EXIT;holding<=0;activity_q<=1;idle_ms<=0;end
     else if(ms_tick)begin
      if(!all_released || (|short_key))begin idle_ms<=0;ir_timeout<=0;end
      else if(idle_ms==(ir_timeout ? IR_IDLE_MS-1:IDLE_MS-1))begin mode<=EXIT;idle_ms<=0;activity_q<=1;end
      else idle_ms<=idle_ms+1'b1;
      if(chord_blocked)begin holding<=0;repeated<=0;held_ms<=0;repeat_ms<=0;end
      else if(!holding && (down[1] ^ down[2]))begin
       holding<=1;plus<=down[2];held_ms<=1;repeat_ms<=0;repeated<=0;idle_ms<=0;
      end else if(holding)begin
       if(!(plus ? down[2]:down[1]))begin
        if(!repeated)adjust(plus);
        holding<=0;held_ms<=0;repeat_ms<=0;repeated<=0;
       end else if(!repeated)begin
        if(held_ms==REPEAT_START_MS-1)begin adjust(plus);repeated<=1;repeat_ms<=0;end
        else held_ms<=held_ms+1'b1;
       end else if(repeat_ms==REPEAT_MS-1)begin adjust(plus);repeat_ms<=0;end
       else repeat_ms<=repeat_ms+1'b1;
      end
     end
    end
    EXIT:begin holding<=0;repeated<=0;idle_ms<=0;if(all_released)mode<=NORMAL;end
    default:mode<=NORMAL;
   endcase
  end
 end
endmodule
