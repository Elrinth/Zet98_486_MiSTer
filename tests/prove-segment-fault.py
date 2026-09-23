#!/usr/bin/env python3
"""All-input equivalence of the segment checker, including invalid selectors.

Compare every output against the frozen pre-optimization module; no descriptor,
address, command-control or length input is constrained. Negative controls must
produce counterexamples for lost stack priority and changed fault boundaries.
"""
from pathlib import Path
import re
import subprocess
import tempfile

source = Path('rtl/vendor/ao486/pipeline/read_segment.v').read_text()
reference = Path('tests/reference/read_segment_before_fault_mux.v').read_text()
ports = re.findall(r'^\s*(input|output)\s+(\[[^\]]+\])?\s*(\w+)\s*[,\n]', source, re.M)
assert len(ports) == 34, len(ports)
inputs = [(width or '', name) for direction, width, name in ports if direction == 'input']
outputs = [(width or '', name) for direction, width, name in ports if direction == 'output']
assert len(outputs) == 7
top = ['module segment_proof(' + ','.join('input '+w+' '+n for w,n in inputs) + ',output equivalent);']
for prefix in ['old','new']:
    top += ['wire '+w+' '+prefix+'_'+n+';' for w,n in outputs]
    connections = ['.'+n+'('+n+')' for _,n in inputs]
    connections += ['.'+n+'('+prefix+'_'+n+')' for _,n in outputs]
    top += [('read_segment_reference' if prefix == 'old' else 'read_segment') + ' '+prefix+'_inst('+','.join(connections)+');']
top += ['assign equivalent = ' + ' && '.join('(old_'+n+' == new_'+n+')' for _,n in outputs) + ';', 'endmodule']

def prove(candidate, negative=False):
    with tempfile.TemporaryDirectory() as directory:
        folder = Path(directory)
        (folder/'reference.v').write_text(reference.replace('module read_segment(', 'module read_segment_reference(', 1))
        (folder/'candidate.v').write_text(candidate)
        (folder/'top.v').write_text('\n'.join(top))
        script = f'read_verilog -sv -Irtl/vendor/ao486 {folder}/reference.v {folder}/candidate.v {folder}/top.v; '
        script += 'prep -top segment_proof -flatten; opt; sat -verify -prove equivalent 1 -show-inputs -show-outputs'
        result = subprocess.run(['yosys','-p',script], capture_output=True, text=True)
        log = result.stdout + result.stderr
        if negative:
            assert result.returncode != 0 and 'proof did fail' in log, log
        else:
            assert result.returncode == 0 and 'SUCCESS' in log, log

prove(source)
print('PASS segment checker: all seven outputs equivalent for every input combination', flush=True)
bad = source.replace('stack_select ? ss_fault : address_edi ? es_fault : prefix_fault',
                     'address_edi ? es_fault : stack_select ? ss_fault : prefix_fault')
assert bad != source
prove(bad, negative=True)
print('PASS incorrect ES-over-stack priority rejected', flush=True)
bad = source.replace('available < {1\'b0, length}', 'available <= {1\'b0, length}')
assert bad != source
prove(bad, negative=True)
print('PASS off-by-one segment boundary rejected', flush=True)
