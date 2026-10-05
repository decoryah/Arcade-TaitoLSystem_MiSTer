#!/usr/bin/env python3
"""Turn a state dumped by tools/lua/dump.lua into the hex files the Verilator video bench reads.

  python tools/tb_prep.py <dump prefix> <frame> <out dir> [--gfx FILE]

Writes <out>/{vram,sprprev,pal,vregs}.hex (one byte a line), <out>/gfx.hex (16-bit little-endian words, one a line)
and prints the tile count (+gfxn=) the bench needs."""
import os
import sys


def hexbytes(path, data):
    with open(path, 'w') as f:
        f.write(''.join('%02x\n' % b for b in data))


def main(argv):
    if len(argv) < 3:
        print(__doc__)
        return 2
    prefix, frame, out = argv[0], int(argv[1]), argv[2]
    gfxp = argv[argv.index('--gfx') + 1] if '--gfx' in argv else prefix + '.gfx.bin'
    os.makedirs(out, exist_ok=True)
    p = '%s.f%05d' % (prefix, frame)
    rd = lambda ext: open(p + ext, 'rb').read()
    hexbytes(os.path.join(out, 'vram.hex'), rd('.vram.bin'))
    hexbytes(os.path.join(out, 'sprprev.hex'), rd('.spr_prev.bin'))
    hexbytes(os.path.join(out, 'pal.hex'), rd('.pal.bin'))
    hexbytes(os.path.join(out, 'vregs.hex'), rd('.vregs.bin')[:8])
    gfx = open(gfxp, 'rb').read()
    if len(gfx) % 2:
        gfx += b'\0'
    with open(os.path.join(out, 'gfx.hex'), 'w') as f:
        f.write(''.join('%04x\n' % (gfx[i] | (gfx[i + 1] << 8)) for i in range(0, len(gfx), 2)))
    print(len(gfx) // 32)
    return 0


if __name__ == '__main__':
    sys.exit(main(sys.argv[1:]))
