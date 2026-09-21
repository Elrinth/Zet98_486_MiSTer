#!/usr/bin/env python3
"""Linux pseudo-terminal checks for the hardware capture utility."""
import fcntl
import importlib.util
import os
from pathlib import Path
import pty
import tempfile
import threading
import time

spec = importlib.util.spec_from_file_location('capture', Path(__file__).with_name('capture_mpu_uart.py'))
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)


def run_case(payload, expected):
    master, slave = pty.openpty()
    device = os.ttyname(slave)
    saved = bytearray(module.TERMIOS2.size)
    fcntl.ioctl(slave, module.TCGETS2, saved)
    os.close(slave)
    ready = threading.Event()

    def send():
        assert ready.wait(10), 'Capture never became ready'
        for start in range(0, len(payload), 7):
            os.write(master, payload[start:start+7])
            time.sleep(0.002)

    sender = threading.Thread(target=send)
    try:
        with tempfile.TemporaryDirectory() as folder:
            sender.start()
            result = module.capture(device, Path(folder) / 'capture', 0.8, ready.set)
            sender.join()
            assert result is expected, (result, expected)
            assert (Path(folder) / 'capture.bin').read_bytes() == payload
            slave = os.open(device, os.O_RDWR | os.O_NOCTTY)
            restored = bytearray(module.TERMIOS2.size)
            fcntl.ioctl(slave, module.TCGETS2, restored)
            os.close(slave)
            assert restored == saved, 'Original UART settings not restored'
    finally:
        sender.join()
        os.close(master)


run_case(b'boot-noise' + module.EXPECTED, True)
bad = bytearray(module.EXPECTED)
bad[65] ^= 1
run_case(bytes(bad), False)
print('PASS fragmented packet, exact-byte negative, and original termios restoration')
