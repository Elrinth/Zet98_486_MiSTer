#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
"""Design the 768 kHz -> 48 kHz anti-alias FIR used by rtl/audio_decimator.sv.

The FIR runs after a second-order CIC (24.576 MHz -> 768 kHz, R=32) and keeps
one output in sixteen. Equiripple (Parks-McClellan): passband 0-18 kHz,
stopband from 28 kHz, so anything the 48 kHz output would fold back lands
above 20 kHz or is attenuated by the stopband.

Writes rtl/assets/audio-decimator-coeffs.mem (256 x 18-bit two's complement
hex, the last entry is zero) and prints the quantized response.
"""
import argparse
from pathlib import Path

import numpy as np
from scipy import signal

FS = 768000
TAPS = 255
PASS_HZ = 18000
STOP_HZ = 28000
STOP_WEIGHT = 30
COEF_FRAC = 21  # coefficient = round(h * 2**21), must fit signed 18 bits


def design():
    h = signal.remez(TAPS, [0, PASS_HZ, STOP_HZ, FS / 2], [1, 0],
                     weight=[1, STOP_WEIGHT], fs=FS)
    q = np.round(h * (1 << COEF_FRAC)).astype(int)
    assert np.abs(q).max() < (1 << 17), 'coefficient overflows 18 bits'
    return q


def response(q):
    # Include the CIC2 (R=32 at 24.576 MHz) that precedes the FIR.
    f = np.linspace(0, FS / 2, 1 << 16)
    _, fir = signal.freqz(q / (1 << COEF_FRAC), worN=f, fs=FS)
    x = np.pi * f / 24576000
    cic = np.ones_like(f)
    nz = f > 0
    cic[nz] = (np.sin(32 * x[nz]) / (32 * np.sin(x[nz]))) ** 2
    db = 20 * np.log10(np.abs(fir * cic) + 1e-15)
    return f, db


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--out', default=str(Path(__file__).resolve().parents[1]
                                          / 'rtl/assets/audio-decimator-coeffs.mem'))
    args = ap.parse_args()
    q = design()
    f, db = response(q)
    print('taps %d  sum %d (DC gain %.5f)  max %d' % (TAPS, q.sum(), q.sum() / (1 << COEF_FRAC), np.abs(q).max()))
    print('passband 0-%d Hz: %.3f .. %.3f dB' % (PASS_HZ, db[f <= PASS_HZ].min(), db[f <= PASS_HZ].max()))
    print('stopband >=%d Hz: %.1f dB' % (STOP_HZ, db[f >= STOP_HZ].max()))
    words = list(q) + [0] * (256 - TAPS)
    Path(args.out).write_text(''.join('%05x\n' % (w & 0x3ffff) for w in words))
    print('wrote', args.out)


if __name__ == '__main__':
    main()
