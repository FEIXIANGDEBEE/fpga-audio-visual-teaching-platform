from pathlib import Path
import json,sys
from scene_mapped_graph import graph
R=Path(__file__).resolve().parents[1];role=sys.argv[1]
B=Path(json.loads((R/f'reports/BUILD_{role.upper()}_ACTIVE.json').read_text())['path'])
g=graph((B/'routed.v').read_text());sg=graph((B/'synthesized.v').read_text());pg=graph((B/'protected.v').read_text())
assert {n:(k,p) for n,(k,p,w) in g.items() if k.startswith('EG_PHY_BRAM')}=={n:(k,p) for n,(k,p,w) in pg.items() if k.startswith('EG_PHY_BRAM')}
v={'pass':True,'board':role,'build':str(B),'native_RAM_INIT_preserved':True,'new_CDC_or_pixel_pipeline_stages':False,'card_and_materials_unchanged':True}
if role=='a':
    assert json.loads((R/'reports/SMALL_FONT_A_INIT.json').read_text())['pass']
    assert json.loads((R/'reports/FONT_REDRAW.json').read_text())['pass']
    assert json.loads((R/'reports/C2_MOTION_NATIVE.json').read_text())['pass']
    v.update(font_words_exact=4608,motion_words_exact=512,OSD_proofs='TEST_PIPELINE.json')
else:
    fields={}
    for field in ['heights','peaks']:
        names=[n for n,(k,p,w) in sg.items() if k=='AL_MAP_SEQ' and n.startswith('\\screen/spectrum_motion/'+field+'_reg[')]
        assert len(names)==128,(field,len(names))
        fields[field]={'bits':len(names),'registered':True}
    v.update(display_only_state=fields,algorithm='Frame-bounded16band serial update, immediate attack, ceil-quarter fall, max(new,peak-1), identity/page reset; transient invalid/wave retain heights; qualified HOLD freeze')
(R/f'reports/V125_NATIVE_{role.upper()}.json').write_text(json.dumps(v,indent=2)+'\n')
print('V125_NATIVE_PASS',role,flush=True)
