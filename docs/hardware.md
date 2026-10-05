# Taito L System — hardware map

Source of truth: MAME `src/mame/taito/taito_l.cpp` and `src/devices/machine/tc009xlvc.{cpp,h}`
(checked out under `ref/mame`, master as of 2026-10-04). Everything here was read from that
source unless tagged **[derived]** (an inference, not in MAME) or **[unknown]**.

## 1. Board families

| Family | CPUs | Sound | I/O | Sets (parent) |
|---|---|---|---|---|
| 1-CPU | TC0090LVC | YM2203 | DIPs/inputs read through YM2203 ports A/B via 2x LS157 mux (plotting/puzznic/horshoes); i8255 (palamed/cachat/cubybop/plgirls) | plotting, puzznic, palamed, cachat, horshoes, cubybop, plgirls, plgirls2 |
| 2-CPU | TC0090LVC + sound Z80 | YM2203 | TC0040IOC (kurikint), TC0510NIO (evilston); MB8421 dual-port RAM | kurikint, evilston |
| 3-CPU | TC0090LVC + slave Z80 + sound Z80 | YM2203 (fhawk, champwr) / YM2610 (raimais) | TC0220IOC (fhawk, champwr), TC0040IOC (raimais) | fhawk, champwr, raimais |

Orientation: fhawk, horshoes, evilston, plgirls, plgirls2 are ROT270; the rest ROT0.

## 2. Clocks

- TC0090LVC (main Z80 core): 13.33056 MHz / 2 = **6.66528 MHz** (verified on pin 122, per MAME comment)
- 1-CPU YM2203: 13.33056 MHz / 4 = 3.33264 MHz
- 2/3-CPU slave + sound Z80: 12 MHz / 3 = 4 MHz; their YM2203: 12 MHz / 4 = 3 MHz
- raimais YM2610: 8 MHz (separate 8 MHz osc, also feeds the 2nd Z80)
- puzznic MCU (Arkanoid MC68705P3): 3.579545 MHz
- champwr MSM5205: 384 kHz, prescaler S48_4B (8 kHz sample rate)

## 3. TC0090LVC (main CPU + video)

### 3.1 CPU memory map (inside the chip)

```
0000-5FFF  ROM, fixed (region "maincpu")
6000-7FFF  ROM, 8 KB window, address = (rom_bank << 13) | (offs & 0x1fff)
8000-BFFF  external (board-specific: work RAM, I/O, sound, shared RAM)
C000-FDFF  4 x 4 KB windows into the 20-bit VRAM space: slot = addr[13:12],
           vram_addr = (ram_bank[slot] << 12) | (addr & 0xfff)
FE00-FEFF  video registers (vregs, 0x100 bytes)
FF00-FF02  IRQ vectors for levels 0,1,2   (mirror +0x10 .. +0xF0)
FF03       IRQ enable (bit0/1/2 = level 0/1/2)
FF04-FF07  ram_bank[0..3]
FF08       rom_bank
```

Reset: `ram_bank[*] = 0x80`, `rom_bank = 0`, irq vectors/enable = 0, vregs[0..4] = 0.

### 3.2 VRAM space (20-bit, 8-bit wide)

```
010000-01FFFF  VRAM (64 KB)   (014000-01FFFF writes go through vram_w; 010000-013FFF
                               are mapped read-only/unused in MAME — first tiles always blank)
040000-05FFFF  bitmap RAM (128 KB)   — only used in bitmap mode
080000-0801FF  palette RAM, mirror 0xE00  (so 080000-080FFF)   <- reset state of every slot
```

Offsets below are indices into MAME's `m_vram[]` (= address - 0x10000):

```
8000-8FFF  BG0 tilemap  (64x32, 2 bytes/tile)
9000-9FFF  BG1 tilemap
A000-AFFF  TX  tilemap
B000-B3FF  sprite RAM + scroll registers
```

Characters are **RAM-based**: MAME decodes the *entire* 64 KB VRAM as 8x8 4bpp tiles (gfx(2)), and the TX
layer's 11-bit code N reads `m_vram[N*32 .. N*32+31]`. So character data can live anywhere in VRAM that
the game keeps free of tilemap/sprite data. MAME only accepts CPU writes at index >= 0x4000.

### 3.3 Tile formats

BG0/BG1 (2 bytes/tile): byte0 = code[7:0]; byte1 = `[7:4]` palette, `[3:2]` bank slot, `[1:0]` code[9:8].
Final code = code10 | (vregs[bank_slot] << 10). **No flip bits.** Tiles come from the
gfx ROM region.

