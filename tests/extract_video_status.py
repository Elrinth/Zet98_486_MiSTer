"""Compile the actual sys_top synchronizer and its two VS edge consumers."""
from pathlib import Path
import re
import sys

source = Path('MiSTer/sys/sys_top.v').read_text()
cdc = source.split('// BEGIN HDMI STATUS CDC\n')[1].split('// END HDMI STATUS CDC')[0]
wait = re.search(r'\tvs_d0 <= .*?if\(~vs_d2 & vs_d1\) vs_wait <= 0;', source, re.S).group()
config = source.split('reg cfg_got = 0;')[1].split('reg cfg_ready = 0;')[0]
assert cdc.count('HDMI_TX_VS') == 1
assert cdc.count('hdmi_vs_meta') == 3  # declaration, first-stage D, second-stage D
assert 'HDMI_TX_VS' not in wait + config
assert wait.count('hdmi_vs_sync') == 2 and config.count('hdmi_vs_sync') == 1
Path(sys.argv[1]).write_text('''module actual_video_status(
    input clk_sys, HDMI_TX_VS, cfg_ready, cfg_set, arm_wait,
    output reg vs_wait=0, output wire cfg_done, sampled_vs);
''' + cdc + '''
assign sampled_vs=hdmi_vs_sync;
always @(posedge clk_sys) begin
    reg vs_d0=0,vs_d1=0,vs_d2=0;
    if(arm_wait) vs_wait<=1;
''' + wait + '\nend\nreg cfg_got=0;\n' + config + '\nassign cfg_done=cfg_got;\nendmodule\n')
