#!/usr/bin/env python3
"""Prove the actual CPU command logic preserves the segment-check length.

All read_commands inputs are unconstrained: the proof covers every command,
subcommand, mutex state, descriptor, mode and operand/address size. Source
expressions are extracted from read.v so changes cannot leave a stale miter.
Requires Yosys; run from the repository root in tests/Dockerfile.formal.
"""
from pathlib import Path
import re
import subprocess
import tempfile

source = Path('rtl/vendor/ao486/pipeline/read.v').read_text()
commands = Path('rtl/vendor/ao486/pipeline/read_commands.v').read_text()
inputs = re.findall(r'^\s*input\s+(\[[^\]]+\])?\s*(\w+)\s*[,\n]', commands, re.M)
assert len(inputs) > 40
ports = ['input ' + (width or '') + ' ' + name for width, name in inputs]
ports += ['input rd_is_8bit', 'output equivalent']
outputs = ['read_virtual', 'read_rmw_virtual', 'write_virtual_check',
           'read_system_word', 'read_system_dword', 'read_system_qword',
           'read_rmw_system_dword', 'read_system_descriptor',
           'read_length_word', 'read_length_dword']
connections = [f'.{name}({name})' for _, name in inputs]
connections += [f'.{name}({name})' for name in outputs]
lengths = []
for name in ('read_length', 'segment_read_length'):
    match = re.search(r'\b' + name + r'\s*=\s*([^;]+);', source)
    assert match, name
    lengths.append('wire [3:0] ' + name + ' = ' + match[1] + ';')
segment_instance = source.split('read_segment read_segment_inst(', 1)[1].split(');', 1)[0]
assert re.search(r'\.read_length\s*\(segment_read_length\)', segment_instance)
miter = '\n'.join([
    'module segment_length_proof(' + ',\n'.join(ports) + ');',
    'wire ' + ', '.join(outputs) + ';',
    'read_commands decoder(' + ',\n'.join(connections) + ');',
    *lengths,
    'assign equivalent = !(read_virtual || read_rmw_virtual || write_virtual_check)',
    '                    || read_length == segment_read_length;',
    'endmodule',
])
with tempfile.TemporaryDirectory() as folder:
    top = Path(folder) / 'proof.sv'
    top.write_text(miter)
    script = (f'read_verilog -sv -Irtl/vendor/ao486 '
              f'rtl/vendor/ao486/pipeline/read_commands.v {top}; '
              'prep -top segment_length_proof -flatten; opt; '
              'sat -verify -prove equivalent 1 -show-inputs -show-outputs')
    subprocess.run(['yosys', '-p', script], check=True)
    # A wrong byte-access length must produce a real counterexample; this
    # also guards against a vacuous proof caused by disconnected controls.
    bad_length = lengths[1].replace("4'd1", "4'd2", 1)
    assert bad_length != lengths[1]
    top.write_text(miter.replace(lengths[1], bad_length))
    bad = subprocess.run(['yosys', '-p', script], stdout=subprocess.PIPE,
                         stderr=subprocess.STDOUT, text=True)
    assert bad.returncode != 0 and 'proof did fail' in bad.stdout, bad.stdout
print('PASS: segment-check length equivalent for all command inputs')
print('PASS: wrong byte-access length rejected with a counterexample')
