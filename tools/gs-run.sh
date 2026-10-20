#!/usr/bin/env bash
# Start a nested gamescope window that stays open; run programs in it with gs-exec.sh.
# Usage: tools/gs-run.sh [-W 1600 -H 900]
W=1600; H=900
while [[ $# -gt 0 ]]; do
  case "$1" in -W) W=$2; shift 2;; -H) H=$2; shift 2;; *) break;; esac
done
info="${XDG_RUNTIME_DIR:-/tmp}/csp-gamescope.env"
rm -f "$info"
gamescope -W "$W" -H "$H" -w "$W" -h "$H" --backend sdl -- \
  bash -c 'printf "DISPLAY=%s\nGAMESCOPE_WAYLAND_DISPLAY=%s\nGS_SIZE=%sx%s\n" "$DISPLAY" "$GAMESCOPE_WAYLAND_DISPLAY" "$1" "$2" > "$0"; exec sleep infinity' "$info" "$W" "$H" \
  > "${XDG_RUNTIME_DIR:-/tmp}/csp-gamescope.log" 2>&1 &
echo "gamescope pid $!"
for _ in $(seq 40); do [[ -s "$info" ]] && { cat "$info"; exit 0; }; sleep 0.25; done
echo "gamescope did not start" >&2; exit 1
