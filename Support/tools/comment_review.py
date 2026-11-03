"""Comment-only inventory and byte comparison; never opens encrypted IP."""
from pathlib import Path
import collections, difflib, json, re, sys

ROOT = Path(__file__).resolve().parents[1]
PARENT = Path('D:/fpga/anlu/work/main1/version/V15_1_low_power')
CACHE = Path('D:/aidownload/anlu_main/aaa_comment_rework_20261103')
PRAGMA = re.compile(rb'\b(?:synthesis|synopsys|translate_off|translate_on|fehdl)\b', re.I)
VERILOG = re.compile(rb'"(?:\\.|[^"\\])*"|\\[^\s]+|//[^\r\n]*|/\*[\s\S]*?\*/')
VHDL = re.compile(rb'"(?:[^"]|"")*"|--[^\r\n]*')

def spans(data, vhdl=False):
    for m in (VHDL if vhdl else VERILOG).finditer(data):
        t = m.group()
        if t.startswith((b'--',) if vhdl else (b'//', b'/*')):
            yield m

def code_bytes(data, vhdl=False):
    # Keep code whitespace byte for byte, remove comments and blank physical lines.
    out=[]; end=0
    for m in spans(data, vhdl):
        out.extend((data[end:m.start()], b'\n' * m.group().count(b'\n')))
        end=m.end()
    out.append(data[end:])
    return b'\n'.join(l for l in b''.join(out).splitlines() if l.strip())

def pragmas(data, vhdl=False):
    return [m.group() for m in spans(data,vhdl) if PRAGMA.search(m.group())]

def files(root,board):
    return [p for p in sorted((root/'source'/board).iterdir())
            if '.enc.' not in p.name and p.suffix.lower() in ('.v','.vh','.vhd')]

