#!/usr/bin/env python3
"""Prove early task-switch payload at every enabled update and global mux priority."""
from pathlib import Path
import re
import subprocess
import tempfile

root=Path('rtl/vendor/ao486')
wrapper=(root/'pipeline/write_commands.v').read_text()
body=(root/'autogen/write_commands.v').read_text()
legacy=Path('tests/reference/write_parameter_payload_legacy.vh').read_text()
original=re.search(r'assign wr_glob_param_1_value =.*?;',legacy,re.S).group()
for expression in re.findall(r'wire cond_\d+ =.*?;|assign wr_glob_param_1_set =.*?;',legacy,re.S):
    assert expression in body, 'Original control changed: '+expression
reference,n=re.subn(r'assign wr_glob_param_1_value =.*?;',lambda m:original,body,flags=re.S)
assert n==1
inputs=re.findall(r'^\s*input\s+(\[[^\]]+\])?\s*(\w+)\s*[,\n]',wrapper,re.M)
inputs=[(w or '',n) for w,n in inputs]
assert len(inputs)>40
connections=[f'.{n}({n})' for _,n in inputs]
ports=','.join('input '+w+' '+n for w,n in inputs)
harness='\n'.join([
    'module proof('+ports+',input rd_set,exe_set,input [31:0] rd_value,exe_value,old_value,output equivalent);',
    'wire [31:0] actual,reference_value; wire actual_set,reference_set;',
    'write_commands dut('+','.join(connections+['.wr_glob_param_1_value(actual)','.wr_glob_param_1_set(actual_set)'])+');',
    'write_commands_reference refdut('+','.join(connections+['.wr_glob_param_1_value(reference_value)','.wr_glob_param_1_set(reference_set)'])+');',
    'wire [31:0] committed = rd_set ? rd_value : exe_set ? exe_value : actual_set ? actual : old_value;',
    'wire [31:0] reference_commit = rd_set ? rd_value : exe_set ? exe_value : reference_set ? reference_value : old_value;',
    'assign equivalent = actual_set == reference_set && (!actual_set || actual == reference_value) && committed == reference_commit;',
    'endmodule'
])
actual_module=wrapper.replace('`include "autogen/write_commands.v"',body)
reference_module=wrapper.replace('module write_commands(', 'module write_commands_reference(',1).replace('`include "autogen/write_commands.v"',reference)

# These are the only consumers of the speculative payload; compare actual
# priority and register hold structure to the all-state next-value proof above.
pipeline=re.sub(r'\s+','',(root/'pipeline/pipeline.v').read_text())
assert 'assignglob_param_1_set=rd_glob_param_1_set|exe_glob_param_1_set|wr_glob_param_1_set;' in pipeline
assert 'assignglob_param_1_value=(rd_glob_param_1_set)?rd_glob_param_1_value:(exe_glob_param_1_set)?exe_glob_param_1_value:wr_glob_param_1_value;' in pipeline
regs=re.sub(r'\s+','',(root/'global_regs.v').read_text())
assert "if(rst_n==1'b0)glob_param_1<=32'd0;elseif(glob_param_1_set)glob_param_1<=glob_param_1_value;" in regs


def prove(actual,negative=False):
    with tempfile.TemporaryDirectory() as directory:
        path=Path(directory)/'proof.v'
        path.write_text(actual+'\n'+reference_module+'\n'+harness)
        script=(f'read_verilog -sv -I{root} {path}; prep -top proof -flatten; opt; '
                'sat -verify -prove equivalent 1 -show-inputs -show-outputs')
        result=subprocess.run(['yosys','-p',script],text=True,timeout=120,
                              stdout=subprocess.PIPE,stderr=subprocess.STDOUT)
        if negative:
            assert result.returncode!=0 and 'proof did fail' in result.stdout,result.stdout
        else:
            assert result.returncode==0 and 'SUCCESS' in result.stdout,result.stdout


prove(actual_module)
print('PASS: all-input enabled payload, unchanged write control, arbitrary global priority/hold state',flush=True)
for name,old,new in [
    ('wrong task data selector','{13\'d0, `SEGMENT_DS, task_ds}','{13\'d0, `SEGMENT_DS, task_es}'),
    ('wrong task step','{32{wr_cmdex == `CMDEX_task_switch_4_STEP_2}}','{32{wr_cmdex == `CMDEX_task_switch_4_STEP_3}}'),
]:
    bad=actual_module.replace(old,new,1)
    assert bad!=actual_module
    prove(bad,True)
    print('PASS: rejected '+name,flush=True)
