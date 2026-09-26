"""Test a null FS selector after replacing a previously full-range FS."""

from pathlib import Path
import json
import re
import subprocess
import sys
import tempfile


out = Path(sys.argv[1])
out.mkdir(parents=True, exist_ok=False)
cases = []
with tempfile.TemporaryDirectory() as scratch:
    subprocess.run([sys.executable, 'tests/make_vipt_segment_cpu.py', scratch],
                   check=True, stdout=subprocess.DEVNULL)
    for op, suffix in [('byte', 'outside'), ('dword', 'cross')]:
        source = (Path(scratch) / f'cold-{op}-aligned-{suffix}.asm').read_text()
        source, changed = re.subn(r'mov word \[pm_gdt\+40\],\d+',
                                  'mov word [pm_gdt+40],65535', source, count=1)
        assert changed == 1
        assert source.count('mov byte [pm_gdt+46],64') == 1
        source = source.replace('mov byte [pm_gdt+46],64',
                                'mov byte [pm_gdt+46],207')
        assert source.count('fault_instruction:\n') == 1
        source = source.replace('fault_instruction:\n',
                                '    mov ax,0\n    mov fs,ax\nfault_instruction:\n')
        name = f'null-fs-after-flat-{op}'
        (out / f'{name}.asm').write_text(source)
        cases.append({'name': name, 'expected': 'precise #GP at load; no direct admission'})
(out / 'cases.json').write_text(json.dumps(cases, indent=2))
print('Generated two null-FS-after-flat cases')
