#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
"""Generate tests/hardware/cmpxchg_xadd_probe.asm (486 CMPXCHG and XADD).

Every case loads all six general registers, a data dword and the arithmetic
flags, runs one CMPXCHG/XADD (8/16/32-bit, register and memory, equal and
not equal, LOCK, 16- and 32-bit addressing) and compares every full 32-bit
register, the data dword and the six arithmetic flags with this script's
reference model. Some cases put a dependent instruction right behind the
486 instruction (flag, register, address and store forwarding). Real mode,
org 1000h, same harness as cache_insn_probe.asm: port 7FE4h prints the
registers (EBP = failing case number), 7FF0h gets 600Dh.

    make_cmpxchg_xadd_probe.py [out.asm]
    make_cmpxchg_xadd_probe.py --unicorn probe.bin   # check the model
"""
import random
import sys

MEM = 0x8010                   # data dword (DS = 2000h)
RESULT = 0x8040                # flags after the instruction
FLAGS_MASK = 0x8D5             # OF SF ZF AF PF CF
GPRS = ['eax', 'ebx', 'ecx', 'edx', 'esi', 'edi']
BYTE_REGS = {'al': ('eax', 0), 'bl': ('ebx', 0), 'cl': ('ecx', 0), 'dl': ('edx', 0),
             'ah': ('eax', 8), 'bh': ('ebx', 8), 'ch': ('ecx', 8), 'dh': ('edx', 8)}


def mask(size):
    return (1 << (size * 8)) - 1


def flags_of(a, b, r, size, sub):
    m, s = mask(size), 1 << (size * 8 - 1)
    f = 0
    if sub:
        if a < b: f |= 1
        if (a ^ b) & (a ^ r) & s: f |= 0x800
    else:
        if a + b > m: f |= 1
        if ~(a ^ b) & (a ^ r) & s: f |= 0x800
    if (a ^ b ^ r) & 0x10: f |= 0x10
    if r == 0: f |= 0x40
    if r & s: f |= 0x80
    if bin(r & 0xFF).count('1') % 2 == 0: f |= 0x4
    return f


class State:
    def __init__(self, regs, mem):
        self.r = dict(regs)
        self.mem = mem

    def get(self, name, size):
        if size == 1:
            full, sh = BYTE_REGS[name]
            return (self.r[full] >> sh) & 0xFF
        full = name if size == 4 else 'e' + name
        return self.r[full] & mask(size)

    def set(self, name, size, v):
        if size == 1:
            full, sh = BYTE_REGS[name]
            self.r[full] = (self.r[full] & ~(0xFF << sh)) | ((v & 0xFF) << sh)
        else:
            full = name if size == 4 else 'e' + name
            self.r[full] = (self.r[full] & ~mask(size)) | (v & mask(size))


def acc(size):
    return {1: 'al', 2: 'ax', 4: 'eax'}[size]


def model(st, op, size, dst, src, ofs):
    """Execute one instruction on st (dst None = memory); return the flags."""
    m = mask(size)
    def rd():
        return (st.mem >> (ofs * 8)) & m if dst is None else st.get(dst, size)
    def wr(v):
        if dst is None:
            st.mem = (st.mem & ~(m << (ofs * 8))) | ((v & m) << (ofs * 8))
        else:
            st.set(dst, size, v)
    d, s = rd(), st.get(src, size)
    if op == 'xadd':
        r = (d + s) & m
        f = flags_of(d, s, r, size, False)
        st.set(src, size, d)
        wr(r)
        return f
    a = st.get(acc(size), size)
    f = flags_of(a, d, (a - d) & m, size, True)
    if a == d:
        wr(s)
    else:
        wr(d)                  # the 486 always writes the destination
        st.set(acc(size), size, d)
    return f


