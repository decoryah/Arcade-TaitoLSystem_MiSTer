#!/bin/bash
# Run the frozen-state video bench (sim/run_video.sh) over dumped frames and compare each with MAME's snapshot.
#   tools/vtest.sh <game> <frame> [<frame> ...]        (dumps in work/dumps/<game>.fNNNNN.*, snapshots in work/mame/snap)
# Builds once (first frame), reuses the build after. Prints one line a frame; exit status = number of failures.
export MSYS_NO_PATHCONV=1
PY=${PY:-/c/Python38/python.exe}
RW="$(cd "$(dirname "$0")/.." && pwd -W)"       # the repository
BASEW="$($PY "$RW/tools/paths.py" base)"          # work/ and ref/ (tools/paths.py)
R="$(cd "$BASEW" && pwd)"
GAME="$1"; shift
WR="$($PY "$RW/tools/paths.py" wslbase)"; WREPO="$($PY "$RW/tools/paths.py" wslrepo)"
fail=0; first=1
for f in "$@"; do
    n=$(printf %05d "$f")
    tiles=$($PY "$RW/tools/tb_prep.py" "$BASEW/work/dumps/$GAME" "$f" "$BASEW/work/hex/$GAME.f$n") || { echo "f$n: prep failed"; fail=$((fail+1)); continue; }
    if [ $first = 1 ]; then unset NOBUILD; else export NOBUILD=1; fi
    first=0
    wsl -e bash $WREPO/sim/run_video.sh $WR/work/hex/$GAME.f$n "$tiles" 2 $WR/work/sim/$GAME.f$n > "$R/work/sim/$GAME.f$n.log" 2>&1 \
        || { echo "f$n: bench failed (see work/sim/$GAME.f$n.log)"; fail=$((fail+1)); continue; }
    res=$($PY "$RW/tools/cmpimg.py" "$BASEW/work/sim/$GAME.f$n.f002.ppm" "$BASEW/work/mame/snap/$GAME.f$n.png" --diff "$BASEW/work/sim/$GAME.f$n.diff.png")
    ovr=$(grep -o "overruns.*spr [0-9]*" "$R/work/sim/$GAME.f$n.log" | tail -1)
    echo "f$n: $res   [$ovr]"
    case "$res" in "0 of"*) ;; *) fail=$((fail+1)) ;; esac
done
exit $fail
