#!/usr/bin/env python3
"""Prove synthesized actual VHDL pixel arithmetic for every pair of inputs.

GHDL prepares good and deliberately faulty netlists; Yosys compares them to
the original 19-bit modular sum followed by signed clamp/truncation. Separate
--prepare and --prove modes allow the existing two Docker images to be used.
"""
import argparse
from pathlib import Path
import re
import subprocess


def run(command, cwd):
    result = subprocess.run(command, cwd=cwd, text=True, timeout=120,
                            stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
    assert result.returncode == 0, result.stdout
    return result.stdout


def prepare(directory):
    directory.mkdir(parents=True, exist_ok=True)
    source = Path('MiSTer/sys/ascal.vhd').read_text()
    bound = re.search(r'  FUNCTION bound\(.*?END FUNCTION bound;', source, re.S).group()
    poly = re.search(r'  FUNCTION poly_bound\(.*?END FUNCTION;', source, re.S).group()
    final = re.search(r'  FUNCTION poly_final\(.*?END FUNCTION;', source, re.S).group()
    # Check all three actual RGB connections; the arithmetic is identical.
    for c in 'rgb':
        assert f'p.{c}:=poly_bound(t.{c}0,t.{c}1);' in final
    prefix = '''library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
entity proof_pixel is
  port(a,b : in signed(26 downto 0); p : out unsigned(7 downto 0));
end entity;
architecture rtl of proof_pixel is
'''
    variants = {'good': poly,
                'carry': poly.replace("IF lo(7)='1'", "IF lo(6)='1'"),
                'rounding': poly.replace('hi1,8', 'hi0,8'),
                'sign': poly.replace('a(26 DOWNTO 15)', "('0' & a(25 DOWNTO 15))")}
    for name, body in variants.items():
        assert name == 'good' or body != poly
        (directory/'pixel.vhd').write_text(prefix + bound + '\n' + body +
                                         '\nbegin p<=poly_bound(a,b); end architecture;\n')
        run(['ghdl', '-a', '--std=08', 'pixel.vhd'], directory)
        text = run(['ghdl', '--synth', '--std=08', '--out=verilog', 'proof_pixel'], directory)
        (directory/(name+'.v')).write_text(text)
    run(['ghdl', '-a', '--std=08', str(Path('rtl/ascal_line_address.vhd').resolve()),
         str(Path('MiSTer/sys/ascal.vhd').resolve())], directory)
    print('PASS: actual scaler analyzes; synthesized carry-select function and three negative controls', flush=True)


def prove(directory):
    harness = '''module proof(input [26:0] a,b,output equivalent);
wire [7:0] actual;
proof_pixel dut(.a(a),.b(b),.p(actual));
wire [18:0] sum = a[26:8]+b[26:8];
wire [7:0] reference_pixel = sum[18] ? 8'h00 : (|sum[18:15]) ? 8'hff : sum[14:7];
assign equivalent = actual == reference_pixel;
endmodule
'''
    (directory/'harness.sv').write_text(harness)
    for name in ['good', 'carry', 'rounding', 'sign']:
        script = ('read_verilog -sv ' + str(directory/(name+'.v')) + ' ' + str(directory/'harness.sv') + '; '
                  'prep -top proof -flatten; opt; sat -verify -prove equivalent 1 -show-inputs -show-outputs')
        result = subprocess.run(['yosys', '-p', script], text=True, timeout=120,
                                stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
        (directory/(name+'.log')).write_text(result.stdout)
        if name == 'good':
            assert result.returncode == 0 and 'SUCCESS' in result.stdout, result.stdout
            print('PASS: synthesized VHDL matches original sum/clamp for all 2^54 input pairs', flush=True)
        else:
            assert result.returncode != 0 and 'proof did fail' in result.stdout, result.stdout
            print('PASS: rejected ' + name + ' arithmetic fault', flush=True)


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
