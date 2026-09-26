"""Derive the existing physical memory/I/O bus harness, replacing its IRQ stub.

The PIC itself is GHDL-synthesized production VHDL, not a behavioral model.
"""
from pathlib import Path
import sys

s = Path('tests/ao486_cpu_tb.sv').read_text()
def replace(old, new):
    global s
    assert s.count(old) == 1, old
    s = s.replace(old, new)

replace('reg interrupt_do = 0;', 'wire interrupt_do;')
replace("wire [7:0] interrupt_vector = interrupt_done ? 8'h80 : 8'h07;", '''wire [7:0] interrupt_vector;
    reg [7:0] pic_irq = 0;
    reg [7:0] slave_irq = 0;
    wire slave_int, slave_oe;
    wire [7:0] master_data, slave_data;
    wire [2:0] cascade;
    integer expected_irqs = 8;
    initial if ($value$plusargs("expected_irqs=%d",expected_irqs)) begin end
    wire pic_select = bus_io && bus_strobe && bus_address[19:2] == 0;
    wire slave_select = bus_io && bus_strobe && bus_address[19:2] == 2;
    wire pic_oe;
    assign interrupt_vector = pic_oe ? master_data : slave_oe ? slave_data : 8'hff;
    z8259 pic(.CS(pic_select), .ADDR(bus_address[1]),
      .DIN(bus_writedata[7:0]), .DOUT(master_data), .DOE(pic_oe),
      .RD(pic_select && !bus_write), .WR(pic_select && bus_write),
      .IR0(pic_irq[0]),.IR1(pic_irq[1]),.IR2(pic_irq[2]),.IR3(pic_irq[3]),
      .IR4(pic_irq[4]),.IR5(pic_irq[5]),.IR6(pic_irq[6]),.IR7(pic_irq[7] | slave_int),
      .INT(interrupt_do),.INTA(interrupt_done),.CASI(3'b0),.CASO(cascade),
      .CASM(1'b1),.clk(clk),.rstn(!reset));
    z8259 slave(.CS(slave_select),.ADDR(bus_address[1]),.DIN(bus_writedata[7:0]),
      .DOUT(slave_data),.DOE(slave_oe),.RD(slave_select && !bus_write),
      .WR(slave_select && bus_write),.IR0(slave_irq[0]),.IR1(slave_irq[1]),
      .IR2(slave_irq[2]),.IR3(slave_irq[3]),.IR4(slave_irq[4]),.IR5(slave_irq[5]),
      .IR6(slave_irq[6]),.IR7(slave_irq[7]),.INT(slave_int),.INTA(interrupt_done),
      .CASI(cascade),.CASO(),.CASM(1'b0),.clk(clk),.rstn(!reset));''')
replace('interrupt_do <= 0;', '''pic_irq <= 0;
        slave_irq <= 0;
        $display("CPU sampled PIC vector %h",interrupt_vector);''')
replace("if (held_data == 16'h0011) interrupt_do <= 1;", "if (held_data == 16'h0011) $fatal(1, \"obsolete IRQ stub\");")
begin=s.index('`ifdef ZET98_Z486',s.index("else if (held_data == 16'h600d)"))
end=s.index('$finish;',begin)
s=s[:begin]+'''if (irq_count != expected_irqs) $fatal(1,"Wrong PIC acknowledgement count");
                                   $display("PASS actual CPU/PIC: %0d distinct vectors and IRET/EOI",irq_count);
                                   '''+s[end:]
needle="if (held_addr == 20'h07ff0) begin"
replace(needle,"if (held_addr == 20'h07fe0) begin if (held_data[4]) slave_irq <= 8'b1 << held_data[2:0]; else pic_irq <= 8'b1 << held_data[2:0]; end\n                           "+needle)
needle="bus_readdata = {ports[held_addr[15:0]+16'd1], ports[held_addr[15:0]]};"
replace(needle,needle+'''
                       if (!held_write && pic_select) bus_readdata = {8'h00,master_data};
                       if (!held_write && slave_select) bus_readdata = {8'h00,slave_data};''')
Path(sys.argv[1]).write_text(s)
