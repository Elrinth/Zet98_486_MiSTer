#!/usr/bin/env python3
"""Build z486_snap_tb inputs from an NP2kai snapshot (snap_regs.txt, snap_mem.bin).

Writes low.bin (1 MB legacy bus), ext.bin (RAM_MB of DDR, byte = physical
address), restore.txt (physical address and original byte of every patched
location) and snap.txt (snapshot CS and EIP for the testbench).
Usage: snap_gen.py SNAPDIR STAGE1.bin STAGE2.bin OUTDIR [options]
The stage-2 address must match the loader's STAGE2 (2000000h, or 3F00000h
with --relocate).
"""
import argparse, struct, os

p = argparse.ArgumentParser()
p.add_argument('snap'); p.add_argument('stage1'); p.add_argument('stage2'); p.add_argument('out')
p.add_argument('--ram-mb', type=int, default=64)
p.add_argument('--cache-on', action='store_true', help='clear CR0.CD/NW')
p.add_argument('--warm-kb', type=int, default=0, help='NOP sled (KB) run before entering the snapshot')
p.add_argument('--marker', type=lambda x: int(x, 16), action='append', default=[],
               help='linear address: patch a text-VRAM Z marker and jmp $ there')
p.add_argument('--hw', metavar='COM', help='hardware run: write hw_ext.bin (DDR from 110000h) and this SNAPGO.COM from stage 1')
p.add_argument('--relocate', type=int, default=0, metavar='MB',
               help='move extended RAM (1 MB up) this many MB higher, rewriting CR3 and the page tables')
a = p.parse_args()

regs = {}
for line in open(os.path.join(a.snap, 'snap_regs.txt')):
    f = line.split()
    if f[0] in ('GDTR', 'IDTR'):
        regs[f[0]] = (int(f[1], 16), int(f[2], 16))
    else:
        regs[f[0]] = int(f[1], 16)
snap = bytearray(open(os.path.join(a.snap, 'snap_mem.bin'), 'rb').read())
if a.relocate:
    R = a.relocate << 20
    def rel(frame_addr):
        return frame_addr + R if 0x100000 <= frame_addr < len(snap) else frame_addr
    cr3 = regs['CR3'] & ~0xfff
    done = set()
    for i in range(1024):
        pde = struct.unpack_from('<I', snap, cr3 + 4 * i)[0]
        if not pde & 1:
            continue
        pt = pde & ~0xfff
        if pt not in done:
            done.add(pt)
            for j in range(1024):
                pte = struct.unpack_from('<I', snap, pt + 4 * j)[0]
                if pte & 1:
                    struct.pack_into('<I', snap, pt + 4 * j, rel(pte & ~0xfff) | (pte & 0xfff))
        struct.pack_into('<I', snap, cr3 + 4 * i, rel(pt) | (pde & 0xfff))
    regs['CR3'] = rel(cr3) | (regs['CR3'] & 0xfff)
    moved = bytearray(len(snap) + R)
    moved[:0x100000] = snap[:0x100000]
    moved[0x100000 + R:len(snap) + R] = snap[0x100000:]
    snap = moved
STAGE2 = 0x3f00000 if a.relocate else 0x2000000
PT = STAGE2 - 0x1000
mem = bytearray(a.ram_mb << 20)
mem[:len(snap)] = snap
orig = bytes(mem)

s1 = open(a.stage1, 'rb').read()
mem[0x1000:0x1000 + len(s1)] = s1
mem[0xffff0:0xffff5] = bytes([0xea, 0x00, 0x10, 0x00, 0x00])
s2 = bytearray(open(a.stage2, 'rb').read())
i = s2.index(struct.pack('<I', 0x534e4150))
cr0 = regs['CR0'] & ~0x60000000 if a.cache_on else regs['CR0']
struct.pack_into('<12I', s2, i + 4, regs['EAX'], regs['ECX'], regs['EDX'], regs['EBX'], regs['ESP'],
                 regs['EBP'], regs['ESI'], regs['EDI'], regs['EIP'], regs['EFLAGS'], cr0, regs['CR3'])
struct.pack_into('<HIHIHH6H', s2, i + 52, regs['GDTR'][1], regs['GDTR'][0], regs['IDTR'][1], regs['IDTR'][0],
                 regs['LDTR'], regs['TR'], *[regs['SREG%d' % n] for n in range(6)])
