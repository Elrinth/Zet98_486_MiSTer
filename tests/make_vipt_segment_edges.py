"""Additional actual-CPU edge tests; previous 128 cases are templates, not rerun."""
from pathlib import Path
import subprocess, sys, tempfile, json, re

out=Path(sys.argv[1]); out.mkdir(exist_ok=True)
cases=[]
def replace(s,a,b):
    assert s.count(a)==1, (a,s.count(a))
    return s.replace(a,b)
def emit(name,s,coverage):
    (out/(name+'.asm')).write_text(s)
    cases.append(dict(name=name,coverage=coverage))

with tempfile.TemporaryDirectory() as tmp:
    subprocess.run([sys.executable,'tests/make_vipt_segment_cpu.py',tmp],check=True,stdout=subprocess.DEVNULL)
    templates=Path(tmp)
    # 32-bit effective offset overflow must fault before the wrapped linear
    # access or any destination/flags/younger-store effect. No high-memory reads.
    for op,width in [('word',2),('dword',4),('adddword',4),('sxword',2)]:
        for over in range(1,width):
            s=(templates/f'cold-{op}-aligned-cross.asm').read_text()
            s=replace(s,'mov esi,0x00000100',f'mov esi,0x{0x100000000-width+over:08x}')
            s=re.sub(r'mov word \[pm_gdt\+40\],\d+', 'mov word [pm_gdt+40],65535', s, count=1)
            s=replace(s,'mov byte [pm_gdt+44],11h','mov byte [pm_gdt+44],0')
            s=replace(s,'mov byte [pm_gdt+46],64','mov byte [pm_gdt+46],207')
            emit(f'overflow-{op}-{over}',s,'4GB offset wrap, exact #GP and precise state')

    # Stack-segment limits, with sufficient valid stack space for #SS delivery.
    # Data at CS:FFFB..FFFF is untouched zero-filled RAM in this independent TB.
    for op,width in [('byte',1),('word',2),('dword',4),('zxbyte',1),('sxword',2),('adddword',4)]:
        for mode in ('valid','cross','outside'):
            if width==1 and mode=='cross': continue
            s=(templates/f'cold-{op}-aligned-{mode}.asm').read_text()
            offset=0xffff-width if mode=='valid' else 0x10000-width if mode=='cross' else 0xffff
            s=replace(s,'mov esi,0x00000100',f'mov esi,0x{offset:08x}')
            s=replace(s,'[fs:esi]','[ss:esi]')
            s=replace(s,'mov word [pm_idt+13*8],pm_exception','mov word [pm_idt+12*8],pm_exception')
            s=replace(s,'mov dword [pm_length],1','mov word [pm_gdt+16],65534\nmov dword [pm_length],1')
            if mode=='valid':
                value=0x76543200 if op=='byte' else 0x76540000 if op=='word' else 0x76543210 if op=='adddword' else 0
                s=re.sub(r'(mov ebp,202\n    cmp ebx,)0x[0-9a-f]+',r'\g<1>0x%08x'%value,s,count=1)
            emit(f'ss-{op}-{mode}',s,'SS limit, vector12, precise state and IRETD')

    # Reload FS from a changed descriptor immediately before the access.
    # The old cache entry and old hidden descriptor must not qualify the new one.
    for warm in ('cold','warm'):
        for mode in ('restrict','relax','base'):
            s=(templates/f'{warm}-dword-aligned-{"outside" if mode=="restrict" else "valid"}.asm').read_text()
            if mode=='restrict':
                s=replace(s,'mov word [pm_gdt+40],255','mov word [pm_gdt+40],65535')
                update='mov word [pm_gdt+40],255'
            elif mode=='relax':
                s=replace(s,'mov word [pm_gdt+40],259','mov word [pm_gdt+40],255')
                update='mov word [pm_gdt+40],259'
            else:
                update='mov byte [pm_gdt+44],12h'
                value=int.from_bytes(bytes((a*37+(a>>8)+(a>>16))&255 for a in range(0x120100,0x120104)),'little')
                s=re.sub(r'(mov ebp,202\n    cmp ebx,)0x[0-9a-f]+',r'\g<1>0x%08x'%value,s,count=1)
            s=replace(s,'fault_instruction:\n',update+'\n    mov ax,28h\n    mov fs,ax\nfault_instruction:\n')
            emit(f'reload-{warm}-{mode}',s,'FS descriptor reload: limit shrink/grow or changed base')

(out/'cases.json').write_text(json.dumps(cases,indent=2))
print('Generated',len(cases),'NEW edge cases; previous128 not executed')