def gen():
    rnd = random.Random(486)
    lines = []
    count = [0]

    def case(op, size, dst, src, regs, mem, flags_in, ofs=0, ea=None,
             lock=False, follow=None):
        """ea = (address expression, {register: value} it needs);
        follow = (instructions, model update, flags still checked)."""
        count[0] += 1
        regs = dict(regs)
        if ea:
            regs.update(ea[1])
        st = State(regs, mem)
        flags = model(st, op, size, dst, src, ofs)
        width = {1: 'byte', 2: 'word', 4: 'dword'}[size]
        target = dst if dst else width + ' ' + ea[0]
        insn = ('lock ' if lock else '') + op + ' ' + target + ',' + src
        lines.append('; case %d: %s' % (count[0], insn))
        lines.append('mov dword [0x%x],0x%08x' % (MEM, mem))
        lines.extend('mov %s,0x%08x' % (k, regs[k]) for k in GPRS)
        lines.extend(['push word 0x%04x' % (0x2 | flags_in), 'popf', insn])
        if follow:
            lines.extend(follow[0])
            follow[1](st)
        lines.extend(['pushf', 'pop word [0x%x]' % RESULT, 'mov ebp,%d' % count[0]])
        for k in GPRS:
            lines.extend(['cmp %s,0x%08x' % (k, st.r[k]), 'jne fail'])
        lines.extend(['cmp dword [0x%x],0x%08x' % (MEM, st.mem), 'jne fail'])
        if not follow or follow[2]:
            lines.extend(['mov ax,[0x%x]' % RESULT, 'and ax,0x%x' % FLAGS_MASK,
                          'cmp ax,0x%x' % flags, 'jne fail'])

    def rregs():
        return {k: rnd.getrandbits(32) for k in GPRS}

    def put(regs, name, size, v):
        st = State(regs, 0)
        st.set(name, size, v)
        return st.r

    def pairs(size):
        m, s = mask(size), 1 << (size * 8 - 1)
        out = [(0, 0), (1, m), (s - 1, 1), (s, s), (m, m), (0x0F, 0x01),
               (s, 1), (1, s), (0x12, 0x12), (m, 0)]
        return out + [(rnd.getrandbits(size * 8), rnd.getrandbits(size * 8))
                      for _ in range(3)]

    def memval(x, size, ofs):
        return (rnd.getrandbits(32) & ~(mask(size) << (ofs * 8))) | (x << (ofs * 8))

    names_by_size = {4: ['eax', 'ebx', 'ecx', 'edx', 'esi', 'edi'],
                     2: ['ax', 'bx', 'cx', 'dx', 'si', 'di'],
                     1: ['al', 'bl', 'cl', 'dl', 'ah', 'bh', 'ch', 'dh']}
    for size in (1, 2, 4):
        names = names_by_size[size]
        a = acc(size)
        no_ea = [n for n in names if n not in ('si', 'di', 'esi', 'edi')]
        ea16 = lambda ofs: ('[si+0x%x]' % (MEM + ofs - 0x7000), {'esi': 0x7000})
        ea32 = lambda ofs: ('[esi+edi*2+0x%x]' % (MEM + ofs - 0x7100),
                            {'esi': 0x7000, 'edi': 0x80})
        for i, (x, y) in enumerate(pairs(size)):
            fl = (0x000, 0x8D5)[i % 2]
            # XADD r,r (two distinct registers, any of the byte halves).
            dst, src = rnd.sample([n for n in names if n != a], 2)
            case('xadd', size, dst, src, put(put(rregs(), dst, size, x), src, size, y),
                 rnd.getrandbits(32), fl)
            # XADD m,r, 16- and 32-bit addresses, any offset inside the dword.
            for ea in (ea16, ea32):
                ofs = rnd.randrange(0, 5 - size)
                src = rnd.choice(no_ea)
                case('xadd', size, None, src, put(rregs(), src, size, y),
                     memval(x, size, ofs), fl ^ 0x8D5, ofs, ea=ea(ofs),
                     lock=(i % 3 == 0))
            for equal in (True, False):
                acc_v = x if equal else (y if y != x else (y + 1) & mask(size))
                # CMPXCHG r,r.
                dst, src = rnd.sample([n for n in names if n != a], 2)
                regs = put(put(rregs(), dst, size, x), a, size, acc_v)
                case('cmpxchg', size, dst, src, regs, rnd.getrandbits(32), fl)
                # CMPXCHG m,r.
                for ea in (ea16, ea32):
                    src = rnd.choice([n for n in no_ea if n != a])
                    ofs = rnd.randrange(0, 5 - size)
                    case('cmpxchg', size, None, src, put(rregs(), a, size, acc_v),
                         memval(x, size, ofs), fl ^ 0x8D5, ofs, ea=ea(ofs),
                         lock=(i % 2 == 1))
        # Operand overlaps.
        x = rnd.getrandbits(size * 8)
        case('xadd', size, a, a, put(rregs(), a, size, x), 0, 0)
        case('xadd', size, names[1], names[1], put(rregs(), names[1], size, x), 0, 0x8D5)
        case('cmpxchg', size, a, names[1], put(rregs(), a, size, x), 0, 0)
        case('cmpxchg', size, names[2], a, put(rregs(), names[2], size, x), 0, 0)
        case('cmpxchg', size, names[2], a,
             put(put(rregs(), names[2], size, x), a, size, x), 0, 0x8D5)
        if size == 1:
            case('cmpxchg', 1, 'ah', 'bh', put(put(rregs(), 'ah', 1, x), 'al', 1, x), 0, 0)
            case('cmpxchg', 1, 'ah', 'al', put(rregs(), 'ah', 1, x), 0, 0)
            case('xadd', 1, 'ah', 'al', rregs(), 0, 0)
        else:
            # The source register is the address register.
            sname = 'si' if size == 2 else 'esi'
            case('xadd', size, None, sname, rregs(), rnd.getrandbits(32), 0, ea=ea16(0))
            case('cmpxchg', size, None, sname, rregs(), rnd.getrandbits(32), 0, ea=ea16(0))

    # Dependent instructions directly behind the 486 instruction.
    def setzc(zf, cf):
        def update(st):
            st.set('cl', 1, zf)
            st.set('ch', 1, cf)
        return (['setz cl', 'setc ch'], update, True)
    def nothing(st):
        pass
    def addsrc(st):
        st.r['edi'] = (st.r['ebx'] + st.r['ecx']) & 0xFFFFFFFF
    def eaxcopy(st):
        st.r['edi'] = st.r['eax']
    def memcopy(st):
        st.r['edi'] = st.mem
    mem_ea = ('[0x%x]' % MEM, {})
    load_mem = ['mov edi,[0x%x]' % MEM]
    def regs_with(**kw):
        r = rregs()
        r.update(kw)
        return r
    case('cmpxchg', 4, 'ebx', 'edx', regs_with(eax=0x1234, ebx=0x1234), 0, 0, follow=setzc(1, 0))
    case('cmpxchg', 4, 'ebx', 'edx', regs_with(eax=0x1233, ebx=0x1234), 0, 0x8D5, follow=setzc(0, 1))
    case('cmpxchg', 4, None, 'edx', regs_with(eax=0x55), 0x55, 0, ea=mem_ea, follow=setzc(1, 0))
    case('cmpxchg', 4, None, 'edx', regs_with(eax=0x56), 0x55, 0x8D5, ea=mem_ea, follow=setzc(0, 0))
    case('cmpxchg', 4, None, 'edx', regs_with(eax=0x56), 0x55, 0, ea=mem_ea,
         follow=(['jz fail'], nothing, True))
    case('cmpxchg', 4, None, 'edx', regs_with(eax=0x55), 0x55, 0, ea=mem_ea,
         follow=(['jnz fail'], nothing, True))
    case('cmpxchg', 1, 'bl', 'dl', regs_with(eax=0x55, ebx=0x56), 0, 0,
         follow=(['jz fail'], nothing, True))
    add_follow = (['mov edi,ebx', 'add edi,ecx'], addsrc, False)
    case('xadd', 4, 'ecx', 'ebx', rregs(), 0, 0, follow=add_follow)
    case('xadd', 4, None, 'ebx', rregs(), 0x11223344, 0, ea=mem_ea, follow=add_follow)
    case('cmpxchg', 4, None, 'ebx', regs_with(eax=7), 0x99, 0, ea=mem_ea,
         follow=(['mov edi,eax'], eaxcopy, True))
    case('cmpxchg', 4, 'ecx', 'ebx', regs_with(eax=7), 0x99, 0,
         follow=(['mov edi,eax'], eaxcopy, True))
    case('cmpxchg', 4, None, 'ebx', regs_with(eax=0xCAFE), 0xCAFE, 0, ea=mem_ea,
         follow=(load_mem, memcopy, True))
    case('cmpxchg', 4, None, 'ebx', regs_with(eax=0xCAFF), 0xCAFE, 0, ea=mem_ea,
         follow=(load_mem, memcopy, True))
    case('xadd', 4, None, 'ebx', rregs(), 0x01020304, 0, ea=mem_ea,
         follow=(load_mem, memcopy, True))
    case('xadd', 4, 'ecx', 'esi', regs_with(ecx=0x10), 0x5A5A5A5A, 0,
         follow=(['mov edi,[si+0x%x]' % (MEM - 0x10)], memcopy, True))
    # Delay-slot register writes (old memory value) feed the next address.
    def ea_load(addr_reg):
        def update(st):
            st.r['edi'] = st.mem
        return (['mov edi,[%s+0x%x]' % (addr_reg, MEM - 0x10)], update, True)
    case('xadd', 4, None, 'esi', rregs(), 0x10, 0, ea=mem_ea, follow=ea_load('si'))
    case('cmpxchg', 4, None, 'ebx', regs_with(eax=0x11), 0x10, 0, ea=mem_ea,
         follow=ea_load('eax'))
    case('cmpxchg', 2, None, 'bx', regs_with(eax=0x11), 0x10, 0, ea=mem_ea,
         follow=ea_load('eax'))
    lines.extend([
        '; LOCK CMPXCHG increment loop (spin-lock shape) and LOCK XADD counter',
        'mov ebp,999', 'mov dword [0x%x],100' % MEM, 'mov cx,5', '.again:',
        'mov eax,[0x%x]' % MEM, '.retry:', 'lea edx,[eax+1]',
        'lock cmpxchg [0x%x],edx' % MEM, 'jnz .retry', 'loop .again',
        'cmp dword [0x%x],105' % MEM, 'jne fail', 'cmp eax,104', 'jne fail',
        'mov ebx,1', 'mov eax,10', 'mov [0x%x],eax' % MEM,
        'lock xadd [0x%x],ebx' % MEM, 'lock xadd [0x%x],ebx' % MEM,
        'cmp ebx,11', 'jne fail', 'cmp dword [0x%x],21' % MEM, 'jne fail'])
    return lines, count[0]


