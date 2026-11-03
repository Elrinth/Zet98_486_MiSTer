#!/usr/bin/env python3
"""Run on MiSTer: move a temporary mouse and click (for automated core tests).

Example: python mister_test_mouse.py move 0 10 click left
Arguments are a sequence of 'move DX DY', 'click left|right', 'press/release
left|right' and 'wait SECONDS'.

'mouse.py --daemon' keeps one virtual mouse for good and takes the same
argument lines from /tmp/moused.fifo; while it runs, plain calls hand their
arguments to it and wait until they are done. A new uinput device per call
could lose its first events (a click's press) when MiSTer had not opened the
device yet.
"""
import fcntl
import os
import struct
import sys
import time

EV_SYN, EV_KEY, EV_REL = 0, 1, 2
BTN = {'left': 0x110, 'right': 0x111}
FIFO, ACK, PID = '/tmp/moused.fifo', '/tmp/moused.ack', '/tmp/moused.pid'


def daemon_alive():
    try:
        os.kill(int(open(PID).read()), 0)
        return os.path.exists(FIFO)
    except (OSError, ValueError):
        return False


def open_device():
    fd = os.open('/dev/uinput', os.O_WRONLY | os.O_NONBLOCK)
    fcntl.ioctl(fd, 0x40045564, EV_KEY)       # UI_SET_EVBIT
    fcntl.ioctl(fd, 0x40045564, EV_REL)
    for b in BTN.values():
        fcntl.ioctl(fd, 0x40045565, b)        # UI_SET_KEYBIT
    fcntl.ioctl(fd, 0x40045566, 0)            # UI_SET_RELBIT REL_X
    fcntl.ioctl(fd, 0x40045566, 1)            # REL_Y
    device = struct.pack('80sHHHHI', b'PC98 temporary test mouse', 3, 0xcafe, 0x9802, 1, 0)
    os.write(fd, device + bytes(64 * 4 * 4))
    fcntl.ioctl(fd, 0x5501)                   # UI_DEV_CREATE
    return fd


def run(fd, args):
    def event(kind, code, value):
        os.write(fd, struct.pack('llHHi', 0, 0, kind, code, value))

    def sync():
        event(EV_SYN, 0, 0)

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
        elif args[i] in ('press', 'release'):
            event(EV_KEY, BTN[args[i + 1]], 1 if args[i] == 'press' else 0); sync()
            i += 2
        elif args[i] == 'wait':
            time.sleep(float(args[i + 1]))
            i += 2
        else:
            raise SystemExit('unknown argument ' + args[i])


if sys.argv[1:] == ['--daemon']:
    fd = open_device()
    if not os.path.exists(FIFO):
        os.mkfifo(FIFO)
    open(PID, 'w').write(str(os.getpid()))
    time.sleep(1.5)
    while True:
        with open(FIFO) as f:
            for line in f:
                job, *args = line.split()
                try:
                    run(fd, args)
                except (SystemExit, ValueError, KeyError, IndexError):
                    pass
                with open(ACK, 'a') as a:
                    a.write(job + '\n')
elif daemon_alive():
    job = '%d.%d' % (os.getpid(), time.time() * 1000)
    with open(FIFO, 'w') as f:
        f.write(job + ' ' + ' '.join(sys.argv[1:]) + '\n')
    end = time.time() + 120
    while time.time() < end:
        try:
            if job in open(ACK).read().split():
                break
        except OSError:
            pass
        time.sleep(0.05)
else:
    fd = open_device()
    try:
        time.sleep(1.5)
        run(fd, sys.argv[1:])
        time.sleep(0.3)
    finally:
        fcntl.ioctl(fd, 0x5502)               # UI_DEV_DESTROY
        os.close(fd)
