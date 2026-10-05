#!/usr/bin/env python3
"""Taito L ROM images, built straight from the ROM_START definitions of MAME's taito_l.cpp and the user's
(merged) MAME ROM zips, and packed into the flat image the core's loader takes.

  python tools/taitol_rom.py list
  python tools/taitol_rom.py build <set> [--romdir DIR] [--out FILE.rom] [--regions DIR]
  python tools/taitol_rom.py check <set> <mame-dump-prefix>      compare regions with dump.lua's TL_REGIONS output

Regions are built the way MAME does it (ROM_LOAD, ROM_LOAD16_BYTE, ROM_LOAD32_BYTE, ROM_CONTINUE; region fill 00, or FF
with ROMREGION_ERASEFF), with the one init the driver applies to ROM data (plottinga: bit-reversed program).

Flat image layout (byte offsets; the core's SDRAM word address is offset / 2, first byte in the low half):

  000000-0FFFFF  maincpu       program (TC0090LVC's ROM)
  100000-27FFFF  maincpu:gfx   tile and sprite ROM, in MAME's region byte order
  280000-2FFFFF  audiocpu      sound Z80 program
  300000-31FFFF  slave         slave Z80 program (Fighting Hawk, Raimais, Champion Wrestler)
  320000-39FFFF  adpcm         Raimais' YM2610 ADPCM-A (ymsnd:adpcma) / Champion Wrestler's MSM5205 (adpcm)
  3A0000-3A07FF  mcu:mcu       Puzznic's MC68705P3
  3A0800-3A082F  configuration: [0] board [1:2] 8x8 tiles [3:5] tile mask [6:8] program ROM mask [9] rotation [10] flags
                 [16:39] input signal ids  [40:42] idle values of IN0..IN2  (tools/inputmap.py)
"""
import os
import re
import subprocess
import sys
import zipfile

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import inputmap  # noqa: E402
import paths  # noqa: E402

HERE = os.path.dirname(os.path.abspath(__file__))
DRIVER = os.path.join(paths.BASE, 'ref', 'mame', 'src', 'mame', 'taito', 'taito_l.cpp')
DEFAULT_ROMDIR = r'R:\Games\Arcade\MAME 0.289 ROMs (merged)'

LAYOUT = {            # region tag -> (image offset, image size)
    'maincpu':      (0x000000, 0x100000),
    'maincpu:gfx':  (0x100000, 0x180000),
    'audiocpu':     (0x280000, 0x080000),
    'slave':        (0x300000, 0x020000),
    'adpcm':        (0x320000, 0x080000),
    'ymsnd:adpcma': (0x320000, 0x080000),
    'mcu:mcu':      (0x3A0000, 0x000800),
}
CFG_OFF = 0x3A0800
CFG_SIZE = 0x30
IMAGE_SIZE = CFG_OFF + CFG_SIZE

# machine config name (4th field of GAME()) -> board id in CFG[0]
BOARDS = {'plotting': 0, 'puzznic': 1, 'puzznici': 2, 'palamed': 3, 'cachat': 3, 'horshoes': 4,
          'kurikint': 5, 'evilston': 6, 'fhawk': 7, 'champwr': 8, 'raimais': 9}


def strip_comments(text):
    text = re.sub(r'/\*.*?\*/', '', text, flags=re.S)
    return re.sub(r'//[^\n]*', '', text)


