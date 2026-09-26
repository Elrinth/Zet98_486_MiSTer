"""Prove all-input conservative admission and reject an overflow mutant."""

from pathlib import Path
import subprocess


out = Path('/project/flat-proof-evidence')
out.mkdir()
source = Path('tests/vipt_flat_admission.sv').read_text()
(out / 'candidate.sv').write_text(source)
top = '''module proof(input [31:0] offset,input [19:0] raw_limit,
 input granularity,input [1:0] size,output safe,output flat_equivalent);
wire reference_fits,candidate_fits,flat_descriptor;
vipt_flat_admission dut(offset,raw_limit,granularity,size,
 reference_fits,candidate_fits,flat_descriptor);
assign safe=!candidate_fits||reference_fits;
assign flat_equivalent=!flat_descriptor||(candidate_fits==reference_fits);
endmodule
'''
(out / 'proof.sv').write_text(top)


def prove(name, design, property_name, negative=False):
    path = out / (name + '.sv')
    path.write_text(design)
    cmd = (f'read_verilog -sv {path} {out}/proof.sv; '
           f'prep -top proof -flatten; opt; '
           f'sat -verify -prove {property_name} 1 -show-inputs -show-outputs')
    result = subprocess.run(['yosys', '-p', cmd], capture_output=True, text=True)
    log = result.stdout + result.stderr
    (out / (name + '.log')).write_text(log)
    if negative:
        assert result.returncode != 0 and 'proof did fail' in log, log[-2000:]
    else:
        assert result.returncode == 0 and 'SUCCESS' in log, log[-2000:]
    print('PASS', name, flush=True)


prove('all-input-safe', source, 'safe')
prove('flat-equivalence', source, 'flat_equivalent')
mutant = source.replace('assign candidate_fits = flat_descriptor && no_wrap;',
                        'assign candidate_fits = flat_descriptor;')
assert mutant != source
prove('overflow-negative', mutant, 'safe', negative=True)
print('PASS all 32-bit offsets, 20-bit limits, both granularities, four sizes')
