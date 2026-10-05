#!/usr/bin/env python3
"""Whole-machine check: the RTL's machine state (sim/run_system.sh ... +state=F1,F2 -> <prefix>.fNNNNN.*) against MAME's.

  python tools/cmprtl.py <set> <rtl prefix> <frame> [<frame> ...] [--rot N] [--gbank N] [--dumps work/dumps/<name>] [--snap NAME]

For each frame it prints
  * how many pixels differ between the reference renderer's picture of the RTL state and MAME's own snapshot,
  * which of the state files (VRAM, palette, video registers, sprite RAM before / after the copy) differ from MAME's dump
    and in how many bytes.
The reference renderer is itself checked against MAME's snapshots from MAME's own state (tools/taitol_ref.py), so a clean
line here means the RTL machine (CPU, board, video) is in the state MAME is in. Exit status: number of frames with a difference.
"""
import argparse
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import paths  # noqa: E402
import taitol_ref  # noqa: E402

ROOT = paths.BASE                                    # work/ and ref/ live here (tools/paths.py)
KINDS = ('vram', 'pal', 'vregs', 'spr_cur', 'spr_prev')


def main(argv):
    ap = argparse.ArgumentParser()
    ap.add_argument('game')
    ap.add_argument('rtl')
    ap.add_argument('frames', type=int, nargs='+')
    ap.add_argument('--rot', type=int, default=0)
    ap.add_argument('--gbank', type=lambda v: int(v, 0), default=0)
    ap.add_argument('--dumps', help='MAME dump prefix (default work/dumps/<game>)')
    ap.add_argument('--snap', help='snapshot name (default <game>)')
    ap.add_argument('--gfx', help='graphics ROM dump (default <dumps>.gfx.bin)')
    a = ap.parse_args(argv)
    dumps = a.dumps or os.path.join(ROOT, 'work', 'dumps', a.game)
    snap = a.snap or a.game
    gfx = a.gfx or dumps + '.gfx.bin'
    tilecb = (lambda code: code | (a.gbank << 12)) if a.gbank else None
    bad_frames = 0
    for f in a.frames:
        n = '%05d' % f
        if not os.path.exists('%s.f%s.vram.bin' % (a.rtl, n)):
            print('f%s: no RTL state (%s.f%s.*)' % (n, a.rtl, n))
            bad_frames += 1
            continue
        st = taitol_ref.load_state(a.rtl, f, gfx, 'prev', tilecb=tilecb)
        img = taitol_ref.render(st)
        png = os.path.join(ROOT, 'work', 'mame', 'snap', '%s.f%s.png' % (snap, n))
        bad = taitol_ref.compare(img, png, None, a.rot)
        diffs = []
        for k in KINDS + (('bitmap',) if os.path.exists('%s.f%s.bitmap.bin' % (a.rtl, n)) else ()):
            x = open('%s.f%s.%s.bin' % (a.rtl, n, k), 'rb').read()
            y = open('%s.f%s.%s.bin' % (dumps, n, k), 'rb').read()
            nd = sum(1 for i in range(min(len(x), len(y))) if x[i] != y[i]) + abs(len(x) - len(y))
            if nd:
                diffs.append('%s %d' % (k, nd))
        print('f%s: picture %s   state %s' % (n, ('IDENTICAL' if bad == 0 else '%d px differ' % bad), ('identical' if not diffs else 'differs: ' + ', '.join(diffs))))
        if bad != 0 or diffs:
            bad_frames += 1
    return bad_frames


if __name__ == '__main__':
    sys.exit(main(sys.argv[1:]))
