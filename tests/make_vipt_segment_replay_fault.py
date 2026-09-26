"""A valid older replayed GS load followed immediately by a narrow FS load."""
from pathlib import Path
import subprocess,sys,tempfile,json
out=Path(sys.argv[1]);out.mkdir(exist_ok=True)
cases=[]
with tempfile.TemporaryDirectory() as tmp:
    subprocess.run([sys.executable,'tests/make_vipt_segment_cpu.py',tmp],check=True,stdout=subprocess.DEVNULL)
    for warm in ('cold','warm'):
        for mode in ('valid','outside'):
            for width in ('byte','dword'):
                s=(Path(tmp)/f'{warm}-dword-aligned-{mode}.asm').read_text()
                anchor='    mov edx,[gs:0x110f00]\nfault_instruction:'
                assert s.count(anchor)==1
                s=s.replace(anchor,f'    mov {width} [gs:0x110e00],0x5a\n'+anchor)
                if warm=='warm':
                    s=s.replace('    mov eax,[gs:0x00110100]\n','    mov eax,[gs:0x00110100]\n    mov eax,[gs:0x110f00]\n')
                name=f'replay-fault-{warm}-{mode}-{width}'
                (out/(name+'.asm')).write_text(s)
                cases.append(dict(name=name,expected_fault=mode=='outside',older='GS valid load must retire',younger='FS exact boundary or outside'))
(out/'cases.json').write_text(json.dumps(cases,indent=2))
print('Generated',len(cases),'precise younger fault/replay cases')
