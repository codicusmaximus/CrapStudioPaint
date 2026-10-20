# CrapStudioPaint — Clip Studio Paint on Linux (Wine)

A self-contained, portable Wine setup for **Clip Studio Paint 5.x** on Linux.
Nothing here touches your system Wine, Steam/Proton or Bottles: the Wine build,
the prefix and all helpers live in this folder, so the folder (or the archive
made by `package.sh`) can be moved to another machine and run there.

## Quick start

```bash
# 1. put the CSP installer (CSP_xxxw_setup.exe) in ./csp-wine/ or ~/Downloads
./setup.sh          # builds wine/ + prefix/ and installs CSP silently
./csp               # run Clip Studio Paint
```

`csp` works from any path (symlink it into `~/bin`). Other modes:

| command | what |
|---|---|
| `./csp --gamescope` | run inside a nested gamescope window |
| `./csp --studio` | run the CLIP STUDIO launcher instead of Paint |
| `./csp --wine winecfg` | run any Wine tool in the prefix |
| `./csp --kill` | stop everything in the prefix |

## Portable archive

```bash
./package.sh        # -> dist/csp-wine-YYYYMMDD.tar.zst
```

On the other machine: `tar -xf csp-wine-*.tar.zst && ./csp-wine/csp`.
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
| `env.sh` | yes | pinned versions + environment (sourced by every script) |
| `setup.sh` | yes | reproducible build, steps: `wine prefix settings csp verify` |
| `csp` | yes | launcher |
| `package.sh` | yes | portable archive builder |
| `config/prefix.reg` | yes | prefix registry settings |
| `config/csp-setup.iss` | yes | recorded InstallShield answers for the silent CSP install |
| `config/package-exclude.txt` | yes | what the archive leaves out |
| `tools/gs-*.sh`, `tools/gs-input.py` | yes | gamescope test harness (screenshots + synthetic clicks) |
| `wine/`, `prefix/`, `cache/`, `dist/` | no (gitignored) | big binaries |

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
- **WebView2 `--no-sandbox`**: Chromium's sandbox doesn't work under Wine;
  without it the WebView2 browser never starts a renderer/GPU process. The
  launcher sets `WEBVIEW2_ADDITIONAL_BROWSER_ARGUMENTS=--no-sandbox`.
- **Blank (white) sign-in / start panel** — *work in progress*: CSP hosts
  WebView2 through DirectComposition. Wine's builtin `dcomp.dll` is only
  partially implemented (`IDCompositionVisual2` is a stub), so WebView2
  controller creation fails and CSP closes the WebView, leaving the panel blank.
  The fix is a small replacement `dcomp.dll` shim (approach pioneered by the
  CSPenguin-Installer project).

## Testing harness (gamescope)

```bash
tools/gs-run.sh                       # start a nested 1600x900 gamescope
tools/gs-exec.sh 'C:\path\to\app.exe' # run a program in it (Wine virtual desktop)
tools/gs-shot.sh out.png              # screenshot
cache/venv/bin/python3 tools/gs-input.py click X Y   # synthetic input (python-xlib)
```

The Wine virtual desktop is sized to the gamescope output so screenshot pixels
equal X coordinates.
