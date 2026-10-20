# Draft: Wine bug report — wintab loses stylus/eraser events (no pressure) on Xwayland

To file: create an account at https://bugs.winehq.org, choose **Enter a new
bug** → product **Wine**, and copy the fields below. First, search for an
existing report (e.g. "wintab XSelectExtensionEvent", "tablet pressure
Xwayland"). Bug 59224 ("Pen/Eraser pressure not working in any application on
2-in-1 laptops") may be the same issue; if so, add this analysis there as a
comment instead of filing a duplicate.

Attach `patches/wine-wintab-select-all-devices.patch`. Patches are normally
sent as a merge request on https://gitlab.winehq.org/wine/wine, with a link
from the bug.

---

**Summary:** winex11 wintab: XSelectExtensionEvent called per device overwrites previous selections; stylus/eraser events lost (no pen pressure, eraser acts as tip) on Xwayland

**Component:** wintab32 (code in dlls/winex11.drv/wintab.c)

**Version:** 11.19 (wine-staging 11.19, Kron4ek build); the code is the same in wine-11.19 upstream

**Platform:** x86-64, Linux

**Severity:** normal

**Keywords:** (none, or `source` if the analysis is accepted)

**Description:**

On a Wayland desktop (GNOME/mutter, Xwayland 24.1, Fedora 44), Wintab apps
under Wine get the pen with no pressure, and the eraser end behaves like the
tip. Seen with Clip Studio Paint 5.1.5 in Wintab mode, Wacom Intuos5 touch M
over the wireless kit. Pressure works in native apps. A plain XInput 1 client
on the same desktop receives the stylus with full pressure (0–65535) and
button events.

Xwayland exposes the tablet as three XI1 devices:
`xwayland-tablet stylus:NN`, `xwayland-tablet eraser:NN` and
`xwayland-tablet cursor:NN`. Wine detects all three
(`tablet_attach_queue Opening cursor 0 id 12` / `1 id 10` / `2 id 11`).

**Cause:** in `dlls/winex11.drv/wintab.c`, `tablet_attach_queue()` loops over
the cursors and, for each device, builds `event_list` with only that device's
classes. It then calls
`pXSelectExtensionEvent(data->display, win, event_list, event_number)` inside
the loop. XSelectExtensionEvent replaces the client's previous XInput 1
selection on that window, so after the loop only the last device is selected.
Querying the window with XGetSelectedExtensionEvents shows only the last
device (here id 12, the puck). The stylus (10) and eraser (11) are not
selected, so Wine receives no stylus motion/button events. A few stale hover
events with pressure 0 get through, and the app falls back to mouse input.

Proof: a separate XI1 client that selects stylus events on the *same* Wine
window receives 824 motion events with pressure up to 65535 in one test, while
Wine (`WINEDEBUG=+wintab32`) logs 5 `motion_event`s, all with
`pkNormalPressure: 0`.

**Fix:** collect the event classes of all devices into one list and call
XSelectExtensionEvent once after the loop (patch attached: the event list
grows to `CURSORMAX * 7` and the call moves out of the loop).

**Possibly related, second issue:** on Xwayland, the stylus/eraser selections
also disappeared again after the pen had been used for a while, while the
unused puck's stayed. This is consistent with Xwayland re-creating or
re-enabling the tool devices, and the X server dropping per-device selections
when that happens. We worked around it out-of-tree by re-applying the merged
selection periodically. A proper fix could re-select when the device
hierarchy changes (XI1 `DevicePresenceNotify` / XI2 `XI_HierarchyChanged`).
This is probably also behind the widespread "pressure only works on the second
launch" reports.

**Workaround (until fixed):** an LD_PRELOAD shim that merges and re-applies
the selections:
https://github.com/codicusmaximus/CrapStudioPaint/blob/main/patches/wintab-xi1-fix.c
(adjust the link if the repo isn't public).

**Steps to reproduce:**
1. Wayland session (GNOME), Wacom tablet working in native apps.
2. Run a Wintab app (e.g. Clip Studio Paint set to Wintab, or Wacom's
   wtcapt.exe) with `WINEDEBUG=+wintab32`.
3. Draw with the pen: the log shows almost no `motion_event`s and pressure
   stays 0; the eraser end draws like the tip.
4. `XGetSelectedExtensionEvents` on the app window (e.g. `xi1-selected.py`
   from the repo above) lists only one tablet device.
