`timescale 1ns/1ps
`include "ui_protocol.vh"
module menu_control #(parameter IDLE_MS=15000)(
 input wire clk,rst_n,ms_tick,input wire [4:0] key_id,input wire [2:0] key_flags,input wire key_valid,
 input wire [3:0] short_key,long_key,switches,input wire [7:0] command,input wire command_valid,demo_prepare,
 input wire online,status_valid,input wire [351:0] status,input wire [3:0] current_page,input wire current_valid,local_busy,local_fault,
 output reg [2:0] brightness,contrast,output reg [1:0] effect,output reg auto_req,text_req,output reg [1:0] filter_req,
 output wire panel,output wire [2:0] menu,output wire action_valid,input wire action_ready,
 output wire [7:0] action_op,action_value,input wire result_valid,input wire [7:0] result,
 output wire [127:0] view,output reg [15:0] generation,input wire [7:0] result_op,output wire [15:0] probe_id,output reg [1:0] motion_level);
 reg menu_action_valid;reg [7:0] menu_action_op,menu_action_value;
 wire menu_panel;wire [127:0] menu_view;reg raw_ev;
 // Automatic transactions own these six bits; menu state and values stay local.
 reg [1:0] record_shortcut,auto_opcode;
 reg auto_valid,auto_pending;
 reg [1:0] next_shortcut,next_opcode,auto_fire;
 reg next_auto_valid,next_auto_pending,auto_hint_valid,auto_open;
 reg [3:0] auto_hint;
 wire auto_active=record_shortcut!=0;
 wire menu_action_ready=action_ready && !auto_valid && !auto_pending;
 wire [7:0] auto_op=auto_opcode==2 ? `UI_PROBE:auto_opcode==3 ? `UI_RECORD:`UI_STOP;
 wire auto_ack=auto_pending && result_valid && result_op==auto_op;
 wire [3:0] rec_backend=status[267:264];
 wire record_page=current_valid && current_page==9 && !local_busy;
 wire view_request=!panel && ((long_key[1] && !long_key[0] && !(|short_key)) ||
  (command_valid && command=="g" && !(|short_key) && !(|long_key)));
 wire record_long=view_request && current_valid && current_page==9;
 wire auto_start=record_long && ready && !local_busy && !saving && can_issue &&
  !demo_prepare && rec_backend!=9 && (!bowner[0] || rec_backend==1);
 wire intercept_start=auto_start || record_long && (demo_prepare || rec_backend==9);
 wire shortcut_menu=long_key[0] || (raw_ev && kid==6 && kflags[0] && !short_key[0]);
 wire shortcut_expired=ms_tick && idle_ms==IDLE_MS-1;
 wire shortcut_cancel=record_shortcut==1 && (short_key[0] || shortcut_menu || !record_page ||
  local_fault || bflags[6] || rec_backend==9 || shortcut_expired || demo_prepare);
 wire fresh_probe={status[127:120],status[7:0]}==probe_generation;
 wire cleanup_known=auto_opcode!=2 || fresh_probe;
 wire cleanup_error=record_shortcut[1] && hint!=0 && hint!=7;
 assign action_valid=auto_valid || (!auto_pending && menu_action_valid);
 assign action_op=auto_valid ? auto_op:menu_action_op;
 assign action_value=auto_valid ? (auto_opcode==3 ? 8'd1:8'd0):
  menu_action_op==`UI_CONTEXT ? {7'd0,menu_action_value[0] || auto_active}:menu_action_value;
 assign view={menu_view[127:113],auto_active,menu_view[111:19],menu_view[18] || auto_active,
  menu_view[17:3],auto_active ? 3'd0:menu_view[2:0]};
 always @*begin
  next_shortcut=record_shortcut;next_opcode=auto_opcode;
  next_auto_valid=auto_valid;next_auto_pending=auto_pending;
  auto_fire=0;auto_hint_valid=0;auto_hint=0;auto_open=0;
  if(auto_valid && action_ready)next_auto_valid=0;
  if(!backend_ok)begin
   next_shortcut=0;next_auto_valid=0;next_auto_pending=0;
   if(auto_active)begin auto_hint_valid=1;auto_hint=6;end
  end else begin
   if(auto_ack)begin
    next_auto_pending=0;auto_hint_valid=1;
    auto_hint=cleanup_error && auto_opcode==1 && result==`UI_OK ? hint:
     result==`UI_OK ? 4'd0:result[3:0];
    if(record_shortcut==1)begin
     if(auto_opcode==3)next_shortcut=result==`UI_OK ? 0:2;
     else if(result!=`UI_OK)next_shortcut=0;
    end else if(record_shortcut[1] && result!=`UI_OK && auto_opcode!=3)begin
     next_shortcut=0;auto_open=record_shortcut==3;
    end
   end
   if(shortcut_cancel)begin
    next_shortcut=shortcut_menu ? 3:2;auto_hint_valid=1;
    auto_hint=local_fault || bflags[6] || rec_backend==9 ? 4:shortcut_expired ? 5:0;
    if(auto_valid && !action_ready)begin next_auto_valid=0;next_auto_pending=0;next_opcode=0;end
    if(auto_ack && result!=`UI_OK)begin
     auto_hint=result[3:0];
     if(auto_opcode!=3)begin next_shortcut=0;auto_open=shortcut_menu;end
    end
   end else if(record_shortcut[1] && !auto_pending && cleanup_known && (!bowner[0] || local_fault || bflags[6]))begin
    next_shortcut=0;auto_open=record_shortcut==3;
   end
   if(auto_start)begin next_shortcut=1;auto_fire=bowner[0] ? 1:2;end
   else if(auto_active && !shortcut_cancel && !auto_pending && can_issue && (!auto_valid || action_ready))begin
    if(record_shortcut==1 && ready && record_page && !saving)begin
     if(auto_opcode==1 && !bowner[0])auto_fire=2;
     else if(auto_opcode==2 && fresh_probe && bowner[0] && bowner[1] && bflags[4])auto_fire=3;
    end else if(record_shortcut[1] && cleanup_known && bowner[0] && !bflags[6] && !saving && auto_opcode!=1)auto_fire=1;
   end
   if(auto_fire!=0)begin
    next_auto_valid=1;next_auto_pending=1;next_opcode=auto_fire;
    auto_hint_valid=1;auto_hint=cleanup_error ? hint:4'd7;
   end
  end
  if(intercept_start && !auto_start)begin auto_hint_valid=1;auto_hint=demo_prepare ? 2:4;end
 end
 always @(posedge clk or negedge rst_n)begin
  if(!rst_n)begin record_shortcut<=0;auto_opcode<=0;auto_valid<=0;auto_pending<=0;end
  else begin record_shortcut<=next_shortcut;auto_opcode<=next_opcode;auto_valid<=next_auto_valid;auto_pending<=next_auto_pending;end
 end
 localparam CLOSED=8'b00000001,CATEGORY=8'b00000010,ITEMS=8'b00000100,EDIT=8'b00001000,CONFIRM=8'b00010000,INFO=8'b00100000,WAIT_ACTION=8'b01000000,WAIT_SCAN=8'b10000000;
 (* KEEP="TRUE" *) reg [7:0] state;reg [2:0] category,item;reg [3:0] draft;reg choice;reg [3:0] hint;reg [13:0] idle_ms;reg [10:0] quick_ms;
 reg [1:0] quick,info_page,demo_interval;reg [1:0] sub_ink;reg [7:0] selected_op;reg record_intent;reg user_pending;reg [4:0] pending_op;
 reg [7:0] context_ms;reg context_dirty;
 reg [15:0] probe_generation;
 assign probe_id=probe_generation;
 reg [7:0] pending_value;reg demo_started,demo_snapshot_valid;reg [13:0] demo_saved;
 reg ev;reg [4:0] kid;reg [2:0] kflags;
 wire [3:0] bsw=status[283:280];
 wire [7:0] bflags=status[343:336],bplay=status[295:288],banalysis=status[279:272],bowner=status[15:8];
 wire [3:0] volume=status[315:312];
 wire backend_ok=online && status_valid;
 wire demo_mode=backend_ok && !local_fault && !bflags[6] && demo_started;
 wire ready=backend_ok && status[237] && !status[238] && !bflags[6] && !local_fault;
 wire can_issue=backend_ok && !local_fault && !user_pending && (!menu_action_valid || menu_action_ready);
 wire saving=backend_ok && bowner[2];
 wire [2:0] last_item=category==0 ? 5:category==1 ? 3:category==2 ? 3:category==3 ? 5:4;
 wire lock_item=(category==0 && (item==4 && |switches[3:2])) ||
  (category==2 && item==1 && switches[0]) ||
  (category==1 && item==1 && bsw[3]) ||
  (category==3 && (item==0 && bsw[0] || item==2 && bsw[1] || item==3 && bsw[2]));
 wire [3:0] current_value=category==0 ? (item==0 ? {1'b0,brightness}:item==1 ? {1'b0,contrast}:item==2 ? {2'd0,effect}:item==3 ? {2'd0,sub_ink}:item==4 ? {2'd0,filter_req}:{2'd0,motion_level}):
  category==1 ? (item==0 ? volume:item==1 ? {3'd0,bplay[1]}:{3'd0,bplay[0]}):
  category==2 ? (item==0 ? current_page:item==1 ? {3'd0,auto_req}:item==2 ? {2'd0,demo_interval}:4'd0):
  category==3 ? (item==0 ? (bplay[7] ? 4'd3:banalysis[1] ? 4'd2:banalysis[7] ? 4'd1:4'd0):item==1 ? {3'd0,banalysis[0]}:item==2 ? {3'd0,banalysis[2]}:{3'd0,banalysis[3]}):0;
 wire [3:0] maximum=category==0 ? (item<2 ? 4:item==2 || item==4 ? 3:item==5 || item==3 ? 2:1):category==2 && item==2 ? 3:category==1 && item==0 || category==2 && item==0 ? 9:1;
 wire view_edit=category==3 && item==0;
 wire [1:0] next_view=kid==3 ? {draft[1] | draft[0],draft[1] | !draft[0]}:{draft[1] & draft[0],draft[1] & !draft[0]};
 wire menu_view_request=!menu_panel && !auto_active && !intercept_start && ((long_key[1] && !long_key[0] && !(|short_key)) ||
  (command_valid && command=="g" && !(|short_key) && !(|long_key)));
 wire [2:0] state_code=state[1] ? 3'd1:state[2] ? 3'd2:state[3] ? 3'd3:state[4] ? 3'd4:state[5] ? 3'd5:state[6] ? 3'd6:state[7] ? 3'd7:3'd0;
 assign menu_panel=!state[0];assign panel=menu_panel || auto_active;assign menu=panel ? 3'd1:3'd0;
 // Build the compact record once in SYS and publish at a pixel-frame boundary.
 // Use the reserved upper 16 bits, keeping mailbox and protocol widths fixed.
 assign menu_view={status[267:264],status[60:56],status[63:62],bowner[0],4'd0,sub_ink,motion_level,status[113],demo_mode,demo_interval,switches,status_valid && online,status[255:240],status[239:224],banalysis,bplay,bsw,volume,
  saving,bflags[2],bflags[3],backend_ok,quick,info_page,generation,quick_ms!=0,hint,choice,draft,item,category,state_code};
 task issue;input [7:0] op,val;begin
  if(!backend_ok)hint<=6;
  else if(local_fault)hint<=4;
  else if(user_pending || (menu_action_valid && !menu_action_ready))hint<=1;
  else begin
   menu_action_valid<=1;menu_action_op<=op;menu_action_value<=val;pending_op<=op[4:0];pending_value<=val;user_pending<=1;hint<=7;
   if(op==`UI_DEMO && val>=1 && val<=4)begin demo_saved<={motion_level,brightness,contrast,effect,auto_req,text_req,filter_req};demo_snapshot_valid<=1;end
   // A key event increments generation as it creates the request. The link
   // sends that updated identity with the action.
   if(op==`UI_PROBE)begin record_intent<=1;probe_generation<=generation+1'b1;end
   if(op==`UI_PLAY || op==`UI_RECORD || op==`UI_DEMO && val<=4 || op==`UI_STOP || op==`UI_PROBE)state<=WAIT_ACTION;
  end
 end endtask
 always @*begin
  ev=key_valid;kid=key_id;kflags=key_flags;
  if(command_valid)case(command)
   "o":begin ev=1;kid=6;kflags=panel ? 0:1;end
   "q":begin ev=panel;kid=6;kflags=1;end
   "(":begin ev=1;kid=0;kflags=1;end
   ")":begin ev=1;kid=1;kflags=1;end
   "<":begin ev=1;kid=2;kflags=1;end
   ">":begin ev=1;kid=3;kflags=1;end
   "=":begin ev=1;kid=4;kflags=1;end
   "*":begin ev=1;kid=5;kflags=1;end
   "#":begin ev=1;kid=6;kflags=1;end
   default:begin end
  endcase
  if(|short_key || |long_key)begin
   ev=!long_key[1];kflags=1;
   kid=long_key[0] ? 6:short_key[0] ? (menu_panel ? 5:6):short_key[1] ? (menu_panel ? (state==EDIT || state==CONFIRM ? 2:1):17):short_key[2] ? (menu_panel ? (state==EDIT || state==CONFIRM ? 3:0):18):menu_panel ? 4:19;
  end
  raw_ev=ev;if(auto_active || intercept_start)ev=0;
 end
 always @(posedge clk or negedge rst_n)begin
  if(!rst_n)begin
   state<=CLOSED;category<=0;item<=0;draft<=0;choice<=0;hint<=0;idle_ms<=0;quick_ms<=0;quick<=0;info_page<=0;demo_interval<=2;
   brightness<=2;contrast<=2;effect<=2;motion_level<=2;auto_req<=0;text_req<=1;sub_ink<=0;filter_req<=0;generation<=0;
   menu_action_valid<=0;menu_action_op<=0;menu_action_value<=0;selected_op<=0;record_intent<=0;probe_generation<=0;context_ms<=0;context_dirty<=1;user_pending<=0;pending_op<=0;pending_value<=0;demo_started<=0;demo_snapshot_valid<=0;demo_saved<=0;
  end else begin
   if(menu_action_valid && menu_action_ready)menu_action_valid<=0;
   if(ms_tick)begin
    if(quick_ms!=0)quick_ms<=quick_ms-1'b1;
    if(menu_panel || auto_active)begin
     if(idle_ms==IDLE_MS-1)begin if(menu_panel)begin if(record_intent && !user_pending && bowner[0])issue(`UI_STOP,0);state<=CLOSED;choice<=0;record_intent<=0;context_dirty<=1;if(menu_action_valid && !menu_action_ready)begin menu_action_valid<=0;if(menu_action_op!=`UI_CONTEXT)user_pending<=0;end end end
     else idle_ms<=idle_ms+1'b1;
    end
    if(context_ms==249)begin context_ms<=0;context_dirty<=1;end else context_ms<=context_ms+1'b1;
   end
   if(context_dirty && !menu_action_valid && backend_ok && !raw_ev && !auto_pending && auto_fire==0 && !intercept_start && !(ms_tick && menu_panel && idle_ms==IDLE_MS-1 && record_intent))begin
    menu_action_valid<=1;menu_action_op<=`UI_CONTEXT;menu_action_value<={7'd0,panel};context_dirty<=0;
   end
   if(!backend_ok)begin
    menu_action_valid<=0;user_pending<=0;record_intent<=0;demo_started<=0;demo_snapshot_valid<=0;context_dirty<=1;
    if(state==WAIT_ACTION || state==WAIT_SCAN)begin hint<=6;state<=ITEMS;end
   end else if(result_valid && result_op!=`UI_CONTEXT && user_pending && result_op=={3'd0,pending_op})begin
    user_pending<=0;hint<=result==`UI_OK ? 4'd0:result[3:0];
    if(result_op==`UI_DEMO)begin
     if(result==`UI_OK && pending_value<=4)begin demo_started<=1;state<=CLOSED;context_dirty<=1;end
     else if(result==`UI_OK && pending_value>=6)begin
      demo_started<=0;
      if(demo_snapshot_valid && !local_fault && !bflags[6])begin {motion_level,brightness,contrast,effect,auto_req,text_req,filter_req}<=demo_saved;context_dirty<=1;end
      demo_snapshot_valid<=0;
     end else if(result!=`UI_OK && pending_value<=4)demo_snapshot_valid<=0;
    end
    if(state==WAIT_ACTION)begin
     if(result_op==`UI_PROBE && result==`UI_OK && record_intent)state<=WAIT_SCAN;
     else if(result_op==`UI_DEMO && result==`UI_OK && pending_value<=4)state<=CLOSED;
     else begin state<=(result==`UI_OK && (result_op==`UI_RECORD || result_op==`UI_PLAY || result_op==`UI_STOP)) ? CLOSED:ITEMS;if(result_op==`UI_PROBE)record_intent<=0;end
    end
   end
   if(state==WAIT_SCAN && backend_ok && record_intent && {status[127:120],status[7:0]}==probe_generation && bowner[0] && bowner[1] && bflags[4] && !local_fault)begin
    selected_op<=`UI_RECORD;choice<=0;state<=CONFIRM;
   end
   if(command_valid && !menu_panel && !auto_active && !intercept_start)case(command)
    "a":auto_req<=!auto_req;"s":text_req<=!text_req;"d":begin auto_req<=0;text_req<=0;end
    "b":begin brightness<=brightness==4 ? 0:brightness+1'b1;quick<=3;info_page<=0;quick_ms<=2000;hint<=0;end
    "c":begin contrast<=contrast==4 ? 0:contrast+1'b1;quick<=3;info_page<=1;quick_ms<=2000;hint<=0;end
    "e":begin effect<=effect+1'b1;quick<=3;info_page<=2;quick_ms<=2000;hint<=0;end
   endcase
   if(menu_view_request)begin
    idle_ms<=0; // Start a fresh menu timeout on a long gesture, as for ev keys.
    generation<=generation+1'b1;context_dirty<=1;quick<=2;quick_ms<=2000;
    if(current_valid && current_page==9)begin
      quick<=3;info_page<=3;
      if(!ready || local_busy)hint<=2;
      else if(saving)hint<=8;
      else if(bowner[0])issue(`UI_STOP,0);
      else begin category<=4;item<=1;issue(`UI_PROBE,0);end
     end else if(bsw[0])hint<=3;
     else if(!ready || !current_valid || current_page<3 || current_page>8 || local_busy || bowner[0] || banalysis[3] || banalysis[4])hint<=2;
     else issue(`UI_VIEW,{7'd0,!(banalysis[1] || banalysis[7])});
   end else if(ev && kflags!=0)begin
    // Give the physical event priority, but consume the reliable incoming key once.
    if(kid<17 || kid<21 && !menu_panel)begin
     if(!(menu_panel && lock_item && state==EDIT && (kid==2 || kid==3)))idle_ms<=0;
     generation<=generation+1'b1;context_dirty<=1;
     if(demo_mode && !menu_panel && kflags[0] && (kid==4 || kid==5 || kid==6))begin
      if(can_issue)issue(`UI_DEMO,kid==4 ? 5:kid==5 ? 6:7);else hint<=1;
     end else if(kid==6 && kflags[0] && short_key[0] && !menu_panel && current_valid && current_page==9 && backend_ok && bowner[0])begin
      quick<=3;info_page<=3;quick_ms<=2000;
      if(saving)hint<=8;else issue(`UI_STOP,0);
     end else if(kid==6 && kflags[0])begin if(record_intent && !user_pending && bowner[0])issue(`UI_STOP,0);state<=menu_panel ? CLOSED:CATEGORY;hint<=0;choice<=0;record_intent<=0;if(menu_action_valid && !menu_action_ready)begin menu_action_valid<=0;if(menu_action_op!=`UI_CONTEXT)user_pending<=0;end end
     else if(kflags[2])begin end
     else case(state)
      CLOSED:begin
       if(kid==0 || kid==1)begin quick<=1;quick_ms<=2000;if(backend_ok)issue(`UI_VOLUME,kid==0 ? (volume<9 ? volume+1'b1:volume):(volume!=0 ? volume-1'b1:volume));else hint<=6;end
       else if(kflags[0])case(kid)
        2,3:if(ready && current_valid && !local_busy && !saving)begin
         if(kid==2 && current_page!=0)issue(`UI_PAGE,current_page-1'b1);
         else if(kid==3 && current_page!=9)issue(`UI_PAGE,current_page+1'b1);
        end else hint<=2;
        4:if(ready && current_page==9)issue(`UI_PLAY,0);else if(ready && bflags[1])issue(`UI_PAUSE,!bplay[0]);else hint<=2;
        5:begin quick<=2;quick_ms<=2000;if(bsw[1])hint<=3;else issue(`UI_HOLD,!banalysis[2]);end
        7:if(ready && !saving)issue(`UI_PAGE,9);else hint<=2;
        8,9,10,11,12,13,14,15,16:if(ready && !saving)issue(`UI_PAGE,kid-8);else hint<=2;
        17:begin
         quick<=3;quick_ms<=2000;
         if(short_key[1] && current_valid && current_page==9)begin
          info_page<=3;
          if(saving)hint<=8;
          else if(rec_backend==9)hint<=4;
          else if(!ready || local_busy || (bowner[0] && rec_backend!=1 && rec_backend!=6))hint<=2;
          else issue(`UI_PLAY,0);
         end else begin effect<=effect+1'b1;info_page<=2;hint<=0;end
        end
        18:begin brightness<=brightness==4 ? 0:brightness+1'b1;quick<=3;info_page<=0;quick_ms<=2000;hint<=0;end
        19:begin contrast<=contrast==4 ? 0:contrast+1'b1;quick<=3;info_page<=1;quick_ms<=2000;hint<=0;end
        20:if(ready && current_valid && current_page==9 && !local_busy && !saving)begin category<=4;item<=1;issue(`UI_PROBE,0);end else hint<=2;
       endcase
      end
      CATEGORY:begin
       if(kid==0 && category!=0)begin category<=category-1'b1;item<=0;end
       if(kid==1 && category!=4)begin category<=category+1'b1;item<=0;end
       if(kid>=8 && kid<=12 && kflags[0])begin category<=kid-8;item<=0;end
       if((kid==4 && kflags[0]) || kid==3 && kflags[0])state<=ITEMS;
       if(kid==5 && kflags[0])begin state<=CLOSED;record_intent<=0;end
      end
      ITEMS:begin
       hint<=0;
       if(kid==0 && item!=0)item<=item-1'b1;
       if(kid==1 && item<last_item)item<=item+1'b1;
       if((kid==2 || kid==5) && kflags[0])begin state<=CATEGORY;record_intent<=0;end
       if((kid==4 || kid==3) && kflags[0])begin
        if(lock_item)hint<=3;
        else if(category==0 || category==1 && item<2 || category==2 && item<3 || category==3 && item<4)begin
         if(category!=0 && !backend_ok)hint<=6;else begin draft<=current_value;state<=EDIT;end
        end else if(category==4 && item>=3)begin state<=INFO;info_page<=0;end
        else if(!ready)hint<=2;
        else if(saving && (category==4 || category==2 && item==3))hint<=8;
        else if(category==2 && item==3)begin selected_op<=`UI_DEMO;choice<=0;state<=CONFIRM;end
        else if(category==4 && item<2)begin
         if(!current_valid || local_busy)hint<=1;
         else if(current_page!=9)begin
          // OK here accepts a normal page transition; it does not queue recording.
          issue(`UI_PAGE,9);hint<=9;record_intent<=0;
         end else if(item==1)begin issue(`UI_PROBE,0);end
         else begin issue(`UI_PLAY,0);end
        end else begin
         if(category==1)issue(item==2 ? `UI_PAUSE:`UI_REPLAY,item==2 ? !bplay[0]:0);
         else if(category==3 && item==4)begin issue(banalysis[4] ? `UI_CANCEL:`UI_ARM,0);if(can_issue)state<=CLOSED;end
         else if(category==3)issue(`UI_CLEAR,0);
         else issue(`UI_STOP,0);
        end
       end
      end
      EDIT:begin
       if(kid==2 || kid==3)begin
        if(lock_item)hint<=3;
        else if(view_edit)begin draft<={2'd0,next_view};issue(`UI_VIEW,{6'd0,next_view});end
        else begin
         draft<=kid==3 ? (draft<maximum ? draft+1'b1:draft):(draft!=0 ? draft-1'b1:draft);
         if(category==0)case(item)
          0:brightness<=kid==3 ? (brightness<4 ? brightness+1'b1:brightness):(brightness!=0 ? brightness-1'b1:brightness);
          1:contrast<=kid==3 ? (contrast<4 ? contrast+1'b1:contrast):(contrast!=0 ? contrast-1'b1:contrast);
          2:effect<=kid==3 ? (effect<3 ? effect+1'b1:effect):(effect!=0 ? effect-1'b1:effect);
          3:sub_ink<=kid==3 ? (sub_ink<2 ? sub_ink+1'b1:sub_ink):(sub_ink!=0 ? sub_ink-1'b1:sub_ink);
          4:filter_req<=kid==3 ? (filter_req<3 ? filter_req+1'b1:filter_req):(filter_req!=0 ? filter_req-1'b1:filter_req);
          5:motion_level<=kid==3 ? (motion_level<2 ? motion_level+1'b1:motion_level):(motion_level!=0 ? motion_level-1'b1:motion_level);
         endcase
         else if(category==2 && item==1)auto_req<=kid==3;
         else if(category==2 && item==2)demo_interval<=kid==3 ? (demo_interval<3 ? demo_interval+1'b1:demo_interval):(demo_interval!=0 ? demo_interval-1'b1:demo_interval);
         else if(!(category==2 && item==0))begin
          issue(category==1 ? (item==0 ? `UI_VOLUME:`UI_MUTE):item==0 ? `UI_VIEW:item==1 ? `UI_RIGHT:item==2 ? `UI_HOLD:`UI_MIC,
           kid==3 ? (draft<maximum ? draft+1'b1:draft):(draft!=0 ? draft-1'b1:draft));
         end
        end
       end
       if(kid==4 && kflags[0])begin
        if(category==2 && item==0)begin if(ready && !saving)issue(`UI_PAGE,{4'd0,draft});else hint<=2;end
        state<=ITEMS;
       end
       if(kid==5 && kflags[0])state<=ITEMS;
      end
      CONFIRM:begin
       if(kid==2)choice<=0;else if(kid==3)choice<=1;
       if(kid==5 && kflags[0])begin if(record_intent && !user_pending && bowner[0])issue(`UI_STOP,0);state<=ITEMS;choice<=0;record_intent<=0;end
       if(kid==4 && kflags[0])begin
        if(!choice)begin if(record_intent && !user_pending && bowner[0])issue(`UI_STOP,0);state<=ITEMS;record_intent<=0;end
        else if(ready && !saving && !local_busy && can_issue)begin issue(selected_op,selected_op==`UI_DEMO ? {6'd0,demo_interval}+1'b1:8'd1);choice<=0;record_intent<=0;end
        else begin hint<=saving ? 8:!backend_ok ? 6:local_fault ? 4:!can_issue ? 1:2;state<=ITEMS;end
       end
      end
      INFO:begin if(kid==5 && kflags[0])state<=ITEMS;if(kid==2 && info_page!=0)info_page<=info_page-1'b1;if(kid==3 && info_page<2)info_page<=info_page+1'b1;end
      WAIT_ACTION:if(kid==5 && kflags[0])state<=ITEMS;
      WAIT_SCAN:if(kid==5 && kflags[0])begin if(!user_pending && bowner[0])issue(`UI_STOP,0);state<=ITEMS;record_intent<=0;end
      default:state<=CLOSED;
     endcase
    end
   end
   if(local_fault || backend_ok && bflags[6])begin demo_started<=0;demo_snapshot_valid<=0;end
   if(local_fault)hint<=4;
   if(demo_prepare)begin state<=CLOSED;brightness<=2;contrast<=2;effect<=2;motion_level<=2;auto_req<=0;text_req<=1;sub_ink<=0;filter_req<=0;context_dirty<=1;choice<=0;end
   // Share metadata only; ordinary menu values do not select automatic phases.
   if(intercept_start)begin
    generation<=generation+1'b1;idle_ms<=0;quick<=3;info_page<=3;quick_ms<=2000;context_dirty<=1;
    if(auto_start)begin category<=4;item<=1;end
   end
   if(auto_fire!=0)begin
    if(!intercept_start)generation<=generation+1'b1;
    if(auto_fire==2)probe_generation<=generation+1'b1;
    context_dirty<=1;
   end
   if(auto_hint_valid)hint<=auto_hint;
   if(record_shortcut!=next_shortcut)context_dirty<=1;
   if(auto_open)begin state<=CATEGORY;context_dirty<=1;end
   if(shortcut_cancel)choice<=0;
   if(local_fault)hint<=4;
  end
 end
endmodule