struct.pack_into('<I', s2, i + 80, a.warm_kb * 256)
mem[STAGE2:STAGE2 + len(s2)] = s2
if a.warm_kb:
    sled = STAGE2 + 0x1000
    mem[sled:sled + a.warm_kb * 1024] = bytes([0x90]) * (a.warm_kb * 1024 - 1) + bytes([0xc3])
pages = 1 + (a.warm_kb + 3) // 4 + 1
base_index = (STAGE2 >> 12) & 0x3ff
assert base_index + pages <= 1024
for n in range(pages):
    struct.pack_into('<I', mem, PT + 4 * (base_index + n), (STAGE2 + 0x1000 * n) | 3)
if a.marker or a.hw:
    struct.pack_into('<I', mem, PT + 4 * (base_index + 0x10), 0xa0000 | 3)   # 2010000h -> text VRAM
def lin2phys(lin):
    cr3 = regs['CR3'] & ~0xfff
    pde_ = struct.unpack_from('<I', mem, cr3 + (lin >> 22) * 4)[0]
    pte_ = struct.unpack_from('<I', mem, (pde_ & ~0xfff) + ((lin >> 12) & 0x3ff) * 4)[0]
    assert pde_ & 1 and pte_ & 1, 'marker address not mapped'
    return (pte_ & ~0xfff) | (lin & 0xfff)
for lin in a.marker:
    code = bytes([0x66, 0xc7, 0x05]) + struct.pack('<I', STAGE2 + 0x10000) + bytes([0x5a, 0x00, 0xeb, 0xfe])
    ph = lin2phys(lin)
    mem[ph:ph + len(code)] = code
    print('marker at %08x (physical %08x)' % (lin, ph))
pde = (regs['CR3'] & ~0xfff) + (STAGE2 >> 22) * 4
assert not orig[pde] & 1, 'loader PDE is in use'
struct.pack_into('<I', mem, pde, PT | 3)

os.makedirs(a.out, exist_ok=True)
if a.hw:
    # The core's UMA (C0000h-DFFFFh: open bus, disk ROM, resident RAM) and BIOS
    # differ from NP2kai's: point every identity-mapped page there at a copy of
    # NP2kai's contents in DDR.
    romcopy = STAGE2 + 0x300000
    cr3 = regs['CR3'] & ~0xfff
    pt0 = struct.unpack_from('<I', mem, cr3)[0] & ~0xfff
    for page in list(range(0xc0, 0xe0)) + list(range(0xe8, 0x100)):
        pte = struct.unpack_from('<I', mem, pt0 + 4 * page)[0]
        if pte & 1 and (pte >> 12) == page:
            dst = romcopy + (page << 12) - 0xc0000
            mem[dst:dst + 0x1000] = mem[page << 12:(page << 12) + 0x1000]
            struct.pack_into('<I', mem, pt0 + 4 * page, dst | (pte & 0xfff))
    end = romcopy + 0x40000
    staging = STAGE2 + 0x100000
    mem[staging:staging + 0x110000] = mem[:0x110000]
    open(os.path.join(a.out, 'hw_ext.bin'), 'wb').write(mem[0x110000:end])
    open(a.hw, 'wb').write(open(a.stage1, 'rb').read())
    print('hw_ext.bin: DDR offset 110000h, %d bytes' % (end - 0x110000))
open(os.path.join(a.out, 'low.bin'), 'wb').write(mem[:0x100000])
open(os.path.join(a.out, 'ext.bin'), 'wb').write(mem)
with open(os.path.join(a.out, 'restore.txt'), 'w') as f:
    for addr in list(range(0x1000, 0x1000 + len(s1))) + list(range(0xffff0, 0xffff5)) + list(range(pde, pde + 4)):
        f.write('%08x %02x\n' % (addr, orig[addr]))
with open(os.path.join(a.out, 'snap.txt'), 'w') as f:
    f.write('%04x %08x\n' % (regs['SREG1'], regs['EIP']))
print('snapshot EIP %04x:%08x CR0 %08x CR3 %08x' % (regs['SREG1'], regs['EIP'], cr0, regs['CR3']))