TX (2 bytes/tile): byte0 = code[7:0]; byte1 = `[7:4]` palette, `[2:0]` code[10:8]. Tiles come from
**character RAM in VRAM**, not ROM.

Tilemaps 64x32 of 8x8, pen 0 transparent. 8x8 4bpp ROM layout, MAME gfx_layout:
planes `{8, 12, 0, 4}`, x `{3,2,1,0, 19,18,17,16}`, y `step 32 bits`, tile = 32 bytes.

### 3.4 Scroll and sprite RAM (at VRAM B000-B3FF, 0x400 bytes)

```
3F4-3F6  BG0 scroll: xlo, xhi, y
3FC-3FE  BG1 scroll: xlo, xhi, y
000-3E7  sprites, 8 bytes each, 125 entries
```

Scroll is read live (TC0090LVC); sprite RAM is **latched at vblank** (`screen_eof` copies B000-B3FF
to a buffer on the vblank rising edge). Scroll pixel offsets: BG0 dx 28, BG1 dx 38, TX dx -8 (non-flipped);
flipped -11 / -21 / -8. Per-game extra x/y offsets are set via `set_tilemap_xoffs/yoffs` (none used by taito_l.cpp).

### 3.5 Sprites (8 bytes)

```
0   code[7:0]
1   code[15:8]
2   [3:0] palette
3   [1] flipY  [0] flipX
4   x[7:0]
5   [0] x[8]
6   y[7:0]
7   unused/garbage
```

16x16 sprites built from four 8x8 gfx tiles (`code << 2` fed through the tile callback, then `>> 2`).
x wraps: `if x >= cliprect.max_x: x -= 512`; same for y with 256. Palette bit 3 set → sprite priority
mask 0xAA (drawn behind BG0 where BG0 has priority class 0 — see 3.7). Sprite order: ascending index,
later entries overwrite earlier ones.

### 3.6 Control register vregs[4] (0xFE04)

```
bit5  screen enable
bit4  global flip (X and Y)
bit3  BG0 priority
[2:0] == 7  -> 8bpp bitmap mode (bitmap RAM, 512 px/line, palette index = byte)
```

vregs[0..3] = tile bank slots 0..3 (see 3.3). Writing vregs[0..3] marks BG tilemaps dirty (MAME only).

### 3.7 Layer order (non-bitmap mode)

1. BG1 opaque (transparency ignored — fills the screen)
2. BG0, priority class `bg0_pri ? 0 : 1`
3. Sprites (priority-masked against BG0 class, see above)
4. TX on top

The exact sprite-vs-BG0 priority truth table must be reproduced from `gfx(1)->prio_transpen`
semantics — pin it down with the reference renderer, do not guess.

### 3.8 Palette

256 entries, 2 bytes each at 080000. MAME format `xBGRBBBBGGGGRRRR_bit0` → 5 bits/channel
with the extra low bits in byte1 bits 4..6. **[verify against emupal.h before writing RTL]**

### 3.9 Interrupts

Z80 runs in **IM 2**. MAME's `irq_callback` clears the line and returns `irq_vector[last_level]`
(the byte from FF00+level), so the CPU vectors through `(I << 8) | that byte`.

MAME fires them from a per-scanline timer, one level per matching line, gated by FF03 bits:

| Level | Scanline | Enable bit | Meaning |
|---|---|---|---|
| 0 | 120 | bit0 | **[unknown]** source |
| 1 | 0 | bit1 | **[unknown]** (vbl-out? hblank?) |
| 2 | 240 | bit2 | vblank |

MAME also skips all IRQs unless the CPU is already in IM 2 (kludge so `plgirls` boots: its program enables
interrupts before it selects IM 2, and in IM 0 the vector byte would be executed as an opcode). Real hardware presumably
differs; **the core copies the kludge** (taitol_main.sv: `ls_pulse && z80_im == 2`; tv80_core exports its interrupt mode as
`IM`), because MAME is the oracle and every other set selects IM 2 before it enables an interrupt, so nothing else is affected.
Writing FF03 so that the *current* level's enable bit is cleared deasserts INT (needed for
Plotting test mode).

### 3.9b Video timing

