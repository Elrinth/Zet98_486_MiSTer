#!/usr/bin/env python3
"""Read the z486 crash recorder (debug builds) from MiSTer's HPS UART.

Run on the MiSTer while nothing else uses the port (stop midilink first).
Writes every received line to OUTPUT and stops after the first complete
B..Z dump or after TIMEOUT seconds. Usage: capture_crash.py OUTPUT [TIMEOUT] [--keep]
"""
import os, sys, termios, time

dev = '/dev/ttyS1'
out = sys.argv[1]
timeout = float(sys.argv[2]) if len(sys.argv) > 2 else 120
keep = '--keep' in sys.argv          # IO_MODE: record every periodic dump until the timeout
fd = os.open(dev, os.O_RDONLY | os.O_NOCTTY | os.O_NONBLOCK)
saved = termios.tcgetattr(fd)
try:
    a = termios.tcgetattr(fd)
    a[0] = 0; a[1] = 0; a[3] = 0
    a[2] = termios.CS8 | termios.CREAD | termios.CLOCAL
    a[4] = a[5] = termios.B115200
    termios.tcsetattr(fd, termios.TCSANOW, a)
    termios.tcflush(fd, termios.TCIFLUSH)
    buf = b''
    lines = []
    in_dump = False
    end = time.time() + timeout
    with open(out, 'w') as f:
        while time.time() < end:
            try:
                chunk = os.read(fd, 4096)
            except BlockingIOError:
                chunk = b''
            if not chunk:
                time.sleep(0.02)
                continue
            buf += chunk
            while b'\n' in buf:
                line, buf = buf.split(b'\n', 1)
                text = line.decode('ascii', 'replace').strip()
                f.write(text + '\n'); f.flush()
                if text == 'B':
                    in_dump = True
                elif text == 'Z' and in_dump and not keep:
                    print('complete dump captured')
                    sys.exit(0)
    print('timeout; partial capture')
finally:
    termios.tcsetattr(fd, termios.TCSANOW, saved)
    os.close(fd)
