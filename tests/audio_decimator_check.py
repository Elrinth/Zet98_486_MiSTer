#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
"""Spectrum check for audio_decimator_tb output (pure Python, no numpy).

Columns: filtered L, filtered R, bypass L, bypass R at 48 kHz.
The filtered channels must carry the tone at its zero-order-hold level with
every other component at least MIN_REJECT dB down; the bypass channels must
show the fold-back aliases, which proves the measurement can see them.
"""
import cmath
import math
import sys

RATE = 48000.0
MIN_REJECT = 65.0      # filtered: worst spur below the tone, dB
MAX_BYPASS = 35.0      # bypass: worst alias must be within this, dB
GUARD = 6              # bins excluded around DC and the tone (window main lobe)
TONES = [(10000.0, 7987200.0 / 144.0), (13000.0, 44100.0)]
AMP = 16000.0


def fft(x):
    n = len(x)
    a = list(x)
    j = 0
    for i in range(1, n):
        bit = n >> 1
        while j & bit:
            j ^= bit
            bit >>= 1
        j |= bit
        if i < j:
            a[i], a[j] = a[j], a[i]
    size = 2
    while size <= n:
        w = cmath.exp(-2j * math.pi / size)
        for start in range(0, n, size):
            wk = 1
            for k in range(size // 2):
                u = a[start + k]
                v = a[start + k + size // 2] * wk
                a[start + k] = u + v
                a[start + k + size // 2] = u - v
                wk *= w
        size <<= 1
    return a


def spectrum(samples):
    n = len(samples)
    c = (0.35875, 0.48829, 0.14128, 0.01168)  # Blackman-Harris, -92 dB sidelobes
    win = [c[0] - c[1] * math.cos(2 * math.pi * i / n) + c[2] * math.cos(4 * math.pi * i / n)
           - c[3] * math.cos(6 * math.pi * i / n) for i in range(n)]
    spec = fft([s * w for s, w in zip(samples, win)])
    gain = sum(win) / 2
    return [abs(v) / gain for v in spec[:n // 2]]


def analyse(samples, tone):
    n = len(samples)
    mag = spectrum(samples)
    tb = round(tone * n / RATE)
    peak = max(range(tb - GUARD, tb + GUARD + 1), key=lambda b: mag[b])
    power = sum(mag[b] ** 2 for b in range(tb - GUARD, tb + GUARD + 1))
    level = math.sqrt(power / 2.0044)  # Blackman-Harris ENBW in bins
    spur_bin = max((b for b in range(GUARD + 1, n // 2) if abs(b - tb) > GUARD), key=lambda b: mag[b])
    spur = 20 * math.log10(mag[spur_bin] / mag[peak] + 1e-12)
    return level, spur, spur_bin * RATE / n


def main(path):
    cols = list(zip(*[[int(v) for v in line.split()] for line in open(path) if line.strip()]))
    ok = True
    for ch, (tone, src) in enumerate(TONES):
        droop = abs(math.sin(math.pi * tone / src) / (math.pi * tone / src))
        expect = 20 * math.log10(droop)
        for name, col, filtered in (('filtered', cols[ch], True), ('bypass', cols[ch + 2], False)):
            level, spur, spur_hz = analyse(col, tone)
            gain = 20 * math.log10(level / AMP)
            print('%-8s %s %5.0f Hz: tone %+.2f dB (ZOH %+.2f), worst other %.1f dBc at %.0f Hz'
                  % (name, 'LR'[ch], tone, gain, expect, spur, spur_hz))
            if filtered:
                if abs(gain - expect) > 0.5:
                    print('FAIL: filtered tone level'); ok = False
                if spur > -MIN_REJECT:
                    print('FAIL: filtered alias/spur above -%g dBc' % MIN_REJECT); ok = False
            elif spur < -MAX_BYPASS:
                print('FAIL: bypass shows no alias; measurement is blind'); ok = False
    print('PASS: audio decimator' if ok else 'FAIL: audio decimator')
    return 0 if ok else 1


if __name__ == '__main__':
    sys.exit(main(sys.argv[1]))
