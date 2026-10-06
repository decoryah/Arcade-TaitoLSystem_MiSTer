#!/usr/bin/env python3
"""Writes the core's MRA files (mra/) from MAME's definitions: the ROM_START lists of taito_l.cpp (through
tools/taitol_rom.py, so the MRAs and the independent image builder cannot disagree) and the DIP switches from
`mame -listxml`. No ROM file is read.

  python tools/make_mra.py [set ...]        (default: every supported set)

Layout, as MiSTer's menu wants it: one MRA a title in mra/, the other versions of the title (regional versions, bootlegs) in
mra/_alternatives/_<Title>/, where <Title> is the title without its bracket ("Puzznic (World)" -> _Puzznic). Which set stands for a
title is MAME's parent, except Tube-It / Cachat (MRA_PARENT below).

The image layout is tools/taitol_rom.py's (LAYOUT); the core's loader packs the byte stream little-endian (first byte
low), so MAME's region byte order is simply the stream order. DIP switches (ioctl index 254): byte 0 is MAME's DSWA,
byte 1 DSWB, bit 0 first, a 1 being MAME's default.
"""
import os
import subprocess
import sys
import xml.etree.ElementTree as ET
from xml.sax.saxutils import quoteattr

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import paths  # noqa: E402
import taitol_rom as T  # noqa: E402

MAME = os.path.join(HERE, 'mame', 'mame.exe')
OUTDIR = os.path.join(paths.REPO, 'mra')

# sets the core runs so far (the family's board id must be implemented in rtl/taitol_board.sv)
SUPPORTED = ['plotting', 'plottinga', 'plottingb', 'plottingu', 'flipull',
             'puzznic', 'puzznicu', 'puzznicj', 'puzznici', 'puzznicb', 'puzznicba',
             'palamed', 'palamedj', 'tubeit', 'cachat', 'cubybop', 'plgirls', 'plgirls2', 'plgirls2j', 'lagirl',
             'horshoes', 'kurikint', 'kurikinta', 'kurikintj', 'kurikintu', 'kurikintw', 'evilston', 'fhawk', 'fhawkj',
             'champwr', 'champwrj', 'champwru', 'raimais', 'raimaisj', 'raimaisjo']

ORDER = ['maincpu', 'maincpu:gfx', 'audiocpu', 'slave', 'adpcm', 'mcu:mcu']     # slot order in the image


def region_parts(reg, slot_size):
    """-> list of MRA lines filling exactly slot_size bytes with region `reg` (None: an absent region)."""
    out, pos = [], 0
    fill = '%02X' % (reg['fill'] if reg else 0)

    def pad(n):
        if n > 0:
            out.append('<part repeat="0x%X">%s</part>' % (n, fill))
    if reg is None:
        pad(slot_size)
        return out
    items, groups = [], {}
    for ld in reg['loads']:
        s = ld['stride']
        if s == 1:
            items.append((ld['offset'], ld['size'], 'lin', [ld]))
        else:
            base = ld['offset'] - ld['offset'] % s
            groups.setdefault((base, s, ld['size']), {})[ld['offset'] % s] = ld
    for (base, s, size), lanes in groups.items():
        if sorted(lanes) != list(range(s)):
            raise ValueError('interleave at %x is missing lanes: %s' % (base, sorted(lanes)))
        items.append((base, size * s, 'ilv', [lanes[i] for i in range(s)]))
    items.sort(key=lambda t: t[0])

    def ref(ld):
        a = 'name=%s crc="%08x"' % (quoteattr(ld['file']), ld['crc'])
        if ld['skip'] or any(o['file'] == ld['file'] and o.get('cont') for o in reg['loads']):      # a file split by ROM_CONTINUE: only this part of it
            a += ' offset="0x%X" length="0x%X"' % (ld['skip'], ld['size'])
        return a

    for base, length, kind, lds in items:
        if base < pos:
            raise ValueError('overlapping loads at %x' % base)
        pad(base - pos)
        if kind == 'lin':
            out.append('<part %s/>' % ref(lds[0]))
        else:
            s = len(lds)
            out.append('<interleave output="%d">' % (8 * s))
            for k, ld in enumerate(lds):
                out.append('    <part %s map="%s"/>' % (ref(ld), ''.join('1' if i == s - 1 - k else '0' for i in range(s))))
            out.append('</interleave>')
        pos = base + length
    pad(min(reg['size'], slot_size) - pos)
    pad(slot_size - max(pos, min(reg['size'], slot_size)))
    return out


