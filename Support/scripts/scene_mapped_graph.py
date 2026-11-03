"""Exact mapped cell/alias graph, including every register INIT.

Adapted from inspected V12 graph and BRAM-inventory implementations. No
archived module is imported or executed. Native rewires are proved against
the complete original graph, not an approximate resource or signal list.
"""
import re
from collections import defaultdict
CELL=re.compile(r'(AL_MAP_\w+|EG_PHY_\w+)\s+#\(([^;]*?)\)\s+(\\\S+|[A-Za-z_][\w$]*)\s+\(([^;]*?)\);',re.S)
def clean(t):return re.sub(r'\s+','',t)
def number(t):
    m=re.fullmatch(r"\d+'([bhd])([0-9a-f_]+)",t.strip(),re.I);assert m,t
    return int(m[2].replace('_',''),{'b':2,'h':16,'d':10}[m[1].lower()])
def values(t,numeric=True):
    result={}
    for key,val in re.findall(r'\.(\w+)\((.*?)\)\s*(?:,|$)',t,re.S):
        val=val.strip();assert key not in result
        result[key]=('number',number(val)) if numeric and re.fullmatch(r"\d+'[bhdBHD][0-9a-fA-F_]+",val) else clean(val)
    return result
def bits(t):
    t=clean(t)
    if t.startswith('{') and t.endswith('}'):return [bit for part in t[1:-1].split(',') for bit in bits(part)]
    m=re.fullmatch(r"(\d+)'([bhd])([0-9a-fxz_]+)",t,re.I)
    if m:
        width=int(m[1]);digits=m[3].lower().replace('_','');base=m[2].lower()
        if base=='b':expanded=digits
        elif base=='h':expanded=''.join(c*4 if c in 'xz' else format(int(c,16),'04b') for c in digits)
        else:expanded=format(int(digits),'b')
        pad=expanded[0] if expanded[0] in 'xz' else '0'
        return ["1'b"+b for b in (pad*width+expanded)[-width:]]
    m=re.fullmatch(r'(.*)\[(\d+):(\d+)\]',t)
    if m:return [m[1]+f'[{i}]' for i in range(int(m[2]),int(m[3])-1,-1)]
    return [t]
def graph(text):
    # A bare vector wire (e.g. .q(held_bank)) represents every declared lane.
    # Expand it before inventory/canonical comparison, rather than treating
    # the whole vector as one scalar source. Escaped names retain their '\\'.
    widths={clean(name):(int(hi),int(lo)) for hi,lo,name in re.findall(r'\b(?:wire|input|output|inout)\s+\[(\d+):(\d+)\]\s+(\\\S+|\w+)\s*;',text)}
    def expand(value):
        value=clean(value)
        if value.startswith('{') and value.endswith('}'):
            return '{'+','.join(expand(part) for part in value[1:-1].split(','))+'}'
        if value in widths:
            hi,lo=widths[value];return value+f'[{hi}:{lo}]'
        return value
    initial={}
    for m in CELL.finditer(text):
        if m[1]=='AL_MAP_SEQ':
            init=re.search(r'//\s*\.INIT\(([^)]+)\)',m[2])
            if init:initial[m[3]]=number(init[1])
    stripped=re.sub(r'//[^\n]*|/\*.*?\*/','',text,flags=re.S);result={}
    for m in CELL.finditer(stripped):
        kind,params,name,ports=m.groups();assert name not in result
        params=values(params)
        if name in initial:params['__REG_INIT__']=initial[name]
        result[name]=(kind,params,{pin:expand(net) for pin,net in values(ports,False).items()})
    assert len(re.findall(r'\b\w+\s+#\(',stripped))==len(result),'Unparsed mapped cell'
    for name,ports in re.findall(r'\bbuf\s+(\\\S+|\w+)\s+\(([^;]+)\);',stripped):
        vals=ports.split(',');assert len(vals)==2 and name not in result
        result[name]=('buf',{},dict(o=expand(vals[0]),i=expand(vals[1])))
    return result
def canonical(g):return {n:(k,p,{pin:bits(net) for pin,net in wires.items()}) for n,(k,p,wires) in g.items()}
def replace_bit(value,lane,new):
    vals=bits(value);assert 0<=lane<len(vals);vals[len(vals)-1-lane]=new
    return vals[0] if len(vals)==1 else '{'+','.join(vals)+'}'
def inventory(g):
    parent={}
    def find(n):
        parent.setdefault(n,n)
        if parent[n]!=n:parent[n]=find(parent[n])
        return parent[n]
    for name,(kind,params,ports) in g.items():
        if kind=='buf':
            out,inp=bits(ports['o']),bits(ports['i']);assert len(out)==len(inp)
            for a,b in zip(out,inp):parent[find(a)]=find(b)
    drivers=defaultdict(list)
    for name,(kind,params,ports) in g.items():
        if kind!='AL_MAP_SEQ' or 'q' not in ports:continue
        for bit in bits(ports['q']):
            if "'" not in bit:drivers[find(bit)].append(name)
    groups={}
    for name,(kind,params,ports) in g.items():
        if kind not in ('EG_PHY_BRAM','EG_PHY_BRAM32K'):continue
        # Protect every registered address/data branch of every B BRAM.
        # Limiting the inventory to prior failing RAMs leaves short paths in
        # other RAMs exposed when a legitimate placement changes.
        for port in ['addra','addrb','dia','dib','bytea','byteb']:
            vals=bits(ports.get(port,''))
            for lane,net in enumerate(reversed(vals)):
                root=find(net);driver=drivers.get(root,[])
                if not driver:continue
                assert len(driver)==1,root
                row=groups.setdefault(root,dict(source=net,driver=driver[0],sinks=[]))
                row['sinks'].append(dict(cell=name,port=port,lane=lane,width=len(vals),net=net))
    return [groups[n] for n in sorted(groups)]

def fifo_reset_inventory(g):
    """Four local FIFO reset-release Q -> asynchronous reset branches.

    Only consumer SR pins are delayed. Synchronizer feedback/data, reset
    inputs, crossing-level observers and every other user remain unchanged.
    """
    parent={}
    def find(n):
        parent.setdefault(n,n)
        if parent[n]!=n:parent[n]=find(parent[n])
        return parent[n]
    for _,(kind,_,ports) in g.items():
        if kind=='buf':
            for a,b in zip(bits(ports['o']),bits(ports['i'])):parent[find(a)]=find(b)
    result=[]
    for domain in ['rreset0','rreset1','wreset0','wreset1']:
        driver='\\core/audio/banks/'+domain+'/release_pipe_reg[2]'
        kind,_,ports=g[driver];assert kind=='AL_MAP_SEQ'
        roots=bits(ports['q']);assert len(roots)==1;root=find(roots[0])
        sinks=[]
        for name,(kind,_,pins) in g.items():
            if kind=='AL_MAP_SEQ' and 'sr' in pins and find(pins['sr'])==root:
                assert pins['clk']==ports['clk'], 'FIFO reset consumer is in another clock domain'
                sinks.append(dict(cell=name,port='sr',lane=0,width=1,net=pins['sr']))
        # Explicit32K read ports remove the old9K read-result selection
        # registers. All actual SR consumers are enumerated, not truncated.
        assert len(sinks)==(39 if domain.startswith('r') else 38), 'FIFO reset fanout changed'
        bank=domain[-1]
        assert all(s['cell'].startswith('\\core/audio/banks/fifo'+bank+'/') for s in sinks)
        result.append(dict(source=sinks[0]['net'],driver=driver,sinks=sinks,kind='fifo_reset_release'))
    return result
