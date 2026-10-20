# Source this file: sets up the self-contained Wine + prefix for CSP.
# Works from any path; everything is relative to this file's directory.
CSP_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
export CSP_ROOT

# Pinned Wine build (Kron4ek portable wine-staging, WoW64 = no 32-bit host libs needed)
WINE_VERSION="11.19"
WINE_FLAVOR="staging-amd64-wow64"
WINE_TARBALL="wine-${WINE_VERSION}-${WINE_FLAVOR}.tar.xz"
WINE_URL="https://github.com/Kron4ek/Wine-Builds/releases/download/${WINE_VERSION}/${WINE_TARBALL}"
WINE_SHA256="c89f69cf22f6664e3791210fa3b40c6e9e6d2e27a9aaa466f5a26d9c56664a09"

WINETRICKS_VERSION="20260125"
WINETRICKS_URL="https://raw.githubusercontent.com/Winetricks/winetricks/${WINETRICKS_VERSION}/src/winetricks"
WINETRICKS_SHA256="431f82fc74000e6c864409f1d8fb495d696c03928808e3e8acffc45179312a7b"

export CSP_CACHE="${CSP_ROOT}/cache"
export CSP_WINE="${CSP_ROOT}/wine"
export WINEPREFIX="${CSP_PREFIX:-${CSP_ROOT}/prefix}"
export WINEARCH=win64
export WINE="${CSP_WINE}/bin/wine"
export WINESERVER="${CSP_WINE}/bin/wineserver"
export WINELOADER="${WINE}"
export WINEDLLPATH="${CSP_WINE}/lib/wine"
export PATH="${CSP_WINE}/bin:${PATH}"
# Keep Wine from creating Linux menu entries / file associations on the host
export WINEDLLOVERRIDES="${WINEDLLOVERRIDES:+${WINEDLLOVERRIDES};}winemenubuilder.exe=d"
export WINEDEBUG="${WINEDEBUG:--all}"

CSP_EXE_REL="drive_c/Program Files/CELSYS/CLIP STUDIO 1.5/CLIP STUDIO PAINT/CLIPStudioPaint.exe"