def dips(name):
    """DIP switches from MAME's -listxml -> (default bytes, [<dip .../> lines])"""
    xml = subprocess.run([MAME, name, '-rompath', T.DEFAULT_ROMDIR, '-listxml'], capture_output=True, text=True,
                         cwd=os.path.join(paths.BASE, 'work', 'mame')).stdout
    root = ET.fromstring(xml)
    machine = [m for m in root.iter('machine') if m.get('name') == name][0]
    default = {'DSWA': 0, 'DSWB': 0}
    lines = []
    for d in machine.iter('dipswitch'):
        tag = d.get('tag')
        if tag not in default:
            continue
        mask = int(d.get('mask'))
        shift = (mask & -mask).bit_length() - 1
        nbits = bin(mask >> shift).count('1')
        base = 0 if tag == 'DSWA' else 8
        vals = {}
        for v in d.iter('dipvalue'):
            idx = (int(v.get('value')) & mask) >> shift
            vals.setdefault(idx, v.get('name'))
            if v.get('default') == 'yes':
                default[tag] |= int(v.get('value')) & mask
        ids = [vals.get(i, 'Unused') for i in range(1 << nbits)]
        bits = ','.join(str(base + shift + i) for i in range(nbits))
        lines.append('        <dip bits="%s" name=%s ids=%s/>' % (bits, quoteattr(d.get('name')), quoteattr(','.join(ids))))
    return default, lines


def mra(name, roms, games):
    g = games[name]
    zips = [name + '.zip'] + ([g['parent'] + '.zip'] if g['parent'] else [])
    cfg = T.config_for(name, roms, games)
    by_tag = {r['tag']: r for r in roms[name]}
    by_tag['adpcm'] = by_tag.get('adpcm') or by_tag.get('ymsnd:adpcma')
    default, diplines = dips(name)
    L = []
    L.append('<misterromdescription>')
    L.append('    <rotation>%s</rotation>' % ('vertical' if g['rot'] in ('ROT90', 'ROT270') else 'horizontal'))
    L.append('    <name>%s</name>' % g['title'].replace('&', '&amp;'))
    L.append('    <setname>%s</setname>' % name)
    L.append('    <mameversion>0289</mameversion>')
    L.append('    <year>%s</year>' % g['year'])
    L.append('    <manufacturer>%s</manufacturer>' % g['company'].replace('&', '&amp;'))
    L.append('    <players>2</players>')
    L.append('    <joystick>8</joystick>')
    L.append('    <rbf>taitol</rbf>')
    L.append('    <platform>Taito L</platform>')
    L.append('')
    L.append('    <!--')
    L.append('      Flat image for the Taito L core (target/mister/taitol_mem.sv), the same for every set (tools/taitol_rom.py):')
    for tag in ORDER:
        off, size = T.LAYOUT[tag]
        L.append('        0x%06X  0x%06X  %s' % (off, size, tag))
    L.append('        0x%06X  0x%06X  configuration: [0] board [1:2] 8x8 tiles [3:5] tile mask [6:8] program ROM mask [9] rotation [10] flags [16:42] controls' % (T.CFG_OFF, T.CFG_SIZE))
    L.append('')
    L.append('      Expects the MAME 0.289 merged romset or the split sets: parts are found by name and CRC.')
    L.append('      DIP switches (ioctl index 254): byte 0 is MAME\'s DSWA, byte 1 DSWB (a 1 is MAME\'s default setting).')
    L.append('    -->')
    L.append('    <switches default="%02X,%02X" base="16">' % (default['DSWA'], default['DSWB']))
    L.extend(diplines)
    L.append('    </switches>')
    L.append('')
    L.append('    <buttons names="Button 1,Button 2,Start,Coin" default="A,B,Start,Select"/>')
    L.append('')
    L.append('    <rom index="0" zip="%s" md5="None">' % '|'.join(zips))
    for tag in ORDER:
        off, size = T.LAYOUT[tag]
        L.append('')
        L.append('        <!-- %s -->' % tag)
        for line in region_parts(by_tag.get(tag), size):
            L.append('        ' + line)
    L.append('')
    L.append('        <!-- configuration -->')
    L.append('        <part>%s</part>' % ' '.join('%02X' % b for b in cfg))
    L.append('    </rom>')
    L.append('</misterromdescription>')
    return '\n'.join(L) + '\n'


# The menu's title for a group of sets, where it is not MAME's parent: Tube-It is the title of the Cachat group, Cachat (Japan) its alternative.
MRA_PARENT = {'tubeit': None, 'cachat': 'tubeit'}


def mra_parent(n, games):
    return MRA_PARENT[n] if n in MRA_PARENT else games[n]['parent']


def base_title(title):
    """'Puzznic (World)' -> 'Puzznic': MiSTer ties an _alternatives/_<Title> folder to the MRAs that start with <Title>"""
    return title.split(' (')[0].strip().replace('/', '-')


def mra_path(n, games):
    fname = '%s.mra' % games[n]['title'].replace('/', '-')
    p = mra_parent(n, games)
    if p:
        return os.path.join(OUTDIR, '_alternatives', '_' + base_title(games[p]['title']), fname)
    return os.path.join(OUTDIR, fname)


def main(argv):
    roms, games = T.parse_driver()
    names = argv or SUPPORTED
    if not argv:                                                   # a full run: no stale files from an older layout
        for d, _, fs in os.walk(OUTDIR):
            for f in fs:
                if f.endswith('.mra'):
                    os.remove(os.path.join(d, f))
    for n in names:
        path = mra_path(n, games)
        os.makedirs(os.path.dirname(path), exist_ok=True)
        open(path, 'w', newline='\n').write(mra(n, roms, games))
        print('wrote', os.path.normpath(path))
    return 0


if __name__ == '__main__':
    sys.exit(main(sys.argv[1:]))
