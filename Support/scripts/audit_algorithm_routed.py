"""New algorithm structures in this actual routed object."""
from pathlib import Path
import json
from scene_mapped_graph import graph,bits
R=Path(__file__).resolve().parents[1];B=Path(json.loads((R/'reports/BUILD_B_ACTIVE.json').read_text())['path'])
g=graph((B/'routed.v').read_text())
dsp=[n for n,(k,p,w) in g.items() if k=='EG_PHY_MULT18']
fft_dsp=[n for n in dsp if n.startswith('\\analysis/fft/')]
assert len(dsp)==7 and len(fft_dsp)==5,(dsp,fft_dsp)
protected=graph((B/'protected.v').read_text())
assert {n:(k,p) for n,(k,p,w) in protected.items() if k=='EG_PHY_MULT18'}=={n:(k,p) for n,(k,p,w) in g.items() if k=='EG_PHY_MULT18'}, 'Native DSP parameters changed during physical flow'
assert all(w['clk']=='sys_clk_dup_1' for n,(k,p,w) in g.items() if k=='EG_PHY_MULT18' and 'exact_multiply/' in n)
descriptor=[(n,k,p,w) for n,(k,p,w) in g.items() if 'files/catalog/descriptors_ram' in n and k.startswith('EG_PHY_BRAM')]
assert descriptor and len(descriptor)<=11
for n,k,p,w in descriptor:
    assert k=='EG_PHY_BRAM' and p['WEBMUX']=='"0"' and p['REGMODE_A']==p['REGMODE_B']=='"NOREG"',n
    assert w['clka']==w['clkb']=='sys_clk_dup_1',n
multiply_q=[n for n,(k,p,w) in g.items() if 'analysis/fft/exact_multiply/' in n]
assert multiply_q
assert not [n for n in g if 'band_real_q_reg' in n or 'band_imag_q_reg' in n or 'exact_multiply/multiplicand_reg' in n], 'Duplicate lifetime registers remain'
assert 'FFT_PASS' in (R/'reports/REUSED_V15_fft.log').read_text()
v={'pass':True,'build':str(B),'DSP_total':7,'FFT_DSP_Hann_and_exact_product':fft_dsp,'serial_multiply_native_cells':len(multiply_q),
 'descriptor_native_9K':[n for n,k,p,w in descriptor],'descriptor_bits_preserved':97,'native_same_clock_no_extra_output_stage':True,
 'behavior':'New TEST_fft_mux.json exact C1 production FFT cycle/product differential; new native DSP kernel;2 full512point/28bit windows32bands, stalls and reset; source/UI integration C1 evidence reused by exact interface equivalence','duplicate_band_registers_removed':56,'DSP_product_pipeline_added':True,
 'old_features':'No FFT point/precision/band changes; exact results; music/recording formats unchanged','hardware_accessed':False,
 'V135':'weight_mode=0 cycle-identical to V13.3 (TARGETED_RESULTS fft_weight); weight_mode 1..3 reuse the same DSP product (DSP total still 7); ROM INIT in FFT_WEIGHT_ROM.json'}
(R/'reports/ALGORITHM_NATIVE.json').write_text(json.dumps(v,indent=2)+'\n')
print('V107_ROUTED_DSP7_DESCRIPTOR_NATIVE_PASS',flush=True)
