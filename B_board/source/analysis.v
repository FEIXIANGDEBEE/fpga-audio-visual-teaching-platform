`timescale 1ns/1ps

module analysis(
 input wire clk,rst_n,mclk,audio_rst_n,sent_valid,input wire [31:0] sent_frame,input wire [6:0] sent_tag,
 input wire right,input wire [1:0] music_id,input wire music_valid,pause,
 input wire request_mic,hold_plot,clear_peak,input wire [3:0] page,
 input wire mic_valid,input wire [34:0] mic_data,input wire mic_alive,mic_warmed,
 input wire voice_enable,input wire [31:0] control_generation,
 output wire feature_pending,input wire feature_take,input wire [5:0] feature_address,output wire [7:0] feature_data,
 output wire [31:0] feature_sequence,source_generation,feature_drops,
 output wire active_mic,source_wait,output wire [31:0] source_discontinuities,source_clips,
 output reg record_mic,record_right,output reg [3:0] record_page,
 output reg [127:0] heights,output wire [2:0] waveform,output reg record_valid,
 output reg [31:0] record_window,output reg [1:0] record_music,
 output wire [31:0] windows,drops,errors,output wire [8:0] peak_bin,
 input wire level_mute,output wire [4:0] play_level,play_peak,output wire play_clipped,play_level_valid,
 output wire [31:0] voice_energy,voice_control,output wire voice_invalid,input wire [12:0] sent_volume,output reg [3:0] record_volume,
 input wire wave_read_clk,input wire [6:0] wave_read_address,output wire [6:0] wave_read_data,input wire [1:0] wave_locked_bank,
 input wire record_mode,output wire replay_observed,
 // A E7 switches[3:2]: weight PLAY/replay to match the heard filter
 // Keep MIC spectra raw
 input wire [1:0] filter_mode
);
 wire ready,valid;wire [51:0] data;reg [7:0] previous_gain_epoch;reg [3:0] play_volume,pending_volume;
 wire gain_changed=valid && (!data[39] || data[51:44]!=previous_gain_epoch);
 always @(posedge clk or negedge sys_audio_rst)
  if(!sys_audio_rst)begin previous_gain_epoch<=0;play_volume<=7;end
  else if(valid)begin previous_gain_epoch<=data[51:44];play_volume<=data[43:40];end
 wire sys_audio_rst;
 reset_sync reset(clk,rst_n && audio_rst_n,sys_audio_rst);
 scene_cdc_mailbox #(.WIDTH(52)) pcm(mclk,audio_rst_n,sent_valid && ready,{sent_volume,sent_tag,sent_frame},ready,,clk,sys_audio_rst,valid,data,1'b1);
 reg overflow;(* ASYNC_REG="TRUE" *)reg ov1,ov2;
 always @(posedge mclk or negedge audio_rst_n)if(!audio_rst_n)overflow<=0;else if(sent_valid && !ready)overflow<=1;
 always @(posedge clk or negedge sys_audio_rst)if(!sys_audio_rst)begin ov1<=0;ov2<=0;end else begin ov1<=overflow;ov2<=ov1;end
 wire fs,sv,sr,fb,fd,rv,rr,mixed;wire signed [15:0] sample;
 wire [31:0] fw,gen,base,crc,actual,werr,generation;wire channel;wire [6:0] tag;
 wire source_valid,source_abort;wire [31:0] source_frame,source_frame_gen;wire [6:0] source_tag;
 wire [2:0] source_context,result_context;wire [1:0] active_gain;wire [31:0] source_aborts;
 // Replay arrives on the PLAY path with its completed-frame tag;
 // it does not need another source state or CDC payload
 assign replay_observed=record_mode && data[35];
 wire wanted_mic=request_mic && !replay_observed;
 wire effective_pause=pause && !replay_observed;
 wire record_replay=record_page==9 && !record_mic;
 analysis_source source(clk,sys_audio_rst,wanted_mic,2'd1,valid,data[38:0],{effective_pause,music_id,right},mic_valid,mic_data,mic_alive,mic_warmed,
 source_valid,source_frame,source_tag,source_context,source_frame_gen,source_abort,active_mic,active_gain,source_generation,source_discontinuities,source_aborts,source_clips,source_wait,data[51:44],data[39],record_mode);
 scene_analysis_windows #(.V18_IDENTITY(1),.V22_SOURCE(1)) input_windows(clk,sys_audio_rst,source_valid,source_frame,active_mic ? 1'b0:right,
 fs,fw,sv,sample,sr,fb,fd,rv,rr,gen,base,crc,channel,actual,windows,drops,werr,generation,source_tag,tag,mixed,source_abort,source_context,source_frame_gen,result_context);
 wire bv,bl;wire [3:0] bi;wire [31:0] energy,ferr,latency,fft_window,peak_power,saturations;
 fft_spectrum #(.DATA_W(28),.LOG_BANDS(1)) fft(clk,sys_audio_rst,fs,fw,sv,sr,sample,fb,fd,fft_window,
 bv,bi,energy,bl,latency,1'b1,peak_bin,peak_power,saturations,ferr,result_context[2] ? 2'd0:filter_mode);
 voice_feature #(.DIAG_REPLAY(0)) feature_tap(.clk(clk),.rst_n(sys_audio_rst),.enable(voice_enable),
 .band_valid(bv),.band_last(bl),.band_index(bi),.band_power(energy),.task_context(result_context),
 .task_invalid(mixed || gen!=source_generation || !active_mic || !mic_alive || !mic_warmed || source_wait),
 .task_generation(gen),.task_window(fw),.live_generation(source_generation),.control_generation(control_generation),
 .clips(source_clips),.fft_errors(ferr),.saturations(saturations),.discontinuities(source_discontinuities),.window_errors(werr),
 .pending(feature_pending),.take(feature_take),.tx_address(feature_address),.tx_data(feature_data),.feature_sequence_out(feature_sequence),.latest_sequence(),.dropped(feature_drops),
 .replay_active(1'b0),.replay_begin(1'b0),.replay_byte(1'b0),.replay_commit(1'b0),.replay_index(4'd0),.replay_data(8'd0),.replay_energy(32'd0),
 .observe_energy(voice_energy),.observe_control(voice_control),.observe_invalid(voice_invalid));
 reg previous_hold;reg [31:0] minimum_window;reg [3:0] pending_page;
 reg [8:0] sample_index;reg start_map,fd_seen,map_done;
 wire map_busy,map_finished;wire [127:0] mapped;
 power_heights mapper(clk,sys_audio_rst,bv,bi,energy,start_map,mapped,map_busy,map_finished);
 assign rr=rv && map_done;
 assign errors=werr+ferr+{31'd0,ov2};
// Publish the whole record together; screen owns the vblank snapshot crossing.
 wire record_eligible=!mixed && gen==source_generation && !source_wait && fw>=minimum_window && pending_page==page &&
  (result_context[2] ? active_mic && wanted_mic && mic_alive && mic_warmed : !active_mic && tag[4] && !tag[2:0] &&
   (tag[3] ? replay_observed : page!=9 && !replay_observed && tag[6:5]==music_id && music_valid && !pause));
 wave_store wave_store(clk,sys_audio_rst,fs && fb,sv && sr && sample_index[3:0]==0,
  sample_index[8:4],sample[15:9],rr && !hold_plot && record_eligible,clear_peak,
  wave_locked_bank,waveform,wave_read_clk,wave_read_address,wave_read_data);
 play_level level_observer(clk,sys_audio_rst,fs && fb,sv && sr,sample,
  rr && record_eligible && !result_context[2] && !clear_peak,hold_plot,
  level_mute || effective_pause || wanted_mic || active_mic || !(music_valid || replay_observed) || source_wait || clear_peak || gain_changed,
  {page,music_id,right},play_level,play_peak,play_clipped,play_level_valid,fd && !fd_seen);
 always @(posedge clk or negedge sys_audio_rst)begin
  if(!sys_audio_rst)begin sample_index<=0;start_map<=0;fd_seen<=0;map_done<=0;
   heights<=0;record_valid<=0;record_window<=0;record_music<=0;record_mic<=0;record_right<=0;record_page<=0;previous_hold<=0;minimum_window<=0;pending_page<=0;record_volume<=7;pending_volume<=7;end
  else begin
   start_map<=0;previous_hold<=hold_plot;
   if(previous_hold && !hold_plot)begin minimum_window<=windows+1'b1;record_valid<=0;end
   if(clear_peak)begin record_valid<=0;heights<=0;end
   if(fs && fb)begin pending_page<=page;pending_volume<=play_volume;end
   if(!fd)fd_seen<=0;
   if(fs && fb)sample_index<=0;
   if(sv && sr)begin
    sample_index<=sample_index+1'b1;
   end
   if(fd && !fd_seen)begin fd_seen<=1;start_map<=1;map_done<=0;end
   if(map_finished)map_done<=1;
   if(rr)begin
    map_done<=0;
    if(!hold_plot)begin
     if(record_eligible)begin
      heights<=mapped;record_valid<=1;record_window<=fw;record_music<=tag[6:5];record_mic<=result_context[2];record_right<=channel;record_page<=pending_page;record_volume<=pending_volume;
     end else record_valid<=0;
    end
   end
   if(!hold_plot && ((!active_mic && (record_replay ? !replay_observed:(!music_valid || pause || record_music!=music_id))) || record_mic!=active_mic || (!active_mic && record_right!=right) || record_page!=page))record_valid<=0;
  end
 end
endmodule
