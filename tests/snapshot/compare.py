#!/usr/bin/env python3
"""Compare the z486 issue trace (run.log "I cs eip vm") with NP2kai's
snap_trace.bin (10 dwords per instruction: cs<<16|vm, eip, eax..edi).
Usage: compare.py RUN.LOG SNAP_TRACE.BIN [--context N]"""
import argparse, struct

p = argparse.ArgumentParser()
p.add_argument('log'); p.add_argument('trace'); p.add_argument('--context', type=int, default=12)
p.add_argument('--snap', help='snapshot dir: skip NP2kai hardware IRQs (IDT vectors 50h-5Fh)')
a = p.parse_args()
irq = set()
if a.snap:
    regs = dict(l.split()[:2] for l in open(a.snap + '/snap_regs.txt') if not l.startswith(('GDTR', 'IDTR')))
    idtr = [l.split() for l in open(a.snap + '/snap_regs.txt') if l.startswith('IDTR')][0]
    m = open(a.snap + '/snap_mem.bin', 'rb').read(); cr3 = int(regs['CR3'], 16)
    def phys(lin):
        pde = struct.unpack_from('<I', m, (cr3 & ~0xfff) + (lin >> 22) * 4)[0]
        pte = struct.unpack_from('<I', m, (pde & ~0xfff) + ((lin >> 12) & 0x3ff) * 4)[0]
        return (pte & ~0xfff) | (lin & 0xfff)
    for v in range(0x50, 0x60):
        lo, sel, _, ty, hi = struct.unpack_from('<HHBBH', m, phys(int(idtr[1], 16) + v * 8))
        irq.add((hi << 16) | lo)
sim = []
for line in open(a.log):
    if line.startswith('I '):
        _, cs, eip, vm = line.split()
        sim.append((int(cs, 16), int(eip, 16), int(vm)))
d = open(a.trace, 'rb').read()
raw = [struct.unpack_from('<10I', d, i * 40) for i in range(min(len(d) // 40, 3 * len(sim) + 100000))]
ref, k, skipped = [], 0, 0
while k < len(raw) and len(ref) < len(sim):
    r = raw[k]
    if r[1] in irq and not r[0] & 1 and ref:
        back = r[6] + 12                       # ring-0 interrupt frame
        k += 1
        while k < len(raw) and not (raw[k][1] == ref[-1][1] and False):
            if raw[k][6] == back and raw[k - 1][1] != raw[k][1] and (raw[k][0] >> 16) == 0x28:
                break
            k += 1
        skipped += 1
        continue
    ref.append(r); k += 1
print('NP2kai hardware IRQs skipped: %d' % skipped)
for i, (s, r) in enumerate(zip(sim, ref)):
    if (s[0], s[1], s[2]) != (r[0] >> 16, r[1], r[0] & 1):
        print('first difference at instruction %d' % i)
        for k in range(max(0, i - a.context), min(len(sim), i + a.context)):
            rr = ref[k]
            print('%6d  z486 %04x:%08x %s   np2 %04x:%08x %s  eax=%08x ecx=%08x edx=%08x esp=%08x%s' % (
                k, sim[k][0], sim[k][1], 'V' if sim[k][2] else 'P', rr[0] >> 16, rr[1], 'V' if rr[0] & 1 else 'P',
                rr[2], rr[3], rr[4], rr[6], '  <==' if k == i else ''))
        break
else:
    print('identical for %d instructions' % len(sim))
