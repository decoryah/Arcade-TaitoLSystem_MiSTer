#!/bin/bash
# Whole-machine bench (sim/tb_system_top.sv):
#   sim/run_system.sh <game.rom> <frames> <out prefix> [tb_system arguments: +load=rtl +coin=F +start=F +every=N +state=f1,f2]
# Builds in $HOME/build_taitol/system; writes <out prefix>.fNNN.ppm and .wav. NOBUILD=1 reuses the build.
set -e
cd "$(dirname "$0")"
ROM="$1"; FRAMES="${2:-4}"; OUT="$3"; shift 3 || true
[ -f "$ROM" ] && [ -n "$OUT" ] || { echo "usage: $0 <game.rom> <frames> <out-prefix> [args]" >&2; exit 2; }
case "$ROM" in /*) ;; *) ROM="$PWD/$ROM" ;; esac
case "$OUT" in /*) ;; *) OUT="$PWD/$OUT" ;; esac
. "$HOME/tools/oss-cad-suite/environment"
DEFS=""; B="$HOME/build_taitol/system"
if [ -n "$NOYM" ]; then DEFS="+define+NOYM"; B="$HOME/build_taitol/system_noym"; fi     # NOYM=1: no sound chip, much faster
if [ -n "$IDEAL" ]; then DEFS="$DEFS +define+IDEAL_ROM"; fi                      # IDEAL=1: program ROM without cache or wait states (timing experiment)
if [ -n "$BTAG" ]; then B="${B}_$BTAG"; fi                                      # BTAG=x: a build dir of its own (never touch a binary that is running)
if [ -n "$PROF" ]; then B="${B}_prof"; PROFFLAGS="-CFLAGS -pg -LDFLAGS -pg"; fi      # PROF=1: gprof build (gmon.out in the build dir)
mkdir -p "$B"
JT=../modules/jt12
JTFILES=$(grep -o '[A-Za-z0-9_/]*\.v ' $JT/jt03.qip | sed "s|^|$JT/|" | tr '\n' ' ')
if [ -z "$NOBUILD" ]; then
verilator --cc --exe --build -j 8 -O3 --x-assign fast --x-initial fast -CFLAGS "-O3 -march=native" \
    -Wall -Wno-fatal -Wno-DECLFILENAME -Wno-UNUSEDSIGNAL -Wno-UNOPTFLAT -Wno-PINCONNECTEMPTY -Wno-WIDTH -Wno-CASEINCOMPLETE \
    -Wno-TIMESCALEMOD -Wno-PINMISSING -Wno-INITIALDLY -Wno-UNDRIVEN -Wno-SYNCASYNCNET -Wno-MULTIDRIVEN -Wno-LATCH -Wno-BLKSEQ \
    -Wno-UNSIGNED -Wno-CMPCONST -Wno-VARHIDDEN -Wno-BLKANDNBLK --no-assert-case -Wno-PROCASSINIT -Wno-WIDTHTRUNC -Wno-WIDTHEXPAND \
    $DEFS $PROFFLAGS -I../modules/jt680x --top-module tb_system_top -Mdir "$B/obj" \
    ../rtl/taitol_ram.sv ../rtl/taitol_cen.sv ../rtl/taitol_vmem.sv ../rtl/taitol_bg.sv ../rtl/taitol_tx.sv ../rtl/taitol_spr.sv ../rtl/taitol_bm.sv \
    ../rtl/taitol_video.sv ../rtl/taitol_vcore.sv ../rtl/taitol_cache.sv ../rtl/taitol_ctrl.sv ../rtl/taitol_main.sv ../rtl/taitol_board.sv ../rtl/taitol_sub.sv ../rtl/taitol_tri.sv ../rtl/taitol_syt.sv ../rtl/taitol_mcu.sv ../rtl/taitol_i8255.sv ../rtl/taitol_upd4701.sv ../modules/jt680x/jt6805.v ../modules/jt680x/jt6805_alu.v ../modules/jt680x/jt6805_ctrl.v ../modules/jt680x/jt6805_regs.v \
    ../rtl/taitol_core.sv ../target/mister/taitol_mem.sv ../target/mister/sdram_ctrl.sv \
    ../modules/cpu-tv80/tv80_alu.v ../modules/cpu-tv80/tv80_core.v ../modules/cpu-tv80/tv80_mcode.v ../modules/cpu-tv80/tv80_reg.v ../modules/cpu-tv80/tv80s_cen.v \
    $JTFILES ../modules/jt5205/jt5205.v ../modules/jt5205/jt5205_adpcm.v ../modules/jt5205/jt5205_timing.v ../modules/jt5205/jt5205_interpol2x.v ../modules/jt49/jt49.v ../modules/jt49/jt49_cen.v ../modules/jt49/jt49_div.v ../modules/jt49/jt49_eg.v ../modules/jt49/jt49_exp.v ../modules/jt49/jt49_noise.v \
    sdram_model.sv tb_system_top.sv tb_system.cpp > "$B/build.log" 2>&1 \
    || { grep -E "%Error|error:" "$B/build.log" | head -40; exit 1; }
fi
[ -n "$IDEAL" ] && [ -f "$IDEAL_HEX" ] && cp -f "$IDEAL_HEX" "$B/ideal_prog.hex"
mkdir -p "$B/modules/jt680x" && cp -f ../modules/jt680x/6805.uc "$B/modules/jt680x/"      # the 6805 core's microcode, read at start (jt680x/UPSTREAM.txt)
cd "$B"
cmp -s ./obj/Vtb_system_top ./obj/taitol_sim_bin || cp -f ./obj/Vtb_system_top ./obj/taitol_sim_bin    # a process name of its own: other projects build a Vtb_system_top too (pkill by name!)
exec ./obj/taitol_sim_bin "$ROM" "$FRAMES" "$OUT" "$@"
