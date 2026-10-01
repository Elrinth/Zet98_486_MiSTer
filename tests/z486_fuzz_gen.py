#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
"""Generate a random Watcom-style integer program for z486 differential tests.

The program enters flat 32-bit protected mode, fills its data areas from an
LFSR, runs BLOCKS random instruction blocks and stores all eight GPRs to a
log after each block. The testbench dumps 40000h-9FFFFh; the same binary runs
on Unicorn and the dumps must match byte for byte.

Only architecturally defined results are observable: flags are never logged,
and every flag consumer (ADC/SBB/SETcc/Jcc) directly follows an instruction
that defines the flags it reads. Memory operands stay inside the scratch areas:
cached low RAM, uncached upper RAM and a 16 KB DDR window.
"""
import json
import os
import random
import sys

SCRATCH = 0x48000       # cached conventional RAM, 16 KB
UPPER = 0x90000         # uncached upper conventional RAM, 16 KB
DDR = 0x2000000         # extended RAM (misses), 16 KB
LOG = 0x50000           # 32 bytes per block
STACK = 0x7f000
FRAME = 0x7e000         # EBP frame; locals at [ebp-80h..ebp+7Ch]
REGS = ['eax', 'ebx', 'ecx', 'edx', 'esi', 'edi']
R16 = {'eax': 'ax', 'ebx': 'bx', 'ecx': 'cx', 'edx': 'dx', 'esi': 'si', 'edi': 'di'}
R8 = {'eax': 'al', 'ebx': 'bl', 'ecx': 'cl', 'edx': 'dl'}
CC = ['e', 'ne', 'l', 'ge', 'le', 'g', 'b', 'ae', 'be', 'a', 's', 'ns']
# Z486_FUZZ_486=1 adds 486 XADD/CMPXCHG blocks (existing seeds are unchanged
# without it).
EXT486 = os.environ.get('Z486_FUZZ_486') == '1'


