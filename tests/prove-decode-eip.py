#!/usr/bin/env python3
"""Prove the production decode EIP update against full-width arithmetic."""
from pathlib import Path
import subprocess
import tempfile

source = Path('rtl/vendor/ao486/pipeline/decode.v').read_text()
block = source.split('//------------------------------------------------------------------------------ eip\n', 1)[1]
block = block.split('//------------------------------------------------------------------------------', 1)[0]
assert 'always @(posedge clk)' in block and 'assign dec_eip' in block


def check(actual, negative=False):
    harness = '''`include "defines.v"
module proof(input clk, rst_n, pr_reset, dec_ready,
             input [31:0] prefetch_eip, input [3:0] dec_consumed,
             output equivalent);
reg [31:0] eip;
wire [31:0] dec_eip;
''' + actual + '''
reg [31:0] reference_eip;
always @(posedge clk) begin
    if (!rst_n) reference_eip <= `STARTUP_EIP;
    else if (pr_reset) reference_eip <= prefetch_eip;
    else if (dec_ready) reference_eip <= reference_eip + {28'b0, dec_consumed};
end
assign equivalent = eip == reference_eip &&
                    dec_eip == reference_eip + {28'b0, dec_consumed};
endmodule
'''
    with tempfile.TemporaryDirectory() as directory:
        path = Path(directory) / 'proof.v'
        path.write_text(harness)
        script = ('read_verilog -sv -Irtl/vendor/ao486 ' + str(path) + '; '
                  'prep -top proof -flatten; opt; '
                  'sat -verify -prove equivalent 1 -seq 4 -tempinduct '
                  '-set-init-zero -set-at 1 rst_n 0 -show-inputs -show-outputs')
        result = subprocess.run(['yosys', '-p', script], text=True, timeout=60,
                                stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
        if negative:
            assert result.returncode != 0 and 'proof did fail' in result.stdout, result.stdout
        else:
            assert result.returncode == 0 and 'SUCCESS' in result.stdout, result.stdout


check(block)
print('PASS: all EIP values, lengths 0..15, wraparound, resets, redirects and stalls')
for name, old, new in (
        ('wrong carry bit', 'dec_eip_low[4]', 'dec_eip_low[3]'),
        ('missing high increment', "eip[31:4] + 28'd1", "eip[31:4] + 28'd0"),
        ('lost redirect priority', 'else if(pr_reset)', 'else if(pr_reset && !dec_ready)')):
    assert old in block
    check(block.replace(old, new), negative=True)
    print('PASS: rejected ' + name)
