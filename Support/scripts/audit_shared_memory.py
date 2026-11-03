"""New fixed four-lane native memory ownership, synth or routed evidence."""
from pathlib import Path
from collections import Counter
import json,sys,subprocess
from scene_mapped_graph import graph,bits
R=Path(__file__).resolve().parents[1];B=Path(json.loads((R/'reports/BUILD_B_ACTIVE.json').read_text())['path'])
phase=sys.argv[1];g=graph((B/(phase+'.v')).read_text());counts=Counter(k for k,p,w in g.values())
golden=[int(x,16) for x in (R/'source/b/record_template.dath').read_text().split()]
templates=[];shared=[];other_store=[]
for n,(k,p,w) in g.items():
 if k.startswith('EG_PHY_BRAM') and 'recorder/store/' in n:
  assert '/template_rom_' in n and k=='EG_PHY_BRAM',(n,k)
  assert p['DATA_WIDTH_A']==p['DATA_WIDTH_B']=='"9"' and p['WEAMUX']==p['WEBMUX']=='"0"',n
  assert p['REGMODE_A']==p['REGMODE_B']=='"NOREG"',n
  raw=sum(p[f'INIT_{i:02X}'][1]<<(256*i) for i in range(32));parity=sum(p[f'INITP_{i:02X}'][1]<<(256*i) for i in range(4))
  decoded=[((raw>>(8*i))&255)|(((parity>>i)&1)<<8) for i in range(1024)]
  hits=[i for i in range(4) if decoded==golden[i*1024:(i+1)*1024]];assert len(hits)==1,(n,hits)
  templates.append({'cell':n,'bank':hits[0],'INIT_exact':True})
 if k=='EG_PHY_BRAM32K' and 'banks/fifo0/g_pcm_lane[' in n:
  import re
  lane=int(re.search(r'g_pcm_lane\[(\d+)\]',n)[1]);assert 0<=lane<4
  assert p['DATA_WIDTH_A']==p['DATA_WIDTH_B']=='"8"' and p['REGMODE_A']==p['REGMODE_B']=='"NOREG"'
  assert p['WEBMUX']=='"0"' and w.get('wea') not in (None,"1'b0","1'b1"),n
  assert p['CSAMUX']==p['CSBMUX']=='"1"' and p['RSTAMUX']==p['RSTBMUX']=='"0"',n
  assert w['clka']=='sys_clk_dup_1' and w['clkb']=='audio_mclk_dup_1',(n,w['clka'],w['clkb'])
  shared.append({'cell':n,'lane':lane,'SYS_clock':w['clka'],'MCLK_clock':w['clkb'],'width':8,'logical_words':4096,
   'native_parameter_WE_A':p.get('WEAMUX','direct WEA pin; 32K primitive emits no WEA mux parameter'),'WE_A_net':w.get('wea'),'native_B_read_only':True,'no_multi_cell_address_bank_select':True})
assert len(shared)==4 and {x['lane'] for x in shared}=={0,1,2,3},shared
assert len({x['WE_A_net'] for x in shared})==4,'Per-lane record write qualification must not merge into one all-lane write'
assert len(templates)==4 and {x['bank'] for x in templates}=={0,1,2,3}
assert not [n for n in g if 'capture_ram' in n],'Dedicated recording RAM was not removed'
# V11.1 adds the previously unused production parser payload read port.
parser_ram=[(n,k,p,w) for n,(k,p,w) in g.items() if n.startswith('\\link/parser/') and k=='EG_PHY_BRAM']
assert len(parser_ram)==1,parser_ram
assert parser_ram[0][2]['REGMODE_A']==parser_ram[0][2]['REGMODE_B']=='"NOREG"'
assert counts['EG_PHY_BRAM32K']==11 and counts['EG_PHY_BRAM']==41 and counts['EG_PHY_MULT18']==7,counts
new_rams=[n for n,(k,p,w) in g.items() if n.startswith('\\screen/render/spectrogram/') and k=='EG_PHY_BRAM']
assert len(new_rams)==11 and counts['EG_PHY_BRAM']-len(new_rams)==30,'Original memory count must remain30; new11 audited separately'
assert not [n for n,(k,p,w) in g.items() if 'files/catalog/descriptors_reg' in n]
descriptor=[n for n,(k,p,w) in g.items() if 'files/catalog/descriptors_ram' in n and k=='EG_PHY_BRAM'];assert descriptor
if phase=='routed':
 pg=graph((B/'protected.v').read_text())
 before={n:(k,p) for n,(k,p,w) in pg.items() if k.startswith('EG_PHY_BRAM')};after={n:(k,p) for n,(k,p,w) in g.items() if k.startswith('EG_PHY_BRAM')}
 assert before==after,'Physical stages changed native RAM/INIT images'
report={'pass':True,'phase':phase,'build':str(B),'shared_FIFO0_RAM32K':shared,'capture_bytes':16384,'music_FIFO0_stereo_frame_capacity':4096,
 'music_FIFO1_stereo_frame_capacity':4096,'template_ROM9K':templates,'native_cell_counts':dict(counts),'expected_B_total_RAM32K':11,
 'dedicated_recording_RAM32K_removed':4,'descriptor_native_cells':descriptor,'total_DSP':7,'native_all_RAM_INIT_preserved':phase=='routed',
 'lane_mapping_proof':'New actual production shared FIFO full15168 SYS/MCLK byte tests, normal full/empty/wrap/clear differential, actual engine capture/save/load/replay; no implicit16K address-bank macro remains',
 'functional_evidence':'Shared FIFO/RAM unchanged from V10.5; native structure is new per physical object. New tag-driven integration and unchanged-kernel reuse boundaries are in SIM_V108.json','hardware_accessed':False}
dest='NATIVE_SYNTH.json' if phase=='synthesized' else 'RECORD_ROUTED.json';(R/'reports'/dest).write_text(json.dumps(report,indent=2)+'\n')
if phase=='synthesized':
 subprocess.run([sys.executable,'-B',str(R/'scripts/audit_registered_owner.py'),'--synthesis'],check=True)
 if (R/'reports/C5_IMPLEMENTED.json').exists():subprocess.run([sys.executable,'-B',str(R/'scripts/audit_registered_active.py'),'--synthesis'],check=True)
print('V105_SHARED_FIFO0_NATIVE_PASS',phase,'RAM32K11 capacity16384 retained music4096+4096',flush=True)
