#!/usr/bin/env python3
"""Prove RF and stack-width controls plus their actual pipeline lifetime.

All decoder inputs remain arbitrary. The sequential proof uses the source's
real command/substep/selector updates, including simultaneous flush/load/retire.
Wrong opcode, missing flush and wrong load priority must produce counterexamples.
"""
from pathlib import Path
import re
import subprocess
import tempfile

root = Path('rtl/vendor/ao486')
source = (root / 'pipeline/write.v').read_text()
module = (root / 'pipeline/write_commands.v').read_text()
generated = (root / 'autogen/write_commands.v').read_text()
legacy = Path('tests/reference/write_control_legacy.vh').read_text()
function = re.search(r'function \[9:0\] write_control_decode;.*?endfunction', source, re.S).group()
outputs = ['rflag_to_reg', 'wr_push_length_word', 'wr_push_length_dword']
for condition in re.findall(r'wire cond_\d+ = [^;]+;', legacy):
    assert condition in generated, 'Original opcode/operand condition changed'
reference = generated
for name in outputs:
    expression = re.search(r'assign ' + name + r' =.*?;', legacy, re.S).group()
    reference, count = re.subn(r'assign ' + name + r' =.*?;', lambda m: expression, reference, flags=re.S)
    assert count == 1
assert '.wr_control_select (wr_control_select)' in source
reference_module = module.replace('module write_commands(', 'module write_commands_reference(', 1).replace(
    '`include "autogen/write_commands.v"', reference)
inputs = re.findall(r'^\s*input\s+(\[[^\]]+\])?\s*(\w+)\s*[,\n]', module, re.M)
inputs = [(width or '', name) for width, name in inputs if name != 'wr_control_select']
assert len(inputs) > 40
connections = [f'.{name}({name})' for _, name in inputs] + ['.wr_control_select(wr_control_select)']
comb = '\n'.join([
    '`include "defines.v"',
    'module control_comb(' + ','.join('input ' + w + ' ' + n for w, n in inputs) + ',output equivalent);',
    function,
    'wire [9:0] wr_control_select = write_control_decode(wr_cmd, wr_cmdex);',
    'wire [2:0] actual, reference;',
    'write_commands dut(' + ','.join(connections + [f'.{n}(actual[{i}])' for i, n in enumerate(outputs)]) + ');',
    'write_commands_reference refdut(' + ','.join(connections + [f'.{n}(reference[{i}])' for i, n in enumerate(outputs)]) + ');',
    'assign equivalent = actual == reference;',
    'endmodule', reference_module,
])
blocks = re.findall(r'always @\(posedge clk\) begin.*?\bend\b', source, re.S)
updates = []
for name in ['wr_cmd', 'wr_cmdex', 'wr_control_select']:
    found = [b for b in blocks if re.search(r'\b' + name + r'\s*<=', b)]
    assert len(found) == 1, name
    updates += found
seq = '\n'.join([
    '`include "defines.v"',
    'module control_seq(input clk,rst_n,wr_reset,w_load,wr_ready,',
    'input [6:0] exe_cmd,input [3:0] exe_cmdex,output equivalent);',
    'reg [6:0] wr_cmd; reg [3:0] wr_cmdex; reg [9:0] wr_control_select;',
    function, *updates,
    'assign equivalent = wr_control_select == write_control_decode(wr_cmd,wr_cmdex);',
    'endmodule',
])


def prove(text, top, sequential=False, negative=False):
    with tempfile.TemporaryDirectory() as directory:
        path = Path(directory) / 'proof.sv'
        path.write_text(text)
        script = (f'read_verilog -sv -I{root} {root}/pipeline/write_commands.v {path}; '
                  f'prep -top {top} -flatten; opt; '
                  'sat -verify -prove equivalent 1 -show-inputs -show-outputs ')
        if sequential:
            script += '-seq 4 -tempinduct -set-init-zero'
        result = subprocess.run(['yosys', '-p', script], text=True, timeout=120,
                                stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
        if negative:
            assert result.returncode != 0 and 'proof did fail' in result.stdout, result.stdout
        else:
            assert result.returncode == 0 and 'SUCCESS' in result.stdout, result.stdout


prove(comb, 'control_comb')
print('PASS: RF and both stack-width controls match original decoder for every input', flush=True)
bad = comb.replace('write_control_decode(wr_cmd, wr_cmdex);', "write_control_decode(wr_cmd, wr_cmdex) ^ 10'd64;")
assert bad != comb
prove(bad, 'control_comb', negative=True)
print('PASS: wrong stack-width selector rejected', flush=True)
prove(seq, 'control_seq', sequential=True)
print('PASS: induction through reset, flush, load, retire, and hold', flush=True)
bad_update = updates[2].replace('else if(wr_reset)', "else if(1'b0)")
assert bad_update != updates[2]
prove(seq.replace(updates[2], bad_update), 'control_seq', sequential=True, negative=True)
print('PASS: missing selector flush rejected', flush=True)
bad_update = updates[2].replace('else if(w_load)', 'else if(w_load && !wr_ready)')
assert bad_update != updates[2]
prove(seq.replace(updates[2], bad_update), 'control_seq', sequential=True, negative=True)
print('PASS: wrong simultaneous load/retire priority rejected', flush=True)
