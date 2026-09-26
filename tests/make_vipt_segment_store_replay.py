"""Exercise ordinary store/load sequences, including a precise younger fault."""
from pathlib import Path
import subprocess, sys, tempfile, json

out=Path(sys.argv[1]); out.mkdir(exist_ok=True)
cases=[]
with tempfile.TemporaryDirectory() as tmp:
    subprocess.run([sys.executable,'tests/make_vipt_segment_cpu.py',tmp],check=True,stdout=subprocess.DEVNULL)
    for warm in ('cold','warm'):
        for mode in ('valid','outside'):
            for width in ('byte','dword'):
                for order in ('fs-first','gs-first'):
                    s=(Path(tmp)/f'{warm}-dword-aligned-{mode}.asm').read_text()
                    pair=['    mov ecx,[fs:esi-16]','    mov edx,[gs:0x110f00]']
                    if order=='gs-first': pair.reverse()
                    store=f'    mov {width} [gs:0x110e00],0x5a\n'
                    sequence=store+'\n'.join(pair)+'\n'
                    anchor='    mov edx,[gs:0x110f00]\nfault_instruction:'
                    assert s.count(anchor)==1
                    # Three real store/load groups prime and exercise the path.
                    s=s.replace(anchor,sequence*3+'fault_instruction:')
                    value=int.from_bytes(bytes((a*37+(a>>8)+(a>>16))&255 for a in range(0x1100f0,0x1100f4)),'little')
                    checks=f'    mov ebp,205\n    cmp ecx,0x{value:08x}\n    jne test_fail\n'
                    checks+=f'    mov ebp,206\n    cmp {width} [gs:0x110e00],0x5a\n    jne test_fail\n'
                    s=s.replace('resume_check:\n','resume_check:\n'+checks)
                    if warm=='warm':
                        s=s.replace('    mov eax,[gs:0x00110100]\n','    mov eax,[gs:0x00110100]\n    mov eax,[gs:0x1100f0]\n    mov eax,[gs:0x110f00]\n')
                    name=f'store-{warm}-{mode}-{width}-{order}'
                    (out/(name+'.asm')).write_text(s)
                    cases.append(dict(name=name,expected_fault=mode=='outside',store_width=width,order=order))
(out/'cases.json').write_text(json.dumps(cases,indent=2))
print('Generated',len(cases),'store/load cases; replay/overlap require measured trace')
