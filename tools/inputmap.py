#!/usr/bin/env python3
"""Per-game input wiring, read from MAME itself: which function (joystick direction, button, coin, start ...) each bit of the
board's input ports IN0..IN2 carries, and the value every port reads with all inputs released.

  python tools/inputmap.py <set> [<set> ...]

The core is generic: these 27 bytes (24 signal ids + 3 idle values, in the ROM image's configuration block) are all it knows
about a game's controls, so a new game needs no RTL.  Signal ids (rtl/taitol_ctrl.sv, TaitoL.sv):
  0 none  1-4 P1 up/down/left/right  5-7 P1 buttons 1-3  8-11 P2 up/down/left/right  12-14 P2 buttons 1-3
  15 coin 1  16 coin 2  17 start 1  18 start 2  19 service  20 tilt
A bit with a signal reads the idle value's complement while the signal is active; a bit with no signal reads its idle bit.
"""
import json
import os
import subprocess
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import paths  # noqa: E402
MAME = os.path.join(HERE, 'mame', 'mame.exe')
LUA = os.path.join(HERE, 'lua', 'inputs.lua')
CACHE = os.path.join(HERE, 'inputmap_cache.json')
ROMDIR = r'R:\Games\Arcade\MAME 0.289 ROMs (merged)'

SIGNALS = {
    'P1 Up': 1, 'P1 Down': 2, 'P1 Left': 3, 'P1 Right': 4, 'P1 Button 1': 5, 'P1 Button 2': 6, 'P1 Button 3': 7,
    'P2 Up': 8, 'P2 Down': 9, 'P2 Left': 10, 'P2 Right': 11, 'P2 Button 1': 12, 'P2 Button 2': 13, 'P2 Button 3': 14,
    'Coin 1': 15, 'Coin 2': 16, '1 Player Start': 17, '2 Players Start': 18, 'Service 1': 19, 'Tilt': 20,
}
PORTS = ['IN0', 'IN1', 'IN2']


def from_mame(name):
    out = subprocess.run([MAME, name, '-rompath', ROMDIR, '-cfg_directory', os.path.join(paths.BASE, 'work', 'mame', 'cfg'),
                          '-video', 'none', '-sound', 'none', '-nothrottle', '-skip_gameinfo', '-autoboot_script', LUA,
                          '-seconds_to_run', '1'], capture_output=True, text=True,
                         cwd=os.path.join(paths.BASE, 'work', 'mame')).stdout
    ids = {p: [0] * 8 for p in PORTS}
    idle = {p: 0xFF for p in PORTS}
    unknown = []
    for line in out.splitlines():
        f = line.strip().split('|')
        if f[0] == 'FIELD' and f[1] in ids:
            mask = int(f[3])
            sig = SIGNALS.get(f[2])
            if sig is None:
                unknown.append((f[1], f[2]))
                continue
            for b in range(8):
                if mask >> b & 1:
                    ids[f[1]][b] = sig
        elif f[0] == 'IDLE' and f[1] in idle:
            idle[f[1]] = int(f[2])
    return {'ids': [ids[p][b] for p in PORTS for b in range(8)], 'idle': [idle[p] for p in PORTS], 'unmapped_fields': unknown}


def input_map(name):
    cache = json.load(open(CACHE)) if os.path.exists(CACHE) else {}
    if name not in cache:
        cache[name] = from_mame(name)
        json.dump(cache, open(CACHE, 'w'), indent=1, sort_keys=True)
    return cache[name]


def config_bytes(name):
    m = input_map(name)
    return bytes(m['ids'] + m['idle'])


def main(argv):
    inv = {v: k for k, v in SIGNALS.items()}
    for n in argv:
        m = input_map(n)
        print('%s: idle %s' % (n, ' '.join('%02x' % v for v in m['idle'])))
        for pi, p in enumerate(PORTS):
            print('  %s: %s' % (p, ' '.join('%-9s' % inv.get(m['ids'][pi * 8 + b], '.')[:9] for b in range(7, -1, -1))), '  (bit 7 .. 0)')
        if m['unmapped_fields']:
            print('  fields with no signal:', m['unmapped_fields'])
    return 0


if __name__ == '__main__':
    sys.exit(main(sys.argv[1:]))
