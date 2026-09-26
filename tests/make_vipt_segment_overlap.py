"""Adjacent load token ownership; test software and data are self-authored."""
from pathlib import Path
import subprocess,sys,tempfile,json
out=Path(sys.argv[1]);out.mkdir(exist_ok=True)
cases=[]
with tempfile.TemporaryDirectory() as tmp:
    subprocess.run([sys.executable,'tests/make_vipt_segment_cpu.py',tmp],check=True,stdout=subprocess.DEVNULL)
    for warm in ('cold','warm'):
        for order in ('fs-first','gs-first'):
            s=(Path(tmp)/f'{warm}-dword-aligned-valid.asm').read_text()
            value=int.from_bytes(bytes((a*37+(a>>8)+(a>>16))&255 for a in range(0x110100,0x110104)),'little')
            anchor='    mov edx,[gs:0x110f00]\nfault_instruction:'
            assert s.count(anchor)==1
            pair='    mov ecx,[fs:esi]\n    mov edx,[gs:0x110f00]\n' if order=='fs-first' else '    mov edx,[gs:0x110f00]\n    mov ecx,[fs:esi]\n'
            s=s.replace(anchor,pair+'fault_instruction:')
            anchor='resume_check:\n'
            s=s.replace(anchor,anchor+f'    mov ebp,205\n    cmp ecx,0x{value:08x}\n    jne test_fail\n')
            if warm:
                s=s.replace('    mov eax,[gs:0x00110100]\n','    mov eax,[gs:0x00110100]\n    mov eax,[gs:0x110f00]\n')
            name=f'overlap-{warm}-{order}'
            (out/(name+'.asm')).write_text(s)
            cases.append(dict(name=name,coverage='adjacent FS narrow-limit and GS flat loads; all destinations checked; trace determines actual overlap'))
(out/'cases.json').write_text(json.dumps(cases,indent=2))
print('Generated',len(cases),'adjacent-token cases; do not infer overlap without trace')
