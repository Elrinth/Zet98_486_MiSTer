"""All-input equivalence, plus independently rejected width/boundary mutants."""
from pathlib import Path
import subprocess

out=Path('/project/segment-compare-proof');out.mkdir()
source=Path('tests/vipt_segment_compare.sv').read_text()
(out/'compare.sv').write_text(source)
top='''module proof(input [31:0] offset,limit,input [1:0] size,output equivalent);
wire reference,candidate;
vipt_segment_compare #(.STRUCTURED(0)) a(offset,limit,size,reference);
vipt_segment_compare #(.STRUCTURED(1)) b(offset,limit,size,candidate);
assign equivalent=reference==candidate;
endmodule
'''
(out/'proof.sv').write_text(top)
def prove(name,text,negative=False):
    path=out/(name+'.sv');path.write_text(text)
    cmd=f'read_verilog -sv {path} {out}/proof.sv; prep -top proof -flatten; opt; sat -verify -prove equivalent 1 -show-inputs -show-outputs'
    result=subprocess.run(['yosys','-p',cmd],capture_output=True,text=True)
    log=result.stdout+result.stderr;(out/(name+'.log')).write_text(log)
    if negative:
        assert result.returncode!=0 and 'proof did fail' in log,log[-3000:]
    else:assert result.returncode==0 and 'SUCCESS' in log,log[-3000:]
    print('PASS',name,flush=True)
prove('all-input-equivalence',source)
bad=source.replace('((offset==previous2)&&size[1])',"1'b0")
assert bad!=source
prove('missing-dword-endpoint-negative',bad,True)
bad=source.replace('assign fits=!outside&&!crosses;',"assign fits=!outside&&(!crosses || offset==limit);")
prove('inclusive-boundary-negative',bad,True)
print('PASS: every32bit offset/limit and allfour sizecodes equivalent; both faulty alternatives rejected')