def gen(seed, blocks, block_len):
    rnd = random.Random(seed)
    out = []
    manifest = []
    label = [0]

    last = ['eax']

    def r():
        # Compiled code chains results: reuse the last destination most of
        # the time and favour EAX, as Watcom's register allocator does.
        x = rnd.random()
        if x < 0.5:
            return last[0]
        if x < 0.7:
            return 'eax'
        return rnd.choice(REGS)

    def area():
        return rnd.choice([SCRATCH, SCRATCH, SCRATCH, UPPER, DDR])

    def mem(size='dword'):
        # Watcom forms: absolute, frame-relative, or base+masked index.
        kind = rnd.randrange(4)
        if kind == 0:
            return f'{size} [0x{area() + rnd.randrange(0, 0x3ff0) & ~3:x}]'
        if kind == 1:
            return f'{size} [ebp{rnd.randrange(-0x80, 0x7c) & ~3:+d}]'
        return None  # caller emits an index form

    def mem_op(size='dword'):
        m = mem(size)
        if m:
            return [], m
        idx = rnd.choice(['esi', 'edi', 'ebx'])
        scale = rnd.choice([1, 2, 4])
        base = area()
        # Keep the index in range; this AND is itself typical of the source.
        return [f'and {idx},0x{0xff0 // scale * scale & ~3:x}'], f'{size} [0x{base:x}+{idx}*{scale}]'

    def flag_def():
        a, b = r(), r()
        return rnd.choice([f'cmp {a},{b}', f'add {a},{b}', f'sub {a},{b}', f'test {a},{b}',
                           f'cmp {a},0x{rnd.randrange(1 << 16):x}'])

    def frame():
        return f'dword [ebp{rnd.randrange(-0x80, 0x7c) & ~3:+d}]'

    def absolute():
        return f'dword [0x{area() + rnd.randrange(0, 0x3ff0) & ~3:x}]'

    def idiom():
        # Recurring Watcom C 9.x shapes (R_PrecacheLevel, R_DrawPlanes loops).
        a = r()
        op = rnd.choice(['add', 'sub', 'and', 'or', 'xor', 'cmp'])
        f = frame()
        k = rnd.randrange(5)
        if k == 0: return [f'mov {a},{absolute()}', f'{op} {a},{frame()}']
        if k == 1: return [f'inc {f}', f'mov {a},{absolute()}', f'add {a},{frame()}', f'mov {r()},{f}']
        if k == 2: return [f'mov {a},{frame()}', f'sar {a},{rnd.randrange(1,32)}', f'{op} {a},{absolute()}']
        if k == 3: return [f'mov {a},{absolute()}', f'shl {a},{rnd.randrange(1,8)}', f'add {a},{frame()}', f'mov {f},{a}']
        return [f'{rnd.choice(["add","sub"])} {f},{a}', f'mov {a},{f}', f'imul {a},{frame()}']

    def ext486():
        a, b = r(), r()
        lock = rnd.choice(['', 'lock '])
        k = rnd.randrange(12)
        size = rnd.choice(['byte', 'word', 'dword', 'dword'])
        def reg(x):
            if size == 'byte':
                return R8.get(x, 'bl')
            return R16[x] if size == 'word' else x
        acc = {'byte': 'al', 'word': 'ax', 'dword': 'eax'}[size]
        pre, m = mem_op(size)
        # Registers that a later reuse of m must not see modified.
        free = [x for x in ['ebx', 'ecx', 'edx', 'esi', 'edi'] if x not in m]
        if a not in free and k == 10:
            a = rnd.choice(free)
        if b not in free and k == 11:
            b = rnd.choice(free)
        tail = rnd.choice([[], [f'set{rnd.choice(CC)} {R8[rnd.choice(list(R8))]}'],
                           [f'{rnd.choice(["adc","sbb"])} {r()},{r()}']])
        if k == 0: return [f'xadd {reg(a)},{reg(b)}'] + tail
        if k in (1, 2): return pre + [f'{lock}xadd {m},{reg(a)}'] + tail
        if k == 3: return [f'cmpxchg {reg(a)},{reg(b)}'] + tail
        if k == 4: return [f'mov {acc},{reg(a)}', f'cmpxchg {reg(a)},{reg(b)}'] + tail
        if k in (5, 6): return pre + [f'{lock}cmpxchg {m},{reg(a)}'] + tail
        if k in (7, 8):
            # Compare-and-swap idiom: load, compute, LOCK CMPXCHG (usually equal).
            new = rnd.choice(free)
            return pre + [f'mov {acc},{m}', f'lea {new},[eax+{rnd.randrange(1, 9)}]',
                          f'{lock}cmpxchg {m},{reg(new) if size != "byte" else R8.get(new, "dl")}'] + tail
        if k == 9:
            label[0] += 1
            return pre + [f'{lock}cmpxchg {m},{reg(a)}', f'jnz .x{label[0]}',
                          f'add {b},0x{rnd.getrandbits(16):x}', f'.x{label[0]}:']
        if k == 10: return pre + [f'{lock}xadd {m},{reg(a)}', f'mov {reg(b)},{m}']
        return pre + [f'mov {reg(b)},{m}', f'{lock}xadd {m},{reg(a)}', f'add {a},{b}']

    def one():
        if EXT486 and rnd.random() < 0.2:
            return ext486()
        if rnd.random() < 0.3:
            return idiom()
        k = rnd.randrange(34)
        a, b = r(), r()
        pre, m = mem_op()
        if k == 0: return [f'mov {a},{b}']
        if k == 1: return [f'mov {a},0x{rnd.getrandbits(32):x}']
        if k in (2, 3): return pre + [f'mov {a},{m}']
        if k == 4: return pre + [f'mov {m},{a}']
        if k == 5: return pre + [f'mov {m},0x{rnd.getrandbits(32):x}']
        if k in (6, 7): return pre + [f'{rnd.choice(["add","sub","and","or","xor"])} {a},{m}']
        if k == 8: return pre + [f'{rnd.choice(["add","sub","and","or","xor"])} {m},{a}']
        if k == 9: return [f'{rnd.choice(["add","sub","and","or","xor"])} {a},{b}']
        if k == 10: return [f'{rnd.choice(["add","sub","and","or","xor"])} {a},0x{rnd.getrandbits(rnd.choice([7,16,32])):x}']
        if k == 11: return pre + [f'{rnd.choice(["inc","dec","neg","not"])} {m}']
        if k == 12: return [f'{rnd.choice(["inc","dec","neg","not"])} {a}']
        if k in (13, 14): return [f'{rnd.choice(["shl","shr","sar","rol","ror"])} {a},{rnd.randrange(1,32)}']
        if k == 15: return [f'mov ecx,{rnd.randrange(32)}', f'{rnd.choice(["shl","shr","sar"])} {a if a != "ecx" else "eax"},cl']
        if k == 16: return pre + [f'{rnd.choice(["shl","shr","sar"])} {m},{rnd.randrange(1,32)}']
        if k == 17: return [f'imul {a},{b}']
        if k == 18: return pre + [f'imul {a},{m}']
        if k == 19: return pre + [f'imul {a},{m},{rnd.randrange(-128,128)}']
        if k == 20: return [f'imul {a},{b},0x{rnd.randrange(1,0x7fffffff):x}']
        if k == 21:
            pre, m = mem_op(rnd.choice(['byte', 'word']))
            return pre + [f'{rnd.choice(["movsx","movzx"])} {a},{m}']
        if k == 22: return [f'lea {a},[{b}+{r()}*{rnd.choice([1,2,4,8])}{rnd.randrange(-0x800,0x800):+d}]']
        if k == 23: return [f'push {a}', f'pop {b}']
        if k == 24: return [f'xchg {a},{b}']
        if k == 25: return ['cdq']
        if k == 26: return [flag_def(), f'set{rnd.choice(CC)} {R8[rnd.choice(list(R8))]}']
        if k == 27: return [flag_def(), f'{rnd.choice(["adc","sbb"])} {a},{b}']
        if k == 28:
            label[0] += 1
            return [flag_def(), f'j{rnd.choice(CC)} .s{label[0]}', f'add {a},0x{rnd.getrandbits(16):x}', f'.s{label[0]}:']
        if k == 29: return ['xor edx,edx', f'or {b if b not in ("eax","edx") else "ebx"},1',
                            f'div {b if b not in ("eax","edx") else "ebx"}']
        if k == 30: return pre + [f'mov {R16[a]},{m.replace("dword","word")}']
        if k == 31: return [f'mul {b}']
        if k == 32: return pre + [f'cmp {a},{m}', f'set{rnd.choice(CC)} {R8[rnd.choice(list(R8))]}']
        return [f'bswap {a}']

    out += ['bits 16', 'cpu 586' if EXT486 else 'cpu 486', 'org 100h', 'cli', 'cld', 'mov ax,cs', 'mov ds,ax',
            'xor al,al', 'out 0f2h,al', 'lgdt [gdtr]', 'mov eax,cr0', 'or al,1', 'mov cr0,eax',
            'jmp dword 8:pm32', 'align 8', 'gdt:', 'dq 0', 'dq 00cf9a010000ffffh', 'dq 00cf92000000ffffh',
            'gdtr:', 'dw $-gdt-1', 'dd 10000h+gdt', 'bits 32', 'pm32:', 'mov ax,10h', 'mov ds,ax', 'mov es,ax', 'mov ss,ax',
            f'mov esp,0x{STACK:x}', f'mov ebp,0x{FRAME:x}']
    # Deterministic data fill (LFSR) of all scratch areas and the frame.
    fill = [(SCRATCH, 0x4000), (UPPER, 0x4000), (DDR, 0x4000), (FRAME - 0x100, 0x200)]
    out += [f'mov eax,0x{rnd.getrandbits(32) | 1:x}']
    for base, size in fill:
        out += [f'mov edi,0x{base:x}', f'mov ecx,{size // 4}', '.f%x:' % base,
                'shr eax,1', 'jnc .n%x' % base, 'xor eax,0xd0000001', '.n%x:' % base,
                'stosd', 'dec ecx', 'jnz .f%x' % base]
    for reg in REGS:
        out.append(f'mov {reg},0x{rnd.getrandbits(32):x}')
    for i in range(blocks):
        body = []
        while len(body) < block_len:
            ins = one()
            body += ins
            for line in reversed(ins):
                dst = line.split(' ', 1)[1].split(',')[0] if ' ' in line else ''
                if dst in REGS:
                    last[0] = dst
                    break
        out += body
        at = LOG + i * 32
        out += [f'mov [0x{at + j * 4:x}],{reg}' for j, reg in enumerate(REGS + ['ebp'])]
        out += [f'mov [0x{at + 28:x}],esp']
        manifest.append(body)
    out += ['mov dx,7ff0h', 'mov ax,600dh', 'out dx,ax', 'hlt', 'jmp $']
    return '\n'.join(out) + '\n', manifest


if __name__ == '__main__':
    seed, blocks, block_len = int(sys.argv[1]), int(sys.argv[2]), int(sys.argv[3])
    asm, manifest = gen(seed, blocks, block_len)
    open(sys.argv[4], 'w', newline='\n').write(asm)
    json.dump(manifest, open(sys.argv[5], 'w'))
