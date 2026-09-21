#!/usr/bin/env python3
"""Prove the real global_regs limit outputs equal the original descriptor decode."""
from pathlib import Path
import re
import subprocess
import tempfile

source = Path('rtl/vendor/ao486/global_regs.v').read_text()
inputs = re.findall(r'^\s*input\s+(\[[^\]]+\])?\s*(\w+)\s*[,\n]', source, re.M)
assert len(inputs) == 16
ports = ['input ' + (width or '') + ' ' + name for width, name in inputs]
connections = [f'.{name}({name})' for _, name in inputs]
connections += [f'.{name}({name})' for name in
                ('glob_descriptor', 'glob_descriptor_2', 'glob_desc_limit', 'glob_desc_2_limit')]
harness = '\n'.join([
    '`include "defines.v"',
    'module limit_proof(' + ',\n'.join(ports + ['output equivalent']) + ');',
    'wire [63:0] glob_descriptor, glob_descriptor_2;',
    'wire [31:0] glob_desc_limit, glob_desc_2_limit;',
    'global_regs dut(' + ',\n'.join(connections) + ');',
    # Independent original expressions, not the optimized helper function.
    'wire [31:0] expected = glob_descriptor[`DESC_BIT_G] ? '
    '{glob_descriptor[51:48],glob_descriptor[15:0],12\'hfff} : '
    '{12\'d0,glob_descriptor[51:48],glob_descriptor[15:0]};',
    'wire [31:0] expected_2 = glob_descriptor_2[`DESC_BIT_G] ? '
    '{glob_descriptor_2[51:48],glob_descriptor_2[15:0],12\'hfff} : '
    '{12\'d0,glob_descriptor_2[51:48],glob_descriptor_2[15:0]};',
    'assign equivalent = glob_desc_limit == expected && glob_desc_2_limit == expected_2;',
    'endmodule',
])


def prove(candidate, negative=False):
    with tempfile.TemporaryDirectory() as folder:
        path = Path(folder)
        (path / 'global_regs.v').write_text(candidate)
        (path / 'proof.v').write_text(harness)
        script = (f'read_verilog -sv -Irtl/vendor/ao486 {path}/global_regs.v {path}/proof.v; '
                  'prep -top limit_proof -flatten; opt; '
                  'sat -verify -prove equivalent 1 -seq 4 -tempinduct -set-init-zero '
                  '-show-inputs -show-outputs')
        result = subprocess.run(['yosys', '-p', script], text=True,
                                stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
        if negative:
            assert result.returncode != 0 and 'proof did fail' in result.stdout, result.stdout
        else:
            assert result.returncode == 0 and 'SUCCESS' in result.stdout, result.stdout


prove(source)
print('PASS: actual descriptor-limit registers equal original decode for arbitrary reset, updates and holds')
bad = source.replace('expanded_global_limit(glob_descriptor_value)',
                     'expanded_global_limit(glob_descriptor)')
assert bad != source
prove(bad, negative=True)
print('PASS: one-cycle-old descriptor value rejected with a counterexample')
bad = source.replace("descriptor_2_limit_cached <= 32'd0;",
                     'descriptor_2_limit_cached <= descriptor_2_limit_cached;')
assert bad != source
prove(bad, negative=True)
print('PASS: missing second-limit reset rejected with a counterexample')
