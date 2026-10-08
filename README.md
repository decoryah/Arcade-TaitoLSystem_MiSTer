# Taito L System for MiSTer

The **Taito L System** (1988-1993) for the MiSTer FPGA platform: the TC0090LVC custom chip (a Z80 and the whole video
section: two scrolling tile layers, a text layer, 125 sprites, a 256-colour palette and a bitmap mode) with, depending on the
game, one to three Z80s, a YM2203 (or YM2610) and the board's I/O chips. Thirty-five MAME sets of thirteen titles run: Plotting,
Puzznic, Palamedes, Tube-It (with Cachat), Cuby Bop, Play Girls, Play Girls 2, American Horseshoes, Kuri Kinton, Evil Stone, Fighting Hawk,
Champion Wrestler and Raimais, with their other versions (regional versions and bootlegs: Flipull is Plotting's Japanese version, Cachat (Japan) the
version of Tube-It, LA Girl a Play Girls bootleg, the Puzznic bootlegs).

It is written for MiSTer from MAME's driver and device sources (`taito_l.cpp`, `tc009xlvc`, `taitosnd`, `taitoio`, the
MC68705 and MB8421 models), which are also the oracle: every family was run in a Verilator simulation of the whole
machine and compared with MAME 0.289 frame by frame (see "Status"). The memory system (SDRAM controller, ROM loader, arbiter,
caches) is that of the owner's MCatAdv core; the sound chips, the MC6805 and the CRT Adjust module are other people's, with
their licences (see "Credits").

No ROMs or other copyrighted data are in this repository; you supply your own MAME romsets.

## Status

**On a real MiSTer** (a CRT on the analog output and a RetroTINK 4K on Direct Video): all 35 sets and the three homebrew games boot and play. The DIP switches work, Flip Screen and
Service Mode included; the sound is good in Champion Wrestler (ADPCM voices), Kuri Kinton, Evil Stone, Fighting Hawk and Raimais; CRT Adjust works.

**In simulation** (Verilator, the real programs through the SDRAM controller and a behavioural chip), against MAME 0.289's dumps and
snapshots: Plotting, Puzznic (with its MC68705), the Palamedes family, Cachat's bitmap mode, Play Girls, American Horseshoes with its
trackball, Kuri Kinton and Evil Stone (two Z80s), Fighting Hawk, Champion Wrestler and Raimais (three Z80s) match frame by frame or
differ in explained one-frame transients and sub-frame interrupt phase; the per-set results are in `docs/status.md`. The picture is
pixel-identical to MAME wherever the machine states agree. `docs/status.md` lists the open points.

## Install

The zip of a GitHub release unpacks over the root of the SD card. By hand:

1. Put `releases/taitol_YYYYMMDD.rbf` in `/media/fat/_Arcade/cores/` and the contents of `mra/` (the parent `.mra` files and the
   `_alternatives` and `_homebrew` folders) in `/media/fat/_Arcade/`. Keep the RBF's `taitol_` name and date: MiSTer finds the core by the MRA's
   `<rbf>` name plus the date. **Delete older `taitol_*.rbf` files from the cores folder** (the test builds of this core were named
   `taitol_2610xx.rbf`; MiSTer may pick one of those instead of the new file).

       /media/fat/_Arcade/<13 MRAs, one a title>.mra
       /media/fat/_Arcade/_alternatives/_<Title>/<other version>.mra
       /media/fat/_Arcade/_homebrew/<3 homebrew MRAs>.mra          (see "Homebrew games": their ROMs are not included)
       /media/fat/_Arcade/cores/taitol_YYYYMMDD.rbf
2. Put your MAME 0.289 romsets in `/media/fat/games/mame/` (the merged set, or the split sets next to their parents, see the table).
3. Start a game from the Arcade menu. The ROM takes a few seconds to load.

