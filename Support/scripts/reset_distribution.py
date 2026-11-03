"""Buffer the evidenced high-fanout synchronous analysis-reset release, without a cycle change."""
from collections import defaultdict
import re
def inventory(g,group_limit=16):
 assert group_limit in [16,24,32]
 groups=defaultdict(list)
 for name,(kind,params,ports) in g.items():
  if ports.get('sr')=='\\analysis/sys_audio_rst':
   assert kind in ['AL_MAP_SEQ','EG_PHY_MSLICE','EG_PHY_LSLICE'] and ports.get('clk')=='sys_clk_dup_1' and 'q' in ports,(name,kind,ports)
   groups[(name.rsplit('/',1)[0],ports.get('ce',"1'b1"))].append(name)
 assert sum(map(len,groups.values()))>1000,'Only use for the evidenced analysis reset tree'
 def natural(s):return [int(x) if x.isdigit() else x for x in re.split(r'(\d+)',s)]
 result=[]
 for (module,ce),names in sorted(groups.items()):
  names=sorted(names,key=natural)
  for i in range(0,len(names),group_limit):
   result.append({'source':'\\analysis/sys_audio_rst','kind':'analysis_reset_distribution','group':module,'clock_enable':ce,
    'sinks':[{'cell':n,'port':'sr','width':1,'lane':0} for n in names[i:i+group_limit]]})
 assert sum(len(x['sinks']) for x in result)==sum(map(len,groups.values()))
 # Retain the parent guard floor with a useful split of one real full group.
 # The same single-level identity buffer feeds each half, with no cycle change.
 if group_limit==32:
  idx=next(i for i,b in enumerate(result) if len(b['sinks'])==32)
  branch=result[idx]
  result[idx:idx+1]=[dict(branch,sinks=branch['sinks'][:16]),dict(branch,sinks=branch['sinks'][16:])]
 return result