MAME: 320x256 total, visible x 0-319, y 16-239 (320x224), 60 Hz, vblank time 0 (i.e. **not modelled** —
the Taito B driver uses the same fudge, so MAME gives no real H/V totals for any of these boards).
**Confirmed by a real-PCB measurement** (Guru, in MAME's `taito_l.cpp`, genuine Puzznic board K1100439A): master oscillator
13.33040 MHz, "HSYNC" 15.4190 kHz, VSYNC 59.9992 Hz. Reading it:

* pixel clock = master / 2 = 6.6652 MHz; 6.6652 MHz / (424 x 262 = 111,088) = **59.9992 Hz**: exactly the measured VSync;
* the measured "HSYNC" is not the line rate (6.6652 MHz / 424 = 15.720 kHz): 15.419 / 15.720 = 257 / 262, i.e. a frequency
  counter on JAMMA's *composite* sync, whose vsync pulse swallows about 6 line pulses (262 - 6 + 1 = 257 per frame);
* so the raster is 424 x 262 (320 + 104 blank, 224 visible + 38 blank), as the core has it. The vsync pulse is about 6 lines
  tall on the board (the core uses 3, which any display accepts).

(The other numbers in that file, "VSync 55.8268 Hz, HSync 14.7739 kHz", are from the LA Girl *bootleg* with a 27.2109 MHz crystal
and are described there as a possible sync/PCB fault: not Taito L timing.)

| System | Dot clock | H x V total | Basis |
|---|---|---|---|
| Taito F2 | 26.686 MHz / 4 = 6.6715 MHz | 424 x 262 (60.06 Hz) | upstream F2 core |
| Taito B | 27.164 MHz / 4 = 6.791 MHz | 448 x 253 (59.92 Hz) | "Guru" PCB measurement: HSync 15.1782 kHz, VSync 60.00000 Hz; totals chosen as a compromise (see `ref/TaitoB/rtl/taitob_video_timing.sv`) |
| Taito L | 13.33056 / 2 = 6.66528 MHz | 424 x 262 (60.0000 Hz; 59.9992 at the measured oscillator) | Guru's Puzznic PCB measurement, read as above |

So the totals differ between Taito generations and cannot be copied from one to another; Taito L's are now backed by a measurement.
What is still MAME's choice, not hardware knowledge, is where the three interrupt levels sit relative to the picture (lines 120, 0, 240).

## 4. Board-level maps (main CPU, window 8000-BFFF)

| Set family | Map |
|---|---|
| plotting / flipull | 8000-9FFF RAM; A000-A003 YM2203 (reads also latch mux select = offset bit1); A800 nop (watchdog/irq ack); B800 nop |
| puzznic | as plotting + B800 MCU data r/w, B801 MCU control (read returns 1, write ignored), BC00 nop; A800 read nop |
| puzznici/b/ba (bootlegs) | puzznic without the MCU (B801 read only) |
| palamed / cachat / cubybop / plgirls* | 8000-9FFF RAM; A000-A003 YM2203 r/w (DIPs via its ports A/B); A800-A803 i8255 (IN0/IN1/IN2); B000 nopw; B001 nopr |
| horshoes | 8000-9FFF RAM; A000-A003 YM2203; A800 `uPD4701A read_xy(offset>>2)` (A800/A804/A808/A80C select), A802 reset_x, A803 reset_y; B801 nopr; **B802 write = GFX bank (tile code \|= bank << 12)**; BC00 nopw |
| kurikint | 8000-9FFF RAM; A000-A7FF MB8421 right; A800-A801 TC0040IOC |
| evilston | 8000-9FFF RAM; A000-A7FF MB8421 right; A800-A807 TC0510NIO |
| raimais | 8000-87FF MB8421 right; 8800-8801 TC0040IOC; 8C00/8C01 TC0140SYT master; A000-BFFF RAM |
| fhawk | 8000-9FFF RAM (shared with slave E000-FFFF); A000-BFFF RAM |
| champwr | 8000-9FFF RAM; A000-BFFF RAM shared with slave C000-DFFF |

### 4.1 Implemented boards (RTL: `taitol_board.sv`, board ids in `tools/taitol_rom.py`)

| id | Sets | What the board module adds |
|---|---|---|
| 0 | plotting family, flipull | YM2203 on the main bus, DIP / input multiplexers selected by A001 vs A003 reads |
| 1 | puzznic, puzznicu, puzznicj | + MC68705P3 (`taitol_mcu` + `jt6805` + its 2 KB program from the image + the Arkanoid-style host latch interface at B800) |
| 2 | puzznici, puzznicb, puzznicba | no MCU |
| 3 | palamed*, cachat, tubeit, cubybop, plgirls*, lagirl | DIPs read through the YM2203's I/O ports (no multiplexer), IN0-IN2 through an 8255 at A800 (`taitol_i8255`, mode 0) |
| 4 | horshoes | + uPD4701A trackball (`taitol_upd4701`), B802 graphics bank |
| 5 | kurikint* | second Z80 (`taitol_sub`, 4 MHz) with the YM2203, MB8421 dual-port RAM (A000-A7FF here, E000-E7FF there), TC0040IOC at A800/A801 |
| 6 | evilston | as 5 with a 48 KB sub ROM and TC0510NIO at A800-A807 |

The sub CPU's interrupt is `irq0_line_hold` at the start of vblank (held until acknowledged; the acknowledge supplies FF).
The TC0040IOC is "select a register at A801, read / write it at A800"; its register 4 (coin lockout / counters) is the only one
that holds a value; unselected registers read FF. The sub ROM is kept in block RAM (loaded from the image's audiocpu region, 64 KB).

### 4.2 The 8-bit bitmap mode

Video register 4 bits [2:0] == 7 (only Cachat's intro uses it): the picture is VRAM-space 040000-05FFFF as 512 bytes a row, 256 rows,
each byte a palette index, pixel (x, y) at `(y & 255) * 512 + (x & 511)`; flipped: row `256 - y`, column `320 - x`. Nothing else is drawn
(no tiles, text or sprites). RTL: `taitol_bm` fills the BG1 line buffer from the RAM's second port, and the mixer shows only that buffer.

Sub-CPU maps of the 3-CPU boards (fhawk, champwr, raimais) are in the driver, lines ~508-702; copy them into this file as each
family is implemented rather than all up front.

## 5. Sets and ROM regions

`maincpu` (program, up to 0x100000), `audiocpu`, `slave`, `maincpu:gfx` (tile+sprite ROM; 0x20000 for
puzznic up to 0x180000 for champwr), `ymsnd:adpcma` (raimais, 0x80000), `adpcm` (champwr MSM5205,
0x20000), `mcu:mcu` (puzznic, 0x800, `c20-01.ic4` CRC 085f68b4). `maincpu` region must be a power of
two in MAME (`rom_r` masks with length-1).

Full set list is at the bottom of `taito_l.cpp` (lines 2520-2567). Parents: raimais, fhawk, champwr,
kurikint, plotting, puzznic, horshoes, palamed, cachat, cubybop, plgirls, plgirls2, evilston.

## 6. MAME version

ROMs are MAME 0.289 (tag `mame0289`, released 2026-07-30). `ref/mame` is master; diffed against the tag:
`tc009xlvc.cpp/.h` are **identical**, `taito_l.cpp` differs only cosmetically plus one functional change:
0.289 used `config.set_perfect_quantum(m_maincpu)` for **fhawk and raimais** (3-CPU), master loosens it to
`set_maximum_quantum(audiocpu_clock/4)`. So MAME gives no hard answer on inter-CPU timing for the 3-CPU
games; use 0.289 as the oracle (`git -C ref/mame show mame0289:<path>` works for any file).

## 7. Known unknowns / MAME TODOs worth carrying over

- IRQ levels 0 and 1: real source unknown (MAME guesses lines 120 and 0).
- Text-plane colours only right in Cuby Bop after starting a game and resetting.
- Cuby Bop game scrolling looks wrong in MAME.
- A bunch of control registers are ignored by MAME.
- plgirls2b is a bootleg on plain Z80 hardware with scroll offset problems — skip it.

## 8. Verified by simulation against MAME 0.289 (2026-10-04)

These statements above were checked, not just read: the reference renderer (`tools/taitol_ref.py`) and the RTL both reproduce
MAME's frames pixel for pixel (`docs/status.md`). Things that were easy to get wrong and are now settled:

* The sprite RAM is drawn from the copy made at the **end of the previous frame** (using the live RAM gives 55-121 wrong
  pixels when it changes between frames).
* The first sprite wins, and every opaque sprite pixel claims its screen pixel *even when it is hidden* behind BG0 (colour bit 3
  set, BG0 priority bit clear) -- it still blocks later sprites.
* 8x8 tile rows are 4 bytes: pixel u (0-3) of a half is `{B1[4+u], B1[u], B0[4+u], B0[u]}`, halves from (b0,b1) and (b2,b3).
* The text layer's x scroll is -8 (screen x 0 shows map pixel 8); BG0/BG1 add 28 / 38 to their scroll registers.
* The YM2203 core (jt03) runs at 3.33264 MHz / 72 = 46,287 Hz samples; MAME's mix is 10.5 dB louder than jt03's raw output.
* `plottinga`'s program is bit-reversed per byte (MAME `init_plottinga`); the image keeps it raw and sets config flag 0.
