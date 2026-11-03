"""Same-cycle SYS rst_n SR fanout split. No reset/data logic or latency changes."""
from collections import defaultdict
import re
def inventory(g,group_limit=128):
    assert group_limit==128
    groups=defaultdict(list)
    for n,(k,p,w) in g.items():
        if k!='AL_MAP_SEQ' or w.get('sr')!='rst_n':continue
        assert re.fullmatch(r'sys_clk_dup_\d+',w['clk']) and p['SRMODE'] in ['"ASYNC"','"SYNC"'] and p['SRMUX']=='"INV"',(n,p,w)
        path=n.lstrip('\\').rsplit('/',1)[0] if '/' in n else '$top'
        groups[(path,w['clk'],p['SRMODE'])].append(n)
    assert sum(map(len,groups.values()))>=3000
    natural=lambda s:[int(x) if x.isdigit() else x for x in re.split(r'(\d+)',s)]
    result=[]
    for (path,clock,mode),names in sorted(groups.items()):
        names=sorted(names,key=natural)
        for i in range(0,len(names),group_limit):
            result.append(dict(source='rst_n',kind='A_SYS_SR_same_cycle',group=path,clock=clock,reset_mode=mode,sinks=[dict(cell=n,port='sr',lane=0,width=1,net='rst_n') for n in names[i:i+group_limit]]))
    assert len(result)<200
    return result
