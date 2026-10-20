# Builds everything the CSP Wine setup needs, so the host only needs
# docker/podman (plus a desktop to run CSP on). Driven by wine-csp-wrapper.sh,
# which passes the pinned versions/checksums from env.sh as build args.
#
# Output (/out, copied to ./build by the wrapper):
#   wine/                      portable Wine (Kron4ek wine-staging, WoW64)
#   dxvk/x64, dxvk/x32         DXVK DLLs
#   winetricks
#   MicrosoftEdgeWebView2RuntimeInstallerX64.exe
#   dcomp.dll                  DirectComposition shim (CSPenguin source + patches/dcomp-shim.patch)
#   wintab-xi1-fix.so          LD_PRELOAD pen pressure fix (patches/wintab-xi1-fix.c)
#   BUILDINFO

ARG WINE_URL
ARG WINE_SHA256
ARG DXVK_URL
ARG DXVK_SHA256
ARG WINETRICKS_URL
ARG WINETRICKS_SHA256
ARG WEBVIEW2_URL
ARG LLVM_MINGW_URL
ARG LLVM_MINGW_SHA256
ARG DCOMP_BASE_URL
ARG DCOMP_CPP_SHA256
ARG DCOMP_DEF_SHA256

# ---- downloads (checksummed) ------------------------------------------------
FROM docker.io/library/debian:bookworm-slim AS fetch
RUN apt-get update && apt-get install -y --no-install-recommends ca-certificates curl xz-utils \
    && rm -rf /var/lib/apt/lists/*
ARG WINE_URL
ARG WINE_SHA256
ARG DXVK_URL
ARG DXVK_SHA256
ARG WINETRICKS_URL
ARG WINETRICKS_SHA256
ARG WEBVIEW2_URL
WORKDIR /dl
RUN set -eux; mkdir -p /out/wine /out/dxvk; \
    curl -fsSL --retry 3 -o wine.tar.xz "$WINE_URL"; \
    echo "$WINE_SHA256  wine.tar.xz" | sha256sum -c -; \
    tar -xf wine.tar.xz -C /out/wine --strip-components=1; rm wine.tar.xz
RUN set -eux; \
    curl -fsSL --retry 3 -o dxvk.tar.gz "$DXVK_URL"; \
    echo "$DXVK_SHA256  dxvk.tar.gz" | sha256sum -c -; \
    tar -xzf dxvk.tar.gz -C /out/dxvk --strip-components=1; rm dxvk.tar.gz
RUN set -eux; \
    curl -fsSL --retry 3 -o /out/winetricks "$WINETRICKS_URL"; \
    echo "$WINETRICKS_SHA256  /out/winetricks" | sha256sum -c -; chmod +x /out/winetricks
# Microsoft's evergreen WebView2 installer (changes over time; not hash-pinned)
RUN set -eux; \
    curl -fsSL --retry 3 -o /out/MicrosoftEdgeWebView2RuntimeInstallerX64.exe "$WEBVIEW2_URL"; \
    sha256sum /out/MicrosoftEdgeWebView2RuntimeInstallerX64.exe

# ---- dcomp.dll shim (llvm-mingw cross compiler) ----------------------------
FROM docker.io/library/ubuntu:22.04 AS dcomp
RUN apt-get update && apt-get install -y --no-install-recommends ca-certificates curl xz-utils patch \
    && rm -rf /var/lib/apt/lists/*
ARG LLVM_MINGW_URL
ARG LLVM_MINGW_SHA256
ARG DCOMP_BASE_URL
ARG DCOMP_CPP_SHA256
ARG DCOMP_DEF_SHA256
RUN set -eux; mkdir -p /opt/llvm-mingw; \
    curl -fsSL --retry 3 -o /tmp/llvm-mingw.tar.xz "$LLVM_MINGW_URL"; \
    echo "$LLVM_MINGW_SHA256  /tmp/llvm-mingw.tar.xz" | sha256sum -c -; \
    tar -xf /tmp/llvm-mingw.tar.xz -C /opt/llvm-mingw --strip-components=1; rm /tmp/llvm-mingw.tar.xz
WORKDIR /src
COPY patches/dcomp-shim.patch /src/
RUN set -eux; \
    curl -fsSL --retry 3 -o dcomp_csp.cpp "$DCOMP_BASE_URL/dcomp_csp.cpp"; \
    curl -fsSL --retry 3 -o dcomp.def "$DCOMP_BASE_URL/dcomp.def"; \
    echo "$DCOMP_CPP_SHA256  dcomp_csp.cpp" | sha256sum -c -; \
    echo "$DCOMP_DEF_SHA256  dcomp.def" | sha256sum -c -; \
    patch -p1 < dcomp-shim.patch; \
    mkdir -p /out; \
    /opt/llvm-mingw/bin/x86_64-w64-mingw32-g++ -D_WIN32_WINNT=0x0A00 -DWINVER=0x0A00 \
        -shared -static -O2 -std=c++17 -o /out/dcomp.dll dcomp_csp.cpp dcomp.def \
        -lole32 -lgdi32 -ldxgi -ld3d11 -luuid

# ---- pen pressure fix (symbols pinned to old glibc versions in the source) --
FROM docker.io/library/debian:bookworm-slim AS tabletfix
RUN apt-get update && apt-get install -y --no-install-recommends gcc libc6-dev \
    && rm -rf /var/lib/apt/lists/*
COPY patches/wintab-xi1-fix.c /src/
RUN mkdir -p /out && gcc -shared -fPIC -O2 -Wall -Wno-nonnull-compare -fno-builtin-memcpy \
        -o /out/wintab-xi1-fix.so /src/wintab-xi1-fix.c -ldl -lpthread \
    && objdump -T /out/wintab-xi1-fix.so | grep -o 'GLIBC_[0-9.]*' | sort -uV

# ---- collect ----------------------------------------------------------------
FROM scratch
COPY --from=fetch /out/ /out/
COPY --from=dcomp /out/ /out/
COPY --from=tabletfix /out/ /out/
ARG WINE_URL
ARG DXVK_URL
ARG DCOMP_BASE_URL
COPY docker/BUILDINFO.in /out/BUILDINFO
CMD ["/none"]