The 35 MRAs (`tools/make_mra.py` writes them from MAME's ROM lists and `-listxml` DIP switches; `tools/mra_verify.py` checks that
each builds the same image as the one the simulations ran): one MRA a title is in `mra/`, the other versions of the title in
`mra/_alternatives/_<Title>/` (the title without its bracket: `_Puzznic` for `Puzznic (World).mra`), where MiSTer's menu keeps the alternative versions
of a title. Tube-It is the title of the Cachat group (MAME's parent, Cachat (Japan), is its alternative).

| MRA | Set | ROM zips (MAME 0.289) | Board |
|---|---|---|---|
| Plotting (World set 1) | plotting | plotting | 1 CPU, YM2203 |
| &nbsp;&nbsp;Plotting (US), (World set 2, protected), (World set 3, earliest version), Flipull (Japan) | plottingu, plottinga, plottingb, flipull | each + plotting | |
| Puzznic (World) | puzznic | puzznic | 1 CPU + MC68705P3 (jt6805) |
| &nbsp;&nbsp;Puzznic (US), (Japan) | puzznicu, puzznicj | each + puzznic | |
| &nbsp;&nbsp;Puzznic (Italian bootleg), (bootleg, set 1), (bootleg, set 2) | puzznici, puzznicb, puzznicba | each + puzznic | no MCU |
| Palamedes (US) | palamed | palamed | 1 CPU, i8255 |
| &nbsp;&nbsp;Palamedes (Japan) | palamedj | palamedj + palamed | |
| Tube-It | tubeit | tubeit + cachat | 1 CPU, i8255, bitmap mode |
| &nbsp;&nbsp;Cachat (Japan) | cachat | cachat | |
| Cuby Bop (Japan, location test) | cubybop | cubybop | 1 CPU, i8255 |
| Play Girls (vertical) | plgirls | plgirls | 1 CPU, i8255 |
| &nbsp;&nbsp;LA Girl | lagirl | lagirl + plgirls | |
| Play Girls 2 (Europe) (vertical) | plgirls2 | plgirls2 | 1 CPU, i8255 |
| &nbsp;&nbsp;Play Girls 2 (Japan) | plgirls2j | plgirls2j + plgirls2 | |
| American Horseshoes (US) (vertical) | horshoes | horshoes | 1 CPU, uPD4701A trackball |
| Kuri Kinton (World) | kurikint | kurikint | 2 Z80s, YM2203 |
| &nbsp;&nbsp;Kuri Kinton (World, prototype), (Japan), (US), (US, World Games license) | kurikinta, kurikintj, kurikintu, kurikintw | each + kurikint | |
| Evil Stone (vertical) | evilston | evilston | 2 Z80s, YM2203 |
| Fighting Hawk (World) (vertical) | fhawk | fhawk | 3 Z80s, YM2203, PC060HA |
| &nbsp;&nbsp;Fighting Hawk (Japan) | fhawkj | fhawkj + fhawk | |
| Champion Wrestler (World) | champwr | champwr | 3 Z80s, YM2203, PC060HA, MSM5205 |
| &nbsp;&nbsp;Champion Wrestler (Japan), (US) | champwrj, champwru | each + champwr | |
| Raimais (World, rev 1) | raimais | raimais | 3 Z80s, YM2610, TC0140SYT |
| &nbsp;&nbsp;Raimais (Japan, rev 1), (Japan) | raimaisj, raimaisjo | each + raimais | |

### Homebrew games

Three homebrew games for the Plotting board run too. They have MRAs in `mra/_homebrew/` (`_Arcade/_homebrew/` on the card) and are not MAME sets:

| MRA | Author | Rename the author's `plotting.zip` to | Download |
|---|---|---|---|
| Sokoban LE | Adrian Smethurst (2015) | `sokobanle.zip` | `sokoban_le_plotting.zip` in the [UKVAC thread](https://www.ukvac.com/forum/threads/new-game-release-sokoban-le-for-taito-l-system.36006/) |
| SQIJ 2018 | Sokurah, Tardis Remakes (v1.5) | `sqij.zip` | [tardis.dk](https://tardis.dk/wordpress/?page_id=1695) |
| The Speccies 2 | Sokurah, Tardis Remakes (v1.0) | `speccies2.zip` | [tardis.dk](https://tardis.dk/wordpress/?page_id=1359) |

The authors ask that their games are distributed only from their own pages, so the ROMs are not in this repository or in its releases. Download the game's zip (it is
called `plotting.zip` because it replaces Plotting in MAME), rename it as in the table and put it in `/media/fat/games/mame/`. The MRAs find the ROMs by name and were
made for these versions of the files. The DIP switches in the menu are the Plotting board's; a game may use only some of them. `tools/make_mra.py` writes these MRAs
(`HOMEBREW` table) and `tools/mra_verify.py` checks that each builds the program and graphics regions MAME loads from the same files.

## OSD options

| Option | Values | |
|---|---|---|
| Aspect ratio | Original, Full Screen, [ARC1], [ARC2] | Original is 4:3 (3:4 for the vertical games when rotated) |
| Scandoubler Fx | None, HQ2x, CRT 25/50/75 % | |
| Vertical games | Rotated, As is | the vertical sets are turned by the scaler (`screen_rotate`, ROT270 counter-clockwise as in MAME); hidden with Direct Video, which never rotates |
| BG scroll update | Live, At vblank | a leftover test; keep Live |
| Trackball invert | None, Horizontal, Vertical, Both | American Horseshoes (mouse or joystick) |
| DIP switches | per game | the MRA's switches (coinage, difficulty, Flip Screen, Service Mode, ...); the game reads them at start-up: change them and press Reset |
| CRT Adjust | Off, On | page of rmonic79's module: H-Size -12..+10 %, H-Position -48..+42 pixels (steps of 6), V-Shift -32..+31 lines; Off is a true bypass |
| SDRAM read capture | Normal, Late | for a module that answers slowly; try it if the picture is garbage |
| Reset | | restarts the machine |

Controls: joystick, Button 1, Button 2, Start, Coin (the games' own button use differs; the wiring of each set comes from MAME's driver). Keyboard:
1/2 start, 5/6 coin, 9 service. American Horseshoes plays with the mouse (a trackball) or the joystick as a slow ball; mouse buttons are buttons 1 and 2.
The Service Mode DIP switch (OSD, then Reset) opens a game's test mode (Cuby Bop, a location test, has none: its screen stays black in MAME too).

## Video and orientation

The raster is 424 x 262 at the board's 6.66528 MHz pixel clock (15.7 kHz, 60.0 Hz; the visible 320 x 224 starts at line 16). The
four layers are drawn a line at a time into line buffers and mixed per pixel.

**Direct Video** (HDMI carrying the 15 kHz stream, e.g. for a RetroTINK 4K) and the analog output are one and the same stream, in
the game's native orientation. The vertical sets (Play Girls, Play Girls 2, LA Girl, American Horseshoes, Evil Stone, Fighting Hawk)
come out as MAME's ROT270 says: the picture's bottom on the left side of the screen and its top on the right, right for a monitor turned
90 degrees counter-clockwise, as in the cabinets. A display that turns the stream the other way shows them upside down: switch the game's
**Flip Screen DIP switch** on (an exact 180 degree turn; MiSTer keeps the DIP settings you save per game). Without Direct Video the scaler
turns the vertical games itself.

**CRT Adjust** (an OSD page) moves the sync signals for a 15 kHz CRT. Direct Video carries those syncs to the HDMI port too, so the same shift moves a
RetroTINK's picture; keep it Off there.

## Sound

The YM2203 is jt03 and its SSG jt49 (Jose Tejada); Raimais' YM2610 is jt10 (the same author), on a 48 MHz clock of its own (the PLL's third output) with its
ADPCM-A and ADPCM-B samples read from the SDRAM; the MSM5205 of Champion Wrestler is jt5205. Output levels follow MAME's mix: the FM with one gain, the SSG
and the ADPCM with their own (matched against MAME's recorded output). The second and third Z80s have their own ROMs and the boards' communication chips
(MB8421 dual-port RAM, PC060HA, TC0040IOC, TC0510NIO, TC0220IOC) are modelled after MAME.

## Build

Quartus Prime Lite 17.0.2 (MiSTer's toolchain):

    quartus_sh --flow compile TaitoL

The released build (`releases/taitol_20261006.rbf`): 43 % of the ALMs (18,069 of 41,910), 477 of 553 RAM blocks (86 %), 43 of 112 DSPs; every setup slack is positive
(the 96 MHz machine +0.90 ns, the YM2610's 48 MHz clock +1.74 ns, the HDMI scaler +0.55 ns, the raster clock +22.6 ns) and so is every hold slack (tightest 0.242 ns); `releases/*.summary` are the fitter's and the
timing analyser's reports. Quartus's one critical warning is about the jt5205 step table's initialisation file (64 addresses in the design, 49 in the file: the
MSM5205's ADPCM step table has 49 entries, the other addresses are never used).
`tools/release.py` copies the RBF and the fitter's and timing analyser's summaries into `releases/`, `tools/package.py` makes the zip of a release in the SD
card structure (`dist/`, not in the repository). `tools/make_mra.py` writes the MRAs from MAME's definitions.

## Simulation and tools

Needs Verilator 5 (the OSS CAD Suite, in WSL) and Python 3, and for the comparison MAME 0.289 (the executable in `tools/mame/` and its source tree in `ref/mame`, neither is in
the repository; `tools/paths.py` says where the tools look for them and for `work/`):

    sim/run_system.sh <game.rom> <frames> <out-prefix> [+coin=F +start=F +dswa=XX +dswb=XX +state=F1,F2 ...]   # the whole machine (NOYM=1: without the sound chip, faster)
    tools/rtlrun.py <set> ...        # whole-machine runs with MAME's default DIP switches, compared with MAME's dumps (tools/cmprtl.py)
    tools/mamedump.py <set> ...      # MAME's reference dumps and snapshots with the same scripted inputs
    tools/dipcheck.py <set> ...      # Service Mode / Flip Screen / Cabinet on, RTL against MAME
    tools/ymcmp.py mame.log rtl.log  # the sound CPU's writes to the sound chip, MAME against the RTL (tools/mamedump.py --ymlog --wav, the bench's +ymlog)
    tools/audiocmp.py mame.wav rtl.wav  # levels and band energies of two recordings
    sim/run_crt.sh                   # CRT Adjust: the raster through the module, shifts measured
    sim/run_mcu.sh                   # the Puzznic MCU alone

`docs/status.md` has every result and the command behind it; `docs/hardware.md` is the hardware map taken from MAME's source.

## Repository layout

| | |
|---|---|
| `TaitoL.sv`, `TaitoL.qsf/.qpf/.sdc`, `files.qip` | the MiSTer top level (OSD, inputs, DIP switches, video output) and the Quartus project |
| `rtl/` | the machine: TC0090LVC (CPU half, VRAM, four line renderers, raster, mixer), the board families, sub CPUs, MC68705 interface, sound chip glue, CRT Adjust glue |
| `target/mister/` | the SDRAM controller and the ROM loader / memory arbiter |
| `modules/` | other people's cores, with their licences: tv80, jt12 (jt03, jt10), jt49, jt5205, jt680x (jt6805), crt_adjust |
| `sys/` | the MiSTer framework |
| `mra/` | the MRAs: one a title in the folder, the other versions in `_alternatives/_<Title>/` |
| `releases/` | the RBF of the release with the fitter's and timing analyser's summaries |
| `tools/` | MRA writer / verifier, ROM-image builder, reference renderer, MAME dump and comparison scripts (Python, Lua) |
| `sim/` | Verilator benches |
| `docs/` | `status.md` (results, hardware tests, open points), `hardware.md` (the hardware map) |

## License

Copyright (C) 2026 decoryah. GPL-3.0, see `LICENSE`. The cores in `modules/` keep their own licences (GPL-3.0 for the JT cores and rmonic79's CRT Adjust, MIT-style for tv80; in their folders);
the files of the MiSTer framework in `sys/` keep their own headers (GPL-2.0-or-later for most, GPL-3.0 for some). MAME's source, which this work follows, is BSD-3-Clause
(`tc009xlvc` is LGPL-2.1+); no MAME code is copied into the RTL.

## Credits

* **MAME** (the taito_l driver by Olivier Galibert and contributors, BSD-3-Clause; `tc009xlvc` by Angelo Salese, LGPL-2.1+; `taitosnd` by Philip Bennett; `taito68705`
  by David Haywood and Vas Crabb; `m68705` by Vas Crabb; `upd4701` by smf and AJR; `i8255` by Curt Coder; `mb8421` by hap and AJR; `msm5205` by Aaron Giles): the
  hardware knowledge, the oracle for every comparison, and the reference renderer's logic.
* **Jose Tejada (jotego)**: JT12 / jt03 / jt10 (YM2203, YM2610), JT49 (SSG), JT5205 (MSM5205), jt680x / jt6805 (MC6805), all GPL-3.0.
* **Guy Hutchison**: tv80 (the Z80), MIT.
* **Umberto Parisi (rmonic79)**: MiSTer-CRT-Adjust (`modules/crt_adjust`, GPL-3.0-or-later).
* **The MiSTer framework** (Sorgelig and contributors); the SDRAM controller and the PLL phase are those of the Gaiapolis MiSTer port, and the loader, arbiter and
  cache structure that of the MCatAdv core by the same owner.
* **Guru** for the measured Puzznic PCB timings quoted in MAME's source, on which the raster totals rest.
