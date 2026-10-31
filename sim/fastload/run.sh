#!/bin/bash
# Bench for the fast load (target/mister/taitol_fastload.sv): ./run.sh [image length]
set -e
command -v verilator >/dev/null || export PATH="$HOME/tools/oss-cad-suite/bin:$PATH"
cd "$(dirname "$0")"
B=$HOME/build_taitol/fastload; mkdir -p $B
verilator --cc --exe --build -O2 -Wno-fatal -Wno-WIDTH --top-module taitol_fastload -Mdir $B \
    ../../target/mister/taitol_fastload.sv tb_fastload.cpp > $B/build.log 2>&1 || { tail -30 $B/build.log; exit 1; }
$B/Vtaitol_fastload "${1:-0x3A0830}"
