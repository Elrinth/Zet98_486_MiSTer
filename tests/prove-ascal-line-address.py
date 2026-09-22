#!/usr/bin/env python3
"""Synthesize actual scaler wiring with GHDL; prove its register contract with Yosys.

--prepare DIR and --prove DIR may run in separate toolchain containers.
The reference is modular subtraction plus the original line-bank rotation.
"""
import argparse
from pathlib import Path
import subprocess


def run(command, directory=None):
    result = subprocess.run(command, cwd=directory, text=True, timeout=90,
                            stdout=subprocess.PIPE, stderr=subprocess.PIPE)
    if result.returncode:
        raise RuntimeError(result.stdout + result.stderr)
    return result.stdout


def prepare(directory):
    directory.mkdir(parents=True, exist_ok=True)
    scaler = Path('MiSTer/sys/ascal.vhd').read_text()
    wiring = scaler.split('  LINE_ADDRESS :', 1)[1].split('  -- Vertical Scaler', 1)[0]
    wiring = '  LINE_ADDRESS :' + wiring
    assert 'address3 => o_radl3' in wiring
    wrapper = '''library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
entity proof_address is
    generic (OHRES : natural := 2048);
    port (o_clk, o_ce : in std_logic;
          o_vfrac : in unsigned(11 downto 0);
          o_vacptl : in unsigned(1 downto 0);
          o_hcpt, o_hmin, o_v_hmin_adj : in natural range 0 to 4095;
          o_radl0,o_radl1,o_radl2,o_radl3 : out natural range 0 to 4095);
end entity;
architecture rtl of proof_address is begin
''' + wiring + 'end architecture;\n'
    (directory/'wiring.vhd').write_text(wrapper)
    original = Path('rtl/ascal_line_address.vhd').read_text()
    variants = {'good': original,
                'borrow': original.replace("when low_a(6)='0'", "when low_a(5)='0'"),
                'bank': original.replace('when "10" => address1 <= second;',
                                         'when "10" => address0 <= second;'),
                'enable': original.replace("if ce='1' then", 'if true then')}
    for variant, text in variants.items():
        if variant != 'good':
            assert text != original
        (directory/'address.vhd').write_text(text)
        run(['ghdl', '-a', '--std=08', 'address.vhd', 'wiring.vhd'], directory)
        for bits in (range(13) if variant == 'good' else [11]):
            result = run(['ghdl', '--synth', '--std=08', '--out=verilog',
                          '-gOHRES=' + str(1 << bits), 'proof_address'], directory)
            (directory/('{}-{}.v'.format(variant, bits))).write_text(result)
    # Also elaborate the actual complete scaler with its new dependency.
    run(['ghdl', '-a', '--std=08', str(Path('rtl/ascal_line_address.vhd').resolve()),
         str(Path('MiSTer/sys/ascal.vhd').resolve())], directory)
    print('PASS synthesized 13 buffer sizes and 3 faults; full scaler analyzes')


def prove(directory):
    for source in sorted(directory.glob('*.v')):
        variant, bits_text = source.stem.split('-')
        bits = int(bits_text)
        width = 12
        harness = '''module proof(input clk, ce,
    input [11:0] x, origin, delayed_origin, fraction,
    input [1:0] bank, output equivalent);
wire [WIDTH-1:0] a0,a1,a2,a3;
proof_address actual(.o_clk(clk),.o_ce(ce),.o_hcpt(x),.o_hmin(origin),
 .o_v_hmin_adj(delayed_origin),.o_vfrac(fraction),.o_vacptl(bank),
 .o_radl0(a0),.o_radl1(a1),.o_radl2(a2),.o_radl3(a3));
wire [11:0] first=(x-delayed_origin)&12'dMASK;
wire [11:0] second=(x-origin)&12'dMASK;
wire [1:0] nearest_bank=bank+(fraction[11] ? 2'd0 : 2'd3);
reg [WIDTH-1:0] r0,r1,r2,r3;
always @(posedge clk) if(ce) begin
 r0 <= nearest_bank==0 ? second : first;
 r1 <= nearest_bank==1 ? second : first;
 r2 <= nearest_bank==2 ? second : first;
 r3 <= nearest_bank==3 ? second : first;
end
assign equivalent={a0,a1,a2,a3}=={r0,r1,r2,r3};
endmodule
'''.replace('WIDTH', str(width)).replace('MASK', str((1 << bits)-1))
        harness_path = directory/'harness.sv'
        harness_path.write_text(harness)
        script = ('read_verilog -sv ' + str(source) + ' ' + str(harness_path) + '; '
                  'prep -top proof -flatten; opt; '
                  'sat -verify -prove equivalent 1 -seq 4 -tempinduct -set-init-zero '
                  '-show-inputs -show-outputs')
        result = subprocess.run(['yosys', '-p', script], text=True, timeout=90,
                                stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
        (directory/(source.stem+'.log')).write_text(result.stdout)
        if variant == 'good':
            assert result.returncode == 0 and 'SUCCESS' in result.stdout, result.stdout
            print('PASS OHRES={}: all positions/origins/banks/fractions/CE stalls'.format(1 << bits))
        else:
            assert result.returncode != 0 and 'proof did fail' in result.stdout, result.stdout
            print('PASS rejected line-address fault: ' + variant)


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    group = parser.add_mutually_exclusive_group(required=True)
    group.add_argument('--prepare', type=Path)
    group.add_argument('--prove', type=Path)
    args = parser.parse_args()
    if args.prepare:
        prepare(args.prepare.resolve())
    else:
        prove(args.prove.resolve())
