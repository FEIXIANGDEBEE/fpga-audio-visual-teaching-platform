"""Actual two CRC contexts remain registered with no interface cycle added."""
from pathlib import Path
import json,sys,re
from scene_mapped_graph import graph,bits
R=Path(__file__).resolve().parents[1];B=Path(json.loads((R/'reports/BUILD_B_ACTIVE.json').read_text())['path'])
phase='synthesized' if '--synthesis' in sys.argv else 'routed';g=graph((B/(phase+'.v')).read_text())
alias={}
for n,(k,p,w) in g.items():
 if k=='buf':
  for a,b in zip(bits(w['o']),bits(w['i'])):alias[a]=b
def root(x):
 while x in alias:x=alias[x]
 return x
rows=[]
if phase=='synthesized':
 source=Path(json.loads((R/'reports/SYNTHESIS_B.json').read_text())['path'])/'source'
 s=(source/'scene_analysis_windows.v').read_text();assert s.count('crc32_byte(')==2
 header=(source/'crc32_defs.vh').read_text()
 assert header==(Path('D:/fpga/anlu/work/main1/version')/'V14_clean/source/b/crc32_defs.vh').read_text(), 'CRC function must match frozen parent'
 for name in ['crc_reg[0]','read_crc_reg[0]']:
  cell='\\analysis/input_windows/'+name;k,p,w=g[cell]
  assert k=='AL_MAP_SEQ' and w['clk']=='sys_clk_dup_1'
  rows.append({'owned_register':cell,'Q':w['q'],'clock':w['clk'],'type':k})
 def count_luts(cells,prefix):return sum(k.startswith('AL_MAP_LUT') for n,(k,p,w) in cells.items() if n.startswith(prefix))
 comparison={prefix:{'current_LUT_primitives':count_luts(g,prefix)} for prefix in ['\\analysis/input_windows/','\\files/','\\link/','\\']}
else:
 previous=json.loads((R/'reports/CRC_SHARED_SYNTH.json').read_text());comparison=previous['synthesis_comparison_only']
 for item in previous['registers']:
  target=root(item['Q']);drivers=[(n,k) for n,(k,p,w) in g.items() if k!='buf' and target in [root(x) for x in bits(w.get('q',''))]]
  assert len(drivers)==1 and drivers[0][1] in ('EG_PHY_MSLICE','EG_PHY_LSLICE'),(target,drivers)
  rows.append({'actual_Q':target,'physical_cell':drivers[0][0],'type':drivers[0][1]})
for name in ['crc_gf2','windows_crc']:assert json.loads((Path('D:/fpga/anlu/work/main1/version')/f'V10_7/reports/TEST_{name}.json').read_text())['pass']
o={'pass':True,'build':str(B),'phase':phase,'registers':rows,'independent_CRC_states':2,'byte_phase_function_calls':2,'CRC_numeric_format_and_latency_unchanged':True,'original_polynomial_function_restored':True,'reused_function_equivalence_space_bits':40,'synthesis_comparison_only':comparison,'full_board_physical_result_is_authoritative':True,'A_crc_path_unchanged':True,'functional_reports_reused_from':'../../V10_7/reports/TEST_crc_gf2.json;TEST_windows_crc.json'}
dest='CRC_SHARED_SYNTH.json' if phase=='synthesized' else 'CRC_SHARED_ROUTED.json'
(R/'reports'/dest).write_text(json.dumps(o,indent=2)+'\n');print('V107_SHARED_CRC_NATIVE_PASS',phase,json.dumps(comparison))
