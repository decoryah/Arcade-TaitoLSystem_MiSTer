#!/usr/bin/env python3
"""Compare two images (PNG or binary PPM): count differing pixels, optionally write a diff image.

  python tools/cmpimg.py a.ppm b.png [--diff out.png]
Exit status 0 when identical."""
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import pngio  # noqa: E402


def read_any(path):
    d = open(path, 'rb').read()
    if d[:2] == b'P6':
        # P6 <w> <h> <max> then binary RGB; header tokens may be on separate lines
        toks, i = [], 2
        while len(toks) < 3:
            while d[i:i + 1].isspace():
                i += 1
            j = i
            while not d[j:j + 1].isspace():
                j += 1
            toks.append(int(d[i:j]))
            i = j
        i += 1
        w, h = toks[0], toks[1]
        return w, h, d[i:i + w * h * 3]
    return pngio.read(path)


def main(argv):
    if len(argv) < 2:
        print(__doc__)
        return 2
    wa, ha, a = read_any(argv[0])
    if '--rot' in argv:                        # a is the native raster; b (MAME's snapshot) is in the game's orientation
        wa, ha, a = pngio.rotate(wa, ha, a, int(argv[argv.index('--rot') + 1]))
    wb, hb, b = read_any(argv[1])
    if (wa, ha) != (wb, hb):
        print('size mismatch: %dx%d vs %dx%d' % (wa, ha, wb, hb))
        return 1
    bad = 0
    diff = bytearray(len(a))
    first = None
    for i in range(0, len(a), 3):
        if a[i:i + 3] != b[i:i + 3]:
            bad += 1
            diff[i:i + 3] = b'\xff\x00\xff'
            if first is None:
                first = (i // 3 % wa, i // 3 // wa)
        else:
            diff[i:i + 3] = bytes(c // 3 for c in b[i:i + 3])
    if '--diff' in argv:
        pngio.write(argv[argv.index('--diff') + 1], wa, ha, bytes(diff))
    print('%d of %d pixels differ%s' % (bad, wa * ha, (' (first at x=%d y=%d)' % first) if first else ''))
    return 0 if bad == 0 else 1


if __name__ == '__main__':
    sys.exit(main(sys.argv[1:]))
