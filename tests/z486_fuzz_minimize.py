#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
"""Shrink a failing z486_fuzz_gen.py program to a minimal instruction list.

Usage: z486_fuzz_minimize.py <fuzz-N.asm> <block> <container> <workdir>

Blocks before <block>-1 stay unchanged, so architectural state reproduces;
blocks <block>-1 and <block> are delta-debugged. A candidate is "failing" when
its final register log differs between the z486 testbench (running in the
already compiled Docker container) and Unicorn. Prints the minimal list.
"""
import os
import re
import subprocess
import sys
from unicorn import Uc, UC_ARCH_X86, UC_MODE_32, UC_HOOK_INSN, UcError
from unicorn.x86_const import UC_X86_INS_OUT

LOG = 0x50000
asm_path, block, container, work = sys.argv[1], int(sys.argv[2]), sys.argv[3], sys.argv[4]
lines = open(asm_path).read().split('\n')
# Each block ends with eight "mov [0x5....],reg" log stores.
log_re = re.compile(r'^mov \[0x5[0-9a-f]{4}\],(e[a-z]{2})$')
ends = [n for n, l in enumerate(lines) if log_re.match(l) and l.endswith('esp')]
# The prologue ends at the last register initialisation before block 0.
first_log = ends[0] - 7
prologue_end = max(n for n in range(first_log) if lines[n].startswith('mov e') and ',0x' in lines[n] and
                   lines[n].split(' ')[1].split(',')[0] in ('eax', 'ebx', 'ecx', 'edx', 'esi', 'edi')) + 1
starts = [prologue_end] + [e + 1 for e in ends[:-1]]
blocks = [lines[starts[b]:ends[b] - 7] for b in range(len(ends))]
prefix = lines[:starts[block - 1]]
epilogue = ['mov dx,7ff0h', 'mov ax,600dh', 'out dx,ax', 'hlt', 'jmp $']


def program(body):
    at = LOG + (block - 1) * 32
    log = [f'mov [0x{at + j * 4:x}],{r}' for j, r in enumerate(['eax', 'ebx', 'ecx', 'edx', 'esi', 'edi', 'ebp', 'esp'])]
    return '\n'.join(prefix + body + log + epilogue) + '\n'


def docker(*args, **kw):
    return subprocess.run(['docker', '--context', 'desktop-linux'] + list(args), capture_output=True, **kw)


def reference(binary):
    far = binary.find(bytes([0x66, 0xea]))
    pm32 = int.from_bytes(binary[far + 2:far + 6], 'little')
    mu = Uc(UC_ARCH_X86, UC_MODE_32)
    mu.mem_map(0, 0x100000)
    mu.mem_map(0x2000000, 0x100000)
    mu.mem_write(0x10100, binary)
    done = []
    def out(uc, port, size, value, user):
        if port == 0x7ff0:
            done.append(value)
            uc.emu_stop()
    mu.hook_add(UC_HOOK_INSN, out, None, 1, 0, UC_X86_INS_OUT)
    mu.emu_start(0x10000 + pm32 + 10, 0, count=50_000_000)
    if done != [0x600d]:
        return None
    return bytes(mu.mem_read(LOG + (block - 1) * 32, 32))


runs = [0]
def failing(body):
    runs[0] += 1
    src = os.path.join(work, 'cand.asm')
    open(src, 'w', newline='\n').write(program(body))
    docker('cp', src, f'{container}:/work/cand.asm')
    r = docker('exec', container, 'bash', '-c',
               'cd /work && nasm -f bin cand.asm -o cand.bin && '
               './obj/Vz486_xms_resident_tb +program=/work/cand.bin +dump=/work/cand.dump >/work/cand.log 2>&1')
    if r.returncode != 0:
        return False
    docker('cp', f'{container}:/work/cand.bin', os.path.join(work, 'cand.bin'))
    docker('cp', f'{container}:/work/cand.dump', os.path.join(work, 'cand.dump'))
    binary = open(os.path.join(work, 'cand.bin'), 'rb').read()
    try:
        ref = reference(binary)
    except UcError:
        return False
    if ref is None:
        return False
    z = open(os.path.join(work, 'cand.dump'), 'rb').read()
    at = LOG - 0x40000 + (block - 1) * 32
    return z[at:at + 32] != ref


body = blocks[block - 1] + blocks[block]
assert failing(body), 'original pair does not reproduce'
n = 2
while len(body) >= 2:
    chunk = max(1, len(body) // n)
    reduced = False
    for i in range(0, len(body), chunk):
        cand = body[:i] + body[i + chunk:]
        if cand and failing(cand):
            body = cand
            n = max(n - 1, 2)
            reduced = True
            break
    if not reduced:
        if chunk == 1:
            break
        n = min(len(body), n * 2)
print(f'MINIMAL ({runs[0]} runs, block {block}):')
for l in body:
    print('   ', l)
open(os.path.join(work, 'minimal.asm'), 'w', newline='\n').write(program(body))
