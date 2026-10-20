#!/usr/bin/env bash
# Screenshot the running gamescope (started by gs-run.sh). Usage: tools/gs-shot.sh out.png
info="${XDG_RUNTIME_DIR:-/tmp}/csp-gamescope.env"
source "$info"
out="$(realpath -m "${1:-gamescope.png}")"
rm -f "$out"
GAMESCOPE_WAYLAND_DISPLAY=$GAMESCOPE_WAYLAND_DISPLAY gamescopectl screenshot "$out" >/dev/null
for _ in $(seq 20); do [[ -s "$out" ]] && { echo "$out"; exit 0; }; sleep 0.25; done
echo "screenshot failed" >&2; exit 1
