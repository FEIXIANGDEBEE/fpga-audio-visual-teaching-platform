"""User-authorized exact V6_1 configuration Flash delivery; B then A.

Reuse qualified bit identities and the existing 180 s acceptance. Preserve both
complete devices before writing. Native program/verify plus full byte comparison.
"""
from pathlib import Path
import argparse
import hashlib
import json
import re
import shutil
import time
import traceback
import hardware_library as h

ROOT = Path(__file__).resolve().parents[1]
CACHE = Path('D:/aidownload/anlu_main/main1/V6_1')
OLD = ROOT.parent / 'V1/flash_delivery_20261019'
FLASH_BYTES = 2097152


def read(path):
    return json.loads(Path(path).read_text(encoding='utf-8'))


def flash_image(bit):
    """TD binary packets: 16-bit big-endian bit count followed by data bytes.

    This decoder matches both complete manufacturer-verified historical images.
    Native program_spi erases the remaining device to FF.
    """
    data = Path(bit).read_bytes()
    assert data.startswith(b'# Anlogic ASCII Bitstream\n')
    pos = data.index(b'\n\n') + 2
    payload = bytearray()
    while pos < len(data):
        assert pos + 2 <= len(data), 'Truncated packet header'
        bits = int.from_bytes(data[pos:pos + 2], 'big')
        pos += 2
        assert bits > 0 and bits % 8 == 0, 'Unsupported bit packet'
        size = bits // 8
        assert pos + size <= len(data), 'Truncated packet data'
        payload.extend(data[pos:pos + size])
        pos += size
    assert 600000 < len(payload) < FLASH_BYTES
    assert payload[:32] == b'\xff' * 32 and payload[32:36] == bytes.fromhex('cc55aa33')
    return bytes(payload) + b'\xff' * (FLASH_BYTES - len(payload)), len(payload)


