"""Placement-only scan over seeds, to pick a routable basin before spending route time.

Each seed gets an isolated directory with the same protected netlist, the same
reviewed SDC and the same 75 floorplan anchors. Only the placer seed varies.
"""
from __future__ import annotations

import json
import re
import shutil
import subprocess
import sys
import time
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from scene_mapped_graph import graph  # noqa: E402

TD = r"D:\apps\anlogic\bin\td_commands_prompt.exe"
BASE = Path(r"D:/aidownload/anlu_main/main1/V14_clean/build_a")
ROOT = Path(r"D:/aidownload/anlu_main/main1/V14_clean")
seeds = [int(s) for s in sys.argv[1:]] or [3, 4, 5, 7, 8]

device = ["import_device eagle_s20.db -package EG4S20BG256"]
anchors = [l for l in (BASE / "place_pins.tcl").read_text().splitlines() if l.strip()]
results = {}

for seed in seeds:
    out = ROOT / f"scan_a_s{seed}"
    if out.exists():
        shutil.rmtree(out)
    out.mkdir(parents=True)
    for n in ("protected.db", "synthesized.v"):
        shutil.copy2(BASE / n, out / n)
    # Placement runs on the pre-rebind constraint set, exactly as the delivered flow did.
    shutil.copy2(BASE / "v3_before_alias_rebind.sdc", out / "v3.sdc")

    lines = device + ["import_db protected.db", "read_sdc v3.sdc",
                      "set_param flow qor_monitor off", "set_param flow thread 8",
                      "set_param place effort high", f"set_param place seed {seed}",
                      "set_inst_assignment {media/memory/memory/u2_ram/u2_wrrd/sdr_t_reg} {location = x21y34z1;}"]
    lines += anchors
    lines += ["place", "report_area -io_info -file placed.area",
              "write_verilog placed_native.v", "puts PLACE_DONE"]
    (out / "place.tcl").write_text("\n".join(lines) + "\n", encoding="utf-8")
    start = time.monotonic()
    with (out / "place.log").open("w", encoding="utf-8") as log:
        p = subprocess.Popen([TD], cwd=out, stdin=subprocess.PIPE, stdout=log,
                             stderr=subprocess.STDOUT, text=True)
        p.stdin.write("source place.tcl\nexit\n")
        p.stdin.close()
        p.wait(timeout=1200)
    txt = (out / "place.log").read_text(errors="replace")
    ok = "PLACE_DONE" in txt and (out / "placed_native.v").exists()
    if not ok:
        results[seed] = {"ok": False}
        print("SEED", seed, "FAILED", round(time.monotonic() - start), "s", flush=True)
        continue
    g = graph((out / "placed_native.v").read_text())
    mslice = sum(k == "EG_PHY_MSLICE" for k, p, w in g.values())
    area = (out / "placed.area").read_text()
    lut = int(re.search(r"^\s*#lut\s+(\d+)", area, re.M)[1])
    reg = int(re.search(r"^\s*#reg\s+(\d+)", area, re.M)[1])
    results[seed] = {"ok": True, "mslice": mslice, "lut": lut, "reg": reg,
                     "seconds": round(time.monotonic() - start, 1)}
    print("SEED", seed, "MSLICE", mslice, "LUT", lut, "REG", reg,
          round(time.monotonic() - start, 1), "s", flush=True)

(BASE.parent / "reports" / "place_seed_scan.json").write_text(
    json.dumps(results, indent=1) + "\n", encoding="utf-8")
best = min((v["mslice"], k) for k, v in results.items() if v["ok"])
print("BEST_SEED", best[1], "MSLICE", best[0])
