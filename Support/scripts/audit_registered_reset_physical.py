from pathlib import Path
import json
from scene_mapped_graph import graph,canonical
from registered_reset import prove
R=Path(__file__).resolve().parents[1];B=Path(json.loads((R/'reports/BUILD_A_ACTIVE.json').read_text())['path']);sg=graph((B/'synthesized.v').read_text());pg=graph((B/'placed_native.v').read_text());gg=graph((B/'routed.v').read_text())
assert json.loads((R/'reports/POWER_RESET_SYNTH.json').read_text())['pass']
if canonical(pg)==canonical(gg):
 result=json.loads((B/'registered_reset_placed.json').read_text());result.update(placed_proof_reused=True,routed_native_graph_identical=True)
else:result=prove(gg,sg);result.update(placed_proof_reused=False,routed_native_graph_identical=False)
(R/'reports/REGISTERED_RESET_PHYSICAL.json').write_text(json.dumps(result,indent=2)+'\n');print('REGISTERED_RESET_PHYSICAL_PASS',len(result['native_drivers']),flush=True)
