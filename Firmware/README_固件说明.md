# A、B 板可烧录位流

- A 板：`A_board/A_scene_a.bit`；配套读回掩码：`A_board/A_scene_a.bmk`。
- B 板：`B_board/B_scene_b.bit`；配套读回掩码：`B_board/B_scene_b.bmk`。

器件：EG4S20BG256；工具：安路 TD 6.2.168116。`.bit` 是对应板的位流文件，`.bmk` 是配套读回掩码，不单独作为固件烧录。A、B 不可互换。

以上文件复制自本项目最终选中配对，复制后的 SHA-256 已与既有 `FINAL_PAIR.json`、`ACTIVE_PAIR.json` 身份记录核对。曾有双板配置 Flash 写入、校验和完整读回记录；这不是对当前接线或独立断电启动的实时观察。实际下载应先按板上连接识别 A/B。
