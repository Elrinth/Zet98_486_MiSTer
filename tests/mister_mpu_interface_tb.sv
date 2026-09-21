// Real MiSTer wrapper + HPS settings + MPU, with the VHDL machine stub only.
`timescale 1ns/1ps
module mister_mpu_interface_tb;
    reg clk=0; always #25 clk=!clk; // Default wrapper clock is 20 MHz.
    tri [48:0] bus;
    reg enable=0,strobe=0;
    reg [15:0] host_data=0;
    assign bus[48:38]=0;
    assign bus[35:33]={1'b0,enable,strobe};
    assign bus[31:16]=host_data;
    wire serial;
    emu dut(.CLK_50M(clk),.RESET(1'b0),.HPS_BUS(bus),.UART_RXD(1'b1),.UART_TXD(serial));
    defparam dut.hps_io.CONF_STR_BRAM=0;
    defparam dut.hps_io.PS2DIV=0;
    defparam dut.floppy_icon.TILE_MAP_FILE="rtl/assets/floppy-tile-map.mem";
    defparam dut.floppy_icon.TILE_PIXELS_FILE="rtl/assets/floppy-tile-pixels.mem";
    task word_io(input [15:0] value);
        @(negedge clk);enable=1;strobe=1;host_data=value;
        @(negedge clk);strobe=0;
        repeat(4) @(negedge clk);
    endtask
    task option_midi(input bit enabled);
        word_io('h1e);word_io(0);word_io(enabled ? 'h0400 : 0);
        @(negedge clk);enable=0;strobe=0;
        repeat(5) @(negedge clk);
    endtask
    task outb(input [15:0] port,input [7:0] value);
        @(negedge clk);dut.Zet98_top.pIDEAddress=port;
        dut.Zet98_top.pIDEWriteData={8'hcd,value};dut.Zet98_top.pIDEWrite=1;
        repeat(6) @(negedge clk);dut.Zet98_top.pIDEWrite=0;
        repeat(4) @(negedge clk);
    endtask
    task inb(input [15:0] port,input [7:0] wanted);
        @(negedge clk);dut.Zet98_top.pIDEAddress=port;dut.Zet98_top.pIDERead=1;
        repeat(6) @(negedge clk);
        if(!dut.Zet98_top.pMPUOE || dut.Zet98_top.pMPUReadData!==wanted)
            $fatal(1,"Wrapper MPU read %04x got %02x expected %02x",port,dut.Zet98_top.pMPUReadData,wanted);
        if(dut.Zet98_top.pIDEOE) $fatal(1,"MPU read selected IDE");
        dut.Zet98_top.pIDERead=0;repeat(4) @(negedge clk);
    endtask
    reg [7:0] received;
    initial begin
        force dut.hps_io.EXT_BUS[32]=1'b0;
        option_midi(0);dut.Zet98_top.pIDEResetn=1;
        outb('he0d2,'hff);
        if(dut.Zet98_top.pMPUIRQ || serial!==1) $fatal(1,"Disabled MIDI active");
        option_midi(1);
        outb('he0d2,'hff);
        if(!dut.Zet98_top.pMPUIRQ) $fatal(1,"ACK IRQ not connected to machine");
        inb('he0d0,'hfe);
        if(dut.Zet98_top.pMPUIRQ) $fatal(1,"IRQ did not clear through wrapper");
        outb('he0d2,'h3f);inb('he0d0,'hfe);
        fork
            outb('he0d0,'h95);
            begin
                @(negedge serial);#16000;
                for(integer b=0;b<8;b=b+1) begin #32000;received[b]=serial;end
                #32000;
                if(serial!==1 || received!==8'h95) $fatal(1,"HPS MIDI serial route/baud incorrect");
            end
        join
        option_midi(0);
        if(dut.Zet98_top.pMPUIRQ || dut.Zet98_top.pMPUOE || serial!==1)
            $fatal(1,"HPS off option failed");
        $display("PASS real HPS MPU wrapper: option bit26, PC98 ports, ACK IRQ, 31250 baud UART_TXD, IDE isolation");
        $finish;
    end
    initial begin #2000000;$fatal(1,"MPU wrapper timeout");end
endmodule
