"""Current explicitly authorized Flash pair. No TF writes, rebuild or packaging."""
from pathlib import Path
import sys,json,re,time,shutil,traceback,hashlib,importlib.util
from datetime import datetime
from zoneinfo import ZoneInfo
ROOT=Path(__file__).resolve().parents[1]
MAIN=Path('D:/fpga/anlu/work/main1')
sys.path.insert(0,str(MAIN/'version/V13_5_filtered_spectrum/hardware/scripts'))
import hardware_lib_v116 as h
sys.modules['hardware_library']=h
spec=importlib.util.spec_from_file_location('flash_decoder',MAIN/'version/V6_1/scripts/program_flash_v6_1.py')
decoder=importlib.util.module_from_spec(spec);spec.loader.exec_module(decoder)
assert sys.argv[1:]==['--execute']
read=lambda p:json.loads(Path(p).read_text(encoding='utf-8-sig'))
out=Path(read(ROOT/'reports/FLASH_SESSION.json')['path'])
identity=read(out/'IDENTITY.json');assert identity['pass'] and identity['stage']=='identified'
assert not(out/'result.json').exists(),'Continue from completed stages; never silently repeat programming.'
shutil.copy2(__file__,out/'program_flash_current.py')
pair=read(ROOT/'reports/FINAL_PAIR.json')
mapping=identity['jtag'];ports=identity['uart'];bauds=identity['baudrate']
res=dict(name=pair['name'],path=str(out),authorization='2026-11-03 user: 开发板已经连接，开始直接固化flash我测试',pass_=False,
    cold_boot_verified=False,user_screen_acceptance=False,external_listening_observed=False,
    TF_written=False,serial_closed=True,configuration_flash_write_attempted=False,
    configuration_flash_pair_pass=False,sram_restored=False,boards={},uart=ports,baudrate=bauds,jtag=mapping)
res['pass']=res.pop('pass_');objects={};refs={};bridge=False
def save():h.write_json(out/'result.json',res)
def cmd(command,label,timeout=300):
    res['active_operation']=label;save();print('BEGIN',label,flush=True)
    log=h.bw(command,label,out,timeout);print('DONE',label,flush=True);return log
def fread(role,stage):
    for attempt in range(2):
        label=f'{role}_flash_{stage}'+('_retry' if attempt else '')
        p=out/(label+'.bin')
        log=cmd(f'read_flash -start_addr 0x0 -length 2097152 -output {{{p.as_posix()}}} -cable {mapping[role]}',label)
        assert 'finish command "read_flash' in log
        data=p.read_bytes()
        if len(data)==2097152 and len(set(data))>1:
            res['boards'][role][stage]=dict(path=str(p),bytes=len(data),sha256=hashlib.sha256(data).hexdigest());save();return data
        res['boards'][role].setdefault('invalid_reads',[]).append(str(p));save()
        assert attempt==0,('Two invalid Flash reads; do not erase/program again',role,stage)
        cmd(f'get_flash_manufacturer -cable {mapping[role]}',label+'_reidentify')
    raise AssertionError('Unreachable')
def restore():
    for role in 'ab':
        obj=objects[role];bit=obj['bit'];st=bit.stat();assert(st.st_size,st.st_mtime_ns)==obj['stat']
        for attempt in range(2):
            label=f'restore_sram_{role}_{attempt}'
            log=cmd(f'download -bit {{{bit.as_posix()}}} -mode jtag -cable {mapping[role]}',label)
            assert 'PRG-2014' in log and 'finish command "download' in log
            actual,p=h.read_sram(out,mapping[role],label+'_readback')
            differences,n=h.score(actual,refs[role])
            res['boards'][role].setdefault('sram_restore_attempts',[]).append(dict(differences=differences,compared_bits=n,readback=str(p)));save()
            if differences==0:break
        assert differences==0,(role,differences)
    res['sram_restored']=True;save()
def startup():
    devices={}
    try:
        for r in 'ab':devices[r]=h.Uart(r,ports[r],out,bauds[r])
        a,b=devices['a'],devices['b'];aq,bq=h.wait_ready(a,b,110)
        deadline=time.monotonic()+45
        while True:
            catalog=b.frame('I')
            if catalog[0]&0x3fff==0x3fff:break
            assert time.monotonic()<deadline,('Catalog incomplete',catalog)
            time.sleep(.3)
        y=b.frame('Y');ss=a.frame('S')
        assert not(y[0]&0x10000) and not(y[0]&0xff00),('Recording owner/fault',y)
        before={r:{q:devices[r].frame(q) for q in ('Q','P')} for r in 'ab'}
        time.sleep(1)
        after={r:{q:devices[r].frame(q) for q in ('Q','P')} for r in 'ab'}
        for r in 'ab':assert after[r]['Q'][2:]==before[r]['Q'][2:]==[0,0],(r,before,after)
        assert after['a']['P'][1]>before['a']['P'][1],'I2S stalled'
        assert after['a']['P'][2]==before['a']['P'][2],'PCM error count increased'
        return dict(pass_=True,before=before,after=after,B_I=catalog,B_Y=y,A_S=ss,
            protocol={r:devices[r].last_protocol for r in 'ab'},cold_boot_verified=False,scope='Short digital startup after exact SRAM restoration only')
    finally:
        for d in devices.values():d.close()
