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

# Cross compiler for the dcomp.dll shim (built from source at setup time)
LLVM_MINGW_VERSION="20260922"
LLVM_MINGW_TARBALL="llvm-mingw-${LLVM_MINGW_VERSION}-ucrt-ubuntu-22.04-x86_64.tar.xz"
LLVM_MINGW_URL="https://github.com/mstorsjo/llvm-mingw/releases/download/${LLVM_MINGW_VERSION}/${LLVM_MINGW_TARBALL}"
LLVM_MINGW_SHA256="bb7bb7654b33d5aa8712acb837c963b2e0c56352560c76105270a3268c665c21"

# DirectComposition shim source (CSPenguin-Installer, pinned commit) + our patch
DCOMP_COMMIT="868d022adfdc3740449241f4721debbf4b1b1426"
DCOMP_BASE_URL="https://raw.githubusercontent.com/parka6060/CSPenguin-Installer/${DCOMP_COMMIT}/patches/dcomp"
DCOMP_CPP_SHA256="e516fd33b7da2452a90b96a9bbb42920564afd1a91d4ba629cad34acfb0cc83a"
DCOMP_DEF_SHA256="319c1a01d6ca059c5127f62a4a6250ccead3af8ae1f4b335b7c2b1f7fe8b4e92"

# DXVK (D3D11 -> Vulkan); the shim + WebView2 need it
DXVK_VERSION="3.1.1"
DXVK_URL="https://github.com/doitsujin/dxvk/releases/download/v${DXVK_VERSION}/dxvk-${DXVK_VERSION}.tar.gz"
DXVK_SHA256="40565b4a724aadc4433fa4e010b4b23916d9b1f1baeee64e17186db94f54e608"

# Newer WebView2 runtime than the 115 bundled with CSP (Microsoft evergreen
# standalone installer; Microsoft updates this file, so it is not hash-pinned).
WEBVIEW2_URL="https://go.microsoft.com/fwlink/?linkid=2124701"
WEBVIEW2_MIN_MAJOR=130

# Chromium flags for the WebView2 panels under Wine
CSP_WEBVIEW2_ARGS="--no-sandbox --disable-gpu-compositing --disable-gpu-vsync --in-process-gpu"
