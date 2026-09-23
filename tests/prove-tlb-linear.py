#!/usr/bin/env python3
"""Prove exact TLB address-register behavior, including faults, flush and hold.

Payloads and request qualifiers are arbitrary; only the mutually exclusive
state encodings are shared. The reference conditions are checked against the
real source so no changed qualifier can silently weaken the comparison.
"""
from pathlib import Path
import re
import subprocess
import tempfile

source = Path('rtl/vendor/ao486/memory/tlb.v').read_text()
legacy = Path('tests/reference/tlb-linear-legacy.vh').read_text()
for condition in re.findall(r'wire cond_\d+ =.*?;', legacy, re.S):
    assert condition in source, 'Original request qualifier changed: ' + condition
actual = source.split('// TLB_LINEAR_MUX_BEGIN', 1)[1].split('// TLB_LINEAR_MUX_END', 1)[0]
reference = re.search(r'wire \[31:0\] linear_to_reg =.*?;', legacy, re.S).group()
update = re.search(r'always @\(posedge clk\) begin\s*if\(rst_n == 1\'b0\) linear <=.*?\bend\b', source, re.S).group()
constants = '\n'.join(re.search(r'localparam \[4:0\] ' + n + r'\s*=.*?;', source).group()
                      for n in ['STATE_IDLE', 'STATE_WRITE_DOUBLE'])
state_conditions = '\n'.join(re.search(r'wire cond_' + str(i) + r' =.*?;', source, re.S).group() for i in [0, 9])
conditions = ','.join('cond_' + str(i) for i in [1, 2, 3, 4, 5, 6, 7, 8, 10])
ports = ('input clk,rst_n,input [4:0] state,input ' + conditions + ',\n'
         'input [31:0] tlbwrite_address,tlbcheck_address,tlbread_address,tlbcoderequest_address,write_double_linear,')

comb = ('module proof_comb(' + ports + 'input [31:0] linear,output equivalent);\n' +
        constants + '\n' + state_conditions + '\n' + actual + '\n' +
        reference.replace('linear_to_reg', 'legacy_next') + '\n' +
        'assign equivalent = (linear_load ? linear_to_reg : linear) == legacy_next;\nendmodule\n')
seq = ('module proof_seq(' + ports + 'output equivalent);\n' +
       constants + '\n' + state_conditions + '\nreg [31:0] linear,reference_linear;\n' +
       actual + '\n' + update + '\n' +
       re.sub(r'\blinear\b', 'reference_linear', reference.replace('linear_to_reg', 'reference_next')) + '\n' +
       "always @(posedge clk) if(!rst_n) reference_linear<=0; else reference_linear<=reference_next;\n" +
       'assign equivalent = linear == reference_linear;\nendmodule\n')


def prove(text, top, sequential=False, negative=False):
    with tempfile.TemporaryDirectory() as directory:
        path = Path(directory) / 'proof.sv'
        path.write_text(text)
        script = (f'read_verilog -sv {path}; prep -top {top} -flatten; opt; '
                  'sat -verify -prove equivalent 1 -show-inputs -show-outputs ')
        if sequential:
            script += '-seq 4 -tempinduct -set-init-zero'
        result = subprocess.run(['yosys', '-p', script], text=True, timeout=120,
                                stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
        if negative:
            assert result.returncode != 0 and 'proof did fail' in result.stdout, result.stdout
        else:
            assert result.returncode == 0 and 'SUCCESS' in result.stdout, result.stdout


prove(comb, 'proof_comb')
print('PASS: exact next address for every payload/state/flush/fault/request combination', flush=True)
prove(seq, 'proof_seq', sequential=True)
print('PASS: actual register update, reset and hold match by induction', flush=True)
for name, old, new in [
    ('missing write alignment check', '!cond_3 &&', "1'b1 &&"),
    ('missing read alignment check', '!cond_6 &&', "1'b1 &&"),
    ('wrong request priority', 'cond_0 && !cond_4 && cond_5;', 'cond_0 && cond_5;'),
    ('wrong next page', "+ 32'h00001000", "+ 32'h00002000"),
]:
    bad = comb.replace(old, new, 1)
    assert bad != comb, name
    prove(bad, 'proof_comb', negative=True)
    print('PASS: rejected ' + name, flush=True)
bad = seq.replace('else if(linear_load)', 'else if(1\'b1)', 1)
assert bad != seq
prove(bad, 'proof_seq', sequential=True, negative=True)
print('PASS: rejected lost register hold', flush=True)
