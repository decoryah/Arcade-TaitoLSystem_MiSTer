#!/usr/bin/env python3
"""Check every generated MRA: assemble its image from the user's merged MAME zip exactly as the MiSTer would (tools/mra_build.py)
and compare with the image tools/taitol_rom.py builds from MAME's own ROM definitions (the one the simulations ran).

  python tools/mra_verify.py [mra files ...]      (default: all of mra/, clones included)
"""
import glob
import os
import sys
import xml.etree.ElementTree as ET

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import mra_build  # noqa: E402
import paths  # noqa: E402
import taitol_rom as T  # noqa: E402


def main(argv):
    files = argv or sorted(glob.glob(os.path.join(paths.REPO, 'mra', '**', '*.mra'), recursive=True))
    roms, games = T.parse_driver()
    bad = 0
    for f in files:
        root = ET.parse(f).getroot()
        name = root.findtext('setname')
        parent = games[name]['parent'] or name
        zp = os.path.join(T.DEFAULT_ROMDIR, parent + '.zip')
        img, md5 = mra_build.build(f, zp)
        ref = T.build_image(name)
        ref = ref[0] if isinstance(ref, tuple) else ref
        ok = (bytes(img) == bytes(ref))
        print('%-10s %-40s %s (%d bytes)' % (name, os.path.basename(f), 'identical to the simulated image' if ok else 'DIFFERENT', len(img)))
        bad += 0 if ok else 1
    return bad


if __name__ == '__main__':
    sys.exit(main(sys.argv[1:]))
