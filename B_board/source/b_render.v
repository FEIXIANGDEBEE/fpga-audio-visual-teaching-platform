`timescale 1ns/1ps
`include "text_b_defs.vh"
module b_render(input wire clk,rst_n,hs,vs,de,input wire [9:0] x,y,
 input wire [136:0] ui,input wire [662:0] plot,output wire oh,ov,od,output wire [23:0] rgb,input wire [6:0] wave_data,output wire [4:0] wave_address,output wire history_ready);
 localparam [23:0] BG=24'hf4f0e7,TEXT=24'h263645,GRID=24'h304252,AXIS=24'h647487,
 BAR=24'h42a6d8,EDGE=24'h60d4bd,AMBER=24'heaa653;
 wire [1:0] volume_mode=ui[131:130];
 wire [3:0] volume_target=ui[129:126],history_volume=ui[125:122];
 wire pending_volume=ui[121:114]!=ui[99:92] || ui[113:110]!=volume_target || ui[100];
 wire held=ui[39],mic=ui[38],busy=ui[18],fault=ui[19],music=plot[650],valid=plot[642],wave=plot[643];
 wire [2:0] voice=ui[31:29];wire [3:0] page=ui[15:12];wire [2:0] mute_sources={ui[47],ui[48],ui[43]};
 wire rec_page=ui[16] && page==9 && (ui[20] || ui[21]);wire [3:0] rec_state=ui[81:78];
 wire current_replay=rec_page && rec_state==6;
 wire [23:0] spec_rgb;wire spec_area;
 wire stale=plot[136],paused=plot[137],identity_stable=plot[135],identity_changed=plot[134];
 wire [8:0] history_filled;assign history_ready=history_filled>=16;
 wire effective_hold=held && history_ready;
 wire music_source=music && !mic && !rec_page;
 wire music_plot=music_source;
 wire history_view=ui[45];
 wire [9:0] chart_bottom=music_plot ? 10'd352:10'd320;
 wire spec_eligible=music_plot && history_view && !fault && !wave && volume_mode==0;
 wire spec_label=spec_eligible;
 spectrogram spectrogram(.clk(clk),.rst_n(rst_n),.wr_start(x==32 && y==0),
  .write_en(!effective_hold && !stale && !paused && valid && identity_stable && !mic),
  .clear(identity_changed),.heights(plot[639:512]),.x(x),.y(y),.show(spec_eligible),
  .rgb(spec_rgb),.in_area(spec_area),.history_filled(history_filled));
 wire waiting=stale || !valid || !identity_stable;
 wire [7:0] record_reason=rec_state==9 ? `B_R_FAIL:rec_state==3 ? `B_R_RECORD:
  rec_state==4 ? `B_R_SAVE:rec_state==6 ? `B_PLAY:rec_state==10 ? (ui[20] ? `B_R_SAVE:`B_R_SAVED):rec_state==1 ? `B_MICREADY:`B_BUSY;
 wire [7:0] reason=fault ? `B_SYSTEM_FAULT:rec_page ? record_reason:
  wave ? (ui[40] ? `B_WAVE_SWITCH:`B_WAVE_MENU):mic ? `B_MIC_NO_HISTORY:
  !music ? `B_NOMUSIC:held && history_filled<16 ? `B_HOLD_PENDING:
  effective_hold ? `B_SPEC_HELD:paused ? `B_SPEC_PAUSED:waiting ? `B_SPEC_WAIT:
  history_filled==0 ? `B_SPEC_PREPARE:`B_SPEC_LIVE;
 wire replay_record=ui[35:32]==9 && !ui[37];
 wire [1:0] progress_state=ui[91:90];wire [3:0] progress_seconds=ui[89:86],progress_segments=ui[85:82];
 wire [7:0] autof=ui[59:52];wire [1:0] last_command=ui[51:50];
 wire [3:0] auto_reason=ui[67:64],auto_seconds=ui[63:60];
 wire [4:0] meter_level=plot[655:651],meter_peak=plot[660:656];
 wire meter_clipped=plot[661],meter_valid=plot[662];
 wire meter_active=meter_valid && valid && !ui[37] && !mic && music && !ui[49] && !plot[647] &&
  !(|mute_sources) && !plot[646] && !busy && !fault && !ui[26];
 // x walks the visible row and returns to zero in blank. Seed each local
 // quotient before its drawing region so the RGB/sync latency stays put.
 reg [3:0] band_q,progress_q;reg [5:0] band_r;
 reg [4:0] meter_q,meter_r;reg [3:0] progress_r;
 always @(posedge clk)begin
  if(!rst_n)begin band_q<=0;band_r<=0;meter_q<=0;meter_r<=0;progress_q<=0;progress_r<=0;end
  else begin
   if(x==31)begin band_q<=0;band_r<=0;meter_q<=0;meter_r<=0;end
   else if(x>=32 && x<607)begin
    if(band_r==35)begin band_r<=0;band_q<=band_q+1'b1;end else band_r<=band_r+1'b1;
    if(meter_r==23)begin meter_r<=0;meter_q<=meter_q+1'b1;end else meter_r<=meter_r+1'b1;
   end
   if(x==431)begin progress_q<=0;progress_r<=0;end
   else if(x>=432 && x<599)begin
    if(progress_r==11)begin progress_r<=0;progress_q<=progress_q+1'b1;end else progress_r<=progress_r+1'b1;
   end
  end
 end
 wire [7:0] progress_cell={progress_q,progress_r};
 wire [9:0] meter={meter_q,meter_r};
 wire [9:0] band={band_q,band_r};wire [7:0] height=plot[512+band[9:6]*8+:8];
 wire [7:0] scaled_height=music_plot ? (height>>1)+(height>>2):(height>>1)+(height>>3);
 wire [7:0] peak_height=plot[band[9:6]*8+:8];
 wire [7:0] scaled_peak=music_plot ? (peak_height>>1)+(peak_height>>2):(peak_height>>1)+(peak_height>>3);
 wire [9:0] peak_y=chart_bottom-{2'b0,scaled_peak};
 wire [3:0] peak_band=plot[131:128];
 // Stable snapshot: fetch a pixel ahead of the cell
 reg [4:0] wave_q;reg [4:0] wave_r;
 always @(posedge clk)begin
  if(!rst_n || x==30)begin wave_q<=0;wave_r<=0;end
  else if(x>=31 && x<607)begin
   if(wave_r==17)begin wave_r<=0;wave_q<=wave_q+1'b1;end else wave_r<=wave_r+1'b1;
  end
 end
 wire [4:0] fetch_index=music_plot ? wave_q+(wave_r==17):x[8:4]-5'd3;
 assign wave_address=fetch_index;
 wire signed [6:0] fetched_sample=$signed(wave_data);
 reg signed [6:0] sample,previous_sample;
 always @(posedge clk)begin
  if(!rst_n)begin sample<=0;previous_sample<=0;end
  else if(music_plot ? (x>=31 && x<=589 && wave_r==0):(x>=63 && x<=559 && x[3:0]==15))begin
   sample<=fetched_sample;
   previous_sample<=(music_plot ? x==31:x==63) ? fetched_sample:sample;
  end
 end
 wire signed [10:0] wy=(music_plot ? 11'sd256:11'sd248)-$signed(sample),py=(music_plot ? 11'sd256:11'sd248)-$signed(previous_sample);
 reg [23:0] graph,ink;reg active,override;reg [7:0] line;reg [9:0] xx;reg [5:0] yy;reg [1:0] size;reg [8:0] gid;
 function [8:0] digit;input [3:0] n;begin digit=`B_G_0030+n;end endfunction
 always @*begin
  graph=BG;ink=TEXT;active=0;override=0;line=0;xx=x-24;yy=0;size=1;gid=0;
  if(x>=16 && x<624 && y>=8 && y<80)graph=24'hffffff;
  if(x>=32 && x<608 && y>=160 && y<=(music_plot ? 368:336))begin
   graph=24'h172b3b;
   if(y==160 || (music_plot ? (y==208 || y==256 || y==304):(y==200 || y==240 || y==280)) || band[5:0]==0)graph=24'h2a3b48;
   if(!wave && (valid || (music_plot && history_filled!=0)) && band[5:0]<30 && y>=chart_bottom-scaled_height && y<chart_bottom)
    graph=held ? AMBER:y<200 ? 24'he76f61:y<240 ? 24'heab45d:24'h42bfc7;
   if(!wave && (valid || (music_plot && history_filled!=0)) && band[5:0]<30 && scaled_peak!=0 && y>=peak_y && y<peak_y+2)
    graph=held ? AMBER:band[9:6]==peak_band ? 24'hffd27a:24'heaf5ed;
   if(y==chart_bottom)graph=AXIS;
   if(wave && (music_plot || x>=64 && x<576))begin
    if(x[5:0]==0 || y==200 || y==240 || y==280)graph=AXIS;
    if(valid && (y==wy || y==wy+1 || ((music_plot ? wave_r==1:x[3:0]==0) && y>=(wy<py ? wy:py) && y<=(wy>py ? wy:py))))graph=held ? AMBER:EDGE;
   end
  end
  if(spec_area)begin graph=spec_rgb;active=0;override=0;end
  // History: old -> new across x, low -> high up y
  // Axis labels stay outside the 160px data area even while valid is low.
  if(spec_eligible && x>=32 && x<608 && y>=352 && y<370)begin
   graph=y==352 ? AXIS:BG;
   if(y>=354)begin
    active=1;override=0;size=0;yy=y-354;ink=TEXT;
    if(x>=32 && x<64)begin line=`B_HISTORY_AXIS;xx=x-32;end
    else if(x>=240 && x<416)begin line=`B_BAND_ORDER;xx=x-240;end
    else if(x>=560 && x<608)begin line=`B_NEW_DATA_AXIS;xx=x-560;end
    else active=0;
   end
  end
  if(music_plot && !history_view && !wave && volume_mode==0 && x>=32 && x<608 && y>=354 && y<370)begin
   graph=BG;active=1;override=1;size=0;yy=y-354;ink=TEXT;
   if(x>=34 && x<66)begin xx=x-34;gid=xx<16 ? digit(9):digit(4);end
   else if(x>=170 && x<218)begin xx=x-170;gid=xx<16 ? digit(4):xx<32 ? digit(7):digit(0);end
   else if(x>=314 && x<362)begin xx=x-314;gid=xx<16 ? digit(8):xx<32 ? digit(9):digit(0);end
   else if(x>=450 && x<514)begin xx=x-450;gid=xx<16 ? digit(3):xx<32 ? digit(4):digit(0);end
   else begin active=0;override=0;end
  end
  // Separate card for the horizontal meter
  if(x>=24 && x<616 && (music_plot ? (y>=372 && y<=433):(y>=340 && y<=401)))graph=24'hffffff;
  if(x>=32 && x<608 && (music_plot ? (y>=408 && y<431):(y>=376 && y<399)) && meter[4:0]<20)begin
   graph=meter_active ? 24'h263e4e:24'hd6ddd8;
   if(rec_page && (rec_state==3 || rec_state==4))begin
    graph=24'h263e4e;
    if(meter[9:5]<ui[89:85]) graph=meter[9:5]>=18 ? 24'hebbd66:24'h36cbb5;
   end else if(meter_active && meter[9:5]<meter_level)
    graph=held ? AMBER:meter_clipped && meter[9:5]==23 ? 24'hc23c39:meter[9:5]>=18 ? 24'hebbd66:24'h36cbb5;
  end
  if(meter_active && meter_peak!=0 && x>=32 && x<608 && meter[9:5]+1'b1==meter_peak &&
   meter[4:0]<20 && (music_plot ? (y>=403 && y<407):(y>=371 && y<375)))graph=held ? AMBER:TEXT;
  if(x>=24 && x<616)begin
   if(y>=14 && y<46)begin active=1;line=`B_TITLE;size=2;yy=y-14;ink=24'h1e5a7a;end
   if(y>=53 && y<77)begin active=1;line=`B_P0+page;yy=y-53;ink=24'h1e5a7a;end
   // Waiting/loading still need a label. Once music or record playback
   // starts, hide its progress text and bar.
   if(x>=432 && x<608 && y>=53 && y<69)begin
    active=!progress_state[1];size=0;xx=x-432;yy=y-53;
    line=progress_state==1 ? `B_PROG_WAIT:`B_PROG_NONE;
    ink=TEXT;
   end
   if(x>=432 && x<600 && y>=72 && y<77)begin
    active=0;
    if(!progress_state[1] && progress_cell[3:0]<10)graph=24'hd6ddd8;
   end
   if(y>=84 && y<108)begin
    active=1;line=fault ? `B_FAULT:busy ? `B_BUSY:mic ? `B_MIC:!music ? `B_NOMUSIC:ui[49] ? `B_PAUSE:`B_PLAY;yy=y-84;
    ink=fault ? 24'hb32020:busy || ui[49] || mic ? 24'had5922:TEXT;
   end
   if(!ui[16] && !fault && y>=84 && y<108)begin
    line=ui[136] ? `B_BOOT_CHECK:`B_BOOT_PREP;size=0;xx=x-24;
    if(x>=104 && x<136)begin override=1;gid=x<120 ? digit(ui[135:132]>=10 ? 1:0):digit(ui[135:132]>=10 ? ui[135:132]-10:ui[135:132]);end
   end
   if(y>=114 && y<130)begin active=1;line=`B_MUTE0+mute_sources;size=0;yy=y-114;ink=mute_sources!=0 ? 24'had5922:24'h2b9b8c;end
   if(y>=136 && y<152)begin active=1;override=0;line=reason;size=0;xx=x-24;yy=y-136;ink=fault ? 24'hb32020:effective_hold || paused || waiting || wave || mic ? 24'had5922:24'h167b6e;
    if(music_source && !history_view && !wave && (reason==`B_SPEC_LIVE || reason==`B_SPEC_HELD || reason==`B_SPEC_PAUSED || reason==`B_SPEC_WAIT || reason==`B_SPEC_PREPARE) && x<56)begin
     override=1;gid=x<40 ? `B_G_9891:`B_G_8C31;
    end
   end
   if(music_plot ? (y>=376 && y<400):(y>=344 && y<368))begin
    active=1;yy=music_plot ? y-376:y-344;
    line=fault || busy || ui[26] ? `B_LEVEL_WAIT:ui[47] ? `B_LEVEL_VOICE:mic ? `B_LEVEL_MIC:
     !music ? `B_LEVEL_NONE:ui[49] || plot[647] ? `B_LEVEL_PAUSE:(|mute_sources) || plot[646] ? `B_LEVEL_MUTE:
     !meter_active ? `B_LEVEL_WAIT:held ? `B_LEVEL_HOLD:ui[36] ? `B_LEVEL_RIGHT:`B_LEVEL_LEFT;
    ink=meter_active ? (held ? 24'had5922:24'h167b6e):TEXT;
    if(x>=408)begin line=`B_LEVEL_RANGE;size=0;xx=x-408;yy=music_plot ? y-380:y-348;active=music_plot ? (y>=380 && y<396):(y>=348 && y<364);ink=TEXT;end
   end
   if((!music_plot && y>=407 && y<431) || (music_plot && (voice!=0 || ui[77:76]!=0 || fault) && y>=114 && y<130))begin
    active=1;yy=music_plot ? y-114:y-407;size=music_plot ? 0:1;
    line=fault ? `B_FAULT:ui[77:76]!=0 ? (ui[77:76]==1 ? `B_PREP_WAIT:ui[70] ? `B_PREP_MIC:ui[69] ? `B_PREP_HOLD:ui[71] ? `B_PREP_MUTE:ui[72] ? `B_PREP_AUTO:(|ui[75:73]) ? `B_PREP_ASW:`B_PREP_READY):volume_mode!=0 ? `B_VOL_HINT:voice==1 ? `B_WARM:voice==2 ? `B_LISTEN:voice==4 ? `B_PROCESS:
     voice==5 ? (last_command==1 && !ui[44] ? (page==9 ? `B_NEXTEND:`B_NEXTWAIT):`B_EXEC0+last_command):voice==6 ? (ui[81:78]!=0 ? `B_VFAIL0+ui[81:78]:ui[46] ? `B_MICFAIL:`B_RETRY):mic ? `B_MICREADY:ui[25:22]>=10 ? `B_EXTRA_HINT0+(ui[25:22]-10):`B_HINT0+ui[25:22];
    ink=voice==2 ? 24'h2b9b8c:fault ? 24'hb32020:TEXT;
   end
   if(y>=440 && y<456)begin
    active=1;line=`B_AUTO7_0+(auto_reason<=10 ? auto_reason:4'd0);size=0;yy=y-440;
    ink=auto_reason==1 ? 24'h167b6e:auto_reason==9 ? 24'hb32020:auto_reason>1 ? 24'had5922:24'h6f8290;
    if(auto_reason==1 && x>=88 && x<120)begin
     override=1;gid=x<104 ? digit(auto_seconds>=10 ? 1:0):digit(auto_seconds>=10 ? auto_seconds-10:auto_seconds);
    end
   end
   if(y>=463 && y<479)begin
    active=1;line=volume_mode!=0 ? `B_VOL_FOOT:music && !mic ? `B_VOL_NORMAL:`B_FOOT;size=0;yy=y-463;
    if(volume_mode==0 && music && !mic && x>=264 && x<280)begin override=1;gid=digit(volume_target);end
   end
   if(rec_page && y>=84 && y<108)begin
    override=0;size=1;xx=x-24;ink=rec_state==9 ? 24'hb32020:TEXT;
    line=rec_state==9 ? `B_R_FAIL:rec_state==3 ? `B_R_RECORD:rec_state==4 ? `B_R_SAVE:
     rec_state==6 ? `B_PLAY:rec_state==10 ? (ui[20] ? `B_R_SAVE:`B_R_SAVED):rec_state==1 ? `B_MICREADY:`B_BUSY;
   end
   if(rec_page && y>=407 && y<431)begin line=`B_R_KEYS;ink=TEXT;end
   // Volume card borrows the plot rectangle
   if(volume_mode!=0 && x>=32 && x<608 && y>=160 && y<=(music_plot ? 369:336))begin
    graph=24'hffffff;active=0;override=0;ink=TEXT;xx=x-64;yy=0;size=0;
    if(x<35 || x>=605 || y<163 || y>=334)graph=24'h42a6d8;
    if(y==204 && x>=64 && x<576)graph=24'he1e9e9;
    if(y>=174 && y<198 && x>=64 && x<432)begin
     active=1;line=volume_mode==1 ? `B_VOL_RELEASE:volume_mode==3 ? `B_VOL_EXIT:`B_VOL_TITLE;
     size=1;yy=y-174;ink=24'h1e5a7a;
    end
    if(y>=174 && y<190 && x>=448 && x<496)begin
     active=1;line=`B_VOL_VALUE;size=2;xx=x-448;yy=y-174;override=1;ink=24'h167b6e;
     gid=x<464 ? digit(volume_target):x<480 ? `B_G_002F:digit(9);
    end
    if(y>=208 && y<224 && x>=64 && x<592)begin
     active=1;size=0;yy=y-208;
     line=(|mute_sources) || plot[646] ? `B_VOL_MUTE:ui[49] || plot[647] ? `B_VOL_PAUSE:
      volume_target==0 ? `B_VOL_ZERO:pending_volume ? `B_VOL_RAMP:volume_target==9 ? `B_VOL_MAX:`B_VOL_READY;
    end
    if(y>=294 && y<310 && x>=64 && x<592)begin active=1;line=`B_VOL_KEYS;size=0;yy=y-294;ink=24'h1e5a7a;end
    if(y>=316 && y<332 && x>=64 && x<592)begin active=1;line=`B_VOL_BACK;size=0;yy=y-316;end
   end
  end
 end
 b_text #(.LABELS("text_b_labels.dath"),.FONT("v6_b_font0"),.FONT1("v6_b_font1"),.FONT2("v6_b_font2"),.FONT_WORDS(`B_FONT_WORDS),.LABEL_WORDS(`B_LABEL_WORDS))
 text_engine(clk,rst_n,hs,vs,de,graph,ink,active,line,xx,yy,size,override,gid,oh,ov,od,rgb);
endmodule
