"""Resume the A-board physical flow from the completed placement database.

Placement, native guard and the reviewed SDC already exist; this stage performs
the post-place constraint rebind, then route, hold fixing and the final timing
gate. Every gate from the original flow is preserved.
"""
from __future__ import annotations

import json
import re
import subprocess
import sys
import time
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from scene_mapped_graph import graph, canonical  # noqa: E402

TD = r"D:\apps\anlogic\bin\td_commands_prompt.exe"
ROOT = Path(r"D:/fpga/anlu/work/main1/version/V15_low_power")
OUT = Path(r"D:/aidownload/anlu_main/main1/V15_1_low_power/build_a")
BOARD = "a"
SEED = 6
device = ["import_device eagle_s20.db -package EG4S20BG256"]
top = "scene_a_top"


def save(name, value):
    (OUT / name).write_text(json.dumps(value, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")


def run(name, lines):
    p = OUT / (name + ".tcl")
    p.write_text("\n".join(lines) + f"\nputs V3_{name.upper()}_DONE\n", encoding="utf-8")
    with (OUT / (name + ".log")).open("w", encoding="utf-8") as log:
        process = subprocess.Popen([TD], cwd=OUT, stdin=subprocess.PIPE, stdout=log,
                                   stderr=subprocess.STDOUT, text=True)
        process.stdin.write(f"source {name}.tcl\nexit\n")
        process.stdin.close()
        start = time.monotonic()
        reason = None
        rows = []
        while process.poll() is None:
            try:
                process.wait(timeout=2)
            except subprocess.TimeoutExpired:
                pass
            if name == "route":
                log.flush()
                current = (OUT / "route.log").read_text(errors="replace")
                rows = [(int(i), int(n), float(t)) for i, n, t in re.findall(
                    r"Iter (\d+):.*?over cnt = (\d+).*?time\(s\) = ([\d.]+)",
                    re.split(r"\nPHY-1001 : Stage [\d.]+ \| Rip-up And ReRoute\n", current)[-1])]
                if rows:
                    best = min(rows, key=lambda x: x[1])
                    last = rows[-1]
                    if best[1] > 0 and last[0] - best[0] >= 10 and last[1] > best[1] and last[2] >= max(30, best[2] * 1.5):
                        reason = "route stagnation: >=10 iterations without lower conflicts, rebound and slower iteration"
            if time.monotonic() - start > 2400.0:
                reason = "explicit wall time budget"
            if reason:
                subprocess.run(["taskkill.exe", "/PID", str(process.pid), "/T", "/F"],
                               stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
                process.wait(timeout=30)
                save("STOP_" + name + ".json", {"status": "ACTIVELY_ABORTED", "stage": name,
                                                "reason": reason, "elapsed_seconds": time.monotonic() - start,
                                                "route_iterations": rows, "qualified": False})
                raise RuntimeError(name + " actively stopped: " + reason)
    s = (OUT / (name + ".log")).read_text(errors="replace")
    errors = [l for l in s.splitlines()
              if re.search(r"\b(ERROR|FATAL)\b|HDL-7225|undeclared symbol", l)
              and not re.search(r"undeclared symbol '(?:\*\*|PLL_HDMI_AUDIO_open\d+)'", l)]
    if process.returncode or f"V3_{name.upper()}_DONE" not in s or errors:
        raise RuntimeError(name + ": " + repr(errors[-8:]) + s[-600:])
    print("DONE", BOARD, name, flush=True)


# 1. Post-placement constraint rebind.
from rebind_v123 import bind  # noqa: E402
if not (OUT / "v123_alias_rebinding.json").exists():
    bind(OUT, ROOT, run, device)

# 2. Capacity and hard design-limit gates.
placed_text = (OUT / "placed.area").read_text()
for metric, limit in [("bram32k", 16), ("bram9k", 64), ("dsp", 29), ("pll", 3)]:
    assert int(re.search(r"^\s*#" + metric + r"\s+(\d+)", placed_text, re.M)[1]) <= limit, ("pre-route capacity", metric)
placed_graph = graph((OUT / "placed_native.v").read_text())
mslice = sum(k == "EG_PHY_MSLICE" for k, p, w in placed_graph.values())
assert mslice <= 4900, "design hard capacity 4900"
print("PLACED_MSLICE", mslice, flush=True)

# 3. P2 constraints must survive the prune.
removed = json.loads((OUT / "sdc_post_place_pruned.json").read_text())["removed"]
assert not any("layers/prefetch" in line or "layer_snapshot" in line for line in removed), ("P2 constraint disappeared", removed)
bound_sdc = (OUT / "v3.sdc").read_text()
for x in ["bg_ret_gray[*]}] -to [get_regs {media/layers/prefetch/rb1[*]}]", "prefetch/rf1",
          "prefetch/frame_toggle", "prefetch/bg_tag", "prefetch/fg_tag", "layer_diag_snapshot"]:
    assert x in bound_sdc, ("P2 constraint absent", x)

# 4. Route with the reviewed SDC, then hold fixing and final timing.
lines = device + ["import_db placed.db", "clear_sdc", "read_sdc v3.sdc",
                  "set_param flow qor_monitor off", "set_param flow thread 8",
                  "set_param route effort routability", "set_param route priority timing",
                  "set_param route fix_hold off",
                  "report_param -all -detail -file effective_route_parameters.txt", "route",
                  "update_timing -mode final", "write_verilog before_hold.v",
                  "export_sdc_target -file before_hold.sdc", "report_timing_summary -file before_hold.timing",
                  "fix_hold", "update_timing -mode final", "write_verilog routed.v",
                  "export_sdc_target -file effective.sdc", "export_db routed.db",
                  "report_area -io_info -file routed.area", "report_io -verbose -file io.txt",
                  "report_timing_summary -file final.timing", "check_timing -verbose -file check.timing",
                  "report_route_status -drc -file route_status.txt"]
run("route", lines)

pg = graph((OUT / "routed.v").read_text())
assert canonical(graph((OUT / "before_hold.v").read_text())) == canonical(pg), "fix_hold graph changed"
assert (OUT / "before_hold.sdc").read_bytes() == (OUT / "effective.sdc").read_bytes()

timing = (OUT / "final.timing").read_text()
setup = float(re.search(r"SWNS:\s*([-+\d.]+)ns", timing)[1])
hold = float(re.search(r"HWNS:\s*([-+\d.]+)ns", timing)[1])
guard = json.loads((OUT / "native_guard.json").read_text())
report = {"board": BOARD, "setup_wns_ns": setup, "hold_wns_ns": hold,
          "native_mslice": mslice,
          "native_lslice": sum(k == "EG_PHY_LSLICE" for k, p, s in pg.values()),
          "native_guard_branches": len(guard["branches"]),
          "pass": setup >= 0 and hold >= 0, "phase": "physical_pending_audit",
          "hardware_accessed": False, "place_strategy": "default", "place_seed": SEED}
save("physical.json", report)
print(json.dumps(report), flush=True)
if not report["pass"]:
    raise RuntimeError("Final timing gate failed")