def startup(out, identity):
    dev = {}
    result = {'pass': False, 'method': 'exact qualified SRAM restored after Flash bridge',
              'cold_boot_verified': False, 'serial_closed': False}
    try:
        for role in 'ab':
            dev[role] = h.Uart(role, identity['uart'][role], out, identity['baudrate'][role])
        a, b = dev['a'], dev['b']
        aq, bq = h.wait_ready(a, b, timeout=90)
        assert aq[0] == 0x020a0001 and bq[0] == 0x020b0001, (aq, bq)
        assert aq[2] & 15 == 0 and bq[2] & 15 == 0
        assert not any(aq[4:]) and not any(bq[4:])
        ss, bn, bi, av = a.frame('S'), b.frame('N'), b.frame('I'), a.frame('V')
        assert ss[0] == 0x060a0002 and bn[0] == 0x060b0001
        deadline = time.monotonic() + 30
        while bi[2] != 0x3fff:
            assert not any(bi[i] for i in (4, 5, 7)), bi
            assert time.monotonic() < deadline, ('Catalog not valid', bi)
            time.sleep(.3)
            bi = b.frame('I')
        assert not any(bi[i] for i in (4, 5, 7)), bi
        assert ss[5] == 0 and not ss[6] & 0xf0 and bn[2] == 0
        assert not any(av[i] for i in (4, 5, 7))
        ref = read(ROOT / 'references/PIXEL_REFERENCE.json')['pages'][0]
        assert av[6] == int(ref['display_crc32'], 16)
        first = a.frame('V')
        time.sleep(.6)
        last = a.frame('V')
        assert last[2] > first[2]
        bp, bc, bm = b.frame('P'), b.frame('C'), b.frame('M')
        assert not bp[1] & 0x3b800 and not bc[3] & 0x7f and bm[1] & 15 == 0
        result.update(pass_=True, **{'pass': True}, A_Q=aq, B_Q=bq, A_S=ss, B_N=bn,
                      B_I=bi, A_V=last, B_P=bp, B_C=bc, B_M=bm,
                      final_state='page 1 READY, manual, menu/diagnostic/pause/mute/HOLD/listening off')
        return result
    finally:
        for device in dev.values():
            device.close()
        result['serial_closed'] = True
        h.write_json(out / 'startup.json', result)


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--execute', action='store_true')
    args = parser.parse_args()
    if not args.execute:
        raise SystemExit('No hardware action; explicit --execute required.')
    pair = read(ROOT / 'ACTIVE_PAIR.json')
    assert pair['version'] == 'V6_1'
    assert pair['status'] == 'V6_1_SRAM_INTERNAL_ACCEPTANCE_180S_PASS'
    acceptance = read(ROOT / 'reports/HARDWARE_ACCEPTANCE_V6_1.json')
    assert acceptance['pass'] and acceptance['stability']['seconds'] >= 180
    assert read(ROOT / 'reports/SRAM_READBACK_V3.json')['pass']
    identity = read(ROOT / 'reports/HARDWARE_IDENTITY_V3.json')
    assert identity['pass'] and identity['jtag'] == {'b': 0, 'a': 1}
    out = CACHE / 'flash_delivery' / time.strftime('%Y%m%d_%H%M%S')
    out.mkdir(parents=True, exist_ok=False)
    shutil.copy2(__file__, out / Path(__file__).name)
    result = {'version': 'V6_1', 'pass': False, 'boards': {}, 'path': str(out),
              'authorization': '测试没问题以后简洁快速的方法帮我烧录到flash里面。',
              'reused_stability_seconds': acceptance['stability']['seconds'],
              'reused_acceptance': str(ROOT / 'reports/HARDWARE_ACCEPTANCE_V6_1.json'),
              'identity_reused': identity, 'tf_written': False, 'cold_boot_verified': False,
              'configuration_flash_write_attempted': False, 'configuration_flash_pair_pass': False,
              'serial_closed': True, 'sram_restored': False}
    expected, original_stat = {}, {}

    def save():
        h.write_json(out / 'result.json', result)

    def command(text, label, timeout=300):
        result['active_operation'] = label
        save()
        print('FLASH_BEGIN', label, flush=True)
        log = h.bw(text, label, out, timeout)
        print('FLASH_DONE', label, flush=True)
        return log

    def flash_read(role, stage):
        path = out / f'{role}_flash_{stage}.bin'
        cable = identity['jtag'][role]
        log = command(f'read_flash -start_addr 0x0 -length {FLASH_BYTES} -output {{{path.as_posix()}}} -cable {cable}', f'read_{stage}_{role}')
        assert 'finish command "read_flash' in log
        data = path.read_bytes()
        assert len(data) == FLASH_BYTES and len(set(data)) > 1
        result['boards'][role][stage] = {'path': str(path), 'bytes': len(data)}
        save()
        return data

    def restore():
        for role in ('b', 'a'):
            bit = Path(pair['boards'][role]['bit'])
            stat = bit.stat()
            assert (stat.st_size, stat.st_mtime_ns) == original_stat[role]
            log = command(f'download -bit {{{bit.as_posix()}}} -mode jtag -cable {identity["jtag"][role]}', f'restore_exact_sram_{role}', 150)
            assert 'PRG-2014' in log and 'finish command "download' in log
        result['sram_restored'] = True
        save()

    bridge_accessed = False
    try:
        historical = read(OLD / 'result.json')
        for role in ('b', 'a'):
            # Validate format against reliable existing full readback, without hashing.
            old_expected, _ = flash_image(historical['selected_pair'][role]['bit'])
            assert old_expected == (OLD / f'{role}_flash_after.bin').read_bytes()
            row = pair['boards'][role]
            bit = Path(row['bit'])
            expected[role], payload_bytes = flash_image(bit)
            stat = bit.stat()
            original_stat[role] = (stat.st_size, stat.st_mtime_ns)
            result['boards'][role] = {'bit': row['bit'], 'bit_sha256_reused': row['sha256'],
                                     'mask_sha256_reused': row['mask_sha256'],
                                     'cable': identity['jtag'][role], 'payload_bytes': payload_bytes,
                                     'programmed': False, 'native_verified': False}
        listing = command('list_cable', 'list_cable')
        assert re.findall(r'^(\d+):EG4S20BG256', listing, re.M) == ['0', '1']
        # Both complete backups must exist before the first erase/write.
        for role in ('b', 'a'):
            bridge_accessed = True
            log = command(f'get_flash_manufacturer -cable {identity["jtag"][role]}', f'manufacturer_{role}')
            for key, value in [('Manufacturer ID', 'ef'), ('Interface type', '40'), ('Density and Feature', '15')]:
                assert re.search(re.escape(key) + r'\s*:\s*' + value + r'\b', log, re.I), log
            before = flash_read(role, 'before')
            assert before == (OLD / f'{role}_flash_after.bin').read_bytes(), 'Unexpected previous Flash contents: ' + role
            result['boards'][role]['before_matches_known_V1_flash'] = True
        result['both_full_2mib_backups_pass'] = True
        save()
        print('BOTH_FULL_FLASH_BACKUPS_PASS', flush=True)
        for role in ('b', 'a'):
            bit = Path(pair['boards'][role]['bit'])
            stat = bit.stat()
            assert (stat.st_size, stat.st_mtime_ns) == original_stat[role]
            before = Path(result['boards'][role]['before']['path']).read_bytes()
            if before == expected[role]:
                result['boards'][role].update(retained_already_exact=True, full_image_differences=0)
                continue
            result['configuration_flash_write_attempted'] = True
            result['boards'][role]['write_attempted'] = True
            save()
            log = command(f'download -bit {{{bit.as_posix()}}} -mode program_spi -cable {identity["jtag"][role]} -v', f'program_verify_{role}')
            for marker in ['PRG-2014', 'finish command "program_spi', '-m verify_spi', 'finish command "program -cable', 'finish command "download']:
                assert marker in log, 'Missing native completion marker: ' + marker
            result['boards'][role].update(programmed=True, native_verified=True)
            after = flash_read(role, 'after')
            differences = sum(a != b for a, b in zip(after, expected[role]))
            result['boards'][role].update(full_image_compared_bytes=FLASH_BYTES, full_image_differences=differences)
            assert differences == 0, 'Full Flash byte comparison failed: ' + role
            save()
        result['configuration_flash_pair_pass'] = True
        save()
        print('EXACT_V6_1_FLASH_PAIR_PASS', flush=True)
        restore()
        result['startup'] = startup(out, identity)
        assert result['startup']['pass']
        result.update(**{'pass': True}, active_operation='complete')
        print('FLASH_DELIVERY_PASS', str(out), flush=True)
    except BaseException as exc:
        result.update(failure=repr(exc), traceback=traceback.format_exc())
        print('FLASH_DELIVERY_FAIL', repr(exc), flush=True)
    finally:
        if bridge_accessed and not result['sram_restored']:
            try:
                restore()
            except BaseException as exc:
                result['recovery_error'] = repr(exc)
        # Seal newly captured Flash images once; existing bit/mask identities are reused.
        for row in result['boards'].values():
            for stage in ('before', 'after'):
                if stage in row:
                    path = Path(row[stage]['path'])
                    row[stage]['sha256'] = hashlib.sha256(path.read_bytes()).hexdigest()
        save()
        h.write_json(ROOT / 'reports/FLASH_V6_1.json', result)
        h.write_json(CACHE / 'flash_delivery/latest.json', {'path': str(out / 'result.json'), 'pass': result['pass']})
    if not result['pass']:
        raise SystemExit(1)


if __name__ == '__main__':
    main()
