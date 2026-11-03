create_clock -name SYS -period 20.000 [get_ports {sys_clk}]
derive_clocks
set_false_path -from [get_ports {sys_rst_n uart_rx key1 key2 key3 sw1 sw2 sw3 sw4 f_data[*] f_clk f_valid r_ready sd_miso mic_sd}]
create_clock -name MCLK -period 81.333333 [get_ports {audio_mclk}]
set_false_path -to [get_regs {screen/snapshot/request_sync[0]}]
set_false_path -to [get_regs {screen/snapshot/ack_sync[0]}]
set_false_path -to [get_regs {microphone/hb1}]
set_false_path -to [get_regs {microphone/samples/ack1}]
set_false_path -to [get_regs {microphone/samples/req1}]
set_false_path -to [get_regs {microphone/diagnostics/request_sync[0]}]
set_false_path -to [get_regs {microphone/diagnostics/ack_sync[0]}]
set_false_path -to [get_regs {active_m}]
set_false_path -to [get_regs {uf_m}]
set_false_path -to [get_regs {banks/guard/hb1}]
set_false_path -to [get_regs {banks/ab1}]
set_false_path -to [get_regs {banks/r01}]
set_false_path -to [get_regs {banks/r11}]
set_false_path -to [get_regs {banks/commands/ack1}]
set_false_path -to [get_regs {banks/commands/req1}]
set_false_path -to [get_regs {analysis/pcm/ack1}]
set_false_path -to [get_regs {analysis/pcm/req1}]
set_false_path -to [get_regs {analysis/ov1}]
set_false_path -to [get_regs {banks/playback_snapshot/request_sync[0]}]
set_false_path -to [get_regs {banks/playback_snapshot/ack_sync[0]}]
set_false_path -to [get_regs {replay_counter/snapshot/request_sync[0]}]
set_false_path -to [get_regs {replay_counter/snapshot/ack_sync[0]}]
set_false_path -to [get_regs {screen/audio_snapshot/request_sync[0]}]
set_false_path -to [get_regs {screen/audio_snapshot/ack_sync[0]}]
set_false_path -to [get_regs {recorder/play_commands/ack1}]
set_false_path -to [get_regs {recorder/play_commands/req1}]
set_false_path -to [get_regs {recorder/stop_meta}]
set_false_path -to [get_regs {banks/borrow_meta}]
set_false_path -to [get_regs {history_ready_meta}]
set_false_path -to [get_regs {banks/volume_commands/ack1}]
set_false_path -to [get_regs {banks/volume_commands/req1}]
set_false_path -to [get_regs {banks/volume_snapshot/request_sync[0]}]
set_false_path -to [get_regs {banks/volume_snapshot/ack_sync[0]}]
set_max_delay -datapath_only -from [get_regs {screen/snapshot/held_data[*]}] -to [get_regs {screen/snapshot/snapshot[*]}] 39.7
set_max_delay -datapath_only -from [get_regs {microphone/samples/held[*]}] -to [get_regs {microphone/samples/ddata[*]}] 19.7
set_max_delay -datapath_only -from [get_regs {microphone/diagnostics/held_data[*]}] -to [get_regs {microphone/diagnostics/snapshot[*]}] 19.7
set_max_delay -datapath_only -from [get_regs {banks/commands/held[*]}] -to [get_regs {banks/commands/ddata[*]}] 81.0
set_max_delay -datapath_only -from [get_regs {analysis/pcm/held[*]}] -to [get_regs {analysis/pcm/ddata[*]}] 19.7
set_max_delay -datapath_only -from [get_regs {banks/playback_snapshot/held_data[*]}] -to [get_regs {banks/playback_snapshot/snapshot[*]}] 19.7
set_max_delay -datapath_only -from [get_regs {replay_counter/snapshot/held_data[*]}] -to [get_regs {replay_counter/snapshot/snapshot[*]}] 19.7
set_max_delay -datapath_only -from [get_regs {screen/audio_snapshot/held_data[*]}] -to [get_regs {screen/audio_snapshot/snapshot[*]}] 39.7
set_max_delay -datapath_only -from [get_regs {recorder/play_commands/held[*]}] -to [get_regs {recorder/player/command}] 81.0
set_max_delay -datapath_only -from [get_regs {banks/volume_commands/held[*]}] -to [get_regs {banks/volume_commands/ddata[*]}] 81.0
set_max_delay -datapath_only -from [get_regs {banks/volume_snapshot/held_data[*]}] -to [get_regs {banks/volume_snapshot/snapshot[*]}] 19.7
set_max_delay -datapath_only -from [get_regs {banks/fifo0/rg[*]}] -to [get_regs {banks/fifo0/rg1[*]}] 19.7
set_max_delay -datapath_only -from [get_regs {banks/fifo0/wg[*]}] -to [get_regs {banks/fifo0/wg1[*]}] 19.7
set_max_delay -datapath_only -from [get_regs {banks/fifo1/rg[*]}] -to [get_regs {banks/fifo1/rg1[*]}] 19.7
set_max_delay -datapath_only -from [get_regs {banks/fifo1/wg[*]}] -to [get_regs {banks/fifo1/wg1[*]}] 19.7
set_false_path -from [get_ports {ir_rx}]
set_false_path -from [get_pins {screen/pll/pll_inst.extlock}]
set_false_path -through [get_nets -hier {banks/guard/reset_source}]
set_false_path -through [get_nets -hier {banks/bank_run[*]}]
set_false_path -through [get_nets -hier {audio_rst_n}]
set_false_path -through [get_nets -hier {banks/wrst_n}]
set_false_path -through [get_nets -hier {recorder/srst_n}]
set_false_path -through [get_nets -hier {recorder/drst_n}]
set_false_path -to [get_pins -hier {analysis/reset/release_pipe_reg[0].sr analysis/reset/release_pipe_reg[1].sr analysis/reset/release_pipe_reg[2].sr banks/guard/ar/release_pipe_reg[0].sr banks/guard/ar/release_pipe_reg[1].sr banks/guard/ar/release_pipe_reg[2].sr banks/guard/heartbeat_reset/release_pipe_reg[0].sr banks/guard/heartbeat_reset/release_pipe_reg[1].sr banks/guard/heartbeat_reset/release_pipe_reg[2].sr banks/guard/wr/release_pipe_reg[0].sr banks/guard/wr/release_pipe_reg[1].sr banks/guard/wr/release_pipe_reg[2].sr banks/rreset0/release_pipe_reg[0].sr banks/rreset0/release_pipe_reg[1].sr banks/rreset0/release_pipe_reg[2].sr banks/rreset1/release_pipe_reg[0].sr banks/rreset1/release_pipe_reg[1].sr banks/rreset1/release_pipe_reg[2].sr banks/wreset0/release_pipe_reg[0].sr banks/wreset0/release_pipe_reg[1].sr banks/wreset0/release_pipe_reg[2].sr banks/wreset1/release_pipe_reg[0].sr banks/wreset1/release_pipe_reg[1].sr banks/wreset1/release_pipe_reg[2].sr eco_audio_reset/release_pipe_reg[0].sr eco_audio_reset/release_pipe_reg[1].sr eco_audio_reset/release_pipe_reg[2].sr eco_sys_reset/release_pipe_reg[0].sr eco_sys_reset/release_pipe_reg[1].sr eco_sys_reset/release_pipe_reg[2].sr microphone/heartbeat_reset/release_pipe_reg[0].sr microphone/heartbeat_reset/release_pipe_reg[1].sr microphone/heartbeat_reset/release_pipe_reg[2].sr microphone/mail_reset/release_pipe_reg[0].sr microphone/mail_reset/release_pipe_reg[1].sr microphone/mail_reset/release_pipe_reg[2].sr microphone/mic_reset/release_pipe_reg[0].sr microphone/mic_reset/release_pipe_reg[1].sr microphone/mic_reset/release_pipe_reg[2].sr recorder/replay_audio_reset/release_pipe_reg[0].sr recorder/replay_audio_reset/release_pipe_reg[1].sr recorder/replay_audio_reset/release_pipe_reg[2].sr recorder/replay_sys_reset/release_pipe_reg[0].sr recorder/replay_sys_reset/release_pipe_reg[1].sr recorder/replay_sys_reset/release_pipe_reg[2].sr screen/reset/release_pipe_reg[0].sr screen/reset/release_pipe_reg[1].sr screen/reset/release_pipe_reg[2].sr screen/source_reset/release_pipe_reg[0].sr screen/source_reset/release_pipe_reg[1].sr screen/source_reset/release_pipe_reg[2].sr}]
