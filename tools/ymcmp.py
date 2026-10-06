#!/usr/bin/env python3
"""Compare the sound CPU's writes to the sound chip in MAME and in the RTL: both logs have "frame address-bits data" a line
(MAME: tools/mamedump.py --ymlog, tools/lua/ymtrace.lua; RTL: the bench's +ymlog=<file>).

  python tools/ymcmp.py mame.log rtl.log [--frames N]

Writes are compared in order. It prints how many of the first N (every write of the shorter log) are identical, the first difference and
how the frame numbers of equal writes drift (the RTL's frame count starts one off MAME's, and the two machines are a few clocks apart).
"""
import sys
from collections import Counter


def load(path):
    out = []
    for line in open(path):
        p = line.split()
        if len(p) == 3:
            out.append((int(p[0]), int(p[1]), int(p[2], 16)))
    return out


def main(argv):
    a, b = load(argv[0]), load(argv[1])
    n = min(len(a), len(b))
    if '--frames' in argv:
        lim = int(argv[argv.index('--frames') + 1])
        a = [x for x in a if x[0] <= lim]
        b = [x for x in b if x[0] <= lim]
        n = min(len(a), len(b))
    same = 0
    first = None
    for i in range(n):
        if a[i][1:] == b[i][1:]:
            same += 1
        elif first is None:
            first = i
    print('%d writes in MAME, %d in the RTL; the first %d compared: %d identical (address and data)' % (len(a), len(b), n, same))
    if first is not None:
        i = first
        print('first difference at write %d: MAME frame %d a%d=%02x   RTL frame %d a%d=%02x' % (i, a[i][0], a[i][1], a[i][2], b[i][0], b[i][1], b[i][2]))
        for j in range(max(0, i - 3), min(n, i + 4)):
            print('   %5d  MAME %3d %d %02x   RTL %3d %d %02x' % (j, a[j][0], a[j][1], a[j][2], b[j][0], b[j][1], b[j][2]))
    d = Counter(b[i][0] - a[i][0] for i in range(min(n, first if first is not None else n)))
    print('frame offset RTL - MAME of the identical writes:', dict(sorted(d.items())[:8]))
    return 0 if first is None else 1


if __name__ == '__main__':
    sys.exit(main(sys.argv[1:]))