def parse_driver(path=DRIVER):
    """-> (roms, games): roms[name] = list of regions {tag,size,fill,loads}, games[name] = {parent, machine, rot, title}"""
    src = strip_comments(open(path, encoding='utf-8', errors='replace').read())
    roms = {}
    for m in re.finditer(r'ROM_START\(\s*(\w+)\s*\)(.*?)ROM_END', src, flags=re.S):
        name, body = m.group(1), m.group(2)
        regions, cur, last = [], None, None
        for line in body.split('\n'):
            line = line.strip()
            r = re.match(r'ROM_REGION\(\s*(0x[0-9a-fA-F]+|\d+)\s*,\s*"([^"]+)"\s*,\s*([^)]*)\)', line)
            if r:
                cur = {'tag': r.group(2), 'size': int(r.group(1), 0),
                       'fill': 0xFF if 'ERASEFF' in r.group(3) else 0x00, 'loads': []}
                regions.append(cur)
                last = None
                continue
            r = re.match(r'ROM_LOAD(16_BYTE|32_BYTE)?\(\s*"([^"]+)"\s*,\s*(0x[0-9a-fA-F]+|\d+)\s*,\s*(0x[0-9a-fA-F]+|\d+)\s*,\s*CRC\(([0-9a-fA-F]+)\)', line)
            if r and cur is not None:
                stride = {None: 1, '16_BYTE': 2, '32_BYTE': 4}[r.group(1)]
                last = {'file': r.group(2), 'offset': int(r.group(3), 0), 'size': int(r.group(4), 0),
                        'crc': int(r.group(5), 16), 'stride': stride, 'skip': 0}
                cur['loads'].append(last)
                continue
            r = re.match(r'ROM_CONTINUE\s*\(\s*(0x[0-9a-fA-F]+|\d+)\s*,\s*(0x[0-9a-fA-F]+|\d+)\s*\)', line)
            if r and cur is not None and last is not None:
                skip = last['skip'] + last['size']
                last = {'file': last['file'], 'offset': int(r.group(1), 0), 'size': int(r.group(2), 0),
                        'crc': last['crc'], 'stride': last['stride'], 'skip': skip, 'cont': True}
                cur['loads'].append(last)
        roms[name] = regions
    games = {}
    for m in re.finditer(r'^\s*GAME\(\s*([^,]+),\s*(\w+)\s*,\s*(\w+)\s*,\s*(\w+)\s*,\s*(\w+)\s*,\s*\w+\s*,\s*(\w+)\s*,\s*(ROT\d+)\s*,\s*"([^"]*)"\s*,\s*"([^"]*)"',
                         src, flags=re.M):
        year, name, parent, machine, inp, init, rot, company, title = m.groups()
        games[name] = {'year': year.strip(), 'parent': None if parent == '0' else parent, 'machine': machine,
                       'input': inp, 'init': init, 'rot': rot, 'company': company, 'title': title}
    return roms, games


def find_zips(name, games, romdir):
    out, n = [], name
    while n:
        p = os.path.join(romdir, n + '.zip')
        if os.path.exists(p):
            out.append(p)
        n = games.get(n, {}).get('parent')
    return out


def crc_index(zips):
    idx = {}
    for zp in zips:
        with zipfile.ZipFile(zp) as z:
            for i in z.infolist():
                idx.setdefault(i.CRC, (zp, i.filename))
    return idx


def build_regions(name, romdir=DEFAULT_ROMDIR, roms=None, games=None, apply_init=True):
    """-> {tag: bytearray}, exactly as MAME fills them."""
    if roms is None:
        roms, games = parse_driver()
    if name not in roms:
        raise KeyError('no ROM_START for %s' % name)
    idx = crc_index(find_zips(name, games, romdir))
    out = {}
    for reg in roms[name]:
        if reg['tag'] in ('plds', 'pals'):
            continue
        buf = bytearray([reg['fill']]) * reg['size']
        for ld in reg['loads']:
            if ld['crc'] not in idx:
                raise FileNotFoundError('%s: %s (CRC %08x) not found in the zips' % (name, ld['file'], ld['crc']))
            zp, fn = idx[ld['crc']]
            with zipfile.ZipFile(zp) as z:
                data = z.read(fn)
            if ld.get('cont'):
                data = data[ld['skip']:ld['skip'] + ld['size']]
            else:
                data = data[:ld['size']]
            if len(data) != ld['size']:
                raise ValueError('%s: %s has %d bytes, the driver wants %d' % (name, ld['file'], len(data), ld['size']))
            for i, b in enumerate(data):
                buf[ld['offset'] + i * ld['stride']] = b
        out[reg['tag']] = buf
    if apply_init and games.get(name, {}).get('init') == 'init_plottinga':        # bits 7..0 => bits 0..7
        tab = [int('{:08b}'.format(i)[::-1], 2) for i in range(256)]
        out['maincpu'] = bytearray(tab[b] for b in out['maincpu'])
    return out


def pow2_ceil(n):
    p = 1
    while p < n:
        p *= 2
    return p


