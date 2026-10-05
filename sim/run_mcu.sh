#!/bin/bash
# MCU bench (sim/tb_mcu_top.sv): the MC68705P3 model and its host interface alone.   sim/run_mcu.sh <mcu.bin> 
set -e
cd "$(dirname "$0")"
ROM="$1"; case "$ROM" in /*) ;; *) ROM="$PWD/$ROM" ;; esac
. "$HOME/tools/oss-cad-suite/environment"
B="$HOME/build_taitol/mcu"; mkdir -p "$B"
verilator --cc --exe --build -j 4 -O2 --x-assign fast --x-initial fast \
    -Wall -Wno-fatal -Wno-DECLFILENAME -Wno-UNUSEDSIGNAL -Wno-UNOPTFLAT -Wno-PINCONNECTEMPTY -Wno-WIDTH -Wno-CASEINCOMPLETE \
    -Wno-TIMESCALEMOD -Wno-PINMISSING -Wno-INITIALDLY -Wno-UNDRIVEN -Wno-MULTIDRIVEN -Wno-LATCH -Wno-BLKSEQ -Wno-UNSIGNED \
    -Wno-CMPCONST -Wno-VARHIDDEN --no-assert-case -Wno-PROCASSINIT -Wno-WIDTHTRUNC -Wno-WIDTHEXPAND -Wno-BLKANDNBLK -Wno-SYNCASYNCNET \
    -I../modules/jt680x --top-module tb_mcu_top -Mdir "$B/obj" ../rtl/taitol_ram.sv ../rtl/taitol_mcu.sv \
    ../modules/jt680x/jt6805.v ../modules/jt680x/jt6805_alu.v ../modules/jt680x/jt6805_ctrl.v ../modules/jt680x/jt6805_regs.v \
    tb_mcu_top.sv tb_mcu.cpp > "$B/build.log" 2>&1 || { grep -E "%Error|error:" "$B/build.log" | head -30; exit 1; }
mkdir -p "$B/run/modules/jt680x" && cp -f ../modules/jt680x/6805.uc "$B/run/modules/jt680x/"
cd "$B/run"
exec "$B/obj/Vtb_mcu_top" "$ROM" "${@:2}"
