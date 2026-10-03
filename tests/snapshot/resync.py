#!/usr/bin/env python3
"""List divergence regions between the z486 issue trace and NP2kai's trace,
resynchronising on the next run of K matching instructions.
Usage: resync.py RUN.LOG SNAP_TRACE.BIN [--k 24] [--window 20000]"""
import argparse, struct
from collections import defaultdict

p = argparse.ArgumentParser()
p.add_argument('log'); p.add_argument('trace')
p.add_argument('--k', type=int, default=24); p.add_argument('--window', type=int, default=20000)
a = p.parse_args()
sim = []
for line in open(a.log):
    if line.startswith('I '):
        _, cs, eip, vm = line.split()
        sim.append((int(cs, 16), int(eip, 16), int(vm)))
d = open(a.trace, 'rb').read()
n = min(len(d) // 40, 4 * len(sim) + 200000)
ref = []
for i in range(n):
    r = struct.unpack_from('<2I', d, i * 40)
    ref.append((r[0] >> 16, r[1], r[0] & 1))
K = a.k
grams = defaultdict(list)
for j in range(len(ref) - K):
    grams[tuple(ref[j:j + K])].append(j)
i = j = 0
while i < len(sim) and j < len(ref):
    if sim[i] == ref[j]:
        i += 1; j += 1; continue
    best = None
    for di in range(0, min(a.window, len(sim) - i - K)):
        for jj in grams.get(tuple(sim[i + di:i + di + K]), ()):
            if jj >= j and jj - j <= a.window:
                best = (di, jj - j); break
        if best: break
    fmt = lambda t: '%04x:%08x%s' % (t[0], t[1], 'V' if t[2] else '')
    if not best:
        print('z486 %6d %s / np2 %6d %s: no resync; z486 continues %s' % (i, fmt(sim[i]), j, fmt(ref[j]),
              ' '.join(fmt(t) for t in sim[i:i + 8])))
        break
    print('z486 %6d %s / np2 %6d %s: z486 skips %d, np2 skips %d' % (i, fmt(sim[i]), j, fmt(ref[j]), best[0], best[1]))
    i += best[0]; j += best[1]
else:
    print('traces end in sync: z486 %d, np2 %d' % (i, j))
