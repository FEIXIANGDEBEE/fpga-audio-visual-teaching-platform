from pathlib import Path
import sys,json
from scene_mapped_graph import graph,bits
R=Path(__file__).resolve().parents[1];B=Path(json.loads((R/'reports/BUILD_B_ACTIVE.json').read_text())['path']);g=graph((B/'routed.v').read_text())
cells=[(n,k,p,w) for n,(k,p,w) in g.items() if k.startswith('EG_PHY_BRAM') and 'analysis/fft/' in n and 'coefficient_rom' in n];assert len(cells)==1
n,k,p,w=cells[0];assert k=='EG_PHY_BRAM32K' and p['DATA_WIDTH_A']==p['DATA_WIDTH_B']=='"16"'
raw=sum(p[f'INIT_{i:02X}'][1]<<(i*256) for i in range(128));words=[(raw>>(i*16))&65535 for i in range(2048)]
assert words==[int(v,16) for v in (R/'source/b/scene_fft_coefficients.dath').read_text().split()]
assert w['csa']==w['csb']=='\\analysis/reset/release_pipe[2]'
for name,(kind,params,ports) in g.items():
 if kind.startswith('EG_PHY_BRAM') and ('analysis/fft/imag_ram/' in name or 'analysis/fft/real_ram/' in name):
  read=ports.get('ceb',ports.get('csb',''))
  assert '\\analysis/reset/release_pipe[2]' in bits(read),(name,read)
  if 'csb' in ports:assert params['CSB2']=='"SIG"',(name,params)
  else:assert params.get('CEBMUX','"SIG"')=='"SIG"'
v={'pass':True,'build':str(B),'coefficient_words_exact':2048,'all_FFT_read_ports_sleep_disabled':True,'read_gate_source':'analysis/reset/release_pipe[2]','modeled_wake_test':'tests/fft.log','hardware_power_measured':False}
(R/'reports/V15_FFT_MEMORY_NATIVE.json').write_text(json.dumps(v,indent=2)+'\n');print('V15_FFT_MEMORY_NATIVE_PASS')
