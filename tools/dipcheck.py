#!/usr/bin/env python3
"""Check that the DIP switches reach the game the way they do in MAME: for a set, take MAME's default DIP bytes, switch "Service Mode" on (and,
separately, "Flip Screen" on, "Cabinet" to cocktail), run MAME and the RTL with those bytes from the start, and compare the machine state
and picture at frame 300 (attract mode, before the scripted coin).

  python tools/dipcheck.py [-j N] [--build TAG] [--variants svc,flip,cab] <set> [<set> ...]

The bytes come from MAME's own -listxml (the same source as the MRA's switch definitions) and are applied through the DIP fields' user values.
Output: one line a set and variant. Needs work/<set>.rom and the set's MAME dumps (tools/mamedump.py) for the graphics ROM.
"""
import argparse
import os
import subprocess
import sys
import time
import xml.etree.ElementTree as ET

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import make_mra  # noqa: E402
import paths  # noqa: E402
import rtlrun  # noqa: E402
import taitol_rom as T  # noqa: E402

ROOT = paths.BASE                                    # work/ and ref/ live here (tools/paths.py)
WANT = {'svc': 'Service Mode', 'flip': 'Flip Screen', 'cab': 'Cabinet'}
ON = {'svc': 'On', 'flip': 'On', 'cab': 'Cocktail'}


def dip_bytes(name, variant):
    """-> 'DSWA,DSWB' hex with the field `variant` switched on, or None if the set has no such switch"""
    xml = subprocess.run([make_mra.MAME, name, '-rompath', T.DEFAULT_ROMDIR, '-listxml'], capture_output=True, text=True,
                         cwd=os.path.join(ROOT, 'work', 'mame')).stdout
    root = ET.fromstring(xml)
    machine = [m for m in root.iter('machine') if m.get('name') == name][0]
    cur = {'DSWA': 0, 'DSWB': 0}
    target = None
    for d in machine.iter('dipswitch'):
        tag, mask = d.get('tag'), int(d.get('mask'))
        if tag not in cur:
            continue
        for v in d.iter('dipvalue'):
            if v.get('default') == 'yes':
                cur[tag] |= int(v.get('value')) & mask
        if d.get('name') == WANT[variant]:
            for v in d.iter('dipvalue'):
                if v.get('name') == ON[variant]:
                    target = (tag, mask, int(v.get('value')))
    if target is None:
        return None
    tag, mask, val = target
    cur[tag] = (cur[tag] & ~mask) | val
    return '%02X,%02X' % (cur['DSWA'], cur['DSWB'])


def main(argv):
    ap = argparse.ArgumentParser()
    ap.add_argument('sets', nargs='+')
    ap.add_argument('-j', type=int, default=4)
    ap.add_argument('--build', default='p3')
    ap.add_argument('--variants', default='svc,flip,cab')
    ap.add_argument('--frames', type=int, default=305)
    a = ap.parse_args(argv)
    games = T.parse_driver()[1]
    jobs = []
    for n in a.sets:
        for v in a.variants.split(','):
            dip = dip_bytes(n, v)
            if dip is None:
                print('%s %s: the set has no such switch' % (n, v))
                continue
            subprocess.run([sys.executable, os.path.join(HERE, 'mamedump.py'), '--frames', '300', '--dip', dip, '--tag', v, '--seconds', '8', n],
                           capture_output=True)
            jobs.append((n, v, dip))
    pending, running, bad = list(jobs), {}, 0
    while pending or running:
        while pending and len(running) < a.j:
            n, v, dip = pending.pop(0)
            running[(n, v, dip)] = rtlrun.launch(n, a.build, a.frames, dip, v, [300])
        time.sleep(5)
        for key in list(running):
            p, log = running[key]
            if p.poll() is not None:
                log.close()
                del running[key]
                n, v, dip = key
                vn = '%s_%s' % (n, v)
                rot = {'ROT0': 0, 'ROT90': 90, 'ROT180': 180, 'ROT270': 270}[games[n]['rot']]
                r = subprocess.run([sys.executable, os.path.join(HERE, 'cmprtl.py'), n, os.path.join(ROOT, 'work', 'sim', vn), '300', '--rot', str(rot),
                                    '--dumps', os.path.join(ROOT, 'work', 'dumps', vn), '--snap', vn, '--gfx', os.path.join(ROOT, 'work', 'dumps', n + '.gfx.bin')],
                                   capture_output=True, text=True)
                print('%-10s %-5s DSW %s: %s' % (n, v, dip, (r.stdout.strip() or r.stderr.strip()[-200:])), flush=True)
                bad += r.returncode != 0
    return bad


if __name__ == '__main__':
    sys.exit(main(sys.argv[1:]))
