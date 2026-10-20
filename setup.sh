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

STEPS=(wine prefix settings csp postinstall verify)

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

# Optional helper (not needed by the default steps): ./setup.sh winetricks
step_winetricks() {
  fetch "$WINETRICKS_URL" "$CSP_CACHE/winetricks" "$WINETRICKS_SHA256"
  chmod +x "$CSP_CACHE/winetricks"
  echo "winetricks: $CSP_CACHE/winetricks (source env.sh first)"
}

step_prefix() {
  [[ -f "$WINEPREFIX/system.reg" ]] && return
  log "Creating prefix $WINEPREFIX"
  # No Mono / Gecko: CSP doesn't use them (WebView2 replaces Gecko).
  WINEDLLOVERRIDES="$WINEDLLOVERRIDES;mscoree,mshtml=" "$WINE" wineboot -i
  "$WINESERVER" -w
}

step_settings() {
  log "Applying prefix settings"
  "$WINE" reg import "$("$WINE" winepath -w "$CSP_ROOT/config/prefix.reg")"
  "$WINESERVER" -w
}

step_postinstall() {
  log "Post-install tweaks"
  # Keep the bundled WebView2 pinned and stop background updater services
  # (they also keep wineserver alive forever).
  "$WINE" reg import "$("$WINE" winepath -w "$CSP_ROOT/config/postinstall.reg")"
  "$WINESERVER" -k || true
}

step_verify() {
  # CSP's installer bundles and installs the Edge WebView2 runtime itself.
  local wv
  wv=$("$WINE" reg query 'HKLM\SOFTWARE\WOW6432Node\Microsoft\EdgeUpdate\Clients\{F3017226-FE2A-4295-8BDF-00C3A9A7E4C5}' /v pv 2>/dev/null | awk '/pv/{print $3}' | tr -d '\r')
  [[ -n "$wv" ]] || die "WebView2 runtime missing (CSP installer should have installed it)"
  log "WebView2 runtime $wv"
  [[ -f "$WINEPREFIX/$CSP_EXE_REL" ]] || die "CSP missing"
  log "CSP installed: $CSP_EXE_REL"
  source "$CSP_ROOT/scripts/relocate.sh"; relocate_prefix_user
}

find_csp_installer() {
  if [[ -n "${CSP_INSTALLER:-}" ]]; then echo "$CSP_INSTALLER"; return; fi
  # First directory that has one wins; within it, the highest version.
  local d f
  for d in "$CSP_ROOT/csp-wine" "$CSP_ROOT/installers" "$HOME/Downloads"; do
    f=$(compgen -G "$d/CSP_*w_setup.exe" | sort -V | tail -1 || true)
    [[ -n "$f" ]] && { echo "$f"; return; }
  done
  return 0
}

step_csp() {
  if [[ -f "$WINEPREFIX/$CSP_EXE_REL" ]]; then return; fi
  local inst; inst=$(find_csp_installer)
  [[ -n "$inst" ]] || die "CSP installer not found; download CSP_xxxw_setup.exe from clipstudio.net into ./csp-wine/"
  log "Installing CSP from $inst"
  local iss="$CSP_ROOT/config/csp-setup.iss"
  if [[ -f "$iss" && -z "${CSP_INTERACTIVE:-}" ]]; then
    # Silent InstallShield install using the recorded response file.
    "$WINE" "$inst" /s /f1"$("$WINE" winepath -w "$iss")" /f2"$("$WINE" winepath -w "$CSP_CACHE/csp-setup.log")"
  else
    "$WINE" "$inst"
  fi
  # The installer leaves the Edge updater services running, so don't wait on wineserver.
  "$WINESERVER" -k || true
  [[ -f "$WINEPREFIX/$CSP_EXE_REL" ]] || die "CSP did not install (expected $CSP_EXE_REL)"
  step_postinstall
}

steps=("$@"); [[ ${#steps[@]} -eq 0 ]] && steps=("${STEPS[@]}")
for s in "${steps[@]}"; do
  declare -F "step_$s" >/dev/null || die "unknown step: $s (have: ${STEPS[*]})"
  "step_$s"
done
log "Done."
