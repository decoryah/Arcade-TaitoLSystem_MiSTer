#!/bin/bash
# Board-level bench (sim/tb_board_top.sv): the YM2203 path of taitol_board in isolation.
set -e
cd "$(dirname "$0")"
. "$HOME/tools/oss-cad-suite/environment"
B="$HOME/build_taitol/board"; mkdir -p "$B"
JT=../modules/jt12
JTFILES=$(grep -o '[A-Za-z0-9_/]*\.v ' $JT/jt03.qip | sed "s|^|$JT/|" | tr '\n' ' ')
verilator --cc --exe --build -j 8 -O3 --x-assign fast --x-initial fast -CFLAGS "-O3 -march=native" \
    -Wall -Wno-fatal -Wno-DECLFILENAME -Wno-UNUSEDSIGNAL -Wno-UNOPTFLAT -Wno-PINCONNECTEMPTY -Wno-WIDTH -Wno-CASEINCOMPLETE \
    -Wno-TIMESCALEMOD -Wno-PINMISSING -Wno-INITIALDLY -Wno-UNDRIVEN -Wno-MULTIDRIVEN -Wno-LATCH -Wno-BLKSEQ -Wno-UNSIGNED \
    -Wno-CMPCONST -Wno-VARHIDDEN --no-assert-case -Wno-PROCASSINIT -Wno-WIDTHTRUNC -Wno-WIDTHEXPAND \
    --top-module tb_board_top -Mdir "$B/obj" ../rtl/taitol_ram.sv ../rtl/taitol_cen.sv ../rtl/taitol_board.sv \
    $JTFILES ../modules/jt49/jt49.v ../modules/jt49/jt49_cen.v ../modules/jt49/jt49_div.v ../modules/jt49/jt49_eg.v ../modules/jt49/jt49_exp.v ../modules/jt49/jt49_noise.v \
    tb_board_top.sv tb_board.cpp > "$B/build.log" 2>&1 || { grep -E "%Error|error:" "$B/build.log" | head -30; exit 1; }
cp -f "$B/obj/Vtb_board_top" "$B/obj/taitol_board_bin"
exec "$B/obj/taitol_board_bin"
