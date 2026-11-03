"""Apply and compare the original native protection recipe on a new graph."""
from pathlib import Path
import sys,json,shutil,subprocess
from comment_review import ROOT, CACHE, write_json
sys.path.insert(0,str(ROOT/'scripts'))
from scene_mapped_graph import graph,canonical
role=sys.argv[1];assert role in ('a','b')
out=Path(json.loads((ROOT/f'reports/SYNTHESIS_{role.upper()}.json').read_text())['path'])
parent=Path('D:/aidownload/anlu_main/main1')/('V15_low_power' if role=='a' else 'V15_1_low_power')/f'build_{role}'
assert json.loads((out/'MAPPED_GRAPH_COMPARISON.json').read_text())['pass_']
assert not (out/'PROTECTION_COMPARISON.json').exists(), 'This stage is already proven; reuse its result.'
shutil.copy2(parent/'source_initial.sdc',out/'reviewed_pre_place.sdc')
if role=='a':shutil.copy2(ROOT/'config/place_pins_a.tcl',out/'place_pins.tcl')
subprocess.run([sys.executable,'-X','utf8','-B',str(ROOT/'scripts/prepare_physical.py'),role],check=True)
result=dict(pass_=canonical(graph((out/'protected.v').read_text()))==canonical(graph((parent/'protected.v').read_text())),source_initial_sdc_identical=(out/'source_initial.sdc').read_bytes()==(parent/'source_initial.sdc').read_bytes(),parent=str(parent),build=str(out))
write_json(out/'PROTECTION_COMPARISON.json',result)
assert result['pass_'] and result['source_initial_sdc_identical']
print(json.dumps(result))
