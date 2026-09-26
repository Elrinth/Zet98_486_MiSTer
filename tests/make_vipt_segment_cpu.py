"""Self-authored precise #GP/direct-load boundary tests, no game/BIOS data."""
from pathlib import Path
import sys, json

out = Path(sys.argv[1]); out.mkdir(exist_ok=True)
kernel = Path('tests/hardware/pm_crc_window.inc').read_text()
cases = []
# Ending exactly at a limit must succeed; crossing by one and starting beyond
# it must fault. Nonzero segment bases distinguish offsets from linear addresses.
ops = [('byte', 1, 'mov bl,byte [fs:esi]'),
       ('word', 2, 'mov bx,word [fs:esi]'),
       ('dword', 4, 'mov ebx,dword [fs:esi]'),
       ('zxbyte', 1, 'movzx ebx,byte [fs:esi]'),
       ('sxword', 2, 'movsx ebx,word [fs:esi]'),
       ('adddword', 4, 'add ebx,dword [fs:esi]')]
ops = [(name,width,instruction,layout) for name,width,instruction in ops
       for layout in ('aligned','unaligned','addr16','pages')]
for warm in (False, True):
    for name, width, instruction, layout in ops:
        for mode in ('valid', 'cross', 'outside'):
            if width == 1 and mode == 'cross': continue
            offset = 0x100 if layout == 'aligned' else 0x103
            limit = offset + width - 1 if mode == 'valid' else offset + width - 2 if mode == 'cross' else offset - 1
            if layout == 'pages':
                limit = 0xfff
                offset = 0x1000-width if mode == 'valid' else 0x1001-width if mode == 'cross' else 0x1000
            if layout == 'addr16': instruction = instruction.replace('[fs:esi]', '[fs:si]')
            base = 0x110000
            payload = bytes(((a*37+(a>>8)+(a>>16))&255) for a in range(base+offset, base+offset+width))
            value = int.from_bytes(payload, 'little')
            if name == 'byte': value |= 0x76543200
            elif name == 'word': value |= 0x76540000
            elif name == 'sxword' and value & 0x8000: value |= 0xffff0000
            elif name == 'adddword': value = (value + 0x76543210) & 0xffffffff
            expected_fault = mode != 'valid'
            label = '{}-{}-{}-{}'.format('warm' if warm else 'cold',name,layout,mode)
            body = f'    mov esi,0x{offset | (0xbeef0000 if layout == "addr16" else 0):08x}\n'
            body += '''
    mov ebx,0x76543210
    mov dword [observed_faults],0
    mov dword [after_marker],0
    mov ax,30h
    mov gs,ax
'''
            if warm:
                # Flat GS warms identical physical bytes without using tested FS.
                body += f'    mov eax,[gs:0x{base+offset:08x}]\n'
            body += '''    mov eax,[safe_value]
    cmp eax,0x13572468
    jne test_fail
    mov al,7fh
    add al,1
    stc
    pushfd
    pop edi
    ; Adjacent valid load uses a different descriptor and destination.
    mov edx,[gs:0x110f00]
fault_instruction:
    ''' + instruction + '''
after_instruction:
    mov dword [after_marker],0x1234
resume_check:
'''
            body += f'    mov ebp,201\n    cmp dword [observed_faults],{int(expected_fault)}\n    jne test_fail\n'
            body += f'    mov ebp,202\n    cmp ebx,0x{(0x76543210 if expected_fault else value):08x}\n    jne test_fail\n'
            body += f'    mov ebp,203\n    cmp dword [after_marker],{0 if expected_fault else 0x1234}\n    jne test_fail\n'
            neighbor = int.from_bytes(bytes((a*37+(a>>8)+(a>>16))&255 for a in range(0x110f00,0x110f04)), 'little')
            body += f'    mov ebp,204\n    cmp edx,0x{neighbor:08x}\n    jne test_fail\n'
            body += '''    mov eax,[safe_value]
    cmp eax,0x13572468
    jne test_fail
    jmp word 18h:pm_exit16
test_fail:
    mov eax,[observed_faults]
    mov ecx,[after_marker]
    mov dx,7fe0h
    out dx,ax
    mov byte [pm_fault],2
    jmp word 18h:pm_exit16
'''
            handler = '''pm_exception:
    mov ebp,301
    cmp dword [esp],0
    jne test_fail
    mov ebp,302
    mov eax,[esp+4]
    cmp dword [esp+4],fault_instruction
    jne test_fail
    mov ebp,303
    cmp dword [esp+8],8
    jne test_fail
    mov ebp,304
    cmp ebx,0x76543210
    jne test_fail
    mov ebp,305
    mov eax,[esp+12]
    and eax,8d5h
    and edi,8d5h
    cmp eax,edi
    jne test_fail
    inc dword [observed_faults]
    mov dword [esp+4],resume_check
    add esp,4
    iretd
'''
            k = kernel
            start = k.index('    mov esi,[pm_address]')
            end = k.index('bits 16\npm_exit16:', start)
            k = k[:start] + body + handler + k[end:]
            k = k.replace('pm_gdtr: dw', '    dq 00cf92000000ffffh ; independent flat GS\npm_gdtr: dw')
            setup = ['bits 16','cpu 386','org 100h','cli','cld','mov ax,cs','mov ds,ax','mov es,ax','mov ss,ax','mov sp,0fef0h',
                     'xor al,al','out 0f2h,al','call pm_initialize',
                     # Only #GP has the test handler; other exceptions go to a
                     # fail gate so #NP/#SS cannot masquerade as the expected #GP.
                     'mov di,pm_idt','mov cx,32','set_gates:','mov word [di],unexpected_exception','add di,8','loop set_gates',
                     'mov word [pm_idt+13*8],pm_exception',
                     f'mov word [pm_gdt+40],{0 if layout == "pages" else limit}',
                     'mov word [pm_gdt+42],0','mov byte [pm_gdt+44],11h',
                     f'mov byte [pm_gdt+46],{0xc0 if layout == "pages" else 0x40}',
                     'mov dword [pm_length],1','call pm_window','cmp byte [pm_fault],0','jne fail',
                     'cmp sp,0fef0h','jne fail','smsw ax','test al,1','jnz fail',
                     'mov ax,600dh','jmp report','fail:','mov ax,0deadh','report:','mov dx,7ff0h','out dx,ax','hlt','jmp $']
            suffix = '''
bits 32
unexpected_exception:
    mov ebp,401
    mov dx,7fe0h
    out dx,ax
    mov byte [pm_fault],3
    jmp word 18h:pm_exit16
bits 16
observed_faults: dd 0
after_marker: dd 0
safe_value: dd 13572468h
'''
            (out/(label+'.asm')).write_text('\n'.join(setup)+'\n'+k+suffix)
            cases.append(dict(name=label,expected_fault=expected_fault,width=width,limit=limit,offset=offset,layout=layout))
(out/'cases.json').write_text(json.dumps(cases,indent=2))
print('Generated',len(cases),'precise boundary cases')
