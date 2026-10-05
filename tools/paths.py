#!/usr/bin/env python3
"""Where things are, for every tool in this folder.

  REPO  the repository root (the Quartus project: TaitoL.qpf, mra/, releases/, sim/, tools/ ...).
  BASE  the scratch area with `work/` (MAME's dumps and snapshots, ROM images, simulation output) and `ref/mame` (a MAME 0.289 source
        tree: taitol_rom.py reads taito_l.cpp from it). It is NOT part of the repository (both are in .gitignore). It is
          * $TAITOL_BASE if that is set,
          * else the folder above the repository when that has a `ref` or `work` folder (the owner's layout: <BASE>/mister is the
            repository),
          * else the repository itself (a plain clone: make `work/` and `ref/mame` in it).
  MAME  tools/mame/mame.exe (MAME 0.289, not in the repository).

  python tools/paths.py repo|base|wslrepo|wslbase     prints one of them (for the shell scripts)
"""
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.dirname(HERE)


def _base():
    b = os.environ.get('TAITOL_BASE')
    if b:
        return os.path.abspath(b)
    up = os.path.dirname(REPO)
    if os.path.isdir(os.path.join(up, 'ref')) or os.path.isdir(os.path.join(up, 'work')):
        return up
    return REPO


BASE = _base()


def wsl(path):
    """A Windows path as the WSL sees it (C:\\x\\y -> /mnt/c/x/y); other paths are returned unchanged."""
    p = os.path.abspath(path).replace('\\', '/')
    if len(p) > 1 and p[1] == ':':
        return '/mnt/' + p[0].lower() + p[2:]
    return p


if __name__ == '__main__':
    what = sys.argv[1] if len(sys.argv) > 1 else 'repo'
    print({'repo': REPO, 'base': BASE, 'wslrepo': wsl(REPO), 'wslbase': wsl(BASE)}[what])
