#!/usr/bin/env bash
# Run a Windows program inside the gamescope started by gs-run.sh, in a Wine
# virtual desktop the size of the gamescope output (so screenshot pixels == X pixels).
# Usage: tools/gs-exec.sh program.exe [args]     (paths: Windows or /unix paths via 'start /unix')
here="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$here/env.sh"
set -a; source "${XDG_RUNTIME_DIR:-/tmp}/csp-gamescope.env"; set +a
exec wine explorer "/desktop=gs,${GS_SIZE}" "$@"
