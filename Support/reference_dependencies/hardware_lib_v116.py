"""V11.1 hardware operations (identity, SRAM program, exact readback, UART frames).

Derived from the V10.11 library, with one deliberate difference: the UART row
parser accepts both the compacted four-word frame (V11.1) and the legacy
eight-word frame (the parent bitstreams still on the boards). Only SRAM/JTAG/UART
operations are used at this layer; Flash writes live in program_flash_v111.py.
"""
from pathlib import Path
import json, re, subprocess, time, sys
import serial
from serial.tools import list_ports

ROOT = Path(__file__).resolve().parents[1]
CACHE = Path('D:/aidownload/anlu_main/main1/V13_5_filtered_spectrum')
BW = Path(r'D:\apps\anlogic\bin\bw_commands_prompt.exe')
# 4 or 8 words of 8 hex digits, separated by single spaces.
ROW = re.compile(rb'V1[345]([AB]) ([A-Z]) ((?:[0-9a-fA-F]{8} ?)+)')


def outdir(topic):
    p = CACHE / topic / time.strftime('%Y%m%d_%H%M%S')
    p.mkdir(parents=True, exist_ok=False)
    return p


def write_json(path, obj):
    Path(path).write_text(json.dumps(obj, ensure_ascii=False, indent=2) + '\n', encoding='utf-8')


def bw(command, label, out, timeout=240):
    (out / (label + '.tcl')).write_text(command + '\n', encoding='utf-8')
    with (out / (label + '.log')).open('w', encoding='utf-8') as log:
        p = subprocess.Popen([str(BW)], cwd=out, stdin=subprocess.PIPE, stdout=log, stderr=subprocess.STDOUT, text=True)
        try:
            p.communicate(command + '\nexit\n', timeout=timeout)
        except subprocess.TimeoutExpired:
            subprocess.run(['taskkill.exe', '/PID', str(p.pid), '/T', '/F'], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
            raise
    text = (out / (label + '.log')).read_text(errors='replace')
    if p.returncode or re.search(r'\b(ERROR|FATAL)\b', text, re.I):
        raise RuntimeError(label + ' failed\n' + text[-3000:])
    return text


def parse_svf(path):
    rows = []
    for m in re.finditer(r'SDR\s+(\d+)\s+(.*?);', Path(path).read_text(), re.S):
        n = int(m[1])
        tdo = re.search(r'TDO\s*\(([0-9a-fA-F\s]+)\)', m[2])
        mask = re.search(r'MASK\s*\(([0-9a-fA-F\s]+)\)', m[2])
        if n == 3904 and tdo:
            rows.append((n, int(re.sub(r'\s+', '', tdo[1]), 16),
                         int(re.sub(r'\s+', '', mask[1]), 16) if mask else (1 << n) - 1))
    if sum(x[0] for x in rows) < 4900000:
        raise RuntimeError('Incomplete SVF ' + str(path))
    return rows


class Uart:
    def __init__(self, role, port, out, baud):
        self.role = role.upper()
        self.raw = (out / (self.role + '_uart.raw')).open('ab')
        self.s = serial.Serial(port=None, baudrate=baud, timeout=.03)
        self.s.dtr = False
        self.s.rts = False
        self.s.port = port
        self.s.open()

    def send(self, c):
        self.s.write(c.encode('ascii'))
        self.s.flush()

    def frame(self, q, timeout=4):
        self.s.reset_input_buffer()
        self.send(q + '?')
        buf = bytearray()
        end = time.monotonic() + timeout
        while time.monotonic() < end:
            d = self.s.read(max(1, self.s.in_waiting))
            self.raw.write(d)
            buf.extend(d)
            while b'\n' in buf:
                line, _, rest = buf.partition(b'\n')
                buf = bytearray(rest)
                m = ROW.fullmatch(line.strip())
                if m and m[1].decode() == self.role and m[2].decode() == q:
                    self.raw.flush()
                    self.last_protocol=m[0][:3].decode('ascii')
                    return [int(x, 16) for x in m[3].split()]
        raise RuntimeError(f'UART timeout {self.role} {q}')

    def close(self):
        try:
            self.s.close()
        finally:
            self.raw.close()


def uart_roles(out):
    found, bauds = {}, {}
    ports = [p for p in list_ports.comports() if (p.vid, p.pid) == (0x1a86, 0x7523)]
    if len(ports) != 2:
        raise RuntimeError('Expected exactly two CH340 board UARTs')
    for p in ports:
        role = None
        for baud in (115200, 460800):
            raw = bytearray()
            s = serial.Serial(port=None, baudrate=baud, timeout=.03)
            s.dtr = False
            s.rts = False
            s.port = p.device
            with s:
                s.write(b'Q?')
                end = time.monotonic() + 2
                while time.monotonic() < end:
                    raw.extend(s.read(max(1, s.in_waiting)))
                    m = ROW.findall(raw)
                    if m:
                        role = m[-1][0].decode().lower()
                        break
            (out / f'{p.device}_{baud}_probe.raw').write_bytes(raw)
            if role:
                break
        if role not in ('a', 'b') or role in found:
            raise RuntimeError('Ambiguous UART role ' + str(p.device))
        found[role] = p.device
        bauds[role] = baud
    return found, bauds


def read_sram(out, cable, label):
    path = out / (label + '.dat')
    bw(f'read_sram -level 1 -total 1 -cable {cable} -output {{{path.as_posix()}}}', 'read_' + label, out)
    rows = [s.strip() for s in path.read_text().splitlines() if re.fullmatch('[01]+', s.strip())]
    return rows, path


def score(actual, expected):
    if len(actual) != len(expected) or any(len(s) != n for s, (n, t, m) in zip(actual, expected)):
        raise RuntimeError('SRAM read shape mismatch')
    diff = sum(((int(s[::-1], 2) ^ t) & m).bit_count() for s, (n, t, m) in zip(actual, expected))
    mask = sum(m.bit_count() for n, t, m in expected)
    return diff, mask


def svf(bit, out, label):
    path = out / (label + '.svf')
    bw(f'svfgen -scan_mode prog_sram -level 1 -total 1 -bypass 11111111 -bit {{{Path(bit).as_posix()}}} '
       f'-svf {{{path.as_posix()}}} -verify -header', 'svf_' + label, out)
    return parse_svf(path)


def wait_ready(a, b, timeout=180):
    """A status bit7 ready / bit6 busy / bit5 fault; B bit8 ready / bit9 busy / bit10 fault."""
    end = time.monotonic() + timeout
    last = None
    while time.monotonic() < end:
        aq, bq = a.frame('Q'), b.frame('Q')
        ast, bst = aq[1], bq[1]
        if ast & 0x20 or bst & 0x400:
            raise RuntimeError('Startup fault A=%08x B=%08x' % (ast, bst))
        if (ast & 0x80) and not (ast & 0x40) and (bst & 0x100) and not (bst & 0x200):
            return aq, bq
        last = (aq, bq)
        time.sleep(.3)
    raise RuntimeError('Startup did not reach READY ' + repr(last))
