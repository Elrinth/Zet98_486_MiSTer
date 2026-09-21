#!/usr/bin/env python3
"""Run on MiSTer: send explicit Linux keyboard codes through a temporary device.

Example: python mister_test_keys.py 28 (Enter). The temporary keyboard is
destroyed on exit; no saved input mappings or physical devices are modified.
"""
import argparse
import fcntl
import os
import struct
import time

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('keys', type=int, nargs='+')
parser.add_argument('--hold', type=float, default=0.15)
args = parser.parse_args()
if any(key < 1 or key > 127 for key in args.keys) or not 0.01 <= args.hold <= 10:
    parser.error('Keys must be 1..127; hold must be 0.01..10 seconds')

fd = os.open('/dev/uinput', os.O_WRONLY | os.O_NONBLOCK)
created = False


def event(kind, code, value):
    # Native long is 32 bits on MiSTer's ARM Linux.
    os.write(fd, struct.pack('llHHi', 0, 0, kind, code, value))


try:
    fcntl.ioctl(fd, 0x40045564, 1)  # UI_SET_EVBIT, EV_KEY
    for key in range(1, 128):
        fcntl.ioctl(fd, 0x40045565, key)  # UI_SET_KEYBIT
    device = struct.pack('80sHHHHI', b'Zet98 temporary test keyboard', 3, 0xcafe, 0x9801, 1, 0)
    os.write(fd, device + bytes(64 * 4 * 4))
    fcntl.ioctl(fd, 0x5501)  # UI_DEV_CREATE
    created = True
    time.sleep(1.5)        # Give MiSTer's hotplug handler time to open it.
    for key in args.keys:
        event(1, key, 1)
        event(0, 0, 0)
        time.sleep(args.hold)
        event(1, key, 0)
        event(0, 0, 0)
        time.sleep(0.25)
finally:
    if created:
        fcntl.ioctl(fd, 0x5502)  # UI_DEV_DESTROY also releases any held key
    os.close(fd)
