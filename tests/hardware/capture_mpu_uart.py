#!/usr/bin/env python3
"""Capture the silent MPU.COM packet on MiSTer's HPS UART; restore termios.

Run before the disposable diagnostic disk boots. No bytes are transmitted.
An exact packet match proves UART transport, not game/music compatibility.
"""
import argparse
import fcntl
import glob
import hashlib
import json
import os
from pathlib import Path
import select
import struct
import termios
import time

TCGETS2, TCSETS2 = 0x802C542A, 0x402C542B
TERMIOS2 = struct.Struct('=IIIIB19BII')
EXPECTED = bytes([0xF0, 0x7D, 0x5A, 0x39, 0x38] + list(range(128)) + [0xF7])


def capture(device, output, timeout, on_ready=None):
    for fdpath in glob.glob('/proc/[0-9]*/fd/*'):
        try:
            if os.path.realpath(fdpath) == os.path.realpath(device):
                raise RuntimeError('Serial port already in use: ' + fdpath)
        except OSError:
            pass
    binary_path, report_path = Path(str(output) + '.bin'), Path(str(output) + '.json')
    if binary_path.exists() or report_path.exists():
        raise FileExistsError('Capture output already exists')
    fd = os.open(device, os.O_RDWR | os.O_NOCTTY | os.O_NONBLOCK)
    saved = bytearray(TERMIOS2.size)
    configured = False
    data = bytearray()
    result = {'device': device, 'baud': 31250, 'matched': False}
    try:
        fcntl.ioctl(fd, TCGETS2, saved)
        settings = list(TERMIOS2.unpack(saved))
        # Linux asm-generic termios2: arbitrary baud, local 8N1, no flow control.
        settings[0] = settings[1] = settings[3] = 0
        settings[2] = (settings[2] & ~(0x100F | 0x100F0000 | termios.CSIZE |
                       termios.PARENB | termios.PARODD | termios.CSTOPB |
                       termios.CRTSCTS)) | termios.CLOCAL | termios.CREAD | termios.CS8 | 0x1000
        settings[5 + termios.VMIN] = 1
        settings[5 + termios.VTIME] = 0
        settings[-2:] = [31250, 31250]
        fcntl.ioctl(fd, TCSETS2, TERMIOS2.pack(*settings))
        configured = True
        observed = bytearray(TERMIOS2.size)
        fcntl.ioctl(fd, TCGETS2, observed)
        assert TERMIOS2.unpack(observed)[-2:] == (31250, 31250), 'UART baud did not apply'
        termios.tcflush(fd, termios.TCIFLUSH)
        deadline = time.monotonic() + timeout
        print('READY: listening at 31250 baud, 8N1', flush=True)
        if on_ready is not None:
            on_ready()
        while time.monotonic() < deadline:
            readable, _, _ = select.select([fd], [], [], min(0.5, max(0, deadline-time.monotonic())))
            if readable:
                data.extend(os.read(fd, 4096))
                if len(data) > 1048576:
                    raise RuntimeError('Unexpected serial volume; refusing an unbounded capture')
                if not result['matched'] and EXPECTED in data:
                    result['matched'] = True
                    result['packet_offset'] = data.index(EXPECTED)
                    deadline = time.monotonic() + 0.5
    finally:
        try:
            if configured:
                fcntl.ioctl(fd, TCSETS2, saved)
                restored = bytearray(TERMIOS2.size)
                fcntl.ioctl(fd, TCGETS2, restored)
                result['termios_restored'] = restored == saved
        finally:
            os.close(fd)
            with binary_path.open('xb') as stream:
                stream.write(data)
            result['bytes'] = len(data)
            result['sha256'] = hashlib.sha256(data).hexdigest()
            result['expected_bytes'] = len(EXPECTED)
            with report_path.open('x') as stream:
                json.dump(result, stream, indent=2)
    print(json.dumps(result), flush=True)
    return result['matched'] and result.get('termios_restored', False)


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--device', default='/dev/ttyS1')
    parser.add_argument('--output', type=Path, required=True)
    parser.add_argument('--timeout', type=float, default=300)
    args = parser.parse_args()
    if not 0 < args.timeout <= 600:
        parser.error('timeout must be between zero and 600 seconds')
    raise SystemExit(0 if capture(args.device, args.output, args.timeout) else 1)
