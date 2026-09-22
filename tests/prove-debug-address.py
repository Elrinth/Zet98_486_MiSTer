#!/usr/bin/env python3
"""Prove the production breakpoint sum comparison, including low-bit masks."""
from pathlib import Path
import re
import subprocess
import tempfile

source = Path('rtl/vendor/ao486/pipeline/write_debug.v').read_text()
block = source.split('// BEGIN PC98 DEBUG SUM MATCH\n', 1)[1]
block = block.split('// END PC98 DEBUG SUM MATCH', 1)[0]
triggers = []
for index in range(4):
    match = re.search(r'assign wr_debug_b%d_code_trigger\s*=\s*(.*?);' % index,
                      source, re.S)
    assert match, index
    triggers.append(match.group(0))


def check(actual, negative=False):
    harness = '''module proof(
    input [31:0] cs_base, wr_eip, dr0, dr1, dr2, dr3, dr7,
    input [2:0] debug_len0, debug_len1, debug_len2, debug_len3,
    input wr_debug_code_trigger,
    output equivalent);
''' + actual + '''
wire [31:0] reference_sum = cs_base + wr_eip;
wire wr_debug_b0_code_trigger, wr_debug_b1_code_trigger;
wire wr_debug_b2_code_trigger, wr_debug_b3_code_trigger;
''' + '\n'.join(triggers)
    checks = []
    for i in range(4):
        mask = "{29'h1fffffff,debug_len%d}" % i
        checks.append('''(wr_debug_b%d_code_trigger ==
            (wr_debug_code_trigger && dr7[%d:%d] == 2'b00 &&
             (dr%d & %s) == (reference_sum & %s)))''' %
                      (i, 17+4*i, 16+4*i, i, mask, mask))
    harness += '\nassign equivalent = ' + ' &&\n'.join(checks) + ';\nendmodule\n'
    with tempfile.TemporaryDirectory() as directory:
        path = Path(directory) / 'proof.v'
        path.write_text(harness)
        script = ('read_verilog -sv ' + str(path) + '; '
                  'prep -top proof -flatten; opt; '
                  'sat -verify -prove equivalent 1 -show-inputs -show-outputs')
        result = subprocess.run(['yosys', '-p', script], text=True, timeout=60,
                                stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
        if negative:
            assert result.returncode != 0 and 'proof did fail' in result.stdout, result.stdout
        else:
            assert result.returncode == 0 and 'SUCCESS' in result.stdout, result.stdout


check(block)
print('PASS: all 32-bit bases, offsets and four breakpoint addresses, '
      'all low-bit masks, wraparound, trigger and DR7 gates')
for name, old, new in (
        ('lost carry from low bits', 'expected_carry[3] == low_sum[3]', "expected_carry[3] == 1'b0"),
        ('wrong carry propagation', '(base[30:3] | offset[30:3])', '(base[30:3] & offset[30:3])'),
        ('ignored low mask', '(low_sum[2:0] & low_mask)', 'low_sum[2:0]'),
        ('ignored upper address bit', 'expected_carry[31:4] == generated_carry', 'expected_carry[30:4] == generated_carry[29:3]')):
    assert old in block
    check(block.replace(old,new), negative=True)
    print('PASS: rejected ' + name)
