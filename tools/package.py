#!/usr/bin/env python3
"""Build the release zip in MiSTer's SD card structure from the repository:

  _Arcade/<title>.mra                         one MRA a title            (mra/*.mra)
  _Arcade/_alternatives/_<Title>/<set>.mra    its other versions         (mra/_alternatives/...)
  _Arcade/cores/taitol_<YYYYMMDD>.rbf         the core                   (releases/taitol_<YYYYMMDD>.rbf)

  python tools/package.py [YYYYMMDD]        (default: the newest RBF in releases/)

Writes dist/TaitoL_MiSTer_<YYYYMMDD>.zip (dist/ is not in the repository: attach the zip to the GitHub release). Unzip it over the root of the
SD card. No ROMs are in it: the MAME 0.289 romsets go to /media/fat/games/mame/.
"""
import glob
import os
import re
import sys
import zipfile

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.dirname(HERE)
DIST = os.path.join(REPO, 'dist')


def main(argv):
    rbfs = sorted(glob.glob(os.path.join(REPO, 'releases', 'taitol_*.rbf')))
    rbfs = [r for r in rbfs if re.search(r'taitol_\d{8}\.rbf$', r)]
    if argv:
        rbfs = [r for r in rbfs if r.endswith('taitol_%s.rbf' % argv[0])]
    if not rbfs:
        print('no releases/taitol_YYYYMMDD.rbf')
        return 1
    rbf = rbfs[-1]
    date = re.search(r'taitol_(\d{8})\.rbf$', rbf).group(1)
    mras = []
    for d, _, fs in os.walk(os.path.join(REPO, 'mra')):
        for f in fs:
            if f.endswith('.mra'):
                full = os.path.join(d, f)
                mras.append((full, '_Arcade/' + os.path.relpath(full, os.path.join(REPO, 'mra')).replace(os.sep, '/')))
    mras.sort(key=lambda t: t[1].lower())
    os.makedirs(DIST, exist_ok=True)
    out = os.path.join(DIST, 'TaitoL_MiSTer_%s.zip' % date)
    with zipfile.ZipFile(out, 'w', zipfile.ZIP_DEFLATED) as z:
        for full, arc in mras:
            z.write(full, arc)
        z.write(rbf, '_Arcade/cores/' + os.path.basename(rbf))
    print('%s: %d MRAs + %s' % (out, len(mras), os.path.basename(rbf)))
    with zipfile.ZipFile(out) as z:
        for n in z.namelist():
            print('  ' + n)
    return 0


if __name__ == '__main__':
    sys.exit(main(sys.argv[1:]))
