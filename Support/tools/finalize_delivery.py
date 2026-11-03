"""Seal the completed pair once, then verify one complete delivery archive."""
from pathlib import Path
import sys,json,re,shutil,os,hashlib,zipfile,datetime
from comment_review import ROOT,CACHE,write_json,files,spans,PRAGMA

assert not (ROOT/'reports/FINAL_PAIR.json').exists(), 'Final identities are recorded once; never silently reseal.'
selection=json.loads((ROOT/'reports/FINAL_SELECTION.json').read_text())
for board in ('a','b'):
    for seed in (3,5,7):
        for tag in (['pilot','final'] if board=='a' else ['final']):
            lane=CACHE/(f'route_a_{tag}_seed{seed}' if board=='a' else f'route_b_seed{seed}')
            assert any((lane/n).exists() for n in ('physical.json','STOP_route.json','STOP_place.json')),str(lane)
    zero=json.loads((ROOT/f'reports/ZERO_DIFF_{board.upper()}.json').read_text());assert zero['pass_']

bitdir=ROOT/'bitstream';bitdir.mkdir(exist_ok=True)
pair=dict(name='aaa_comment_rework_20261103',phase='OFFLINE_COMPLETE_USER_HARDWARE_ACCEPTANCE_PENDING',date='2026-11-03',timezone='Asia/Shanghai',tool='TD 6.2.168116',device='EG4S20BG256',source_root=str(ROOT),logic_changes=False,hardware_accessed=False,SRAM_programmed=False,Flash_written=False,TF_accessed=False,boards={})
resources={};changed_ids={};file_rows={}
for board in ('a','b'):
    label=board.upper();lane=Path(selection[board]);syn=Path(json.loads((ROOT/f'reports/SYNTHESIS_{label}.json').read_text())['path'])
    sign=json.loads((ROOT/f'reports/OFFLINE_SIGNOFF_{label}.json').read_text())
    assert Path(sign['build'])==lane and sign['pass'] and sign['conflicts']==sign['TNS_THS']==0
    phy=sign['physical'];assert phy['native_mslice']<=4820 and phy['setup_wns_ns']>0 and phy['hold_wns_ns']>0
    ids={}
    for ext in ('bit','bmk'):
        source=lane/f'artifacts/scene_{board}.{ext}';target=bitdir/f'{label}_scene_{board}.{ext}'
        assert source.exists();shutil.copy2(source,target)
        ids[ext]=dict(path=str(target),bytes=target.stat().st_size,sha256=hashlib.sha256(target.read_bytes()).hexdigest())
    area=(lane/'routed.area').read_text();native={}
    for key in ('lut','reg','bram9k','bram32k','dsp','pll'):
        native[key]=int(re.search(r'^\s*#'+key+r'\s+(\d+)',area,re.M)[1])
    resources[board]=native
    pair['boards'][board]=dict(implementation='NEW_SYNTHESIS_NEW_PHYSICAL_NEW_BITGEN',selected_seed=phy['place_seed'],source_snapshot=str(syn/'source'),synthesis=str(syn),routed_build=str(lane),files=ids,effective_sdc_sha256=hashlib.sha256((lane/'effective.sdc').read_bytes()).hexdigest(),MSLICE=phy['native_mslice'],resources=native,setup_ns=phy['setup_wns_ns'],hold_ns=phy['hold_wns_ns'],TNS=0,THS=0,conflicts=0,STA_coverage=100,offline_signoff=f'reports/OFFLINE_SIGNOFF_{label}.json',hardware_acceptance='NOT_OBSERVED')
    changed_ids[board]={};file_rows[board]=[]
    batches={}
    for p in sorted((ROOT/'reports/batches').glob(board+'_*.json')):
        for item in json.loads(p.read_text(encoding='utf-8'))['changes']:batches.setdefault(item['file'],[]).append((p.name,item['reason']))
    zero=json.loads((ROOT/f'reports/ZERO_DIFF_{label}.json').read_text())
    for item in zero['files']:
        p=ROOT/'source'/board/item['file'];data=p.read_bytes()
        if item['changed']:
            changed_ids[board][p.name]=dict(bytes=len(data),sha256=hashlib.sha256(data).hexdigest())
            meaningful=[m.group().decode('utf-8-sig').replace('\r','').replace('\n',' ') for m in spans(data,p.suffix=='.vhd') if not PRAGMA.search(m.group())]
            focus=(meaningful[0][:220] if meaningful else '删除重复的模块概述，直接阅读模块接口。').replace('|','/')
            record=dict(file=p.name,action='COMMENT_ONLY_EDIT',focus=focus,batches=[n for n,_ in batches.get(p.name,[])],reason='说明当前模块的实际契约、设计原因或生命周期；删除过时版本比较和重复概述。',noncomment_bytes_identical=True,tool_directives_identical=True)
        else:
            record=dict(file=p.name,action='EXACT_REUSE',focus='保留厂商生成说明/署名、卡与参数绑定、有效短注释；无描述性注释的文件不添加模板头。',noncomment_bytes_identical=True,tool_directives_identical=True)
        file_rows[board].append(record)
    # Editable project is a standalone copy of this board's final source snapshot.
    project=ROOT/'project'/board;project.mkdir(parents=True,exist_ok=True)
    for p in (ROOT/'source'/board).iterdir():
        q=project/'source'/p.name;q.parent.mkdir(exist_ok=True)
        if '.enc.' in p.name:os.link(p,q)
        else:shutil.copy2(p,q)
        if p.suffix in ('.dath','.hex','.vh'):shutil.copy2(p,project/p.name)
    shutil.copy2(ROOT/f'constraints/scene_{board}.adc',project/f'source/scene_{board}.adc')
    if board=='a':shutil.copytree(syn/'user_source',project/'user_source')
    text=(syn/f'scene_{board}_top.al').read_text();text=re.sub(r'(<Project\b[^>]*\bPath=")[^"]*',lambda m:m[1]+project.as_posix(),text,count=1)
    (project/f'scene_{board}_top.al').write_text(text,encoding='utf-8')
    shutil.copy2(lane/'effective.sdc',project/'final_effective.sdc')
    shutil.copy2(syn/'source_initial.sdc',project/'initial_physical.sdc')
    shutil.copy2(syn/'synthesis.tcl',project/'synthesis_recipe.tcl')
    # Validate new project references by existence without reopening opaque IP.
    for path in re.findall(r'<File Path="([^"]+)"',text):assert (project/path).is_file(),path

