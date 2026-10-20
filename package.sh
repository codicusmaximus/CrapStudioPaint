#!/usr/bin/env bash
# Build a portable archive: Wine build + prefix (with CSP installed) + scripts.
# License / sign-in / analytics data and caches are excluded, so the archive is
# safe to copy to other machines and each machine signs in on its own.
#
#   ./package.sh            # -> dist/csp-wine-<date>.tar.zst
#
# On the other machine:  tar -xf csp-wine-*.tar.zst && ./csp-wine/csp
set -euo pipefail
source "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")/env.sh"
cd "$CSP_ROOT"

[[ -f "$WINEPREFIX/$CSP_EXE_REL" ]] || { echo "run ./setup.sh first" >&2; exit 1; }
"$WINESERVER" -k 2>/dev/null || true
"$WINESERVER" -w 2>/dev/null || true

name="csp-wine"
out="$CSP_ROOT/dist/${name}-$(date +%Y%m%d).tar.zst"
mkdir -p "$CSP_ROOT/dist"

# Turn the exclude list (paths relative to the prefix profile) into tar args.
excludes=()
while IFS= read -r line; do
  line="${line%%#*}"; line="${line%"${line##*[![:space:]]}"}"
  [[ -z "$line" ]] && continue
  line="${line//@USER@/$USER}"
  excludes+=("--exclude=prefix/${line}")
done < "$CSP_ROOT/config/package-exclude.txt"

files=(env.sh csp setup.sh package.sh README.md scripts config tools patches lib wine prefix)
echo "Packaging -> $out"
tar --transform "s#^#${name}/#" "${excludes[@]}" \
    --exclude="tools/__pycache__" \
    -C "$CSP_ROOT" -cf - "${files[@]}" \
  | zstd -T0 -10 -q -o "$out" -f
ls -lh "$out"
