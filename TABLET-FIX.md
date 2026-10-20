# Pen pressure / eraser under Wine on Xwayland — what was wrong and the fix

**Symptom:** In Clip Studio Paint (Wintab mode) under Wine on a Wayland
desktop (GNOME, Xwayland), the pen draws but has **no pressure**, and the
**eraser end draws like the tip**. Pressure works fine in native Linux apps.

## How Wine gets pen data

Windows paint apps read tablets through *Wintab* (`wintab32.dll`). Wine
implements it in its X11 driver (`winex11.so`, `dlls/winex11.drv/wintab.c`)
on top of the old **XInput 1 (XI1)** X extension:

1. At startup it lists X input devices and picks the tablet ones. Under
   Xwayland they are `xwayland-tablet stylus`, `xwayland-tablet eraser` and
   `xwayland-tablet cursor` (the puck).
2. When the app opens a Wintab context, `tablet_attach_queue()` opens each
   device and calls `XSelectExtensionEvent(display, window, classes, n)` to
   subscribe the app's window to that device's motion/button events. Pressure
   is axis 2 of each XI1 motion event.

## What was actually broken (verified step by step)

| Test | Result |
|---|---|
| Raw XI2 events on the desktop (`tools/xi-raw.py`) | stylus delivers pressure up to ~49 000/65 535 → desktop is fine |
| Our own XI1 test window (`tools/xi1-test.py`) | ~10 000 events, full pressure → XI1 on Xwayland works |
| Our listener on **CSP's own window** (`xi1-test.py --window=…`) | 824 events with full pressure while Wine got **5** → events reach the window; Wine isn't subscribed |
| Which clients subscribe on CSP's window (`tools/xi1-selected.py`) | only device 12 (the puck) — **stylus and eraser not subscribed** |

Two problems stack up:

1. **Wine bug: each device's subscription overwrites the previous one.**
   `tablet_attach_queue()` calls `XSelectExtensionEvent()` *once per device*
   on the same window, each time with only that device's event classes. In
   XInput 1, that request **replaces** the client's selection on the window,
   so only the last device in the loop stays subscribed. Here that was the
   puck, which nobody uses, so the tip and eraser were never heard. The
   handful of events Wine did get were stray leftovers from before the last
   overwrite (hover only, so pressure was always 0).

2. **The desktop drops the subscriptions again.** Even after merging them,
   the stylus and eraser subscriptions disappeared as soon as the pen was
   used, while the unused puck's stayed. Our explanation: Xwayland re-creates
   or disables the tool devices on use, and the X server drops every client's
   selections for a device when that happens. That's inferred from what we
   observed, not confirmed in Xwayland's source. It also fits the community
   reports that pressure "works on the second launch" or "after starting the
   CLIP STUDIO launcher first".

## The fix (`patches/wintab-xi1-fix.c`)

A ~150-line `LD_PRELOAD` library, loaded by the `csp` launcher. It changes no
Wine files.

- **Merges subscriptions.** It wraps `XSelectExtensionEvent`. For calls coming
  from `winex11.so`, it remembers every event class requested per window and
  always subscribes the **union**: stylus + eraser + puck. winex11 looks the
  function up with `dlsym(libXi_handle, …)`, which bypasses normal preloading,
  so the library also intercepts that one `dlsym` lookup and returns the
  wrapper.
- **Keeps them alive.** About twice a second, from inside Wine's own event
  loop (`XCheckIfEvent` is called there constantly), it re-sends the merged
  subscription on the same X connection. Any reset by the desktop is undone
  within half a second.
- **Lets tablet events through input-only waits.** This was a side hypothesis:
  winex11 only dequeues XI1 events when the app waits for "sent messages", and
  CSP's drawing loop may wait for input only. The wrapper lets XI1 events
  through when the app asks for mouse input. We never proved this part was
  needed, but it's harmless.

Result: about 1 400 pen events in a short test, with pressure up to 65 535,
and eraser events (device 11) correctly marked as the inverted tip.

Build and use:

```bash
gcc -shared -fPIC -O2 -o wintab-xi1-fix.so wintab-xi1-fix.c -ldl -lpthread
LD_PRELOAD=$PWD/wintab-xi1-fix.so wine "C:\path\to\App.exe"
```

## Tips for someone else with broken pressure under Wine

1. **Rule out the basics.** Pressure works in a native app (Krita, GIMP)? The
   app's tablet mode is **Wintab**, not "TabletPC"/"Windows Ink" (Wine doesn't
   do Windows Ink pressure). The tablet was plugged in *before* the app
   started (Wine scans for tablets only at startup).
2. **Check that Wine sees a stylus:** run with `WINEDEBUG=+wintab32` and look
   for `Opening cursor … id …` lines. If you see
   `Did not find a valid stylus … Wintab is disabled`, it's a different bug
   (device naming), not this one.
3. **Check whether the stylus is subscribed** while the app is running and
   after you've used the pen:
   `DISPLAY=:0 python3 xi1-selected.py 0x<app window id>`. If only the
   `cursor`/puck device appears, or the stylus is missing, you have this bug.
4. **Fix:** preload `wintab-xi1-fix.so` as shown above (any Wine version with
   the X11 driver; works for any Wintab app, not just CSP). Restarting the app
   after first using the pen may work as a stopgap, which is where the
   "second launch" folklore comes from, but it isn't reliable.
5. The proper long-term fix belongs in Wine: collect all devices' event classes
   in `tablet_attach_queue()` and call `XSelectExtensionEvent()` once, and
   re-select on XI device-presence/hierarchy changes. Worth reporting upstream.
