#!/usr/bin/env python3
"""Prove ECX flag alignment and equivalence of the actual string unit."""
from pathlib import Path
import re
import subprocess
import tempfile

registers = Path('rtl/vendor/ao486/pipeline/write_register.v').read_text()
string_unit = Path('rtl/vendor/ao486/pipeline/write_string.v').read_text()
reference = Path('tests/reference/write_string_before_ecx_flags.v').read_text()


def ports(source, direction):
    return re.findall(r'^\s*' + direction + r'\s+(?:reg\s+)?(\[[^\]]+\])?\s*(\w+)\s*[,\n]', source, re.M)


def declarations(items):
    return ['input ' + (width or '') + ' ' + name for width, name in items]


def check(files, harness, sequential=False, negative=False):
    with tempfile.TemporaryDirectory() as directory:
        root = Path(directory)
        names = []
        for name, content in dict(files, harness=harness).items():
            path = root / (name + '.v')
            path.write_text(content)
            names.append(str(path))
        script = ('read_verilog -sv -Irtl/vendor/ao486 ' + ' '.join(names) + '; '
                  'prep -top proof -flatten; opt; '
                  'sat -verify -prove equivalent 1 ')
        if sequential:
            script += '-seq 4 -tempinduct -set-init-zero -set-at 1 rst_n 0 '
        script += '-show-inputs -show-outputs'
        result = subprocess.run(['yosys', '-p', script], text=True, timeout=120,
                                stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
        if negative:
            assert result.returncode != 0 and 'proof did fail' in result.stdout, result.stdout
        else:
            assert result.returncode == 0 and 'SUCCESS' in result.stdout, result.stdout


register_inputs = ports(registers, 'input')
assert len(register_inputs) > 100
register_connections = [f'.{name}({name})' for _, name in register_inputs]
register_connections += ['.ecx(ecx)', '.ecx_count_flags(flags)']
register_harness = '\n'.join([
    'module proof(' + ',\n'.join(declarations(register_inputs) + ['output equivalent']) + ');',
    'wire [31:0] ecx; wire [3:0] flags;',
    'write_register dut(' + ','.join(register_connections) + ');',
    # The first transition is reset. Don't assert architectural state before it.
    "reg started = 0; always @(posedge clk) started <= 1'b1;",
    "assign equivalent = !started || flags == {ecx == 32'd1, ecx[15:0] == 16'd1, "
    "ecx == 32'd0, ecx[15:0] == 16'd0};",
    'endmodule',
])
check({'registers': registers}, register_harness, sequential=True)
print('PASS: real ECX flags track partial/full/general/internal writes and repeated reset for arbitrary inputs')
bad = registers.replace('ecx_count_next == ', 'ecx == ').replace('ecx_count_next[15:0]', 'ecx[15:0]')
check({'registers': bad}, register_harness, sequential=True, negative=True)
print('PASS: one-cycle-old count flags rejected')
bad = registers.replace("!rst_n ? `STARTUP_ECX :", '')
check({'registers': bad}, register_harness, sequential=True, negative=True)
print('PASS: missing count-flag reset rejected')
bad = registers.replace("ecx_count_next == 32'd0", "ecx_count_next[15:0] == 16'd0")
check({'registers': bad}, register_harness, sequential=True, negative=True)
print('PASS: ignoring ECX high bits rejected')

string_inputs = ports(reference, 'input')
string_outputs = ports(reference, 'output')
assert len(string_outputs) == 8
connections = [f'.{name}({name})' for _, name in string_inputs]
lines = ['module proof(' + ',\n'.join(declarations(string_inputs) + ['output equivalent']) + ');',
         "wire [3:0] flags = {ecx == 32'd1, ecx[15:0] == 16'd1, ecx == 32'd0, ecx[15:0] == 16'd0};"]
for prefix in ('actual', 'original'):
    lines += ['wire ' + (width or '') + ' ' + prefix + '_' + name + ';' for width, name in string_outputs]
    output_connections = [f'.{name}({prefix}_{name})' for _, name in string_outputs]
    if prefix == 'actual':
        lines += ['write_string dut(' + ','.join(connections + output_connections + ['.ecx_count_flags(flags)']) + ');']
    else:
        lines += ['write_string_reference ref_dut(' + ','.join(connections + output_connections) + ');']
lines += ['assign equivalent = ' + ' && '.join(f'actual_{name} == original_{name}' for _, name in string_outputs) + ';', 'endmodule']
string_harness = '\n'.join(lines)
check({'actual': string_unit, 'original': reference}, string_harness)
print('PASS: all eight actual string-unit outputs match the original for arbitrary counts, sizes, REP, flags and segments')
bad = string_unit.replace('ecx_count_flags[1]', 'ecx_count_flags[0]')
check({'actual': bad, 'original': reference}, string_harness, negative=True)
print('PASS: wrong 32-bit address-size predicate rejected')
