`timescale 1ns/1ps
// Replays an NP2kai CPU snapshot on the actual z486 (pc98_ao486 memory path).
// Inputs from snap_gen.py: +dir=OUTDIR (low.bin, ext.bin, restore.txt,
// snap.txt). Once the snapshot instruction issues, the patched loader bytes
// are restored, the caches invalidated, and every issued instruction is
// printed as "I <cs> <eip> <vm>" until +n=COUNT instructions. I/O reads
// return FFFFh unless +io=FILE lists "port value" pairs to return in order.
module z486_snap_tb;
    import z486_pkg::*;
    parameter RAM_MB=64;
    parameter UPPER_RAM_ICACHE=1;   // release builds: -UpperRamICache, PEGC on
    parameter PEGC_ENABLE=1;
    reg clk=0,reset=1;
    always #5 clk=!clk;
    reg cache_invalidate=0;
    reg interrupt_do=0;
    wire cache_upper_ram_native = 1;    // bank 89 selects native RAM
    wire [7:0] interrupt_vector=8'h50;     // VPICD's IRQ0 vector
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
    wire pegc_mode256,pegc_single_page;
    reg [1:0] tb_cpu_speed=0;
    pc98_ao486 #(.EXT_RAM_MB(RAM_MB),.EXT_RAM_READ_CACHE(1),.LOWMEM_CACHE(0),.UPPER_RAM_ICACHE(UPPER_RAM_ICACHE),.PEGC_ENABLE(PEGC_ENABLE)) dut(
        .cpu_speed_sel(tb_cpu_speed),.pegc_analog16(1'b1),.pegc_display_enable(1'b1),.pegc_gdc_5mhz(1'b1),
        .pegc_mode256(pegc_mode256),.pegc_single_page(pegc_single_page),.pegc_pixel_clk(clk),
        .pegc_palette_index(8'b0),.pegc_palette_rgb(),.pegc_video_address(16'b0),
        .pegc_video_burstcount(5'b0),.pegc_video_read(1'b0),.pegc_video_busy(),
        .pegc_video_readdatavalid(),.pegc_video_readdata(),.*);

    reg [7:0] memory[0:1048575];
    reg [7:0] ext[0:RAM_MB*1048576-1];
    integer ticks=0,left=0,ddr_commands=0;
    // +seed=N randomises DDR/legacy latencies and DDR busy cycles (0 = fixed pattern)
    integer seed=0,lat_min=2,lat_rand=6,busy_pct=25;  // +lat_min +lat_rand +busy_pct shape the random mode
    function automatic integer rnd(input integer range);
        rnd = seed==0 ? 0 : $urandom%range;
    endfunction
    reg [31:0] read_addr;
    function automatic [63:0] ext_word(input [31:0] a);
        for(integer j=0;j<8;j=j+1) ext_word[j*8+:8]=ext[a+j];
    endfunction
    always @(posedge clk) begin
        ticks<=ticks+1;
        ddr_busy<=seed==0 ? ticks%7<2 : rnd(100)<busy_pct;
        ddr_readdatavalid<=0;
        if(left!=0) begin
            left<=left-1;
            if(left==1) begin ddr_readdatavalid<=1; ddr_readdata<=ext_word(read_addr); end
        end
        if((ddr_read || ddr_write) && !ddr_busy) begin
            if(left!=0 || ddr_burstcount!=1 || ddr_address[28:25]!=3)
                $fatal(1,"invalid DDR command ordering or region");
            if(ddr_address[24:0] < (32'h100000>>3) || ddr_address[24:0] >= ((RAM_MB*32'h100000)>>3))
                $fatal(1,"CPU escaped extended RAM map");
            if(ddr_write) begin
                for(integer k=0;k<8;k=k+1)
                    if(ddr_byteenable[k]) ext[{ddr_address[24:0],3'b0}+k]=ddr_writedata[k*8+:8];
            end else begin read_addr<={ddr_address[24:0],3'b0}; left<=seed==0 ? 3+ddr_commands%5 : lat_min+rnd(rnd(4)==0 ? 40 : lat_rand); end
            ddr_commands<=ddr_commands+1;
        end
    end

    // I/O replay
    integer io_fd=0,io_n=0;
    reg io_have=0;
    reg [15:0] io_port,io_value;
    task automatic io_next;
        integer r;
        io_have=0;
        if(io_fd!=0 && !$feof(io_fd)) begin
            r=$fscanf(io_fd,"%h %h\n",io_port,io_value);
            io_have=(r==2);
        end
    endtask

    integer phase=0,wait_left=0,legacy_commands=0;
    reg pit_byte=0;
    // +irq_period=P (clocks) +irq_phase=Q: periodic IRQ0 after the snapshot point
    integer irq_period=0,irq_phase=0,irq_count=0,trace_start=0;
    always @(posedge clk) begin
        if(reset || irq_period==0 || !tracing) interrupt_do<=0;
        else if(interrupt_done) begin interrupt_do<=0; irq_count<=irq_count+1; end
        else if(((ticks-trace_start)%irq_period)==irq_phase) interrupt_do<=1;
    end
    reg [19:0] held_address;
    reg [15:0] held_data;
    reg [1:0] held_select;
    reg held_write,held_io;
    reg tracing=0;
    always @(negedge clk) begin
        if(reset) begin phase=0; bus_ack=0; end
        else case(phase)
            0: if(bus_strobe) begin
                held_address={bus_address,1'b0}; held_data=bus_writedata;
                held_select=bus_select; held_write=bus_write; held_io=bus_io;
                wait_left=seed==0 ? legacy_commands%3 : rnd(rnd(4)==0 ? 30 : 4); phase=1;
            end
            1: if(wait_left!=0) wait_left=wait_left-1;
            else begin
                if(held_io) begin
                    bus_readdata=16'hffff;
                    // PIC status reads idle, PIT counters free-running
                    if(held_address[15:0]==16'h0000 || held_address[15:0]==16'h0002 ||
                       held_address[15:0]==16'h0008 || held_address[15:0]==16'h000a) bus_readdata=16'h0000;
                    if(held_address[15:0]==16'h0071 || held_address[15:0]==16'h0073 || held_address[15:0]==16'h0075) begin
                        pit_byte=!pit_byte;
                        bus_readdata={8'hff, pit_byte ? 8'(~(ticks>>4)) : 8'(~(ticks>>12))};
                    end
                    if(tracing) begin
                        if(!held_write && io_have) begin
                            if(io_port!=held_address[15:0])
                                $display("IO MISMATCH read port %h, replay expects %h", held_address[15:0], io_port);
                            bus_readdata=io_value; io_n=io_n+1; io_next();
                        end
                        $display("IO %s %h=%h sel=%b EIP=%h", held_write ? "W" : "R", held_address[15:0],
                                 held_write ? held_data : bus_readdata, held_select, dut.cpu.eip);
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

    // Issue trace
    reg [15:0] snap_cs;
    reg [31:0] snap_eip;
    integer limit=20000,issued=0,restore_fd,quiet=0,no_inval=0,regs=0;
    wire [31:0] issue_eip = (dut.cpu.core.uc_exec && dut.cpu.core.recipe_rni && (dut.cpu.core.uc_dest == DEST_eIP))
        ? (dut.cpu.core.is_dword ? dut.cpu.core.eip_source_value : {16'h0, dut.cpu.core.eip_source_value[15:0]})
        : dut.cpu.core.EIP;
    always @(posedge clk) begin
        if(cache_invalidate) cache_invalidate<=0;
        if(!reset && dut.cpu.core.i_issue) begin
            if(!tracing && dut.cpu.core.CS==snap_cs && issue_eip==snap_eip) begin
                integer r; reg [31:0] a; reg [7:0] v;
                tracing=1; trace_start=ticks;
                restore_fd=$fopen({dir,"/restore.txt"},"r");
                while(!$feof(restore_fd)) begin
                    r=$fscanf(restore_fd,"%h %h\n",a,v);
                    if(r==2) begin if(a<32'h100000) memory[a]=v; else ext[a]=v; end
                end
                $fclose(restore_fd);
                cache_invalidate<=!no_inval;   // +no_inval=1 keeps a warmed cache
                $display("SNAP reached at tick %0d; loader bytes restored", ticks);
            end
            if(tracing) begin
                if(!quiet) begin if(regs) $display("I %04x %08x %0d eax=%08x esi=%08x efl=%08x", dut.cpu.core.CS, issue_eip, dut.cpu.core.EFLAGS[17], dut.cpu.core.EAX, dut.cpu.core.ESI, dut.cpu.core.EFLAGS); else $display("I %04x %08x %0d", dut.cpu.core.CS, issue_eip, dut.cpu.core.EFLAGS[17]); end
                issued=issued+1;
                if(issued>=limit) begin $display("DONE %0d instructions irqs=%0d", issued, irq_count); $finish; end
            end
        end
    end
    // First V86 instruction: the nested Exec_Int call is running.
    reg v86_seen=0;
    always @(posedge clk) if(tracing && !v86_seen && dut.cpu.core.i_issue && dut.cpu.core.EFLAGS[17]) begin
        v86_seen<=1; $display("V86 reached after %0d instructions, %0d clocks", issued, ticks-trace_start);
    end
    // +watch=PHYS: print every change of the 16-bit word at that DDR address
    reg [31:0] watch_addr=0; reg [15:0] watch_last=0; reg watch_on=0;
    always @(posedge clk) if(watch_on) begin
        if({ext[watch_addr+1],ext[watch_addr]}!==watch_last) begin
            $display("WATCH issued=%0d %h -> %h EIP=%h", issued, watch_last, {ext[watch_addr+1],ext[watch_addr]}, dut.cpu.eip);
            watch_last<={ext[watch_addr+1],ext[watch_addr]};
        end
    end
    // +pre=N: before the snapshot is reached, print the first N issues outside
    // the loader's flat code selector 08h (where a failed entry goes).
    integer pre=0;
    always @(posedge clk) if(!reset && !tracing && pre>0 && dut.cpu.core.i_issue && dut.cpu.core.CS!=16'h0008) begin
        $display("P %04x %08x vm=%0d eax=%08x esp=%08x efl=%08x", dut.cpu.core.CS, issue_eip, dut.cpu.core.EFLAGS[17], dut.cpu.core.EAX, dut.cpu.core.ESP, dut.cpu.core.EFLAGS);
        pre=pre-1;
    end
    // +dbg_eip=HEX +dbg_n=N: after the first issue at that EIP, print the
    // pipeline stall/fault state for N clocks (stalled-store debugging).
    reg [31:0] dbg_eip=0, dbg_eip2=0; integer dbg_n=0, dbg_left=0;
    always @(posedge clk) begin
        if(tracing && dbg_n!=0 && dbg_left==0 && dut.cpu.core.i_issue && (issue_eip==dbg_eip || issue_eip==dbg_eip2)) dbg_left=dbg_n;
        if(dbg_left>0) begin
            $display("D t=%0d ua=%03x ex=%0d act=%0d st=%0d mem=%0d wio=%0d d2=%0d fs=%0d ww=%0d ow=%0d svc=%0d rq=%0d acc=%0d pf=%0d pfh=%0d af=%0d afi=%0d ie=%0d iss=%0d rni=%0d dly=%0d EIP=%08x",
                ticks, dut.cpu.core.uc_addr, dut.cpu.core.uc_exec, dut.cpu.core.uc_active, dut.cpu.core.stall,
                dut.cpu.core.stall_mem, dut.cpu.core.stall_wio, dut.cpu.core.stall_d2, dut.cpu.core.stall_fast_store,
                dut.cpu.core.mem_write_wait, dut.cpu.core.mem_opt_wait, dut.cpu.core.mem_servicing,
                dut.cpu.core.mem_req_current, dut.cpu.core.mem_accepted, dut.cpu.core.page_fault,
                dut.cpu.core.pf_store_held, dut.cpu.core.any_fault, dut.cpu.core.any_fault_issue,
                dut.cpu.core.interrupt_entry, dut.cpu.core.i_issue, dut.cpu.core.i_rni, dut.cpu.core.i_rni_delay,
                dut.cpu.core.EIP);
            $display("  P st=%0d lin=%08x wr=%0d cross=%0d lin2=%08x pla=%08x seg=%0d dreq=%0d wbp=%0d fpp=%0d vrp=%0d pff=%0d",
                dut.cpu.core.paging_inst.state, dut.cpu.core.paging_inst.req_linear, dut.cpu.core.paging_inst.req_is_write,
                dut.cpu.core.paging_inst.req_crossing, dut.cpu.core.paging_inst.req_linear2, dut.cpu.core.paging_linear_addr,
                dut.cpu.core.mem_seg_sel, dut.cpu.core.paging_inst.dcache_req_valid_r, dut.cpu.core.paging_inst.walk_biu_pending,
                dut.cpu.core.paging_inst.fast_path_pending, dut.cpu.core.paging_inst.vipt_refill_pending_r,
                dut.cpu.core.paging_inst.pf_fast_pending);
            $display("  R SIG=%08x B=%08x C=%08x D=%08x G=%08x IND=%08x OPR=%08x",
                dut.cpu.core.SIGMA, dut.cpu.core.data_unit_inst.tmpb, dut.cpu.core.data_unit_inst.tmpc,
                dut.cpu.core.data_unit_inst.tmpd, dut.cpu.core.data_unit_inst.tmpg, dut.cpu.core.IND, dut.cpu.core.OPR_R);
            dbg_left=dbg_left-1;
        end
    end
    always @(posedge clk) if(!reset && dut.cpu.triple_fault) begin $display("TRIPLE FAULT EIP=%h", dut.cpu.eip); $finish; end

    string dir,io_path;
    integer fd,loaded;
    initial begin
        if(!$value$plusargs("dir=%s",dir)) $fatal(1,"missing +dir");
        void'($value$plusargs("n=%d",limit));
        void'($value$plusargs("irq_period=%d",irq_period));
        void'($value$plusargs("irq_phase=%d",irq_phase));
        void'($value$plusargs("quiet=%d",quiet));
        void'($value$plusargs("no_inval=%d",no_inval));
        if($value$plusargs("watch=%h",watch_addr)) watch_on=1;
        void'($value$plusargs("regs=%d",regs));
        void'($value$plusargs("dbg_eip=%h",dbg_eip));
        void'($value$plusargs("pre=%d",pre));
        void'($value$plusargs("dbg_eip2=%h",dbg_eip2));
        void'($value$plusargs("dbg_n=%d",dbg_n));
        if($value$plusargs("seed=%d",seed) && seed!=0) void'($urandom(seed));
        void'($value$plusargs("lat_min=%d",lat_min));
        void'($value$plusargs("lat_rand=%d",lat_rand));
        void'($value$plusargs("busy_pct=%d",busy_pct));
        fd=$fopen({dir,"/low.bin"},"rb"); loaded=$fread(memory,fd); $fclose(fd);
        if(loaded!=1048576) $fatal(1,"low.bin size %0d",loaded);
        fd=$fopen({dir,"/ext.bin"},"rb"); loaded=$fread(ext,fd); $fclose(fd);
        if(loaded!=RAM_MB*1048576) $fatal(1,"ext.bin size %0d",loaded);
        fd=$fopen({dir,"/snap.txt"},"r"); loaded=$fscanf(fd,"%h %h",snap_cs,snap_eip); $fclose(fd);
        if($value$plusargs("io=%s",io_path)) begin io_fd=$fopen(io_path,"r"); io_next(); end
        repeat(5) @(negedge clk); reset=0;
    end
    initial begin #1; #(400000000); $display("WATCHDOG issued=%0d EIP=%h", issued, dut.cpu.eip); $finish; end
endmodule
