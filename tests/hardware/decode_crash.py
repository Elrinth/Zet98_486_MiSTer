#!/usr/bin/env python3
"""Decode a z486 crash-recorder capture (tests/hardware/capture_crash.py).

Prints the last complete B..Z dump oldest first. Gate reads show the vector
relative to the IDT base, taken as the lowest gate address seen unless
--idt is given. Usage: decode_crash.py CAPTURE [--idt HEX] [--last N]
"""
import argparse

TYPES = {1: 'GATE', 2: 'MODE', 3: 'TRIPLE', 4: 'PORT_F0', 5: 'RESETVEC', 6: 'PF', 7: 'WALK', 8: 'WATCHWR', 9: 'EXTWR', 10: 'IOWR', 11: 'IORD'}
EXC = {0: '#DE', 1: '#DB', 2: 'NMI', 3: '#BP', 4: '#OF', 5: '#BR', 6: '#UD', 7: '#NM', 8: '#DF',
       10: '#TS', 11: '#NP', 12: '#SS', 13: '#GP', 14: '#PF', 16: '#MF', 17: '#AC'}

p = argparse.ArgumentParser()
p.add_argument('capture')
p.add_argument('--idt', type=lambda x: int(x, 16))
p.add_argument('--last', type=int, default=256)
a = p.parse_args()
lines = [l.strip() for l in open(a.capture)]
dumps, cur = [], None
ALL = '--all' in __import__('sys').argv
for l in lines:
    if l == 'B':
        cur = []
    elif l == 'Z' and cur is not None:
        dumps.append(cur); cur = None
    elif l.startswith('E') and cur is not None and len(l) == 33:
        cur.append(int(l[1:], 16))
if not dumps:
    hb = [l for l in lines if l.startswith('H')]
    raise SystemExit('no complete dump; %d heartbeat lines (recorder not triggered?)' % len(hb))
entries = [e for e in dumps[-1] if e >> 124]
gates = [(e >> 44) & 0xffffffff for e in entries if (e >> 124) == 1]
idt = a.idt if a.idt is not None else (min(gates) if gates else 0)
print('IDT base %08x, %d entries' % (idt, len(entries)))
for e in entries[-a.last:]:
    t = e >> 124; cs = (e >> 108) & 0xffff; eip = (e >> 76) & 0xffffffff
    pay = (e >> 44) & 0xffffffff; pfc = (e >> 41) & 7; cr2 = (e >> 9) & 0xffffffff
    vm = (e >> 8) & 1; pe = (e >> 7) & 1; seq = e & 0x7f
    what = TYPES.get(t, '?%d' % t)
    extra = ''
    if t == 1:
        v = (pay - idt) // 8
        extra = 'vec %02Xh %s gate@%08x' % (v, EXC.get(v, ''), pay)
    elif t == 2:
        extra = 'EFLAGS %08x' % pay
    elif t == 4:
        extra = 'data %02x' % (pay & 0xff)
    elif t == 6:
        extra = 'PTE %08x' % pay
    elif t in (10, 11):
        print('%3d %-5s port %04x = %08x  at %04x:%04x' % (seq, what, cs, eip, pay >> 16, pay & 0xffff))
        continue
    elif t in (8, 9):
        print('%3d %-8s addr %08x = %08x (be %x)  PE=%d VM=%d' % (seq, what, eip, pay, cs & 15, pe, vm))
        continue
    elif t == 7:
        print('    WALK     PDE %08x  CR3 %08x  A20=%d' % (eip, pay, cs & 1))
        continue
    print('%3d %-8s %04x:%08x VM=%d PE=%d  %-28s  #PF code %d CR2 %08x' % (seq, what, cs, eip, vm, pe, extra, pfc, cr2))
