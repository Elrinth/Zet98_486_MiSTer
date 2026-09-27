#!/usr/bin/env python3
"""Run on MiSTer: move a temporary mouse and click (for automated core tests).

Example: python mister_test_mouse.py move 0 10 click left
Arguments are a sequence of 'move DX DY', 'click left|right' and 'wait SECONDS'.
The temporary device is destroyed on exit.
"""
import fcntl
import os
import struct
import sys
import time

EV_SYN, EV_KEY, EV_REL = 0, 1, 2
BTN = {'left': 0x110, 'right': 0x111}
fd = os.open('/dev/uinput', os.O_WRONLY | os.O_NONBLOCK)


def event(kind, code, value):
    os.write(fd, struct.pack('llHHi', 0, 0, kind, code, value))


def sync():
    event(EV_SYN, 0, 0)


created = False
try:
    fcntl.ioctl(fd, 0x40045564, EV_KEY)       # UI_SET_EVBIT
    fcntl.ioctl(fd, 0x40045564, EV_REL)
    for b in BTN.values():
        fcntl.ioctl(fd, 0x40045565, b)        # UI_SET_KEYBIT
    fcntl.ioctl(fd, 0x40045566, 0)            # UI_SET_RELBIT REL_X
    fcntl.ioctl(fd, 0x40045566, 1)            # REL_Y
    device = struct.pack('80sHHHHI', b'PC98 temporary test mouse', 3, 0xcafe, 0x9802, 1, 0)
    os.write(fd, device + bytes(64 * 4 * 4))
    fcntl.ioctl(fd, 0x5501)                   # UI_DEV_CREATE
    created = True
    time.sleep(1.5)
    args = sys.argv[1:]
    i = 0
    while i < len(args):
        if args[i] == 'move':
            dx, dy = int(args[i + 1]), int(args[i + 2])
            steps = max(1, (max(abs(dx), abs(dy)) + 9) // 10)
            for s in range(steps):
                event(EV_REL, 0, dx // steps)
                event(EV_REL, 1, dy // steps)
                sync()
                time.sleep(0.02)
            i += 3
        elif args[i] == 'click':
            b = BTN[args[i + 1]]
            event(EV_KEY, b, 1); sync(); time.sleep(0.15)
            event(EV_KEY, b, 0); sync(); time.sleep(0.15)
            i += 2
        elif args[i] == 'wait':
            time.sleep(float(args[i + 1]))
            i += 2
        else:
            raise SystemExit('unknown argument ' + args[i])
    time.sleep(0.3)
finally:
    if created:
        fcntl.ioctl(fd, 0x5502)               # UI_DEV_DESTROY
    os.close(fd)
