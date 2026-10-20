#!/usr/bin/env bash
# Build the CSP Wine prefix from scratch, reproducibly.
#
#   ./setup.sh                 # all steps
#   ./setup.sh wine prefix     # only some steps (see STEPS below)
#
# Steps are idempotent; re-running skips what is already done.
# Downloads land in ./cache (gitignored). Put the CSP installer
# (CSP_*w_setup.exe) in ./csp-wine/ or ~/Downloads, or pass CSP_INSTALLER=path.
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/env.sh"
cd "$CSP_ROOT"

STEPS=(wine winetricks prefix settings webview2 csp)

log() { printf '\e[1;34m==> %s\e[0m\n' "$*"; }
die() { printf '\e[1;31m!! %s\e[0m\n' "$*" >&2; exit 1; }

fetch() { # url dest [sha256]
  local url=$1 dest=$2 sum=${3:-}
  if [[ ! -s "$dest" ]]; then
    log "Downloading $(basename "$dest")"
    mkdir -p "$(dirname "$dest")"
    curl -fL --retry 3 -o "$dest.part" "$url"
    mv "$dest.part" "$dest"
  fi
  if [[ -n "$sum" ]]; then
    echo "$sum  $dest" | sha256sum -c --quiet - || die "checksum mismatch: $dest"
  fi
}

step_wine() {
  if [[ -x "$CSP_WINE/bin/wine" ]] && "$CSP_WINE/bin/wine" --version | grep -q "$WINE_VERSION"; then
    return
  fi
  fetch "$WINE_URL" "$CSP_CACHE/$WINE_TARBALL" "$WINE_SHA256"
  log "Unpacking Wine $WINE_VERSION ($WINE_FLAVOR)"
  rm -rf "$CSP_WINE"; mkdir -p "$CSP_WINE"
  tar -xf "$CSP_CACHE/$WINE_TARBALL" -C "$CSP_WINE" --strip-components=1
  "$WINE" --version
}

step_winetricks() {
  fetch "$WINETRICKS_URL" "$CSP_CACHE/winetricks" "$WINETRICKS_SHA256"
  chmod +x "$CSP_CACHE/winetricks"
}

winetricks() { "$CSP_CACHE/winetricks" --unattended "$@"; }

step_prefix() {
  [[ -f "$WINEPREFIX/system.reg" ]] && return
  log "Creating prefix $WINEPREFIX"
  # No Mono / Gecko: CSP doesn't use them (WebView2 replaces Gecko).
  WINEDLLOVERRIDES="$WINEDLLOVERRIDES;mscoree,mshtml=" "$WINE" wineboot -i
  "$WINESERVER" -w
}

step_settings() {
  log "Applying prefix settings"
  "$WINE" reg import "$CSP_ROOT/config/prefix.reg"
  "$WINESERVER" -w
}

step_webview2() {
  source "$CSP_ROOT/scripts/webview2.sh"
  install_webview2
}

find_csp_installer() {
  if [[ -n "${CSP_INSTALLER:-}" ]]; then echo "$CSP_INSTALLER"; return; fi
  ls -1t "$CSP_ROOT"/csp-wine/CSP_*w_setup.exe "$CSP_ROOT"/installers/CSP_*w_setup.exe \
    "$HOME"/Downloads/CSP_*w_setup.exe 2>/dev/null | head -1
}

step_csp() {
  if [[ -f "$WINEPREFIX/$CSP_EXE_REL" ]]; then return; fi
  local inst; inst=$(find_csp_installer)
  [[ -n "$inst" ]] || die "CSP installer not found; download CSP_xxxw_setup.exe from clipstudio.net into ./csp-wine/"
  log "Installing CSP from $inst"
  local iss="$CSP_ROOT/config/csp-setup.iss"
  if [[ -f "$iss" && -z "${CSP_INTERACTIVE:-}" ]]; then
    # Silent InstallShield install using the recorded response file.
    "$WINE" "$inst" /s /f1"$(winepath -w "$iss")" /f2"$(winepath -w "$CSP_CACHE/csp-setup.log")"
  else
    "$WINE" "$inst"
  fi
  "$WINESERVER" -w
  [[ -f "$WINEPREFIX/$CSP_EXE_REL" ]] || die "CSP did not install (expected $CSP_EXE_REL)"
}

steps=("$@"); [[ ${#steps[@]} -eq 0 ]] && steps=("${STEPS[@]}")
for s in "${steps[@]}"; do
  declare -F "step_$s" >/dev/null || die "unknown step: $s (have: ${STEPS[*]})"
  "step_$s"
done
log "Done."
