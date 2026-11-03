"""Synthesize a fresh source snapshot; do not touch an earlier build."""
from pathlib import Path
import json, sys, shutil, subprocess, time, re, os
from comment_review import ROOT, CACHE, verify_board, write_json
sys.path.insert(0,str(ROOT/'scripts'))
from scene_mapped_graph import graph, canonical

board=sys.argv[1]; tag=sys.argv[2] if len(sys.argv)>2 else 'final'
assert board in ('a','b') and tag in ('pilot','final')
suffix=sys.argv[3] if len(sys.argv)>3 else ''
assert suffix in ('','r1')
out=CACHE/(f'build_{board}_{tag}'+('_'+suffix if suffix else ''))
assert not out.exists() or not (out/'synthesis.tcl').exists(), 'An attempted build must be resumed at its complete stage, not overwritten.'
verify_board(board)
out.mkdir(exist_ok=True); (out/'source').mkdir(exist_ok=True)
for p in (ROOT/'source'/board).iterdir():
    if not p.is_file(): continue
    q=out/'source'/p.name
    if '.enc.' in p.name:
        if not q.exists(): os.link(p,q)
    else: shutil.copy2(p,q)
shutil.copy2(ROOT/f'constraints/scene_{board}.adc',out/f'source/scene_{board}.adc')
parent=Path('D:/aidownload/anlu_main/main1')/('V15_low_power' if board=='a' else 'V15_1_low_power')/f'build_{board}'
for p in (ROOT/'source'/board).iterdir():
    if p.suffix.lower() in ('.vh','.hex','.dath'): shutil.copy2(p,out/p.name)
if board=='a':
    # The opaque SDRAM IP includes this relative path. Mirror the parent's
    # support-directory layout without reading or altering the encrypted files.
    shutil.copytree(parent/'user_source',out/'user_source',dirs_exist_ok=True)
template=(parent/'synthesis.tcl').read_text()
compiled=json.loads((ROOT/f'config/sources_{board}.json').read_text())
assert re.findall(r'^add_files source/(.*)$',template,re.M)==compiled+['global_def.v',f'scene_{board}.adc']
(out/'synthesis.tcl').write_text(template,encoding='utf-8')
write_json(out/'SOURCE_SNAPSHOT.json',dict(board=board,tag=tag,source=str(ROOT/f'source/{board}'),compiled=compiled,encrypted_ip='opaque hardlinks',parent_recipe=str(parent/'synthesis.tcl'),hardware_accessed=False))
start=time.monotonic()
with (out/'synthesis.log').open('w',encoding='utf-8') as log:
    p=subprocess.run(['D:/apps/anlogic/bin/td_commands_prompt.exe'],cwd=out,input='source synthesis.tcl\nexit\n',text=True,stdout=log,stderr=subprocess.STDOUT)
s=(out/'synthesis.log').read_text(errors='replace')
errors=[l for l in s.splitlines() if re.search(r'\b(ERROR|FATAL)\b|HDL-7225|undeclared symbol',l) and not re.search(r"undeclared symbol '(?:\*\*|PLL_HDMI_AUDIO_open\d+)'",l)]
result=dict(pass_=p.returncode==0 and 'SYN_FLOW_DONE' in s and not errors,board=board,tag=tag,path=str(out),seconds=round(time.monotonic()-start,1),errors=errors,hardware_accessed=False)
result['pass']=result.pop('pass_')
write_json(out/'SYNTHESIS.json',result)
assert result['pass'],result
new=graph((out/'synthesized.v').read_text()); old=graph((parent/'synthesized.v').read_text())
comparison=dict(pass_=canonical(new)==canonical(old),parent=str(parent),new_build=str(out),comparison='Canonical native graph: cell type, parameters including INIT, and connectivity; no source or old-object hashes recalculated.',new_cells=len(new),parent_cells=len(old))
write_json(out/'MAPPED_GRAPH_COMPARISON.json',comparison)
assert comparison['pass_'],'Diagnose new mapping before applying the inherited protection recipe.'
write_json(ROOT/f'reports/SYNTHESIS_{board.upper()}.json',result)
write_json(ROOT/f'reports/BUILD_{board.upper()}_ACTIVE.json',dict(path=str(out),phase='synthesized',tag=tag))
print(json.dumps(result),flush=True)
