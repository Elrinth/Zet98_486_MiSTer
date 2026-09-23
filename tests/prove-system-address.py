#!/usr/bin/env python3
"""Prove actual system-address mux for every command, input and shared state."""
from pathlib import Path
import re, subprocess, tempfile
wrapper = Path('rtl/vendor/ao486/pipeline/read_commands.v').read_text()
body = Path('rtl/vendor/ao486/autogen/read_commands.v').read_text()
legacy = Path('tests/reference/read-system-linear-legacy.vh').read_text()
reference = re.search(r'assign rd_system_linear =.*?;', legacy, re.S).group()
reference = reference.replace('rd_system_linear', 'reference_address', 1)
# The sole state register feeds both expressions identically. Proving its
# next-state input for every arbitrary value also preserves all histories.
assert len(re.findall(r'^reg ', body, re.M)) == 1
body = body.replace('reg [31:0] rd_task_switch_linear_reg;',
                    'wire [31:0] rd_task_switch_linear_reg = arbitrary_task_state;')
body, count = re.subn(r'always @\(posedge clk\) begin.*?\bend\b', '', body, flags=re.S)
assert count == 1
wrapper = wrapper.replace('module read_commands(', 'module system_address_proof(', 1)
wrapper = wrapper.replace('\n);', ',\n input [31:0] arbitrary_task_state, output equivalent\n);', 1)
source = wrapper.replace('`include "autogen/read_commands.v"', body + '\nwire [31:0] reference_address;\n' + reference + '\nassign equivalent = rd_system_linear == reference_address;')
with tempfile.TemporaryDirectory() as folder:
    path = Path(folder) / 'proof.v'
    script = f'read_verilog -sv -Irtl/vendor/ao486 {path}; prep -top system_address_proof -flatten; opt; sat -verify -prove equivalent 1 -show-inputs -show-outputs'
    for negative in (False, True):
        candidate = source.replace('({32{cond_33}}', '({32{cond_35}}', 1) if negative else source
        assert not negative or candidate != source
        path.write_text(candidate)
        result = subprocess.run(['yosys', '-p', script], capture_output=True, text=True, timeout=120)
        log = result.stdout + result.stderr
        if negative:
            assert result.returncode != 0 and 'proof did fail' in log, log
            print('PASS wrong system-address selector rejected')
        else:
            assert result.returncode == 0 and 'SUCCESS' in log, log
            print('PASS parallel system-address mux equals original priority decoder for all inputs/state')
