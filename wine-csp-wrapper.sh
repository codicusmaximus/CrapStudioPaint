#!/usr/bin/env bash
# One-stop wrapper: build the supporting pieces in a container, install your
# Clip Studio Paint into a self-contained Wine prefix, and run it.
#
#   ./wine-csp-wrapper.sh install /path/to/CSP_xxxw_setup.exe
#   ./wine-csp-wrapper.sh run [--gamescope] [--studio]
#
# Other commands:
#   build       (re)build ./build with docker or podman (install does this if needed)
#   studio      run the CLIP STUDIO launcher (sign in here the first time)
#   winecfg     open Wine's settings for the prefix
#   kill        stop everything running in the prefix
#   package     make a portable archive in ./dist (no account/license data)
#   status      show what is built/installed
#
# Host needs: docker or podman (only for `build`), an X11/Wayland desktop with
# Vulkan drivers to run CSP. No Wine, compilers or 32-bit libraries needed.
set -euo pipefail
self="$(readlink -f "${BASH_SOURCE[0]}")"
ROOT="$(dirname "$self")"
source "$ROOT/env.sh"
BUILD="$ROOT/build"
IMAGE="localhost/csp-wine-build:latest"

log() { printf '\e[1;34m==> %s\e[0m\n' "$*"; }
die() { printf '\e[1;31m!! %s\e[0m\n' "$*" >&2; exit 1; }

container_cli() {
  if [[ -n "${CONTAINER_CLI:-}" ]]; then echo "$CONTAINER_CLI"
  elif command -v docker >/dev/null; then echo docker
  elif command -v podman >/dev/null; then echo podman
  else die "docker or podman is required to build (install one, or set CONTAINER_CLI)"; fi
}

built() {
  [[ -x "$BUILD/wine/bin/wine" && -f "$BUILD/dcomp.dll" && -f "$BUILD/wintab-xi1-fix.so" \
     && -f "$BUILD/dxvk/x64/d3d11.dll" ]]
}

cmd_build() {
  local ct; ct=$(container_cli)
  log "Building supporting files with $ct (first run downloads ~400 MB)"
  "$ct" build -f "$ROOT/docker/Dockerfile" -t "$IMAGE" \
    --build-arg WINE_URL="$WINE_URL" --build-arg WINE_SHA256="$WINE_SHA256" \
    --build-arg DXVK_URL="$DXVK_URL" --build-arg DXVK_SHA256="$DXVK_SHA256" \
    --build-arg WINETRICKS_URL="$WINETRICKS_URL" --build-arg WINETRICKS_SHA256="$WINETRICKS_SHA256" \
    --build-arg WEBVIEW2_URL="$WEBVIEW2_URL" \
    --build-arg LLVM_MINGW_URL="$LLVM_MINGW_URL" --build-arg LLVM_MINGW_SHA256="$LLVM_MINGW_SHA256" \
    --build-arg DCOMP_BASE_URL="$DCOMP_BASE_URL" \
    --build-arg DCOMP_CPP_SHA256="$DCOMP_CPP_SHA256" --build-arg DCOMP_DEF_SHA256="$DCOMP_DEF_SHA256" \
    "$ROOT"
  log "Copying build output to $BUILD"
  local cid; cid=$("$ct" create "$IMAGE")
  rm -rf "$BUILD.new"; mkdir -p "$BUILD.new"
  if ! "$ct" cp "$cid:/out/." "$BUILD.new/"; then "$ct" rm "$cid" >/dev/null; die "copy failed"; fi
  "$ct" rm "$cid" >/dev/null
  rm -rf "$BUILD"; mv "$BUILD.new" "$BUILD"
  "$BUILD/wine/bin/wine" --version >/dev/null 2>&1 || log "note: wine --version failed on this host (missing libraries?)"
  log "Build done: $(ls "$BUILD" | tr '\n' ' ')"
}

cmd_install() {
  local inst="${1:-}"
  [[ -n "$inst" ]] || die "usage: $0 install /path/to/CSP_xxxw_setup.exe"
  [[ -f "$inst" ]] || die "installer not found: $inst"
  inst="$(readlink -f "$inst")"
  built || cmd_build
  if [[ -f "$WINEPREFIX/$CSP_EXE_REL" ]]; then
    log "CSP is already installed in $WINEPREFIX; running the installer again (update/repair)"
    CSP_REINSTALL=1 CSP_INSTALLER="$inst" "$ROOT/setup.sh"
  else
    CSP_INSTALLER="$inst" "$ROOT/setup.sh"
  fi
  cat <<EOF

$(printf '\e[1;32m')CSP is installed.$(printf '\e[0m')
  First time: sign in once via   $0 studio   (Log in in the left sidebar),
  then in CSP set File > Preferences > Tablet to "Wintab" for pen pressure.
  Run CSP:                       $0 run
EOF
}

cmd_status() {
  echo "repo:    $ROOT"
  if built; then echo "build:   ok ($("$BUILD/wine/bin/wine" --version 2>/dev/null || echo wine))"; else echo "build:   missing (run: $0 build)"; fi
  if [[ -f "$WINEPREFIX/$CSP_EXE_REL" ]]; then echo "CSP:     installed in $WINEPREFIX"; else echo "CSP:     not installed (run: $0 install <installer.exe>)"; fi
}

cmd="${1:-help}"; shift || true
case "$cmd" in
  build)   cmd_build ;;
  install) cmd_install "$@" ;;
  run)     exec "$ROOT/csp" "$@" ;;
  studio)  exec "$ROOT/csp" --studio "$@" ;;
  winecfg) exec "$ROOT/csp" --wine winecfg ;;
  kill)    exec "$ROOT/csp" --kill ;;
  package) exec "$ROOT/package.sh" ;;
  status)  cmd_status ;;
  help|-h|--help) sed -n '2,18p' "$self" | sed 's/^# \{0,1\}//' ;;
  *) die "unknown command: $cmd (try: $0 help)" ;;
esac