write_json(ROOT/'reports/SOURCE_FINAL_IDENTITY.json',dict(changed_files=changed_ids,unchanged_files='Parent identities/evidence reused; not rehashed.',encrypted_ip='Opaque original objects, not individually hashed.',final_seal=True))
write_json(ROOT/'reports/FILE_CHANGE_REPORT.json',file_rows)
write_json(ROOT/'reports/FINAL_PAIR.json',pair)

lines=['# 逐文件注释改写说明','', '全部可读 HDL 文件均有非注释字节及工具指令相同比较。加密 IP 不参与注释审阅；原对象不改写。逐批替换与 diff 在 reports/batches 和缓存 diffs 中，以下为最终保留状态。','']
for board in ('a','b'):
    lines+=['## '+board.upper()+' 板','','| 文件 | 最终处理与具体关注点 |','|---|---|']
    for row in file_rows[board]:lines.append('| '+row['file']+' | '+('改写：' if row['action']=='COMMENT_ONLY_EDIT' else '保留：')+row['focus']+' |')
    lines.append('')
(ROOT/'逐文件改写说明.md').write_text('\n'.join(lines)+'\n',encoding='utf-8')

base={b:json.loads((ROOT/f'reports/BASELINE_PHYSICAL_{b.upper()}.json').read_text()) for b in ('a','b')}
lines=['# 双板最终资源与时序','','口径：全板原生物理结果；基线为交接已查询的父版 routed.db。新结果绑定 FINAL_PAIR.json。注释本身没有面积优化作用；B 的差异来自选中布局路线。','','| 指标 | A 父版 | A 本次 | B 父版 | B 本次 |','|---|---:|---:|---:|---:|']
for name,key in [('MSLICE','MSLICE'),('LUT','lut'),('REG','reg'),('BRAM9K','bram9k'),('BRAM32K','bram32k'),('DSP','dsp'),('setup WNS/ns','setup_ns'),('hold WNS/ns','hold_ns')]:
    vals=[]
    for b in ('a','b'):
        old=base[b];new=pair['boards'][b]
        if key=='MSLICE':vals.extend([old['source_report']['native_mslice'],new['MSLICE']])
        elif key in ('setup_ns','hold_ns'):vals.extend([old[key],new[key]])
        else:vals.extend([old['resources'][key],new['resources'][key]])
    lines.append('| '+name+' | '+' | '.join(str(v) for v in vals)+' |')
lines+=['','两板最终零冲突，物理 DRC、全部有效时钟/I/O、Gray/CDC、复位和原生存储/INIT 审核通过；TNS/THS=0，STA100%。A/B 都是本候选新综合、新物理实现和新位流生成，未冒充父版位流。','','A 的试点不生成交付位流。全部路线结果见 PHYSICAL_COMPARISON 报告；中止路线不算通过。完整进程、阶段、冲突轨迹、审核和失败日志保留在缓存。']
(ROOT/'资源时序对照.md').write_text('\n'.join(lines)+'\n',encoding='utf-8')

