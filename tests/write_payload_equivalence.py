from pathlib import Path
import re, sys
source=Path('rtl/vendor/ao486/pipeline/write.v').read_text()
module=Path('rtl/vendor/ao486/pipeline/write_commands.v').read_text()
ports={}
for line in module.splitlines():
    m=re.match(r"\s*(input|output)\s+(?:reg\s+|wire\s+)?(\[[^]]+\])?\s*(\w+)",line)
    if m: ports[m[3]]=(m[1],m[2] or '')
extra=['wr_string_es_linear','wr_push_linear','wr_new_push_linear','wr_descriptor_touch_offset','wr_descriptor_busy_tss_offset','wr_linear','wr_reset','write_page_fault','write_ac_fault']
bench='`include "defines.v"\nmodule check;\n'
for name,(direction,width) in ports.items():
    bench+=('%s %s %s;\n'%('reg' if direction=='input' else 'wire',width,name))
for name in extra:
    if name not in ports: bench+='reg '+('' if name in ['wr_reset','write_page_fault','write_ac_fault'] else '[31:0] ')+name+';\n'
bench+='write_commands dut('+','.join('.%s(%s)'%(n,n) for n in ports)+');\n'
bench+='wire [31:0] write_address,write_data,expected_address,expected_data;\nwire write_do,memory_write_system;\n'
for name in ['memory_write_system','write_address','write_data','write_do']:
    expr=re.search(r'assign '+name+r' =.*?;',source,re.S).group()
    bench+=expr+'\n'
    if name in ['write_address','write_data']:
        bench+=expr.replace(name,'expected_address' if name=='write_address' else 'expected_data',1).replace('wr_string_write_select','write_string_es_virtual')+'\n'
bench+=re.search(r'wire wr_string_write_select =.*?;',source,re.S).group()+'\n'
bench+='integer trial,command,step,accepted=0,faulted=0; initial begin\n'
for name,(direction,width) in ports.items():
    if direction=='input': bench+=name+"=0;\n"
bench+="#1;clk=1;#1;clk=0;rst_n=1;\nfor(trial=0;trial<16;trial=trial+1)begin\n"
for name,(direction,width) in ports.items():
    if direction=='input' and name not in ['clk','rst_n','wr_cmd','wr_cmdex']:
        bench+=name+'={$random,$random,$random,$random,$random,$random,$random,$random,$random,$random,$random,$random,$random,$random,$random,$random};\n'
for name in extra:
    if name not in ports: bench+=name+'=$random;\n'
bench+="""
wr_string_es_fault=trial[0];wr_string_ignore=trial[1];
wr_reset=0;write_page_fault=0;write_ac_fault=0;
for(command=0;command<128;command=command+1)begin
 for(step=0;step<16;step=step+1)begin
  wr_cmd=command;wr_cmdex=step;#1;
  if(write_do)begin
   accepted=accepted+1;
   if(write_address !== expected_address || write_data !== expected_data)
    $fatal(1,"Payload mismatch cmd=%h step=%h address=%h/%h data=%h/%h",wr_cmd,wr_cmdex,write_address,expected_address,write_data,expected_data);
  end
  if((wr_cmd==`CMD_STOS || wr_cmd==`CMD_MOVS) && (wr_string_es_fault || wr_string_ignore))begin
   faulted=faulted+1;
   if(write_do) $fatal(1,"Fault or REP-zero suppression bypassed");
  end
 end
end
end
if(accepted<100 || faulted<256)$fatal(1,"Insufficient coverage");
$display("PASS: raw string payload selection: 32768 command/substep/control cases, %0d enabled writes, %0d fault/REP-zero suppressed cases",accepted,faulted);
$finish;
end endmodule
"""
Path(sys.argv[1]).write_text(bench)