HEAD = """; SPDX-License-Identifier: GPL-3.0-or-later
; Generated by tests/make_cmpxchg_xadd_probe.py; do not edit.
; 486 CMPXCHG (0F B0/B1) and XADD (0F C0/C1) in real mode: {n} cases of
; registers, memory and arithmetic flags against the generator's model, plus
; LOCK CMPXCHG/XADD loops. An INT 06h (#UD) handler fails the run.
; Port 7FE4h prints the registers (EBP = case number); 7FF0h gets 600Dh.
bits 16
cpu 586                         ; NASM files CMPXCHG under the Pentium
org 1000h
cli
xor ax,ax
mov ds,ax
mov word [6*4],ud_handler
mov word [6*4+2],0
mov ax,2000h                    ; data at 20000h, stack at 3xxxxh
mov ds,ax
mov ax,3000h
mov ss,ax
mov sp,0fff0h
"""
TAIL = """mov ax,600dh
jmp report
ud_handler:
mov ebp,0ffffh
fail:
mov dx,7fe4h
out dx,ax
mov ax,0deadh
report:
mov dx,7ff0h
out dx,ax
hlt
jmp $
"""


def run_unicorn(path):
    from unicorn import Uc, UC_ARCH_X86, UC_MODE_16, UC_HOOK_INSN
    from unicorn.x86_const import UC_X86_INS_OUT, UC_X86_REG_EBP, UC_X86_REG_SP
    mu = Uc(UC_ARCH_X86, UC_MODE_16)
    mu.mem_map(0, 0x100000)
    mu.mem_write(0x1000, open(path, 'rb').read())
    mu.reg_write(UC_X86_REG_SP, 0x8000)
    seen = []
    def out(uc, port, size, value, user):
        seen.append((port, value, uc.reg_read(UC_X86_REG_EBP)))
        if port == 0x7ff0:
            uc.emu_stop()
    mu.hook_add(UC_HOOK_INSN, out, None, 1, 0, UC_X86_INS_OUT)
    mu.emu_start(0x1000, 0, count=10000000)
    if not seen or seen[-1][:2] != (0x7ff0, 0x600d):
        sys.exit('FAIL: Unicorn disagrees with the model %r' % seen)
    print('PASS: Unicorn runs the probe to 600Dh (model matches)')


if __name__ == '__main__':
    if len(sys.argv) == 3 and sys.argv[1] == '--unicorn':
        run_unicorn(sys.argv[2])
        sys.exit(0)
    body, n = gen()
    path = sys.argv[1] if len(sys.argv) > 1 else 'tests/hardware/cmpxchg_xadd_probe.asm'
    open(path, 'w', newline='\n').write(HEAD.format(n=n) + '\n'.join(body) + '\n' + TAIL)
    print('%s: %d cases' % (path, n))