def config_for(name, roms, games):
    """The 16 configuration bytes at CFG_OFF, from the definitions alone (region sizes), no ROM data needed."""
    size = {r['tag']: r['size'] for r in roms[name]}
    main, n8 = size['maincpu'], size['maincpu:gfx'] // 32
    pmask = pow2_ceil(n8) - 1
    rmask = pow2_ceil(main) - 1                                    # the program ROM wraps at its (power of two) size
    cfg = bytearray(CFG_SIZE)
    cfg[0] = BOARDS[games[name]['machine']]
    cfg[1], cfg[2] = n8 & 255, n8 >> 8
    cfg[3], cfg[4], cfg[5] = pmask & 255, (pmask >> 8) & 255, pmask >> 16
    cfg[6], cfg[7], cfg[8] = rmask & 255, (rmask >> 8) & 255, rmask >> 16
    cfg[9] = {'ROT0': 0, 'ROT90': 1, 'ROT180': 2, 'ROT270': 3}[games[name]['rot']]
    cfg[10] = 1 if games[name].get('init') == 'init_plottinga' else 0      # bit 0: the program ROM is bit-reversed
    cfg[16:16 + 27] = inputmap.config_bytes(name)                          # 24 signal ids + 3 idle values (tools/inputmap.py)
    return cfg


def build_image(name, romdir=DEFAULT_ROMDIR, roms=None, games=None):
    if roms is None:
        roms, games = parse_driver()
    regions = build_regions(name, romdir, roms, games, apply_init=False)       # the image holds the ROMs as they are;
    img = bytearray(IMAGE_SIZE)                                                # the core applies the driver's init (CFG[10])
    for tag, buf in regions.items():
        off, size = LAYOUT[tag]
        if len(buf) > size:
            raise ValueError('%s region %s is 0x%x bytes, the image has room for 0x%x' % (name, tag, len(buf), size))
        img[off:off + len(buf)] = buf
    cfg = config_for(name, roms, games)
    img[CFG_OFF:CFG_OFF + CFG_SIZE] = cfg
    return img, regions, cfg


def main(argv):
    roms, games = parse_driver()
    if not argv or argv[0] == 'list':
        for n in sorted(roms):
            g = games.get(n, {})
            print('%-10s %-9s parent %-9s %-6s %s' % (n, g.get('machine', '?'), g.get('parent') or '-', g.get('rot', '?'), g.get('title', '')))
        return 0
    cmd, name = argv[0], argv[1]
    romdir = argv[argv.index('--romdir') + 1] if '--romdir' in argv else DEFAULT_ROMDIR
    if cmd == 'build':
        img, regions, cfg = build_image(name, romdir, roms, games)
        for tag, buf in regions.items():
            print('  %-14s 0x%06x bytes' % (tag, len(buf)))
        print('  config: board %d, %d gfx tiles, program mask %06x, %s' % (cfg[0], cfg[1] | cfg[2] << 8, cfg[6] | cfg[7] << 8 | cfg[8] << 16, games[name]['rot']))
        if '--out' in argv:
            open(argv[argv.index('--out') + 1], 'wb').write(img)
        if '--regions' in argv:
            d = argv[argv.index('--regions') + 1]
            os.makedirs(d, exist_ok=True)
            for tag, buf in regions.items():
                open(os.path.join(d, '%s.%s.bin' % (name, tag.replace(':', '_'))), 'wb').write(buf)
        return 0
    if cmd == 'check':                                              # against dump.lua's maincpu/gfx dump
        pre = argv[2]
        regions = build_regions(name, romdir, roms, games)
        bad = 0
        for tag, suffix in (('maincpu', 'maincpu'), ('maincpu:gfx', 'gfx')):
            ref = open('%s.%s.bin' % (pre, suffix), 'rb').read()
            mine = bytes(regions[tag])
            same = (ref == mine)
            print('  %-12s %s (%d vs %d bytes)' % (tag, 'identical' if same else 'DIFFERENT', len(mine), len(ref)))
            bad += 0 if same else 1
        return bad
    print(__doc__)
    return 2


if __name__ == '__main__':
    sys.exit(main(sys.argv[1:]))
