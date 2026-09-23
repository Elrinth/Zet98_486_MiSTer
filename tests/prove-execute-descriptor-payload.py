#!/usr/bin/env python3
"""Prove actual execute descriptor payloads whenever original enables are set."""
from pathlib import Path
import re,subprocess,tempfile
source=Path('rtl/vendor/ao486/pipeline/execute.v').read_text()
commands=Path('rtl/vendor/ao486/pipeline/execute_commands.v').read_text()
inputs=re.findall(r'^\s*input\s+(\[[^\]]+\])?\s*(\w+)\s*[,\n]',commands,re.M)
assert len(inputs)>90
ports=['input '+(w or '')+' '+n for w,n in inputs]
outs=['exe_glob_descriptor_set','exe_glob_descriptor_2_set','exe_glob_descriptor_value','exe_glob_descriptor_2_value']
connections=[f'.{n}({n})' for w,n in inputs]+[f'.{n}(original_{n})' for n in outs]
expressions=[]
for n in outs[2:]:
 expr=re.search(r'assign '+n+r'\s*=([^;]+);',source).group(1).strip()
 assert re.search(r'\.'+n+r'\s*\('+n+r'_reference\)',source)
 expressions.append('wire [63:0] '+n+' = '+expr+';')
miter='`include "defines.v"\nmodule proof('+','.join(ports+['output equivalent'])+');\n'
miter+='wire original_exe_glob_descriptor_set,original_exe_glob_descriptor_2_set;\nwire [63:0] original_exe_glob_descriptor_value,original_exe_glob_descriptor_2_value;\n'
miter+='execute_commands decoder('+','.join(connections)+');\n'+'\n'.join(expressions)
miter+='\nassign equivalent = (!original_exe_glob_descriptor_set || exe_glob_descriptor_value == original_exe_glob_descriptor_value) && (!original_exe_glob_descriptor_2_set || exe_glob_descriptor_2_value == original_exe_glob_descriptor_2_value);\nendmodule\n'
with tempfile.TemporaryDirectory() as d:
 p=Path(d)/'proof.v'
 script=f'read_verilog -sv -Irtl/vendor/ao486 rtl/vendor/ao486/pipeline/execute_commands.v rtl/vendor/ao486/pipeline/condition.v {p}; prep -top proof -flatten; opt; sat -verify -prove equivalent 1 -show-inputs -show-outputs'
 p.write_text(miter)
 r=subprocess.run(['yosys','-p',script],capture_output=True,text=True)
 assert r.returncode==0 and 'SUCCESS' in r.stdout,r.stdout+r.stderr
 print('PASS: both actual descriptor payloads equivalent on enabled writes for every decoder input')
 for before,after in [('? ss_cache : glob_descriptor_2','? glob_descriptor : glob_descriptor_2'),('wire [63:0] exe_glob_descriptor_2_value = glob_descriptor;','wire [63:0] exe_glob_descriptor_2_value = glob_descriptor_2;')]:
  bad=miter.replace(before,after)
  assert bad!=miter
  p.write_text(bad)
  r=subprocess.run(['yosys','-p',script],capture_output=True,text=True)
  assert r.returncode!=0 and 'proof did fail' in r.stdout+r.stderr,r.stdout+r.stderr
 print('PASS: wrong stack descriptor and wrong descriptor 2 source mutations rejected')
