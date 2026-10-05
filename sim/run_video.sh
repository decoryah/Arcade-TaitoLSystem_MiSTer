#!/bin/bash
# Frozen-state video bench (sim/tb_video_top.sv):
#   sim/run_video.sh <hex dir from tools/tb_prep.py> <tile count> <frames> <out prefix>
# Builds in $HOME/build_taitol/video, writes <out prefix>.fNNN.ppm.
set -e
cd "$(dirname "$0")"
HEX="$1"; GFXN="$2"; FRAMES="${3:-2}"; OUT="$4"
[ -d "$HEX" ] && [ -n "$OUT" ] || { echo "usage: $0 <hexdir> <tiles> <frames> <out-prefix>" >&2; exit 2; }
case "$HEX" in /*) ;; *) HEX="$PWD/$HEX" ;; esac
case "$OUT" in /*) ;; *) OUT="$PWD/$OUT" ;; esac
. "$HOME/tools/oss-cad-suite/environment"
B="$HOME/build_taitol/video"; mkdir -p "$B"
if [ -z "$NOBUILD" ]; then
verilator --cc --exe --build -j 8 -O3 --x-assign fast --x-initial fast -CFLAGS "-O3 -march=native" \
    -Wall -Wno-fatal -Wno-DECLFILENAME -Wno-UNUSEDSIGNAL -Wno-UNOPTFLAT -Wno-PINCONNECTEMPTY -Wno-WIDTH -Wno-CASEINCOMPLETE \
    -Wno-TIMESCALEMOD -Wno-PINMISSING -Wno-INITIALDLY -Wno-UNDRIVEN -Wno-SYNCASYNCNET -Wno-MULTIDRIVEN -Wno-LATCH -Wno-BLKSEQ \
    -Wno-UNSIGNED -Wno-CMPCONST -Wno-VARHIDDEN -Wno-BLKANDNBLK --no-assert-case -Wno-PROCASSINIT -Wno-WIDTHTRUNC -Wno-WIDTHEXPAND \
    --top-module tb_video_top -Mdir "$B/obj" \
    ../rtl/taitol_ram.sv ../rtl/taitol_vmem.sv ../rtl/taitol_bg.sv ../rtl/taitol_tx.sv ../rtl/taitol_spr.sv ../rtl/taitol_bm.sv \
    ../rtl/taitol_video.sv ../rtl/taitol_vcore.sv tb_gfx_rom.sv tb_video_top.sv tb_video.cpp > "$B/build.log" 2>&1 \
    || { grep -E "%Error|error:" "$B/build.log" | head -40; exit 1; }
fi
cd "$B"
./obj/Vtb_video_top "$OUT" "$FRAMES" +vram="$HEX/vram.hex" +sprprev="$HEX/sprprev.hex" +pal="$HEX/pal.hex" \
    +vregs="$HEX/vregs.hex" +gfx="$HEX/gfx.hex" +gfxn="$GFXN"
