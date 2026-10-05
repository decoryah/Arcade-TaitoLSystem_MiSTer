#!/bin/bash
# CRT Adjust bench (sim/tb_crt_top.sv): the raster and rmonic79's CRT Adjust through the core's glue, shifts measured against the native sync.
set -e
cd "$(dirname "$0")"
. "$HOME/tools/oss-cad-suite/environment"
B="$HOME/build_taitol/crt"; mkdir -p "$B"
verilator --cc --exe --build -j 4 -O2 --x-assign fast --x-initial fast \
    -Wall -Wno-fatal -Wno-DECLFILENAME -Wno-UNUSEDSIGNAL -Wno-UNOPTFLAT -Wno-PINCONNECTEMPTY -Wno-WIDTH -Wno-CASEINCOMPLETE \
    -Wno-TIMESCALEMOD -Wno-PINMISSING -Wno-INITIALDLY -Wno-UNDRIVEN -Wno-MULTIDRIVEN -Wno-LATCH -Wno-BLKSEQ -Wno-UNSIGNED \
    -Wno-CMPCONST -Wno-VARHIDDEN --no-assert-case -Wno-PROCASSINIT -Wno-WIDTHTRUNC -Wno-WIDTHEXPAND -Wno-BLKANDNBLK -Wno-SYNCASYNCNET -Wno-SELRANGE \
    --top-module tb_crt_top -Mdir "$B/obj" ../rtl/taitol_ram.sv ../rtl/taitol_video.sv ../modules/crt_adjust/crt_adjust.sv ../rtl/taitol_crt_adjust.sv \
    tb_crt_top.sv tb_crt.cpp > "$B/build.log" 2>&1 || { grep -E "%Error|error:" "$B/build.log" | head -30; exit 1; }
exec "$B/obj/Vtb_crt_top"
