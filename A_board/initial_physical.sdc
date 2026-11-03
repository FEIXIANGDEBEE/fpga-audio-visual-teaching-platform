create_clock -name SYS -period 20.000 [get_ports {sys_clk}]
derive_clocks
set_false_path -from [get_ports {sys_rst_n uart_rx key1 key2 key3 sw1 sw2 sw3 sw4 r_data[*] r_clk r_valid f_ready audio_bclk audio_lrck audio_data}]
set_false_path -to [get_regs {media/observer/observed_m}]
set_false_path -to [get_regs {media/mem_ready_meta}]
set_false_path -to [get_regs {media/memory/req0_s1}]
set_false_path -to [get_regs {media/memory/client0/rsp_sync1}]
set_false_path -to [get_regs {media/picture_fx/brightness_m[*]}]
set_false_path -to [get_regs {media/picture_fx/contrast_m[*]}]
set_false_path -to [get_regs {media/settings_snapshot/request_sync[0]}]
set_false_path -to [get_regs {media/settings_snapshot/ack_sync[0]}]
set_false_path -to [get_regs {media/fx_configuration/request_sync[0]}]
set_false_path -to [get_regs {media/fx_configuration/ack_sync[0]}]
set_false_path -to [get_regs {media/fade/commit_sync1}]
set_false_path -to [get_regs {media/fade/done_sync1}]
set_false_path -to [get_regs {media/fade/start_sync1}]
set_false_path -to [get_regs {media/audio_snapshot/request_sync[0]}]
set_false_path -to [get_regs {media/audio_snapshot/ack_sync[0]}]
set_false_path -to [get_regs {media/geometry_snapshot/request_sync[0]}]
set_false_path -to [get_regs {media/geometry_snapshot/ack_sync[0]}]
set_false_path -to [get_regs {media/layer_fault_diag/meta}]
set_false_path -to [get_regs {media/safe_m1}]
set_false_path -to [get_regs {media/layer_snapshot/request_sync[0]}]
set_false_path -to [get_regs {media/layer_snapshot/ack_sync[0]}]
set_false_path -to [get_regs {media/layers/fault_m1}]
set_false_path -to [get_regs {media/layers/prefetch/pb1[*]}]
set_false_path -to [get_regs {media/layers/prefetch/pf1[*]}]
set_false_path -to [get_regs {media/layer_diag_snapshot/request_sync[0]}]
set_false_path -to [get_regs {media/layer_diag_snapshot/ack_sync[0]}]
set_max_delay -datapath_only -from [get_regs {media/memory/client0/m_req_addr[*] media/memory/client0/m_req_data[*] media/memory/client0/m_req_dm[*] media/memory/client0/m_req_write}] -to [get_regs {media/memory/req_addr_r[*] media/memory/req_data_r[*] media/memory/req_dm_r[*] media/memory/req_write_r}] 23.7
set_max_delay -datapath_only -from [get_regs {media/memory/rsp0_data[*] media/memory/rsp0_error}] -to [get_regs {media/memory/client0/rsp_data[*] media/memory/client0/rsp_error}] 19.7
set_max_delay -datapath_only -from [get_regs {media/observer/observed_id[*]}] -to [get_regs {media/observer/committed}] 19.7
set_max_delay -datapath_only -from [get_regs {display_base[*]}] -to [get_regs {media/reader/frame_base[*]}] 39.7
set_max_delay -datapath_only -from [get_regs {display_id[*]}] -to [get_regs {media/reader/frame_id[*]}] 39.7
set_max_delay -datapath_only -from [get_regs {display_base_crc[*]}] -to [get_regs {media/reader/frame_crc[*]}] 39.7
set_max_delay -datapath_only -from [get_regs {display_swap}] -to [get_regs {media/reader/swap_p1}] 39.7
set_max_delay -datapath_only -from [get_regs {media/reader/clean_epoch}] -to [get_regs {media/reader/clean1}] 19.7
set_max_delay -datapath_only -from [get_regs {media/reader/frame_epoch}] -to [get_regs {media/reader/epoch1}] 19.7
set_max_delay -datapath_only -from [get_regs {media/reader/rflush}] -to [get_regs {media/reader/rflush_m1}] 19.7
set_max_delay -datapath_only -from [get_regs {media/reader/frame_base[*]}] -to [get_regs {media/reader/base_q[*]}] 19.7
set_max_delay -datapath_only -from [get_regs {media/reader/read_errors[*]}] -to [get_regs {media/reader/read_fault_p1}] 19.7
set_max_delay -datapath_only -from [get_regs {media/reader/fifo/fifo_core/wr_to_rd_cross_inst/primary_addr_gray_reg[*]}] -to [get_regs {media/reader/fifo/fifo_core/wr_to_rd_cross_inst/sync_r1[*]}] 19.7
set_max_delay -datapath_only -from [get_regs {media/reader/fifo/fifo_core/rd_to_wr_cross_inst/primary_addr_gray_reg[*]}] -to [get_regs {media/reader/fifo/fifo_core/rd_to_wr_cross_inst/sync_r1[*]}] 19.7
set_max_delay -datapath_only -from [get_regs {media/settings_snapshot/held_data[*]}] -to [get_regs {media/settings_snapshot/snapshot[*]}] 39.7
set_max_delay -datapath_only -from [get_regs {media/fx_configuration/held_data[*]}] -to [get_regs {media/fx_configuration/snapshot[*]}] 39.7
set_max_delay -datapath_only -from [get_regs {transition_base[*]}] -to [get_regs {media/reader/frame_new_base[*]}] 39.7
set_max_delay -datapath_only -from [get_regs {transition_crc[*]}] -to [get_regs {media/reader/frame_new_crc[*]}] 39.7
set_max_delay -datapath_only -from [get_regs {active_effect[*]}] -to [get_regs {media/reader/frame_mode[*]}] 39.7
set_max_delay -datapath_only -from [get_regs {swap_pending}] -to [get_regs {media/reader/pending_p1}] 39.7
set_max_delay -datapath_only -from [get_regs {media/audio_snapshot/held_data[*]}] -to [get_regs {media/audio_snapshot/snapshot[*]}] 19.7
set_max_delay -datapath_only -from [get_regs {media/geometry_snapshot/held_data[*]}] -to [get_regs {media/geometry_snapshot/snapshot[*]}] 39.7
set_max_delay -datapath_only -from [get_regs {media/layer_diag_snapshot/held_data[*]}] -to [get_regs {media/layer_diag_snapshot/snapshot[*]}] 19.7
set_max_delay -datapath_only -from [get_regs {media/layer_snapshot/held_data[*]}] -to [get_regs {media/layer_snapshot/snapshot[*]}] 39.7
set_max_delay -datapath_only -from [get_regs {media/layers/prefetch/frame_toggle}] -to [get_regs {media/layers/prefetch/epoch_m1}] 19.7
set_max_delay -datapath_only -from [get_regs {media/layers/prefetch/bg_ret_gray[*]}] -to [get_regs {media/layers/prefetch/rb1[*]}] 19.7
set_max_delay -datapath_only -from [get_regs {media/layers/prefetch/fg_ret_gray[*]}] -to [get_regs {media/layers/prefetch/rf1[*]}] 19.7
set_max_delay -datapath_only -from [get_regs {media/layers/prefetch/bg_tag[*] media/layers/prefetch/bg_epoch[*]}] -to [get_regs {media/layers/prefetch/pt_bg[*] media/layers/prefetch/pe_bg[*]}] 39.7
set_max_delay -datapath_only -from [get_regs {media/layers/prefetch/fg_tag[*] media/layers/prefetch/fg_epoch[*]}] -to [get_regs {media/layers/prefetch/pt_fg[*] media/layers/prefetch/pe_fg[*]}] 39.7
set_max_delay -datapath_only -from [get_regs {media/layers/frame_enable}] -to [get_regs {media/layers/prefetch/active}] 19.7
set_max_delay -datapath_only -from [get_regs {current_valid}] -to [get_regs {media/reader/en1 media/reader/en1_p}] 39.7
set_false_path -from [get_pins {media/video_clock/pll_inst.extlock}]
set_false_path -from [get_pins {media/memory/pll/pll_inst.extlock}]
set_false_path -from [get_pins {media/audio_clock/pll_inst.extlock}]
set_false_path -through [get_nets -hier {media/video_reset/arst_n}]
set_false_path -through [get_nets -hier {media/reader/fifo/fifo_rst}]
set_false_path -through [get_nets -hier {media/audio_reset_n}]
set_false_path -to [get_pins -hier {media/audio_reset/release_pipe_reg[0].sr media/audio_reset/release_pipe_reg[1].sr media/audio_reset/release_pipe_reg[2].sr media/video_reset/release_pipe_reg[0].sr media/video_reset/release_pipe_reg[1].sr media/video_reset/release_pipe_reg[2].sr}]
