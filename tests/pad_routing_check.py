"""Simulate the actual top-level routing expressions without the FPGA shell."""
from pathlib import Path
import subprocess
import tempfile

root = Path(__file__).resolve().parents[1]
source = (root / 'Zet98/MiSTer/Zet98.sv').read_text()
assert 'P3oFG,Pad input,Both,Joystick only,Keyboard only;' in source
logic = source[source.index('wire  [5:0] joy0_bits'):source.index('wire        ioctl_download;')]
prefix = '''module pad_routing_tb;
reg [63:0] status = 0;
reg [15:0] joystick_0=0, joystick_1=0;
reg [3:0] dirs0=0, dirs1=0;
reg [5:0] snac_joy1=0, snac_joy2=0;
reg [7:0] snac_keys1=0, snac_keys2=0;
'''
checks = '''
integer route, mapping, portnum, bitnum, k, checks=0;
reg [5:0] expectedA, expectedB;
reg [15:0] expectedKeys;
task verify;
begin
  expectedA=63; expectedB=63; expectedKeys=0;
  // Reference wiring: pad R/L/D/U become joystick bits 3/2/1/0.
  for(k=0;k<4;k=k+1) begin
    if((route & 2) == 0) begin
      expectedA[3-k]=!(dirs0[k] | snac_joy1[k]);
      expectedB[3-k]=!(dirs1[k] | snac_joy2[k]);
    end
    if((route & 1) == 0 && mapping < 2)
      expectedKeys[(mapping==0 ? 0:4)+3-k]=dirs0[k]|dirs1[k]|snac_joy1[k]|snac_joy2[k];
  end
  for(k=0;k<2;k=k+1) begin
    if((route & 2) == 0) begin
      expectedA[k+4]=!(joystick_0[k+4]|snac_joy1[k+4]);
      expectedB[k+4]=!(joystick_1[k+4]|snac_joy2[k+4]);
    end
    if((route & 1) == 0 && mapping != 3)
      expectedKeys[k+8]=joystick_0[k+4]|joystick_1[k+4]|snac_keys1[k]|snac_keys2[k];
  end
  if((route & 1) == 0 && mapping != 3)
    for(k=2;k<8;k=k+1)
      expectedKeys[k+8]=joystick_0[k+6]|joystick_1[k+6]|snac_keys1[k]|snac_keys2[k];
  #1;
  if(joyA !== expectedA || joyB !== expectedB || pad_keys !== expectedKeys)
    $fatal(1,"route %0d mapping %0d: joy %h/%h keys %h expected %h/%h %h",
      route,mapping,joyA,joyB,pad_keys,expectedA,expectedB,expectedKeys);
  checks=checks+1;
end
endtask
initial begin
  for(mapping=0;mapping<4;mapping=mapping+1) begin
    status[46:45]=mapping;
    // Includes reserved route 3; switch modes while each input remains held.
    for(portnum=0;portnum<4;portnum=portnum+1)
      for(bitnum=0;bitnum<16;bitnum=bitnum+1) begin
        joystick_0=0;joystick_1=0;dirs0=0;dirs1=0;
        snac_joy1=0;snac_joy2=0;snac_keys1=0;snac_keys2=0;
        case(portnum)
        0: begin joystick_0=1<<bitnum;dirs0=joystick_0[3:0];end
        1: begin joystick_1=1<<bitnum;dirs1=joystick_1[3:0];end
        2: begin snac_joy1=1<<bitnum;snac_keys1=1<<bitnum;end
        3: begin snac_joy2=1<<bitnum;snac_keys2=1<<bitnum;end
        endcase
        for(route=0;route<4;route=route+1) begin status[48:47]=route;verify;end
      end
    joystick_0='1;joystick_1='1;dirs0='1;dirs1='1;
    snac_joy1='1;snac_joy2='1;snac_keys1='1;snac_keys2='1;
    for(route=0;route<4;route=route+1) begin status[48:47]=route;verify;end
  end
  $display("PASS: %0d pad routing cases (both ports, USB/SNAC, held switches, all mappings)",checks);
  $finish;
end
endmodule
'''
with tempfile.TemporaryDirectory() as temp:
    tb = Path(temp) / 'routing.sv'
    exe = Path(temp) / 'routing'
    tb.write_text(prefix + logic + checks)
    subprocess.run(['iverilog', '-g2012', '-Wall', '-s', 'pad_routing_tb', '-o', str(exe), str(tb)], check=True)
    subprocess.run(['vvp', str(exe)], check=True)