def stats(root, board):
    rows=[]; lengths=[]; periods=0; total=0; heads=0; modules=0
    for p in files(root,board):
        data=p.read_bytes(); text=data.decode('utf-8-sig'); comments=[]
        for m in spans(data,p.suffix=='.vhd'):
            if PRAGMA.search(m.group()): continue
            s=m.group().decode('utf-8-sig')
            body=s[2:-2] if s.startswith('/*') else s[2:]
            comments.extend(x.strip().lstrip('*').strip() for x in body.splitlines())
        cs=[x for x in comments if re.search(r'[A-Za-z\u4e00-\u9fff]',x)]
        ns=[len(re.findall(r"[A-Za-z0-9_]+(?:['-][A-Za-z0-9_]+)*|[\u4e00-\u9fff]",x)) for x in cs]
        lengths.extend(ns); nperiod=sum(c.endswith('.') for c in cs)
        periods+=nperiod; total+=len(cs)
        mod=bool(re.search(r'^\s*module\b',text,re.M)); modules+=mod
        head=bool(mod and re.search(r'`timescale[^\r\n]*(?:\r?\n\s*)+(?://[^\r\n]*\r?\n\s*|/\*[\s\S]*?\*/\s*)+module\b',text)); heads+=head
        positions=[data[:m.start()].count(b'\n')+1 for m in spans(data,p.suffix=='.vhd') if not PRAGMA.search(m.group())]
        windows=collections.Counter((pos-1)//40 for pos in positions)
        rows.append(dict(file=p.name,lines=len(text.splitlines()),comments=len(cs),periods=nperiod,header=head,
                         lengths=ns,comments_per_40_lines=[windows[i] for i in range((len(text.splitlines())+39)//40)]))
    return dict(board=board,files=len(rows),source_lines=sum(r['lines'] for r in rows),comment_units=total,
                length_bins={'1-3':sum(1<=n<=3 for n in lengths),'4-7':sum(4<=n<=7 for n in lengths),
                             '8-12':sum(8<=n<=12 for n in lengths),'13-20':sum(13<=n<=20 for n in lengths),'21+':sum(n>=21 for n in lengths)},
                word_histogram=dict(sorted(collections.Counter(lengths).items())),period_count=periods,
                period_percent=round(periods/total*100,2) if total else 0,module_files=modules,
                header_template_files=heads,header_template_percent=round(heads/modules*100,2) if modules else 0,files_detail=rows)

def write_json(path,value):
    path.parent.mkdir(parents=True,exist_ok=True)
    path.write_text(json.dumps(value,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')

def verify_board(board):
    results=[]
    for p in files(ROOT,board):
        old=(CACHE/'original'/'source'/board/p.name).read_bytes(); new=p.read_bytes()
        vhdl=p.suffix=='.vhd'
        ok=code_bytes(old,vhdl)==code_bytes(new,vhdl)
        protected=pragmas(old,vhdl)==pragmas(new,vhdl)
        results.append(dict(file=p.name,changed=old!=new,noncomment_bytes_identical=ok,tool_directives_identical=protected,
                            original_noncomment_bytes=len(code_bytes(old,vhdl)),new_noncomment_bytes=len(code_bytes(new,vhdl))))
    result=dict(board=board,pass_=all(x['noncomment_bytes_identical'] and x['tool_directives_identical'] for x in results),
                method='Byte lexer excludes strings and escaped identifiers; removes //, /* */ or VHDL -- comments and blank lines only. Code whitespace, order and all other bytes retained. Tool-directive comments compared separately.',files=results)
    write_json(ROOT/'reports'/f'ZERO_DIFF_{board.upper()}.json',result)
    assert result['pass_'],[x for x in results if not x['noncomment_bytes_identical'] or not x['tool_directives_identical']]
    print('ZERO_DIFF_PASS',board,len(results),'changed',sum(x['changed'] for x in results))
    return result

def apply_batch(board, label, edits, reasons):
    assert 1<=len(edits)<=5
    changes=[]; staged=[]
    for name,replacements in edits.items():
        assert '.enc.' not in name
        p=ROOT/'source'/board/name; before=p.read_bytes(); after=before
        eol=b'\r\n' if b'\r\n' in before else b'\n'
        for old,new in replacements:
            a=old.encode('utf-8').replace(b'\r\n',b'\n').replace(b'\n',eol)
            b=new.encode('utf-8').replace(b'\r\n',b'\n').replace(b'\n',eol)
            assert after.count(a)==1,(name,old,after.count(a))
            after=after.replace(a,b,1)
        assert code_bytes(before,p.suffix=='.vhd')==code_bytes(after,p.suffix=='.vhd'),name
        assert pragmas(before,p.suffix=='.vhd')==pragmas(after,p.suffix=='.vhd'),name
        staged.append((p,before,after))
        changes.append(dict(file=name,replacements=len(replacements),signals_renamed=[],reason=reasons[name],
                            noncomment_bytes_identical=True,tool_directives_identical=True))
    for p,before,after in staged:
        name=p.name; p.write_bytes(after)
        diff=''.join(difflib.unified_diff(before.decode('utf-8-sig').splitlines(keepends=True),after.decode('utf-8-sig').splitlines(keepends=True),fromfile='original/'+board+'/'+name,tofile='source/'+board+'/'+name))
        q=CACHE/'diffs'/board/label/(name+'.diff');q.parent.mkdir(parents=True,exist_ok=True);q.write_text(diff,encoding='utf-8',newline='')
    result=dict(board=board,batch=label,pass_=True,scope='comments and blank lines only',changes=changes)
    write_json(ROOT/'reports'/'batches'/f'{board}_{label}.json',result)
    with (ROOT/'reports'/'MILESTONES.md').open('a',encoding='utf-8') as f:
        f.write(f'\n- {board.upper()} {label}: '+', '.join(edits)+'. 非注释字节与工具指令均相同；'+ '；'.join(reasons.values())+'\n')
    print(json.dumps(result,ensure_ascii=False))

if __name__=='__main__':
    if sys.argv[1]=='baseline':
        result={b:stats(PARENT,b) for b in ('a','b')}
        write_json(ROOT/'reports'/'COMMENT_BASELINE.json',result)
        print(json.dumps({b:{k:v for k,v in d.items() if k!='files_detail'} for b,d in result.items()},ensure_ascii=False))
    elif sys.argv[1]=='verify':
        verify_board(sys.argv[2])
    elif sys.argv[1]=='after':
        b=sys.argv[2]; write_json(ROOT/'reports'/f'COMMENT_AFTER_{b.upper()}.json',stats(ROOT,b));verify_board(b)