comment_baseline=json.loads((ROOT/'reports/COMMENT_BASELINE.json').read_text())
lines=['# 注释统计对照','','沿用交接的同一统计方法：非空且带英文或中文的注释物理行为一个单元；工具指令不计，字符串内的注释符不计。英文标识符/数字/连字符或撇号词按词计，中文按字符计。统计用于观察文本形态，不是作者身份或“AI率”判定，也不按配额修改。','','| 指标 | A 改前 | A 改后 | B 改前 | B 改后 |','|---|---:|---:|---:|---:|']
after={b:json.loads((ROOT/f'reports/COMMENT_AFTER_{b.upper()}.json').read_text()) for b in ('a','b')}
for name,key in [('可读 HDL 文件','files'),('源码行','source_lines'),('注释单元','comment_units'),('句号结尾/%','period_percent'),('timescale→注释→module/%','header_template_percent')]:
    lines.append('| '+name+' | '+' | '.join(str(v[key]) for b in ('a','b') for v in (comment_baseline[b],after[b]))+' |')
for bucket in ('1-3','4-7','8-12','13-20','21+'):
    lines.append('| '+bucket+' 词 | '+' | '.join(str(v['length_bins'][bucket]) for b in ('a','b') for v in (comment_baseline[b],after[b]))+' |')
lines+=['','A 保留较多厂商生成接口说明与短行注释；句号比例增加如实报告。B 的重复头部与集中句长减少。重要的位宽、CRC、舍入、帧边界、存储所有权和复位信息仍按当前行为说明。完整逐文件分布见 COMMENT_BASELINE.json 和 COMMENT_AFTER_A/B.json。']
(ROOT/'注释统计对照.md').write_text('\n'.join(lines)+'\n',encoding='utf-8')

counts={b:sum(x['action']=='COMMENT_ONLY_EDIT' for x in file_rows[b]) for b in ('a','b')}
readme=f'''# 双板源码注释整理离线交付

2026-11-03，Asia/Shanghai。实测前授权工作已完成。A 改写 {counts['a']} 个文件，B 改写 {counts['b']} 个文件；全部可读 HDL 非注释代码和工具指令保持一致，未改信号名、模块结构、功能、ROM/系数、接口或约束时限。

最终位流：`bitstream/A_scene_a.bit`、`bitstream/B_scene_b.bit`，配套同名 `.bmk`。逐板身份见 `reports/FINAL_PAIR.json`，不要按旧显示标题推断版本。

A：{pair['boards']['a']['MSLICE']} MSLICE，setup/hold {pair['boards']['a']['setup_ns']:+.3f}/{pair['boards']['a']['hold_ns']:+.3f} ns。B：{pair['boards']['b']['MSLICE']} MSLICE，setup/hold {pair['boards']['b']['setup_ns']:+.3f}/{pair['boards']['b']['hold_ns']:+.3f} ns。两板 TNS/THS=0、零冲突、STA100%，完整离线签核通过，满足 MSLICE≤4820 与严格正时序。

阅读入口：

- `逐文件改写说明.md`：逐个源码文件的修改或保留理由。
- `资源时序对照.md`：父版和最终全板原生数据。
- `注释统计对照.md`：沿用同一算法的改前/改后统计，不作为作者身份判断。
- `烧录说明_A板.md` / `烧录说明_B板.md`：工具、实际角色识别、观察顺序和异常排查。
- `构建与证据说明.md`：新执行、精确复用、失败及中止范围；可编辑工程在 `project/a`、`project/b`。
- `reports/FINAL_PAIR.json`：最终配对、位流身份及每板签核来源。
- 构建缓存 `{CACHE.as_posix()}`：全部真实路线、数据库、日志、diff、原始备份。

本轮没有访问开发板、UART、JTAG、TF 或配置 Flash，没有实板功耗、屏幕、听音、红外、录音保存或独立冷启动观测。请按两份烧录说明验收。历史功能仿真按未变源码和原生图证据复用，本轮未重跑功能仿真。

`PLAN.md`、`AUTHORIZATION_UPDATE.md` 和历史停止报告保留其当时状态；当前状态只以本 README、FINAL_PAIR 和最终交接为准。父版 V15.1、原始备份和其交付包未改写。
'''
(ROOT/'README.md').write_text(readme,encoding='utf-8')
history=ROOT/'history';history.mkdir(exist_ok=True)
shutil.copy2(ROOT/'交接_20261103.md',history/'交接_20261103_接手前.md')
(ROOT/'交接_20261103.md').write_text(readme+'\n## 实际尝试\n\nB 三路全部布通；A 试点及最终三路按原授权分别执行，所有停止和结果见 reports/PHYSICAL_COMPARISON_A_PILOT.json、PHYSICAL_COMPARISON_A_FINAL.json 与 PHYSICAL_COMPARISON_B.json。A 首次试点缺 include 的读源码失败与 B 审核脚本假设失败均保留，最终续做不重复已通过阶段。\n',encoding='utf-8')
write_json(ROOT/'reports/STATE.json',dict(status='OFFLINE_COMPLETE_USER_HARDWARE_ACCEPTANCE_PENDING',task_complete=True,offline_complete=True,logic_changes=False,hardware_accessed=False,final_pair='FINAL_PAIR.json',remaining='User physical acceptance only'))

