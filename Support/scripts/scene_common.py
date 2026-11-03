from pathlib import Path
import json
ROOT=Path(__file__).resolve().parents[1]
CACHE=Path('D:/aidownload/anlu_main/aaa_comment_rework_20261103')
def write_json(p,v):Path(p).write_text(json.dumps(v,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
