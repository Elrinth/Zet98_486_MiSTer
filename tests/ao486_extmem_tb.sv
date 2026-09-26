`timescale 1ns/1ps
module ao486_extmem_tb;
    parameter RAM_MB=16;
    parameter DOS_PROBE=0;
    parameter READ_CACHE=1;
    parameter LOWMEM_CACHE=0;
    parameter MEMORY_INIT=0;
    reg clk=0,reset=1;
    always #5 clk=!clk;
    wire cache_invalidate=0,interrupt_do=0;
    wire cache_upper_ram_native = 0;
    wire [7:0] interrupt_vector=0;
    wire interrupt_done,unmapped_access;
    wire [19:1] bus_address;
    wire [1:0] bus_select;
    wire [15:0] bus_writedata;
    wire bus_write,bus_strobe,bus_io;
    reg [15:0] bus_readdata=0;
    reg bus_ack=0;
    wire [127:0] debug_snapshot;
    wire [28:0] ddr_address;
    wire [63:0] ddr_writedata;
    wire [7:0] ddr_byteenable,ddr_burstcount;
    wire ddr_read,ddr_write;
    reg ddr_busy=0,ddr_readdatavalid=0;
    reg [63:0] ddr_readdata=0;
    pc98_ao486 #(.EXT_RAM_MB(RAM_MB),.EXT_RAM_READ_CACHE(READ_CACHE),.LOWMEM_CACHE(LOWMEM_CACHE)) dut(
        .pegc_analog16(1'b0),.pegc_display_enable(1'b0),.pegc_gdc_5mhz(1'b0),
        .pegc_mode256(),.pegc_single_page(),.pegc_pixel_clk(clk),
        .pegc_palette_index(8'b0),.pegc_palette_rgb(),.pegc_video_address(16'b0),
        .pegc_video_burstcount(5'b0),.pegc_video_read(1'b0),.pegc_video_busy(),
        .pegc_video_readdatavalid(),.pegc_video_readdata(),
        .cpu_speed_sel(2'b0),.*);
    reg [7:0] memory[0:1048575];
    reg [28:0] keys[0:255];
    reg [63:0] words[0:255];
    integer used=0,ddr_commands=0,left=0,read_index=0,ticks=0,boots=0;
    integer n,k,found;
    always @(posedge clk) begin
        ticks<=ticks+1;
        ddr_busy<=ticks%7<2;
        ddr_readdatavalid<=0;
        if(left!=0) begin
            left<=left-1;
            if(left==1) begin ddr_readdatavalid<=1; ddr_readdata<=words[read_index]; end
        end
        if((ddr_read || ddr_write) && !ddr_busy) begin
            if(left!=0 || ddr_burstcount!=1 || ddr_address[28:25]!=3)
                $fatal(1,"invalid DDR command ordering or region");
            if(ddr_address[24:0] < (32'h100000>>3) ||
               ddr_address[24:0] >= ((RAM_MB*32'h100000)>>3) ||
               (ddr_address[24:0] >= (32'hf00000>>3) && ddr_address[24:0] < (32'h1000000>>3)))
                $fatal(1,"CPU escaped extended RAM map");
            found=-1;
            for(n=0;n<used;n=n+1) if(keys[n]==ddr_address) found=n;
            if(found<0) begin
                if(used==256) $fatal(1,"DDR model table full");
                found=used; used=used+1; keys[found]=ddr_address;
                words[found]=MEMORY_INIT ? (64'ha5987e21c0359bf4 ^ ddr_address) : 0;
            end
            if(ddr_write) begin
                for(k=0;k<8;k=k+1)
                    if(ddr_byteenable[k]) words[found][k*8+:8]=ddr_writedata[k*8+:8];
            end else begin read_index<=found; left<=3+ddr_commands%5; end
            ddr_commands<=ddr_commands+1;
        end
    end
    integer phase=0,wait_left=0,legacy_commands=0;
    reg [19:0] held_address;
    reg [15:0] held_data;
    reg [1:0] held_select;
    reg held_write,held_io;
    always @(negedge clk) begin
        if(reset) begin phase=0; bus_ack=0; end
        else case(phase)
            0: if(bus_strobe) begin
                held_address={bus_address,1'b0}; held_data=bus_writedata;
                held_select=bus_select; held_write=bus_write; held_io=bus_io;
                wait_left=legacy_commands%3; phase=1;
            end
            1: if(wait_left!=0) wait_left=wait_left-1;
            else begin
                if(held_io) begin
                    bus_readdata=16'hffff;
                    if(held_write && held_address==20'hf2) boots=boots+1;
                    if(held_write && held_address==20'h7ff0) begin
                        if(held_data!=16'h600d) $fatal(1,"protected-mode extended memory program failed");
                        if(MEMORY_INIT) begin
                            if(boots!=1 || !dut.cpu.real_mode || dut.a20_enable)
                                $fatal(1,"memory initializer failed mode/A20 restoration");
                            if(memory[20'h401]!=(RAM_MB==0 ? 0 : 112) ||
                               {memory[20'h595],memory[20'h594]}!=(RAM_MB==64 ? 48 : 0))
                                $fatal(1,"incorrect PC-98 BIOS memory counts");
                            if(memory[20'h501]!=(RAM_MB==0 ? identity_flag : (identity_flag & 8'hbf)) ||
                               memory[20'h480]!=8'h50 || memory[20'h500]!=8'h03)
                                $fatal(1,"incorrect CPU identity correction or unrelated BIOS mutation");
                            for(n=0;n<used;n=n+1) if(words[n]!=(64'ha5987e21c0359bf4 ^ keys[n]))
                                $fatal(1,"memory initializer did not restore probe words");
                            $display("PASS: memory initializer %0d MB: real driver entry, BIOS counts, preserved RAM, restored mode/A20",RAM_MB);
                            $finish;
                        end
                        else if(DOS_PROBE) begin
                            if(boots!=1 || ddr_commands<80 || !dut.cpu.real_mode)
                                $fatal(1,"DOS probe did not return to real-mode code");
                            $display("PASS: DOS RAM probe protected-mode tests and real-mode return, %0d MB, %0d DDR commands",RAM_MB,ddr_commands);
                            $finish;
                        end
                        else begin
                            if(boots!=2 || ddr_commands<150) $fatal(1,"missing CPU reset or DDR traffic");
                            $display("PASS: actual ao486 %0d MB RAM: protected mode, partial/unaligned writes, REP MOVSD, DDR code execution, CPU reset; %0d DDR commands",RAM_MB,ddr_commands);
                            $finish;
                        end
                    end
                end else begin
                    if(held_write) begin
                        if(held_select[0]) memory[held_address]=held_data[7:0];
                        if(held_select[1]) memory[held_address+20'd1]=held_data[15:8];
                    end
                    bus_readdata={memory[held_address+20'd1],memory[held_address]};
                end
                bus_ack=1; phase=2; legacy_commands=legacy_commands+1;
            end
            2: if(!bus_strobe) begin phase=0; bus_ack=0; end
        endcase
    end
    string program_path;
    integer fd,loaded,i,identity_flag=8'he7;
    initial begin
        for(i=0;i<1048576;i=i+1) memory[i]=0;
        if(MEMORY_INIT) begin
            if($value$plusargs("identity_flag=%d",identity_flag)) begin end
            memory[20'h480]=8'h50; memory[20'h500]=8'h03; memory[20'h501]=identity_flag;
        end
        if(!$value$plusargs("program=%s",program_path)) $fatal(1,"missing CPU program");
        fd=$fopen(program_path,"rb"); if(!fd) $fatal(1,"cannot open CPU program");
        loaded=$fread(memory,fd,DOS_PROBE ? 20'h10100 : 4096); $fclose(fd);
        if(!loaded) $fatal(1,"empty CPU program");
        memory[20'hffff0]=8'hea; memory[20'hffff1]=0; memory[20'hffff2]=DOS_PROBE ? 1 : 8'h10;
        memory[20'hffff3]=0; memory[20'hffff4]=DOS_PROBE ? 8'h10 : 0;
        repeat(5) @(negedge clk); reset=0;
    end
    initial begin #10000000; $fatal(1,"extended CPU watchdog"); end
endmodule
