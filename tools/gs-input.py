#!/usr/bin/env python3
"""Send synthetic input (XTEST) to the gamescope X display started by gs-run.sh.

Usage:
  gs-input.py click X Y [button]     # coordinates in gamescope output pixels
  gs-input.py dclick X Y
  gs-input.py move X Y
  gs-input.py drag X1 Y1 X2 Y2
  gs-input.py type "text"
  gs-input.py key Return|Tab|Escape|ctrl+s|alt+F4 ...
  gs-input.py windows                # list top-level window names/geometry
Needs python-xlib (tools/ uses cache/venv, see README).
"""
import os
import sys
import time

from Xlib import X, XK, display
from Xlib.ext import xtest


def load_display():
    info = os.path.join(os.environ.get("XDG_RUNTIME_DIR", "/tmp"), "csp-gamescope.env")
    env = dict(l.strip().split("=", 1) for l in open(info) if "=" in l)
    return display.Display(env["DISPLAY"])


d = load_display()


def sync():
    d.sync()
    time.sleep(0.05)


def move(x, y):
    xtest.fake_input(d, X.MotionNotify, x=int(x), y=int(y))
    sync()


def click(x, y, button=1, count=1):
    move(x, y)
    for _ in range(count):
        xtest.fake_input(d, X.ButtonPress, int(button))
        sync()
        xtest.fake_input(d, X.ButtonRelease, int(button))
        sync()


def drag(x1, y1, x2, y2, steps=20):
    move(x1, y1)
    xtest.fake_input(d, X.ButtonPress, 1)
    sync()
    for i in range(1, steps + 1):
        move(x1 + (x2 - x1) * i / steps, y1 + (y2 - y1) * i / steps)
    xtest.fake_input(d, X.ButtonRelease, 1)
    sync()


ALIASES = {"ctrl": "Control_L", "alt": "Alt_L", "shift": "Shift_L", "super": "Super_L",
           "enter": "Return", "esc": "Escape"}


def keycode(name):
    name = ALIASES.get(name.lower(), name)
    sym = XK.string_to_keysym(name)
    if sym == 0 and len(name) == 1:
        sym = ord(name)
    code = d.keysym_to_keycode(sym)
    if not code:
        raise SystemExit(f"unknown key {name}")
    return code


def key(combo):
    codes = [keycode(k) for k in combo.split("+")]
    for c in codes:
        xtest.fake_input(d, X.KeyPress, c)
        sync()
    for c in reversed(codes):
        xtest.fake_input(d, X.KeyRelease, c)
        sync()


def type_text(text):
    for ch in text:
        sym = XK.string_to_keysym(ch) or ord(ch)
        code = d.keysym_to_keycode(sym)
        shift = d.keycode_to_keysym(code, 0) != sym
        if shift:
            xtest.fake_input(d, X.KeyPress, keycode("shift"))
        xtest.fake_input(d, X.KeyPress, code)
        xtest.fake_input(d, X.KeyRelease, code)
        if shift:
            xtest.fake_input(d, X.KeyRelease, keycode("shift"))
        sync()


def windows():
    root = d.screen().root
    for w in root.query_tree().children:
        try:
            attrs = w.get_attributes()
            if attrs.map_state != X.IsViewable:
                continue
            g = w.get_geometry()
            name = w.get_wm_name()
            print(f"0x{w.id:x} {g.x},{g.y} {g.width}x{g.height} {name!r}")
        except Exception:
            pass


cmd, args = sys.argv[1], sys.argv[2:]
if cmd == "click":
    click(*map(float, args[:2]), *(int(a) for a in args[2:3]))
elif cmd == "dclick":
    click(*map(float, args[:2]), count=2)
elif cmd == "move":
    move(*map(float, args))
elif cmd == "drag":
    drag(*map(float, args))
elif cmd == "type":
    type_text(args[0])
elif cmd == "key":
    for k in args:
        key(k)
elif cmd == "windows":
    windows()
else:
    raise SystemExit(__doc__)
