`timescale 1ns/1ps
module b_inputs #(parameter MS_CYCLES=50000,DB_MS=20,LONG_MS=1500,LONG_MASK=15)(
 input wire clk,rst_n,input wire [3:0] keys_n,switches,
 output reg [3:0] short_event,long_event,sw,output reg activity,blocked,output wire ms_tick,output wire [3:0] key_down,output wire all_released,chord_blocked);
 localparam MW=MS_CYCLES<2 ? 1:$clog2(MS_CYCLES);
 reg [MW-1:0] divider;
 (* ASYNC_REG="TRUE" *)reg [3:0] key_m,key_s,sw_m,sw_s;
 reg [3:0] stable,armed,pressed,fired;
 reg [4:0] db[0:3],sdb[0:3];reg [10:0] held[0:3];
 reg group_blocked;
 wire tick=divider==MS_CYCLES-1;
 wire [3:0] down=~key_s;
 wire multi=(down!=0) && ((down & (down-1'b1))!=0);
 assign ms_tick=tick;
 assign key_down=pressed & ~stable & {4{!group_blocked && !multi}};
 assign all_released=key_s==15 && stable==15;
 assign chord_blocked=group_blocked || multi;
 integer i;
 always @(posedge clk or negedge rst_n)begin
  if(!rst_n)begin
   divider<=0;key_m<=0;key_s<=0;sw_m<=0;sw_s<=0;stable<=0;armed<=0;pressed<=0;fired<=0;
   short_event<=0;long_event<=0;sw<=0;activity<=0;blocked<=0;group_blocked<=0;
   for(i=0;i<4;i=i+1)begin db[i]<=0;sdb[i]<=0;held[i]<=0;end
  end else begin
   key_m<=keys_n;key_s<=key_m;sw_m<=switches;sw_s<=sw_m;
   short_event<=0;long_event<=0;activity<=0;blocked<=0;
   if(tick)divider<=0;else divider<=divider+1'b1;
   if(tick)begin
    if(multi)begin group_blocked<=1;pressed<=0;armed<=0;blocked<=1;end
    if(key_s==15 && stable==15)group_blocked<=0;
    for(i=0;i<4;i=i+1)begin
     if(sw_s[i]==sw[i])sdb[i]<=0;
     else if(sdb[i]==DB_MS-1)begin sw[i]<=sw_s[i];sdb[i]<=0;activity<=1;end
     else sdb[i]<=sdb[i]+1'b1;
     if(key_s[i]==stable[i])begin
      db[i]<=0;
      if(stable[i])begin if(!group_blocked && !multi)armed[i]<=1;end
      else if(pressed[i] && !fired[i] && !group_blocked && !multi)begin
       if(held[i]<LONG_MS)held[i]<=held[i]+1'b1;
       if(held[i]==LONG_MS-1 && (LONG_MASK & (1<<i)))begin long_event[i]<=1;fired[i]<=1;activity<=1;end
      end
     end else if(db[i]==DB_MS-1)begin
      db[i]<=0;stable[i]<=key_s[i];held[i]<=0;activity<=1;
      if(!key_s[i])begin pressed[i]<=armed[i] && !group_blocked && !multi;armed[i]<=0;fired[i]<=0;end
      else begin
       if(pressed[i] && !fired[i] && !group_blocked && !multi)begin short_event[i]<=1;activity<=1;end
       pressed[i]<=0;fired[i]<=0;
      end
     end else db[i]<=db[i]+1'b1;
    end
   end
  end
 end
endmodule
