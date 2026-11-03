"""Read-only current hardware identification for the authorized Flash operation."""
from pathlib import Path
import sys,json,re,shutil
from datetime import datetime
from zoneinfo import ZoneInfo
ROOT=Path(__file__).resolve().parents[1]
CACHE=Path('D:/aidownload/anlu_main/aaa_comment_rework_20261103')
LIB=Path('D:/fpga/anlu/work/main1/version/V13_5_filtered_spectrum/hardware/scripts')
sys.path.insert(0,str(LIB))
import hardware_lib_v116 as h
out=CACHE/'flash_delivery'/datetime.now(ZoneInfo('Asia/Shanghai')).strftime('%Y%m%d_%H%M%S')
out.mkdir(parents=True,exist_ok=False)
shutil.copy2(__file__,out/'flash_identify.py')
h.write_json(ROOT/'reports/FLASH_SESSION.json',dict(path=str(out),authorization='2026-11-03 user: 开发板已经连接，开始直接固化flash我测试'))
pair=json.loads((ROOT/'reports/FINAL_PAIR.json').read_text())
result=dict(pass_=False,stage='identify',hardware_accessed=True,flash_write_attempted=False,TF_written=False,authorization='2026-11-03 user direct Flash before user physical testing',cold_boot_verified=False)
try:
    ports,bauds=h.uart_roles(out);result.update(uart=ports,baudrate=bauds)
    print('FRESH_UART',ports,bauds,flush=True)
    for role in 'ab':
        d=h.Uart(role,ports[role],out,bauds[role])
        try:result.setdefault('pre_status',{})[role]={q:d.frame(q) for q in (('Q','S') if role=='a' else ('Q','Y','P'))}
        finally:d.close()
    y=result['pre_status']['b']['Y']
    assert not(y[0]&0x10000) and not(y[0]&0xff00),('recorder active/fault; preserve state',y)
    listing=h.bw('list_cable','list_cable',out)
    cables=sorted(int(x) for x in re.findall(r'^(\d+):EG4S20BG256',listing,re.M))
    assert cables==[0,1],cables
    old=Path('D:/aidownload/anlu_main/main1/V15_1_low_power/flash_delivery/20261102_155411')
    refs={}
    for r in 'ab':
        refs['parent_'+r]=h.parse_svf(old/f'target_{r}.svf')
        bit=Path(pair['boards'][r]['files']['bit']['path'])
        assert bit.stat().st_size==pair['boards'][r]['files']['bit']['bytes']
        refs['target_'+r]=h.svf(bit,out,'target_'+r)
    mapping={};matrix={}
    for cable in cables:
        actual,p=h.read_sram(out,cable,f'current_identity_{cable}')
        scores={name:h.score(actual,ref)[0] for name,ref in refs.items()}
        matches={name[-1] for name,score in scores.items() if score==0}
        matrix[str(cable)]=dict(scores=scores,path=str(p))
        assert len(matches)==1,(cable,scores)
        r=matches.pop();assert r not in mapping;mapping[r]=cable
        print('FRESH_JTAG',cable,r,scores,flush=True)
    result.update(jtag=mapping,identity_matrix=matrix,serial_closed=True)
    result['pass']=True;result['stage']='identified'
finally:
    result.pop('pass_',None)
    h.write_json(out/'IDENTITY.json',result)
print('IDENTITY_PASS',out,flush=True)
