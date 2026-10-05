#!/usr/bin/env python3
"""Reference renderer for the Taito L system's TC0090LVC video: MAME 0.289's screen_update written out
literally (src/devices/machine/tc009xlvc.cpp + the tilemap and drawgfx code it uses), reading a state dumped
by tools/lua/dump.lua.  It is the executable spec for rtl/taitol_*.sv: the RTL must reproduce this, and this
must reproduce MAME's own snapshot.

  python tools/taitol_ref.py <dump prefix> <frame> [--gfx FILE] [--out FILE.png] [--cmp MAME.png] [--diff FILE.png]
                             [--spr prev|cur] [--tilecb horshoes]

The dump prefix is TL_OUT of dump.lua (e.g. work/dumps/plotting); --gfx defaults to <prefix>.gfx.bin.
"""
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import pngio  # noqa: E402

SCR_W = 320
VIS_TOP, VIS_BOT = 16, 239          # visible lines (bitmap y)
MAP_W, MAP_H = 512, 256             # 64 x 32 tiles of 8 x 8


# ---------------------------------------------------------------- gfx decode (MAME gfx_layout, MSB-first bits)
def _bit(data, n):
    return (data[n >> 3] >> (7 - (n & 7))) & 1


_PLANES = (8, 12, 0, 4)
_X8 = (3, 2, 1, 0, 19, 18, 17, 16)
_X16 = _X8 + (259, 258, 257, 256, 275, 274, 273, 272)
_Y8 = tuple(32 * i for i in range(8))
_Y16 = _Y8 + tuple(512 + 32 * i for i in range(8))


def _decode(data, code, xs, ys, charinc):
    """-> list of h rows of w pens (0..15); plane 0 is the most significant bit."""
    base = code * charinc
    rows = []
    for yo in ys:
        row = []
        for xo in xs:
            v = 0
            for p in _PLANES:
                v = (v << 1) | _bit(data, base + p + yo + xo)
            row.append(v)
        rows.append(row)
    return rows


class Gfx:
    """A byte source decoded on demand as 8x8 or 16x16 tiles; codes wrap modulo the element count."""

    def __init__(self, data):
        self.data = data
        self.n8 = len(data) // 32
        self.n16 = len(data) // 128
        self._c8, self._c16 = {}, {}

    def t8(self, code):
        code %= self.n8
        t = self._c8.get(code)
        if t is None:
            t = self._c8[code] = _decode(self.data, code, _X8, _Y8, 256)
        return t

    def t16(self, code):
        code %= self.n16
        t = self._c16.get(code)
        if t is None:
            t = self._c16[code] = _decode(self.data, code, _X16, _Y16, 1024)
        return t


# ---------------------------------------------------------------- palette
def pal5(v):
    return (v << 3) | (v >> 2)


def pal_rgb(pal):
    """256 entries of xBGRBBBBGGGGRRRR_bit0 (little endian 16 bit) -> (r,g,b) tuples."""
    out = []
    for i in range(256):
        raw = pal[2 * i] | (pal[2 * i + 1] << 8)
        r = pal5(((raw << 1) & 0x1e) | ((raw >> 12) & 1))
        g = pal5(((raw >> 3) & 0x1e) | ((raw >> 13) & 1))
        b = pal5(((raw >> 7) & 0x1e) | ((raw >> 14) & 1))
        out.append((r, g, b))
    return out


# ---------------------------------------------------------------- the chip
def eff_scroll(rowscroll, dx, dx_flipped, extent, size, flipped):
    """tilemap_t::effective_rowscroll / effective_colscroll for a single scroll value."""
    if not flipped:
        v = dx - rowscroll
    else:
        v = extent - size - (dx_flipped - rowscroll)
    return v % size


class State:
    def __init__(self, vram, pal, vregs, spr, gfxrom, bitmap=None, tilecb=None):
        self.vram, self.pal, self.vregs, self.spr = vram, pal, vregs, spr
        self.gfx = Gfx(gfxrom)                 # tile + sprite ROM
        self.chr = Gfx(vram)                   # RAM characters: all of VRAM as 8x8 tiles
        self.bitmap = bitmap
        self.tilecb = tilecb or (lambda code: code)

    @property
    def screen_enable(self): return (self.vregs[4] >> 5) & 1
    @property
    def flip(self): return (self.vregs[4] >> 4) & 1
    @property
    def bg0_pri(self): return (self.vregs[4] >> 3) & 1
    @property
    def bitmap_mode(self): return (self.vregs[4] & 7) == 7


