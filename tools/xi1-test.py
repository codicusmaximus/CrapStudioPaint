#!/usr/bin/env python3
"""XInput 1 tablet test window (what Wine's wintab uses), via ctypes + libXi.

Opens a window on DISPLAY, selects XI1 motion/button/proximity events from the
tablet stylus/eraser devices and prints event counts and max pressure.
  xi1-test.py [seconds] [--touch] [--window=0xID]   (--touch also selects XI2 touch events on
                                    the window, like winex11 does)
"""
import ctypes as C
import ctypes.util
import os
import sys
import time

secs = float(next((a for a in sys.argv[1:] if not a.startswith('-')), 30))
touch = '--touch' in sys.argv
target = next((int(a.split('=')[1], 16) for a in sys.argv if a.startswith('--window=')), None)

X = C.CDLL(ctypes.util.find_library('X11'))
Xi = C.CDLL('libXi.so.6')
X.XOpenDisplay.restype = C.c_void_p
X.XOpenDisplay.argtypes = [C.c_char_p]
dpy = C.c_void_p(X.XOpenDisplay(os.environ.get('DISPLAY', ':0').encode()))
X.XDefaultRootWindow.restype = C.c_ulong
X.XDefaultRootWindow.argtypes = [C.c_void_p]
X.XCreateSimpleWindow.restype = C.c_ulong
X.XCreateSimpleWindow.argtypes = [C.c_void_p, C.c_ulong, C.c_int, C.c_int, C.c_uint, C.c_uint, C.c_uint, C.c_ulong, C.c_ulong]
X.XStoreName.argtypes = [C.c_void_p, C.c_ulong, C.c_char_p]
X.XMapWindow.argtypes = [C.c_void_p, C.c_ulong]
X.XPending.argtypes = [C.c_void_p]
X.XNextEvent.argtypes = [C.c_void_p, C.c_void_p]
X.XFlush.argtypes = [C.c_void_p]
X.XSelectInput.argtypes = [C.c_void_p, C.c_ulong, C.c_long]


class XDeviceInfo(C.Structure):
    _fields_ = [('id', C.c_ulong), ('type', C.c_ulong), ('name', C.c_char_p),
                ('num_classes', C.c_int), ('use', C.c_int), ('inputclassinfo', C.c_void_p)]


class XInputClassInfo(C.Structure):
    _fields_ = [('input_class', C.c_ubyte), ('event_type_base', C.c_ubyte)]


class XDevice(C.Structure):
    _fields_ = [('device_id', C.c_ulong), ('num_classes', C.c_int), ('classes', C.POINTER(XInputClassInfo))]


class XDeviceMotionEvent(C.Structure):
    _fields_ = [('type', C.c_int), ('serial', C.c_ulong), ('send_event', C.c_int), ('display', C.c_void_p),
                ('window', C.c_ulong), ('deviceid', C.c_ulong), ('root', C.c_ulong), ('subwindow', C.c_ulong),
                ('time', C.c_ulong), ('x', C.c_int), ('y', C.c_int), ('x_root', C.c_int), ('y_root', C.c_int),
                ('state', C.c_uint), ('is_hint', C.c_char), ('same_screen', C.c_int), ('device_state', C.c_uint),
                ('axes_count', C.c_ubyte), ('first_axis', C.c_ubyte), ('axis_data', C.c_int * 6)]


Xi.XListInputDevices.restype = C.POINTER(XDeviceInfo)
Xi.XListInputDevices.argtypes = [C.c_void_p, C.POINTER(C.c_int)]
Xi.XOpenDevice.restype = C.POINTER(XDevice)
Xi.XOpenDevice.argtypes = [C.c_void_p, C.c_ulong]
Xi.XSelectExtensionEvent.argtypes = [C.c_void_p, C.c_ulong, C.POINTER(C.c_ulong), C.c_int]

n = C.c_int()
devs = Xi.XListInputDevices(dpy, C.byref(n))
root = X.XDefaultRootWindow(dpy)
if target:
    win = target  # listen on another client's window
else:
    win = X.XCreateSimpleWindow(dpy, root, 0, 0, 1000, 700, 0, 0, 0xffffff)
    X.XStoreName(dpy, win, b'XI1 tablet test - draw here with the pen')
X.XSelectInput(dpy, win, 1 << 6)  # core PointerMotion (ButtonPress can't be shared)

classes, types, names = [], {}, {}
for i in range(n.value):
    name = devs[i].name.decode()
    if not any(k in name.lower() for k in ('stylus', 'eraser', 'pen')):
        continue
    dev = Xi.XOpenDevice(dpy, devs[i].id)
    if not dev:
        continue
    names[devs[i].id] = name
    for c in range(dev.contents.num_classes):
        ic = dev.contents.classes[c]
        base = ic.event_type_base
        did = dev.contents.device_id
        if ic.input_class == 1:    # ButtonClass: press=+0 release=+1
            for off, t in ((0, 'press'), (1, 'release')):
                types[base + off] = t; classes.append(did << 8 | base + off)
        elif ic.input_class == 2:  # ValuatorClass: motion=+0
            types[base] = 'motion'; classes.append(did << 8 | base)
        elif ic.input_class == 4:  # ProximityClass: in=+0 out=+1
            for off, t in ((0, 'prox-in'), (1, 'prox-out')):
                types[base + off] = t; classes.append(did << 8 | base + off)
print('devices:', names, 'classes:', len(classes))
arr = (C.c_ulong * len(classes))(*classes)
Xi.XSelectExtensionEvent(dpy, win, arr, len(classes))

if touch:
    XI = C.CDLL('libXi.so.6')

    class XIEventMask(C.Structure):
        _fields_ = [('deviceid', C.c_int), ('mask_len', C.c_int), ('mask', C.POINTER(C.c_ubyte))]
    bits = (C.c_ubyte * 4)()
    for ev in (18, 19, 20):  # XI_TouchBegin/Update/End
        bits[ev >> 3] |= 1 << (ev & 7)
    m = XIEventMask(1, 4, bits)  # XIAllMasterDevices
    XI.XISelectEvents.argtypes = [C.c_void_p, C.c_ulong, C.POINTER(XIEventMask), C.c_int]
    print('XISelectEvents touch ->', XI.XISelectEvents(dpy, win, C.byref(m), 1))

if not target:
    X.XMapWindow(dpy, win)
X.XFlush(dpy)
ev = (C.c_char * 192)()
counts, maxp = {}, 0
end = time.time() + secs
while time.time() < end:
    while X.XPending(dpy):
        X.XNextEvent(dpy, ev)
        t = C.cast(ev, C.POINTER(C.c_int))[0]
        name = types.get(t, {4: 'core-press', 5: 'core-release', 6: 'core-motion'}.get(t, f'type{t}'))
        counts[name] = counts.get(name, 0) + 1
        if name == 'motion':
            m = C.cast(ev, C.POINTER(XDeviceMotionEvent)).contents
            maxp = max(maxp, m.axis_data[2 - m.first_axis] if m.first_axis <= 2 < m.first_axis + m.axes_count else 0)
    time.sleep(0.005)
print('counts', counts, 'max pressure', maxp)
