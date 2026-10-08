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
        a = 'name=%s' % quoteattr(ld['file'])
        if ld['crc'] is not None:                                   # homebrew parts are found by name only
            a += ' crc="%08x"' % ld['crc']
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


def mra(name, roms, games, hb=None):
    """The MRA of MAME set `name`, or of homebrew `hb` (HOMEBREW below: a game for the Plotting board, ROMs not in MAME)."""
    if hb:
        base = 'plotting'
        g = dict(games[base], title=hb['title'], year=hb['year'], company=hb['company'], parent=None)
        zips = [hb['zip']]
        by_tag = {'maincpu': {'tag': 'maincpu', 'size': 0x10000, 'fill': 0, 'loads': [
                      {'file': 'ic10', 'offset': 0, 'size': hb['ic10'][0], 'crc': None, 'stride': 1, 'skip': 0}]},
                  'maincpu:gfx': {'tag': 'maincpu:gfx', 'size': 0x20000, 'fill': 0, 'loads': [
                      {'file': 'b96-07.ic9', 'offset': 0, 'size': hb['ic9'][0], 'crc': None, 'stride': 2, 'skip': 0},
                      {'file': 'b96-08.ic8', 'offset': 1, 'size': hb['ic8'][0], 'crc': None, 'stride': 2, 'skip': 0}]}}
    else:
        base = name
        g = games[name]
        zips = [name + '.zip'] + ([g['parent'] + '.zip'] if g['parent'] else [])
        by_tag = {r['tag']: r for r in roms[name]}
        by_tag['adpcm'] = by_tag.get('adpcm') or by_tag.get('ymsnd:adpcma')
    cfg = T.config_for(base, roms, games)
    default, diplines = dips(base)
    L = []
    L.append('<misterromdescription>')
    L.append('    <rotation>%s</rotation>' % ('vertical' if g['rot'] in ('ROT90', 'ROT270') else 'horizontal'))
    L.append('    <name>%s</name>' % g['title'].replace('&', '&amp;'))
    L.append('    <setname>%s</setname>' % name)
    if not hb:
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
    if hb:
        L.append('      %s' % hb['about'])
        L.append("      Needs %s in games/mame: the author's plotting.zip (%s), renamed. Parts are found by name; the released files are" % (hb['zip'], hb['url']))
        L.append('      ic10 %d bytes CRC %08x, b96-07.ic9 %d bytes CRC %08x, b96-08.ic8 %d bytes CRC %08x.' % (
            hb['ic10'][0], hb['ic10'][1], hb['ic9'][0], hb['ic9'][1], hb['ic8'][0], hb['ic8'][1]))
        L.append('      The program (ic10) is padded with 00 to the 64 KB the board has, as MAME does; the graphics ROMs are 64 KB each.')
    else:
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


# Homebrew games for the Plotting board (board 0). Each is the author's replacement `plotting.zip` (b96-07.ic9, b96-08.ic8, ic10: MAME runs it with
# `mame plotting` and a checksum warning). The authors ask that their ROMs are only distributed from their own sites, so there are MRAs and no ROMs; the
# user renames the download to `zip`. ic10 / ic9 / ic8 = (size, CRC) of the released file; the program is padded to the board's 64 KB as MAME does.
HOMEBREW = [
    dict(setname='sokobanle', zip='sokobanle.zip', title='Sokoban LE', year='2015', company='Adrian Smethurst',
         ic10=(65536, 0x5959ddb4), ic9=(65536, 0x859e1ff4), ic8=(65536, 0x439a6670),
         url='https://www.ukvac.com/forum/threads/new-game-release-sokoban-le-for-taito-l-system.36006/ - sokoban_le_plotting.zip',
         about="Sokoban LE (August 2015) by Adrian Smethurst: a port of Compiler Software's Spectrum Sokoban."),
    dict(setname='sqij', zip='sqij.zip', title='SQIJ 2018', year='2018', company='Tardis Remakes',
         ic10=(61440, 0x793c8b97), ic9=(65536, 0xc4de729b), ic8=(65536, 0x978df42d),
         url='https://tardis.dk/wordpress/?page_id=1695',
         about='SQIJ 2018 (v1.5, November 2018) by Soeren Borgquist (Sokurah), Tardis Remakes: a remake of the C64 maze game.'),
    dict(setname='speccies2', zip='speccies2.zip', title='The Speccies 2', year='2015', company='Tardis Remakes',
         ic10=(21993, 0x29e126ac), ic9=(65536, 0x11ed1528), ic8=(65536, 0xfcfeb89f),
         url='https://tardis.dk/wordpress/?page_id=1359',
         about='The Speccies 2 (v1.0, October 2015) by Soeren Borgquist (Sokurah), Tardis Remakes: a puzzle game, 50 levels.'),
]


def homebrew_path(hb):
    return os.path.join(OUTDIR, '_homebrew', hb['title'] + '.mra')


def main(argv):
    roms, games = T.parse_driver()
    names = [n for n in (argv or SUPPORTED) if n in games]
    hbs = [h for h in HOMEBREW if not argv or h['setname'] in argv]
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
    for hb in hbs:
        path = homebrew_path(hb)
        os.makedirs(os.path.dirname(path), exist_ok=True)
        open(path, 'w', newline='\n').write(mra(hb['setname'], roms, games, hb))
        print('wrote', os.path.normpath(path))
    return 0


if __name__ == '__main__':
    sys.exit(main(sys.argv[1:]))
