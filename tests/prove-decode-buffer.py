#!/usr/bin/env python3
"""Prove one-step equivalence for every possible instruction-buffer state.

Both machines start at zero and have identical clock/reset updates. Equality
of outputs and next state for arbitrary shared state establishes induction
without unrolling the 96-bit buffer through several copies of its shifters.
"""
from pathlib import Path
import re
import os
import subprocess
import tempfile

production = Path('rtl/vendor/ao486/pipeline/decode_regs.v').read_text()
reference = Path('tests/reference/decode_regs_legacy.v').read_text().replace(
    'module decode_regs(', 'module decode_regs_legacy(')

harness = '''
module proof(input clk, rst_n, dec_reset, consume_enabled,
             input [3:0] fetch_valid, prefix_count, consume_count,
             input [63:0] fetch, input [95:0] bytes,
             input [3:0] count, output equivalent);
wire [3:0] capacity, reference_capacity;
wire fetch_fits;
wire [99:0] next_state, reference_next_state;
decode_regs actual(.clk(clk), .rst_n(rst_n), .dec_reset(dec_reset),
    .fetch_valid(fetch_valid), .fetch(fetch), .prefix_count(prefix_count),
    .consume_count(consume_count), .consume_enabled(consume_enabled),
    .dec_acceptable(capacity), .decoder(bytes), .decoder_count(count),
    .dec_fetch_fits(fetch_fits),
    .next_state(next_state));
decode_regs_legacy expected(.clk(clk), .rst_n(rst_n), .dec_reset(dec_reset),
    .fetch_valid(fetch_valid), .fetch(fetch), .prefix_count(prefix_count),
    .consume_count(consume_enabled ? consume_count : 4'd0),
    .dec_acceptable(reference_capacity), .decoder(bytes), .decoder_count(count),
    .next_state(reference_next_state));
assign equivalent = capacity == reference_capacity &&
                    fetch_fits == (reference_capacity >= fetch_valid) &&
                    next_state == reference_next_state;
endmodule
'''


def combinational(source, legacy=False):
    head, sequential = source.split('always @(posedge clk)', 1)
    sequential = re.sub(r'//[^\n]*', '', sequential)
    sequential = re.sub(r'\s+', '', sequential)
    expected = (
        "beginif(rst_n==1'b0)decoder<=96'd0;elsedecoder<=decoder_next;end"
        "always@(posedgeclk)beginif(rst_n==1'b0)decoder_count<=4'd0;"
        "elseif(dec_reset)decoder_count<=4'd0;"
        "elsedecoder_count<=after_consume_count+accepted;endendmodule"
    ) if legacy else (
        "beginif(!rst_n)begindecoder<=96'd0;decoder_count<=4'd0;end"
        "elsebegindecoder<=selected_step[95:0];"
        "decoder_count<=selected_step[99:96];endendendmodule")
    assert sequential == expected, 'Clock/reset update changed; re-audit proof'
    head, replaced = re.subn(r'output\s+reg', 'input wire', head)
    assert replaced == 2
    head = head.replace('input wire', 'output [99:0] next_state,\n    input wire', 1)
    next_expression = (
        "{(dec_reset ? 4'd0 : (after_consume_count + accepted)), decoder_next}"
        if legacy else 'selected_step[99:0]')
    return head + 'assign next_state = !rst_n ? 100\'d0 : ' + next_expression + ';\nendmodule\n'


def prove(source, label, negative=False):
    with tempfile.TemporaryDirectory() as directory:
        path = Path(directory) / 'proof.v'
        path.write_text(combinational(source) + combinational(reference, True) + harness)
        vendor = Path(os.environ.get('INTEL_SIM_LIB', '/project/intel-sim')) / 'cyclonev_atoms.v'
        atom = re.search(r'module cyclonev_lcell_comb\s*\(.*?endmodule', vendor.read_text(), re.S).group()
        model = Path(directory) / 'atom.v'
        model.write_text(atom)
        commands = (
            'read_verilog -sv -DZET98_CYCLONEV_READY_MUX ' + str(model) + ' ' + str(path) + '; '
            'prep -top proof -flatten; opt; '
            'sat -verify -prove equivalent 1 -show-inputs -show-outputs')
        result = subprocess.run(['yosys', '-p', commands], text=True,
                                stdout=subprocess.PIPE,
                                stderr=subprocess.STDOUT, timeout=60)
        if negative:
            assert result.returncode != 0 and 'proof did fail' in result.stdout, (
                label, result.stdout[-5000:])
            print('PASS rejected negative control:', label)
        else:
            assert result.returncode == 0 and 'SUCCESS' in result.stdout, (
                label, result.stdout[-5000:])
            print('PASS arbitrary-state next-step equivalence:', label, flush=True)


def mutation(old, new):
    assert production.count(old) == 1, old
    return production.replace(old, new)


prove(production, 'all buffer bits, counts, acceptance, reset/stall/refill histories')
prove(mutation("(acceptable_1 < available) ? 4'd12",
               "(acceptable_1 < available) ? 4'd11"), 'wrong capacity', True)
prove(mutation('consume_enabled ? consume_step : stalled_step', 'consume_step').replace('.datac(consume_enabled)', ".datac(1'b1)"),
      'ignored stall', True)
prove(mutation("next_count = dec_reset ? 4'd0 :", "next_count = 1'b0 ? 4'd0 :"),
      'ignored decode reset', True)

assert production.count("64'hCACACACACACACACA") == 2
prove(production.replace("64'hCACACACACACACACA", "64'hACACACACACACACAC", 1), 'swapped FPGA mux arms', True)
prove(mutation('consume_step[103:100] >= fetch_valid',
               'consume_step[103:100] > fetch_valid'), 'full-fetch equality boundary', True)

# The new output must reach both fetch decisions through the actual instances.
pipeline = Path('rtl/vendor/ao486/pipeline/pipeline.v').read_text()
decode = Path('rtl/vendor/ao486/pipeline/decode.v').read_text()
fetch_source = Path('rtl/vendor/ao486/pipeline/fetch.v').read_text()
assert len(re.findall(r'\.dec_fetch_fits\s*\(dec_fetch_fits\)', pipeline)) == 2
assert len(re.findall(r'\.dec_fetch_fits\s*\(dec_fetch_fits\)', decode)) == 1
assert re.search(r'assign prefetchfifo_accept_do\s*= dec_fetch_fits &&', fetch_source)
assert re.search(r'assign partial\s*= !dec_fetch_fits &&', fetch_source)
