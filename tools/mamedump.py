#!/usr/bin/env python3
"""Dump MAME's reference frames for a set (state files, snapshots, ROM regions) with the same scripted inputs the RTL bench uses
(tools/rtlrun.py): coin 1 at frame 320 for 4 frames, then 1P start (or P1 button 1 for games without a start button) at 345.

  python tools/mamedump.py [--frames 300,331,...] [--bitmap] [--dip FB,FF --tag svc] <set> [<set> ...]

The port holding each button is taken from the set's own wiring (tools/inputmap.py), so it works for every board.
Writes work/dumps/<set>.fNNNNN.* and work/mame/snap/<set>.fNNNNN.png.
--dip DSWA,DSWB (hex) runs MAME with those DIP switch bytes from the start (set through the DIP fields' user values) and --tag writes the
dumps as <set>_<tag> (no ROM regions), for comparing a non-default switch setting with the RTL (tools/rtlrun.py --dip ... --tag ...).
"""
import argparse
import io
import os
import subprocess
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import inputmap  # noqa: E402
import paths  # noqa: E402
import taitol_rom as T  # noqa: E402

ROOT = paths.BASE                                    # work/ and ref/ live here (tools/paths.py)
MAME = os.path.join(HERE, 'mame', 'mame.exe')
START_WITH_B1 = {'horshoes'}
NAMES = {15: 'Coin 1', 17: '1 Player Start', 5: 'P1 Button 1'}


def port_of(name, sig):
    ids = inputmap.input_map(name)['ids']
    for i, v in enumerate(ids):
        if v == sig:
            return ['IN0', 'IN1', 'IN2'][i // 8]
    raise SystemExit('%s: no input with signal %d' % (name, sig))


def main(argv):
    ap = argparse.ArgumentParser()
    ap.add_argument('sets', nargs='+')
    ap.add_argument('--frames', default='300,331,360,420,500,560')
    ap.add_argument('--bitmap', action='store_true')
    ap.add_argument('--seconds', type=int, default=10)
    ap.add_argument('--dip', help='DIP switch bytes DSWA,DSWB in hex, applied at boot')
    ap.add_argument('--tag', help='write the dumps as <set>_<tag> (no ROM regions)')
    ap.add_argument('--ymlog', help="log the sound CPU's writes to its sound chip (frame, address bits, data: the RTL bench's +ymlog format)")
    ap.add_argument('--ymrange', default='e000-e003', help='the sound chip on the sound CPU bus (default Raimais: e000-e003; Fighting Hawk f000-f001)')
    ap.add_argument('--ymcpu', default=':audiocpu', help='CPU the sound chip is on (Plotting and the other one-CPU boards: :maincpu)')
    ap.add_argument('--ymmask', default='3', help='address bits kept in the log (YM2203: 1)')
    ap.add_argument('--wav', help="write MAME's sound output to this WAV (-wavwrite)")
    ap.add_argument('--rompath', help="MAME ROM folder instead of the default (a homebrew's replacement plotting.zip)")
    ap.add_argument('--outname', help='write the dumps as <outname> (with the ROM regions) instead of <set>')
    a = ap.parse_args(argv)
    for name in a.sets:
        start_sig = 5 if name in START_WITH_B1 else 17
        script = ';'.join([
            '320:%s:%s:1' % (port_of(name, 15), NAMES[15]), '324:%s:%s:0' % (port_of(name, 15), NAMES[15]),
            '345:%s:%s:1' % (port_of(name, start_sig), NAMES[start_sig]), '349:%s:%s:0' % (port_of(name, start_sig), NAMES[start_sig])])
        outname = a.outname or name + ('_' + a.tag if a.tag else '')
        env = dict(os.environ, TL_OUT=os.path.join('..', 'dumps', outname), TL_FRAMES=a.frames, TL_REGIONS='0' if a.tag and not a.outname else '1', TL_INPUT=script)
        boot = os.path.join(HERE, 'lua', 'dump.lua')
        if a.dip or a.ymlog:
            lines = []
            if a.dip:
                vals = [int(v, 16) for v in a.dip.split(',')]
                lines.append('local ports = manager.machine.ioport.ports')
                for port, v in zip(('DSWA', 'DSWB'), vals):
                    lines.append('for _, f in pairs(ports[":%s"].fields) do f.user_value = %d & f.mask end' % (port, v))
            if a.ymlog:
                env['TL_YMLOG'] = os.path.abspath(a.ymlog)
                env['TL_YMRANGE'] = a.ymrange
                env['TL_YMCPU'] = a.ymcpu
                env['TL_YMMASK'] = a.ymmask
                lines.append('dofile("%s")' % os.path.join(HERE, 'lua', 'ymtrace.lua').replace(os.sep, '/'))
            lines.append('dofile("%s")' % boot.replace(os.sep, '/'))
            boot = os.path.join(ROOT, 'work', 'mame', 'dip_%s.lua' % outname)
            with io.open(boot, 'w', newline='') as f:
                f.write(chr(10).join(lines) + chr(10))
        if a.bitmap:
            env['TL_BITMAP'] = '1'
        cwd = os.path.join(ROOT, 'work', 'mame')
        cmd = [MAME, name, '-rompath', a.rompath or T.DEFAULT_ROMDIR, '-cfg_directory', 'cfg', '-nvram_directory', 'nvram',
               '-snapshot_directory', 'snap', '-video', 'none', '-sound', 'none', '-nothrottle', '-skip_gameinfo',
               '-autoboot_script', boot, '-seconds_to_run', str(a.seconds)]
        if a.wav:
            cmd += ['-wavwrite', os.path.abspath(a.wav)]
        out = subprocess.run(cmd, capture_output=True, text=True, cwd=cwd, env=env).stdout
        print('%s: %d frames dumped (inputs %s)' % (outname, out.count('dumped'), script))
    return 0


if __name__ == '__main__':
    sys.exit(main(sys.argv[1:]))
