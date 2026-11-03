"""Query sealed physical databases into a new directory, never modifying originals."""
from pathlib import Path
import concurrent.futures, json, re, subprocess
from comment_review import CACHE,ROOT,write_json
TD='D:/apps/anlogic/bin/td_commands_prompt.exe'
SOURCES={'a':Path('D:/aidownload/anlu_main/main1/V15_low_power/route_a_seed7'),
         'b':Path('D:/aidownload/anlu_main/main1/V15_1_low_power/route_b_seed3')}
def query(board):
    src=SOURCES[board];out=CACHE/('baseline_'+board);out.mkdir(exist_ok=False)
    lines=['import_device eagle_s20.db -package EG4S20BG256',f'import_db {{{(src/"routed.db").as_posix()}}}',
           'set_param flow thread 4','update_timing -mode final','report_area -io_info -file baseline.area',
           'report_timing_summary -file baseline.timing','check_timing -verbose -file baseline.check',
           'report_route_status -drc -file baseline.route_status','puts BASELINE_QUERY_DONE']
    (out/'query.tcl').write_text('\n'.join(lines)+'\n',encoding='utf-8')
    with (out/'query.log').open('w',encoding='utf-8') as log:
        p=subprocess.Popen([TD],cwd=out,stdin=subprocess.PIPE,stdout=log,stderr=subprocess.STDOUT,text=True)
        p.stdin.write('source query.tcl\nexit\n');p.stdin.close();code=p.wait(timeout=300)
    log=(out/'query.log').read_text(errors='replace')
    assert code==0 and 'BASELINE_QUERY_DONE' in log and not re.search(r'\b(ERROR|FATAL)\b',log),log[-2500:]
    timing=(out/'baseline.timing').read_text();area=(out/'baseline.area').read_text()
    result={'board':board,'source_db':str(src/'routed.db'),'fresh_readonly_query':True,'setup_ns':float(re.search(r'SWNS:\s*([-+\d.]+)ns',timing)[1]),
            'hold_ns':float(re.search(r'HWNS:\s*([-+\d.]+)ns',timing)[1]),
            'TNS':float(re.search(r'STNS:\s*([-+\d.]+)ns',timing)[1]),'THS':float(re.search(r'HTNS:\s*([-+\d.]+)ns',timing)[1]),
            'resources':{k:int(re.search(r'^\s*#'+k+r'\s+(\d+)',area,re.M)[1]) for k in ('lut','reg','bram9k','bram32k','dsp')},
            'original_native_mslice_evidence':str(src/'physical.json'),'source_report':json.loads((src/'physical.json').read_text()),'output':str(out)}
    write_json(ROOT/'reports'/f'BASELINE_PHYSICAL_{board.upper()}.json',result)
    print(json.dumps(result,ensure_ascii=False),flush=True)
if __name__=='__main__':
    with concurrent.futures.ThreadPoolExecutor(2) as pool:
        list(pool.map(query,('a','b')))
