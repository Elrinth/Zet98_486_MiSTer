"""Sweep instruction placement after real store/load traffic; no internal forces."""
from pathlib import Path
import subprocess,sys,tempfile,json
out=Path(sys.argv[1]);out.mkdir(exist_ok=True)
cases=[]
with tempfile.TemporaryDirectory() as tmp:
    subprocess.run([sys.executable,'tests/make_vipt_segment_cpu.py',tmp],check=True,stdout=subprocess.DEVNULL)
    for mode in ('valid','outside'):
        for padding in range(16):
            s=(Path(tmp)/f'cold-dword-aligned-{mode}.asm').read_text()
            anchor='    mov edx,[gs:0x110f00]\nfault_instruction:'
            assert s.count(anchor)==1
            group='    mov dword [gs:0x110e00],0x5a\n    mov ecx,[fs:esi-16]\n    mov edx,[gs:0x110f00]\n'
            sequence=group*3+f'    times {padding} nop\n    mov dword [gs:0x110e00],0x5a\n'+anchor
            s=s.replace(anchor,sequence)
            name=f'replay-alignment-{mode}-{padding:02d}'
            (out/(name+'.asm')).write_text(s)
            cases.append(dict(name=name,expected_fault=mode=='outside',padding=padding,prelude_groups=3))
(out/'cases.json').write_text(json.dumps(cases,indent=2))
print('Generated',len(cases),'instruction-placement cases; natural replay/rejection coverage is separate')
