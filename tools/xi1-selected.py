#!/usr/bin/env python3
"""Show XInput 1 event classes selected on a window (by any client): xi1-selected.py 0xWINDOW"""
import ctypes as C, ctypes.util, os, sys
X = C.CDLL(ctypes.util.find_library('X11')); Xi = C.CDLL('libXi.so.6')
X.XOpenDisplay.restype = C.c_void_p
dpy = C.c_void_p(X.XOpenDisplay(os.environ.get('DISPLAY', ':0').encode()))
Xi.XGetSelectedExtensionEvents.argtypes = [C.c_void_p, C.c_ulong, C.POINTER(C.c_int), C.POINTER(C.POINTER(C.c_ulong)),
                                           C.POINTER(C.c_int), C.POINTER(C.POINTER(C.c_ulong))]
tc, ac = C.c_int(), C.c_int()
tl, al = C.POINTER(C.c_ulong)(), C.POINTER(C.c_ulong)()
Xi.XGetSelectedExtensionEvents(dpy, int(sys.argv[1], 16), C.byref(tc), C.byref(tl), C.byref(ac), C.byref(al))
print('all clients:', sorted((al[i] >> 8, al[i] & 0xff) for i in range(ac.value)), '(device, event type)')
