// SPDX-License-Identifier: GPL-3.0-or-later
`timescale 1ns/1ps
module pc98_ide_tb;
    reg clk=0; always #5 clk=!clk;
    reg reset=1;
    reg [15:0] io_address=0, io_writedata=0;
    reg [1:0] io_select=3;
    reg io_read=0, io_write=0;
    wire [15:0] io_readdata;
    wire io_oe,irq;
    reg image_mounted=0, image_readonly=0;
    reg [63:0] image_size=524288;
    wire [31:0] sd_lba;
    wire sd_rd,sd_wr;
    reg sd_ack=0,sd_buff_wr=0;
    reg [8:0] sd_buff_addr=0;
    reg [7:0] sd_buff_dout=0;
    wire [7:0] sd_buff_din;
    // CD-ROM slot (secondary channel) idle: no disc.
    reg cd_mounted=0, cd_ack=0, cd_buff_wr=0;
    reg [63:0] cd_size=0;
    reg [8:0] cd_buff_addr=0;
    reg [7:0] cd_buff_dout=0;
    wire [31:0] cd_lba;
    wire cd_rd;
    wire signed [15:0] cd_audio_l, cd_audio_r;
    wire [5:0] cd_blk_cnt;
    wire [1:0] cd_activity;
    wire [91:0] cd_trace;
    pc98_ide dut(.*);
    // The shared RAM port depends on mutually exclusive command ownership.
    always @(posedge clk) if(dut.cpu_buffer_write && dut.host_buffer_write)
        $fatal(1,"CPU and host attempted to write the buffer together");
    reg [7:0] disk[0:524287];
    integer reads=0,writes=0,host_index,host_delay;
    reg [31:0] host_lba;
    reg host_direction;
    // Delayed host service, full byte-stream sector transfer and synchronous
    // write-buffer reads. Every request must survive through ACK assertion.
    initial forever begin
        @(negedge clk);
        if(sd_rd || sd_wr) begin
            if(sd_rd && sd_wr) $fatal(1,"simultaneous host read/write");
            host_lba=sd_lba; host_direction=sd_wr;
            if(host_lba>=1024) $fatal(1,"out-of-range host request");
            repeat(7) begin
                @(negedge clk);
                if(sd_lba!==host_lba || sd_wr!==host_direction || sd_rd===host_direction)
                    $fatal(1,"request changed before ACK");
            end
            sd_ack=1;
            if(host_direction) writes=writes+1; else reads=reads+1;
            for(host_index=0;host_index<512;host_index=host_index+1) begin
                @(negedge clk);
                sd_buff_addr=host_index;
                sd_buff_dout=disk[host_lba*512+host_index];
                sd_buff_wr=!host_direction;
                repeat(2) @(negedge clk);
                if(host_direction) disk[host_lba*512+host_index]=sd_buff_din;
                sd_buff_wr=0;
            end
            repeat(5) @(negedge clk);
            sd_ack=0;
        end
    end
    task automatic outw(input [15:0] port, input [15:0] value, input [1:0] lanes);
        begin
            @(negedge clk); io_address=port; io_writedata=value; io_select=lanes; io_write=1;
            repeat(4) @(negedge clk);
            io_write=0;
            repeat(3) @(negedge clk);
        end
    endtask
    task automatic inw(input [15:0] port, output [15:0] value, input [1:0] lanes);
        reg [15:0] held;
        begin
            @(negedge clk); io_address=port; io_select=lanes; io_read=1;
            repeat(3) @(negedge clk);
            value=io_readdata; held=io_readdata;
            repeat(4) begin
                @(negedge clk);
                if(port==16'h0640 && io_readdata!==held) $fatal(1,"data advanced while IN held");
            end
            if(lanes[0] && !io_oe) $fatal(1,"missing decode %h",port);
            if(!lanes[0] && io_oe) $fatal(1,"odd lane decoded");
            io_read=0;
            repeat(3) @(negedge clk);
        end
    endtask
    task automatic mount(input [63:0] bytes, input ro);
        begin
            @(negedge clk); image_mounted=1; image_size=bytes; image_readonly=ro;
            @(negedge clk); image_mounted=0;
            repeat(4) @(negedge clk);
        end
    endtask
    task automatic taskfile(input [27:0] lba, input [7:0] blocks);
        begin
            outw('h644,blocks,1); outw('h646,lba[7:0],1);
            outw('h648,lba[15:8],1); outw('h64a,lba[23:16],1);
            outw('h64c,{8'b0,4'he,lba[27:24]},1);
        end
    endtask
    task automatic await_status(input [7:0] wanted);
        reg [15:0] s;
        integer tries;
        begin
            tries=0; s=0;
            while(s[7:0]!==wanted && tries<10000) begin
                inw('h74c,s,1); tries=tries+1;
            end
            if(s[7:0]!==wanted) $fatal(1,"status %h expected %h",s,wanted);
        end
    endtask
    task automatic check_sector(input integer lba);
        reg [15:0] got;
        integer w;
        begin
            await_status('h58);
            if(!irq) $fatal(1,"missing read IRQ");
            inw('h74c,got,1);
            if(!irq) $fatal(1,"alternate status cleared IRQ");
            inw('h64e,got,1);
            if(irq) $fatal(1,"status did not clear IRQ");
            for(w=0;w<256;w=w+1) begin
                inw('h640,got,3);
                if(got!=={disk[lba*512+w*2+1],disk[lba*512+w*2]})
                    $fatal(1,"read data mismatch LBA%0d word%0d got%h",lba,w,got);
            end
        end
    endtask
    reg [15:0] value;
    integer i,j,old_reads,old_writes;
    initial begin
        for(i=0;i<524288;i=i+1) disk[i]=(i>>9)^i^(i>>8);
        repeat(5) @(negedge clk); reset=0;
        mount(524288,0);
        await_status('h50);
        inw('h430,value,1); if(value!==16'hff01) $fatal(1,"presence register");
        outw('h64e,'hec,2); // High byte of another PC-98 peripheral, not IDE.
        if(irq) $fatal(1,"odd lane command changed state");
        inw('h64e,value,2);
        outw('h64e,'hec,1);
        await_status('h58);
        for(i=0;i<256;i=i+1) begin
            inw('h640,value,3);
            case(i)
                0: if(value!='h0040) $fatal(1,"identify device type");
                1: if(value!=2) $fatal(1,"identify cylinders");
                3: if(value!=16) $fatal(1,"identify heads");
                6: if(value!=32) $fatal(1,"identify sectors");
                49: if(value!='h0200) $fatal(1,"identify features");
                60: if(value!=1024) $fatal(1,"identify capacity");
                61: if(value!=0) $fatal(1,"identify capacity high");
            endcase
        end
        await_status('h50);
        if(reads || writes) $fatal(1,"identify touched disk");
        inw('h64e,value,1);
        taskfile(3,2); outw('h64e,'h20,1);
        check_sector(3); check_sector(4); await_status('h50);
        inw('h644,value,1); if(value[7:0]!=0) $fatal(1,"read sector count");
        inw('h646,value,1); if(value[7:0]!=5) $fatal(1,"read address advancement");
        // Writes issue no initial interrupt, then one for each committed sector.
        taskfile(7,2); outw('h64e,'h30,1);
        if(irq) $fatal(1,"initial write DRQ should not interrupt");
        for(j=0;j<2;j=j+1) begin
            await_status('h58);
            for(i=0;i<256;i=i+1) outw('h640,16'hc000+j*256+i,3);
            await_status(j==0 ? 'h58 : 'h50);
            if(!irq) $fatal(1,"write completion IRQ missing");
            inw('h64e,value,1);
            for(i=0;i<256;i=i+1)
                if({disk[(7+j)*512+i*2+1],disk[(7+j)*512+i*2]} !== ((16'hc000+j*256+i)&16'hffff))
                    $fatal(1,"write data mismatch");
        end
        // CHS head/cylinder rollover: cylinder 0, head 15, sector 32 -> 1/0/1.
        outw('h644,2,1); outw('h646,32,1); outw('h648,0,1); outw('h64a,0,1); outw('h64c,'haf,1);
        outw('h64e,'h21,1); check_sector(511); check_sector(512); await_status('h50);
        inw('h648,value,1); if(value[7:0]!=1) $fatal(1,"CHS cylinder rollover");
        inw('h646,value,1); if(value[7:0]!=2) $fatal(1,"CHS sector rollover");
        taskfile(768,0); outw('h64e,'h20,1);
        for(j=768;j<1024;j=j+1) check_sector(j);
        await_status('h50);
        old_reads=reads; old_writes=writes;
        taskfile(1023,2); outw('h64e,'h20,1); await_status('h51);
        inw('h642,value,1); if(value[7:0]!='h10) $fatal(1,"range error missing");
        mount(524288,1); taskfile(1,1); outw('h64e,'h30,1); await_status('h51);
        inw('h642,value,1); if(value[7:0]!='h04) $fatal(1,"readonly error missing");
        if(reads!=old_reads || writes!=old_writes) $fatal(1,"invalid request touched disk");
        mount(524288,0); outw('h432,1,1); inw('h64e,value,1);
        if(value[7:0]!=0) $fatal(1,"CD not in reset state");
        // Bank 1 holds the ATAPI CD: IDENTIFY DEVICE aborts with the packet
        // signature and an interrupt; reading status acknowledges it.
        outw('h64e,'hec,1); repeat(3) @(negedge clk); if(!irq) $fatal(1,"CD abort IRQ missing");
        inw('h648,value,1); if(value[7:0]!='h14) $fatal(1,"CD signature missing");
        inw('h64e,value,1); if(value[7:0]!='h41) $fatal(1,"CD abort status");
        if(irq) $fatal(1,"CD IRQ not acknowledged");
        outw('h432,0,1); outw('h64c,'hb0,1); inw('h64e,value,1);
        if(value[7:0]!=0) $fatal(1,"absent slave ready");
        outw('h64c,'ha0,1);
        outw('h74c,2,1); outw('h64e,'hec,1); await_status('h58);
        if(irq) $fatal(1,"nIEN failed");
        outw('h74c,0,1); if(!irq) $fatal(1,"pending IRQ lost while masked");
        outw('h74c,4,1); await_status('h80); outw('h74c,0,1); await_status('h50);
        if(irq) $fatal(1,"SRST failed to clear IRQ");
        // Reset before host ACK must drain the old request, never reuse it.
        taskfile(19,1); outw('h64e,'h20,1);
        @(negedge clk); reset=1;
        repeat(3) @(negedge clk); reset=0;
        await_status('h50);
        if(irq) $fatal(1,"aborted host request interrupted after reset");
        taskfile(20,1); outw('h64e,'h20,1); check_sector(20); await_status('h50);
        mount(0,0); inw('h430,value,1); if(value[7:0]!=0) $fatal(1,"unmount presence");
        inw('h64e,value,1); if(value[7:0]!=0) $fatal(1,"unmounted drive ready");
        mount(511,0); inw('h430,value,1); if(value[7:0]!=0) $fatal(1,"sub-sector image accepted");
        // A trailing partial sector is ignored: 1024+497 bytes is a two-sector drive.
        mount(1521,0); inw('h430,value,1); if(value!==16'hff01) $fatal(1,"image with partial tail rejected");
        outw('h64e,'hec,1); await_status('h58);
        for(int i=0;i<256;i++) begin inw('h640,value,3); if(i==60 && value!==2) $fatal(1,"partial tail capacity %0d",value); end
        $display("PASS PC98 ATA: IDENTIFY, LBA/CHS, 256 sectors, writes, IRQ, lanes, bounds, RO, reset drain (%0d reads/%0d writes)",reads,writes);
        $finish;
    end
    initial begin #50000000; $fatal(1,"IDE test watchdog"); end
endmodule
