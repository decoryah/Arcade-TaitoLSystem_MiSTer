#!/usr/bin/env python3
"""Run the whole-machine RTL simulation (sim/run_system.sh) for a list of sets, several at a time, and check each against MAME.

  python tools/rtlrun.py [-j N] [--frames 565] [--build TAG] <set> [<set> ...]

For every set it
  * builds the ROM image (tools/taitol_rom.py) if work/<set>.rom is missing,
  * asks MAME for the DIP defaults (the sim must start from the same switches) and warns if the MRA's defaults would differ,
  * runs the sim with the scripted coin (frame 320) and 1P start (345, or button 1 for games without a start button), dumping
    the machine state at frames 300 331 360 420 500 560 (the same frames tools/lua/dump.lua dumps from MAME),
  * with MAME's dumps and snapshots in work/dumps/<set>.* / work/mame/snap/ (made by dump.lua with the same inputs),
    compares picture and state (tools/cmprtl.py).
The binary is $HOME/build_taitol/system_noym_<TAG> (built once by `NOYM=1 BTAG=<TAG> sim/run_system.sh`); every set uses it:
the game is data. Logs: work/sim/<set>.log.
"""
import argparse
import os
import re
import subprocess
import sys
import time

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import make_mra  # noqa: E402
import paths  # noqa: E402
import taitol_rom as T  # noqa: E402

ROOT = paths.BASE                                    # work/ and ref/ live here (tools/paths.py)
WROOT = paths.wsl(paths.BASE)
WREPO = paths.wsl(paths.REPO)
MAME = os.path.join(HERE, 'mame', 'mame.exe')
STATE_FRAMES = (300, 331, 360, 420, 500, 560)
# games with no start button: the first player starts with button 1
START_WITH_B1 = {'horshoes'}


def mame_dips(name):
    lua = os.path.join(ROOT, 'work', 'mame', 'dsw.lua')
    out = subprocess.run([MAME, name, '-rompath', T.DEFAULT_ROMDIR, '-cfg_directory', os.path.join(ROOT, 'work', 'mame', 'cfg'),
                          '-video', 'none', '-sound', 'none', '-nothrottle', '-skip_gameinfo', '-autoboot_script', lua,
                          '-seconds_to_run', '1'], capture_output=True, text=True, cwd=os.path.join(ROOT, 'work', 'mame')).stdout
    got = dict(re.findall(r'DSW (DSW[AB]) = ([0-9a-f]{2})', out))
    return int(got.get('DSWA', 'ff'), 16), int(got.get('DSWB', 'ff'), 16)


def launch(name, tag, frames, dip=None, vtag=None, states=STATE_FRAMES, extra=()):
    rom = os.path.join(ROOT, 'work', name + '.rom')
    if not os.path.exists(rom):
        subprocess.run([sys.executable, os.path.join(HERE, 'taitol_rom.py'), 'build', name, '--out', rom], check=True, capture_output=True)
    dswa, dswb = mame_dips(name)
    if dip:
        dswa, dswb = [int(v, 16) for v in dip.split(',')]
    try:
        listed = make_mra.dips(name)[0]
        if not dip and (listed['DSWA'], listed['DSWB']) != (dswa, dswb):
            print('%s: WARNING the MRA default switches (%02X,%02X) differ from MAME\'s (%02X,%02X)' % (name, listed['DSWA'], listed['DSWB'], dswa, dswb))
    except Exception as e:                                         # noqa: BLE001
        print('%s: could not list the MRA defaults (%s)' % (name, e))
    args = ['+every=1000', '+coin=320', '+b1=345' if name in START_WITH_B1 else '+start=345', '+dswa=%02X' % dswa, '+dswb=%02X' % dswb,
            '+state=' + ','.join(str(f) for f in states)] + list(extra)
    cmd = ['wsl', '-e', 'env', 'NOYM=1', 'BTAG=' + tag, 'NOBUILD=1', 'bash', WREPO + '/sim/run_system.sh',
           '%s/work/%s.rom' % (WROOT, name), str(frames), '%s/work/sim/%s' % (WROOT, name + ('_' + vtag if vtag else ''))] + args
    log = open(os.path.join(ROOT, 'work', 'sim', name + ('_' + vtag if vtag else '') + '.log'), 'w')
    env = dict(os.environ, MSYS_NO_PATHCONV='1')
    return subprocess.Popen(cmd, stdout=log, stderr=subprocess.STDOUT, env=env), log


def main(argv):
    ap = argparse.ArgumentParser()
    ap.add_argument('sets', nargs='+')
    ap.add_argument('-j', type=int, default=4)
    ap.add_argument('--frames', type=int, default=565)
    ap.add_argument('--build', default='p3', help='BTAG of the prebuilt NOYM simulator')
    ap.add_argument('--dip', help="DSWA,DSWB hex bytes instead of the MAME defaults (needs --tag; the MAME dumps are work/dumps/<set>_<tag>, tools/mamedump.py --dip ... --tag ...)")
    ap.add_argument('--tag')
    ap.add_argument('--extra', default='', help='more bench arguments, comma separated (+oflip=1 = the OSD flip option)')
    ap.add_argument('--states', default=','.join(str(f) for f in STATE_FRAMES))
    a = ap.parse_args(argv)
    games = T.parse_driver()[1]
    pending, running, results = list(a.sets), {}, {}
    while pending or running:
        while pending and len(running) < a.j:
            n = pending.pop(0)
            running[n] = launch(n, a.build, a.frames, a.dip, a.tag, [int(f) for f in a.states.split(',')],
                                 [x for x in a.extra.split(',') if x])
            print('%s: started' % n, flush=True)
        time.sleep(5)
        for n in list(running):
            p, log = running[n]
            if p.poll() is not None:
                log.close()
                del running[n]
                rot = 0
                try:
                    rot = {'ROT0': 0, 'ROT90': 90, 'ROT180': 180, 'ROT270': 270}[games[n]['rot']] if games else 0
                except Exception:                                  # noqa: BLE001
                    pass
                vn = n + ('_' + a.tag if a.tag else '')
                extra = ['--dumps', os.path.join(ROOT, 'work', 'dumps', vn), '--snap', vn, '--gfx', os.path.join(ROOT, 'work', 'dumps', n + '.gfx.bin')] if a.tag else []
                r = subprocess.run([sys.executable, os.path.join(HERE, 'cmprtl.py'), n, os.path.join(ROOT, 'work', 'sim', vn)] +
                                   a.states.split(',') + ['--rot', str(rot)] + extra, capture_output=True, text=True)
                results[n] = (p.returncode, r.returncode, r.stdout)
                print('== %s (sim exit %d, %d frame(s) differ)\n%s' % (n, p.returncode, r.returncode, r.stdout), flush=True)
    return sum(1 for v in results.values() if v[0] or v[1])


if __name__ == '__main__':
    sys.exit(main(sys.argv[1:]))