def bg_pixmap(st, base):
    """64x32 map of {color*16+pix} for the BG layer whose tile RAM starts at vram[base] (2 bytes a tile)."""
    pm = [[0] * MAP_W for _ in range(MAP_H)]
    for ti in range(64 * 32):
        lo, attr = st.vram[base + 2 * ti], st.vram[base + 2 * ti + 1]
        code = lo | ((attr & 3) << 8) | (st.vregs[(attr & 0xc) >> 2] << 10)
        code = st.tilecb(code)
        col = attr >> 4
        t = st.gfx.t8(code)
        x0, y0 = (ti % 64) * 8, (ti // 64) * 8
        for r in range(8):
            row = pm[y0 + r]
            for c in range(8):
                row[x0 + c] = (col << 4) | t[r][c]
    return pm


def tx_pixmap(st):
    pm = [[0] * MAP_W for _ in range(MAP_H)]
    for ti in range(64 * 32):
        lo, attr = st.vram[0xa000 + 2 * ti], st.vram[0xa000 + 2 * ti + 1]
        code = lo | ((attr & 7) << 8)
        col = attr >> 4
        t = st.chr.t8(code)
        x0, y0 = (ti % 64) * 8, (ti // 64) * 8
        for r in range(8):
            row = pm[y0 + r]
            for c in range(8):
                row[x0 + c] = (col << 4) | t[r][c]
    return pm


def sample(pm, x, y, sx, sy, flip):
    """The tilemap's pixel at screen (x, y) given its effective scroll (flipping mirrors the pixmap)."""
    px, py = (x - sx) % MAP_W, (y - sy) % MAP_H
    if flip:
        px, py = MAP_W - 1 - px, MAP_H - 1 - py
    return pm[py][px]


def render(st):
    """-> 224 rows of 320 (r,g,b).  Mirrors tc0090lvc_device::screen_update."""
    rgb = pal_rgb(st.pal)
    black = (0, 0, 0)
    if not st.screen_enable:
        return [[black] * SCR_W for _ in range(VIS_BOT - VIS_TOP + 1)]

    pens = [[0] * SCR_W for _ in range(256)]
    pri = [[0] * SCR_W for _ in range(256)]
    flip = bool(st.flip)

    if st.bitmap_mode:
        for y in range(VIS_TOP, VIS_BOT + 1):
            ry = (256 - y) if flip else y
            for x in range(SCR_W):
                rx = (320 - x) if flip else x
                pens[y][x] = st.bitmap[(ry & 0xff) * 512 + (rx & 0x1ff)]
    else:
        # scroll registers (the TC0090LVC reads them live from sprite RAM / vram[B3F4..])
        v = st.vram
        def scroll(base):
            dx = v[base] | (v[base + 1] << 8)
            if flip:
                dx = ((dx & 0xfffc) | ((dx - 3) & 3)) ^ 0xf
            return dx, v[base + 2]
        dx0, dy0 = scroll(0xb3f4)
        dx1, dy1 = scroll(0xb3fc)
        # tilemap_xoffs/yoffs are 0 on this board; scrolldx: tx -8/-8, bg0 28/-11, bg1 38/-21
        sx0 = eff_scroll(-dx0, 28, -11, SCR_W, MAP_W, flip)
        sy0 = eff_scroll(-dy0, 0, 0, 256, MAP_H, flip)
        sx1 = eff_scroll(-dx1, 38, -21, SCR_W, MAP_W, flip)
        sy1 = eff_scroll(-dy1, 0, 0, 256, MAP_H, flip)
        sxt = eff_scroll(0, -8, -8, SCR_W, MAP_W, flip)
        syt = eff_scroll(0, 0, 0, 256, MAP_H, flip)

        bg0 = bg_pixmap(st, 0x8000)
        bg1 = bg_pixmap(st, 0x9000)
        tx = tx_pixmap(st)
        bg0p = 0 if st.bg0_pri else 1

        for y in range(VIS_TOP, VIS_BOT + 1):
            prow, orow = pri[y], pens[y]
            for x in range(SCR_W):
                orow[x] = sample(bg1, x, y, sx1, sy1, flip)              # opaque, priority 0
                p0 = sample(bg0, x, y, sx0, sy0, flip)
                if p0 & 15:
                    orow[x] = p0
                    prow[x] = (prow[x] & 0xff) | bg0p

        # sprites: 125 entries, in order; an opaque pixel always sets priority 31 (so the first one wins),
        # and is drawn only if (1 << pri) & pmask == 0 (pmask has bit 31 forced on)
        for e in range(0, 0x3e7, 8):
            s = st.spr
            code = s[e] | (s[e + 1] << 8)
            x = s[e + 4] | ((s[e + 5] & 1) << 8)
            if x >= SCR_W - 1:
                x -= 512
            y = s[e + 6]
            if y >= VIS_BOT:
                y -= 256
            col = s[e + 2] & 0x0f
            fx, fy = s[e + 3] & 1, (s[e + 3] >> 1) & 1
            code = st.tilecb(code << 2) >> 2
            if flip:
                x, y, fx, fy = 304 - x, 240 - y, 1 - fx, 1 - fy
            pmask = (0xaa if (col & 8) else 0) | (1 << 31)
            t = st.gfx.t16(code)
            for r in range(16):
                yy = y + r
                if yy < VIS_TOP or yy > VIS_BOT:
                    continue
                row = t[15 - r] if fy else t[r]
                for c in range(16):
                    xx = x + c
                    if xx < 0 or xx >= SCR_W:
                        continue
                    pix = row[15 - c] if fx else row[c]
                    if pix == 0:
                        continue
                    if not ((1 << (pri[yy][xx] & 0x1f)) & pmask):
                        pens[yy][xx] = (col << 4) | pix
                    pri[yy][xx] = 31

        for y in range(VIS_TOP, VIS_BOT + 1):
            orow = pens[y]
            for x in range(SCR_W):
                t = sample(tx, x, y, sxt, syt, flip)
                if t & 15:
                    orow[x] = t

    return [[rgb[pens[y][x]] for x in range(SCR_W)] for y in range(VIS_TOP, VIS_BOT + 1)]


# ---------------------------------------------------------------- IO / CLI
def load_state(prefix, frame, gfx_path=None, spr="prev", tilecb=None):
    p = '%s.f%05d' % (prefix, frame)
    rd = lambda ext: open(p + ext, 'rb').read()
    gfx = open(gfx_path or (prefix + '.gfx.bin'), 'rb').read()
    bitmap = rd('.bitmap.bin') if os.path.exists(p + '.bitmap.bin') else None
    return State(rd('.vram.bin'), rd('.pal.bin'), rd('.vregs.bin'), rd('.spr_%s.bin' % spr), gfx, bitmap, tilecb)


def to_flat(img):
    out = bytearray()
    for row in img:
        for r, g, b in row:
            out += bytes((r, g, b))
    return out


def compare(img, mame_png, diff_png=None, rot=0):
    w, h, ref = pngio.read(mame_png)
    mw, mh, mine = pngio.rotate(SCR_W, len(img), bytes(to_flat(img)), rot)       # MAME's snapshot is in the game's orientation
    if (w, h) != (mw, mh):
        print('size mismatch: mame %dx%d, mine %dx%d' % (w, h, mw, mh))
        return -1
    bad = 0
    diff = bytearray(len(mine))
    for i in range(0, len(mine), 3):
        if mine[i:i + 3] != ref[i:i + 3]:
            bad += 1
            diff[i:i + 3] = b'\xff\x00\xff'
        else:
            diff[i:i + 3] = bytes(c // 3 for c in ref[i:i + 3])
    if diff_png:
        pngio.write(diff_png, w, h, bytes(diff))
    return bad


def main(argv):
    import argparse
    ap = argparse.ArgumentParser()
    ap.add_argument('prefix')
    ap.add_argument('frame', type=int)
    ap.add_argument('--gfx')
    ap.add_argument('--out')
    ap.add_argument('--cmp')
    ap.add_argument('--diff')
    ap.add_argument('--gbank', type=lambda v: int(v, 0), default=0, help="American Horseshoes' graphics bank (B802): tile code |= gbank << 12")
    ap.add_argument('--rot', type=int, default=0, choices=(0, 90, 180, 270), help='the game rotation (MAME ROTn) of the snapshot')
    ap.add_argument('--spr', default='prev', choices=('prev', 'cur'))
    a = ap.parse_args(argv)
    st = load_state(a.prefix, a.frame, a.gfx, a.spr, tilecb=(lambda code: code | (a.gbank << 12)) if a.gbank else None)
    img = render(st)
    if a.out:
        pngio.write(a.out, SCR_W, len(img), bytes(to_flat(img)))
    if a.cmp:
        bad = compare(img, a.cmp, a.diff, a.rot)
        print('frame %d: %d of %d pixels differ' % (a.frame, bad, SCR_W * len(img)))
        return 0 if bad == 0 else 1
    return 0


if __name__ == '__main__':
    sys.exit(main(sys.argv[1:]))
