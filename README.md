# CrapStudioPaint — Clip Studio Paint on Linux (Wine)

A self-contained, portable Wine setup for **Clip Studio Paint 5.x** on Linux.
Nothing here touches your system Wine, Steam/Proton or Bottles: the Wine build,
the prefix and all helpers live in this folder, so the folder (or the archive
made by `package.sh`) can be moved to another machine and run there.

## Quick start

Needs: **docker or podman** (to build), a Linux desktop (X11 or Wayland) with
working Vulkan drivers, and the CSP installer from clipstudio.net.

```bash
./wine-csp-wrapper.sh install ~/Downloads/CSP_515w_setup.exe   # build + prefix + install
./wine-csp-wrapper.sh studio    # first time only: "Log in" in the left sidebar
./wine-csp-wrapper.sh run       # run Clip Studio Paint
```

`install` builds everything in a container the first time (`./build`:
portable Wine, DXVK, the WebView2 runtime, the dcomp shim and the pen pressure
fix — see *What was needed*), creates the Wine prefix in `./prefix`, and runs
your CSP installer: silently with recorded answers when they fit, otherwise the
normal installer window opens for you to click through (keep the default
folder). Running it again with a newer installer updates CSP.

Other wrapper commands: `build`, `run --gamescope`, `studio`, `winecfg`,
`kill`, `package`, `status`, `help`. Without docker/podman, `./setup.sh` does
the same steps on the host (needs curl, gcc, patch).

**First run notes**
- CSP Paint's own sign-in / "Try for free" panel stays blank under Wine (see
  *Known limitation*), so sign in once in CLIP STUDIO (`studio` → **Log in**),
  then start Paint.
- Pen pressure: in CSP set *File → Preferences → Tablet* to **Wintab**, then
  restart CSP. Plug the tablet in before starting CSP.
- If Paint ever ignores all clicks, a modal popup (e.g. "What's new") is hidden
  behind the main window — Alt+Tab to it and close it.

`csp` works from any path (symlink it into `~/bin`). Other modes:

| command | what |
|---|---|
| `./csp --gamescope` | run inside a nested gamescope window (Wine virtual desktop with a taskbar; mainly for testing/screenshots) |
| `./csp --studio` | run the CLIP STUDIO launcher instead of Paint |
| `./csp --wine winecfg` | run any Wine tool in the prefix |
| `./csp --kill` | stop everything in the prefix |

## Portable archive

```bash
./wine-csp-wrapper.sh package      # -> dist/csp-wine-YYYYMMDD.tar.zst (~1.8 GB)
```

On the other machine (no docker/compilers needed, just a desktop with Vulkan):

```bash
tar -xf csp-wine-*.tar.zst
./csp-wine/wine-csp-wrapper.sh studio   # sign in once (Log in in the sidebar)
./csp-wine/wine-csp-wrapper.sh run
```
The archive contains Wine + the prefix with CSP installed, but **not** CELSYS
account/license/sign-in data, the WebView2 browser profile, caches or temp
files (see `config/package-exclude.txt`), so each machine signs in on its own.
If the other machine's username differs, `csp` renames the Windows profile
(`C:\users\<name>`) and rewrites the registry paths on first run
(`scripts/relocate.sh`). Host requirements: x86-64 Linux with
X11/Xwayland and working Vulkan/OpenGL drivers; no 32-bit libraries are needed
(the Wine build is WoW64).

## Layout

| path | committed? | what |
|---|---|---|
| `wine-csp-wrapper.sh` | yes | main entry point: build / install / run |
| `docker/Dockerfile` | yes | container build of all supporting pieces |
| `env.sh` | yes | pinned versions + environment (sourced by every script) |
| `setup.sh` | yes | reproducible build, steps: `wine prefix settings csp postinstall dxvk webview2 dcomp verify` |
| `csp` | yes | launcher |
| `package.sh` | yes | portable archive builder |
| `config/prefix.reg` | yes | prefix registry settings |
| `config/csp-setup.iss` | yes | recorded InstallShield answers for the silent CSP install |
| `config/package-exclude.txt` | yes | what the archive leaves out |
| `config/postinstall.reg` | yes | disables Edge updater services, crash dialogs |
| `patches/dcomp-shim.patch` | yes | our fixes to the dcomp shim |
| `patches/wintab-xi1-fix.c` | yes | LD_PRELOAD fix for pen pressure/eraser |
| `tools/xi-raw.py`, `tools/xi1-*.py` | yes | tablet event diagnostics |
| `tools/gs-*.sh`, `tools/gs-input.py` | yes | gamescope test harness (screenshots + synthetic clicks) |
| `build/`, `wine/`, `prefix/`, `lib/`, `cache/`, `dist/` | no (gitignored) | big/built binaries |

