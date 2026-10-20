#!/usr/bin/env python3
"""Print XI2 raw pointer/tablet events (source device, axis values) on an X display.
Used to check that the desktop delivers tablet pressure (axis 2) to X clients.
Usage: xi-raw.py [:0] [seconds]"""
import struct
import sys
import time

from Xlib import display
from Xlib.ext import xinput

d = display.Display(sys.argv[1] if len(sys.argv) > 1 else ':0')
secs = float(sys.argv[2]) if len(sys.argv) > 2 else 20
d.xinput_query_version()
names = {i.deviceid: i.name for i in d.xinput_query_device(xinput.AllDevices).devices}
d.screen().root.xinput_select_events(
    [(xinput.AllDevices, xinput.RawMotionMask | xinput.RawButtonPressMask | xinput.RawButtonReleaseMask)])

EVT = {15: 'press', 16: 'release', 17: 'motion'}
counts, maxp = {}, {}
end = time.time() + secs
while time.time() < end:
    while d.pending_events():
        e = d.next_event()
        if e.type != d.extension_event.GenericEvent or e.evtype not in EVT:
            continue
        b = e.data
        src, nval = struct.unpack_from('<HH', b, 10)
        mask = int.from_bytes(b[22:22 + 4 * nval], 'little')
        off, axes = 22 + 4 * nval, {}
        for i in range(32 * nval):
            if mask >> i & 1:
                hi, lo = struct.unpack_from('<iI', b, off)
                axes[i] = hi + lo / 2**32
                off += 8
        name = names.get(src, str(src))
        counts[name] = counts.get(name, 0) + 1
        if 2 in axes:
            maxp[name] = max(maxp.get(name, 0), axes[2])
        if counts[name] % 20 == 1 or e.evtype != 17:
            print(f'{EVT[e.evtype]:7} {name:28} ' + ' '.join(f'a{k}={v:.0f}' for k, v in axes.items()), flush=True)
    time.sleep(0.005)
print('counts', counts)
print('max pressure (axis 2)', maxp)
