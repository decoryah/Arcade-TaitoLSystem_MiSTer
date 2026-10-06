# Status of the Taito L core

Last updated 2026-10-05. The core runs on a real MiSTer (see "Hardware tests and releases" below for what the owner tested and what has not been seen on
hardware yet). Everything in the other sections is simulation (Verilator) and Quartus results; where a number is given, the command that
produced it is given too (the commands are in `tools/` and `sim/`; they need MAME 0.289 and its sources, which are not in this repository,
see `tools/paths.py`).

## Verified against MAME 0.289 (simulation)

| Check | How | Result |
|---|---|---|
| Reference renderer vs MAME | `tools/taitol_ref.py` on 60 dumped Plotting frames (attract, gameplay, sprite RAM changing between frames) | 0 pixels differ in all |
| Video RTL vs MAME, frozen states | `tools/vtest.sh plotting <frames>` (MAME state loaded through the chip's CPU port, behavioural gfx ROM) | 15 states, 0 pixels differ in all (re-run after the last RTL cleanup) |
| Flip screen | MAME run with the chip's flip bit forced (Plotting keeps a RAM shadow of video register 4 at 8211 which it copies to the chip every frame: `TL_FORCEFLIP=250` in `tools/lua/dump.lua`), frames 300, 331, 360, 420, 500 (attract, coin, gameplay with sprites) | reference renderer **and** RTL video path pixel-identical to MAME's flipped frames (`tools/vtest.sh flip ...`: 0 of 71,680 differ in all five) |
| ROM images | `tools/taitol_rom.py check <set> <dump>` | program and graphics regions byte-identical to MAME's own regions (plotting, plottinga incl. the bit-reversal) |
| MRAs | `tools/mra_build.py` on each generated MRA vs `taitol_rom.py build` | identical images: Plotting set 1, set 2 (protected), set 3, US, Flipull |
| **Whole machine, attract** | `sim/run_system.sh` (image through the SDRAM controller and a behavioural chip; Z80, banking, interrupts, VRAM window, palette, YM2203 port reads) booting the real program | the *displayed* frame 300 (TAITO logo, through raster / line buffers / mixer) is **pixel-identical** to MAME's frame 300 for **all five sets** (plotting, plottinga, plottingb, plottingu, flipull) |
| **Whole machine, coin and play** | same, with a scripted coin at frame 320 and 1P start at 345 (`+coin=320 +start=345`), MAME given the same inputs | RTL machine state rendered by the reference renderer was pixel-identical to MAME's snapshot at frames 331, 360, 361, 420, 421, 500, 501, 560, 561 (first session, Plotting only). Re-run on 2026-10-06 with the raster that is in the core now (both the 261007 and the 20261006 simulators): identical at 300, but a one-frame CREDIT-text transient at 331 (375 px, 48 VRAM bytes: the update lands one frame apart, a scheduling difference gone a frame later) |
| Boot timeline | RTL trace vs MAME state dumps | ROM bank 4 selected at frame 6 in both |
| YM2203 board path | `sim/run_board.sh`: the DIP/input mux reads via A000-A003 and a programmed SSG tone | all four mux reads correct; tone produced |
| Audio vs MAME | `tools/audiocmp.py` on 5 s of MAME's `-wavwrite` vs the RTL's (same inputs, coin sound + game music) | timing and spectrum match; level was a constant -10.5 dB (the same in every band, SSG and FM): fixed with a x3.33 gain in `taitol_core`; after it RMS ratio 0.99-1.01 and every band within about +-2 dB (checked offline on the recorded WAV; the in-core gain is the same arithmetic) |

## Second batch (2026-10-05): Puzznic, Palamedes family, Play Girls, American Horseshoes

Method as above: `tools/rtlrun.py <sets>` runs the whole-machine sim (`NOYM=1`, MAME's default DIP switches, coin at frame 320, 1P start
at 345 or button 1 for Horseshoes) and `tools/cmprtl.py` compares the RTL's machine state and the picture rendered from it with MAME's dumps
and snapshots at frames 300 331 360 420 500 560 (rotated sets compared in MAME's orientation). "Identical" means pixels and state
files. A transient at 331 / 360 is the update of the CREDIT text or a sprite buffer landing one frame apart; it is gone at the next
frame compared.

| Set(s) | Board | Result |
|---|---|---|
| puzznicu | 1 (MC68705 MCU) | identical at all six frames |
| puzznic, puzznicj | 1 | identical (puzznic with `+dswa=FE`, MAME's default) |
| puzznici, puzznicb, puzznicba (bootlegs, no MCU) | 2 | identical; one-frame CREDIT transient at 331 (puzznicj, b, ba: 8 VRAM bytes) |
| horshoes | 4 (+ uPD4701A, graphics bank) | identical at all six frames; attract frames 600-950 identical picture *as drawn by the RTL* (the game writes bank 2 at frame 633 and bank 1 at 877: the bank register works); a trackball step of -255 on the chip's X counter at frame 800 moves the "select mode" cursor exactly as MAME's injected analog value does (0 of 71,680 pixels differ at 820 / 830 / 840) |
| plgirls, lagirl | 3, ROT270, IM 2 gate | identical (28 VRAM bytes at 360 for one frame); **boots only with the interrupt-mode kludge** |
| plgirls2, plgirls2j | 3, ROT270 | identical except a one-frame transient at 300 |
| cubybop | 3 | identical (168 VRAM bytes at 360 for one frame) |
| palamed, palamedj, tubeit | 3 | attract / title **match at frame 300**; after the coin they are not frame-exact (see below). Tube-It's rank-select screen is the same picture with the mascot's animation one step apart |
| cachat | 3 + bitmap mode | frame 300 (the bitmap-mode intro) **identical, picture drawn by the RTL's own bitmap path** and state including the 128 KB bitmap RAM; 331 is the palette fade one frame apart (6,565 px; the state-rendered picture differs by the same count, so the display path agrees with the reference renderer); 360-560 differ only in palette / sprite animation phase (Palamedes-class timing) |
| kurikint (2 Z80s, YM2203 on the second) | 5 | identical at 300, 331, 360; 420 differs by 2 px; 500 / 560 show the same demo scene with the scroll a few pixels apart (the two CPUs and MAME's coarse scheduling quantum drift) |
| evilston (2 Z80s) | 6 | identical at 300, 331, 360 (VRAM 418 B), 420, 560; 32 px at 500 |
| fhawk (3 Z80s, ROT270, sound chip stubbed) | 7 | identical at 300, 360, 500, 560; one-frame transients at 331 (230 px) and 420 (1,024 px) |
| champwr (3 Z80s, no ADPCM) | 8 | **identical at all six frames** |

**DIP switches (checked after the first hardware test, 2026-10-05).** The MRAs' switch definitions come from MAME's `-listxml` and their default bytes were
compared with MAME's own read-out; non-default settings had not been tried until the owner reported no service menu in Cuby Bop. `tools/dipcheck.py` now
runs MAME and the RTL with the same non-default bytes from the start (set in MAME through the DIP fields' user values) for **Service Mode on** and
**Flip Screen on** in one or more sets of every board (plotting, puzznic, palamed, cachat, cubybop, plgirls2, horshoes, kurikint, evilston, fhawk, champwr)
and compares state and picture at frame 300: **all identical** (Service Mode shows the same colour-grid test screen in MAME and the RTL; Flip Screen flips
identically, Cachat's bitmap screen included), apart from a persistent one-frame transient in Play Girls 2 (the same 9,579 px with or without the switch) and
a few state bytes. **Cuby Bop** with Service Mode on is a black screen in MAME too (the game, a location test, has no working test screen), and the RTL shows the same.
Not tried: coinage, difficulty and the other switches one by one; they ride on the same bytes.

**Palamedes and Tube-It are not frame-exact, and why (traced, not guessed).** A Z80 instruction trace of MAME and of the RTL around the
coin (frames 316-336) is identical for the first two frames (18,802 instructions, interrupt entries included) and then differs by *one
iteration of the 12-cycle idle loop at 0120 before an interrupt is taken*. The frame counter at 81CB is the same in both. So the code
paths are identical and the difference is the sub-frame phase of the interrupts against the Z80 clock: MAME's screen is 256 lines at
60 Hz, so its line-240 interrupt falls 2,385 CPU cycles later in the frame than at line 240 of the RTL's 424 x 262 raster (which is
the measured PCB total). Palamedes' dice come from a counter the idle loop advances, so the random sequence differs
(different dice at 420 and on) while every screen is the same kind of screen. Plotting, Puzznic, Play Girls and Cuby Bop have no such sensitivity and match.
Not chased further: matching MAME's dice would mean copying MAME's wrong line timing.

**The Puzznic MCU needed its microcode.** `jt6805` reads its microcode ROM (`6805.uc`, generated by jtframe) with an
`initial $readmemb`; without the file it warns and executes nothing, and the original Puzznic hung at its MCU handshake (the first
simulations). The file is now in `modules/jt680x/` with the path edited to `modules/jt680x/6805.uc`; Quartus finds it from the project directory
(report line "Auto-Found Unspecified File ... yes"; the ROM is built from logic, ALMs 27 % -> 30 %) and the sim scripts copy it. A standalone bench
(`sim/run_mcu.sh`, MAME's own MCU trace as the reference) shows the RTL MCU answering 0x20 to the first host write and 0x50 to 0x43, as MAME's
program does.

**Screen rotation** (ROT90 / ROT270 / ROT180) without Direct Video is `screen_rotate` from the MiSTer framework fed by `arcade_video`'s output, ROT270
counter-clockwise, with a "Vertical games" OSD option. The geometry of the rotation was checked in Python against MAME's portrait snapshots
(`tools/pngio.rotate`; 0 pixels differ); the DDR3 frame buffer path itself cannot be simulated here. With Direct Video the stream is not rotated: see "Orientation and Direct Video".

**Sound levels, and a correction.** The YM2203's FM section matched MAME with one gain (Plotting is FM only: its SSG registers stay at zero). The
first game that uses the SSG, Kuri Kinton's music, showed the problem: for the same register state the RTL was 9.2x (19 dB) louder than MAME. jt03
adds the SSG as `psg << 5` to the FM sum, but on the board the SSG channels (MAME's route 0.20 each) and the FM (0.80) meet at different
weights. Measured: MAME's output has mean 1,850 and RMS 2,330 for the music; the RTL's raw SSG output has mean 176, RMS 218 per `psg_snd` unit,
so the SSG needs 10.4 output units per raw unit; the FM keeps the x3.33 of `taitol_core`. `taitol_board` now outputs `fm + 3.125 * psg` (the core
multiplies by 3.33). The Kuri Kinton register-write stream to the YM matches MAME's for the first 7,866 writes (the whole boot and the start of the coin
sound), the music then starts about 6 frames earlier in the RTL than in MAME but with the same register values. Verified only by the numbers above and one re-run
(`tools/audiocmp.py`), not by ear.

## Hardware tests and releases

All tests are by the owner, on a real MiSTer (DE10-Nano) with a 15 kHz CRT on the analog output and a RetroTINK 4K on Direct Video (HDMI); with
Direct Video the two are fed the very same stream.

| Build | Result on the MiSTer |
|---|---|
| 261004 (Plotting only) | all Plotting MRAs: picture and sound good |
| 261005, 261006 (all sets) | every MRA boots and plays; the DIP switches work, Flip Screen and Service Mode included; sound good in Champion Wrestler (ADPCM voices), Kuri Kinton, Evil Stone and Fighting Hawk. Faults: at random, for a few seconds, striping / streaks / a vertical roll (every board, CRT and 4K alike; a restart of the game usually cured it); vertical games upside down on the RetroTINK 4K; the CRT picture a little low |
| 261007 | **the shaking is gone** (the fix below). CRT Adjust works |
| 20261005 | 261007 plus a longer V-Shift (-32..+31 lines) and the rotation direction of the HDMI scaler path put back to what MAME's orientation says. Tested by the owner on the CRT and the RetroTINK 4K (Direct Video); the scaler rotation path (Direct Video off) was not part of that test |
| 20261006 (this release) | 20261005 plus Raimais with its YM2610, the other versions of Kuri Kinton, Fighting Hawk and Champion Wrestler (10 sets), and a third PLL output for the YM2610. Tested by the owner on the CRT and the RetroTINK 4K: Raimais and the other new sets work |

**The random shaking was a real bug in the raster-to-machine event crossing** (found from two phone videos of Puzznic and Cachat). For a few seconds at
a time the picture striped (alternate lines from the wrong place), streaked (grass colours in the sky) or *rolled vertically* (the HUD at the bottom of
the screen); it came and went by itself and a fresh start of the core usually cured it. Cause: `taitol_video` sent the machine side a toggle per raster
line and, separately, a toggle for line 0; the machine counted lines and cleared the count only when the line-0 toggle arrived *in the same clock* as a
line toggle. The two toggles change on the same video-clock edge but each has its own synchroniser, so when the 96 MHz sampling edge fell between them
they arrived a clock apart, the count was not cleared, and from then on the renderers drew line numbers that were wrong by ever more lines (a roll),
the line-buffer bank parity was wrong (stripes) and the interrupts were not on lines 0 / 120 / 240. A frame is **exactly 1,600,000** machine clocks
(60.000 Hz of the 26.66112 MHz raster clock), so the phase between the two clocks is the same every frame: the bad case persists for as long as the PLL
lock phase (random on each load) keeps it there. Simulation never showed it: its clocks are exact multiples. Fix: the raster sends the *number* of the
line that starts (held stable for a line, read after the toggle has gone through a 4-flop synchroniser), nothing is counted on the machine side. The
bench (Plotting, Play Girls 2, Kuri Kinton, Cachat at frames 300 and 331) gives the same results as before to the pixel and the byte.

**Orientation and Direct Video.** With Direct Video the framework's `screen_rotate` is not used (it needs a DDR3 frame buffer): the stream goes out in the
game's native orientation and the display turns it. The native stream of a ROT270 game has the picture's bottom on the left and its top on the right,
which is right for a CRT turned 90 degrees counter-clockwise (the cabinet's way). A display that turns the stream the other way shows the game upside down;
the game's own **Flip Screen** DIP switch (DSWA bit 1, the same bit in every vertical set) turns the picture 180 degrees exactly: with that switch on, the
picture is the unflipped picture turned 180 degrees pixel for pixel (Fighting Hawk, Play Girls 2: 0 pixels differ in the simulation), and it also matches MAME's
own flipped snapshot. A flip of the video chip's bit alone is *not* a clean turn (Fighting Hawk: 11,749 of 71,680 pixels differ, the layers are offset),
because the game moves its scroll and sprite positions itself when it flips, so the core leaves flipping to the game. A CRT and a display that turns
the other way cannot both be right with one stream: choose the DIP setting for the display in use (MiSTer keeps the DIP settings it has saved, and a
saved setting overrides the MRA's default, which is MAME's: Flip Screen Off).
Without Direct Video, the vertical sets (ROT90 / ROT270 in the MRA's configuration byte) go through `screen_rotate`: ROT270 turns counter-clockwise, ROT90
clockwise, as MAME's orientation says and as the Taito B / F2 cores do. That path has not been seen on hardware (261006 reversed it on the strength of a test made in
Direct Video, which never uses it; it was put back).

**CRT Adjust** is rmonic79's module (`modules/crt_adjust`, as in the owner's Nostradamus core) with the glue `taitol_crt_adjust.sv`: OSD page "CRT Adjust"
(Off / On, H-Size -12..+10 %, H-Position -48..+42 pixels in steps of 6, V-Shift -32..+31 lines); Off is a true bypass. It changes the sync signals, so with
Direct Video it moves the RetroTINK's picture too (one stream). `sim/run_crt.sh` runs the raster through it and measures the shifts: H-Position +6 moves
the HSync 6 pixels; V-Shift +3 moves the VSync 3 lines, +31 by 31, -16 by -16, -32 by -32 (the module adds a constant 2 pixel / 1 line latency when On); settings
beyond the H-Position limit of the raster are clamped. V-Shift delays the VSync by N lines (+) or advances it (-); by the CRT's timing a *later* VSync leaves less
blank between the retrace and the picture, so + should lift the picture and - lower it (not yet confirmed on the CRT).

**Quartus, release 20261006** (`releases/taitol_20261006.rbf`, `quartus_sh --flow compile TaitoL`; the fitter's and the timing analyser's reports are
`releases/taitol_20261006.fit.summary` and `.sta.summary`): 43 % of the ALMs (18,069 of 41,910), 477 of 553 RAM blocks (86 %), 43 of 112 DSPs, 45 timing entries, none negative: every setup slack
is positive (the 96 MHz machine +0.90 ns, the YM2610's 48 MHz +1.74 ns, the HDMI scaler +0.55 ns, the raster clock +22.6 ns), tightest hold 0.242 ns.

## Raimais, its YM2610, and the other versions of Kuri Kinton, Fighting Hawk and Champion Wrestler (release 20261006)

Ten sets were added: Raimais (World rev 1, Japan rev 1, Japan), Kuri Kinton (prototype, Japan, US, US World Games), Fighting Hawk (Japan) and Champion
Wrestler (Japan, US). The other versions run on boards that already existed; their MRAs are made by `tools/make_mra.py` and each image is byte-identical to the
one the simulation used (`tools/mra_verify.py`, all 35 MRAs). The owner ran all ten on a real MiSTer (CRT and RetroTINK 4K) and they work.

**Pictures and machine states against MAME** (`tools/rtlrun.py`, `tools/cmprtl.py`, MAME's default DIP switches, coin at frame 320, 1P start at 345; the sound
chips stubbed out, as in the first batches):

| Set | Result |
|---|---|
| raimais | identical at 300, 420, 500, 560; one-frame transients at 331 (6,397 px) and 360 (498 px) |
| raimaisj, raimaisjo | identical at 300, 331, 360, 420, 560; 633 px at 500 |
| kurikinta, kurikintj, kurikintu, kurikintw | as kurikint: identical at 300, 331, 360 (the prototype also at 420), 2 px at 420 in the others; 500 / 560 (run for the prototype and the Japan set) show the demo's scroll a few pixels apart (about 20-25 k px), as the parent |
| fhawkj | identical at 300, 331, 360, 420 (these four sets were run to frame 425) |
| champwrj, champwru | pictures identical at 300, 331, 360, 420 (champwru: 226 VRAM bytes of state differ for one frame at 331, the picture does not) |

Regression of the new memory arbiter and sound wiring on the other boards (frames 300 and 331): kurikint, puzznicu and champwr identical; fhawk has its known 230 px
transient at 331. Plotting at 331 shows a one-frame CREDIT-text transient (375 px, 48 VRAM bytes), the same with the simulator of the previous release: it is
not from this change (the older claim of an identical 331 predates the raster that is in the core now).

**The YM2610.** jt10 (jt12 tree of the YM2203's jt03) at 8 MHz on the sound Z80's bus (E000-E003, the YM2610's IRQ is the Z80's INT, F200 is the audio ROM bank, the
TC0140SYT gives the NMI and the reset). Its ADPCM-A *and* ADPCM-B read the 512 KB `ymsnd:adpcma` ROM (MAME gives the ADPCM-B the ADPCM-A region when a set has no ADPCM-B
one; Raimais' sound program starts both) through two 8 KB direct-mapped caches that share one SDRAM client; that client has the arbiter's top priority now, because the
chip wants each ADPCM-A byte within 1.5 us (144 machine clocks) of its address. Measured in the simulation with the video's traffic on the bus: the longest wait of an
ADPCM-A read for its cache line was **33 machine clocks**.
*Clock:* the first compile, with jt10 on the 96 MHz machine clock, failed setup by 1.665 ns inside jt12_pg (the multicycle constraint of the YM2203 covers only jt03's
instance, and jt12_div / jt12_rst make their enables on the falling edge, a half-cycle path to every flip-flop they enable). As in the owner's MCatAdv core the chip now runs
on the PLL's third output, 48 MHz in phase with the 96 MHz one (`rtl/pll.v` is that core's), with its own 8 MHz enable, and `TaitoL.sdc` relaxes the paths between its registers
while the enables, the reset and `cen_reg` stay single-cycle. The Z80's side of the chip and the sample reads cross between the two clocks edge to edge.
*Mix* (`taitol_board.sv`): MAME's routes into one speaker are the SSG 0.75 of (a + b + c) * 2/3 and the FM + ADPCM left and right at 1.0 each; with jt10's units equal to ymfm's
(the MCatAdv core's figures) and the core's x3.33 gain that is 9.625 per unit of the SSG's `psg_snd` and 0.297 for (left + right).

**Sound against MAME** (Raimais, MAME's default switches, coin at 320, 600 frames; `tools/mamedump.py --ymlog --wav`, the bench's `+ymlog`, `tools/ymcmp.py`, `tools/audiocmp.py`):
* The sound CPU's writes to the chip are identical, in order, for the first 916 writes after the 60 Hz timer reload pairs (register 27 = 15) are left out: boot, FM and ADPCM
  set-up and the first sounds (MAME frames 3 to 365). Then the games diverge in *time*: the main CPU hands the coin's sound command to the communication chip at frame 325
  in the RTL, 323 in MAME (the later commands come a frame earlier), the same few frames as the pictures' one-frame transients; the sound CPU answers each command correctly.
* **Levels, after the one-to-two frame offset**: RMS of the RTL / MAME per 0.5 s window from 8.5 to 11 s, where ADPCM-B plays too: 1.01, 1.01, 1.02, 0.99, 1.00 (overall **1.005, 0.0 dB**);
  per 1 s window from 5 to 9 s (before ADPCM-B comes in): 0.96, 1.04, 1.01, 1.01. The band energies (60 Hz - 12 kHz) agree within +-3 dB, the 8-12 kHz band is 3-4.5 dB higher in the RTL.
  Waveform cross-correlation at the best lag (1-2 frames): 0.83 / 0.92 / 0.86 for FM + ADPCM-A in 5.2-6.6 / 6.6-8.0 / 8.0-9.4 s; 0.66 in 9.3-10.6 s, where ADPCM-B starts, against 0.47
  with ADPCM-B stubbed out (the level in that window was 0.77 without it).
* **ADPCM-B**: the copy of jt12 the core had (from the Pocket core) had the ADPCM-B engine stubbed out; the sound log showed Raimais starting ADPCM-B samples at MAME frame 558, so it is instantiated again
  in `modules/jt12/jt12_top.v` (`modules/jt12/LOCAL_CHANGES.txt`) and reads the same ROM through its own cache.
* The SSG is not exercised in the first 12 s of the attract mode (no register 0-15 write), so its level is by calculation (the owner's MCatAdv core, checked on hardware, uses the same
  figures), not measured here.

## Quartus 17.0.2 (MiSTer's toolchain)

`quartus_sh --flow compile TaitoL` in the repository root: about 20 minutes on an idle machine, up to an hour with other builds running. Do not touch the
project's files (`files.qip`, `TaitoL.qsf`, ...) while it runs: the flow then fails at the very end ("Settings File changed outside of Quartus"). The
fractional PLL gives exactly 26.66112 MHz (fit report). Block RAM is the resource to watch (86 % in the release). `tools/release.py` copies the RBF and
the fitter's and the timing analyser's summaries into `releases/`; `tools/package.py` makes the zip in the SD card structure.

## Known gaps and guesses

* **Raimais' YM2610**: the SSG level is by calculation (Raimais' first 12 s of attract mode use no SSG, so the simulation could not measure it),
  its FM, ADPCM-A and ADPCM-B levels are measured against MAME (see above); on the MiSTer the owner found the sound good. ADPCM-A / B ROM reads past the 512 KB region wrap around (MAME reads open bus there); the game does not do it.
* The jt12 copy's other local simplifications (the ADPCM-A channel-enable register is fixed to all channels: `ch_enable`) are unchanged from the Pocket core's copy; Raimais does not need them.
* **Video timing** (424 x 262 at 6.66528 MHz) is backed by Guru's real Puzznic PCB measurement in MAME's source (VSync 59.9992 Hz at a 13.3304 MHz
  oscillator; the quoted 15.419 kHz "HSync" is a composite-sync pulse count, see `docs/hardware.md` 3.9b). Where the interrupts sit relative to the
  picture (levels at raster lines 120, 0, 240) is MAME's choice, not hardware knowledge.
* **Rotation through the HDMI scaler** (Direct Video off) is checked in Python only (see above), not on hardware.
* **MAME's own gaps** in the TC0090LVC model (Cuby Bop's text colours and scrolling, ignored control registers): "identical to MAME" is the bar, not
  "identical to the board".
* **Sound levels** are matched to MAME's final mix with constants (YM2203: FM x3.33, SSG x3.125; MSM5205 x2.25; YM2610: FM + ADPCM x0.297 per side, SSG x9.625), not by modelling MAME's per-channel routing; the
  owner found the sound good on the four games listed above, the others were not compared by ear.
* The trackball direction of American Horseshoes with a real mouse is unverified (MAME's analog injection is verified; the mouse-to-counter mapping and
  the OSD invert option are not testable in the simulation).
* The sprite renderer overran 8 lines once (frame ~135 of the boot), when the game first runs interrupt-driven code and its sprite table briefly has ~90+
  sprites overlapping on a line (the engine needs about 570 + 45 per sprite clocks of a 4,600-clock line); none in the next 430 frames of attract and play.
  Harmless so far (the LED shows overruns).
* Two OSD items are leftovers of the hunt for the shaking and do nothing useful now: "BG scroll update" (Live / At vblank: the BG scroll registers latched
  with the sprite RAM) and "SDRAM read capture" (Normal / Late: for a module that answers slowly; the same item as in the owner's other cores).
* Simulation speed: about 3 s per frame without the sound chip and about 7 s with it; reaching gameplay (frame ~350) takes 15-45 minutes.