## What was needed, and why

- **Wine**: Kron4ek's portable `wine-11.19-staging-amd64-wow64` build, pinned by
  version + SHA-256 in `env.sh`. WoW64 means the 32-bit CSP installer runs
  without 32-bit host libraries, which keeps the folder portable.
- **No Mono / Gecko**: CSP uses neither (WebView2 replaces Gecko).
- **Windows 10** reported to apps (CSP 4/5 require it).
- **winemenubuilder disabled** so Wine doesn't litter the host with menu entries
  and file associations.
- **CSP install**: InstallShield; `config/csp-setup.iss` was recorded with
  `/r` and replays with `/s`. The CSP installer **bundles WebView2 115** and
  installs it itself, so no separate WebView2 download is needed.
- **WebView2 flags** (`CSP_WEBVIEW2_ARGS` in `env.sh`, exported by `csp` as
  `WEBVIEW2_ADDITIONAL_BROWSER_ARGUMENTS`): `--no-sandbox` (Chromium's sandbox
  doesn't work under Wine; without it there is no renderer process),
  `--in-process-gpu --disable-gpu-compositing --disable-gpu-vsync`.
- **WebView2 155** (`setup.sh webview2`): CSP bundles WebView2 115; a current
  runtime is installed over it. The Edge updater services are then disabled
  (`config/postinstall.reg`) so it stays put and wineserver can exit.
- **DXVK 3.1.1** (`setup.sh dxvk`): D3D11 on Vulkan; the dcomp shim and
  WebView2's GPU path are built around DXVK's behaviour.
- **dcomp.dll shim** (`setup.sh dcomp`) — the actual *white/blank panel* fix.
  CSP hosts WebView2 through DirectComposition; Wine's builtin `dcomp.dll` is
  only partly implemented (e.g. `IDCompositionVisual2` is a stub), so WebView2
  panels never show. The shim (from the CSPenguin-Installer project, fetched at a
  pinned commit and compiled locally with a pinned llvm-mingw) fakes
  DirectComposition and copies each WebView2 frame into the window with GDI.
  `patches/dcomp-shim.patch` is our change on top of it:
  - support the Win8 `IDCompositionDevice` (v1) interface and
    `DCompositionCreateDevice2(NULL, …)` — WebView2 requests both;
  - re-blit on swapchain `Present()`, not only on `Commit()` — without it
    pages paint once and then stay blank/grey.
- **Pen pressure fix** (full write-up: `TABLET-FIX.md`) (`setup.sh tabletfix` → `lib/wintab-xi1-fix.so`,
  loaded by `csp` via `LD_PRELOAD`; source `patches/wintab-xi1-fix.c`).
  Under Xwayland, Wine's wintab got the pen with no pressure and the eraser
  acted like the tip. Diagnosed with `tools/xi-raw.py`, `tools/xi1-test.py`
  and `tools/xi1-selected.py`: the desktop delivers full pressure, but
  winex11 calls `XSelectExtensionEvent` once per tablet device on the same
  window — each call replaces the previous selection, so only the last device
  (the puck) stays subscribed — and Xwayland drops selections whenever it
  re-creates the stylus/eraser devices. The shim merges the selections and
  re-applies them twice a second from Wine's event loop (it also lets tablet
  events through Wine's input-only message waits). In CSP set
  *File → Preferences → Tablet* to **Wintab** (TabletPC/Windows Ink doesn't
  work under Wine). Building the shim needs `gcc` once; packaged archives
  include the built `.so`.
- **No per-app Windows version overrides.** Setting `CLIPStudioPaint.exe` to
  Windows 8.1 (as some guides do) makes CSP 5.1 never start WebView2 at all.

### Known limitation: sign-in panel inside CLIP STUDIO PAINT

The WebView2 panels in **CLIP STUDIO** (the launcher: store, news, *Log in*)
render and work. The panel on CSP Paint's own start screen ("Try for free" /
"Continue offline") still stays blank: Paint uses WebView2 "visual hosting",
which needs an undocumented DirectComposition interface
(`d14b6158-c3fa-4bce-9c1f-b61d8665eab0`) that no shim implements. Workaround:
sign in once in CLIP STUDIO (`./csp --studio` → *Log in*), then start Paint.

## Testing harness (gamescope)

```bash
tools/gs-run.sh                       # start a nested 1600x900 gamescope
tools/gs-exec.sh 'C:\path\to\app.exe' # run a program in it (Wine virtual desktop)
tools/gs-shot.sh out.png              # screenshot
cache/venv/bin/python3 tools/gs-input.py click X Y   # synthetic input (python-xlib)
```

The Wine virtual desktop is sized to the gamescope output so screenshot pixels
equal X coordinates.
