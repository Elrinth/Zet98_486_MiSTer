"""Prove early write-stage completion decoding without changing flush/stall timing."""
from pathlib import Path
import re
import subprocess
import tempfile

root = Path('rtl/vendor/ao486')
source = (root/'pipeline/write.v').read_text()
module = (root/'pipeline/write_commands.v').read_text()
generated = (root/'autogen/write_commands.v').read_text()
function = re.search(r'function \[20:0\] write_finish_decode;.*?endfunction', source, re.S).group()
assert len(re.findall(r'write_finish_decode\[\d+\] =', function)) == 21
legacy = Path('tests/reference/write_finish_legacy.vh').read_text()
for condition in re.findall(r'wire cond_\d+ = [^;]+;', legacy):
    assert condition in generated, 'Original dynamic/opcode condition changed'
reference = generated
for block in re.findall(r'assign (wr_not_finished) =\s*([^;]+);', legacy):
    reference = re.sub(r'assign '+block[0]+r' =\s*[^;]+;',
                       lambda m: 'assign '+block[0]+' = '+block[1]+';', reference)
assert 'wr_finish_select[' not in reference
reference_module = module.replace('module write_commands(', 'module write_commands_reference(').replace(
    '`include "autogen/write_commands.v"', reference)
inputs = re.findall(r'^\s*input\s+(\[[^\]]+\])?\s*(\w+)\s*[,\n]', module, re.M)
inputs = [(w, n) for w, n in inputs if n != 'wr_finish_select']
assert len(inputs) > 40
outputs = ['wr_not_finished']
for name in outputs:
    expression = re.search(r'assign '+name+r' =\s*([^;]+);', generated).group(1)
    assert 'wr_finish_select[' in expression, 'Regeneration dropped completion selection: ' + name
connections = [f'.{n}({n})' for w, n in inputs] + ['.wr_finish_select(wr_finish_select)']
comb = '\n'.join([
    '`include "defines.v"',
    'module reset_comb(' + ','.join('input '+(w or '')+' '+n for w, n in inputs) + ',output equivalent);',
    function,
    'wire [20:0] wr_finish_select = write_finish_decode(wr_cmd, wr_cmdex);',
    'wire [0:0] actual, reference;',
    'write_commands dut(' + ','.join(connections + [f'.{n}(actual[{i}])' for i, n in enumerate(outputs)]) + ');',
    'write_commands_reference refdut(' + ','.join(connections + [f'.{n}(reference[{i}])' for i, n in enumerate(outputs)]) + ');',
    'assign equivalent = actual == reference;',
    'endmodule', reference_module,
])
blocks = re.findall(r'always @\(posedge clk\) begin.*?\bend\b', source, re.S)
updates = []
for name in ('wr_cmd', 'wr_cmdex', 'wr_finish_select'):
    found = [b for b in blocks if re.search(r'\b' + name + r'\s*<=', b)]
    assert len(found) == 1, name
    updates += found
assert '.wr_finish_select (wr_finish_select)' in source
seq = '\n'.join([
    '`include "defines.v"',
    'module reset_seq(input clk,rst_n,wr_reset,w_load,wr_ready,',
    'input [6:0] exe_cmd,input [3:0] exe_cmdex,output equivalent);',
    'reg [6:0] wr_cmd; reg [3:0] wr_cmdex; reg [20:0] wr_finish_select;',
    function, *updates,
    'assign equivalent = wr_finish_select == write_finish_decode(wr_cmd,wr_cmdex);',
    'endmodule',
])

def prove(text, top, sequential=False, negative=False):
    with tempfile.TemporaryDirectory() as folder:
        p = Path(folder)/'proof.sv'
        p.write_text(text)
        script = (f'read_verilog -sv -I{root} {root}/pipeline/write_commands.v {p}; '
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

prove(comb, 'reset_comb')
print('PASS write-stage completion output match original decoder for every input')
bad = comb.replace('write_finish_decode(wr_cmd, wr_cmdex);', "write_finish_decode(wr_cmd, wr_cmdex) ^ 21'd1;")
assert bad != comb
prove(bad, 'reset_comb', negative=True)
print('PASS wrong opcode selector rejected')
prove(seq, 'reset_seq', sequential=True)
print('PASS induction: flags track actual command through reset, flush, load, retire and hold')
bad = seq.replace("else if(wr_reset) wr_finish_select <= 21'd0;", "else if(1'b0) wr_finish_select <= 21'd0;")
assert bad != seq
prove(bad, 'reset_seq', sequential=True, negative=True)
print('PASS missing selector flush rejected')
