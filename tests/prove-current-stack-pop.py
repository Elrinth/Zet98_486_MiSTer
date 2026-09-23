#!/usr/bin/env python3
"""Prove stack predecode against the real decoder and command-register updates.

The combinational proof leaves every decoder input unconstrained. The temporal
induction proof checks arbitrary reset, flush, load, ready and command inputs.
Requires Yosys (tests/Dockerfile.formal); run from the repository root.
"""
from pathlib import Path
import re
import subprocess
import tempfile

source = Path('rtl/vendor/ao486/pipeline/read.v').read_text()
commands = Path('rtl/vendor/ao486/pipeline/read_commands.v').read_text()
function = re.search(r'function \[1:0\] stack_pop_decode;.*?endfunction', source, re.S).group()
expression = re.search(r'assign address_stack_pop\s*=([^;]+);', source).group(1)
instance = source.split('read_commands read_commands_inst(', 1)[1].split(');', 1)[0]
assert re.search(r'\.address_stack_pop\s*\(address_stack_pop_reference\)', instance)
inputs = re.findall(r'^\s*input\s+(\[[^\]]+\])?\s*(\w+)\s*[,\n]', commands, re.M)
assert len(inputs) > 40
ports = ['input ' + (width or '') + ' ' + name for width, name in inputs]
connections = [f'.{name}({name})' for _, name in inputs]
connections += ['.address_stack_pop(reference)']
comb = '\n'.join([
    '`include "defines.v"',
    'module predecode_comb(' + ',\n'.join(ports + ['output equivalent']) + ');',
    function,
    'wire reference;',
    'wire [1:0] stack_pop_flags = stack_pop_decode(rd_cmd, rd_cmdex);',
    'wire actual = ' + expression + ';',
    'read_commands decoder(' + ',\n'.join(connections) + ');',
    'assign equivalent = actual == reference;',
    'endmodule',
])
blocks = re.findall(r'always @\(posedge clk\) begin.*?\bend\b', source, re.S)
registers = ['rd_cmd', 'rd_cmdex', 'stack_pop_flags']
updates = []
for register in registers:
    found = [block for block in blocks if re.search(r'\b' + register + r'\s*<=', block)]
    assert len(found) == 1, register
    updates.append(found[0])
seq = '\n'.join([
    '`include "defines.v"',
    'module predecode_seq(input clk, rst_n, rd_reset, r_load, rd_ready,',
    'input [6:0] micro_cmd, input [3:0] micro_cmdex, output equivalent);',
    'reg [6:0] rd_cmd; reg [3:0] rd_cmdex; reg [1:0] stack_pop_flags;',
    function, *updates,
    'assign equivalent = stack_pop_flags == stack_pop_decode(rd_cmd, rd_cmdex);',
    'endmodule',
])


def prove(text, top, sequential=False, negative=False):
    with tempfile.TemporaryDirectory() as folder:
        path = Path(folder) / 'proof.sv'
        path.write_text(text)
        script = (f'read_verilog -sv -Irtl/vendor/ao486 '
                  f'rtl/vendor/ao486/pipeline/read_commands.v {path}; '
                  f'prep -top {top} -flatten; opt; '
                  'sat -verify -prove equivalent 1 -show-inputs -show-outputs ')
        if sequential:
            script += '-seq 4 -tempinduct -set-init-zero'
        result = subprocess.run(['yosys', '-p', script], stdout=subprocess.PIPE,
                                stderr=subprocess.STDOUT, text=True)
        if negative:
            assert result.returncode != 0 and 'proof did fail' in result.stdout, result.stdout
        else:
            assert result.returncode == 0 and 'SUCCESS' in result.stdout, result.stdout


prove(comb, 'predecode_comb')
print('PASS stack predecode equals actual decoder for every input combination')
bad_comb = comb.replace('&& (real_mode || v8086_mode)', '|| (real_mode || v8086_mode)')
assert bad_comb != comb
prove(bad_comb, 'predecode_comb', negative=True)
print('PASS wrong real/v8086-mode gating rejected with a counterexample')
prove(seq, 'predecode_seq', sequential=True)
print('PASS temporal induction for actual command/flag reset, load, ready and hold updates')
bad_update = updates[2].replace('else if(rd_reset)', "else if(1'b0)")
assert bad_update != updates[2]
prove(seq.replace(updates[2], bad_update), 'predecode_seq', sequential=True, negative=True)
print('PASS missing flag flush rejected with a counterexample')
