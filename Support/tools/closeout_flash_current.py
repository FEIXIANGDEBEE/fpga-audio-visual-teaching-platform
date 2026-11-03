"""Publish current Flash outcome; keep offline snapshots and folders intact."""
from pathlib import Path
import json,shutil
from datetime import datetime
from zoneinfo import ZoneInfo
ROOT=Path(__file__).resolve().parents[1]
read=lambda p:json.loads(Path(p).read_text(encoding='utf-8-sig'))
out=Path(read(ROOT/'reports/FLASH_SESSION.json')['path']);result=read(out/'result.json')
assert result['pass'] and result['configuration_flash_pair_pass'] and result['sram_restored']
assert result['startup']['pass'] and result['serial_closed'] and not result['TF_written']
for board in 'ab':
    row=result['boards'][board]
    assert row['full_image_differences']==row['preserved_tail_differences']==0
    assert row['sram_restore_attempts'][-1]['differences']==0
    assert row['native_verified'] or row.get('write_skipped')
pair=read(ROOT/'reports/FINAL_PAIR.json')
pair.update(phase='FLASH_VERIFIED_SRAM_RESTORED_USER_PHYSICAL_TEST_PENDING',hardware_accessed=True,
    SRAM_programmed=True,Flash_written=any(result['boards'][b]['programmed'] for b in 'ab'),
    host_TF_accessed=False,TF_written=False,flash_result=str(out/'result.json'),configuration_flash_pair_pass=True,
    cold_boot_verified=False,user_screen_acceptance=False,external_listening_observed=False,serial_closed=True,
    hardware_identity=dict(uart=result['uart'],baudrate=result['baudrate'],jtag=result['jtag']),
    updated_at=datetime.now(ZoneInfo('Asia/Shanghai')).isoformat(),packaging='Deferred by user until physical testing passes; no new ZIP/RAR created')
pair.pop('TF_accessed',None)
for board in 'ab':
    pair['boards'][board].update(configuration_flash_verified=True,
        flash_programmed_this_session=result['boards'][board]['programmed'],
        flash_write_skipped=result['boards'][board].get('write_skipped'),
        sram_masked_differences=result['boards'][board]['sram_restore_attempts'][-1]['differences'],
        hardware_acceptance='Short digital startup passed; real screen/audio/controls/cold boot pending user')
(ROOT/'ACTIVE_PAIR.json').write_text(json.dumps(pair,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
state=read(ROOT/'reports/STATE.json')
state.update(status='FLASH_VERIFIED_USER_PHYSICAL_TEST_PENDING',hardware_accessed=True,flash_result=str(out/'result.json'),
    configuration_flash_pair_pass=True,SRAM_restored=True,TF_written=False,serial_closed=True,cold_boot_verified=False,
    archive_present=False,packaging='WAIT_USER_TEST_PASS',active_pair='ACTIVE_PAIR.json')
(ROOT/'reports/STATE.json').write_text(json.dumps(state,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
rows=[]
for b in 'ab':
    row=result['boards'][b]
    rows.append(f"| {b.upper()} | {result['uart'][b]} / {result['jtag'][b]} | {row['before']['bytes']:,} | {'写入并原厂校验通过' if row['programmed'] else '完整镜像相同，跳过擦写'} | {row['full_image_differences']} | {row['preserved_tail_differences']} | {row['sram_restore_attempts'][-1]['differences']} |")
text='''# 本次双板配置 Flash 固化交接

2026-11-03，用户明确要求“开发板已经连接，开始直接固化flash我测试”。本次 A seed7 / B seed5 配对的配置 Flash 已完成验证；B 实际写入并通过原厂 verify，A 整片镜像已等于目标，跳过无必要擦写。两板均完成独立全片读回、尾区比较及目标 SRAM 恢复/掩码读回。

| 板 | UART / JTAG | 完整写前备份字节 | 固化动作 | 整片字节差异 | 尾区字节差异 | SRAM 掩码差异 |
|---|---|---:|---|---:|---:|---:|
'''+ '\n'.join(rows)+f'''

写前后完整镜像、原厂日志、目标 SVF、身份矩阵及恢复记录位于 `{out}`。结果：`{out/'result.json'}`。既有离线身份记录 FINAL_PAIR.json 保持原样；当前硬件配对见 ACTIVE_PAIR.json。

每板配置载荷 {result['boards']['a']['payload_bytes']} 字节，擦除包络 {result['boards']['a']['erase_boundary']} 字节，包络外 {result['boards']['a']['preserved_tail_bytes']} 字节保持。所有读回异常原始尝试保留；全同值无效读回仅做只读重新识别/重试，不重复擦写。

短启动数字检查通过：两板 READY、14 个目录项有效、链路/图像/分析错误计数为零，I2S 前进，PCM 错误不增长，录音所有权释放。没有执行录音或 TF 写入，串口已关闭。

当前运行状态来自目标 SRAM 恢复，尚未观测独立断电启动。请将两板彻底断电再上电，确认 USB 等连接没有继续给板供电，再测试画面、左右声道、暂停/继续/静音、实体按键/遥控与录音。低功耗在第 4 页正常音乐下，通过“分析 → 分析视图 → 节能”检查正常→节能→恢复；B 屏休眠无信号为预期，恢复画面/听音和功率读数由操作者观察。

遵照用户“测试通过再打包”的要求，本次未生成 ZIP/RAR，原始交付文件夹保留不动。真实屏幕、听音、实体操作、麦克风/录音保存及独立冷启动仍待用户验收。
'''
(ROOT/'FLASH_HANDOFF.md').write_text(text,encoding='utf-8')
prefix='> 2026-11-03 后续固化：**本次 A seed7 / B seed5 的配置 Flash 已验证，B 写入并通过原厂校验，A整片相同跳过擦写；两板全片/尾区零差异、精确 SRAM 恢复及短启动数字检查通过。** TF未写，串口已关闭；独立断电启动和真实视听/操作待用户测试。测试通过前暂不打包。[Flash交接](FLASH_HANDOFF.md) · [当前硬件配对](ACTIVE_PAIR.json)。下方离线记录保留其原时点。\n\n'
for name in ('README.md','交接_20261103.md'):
    p=ROOT/name;s=p.read_text(encoding='utf-8-sig')
    if not s.startswith('> 2026-11-03 后续固化：'):p.write_text(prefix+s,encoding='utf-8')
print('FLASH_CLOSEOUT_PASS',ROOT/'FLASH_HANDOFF.md')