try:
    for role in 'ab':
        board=pair['boards'][role];sig=read(ROOT/f'reports/OFFLINE_SIGNOFF_{role.upper()}.json')
        assert sig['pass'] and sig['physical']['pass'] and sig['physical']['native_mslice']<=4820
        assert sig['physical']['setup_wns_ns']>0 and sig['physical']['hold_wns_ns']>0
        assert sig['STA_coverage']==100 and sig['TNS_THS']==sig['conflicts']==0
        bit=Path(board['files']['bit']['path']);st=bit.stat();assert st.st_size==board['files']['bit']['bytes']
        model,n=decoder.flash_image(bit)
        objects[role]=dict(bit=bit,stat=(st.st_size,st.st_mtime_ns),model=model,n=n)
        refs[role]=h.parse_svf(out/f'target_{role}.svf')
        res['boards'][role]=dict(bit=str(bit),sha256=board['files']['bit']['sha256'],identity_reused_from=str(ROOT/'reports/FINAL_PAIR.json'),payload_bytes=n,programmed=False,native_verified=False)
    # Recheck the existing recording owner immediately before entering the SPI bridge.
    d=h.Uart('b',ports['b'],out,bauds['b'])
    try:
        y=d.frame('Y');res['pre_record_state']=y;save()
        assert not(y[0]&0x10000) and not(y[0]&0xff00),('Recorder active/fault; no Flash operation',y)
    finally:d.close()
    listing=cmd('list_cable','list_cable_before_flash')
    assert sorted(int(x) for x in re.findall(r'^(\d+):EG4S20BG256',listing,re.M))==sorted(mapping.values())
    old=read(MAIN/'version/V15_1_low_power/reports/FLASH_DELIVERY_LATEST.json')
    oldresult=read(old['path'])
    for role in 'ab':
        bridge=True
        log=cmd(f'get_flash_manufacturer -cable {mapping[role]}',f'manufacturer_{role}')
        for key,value in [('Manufacturer ID','ef'),('Interface type','40'),('Density and Feature','15')]:
            assert re.search(re.escape(key)+r'\s*:\s*'+value+r'\b',log,re.I),log
        before=fread(role,'before');obj=objects[role]
        boundary=((obj['n']+65535)//65536)*65536;assert 0<boundary<=2097152
        obj.update(before=before,boundary=boundary,expected=obj['model'][:boundary]+before[boundary:])
        prior=Path(oldresult['boards'][role]['after']['path'])
        res['boards'][role].update(before_matches_previous_delivered=before==prior.read_bytes(),erase_boundary=boundary,preserved_tail_bytes=2097152-boundary)
        save()
    res['both_full_2mib_backups_pass']=True;save();print('BOTH_BACKUPS_PASS',flush=True)
    for role in 'ab':
        obj=objects[role];bit=obj['bit'];st=bit.stat();assert(st.st_size,st.st_mtime_ns)==obj['stat']
        if obj['before']==obj['expected']:
            res['boards'][role]['write_skipped']='Complete current Flash image already equals target plus preserved tail';save();print('SKIP_IDENTICAL_FLASH',role,flush=True);continue
        res['configuration_flash_write_attempted']=True;res['boards'][role]['write_attempted']=True;save()
        log=cmd(f'download -bit {{{bit.as_posix()}}} -mode program_spi -cable {mapping[role]} -v',f'program_verify_{role}')
        for marker in ['PRG-2014','finish command "program_spi','-m verify_spi','finish command "program -cable','finish command "download']:assert marker in log,marker
        res['boards'][role].update(programmed=True,native_verified=True);save()
    for role in 'ab':
        after=fread(role,'after');obj=objects[role];boundary=obj['boundary']
        diff=sum(a!=b for a,b in zip(after,obj['expected']))
        tail=sum(a!=b for a,b in zip(after[boundary:],obj['before'][boundary:]))
        res['boards'][role].update(full_image_compared_bytes=len(after),full_image_differences=diff,preserved_tail_differences=tail);save()
        assert diff==tail==0,(role,diff,tail)
    res['configuration_flash_pair_pass']=True;save();print('FLASH_PAIR_READBACK_PASS',flush=True)
    restore();res['startup']=startup();res['startup']['pass']=res['startup'].pop('pass_')
    res.update({'pass':True},active_operation='complete',completed_at=datetime.now(ZoneInfo('Asia/Shanghai')).isoformat());save()
    print('FLASH_COMPLETE',out,flush=True)
except BaseException as e:
    res['failure']=repr(e);res['traceback']=traceback.format_exc();print(res['traceback'],flush=True)
finally:
    if bridge and not res['sram_restored']:
        try:restore()
        except BaseException as e:res['recovery_error']=repr(e)
    save()
    h.write_json(ROOT/'reports/FLASH_DELIVERY_LATEST.json',dict(path=str(out/'result.json'),pass_=res['pass'],configuration_flash_pair_pass=res['configuration_flash_pair_pass']))
if not res['pass']:raise SystemExit(1)