new_files=[ROOT/n for n in ('README.md','交接_20261103.md','逐文件改写说明.md','资源时序对照.md','注释统计对照.md','烧录说明_A板.md','烧录说明_B板.md','构建与证据说明.md','恢复原始源码.ps1')]
new_files += list((ROOT/'tools').glob('*candidate.py'))
new_files += [ROOT/'tools'/n for n in ('finish_a_comments.py','finish_b_comments.py','finalize_delivery.py')]
new_files += [ROOT/'scripts'/n for n in ('lane_candidate_a.py','lane_candidate_b.py','signoff_v15.py','audit_v151_routed.py','audit_crc_shared.py','scene_common.py')]
new_files += [ROOT/f'project/{b}/scene_{b}_top.al' for b in ('a','b')]
write_json(ROOT/'reports/DELIVERY_NEW_FILE_IDENTITY.json',{p.relative_to(ROOT).as_posix():dict(bytes=p.stat().st_size,sha256=hashlib.sha256(p.read_bytes()).hexdigest()) for p in sorted(set(new_files))})

# Stage a self-contained archive with source projects, original rollback data,
# and selected implementation evidence. Do not include old archives or dumps.
delivery=CACHE/'delivery';delivery.mkdir(exist_ok=True);stage=delivery/'双板源码自然化_20261103'
assert not stage.exists();stage.mkdir()
for name in ('source','config','constraints','scripts','tools','reports','bitstream','project','history'):
    shutil.copytree(ROOT/name,stage/name)
for p in ROOT.iterdir():
    if p.is_file() and p.suffix in ('.md','.ps1'):shutil.copy2(p,stage/p.name)
shutil.copytree(CACHE/'original',stage/'original')
shutil.copytree(CACHE/'diffs',stage/'diffs')
for board in ('a','b'):
    source=Path(selection[board]);dest=stage/'implementation'/board;dest.mkdir(parents=True)
    for p in source.iterdir():
        if p.is_file() and p.suffix not in ('.dmp',):shutil.copy2(p,dest/p.name)
    syn=Path(pair['boards'][board]['synthesis']);target=stage/'implementation'/f'{board}_synthesis';target.mkdir()
    for n in ('synthesis.tcl','synthesis.log','synthesized.v','protected.v','protected.db','native_guard.json','reset_distribution.json','SOURCE_SNAPSHOT.json','MAPPED_GRAPH_COMPARISON.json','PROTECTION_COMPARISON.json','SYNTHESIS.json','source_initial.sdc'):
        if (syn/n).exists():shutil.copy2(syn/n,target/n)

archive=delivery/'双板源码自然化_20261103_离线交付.zip';assert not archive.exists()
inventory=[]
with zipfile.ZipFile(archive,'w',compression=zipfile.ZIP_DEFLATED,compresslevel=6,allowZip64=True) as z:
    for p in sorted(stage.rglob('*')):
        if p.is_file():
            rel=p.relative_to(stage).as_posix();z.write(p,rel);inventory.append(dict(path=rel,bytes=p.stat().st_size))
with zipfile.ZipFile(archive) as z:
    assert z.testzip() is None
    assert [(x.filename,x.file_size) for x in z.infolist()]==[(x['path'],x['bytes']) for x in inventory]
    entries=len(z.infolist())
with archive.open('rb') as f:digest=hashlib.file_digest(f,'sha256').hexdigest()
report=dict(archive=str(archive),bytes=archive.stat().st_size,sha256=digest,entries=entries,verification='Every entry decompressed once with ZIP CRC; exact inventory and byte sizes checked.',final_pair=str(ROOT/'reports/FINAL_PAIR.json'),hardware_accessed=False)
write_json(delivery/'DELIVERY_ARCHIVE.json',report)
write_json(ROOT/'reports/DELIVERY_ARCHIVE.json',report)
print(json.dumps(report,ensure_ascii=False),flush=True)
