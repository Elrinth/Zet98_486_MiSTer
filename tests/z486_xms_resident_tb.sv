`timescale 1ns/1ps
module z486_xms_resident_tb;
    parameter DDR_WORDS=8192;
    parameter RAM_MB=16;
    parameter DOS_PROBE=0;
    parameter READ_CACHE=1;
    parameter LOWMEM_CACHE=0;
    parameter MEMORY_INIT=0;
    parameter PEGC_ENABLE=0;
    parameter EARLY_WRITE_COMPLETE=1;
    parameter TRACE_LIMIT=2000;
    parameter PIT_PM_TEST=0;
    parameter PM_PAYLOAD_TEST=0;
    parameter PM_MIN_DDR=1000;
    parameter WATCHDOG_NS=50000000;
    // RANDOM_WAIT>0: each bus access waits a random 0..RANDOM_WAIT-1 clocks
    // (SDRAM refresh/video contention on hardware) instead of 0..2.
    parameter RANDOM_WAIT=0;
    reg clk=0,reset=1;
    integer reset_after_read=0,reset_hold=0;
    bit reset_injected=0;
    initial void'($value$plusargs("reset_after_read=%d",reset_after_read));
    // Optional guest reset during a real DDR read. DDR storage and its delayed
    // response deliberately continue while the CPU and frontend restart.
    always @(negedge clk) begin
        if(reset_after_read!=0 && !reset_injected && left!=0) begin
            reset_injected=1;reset_hold=3;reset=1;
            $display("RESET pending DDR read; response must drain before reboot");
        end else if(reset_hold!=0) begin
            reset_hold=reset_hold-1;
            if(reset_hold==0) reset=0;
        end
    end
    always #5 clk=!clk;
    wire cache_invalidate=0;
    reg interrupt_do=0;
    wire cache_upper_ram_native = 0;
    wire [7:0] interrupt_vector=PIT_PM_TEST ? 8'h08 : 0;
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
    // +cpu_speed=N drives the z486 execution-rate throttle (0=full). Slower
    // settings scale the watchdog unless +watchdog_scale=N overrides it.
    reg [1:0] tb_cpu_speed=0;
    integer watchdog_scale=1,speed_arg=0;
    initial begin
        if($value$plusargs("cpu_speed=%d",speed_arg)) tb_cpu_speed=speed_arg[1:0];
        watchdog_scale=tb_cpu_speed==0 ? 1 : tb_cpu_speed==1 ? 4 : tb_cpu_speed==2 ? 16 : 40;
        void'($value$plusargs("watchdog_scale=%d",watchdog_scale));
    end
    // Execution-rate evidence: wall cycles, issued instructions, and cycles
    // the throttle charged as execution, printed with the PASS line.
    integer rate_cycles=0,rate_issued=0,rate_active=0;
    always @(posedge clk) if(!reset) begin
        rate_cycles<=rate_cycles+1;
        if(dut.cpu.core.i_issue) rate_issued<=rate_issued+1;
        if(dut.cpu.core.throttle_active_cycle) rate_active<=rate_active+1;
    end
    pc98_ao486 #(.EXT_RAM_MB(RAM_MB),.EXT_RAM_READ_CACHE(READ_CACHE),.LOWMEM_CACHE(LOWMEM_CACHE),.PEGC_ENABLE(PEGC_ENABLE),.EARLY_WRITE_COMPLETE(EARLY_WRITE_COMPLETE)) dut(
        .cpu_speed_sel(tb_cpu_speed),.pegc_analog16(1'b1),.pegc_display_enable(1'b1),.pegc_gdc_5mhz(1'b1),
        .pegc_mode256(pegc_mode256),.pegc_single_page(pegc_single_page),.pegc_pixel_clk(clk),
        .pegc_palette_index(8'b0),.pegc_palette_rgb(),.pegc_video_address(16'b0),
        .pegc_video_burstcount(5'b0),.pegc_video_read(1'b0),.pegc_video_busy(),
        .pegc_video_readdatavalid(),.pegc_video_readdata(),.*);
    reg [7:0] memory[0:1048575];
    reg [28:0] keys[0:DDR_WORDS-1];
    reg [63:0] words[0:DDR_WORDS-1];
    integer used=0,ddr_commands=0,left=0,read_index=0,ticks=0,boots=0;
    integer n,k,found;
    reg [7:0] resident_original[0:4095];
    integer resized=0;
    integer verify_copy=0;
    bit has_resident=0;
    string resident_path;
    integer checked_words=0;
    reg [7:0] irq_mask=8'hff;
    integer irq_accepted=0,irq_eoi=0;
    integer irq_window=0,irq_window_start=0;  // clocks with IRQ0 unmasked
    always @(posedge clk) if(PIT_PM_TEST) begin
        if(reset || irq_mask[0]) interrupt_do<=0;
        else if(interrupt_done) begin
            interrupt_do<=0;
            irq_accepted<=irq_accepted+1;
        end else if(ticks%10000==0) interrupt_do<=1;
    end
    function automatic [63:0] pattern_word(input [28:0] address);
        reg [31:0] byte_addr;
        begin
            byte_addr={address[24:0],3'b0};
            pattern_word=0;
            if(PM_PAYLOAD_TEST)
                for(integer j=0;j<8;j=j+1)
                    pattern_word[j*8+:8]=8'((byte_addr+j)*37+((byte_addr+j)>>8)+((byte_addr+j)>>16));
            if(!PM_PAYLOAD_TEST && byte_addr>=32'h110000 && byte_addr<32'h114c00)
                for(integer j=0;j<8;j=j+1) pattern_word[j*8+:8]=8'((byte_addr+j)*19+37);
        end
    endfunction
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
               (ddr_address[24:0] >= ((PEGC_ENABLE ? 32'hf80000 : 32'hf00000)>>3) && ddr_address[24:0] < (32'h1000000>>3)))
                $fatal(1,"CPU escaped extended RAM map");
            found=-1;
            for(n=0;n<used;n=n+1) if(keys[n]==ddr_address) found=n;
            if(found<0) begin
                if(used==DDR_WORDS) $fatal(1,"DDR model table full");
                found=used; used=used+1; keys[found]=ddr_address;
                words[found]=pattern_word(ddr_address);
            end
            if(ddr_write) begin
                for(k=0;k<8;k=k+1)
                    if(ddr_byteenable[k]) words[found][k*8+:8]=ddr_writedata[k*8+:8];
            end else begin read_index<=found; left<=3+ddr_commands%5; end
            ddr_commands<=ddr_commands+1;
        end
    end
    integer phase=0,wait_left=0,legacy_commands=0;
    integer payload_fault_traces=0;
    always @(posedge clk) if(PM_PAYLOAD_TEST && dut.cpu.core.EBP==101 && dut.cpu.core.pe &&
                            dut.cpu.core.seg_unit.seg_sel==4 &&
                            (dut.cpu.core.gp_fault_mem_op || dut.cpu.core.vipt_load_ex_r.valid || dut.cpu.core.vipt_slow_submit) && payload_fault_traces<12) begin
        payload_fault_traces<=payload_fault_traces+1;
        $display("PM LIMIT raw=%h G=%b selected=%h offset=%h check=%b fault=%b EIP=%h",
          dut.cpu.core.seg_unit.desc_cache[4].limit,dut.cpu.core.seg_unit.desc_cache[4].G,
          dut.cpu.core.seg_unit.seg_limit_r,dut.cpu.core.seg_unit.eff_offset,
          dut.cpu.core.seg_unit.check_en,dut.cpu.core.seg_gp_fault,dut.cpu.eip);
        $display("PM PIPE ex=%b probed=%b hit=%b block=%b shadow=%b submit=%b memop=%b faultTrigger=%b",
          dut.cpu.core.vipt_load_ex_r.valid,dut.cpu.core.vipt_load_ex_probed_r,dut.cpu.core.vipt_load_ex_hit,
          dut.cpu.core.vipt_load_exec_block,dut.cpu.core.vipt_load_rom_shadow_r,dut.cpu.core.vipt_slow_submit,
          dut.cpu.core.gp_fault_mem_op,dut.cpu.core.gp_fault_trigger);
    end
`ifdef RMW_TRACE
    // Ring buffer of data-side activity inside the RMW-reload loop copies,
    // printed when the program reports a failure through port 7FE4h.
    string rmw_ring[0:511];
    integer rmw_ring_at=0;
    reg [31:0] trace_lo=32'h1fc,trace_hi=32'h227;
    initial begin void'($value$plusargs("trace_lo=%h",trace_lo)); void'($value$plusargs("trace_hi=%h",trace_hi)); end
    always @(posedge clk) if(!reset && dut.cpu.core.pe && dut.cpu.eip>=trace_lo && dut.cpu.eip<trace_hi) begin
        rmw_ring[rmw_ring_at%512]=$sformatf("t=%0d eip=%h ua=%h ESI=%h EDX=%h EAX=%h issue=%b rmwfast=%b vload=%b vwait=%b vprobe=%b/%h res=%b rdata=%h req=%b w=%b pa=%h wd=%h acc=%b rdone=%b sq=%0d st=%0d",
            ticks,dut.cpu.eip,dut.cpu.core.uaddr,dut.cpu.core.ESI,dut.cpu.core.EDX,dut.cpu.core.EAX,
            dut.cpu.core.i_issue,dut.cpu.core.rd_fast_issue,dut.cpu.core.vipt_issue_load,dut.cpu.core.vipt_issue_store_wait,
            dut.cpu.core.dcache_vipt_probe_valid,dut.cpu.core.dcache_vipt_probe_offset,dut.cpu.core.dcache_vipt_resolve_valid,
            dut.cpu.core.dcache_vipt_resolve_data,dut.cpu.core.dcache_req_valid,dut.cpu.core.dcache_req_write,
            dut.cpu.core.dcache_req_phys_addr_raw,dut.cpu.core.dcache_req_wdata,dut.cpu.core.dcache_req_accepted,
            dut.cpu.core.dcache_read_complete,dut.cpu.core.memory_inst.dcache_inst.storeq_count,
            dut.cpu.core.memory_inst.dcache_inst.state);
        rmw_ring[rmw_ring_at%512]={rmw_ring[rmw_ring_at%512],$sformatf(" | eax=%h exec=%b dest=%h dsel=%0d lwb=%b/%0d/%b/%h rmem=%b/%0d cancel=%b rni=%b hw=%b csel=%0d alu=%h opr=%h",
            dut.cpu.core.data_unit_inst.eax,dut.cpu.core.data_unit_inst.exec,dut.cpu.core.data_unit_inst.dest,
            dut.cpu.core.data_unit_inst.dst_reg_sel_r,
            dut.cpu.core.data_unit_inst.load_wb_valid,dut.cpu.core.data_unit_inst.load_wb_dst,
            dut.cpu.core.data_unit_inst.load_wb_is_alu,dut.cpu.core.data_unit_inst.load_wb_commit_data,
            dut.cpu.core.data_unit_inst.recipe_memory_write.valid,dut.cpu.core.data_unit_inst.recipe_memory_write.dst,
            dut.cpu.core.data_unit_inst.recipe_commit_cancel,dut.cpu.core.data_unit_inst.recipe_rni,
            dut.cpu.core.data_unit_inst.recipe_state.hardwired,dut.cpu.core.data_unit_inst.recipe_state.commit_sel,
            dut.cpu.core.data_unit_inst.alu_result,dut.cpu.core.data_unit_inst.opr_r)};
        rmw_ring[rmw_ring_at%512]={rmw_ring[rmw_ring_at%512],$sformatf(" | ex=%b/%b hit=%b slow=%b/%b rep=%b msv=%b stall=%b",
            dut.cpu.core.vipt_load_ex_r.valid,dut.cpu.core.vipt_load_ex_probed_r,dut.cpu.core.vipt_load_ex_hit,
            dut.cpu.core.vipt_load_slow_req_r,dut.cpu.core.vipt_load_slow_wait_r,dut.cpu.core.vipt_load_replay_r.valid,
            dut.cpu.core.mem_servicing,dut.cpu.core.stall)};
        rmw_ring_at=rmw_ring_at+1;
    end
    task automatic dump_rmw_ring;
        for(integer r=(rmw_ring_at>512?rmw_ring_at-512:0);r<rmw_ring_at;r=r+1) $display("%s",rmw_ring[r%512]);
    endtask
`endif
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
                wait_left=RANDOM_WAIT>0 ? $urandom%RANDOM_WAIT : legacy_commands%3; phase=1;
            end
            1: if(wait_left!=0) wait_left=wait_left-1;
            else begin
                if(held_io) begin
                    if(PEGC_ENABLE && pegc_mode256 && held_address>=20'ha8 && held_address<=20'hae)
                        $fatal(1,"PEGC palette leaked onto legacy I/O");
                    bus_readdata=16'hffff;
                    if(PIT_PM_TEST && held_address==2) begin
                        bus_readdata={8'hff,irq_mask};
                        if(held_write) begin
                            if(irq_mask[0] && !held_data[0]) irq_window_start=ticks;
                            if(!irq_mask[0] && held_data[0]) irq_window=irq_window+ticks-irq_window_start;
                            irq_mask=held_data[7:0];
                        end
                    end
                    if(PIT_PM_TEST && held_write && held_address==0 && held_data[7:0]==8'h20)
                        irq_eoi=irq_eoi+1;
                    if(held_write && held_address==20'hf2) boots=boots+1;
`ifdef RMW_TRACE
                    if(held_write && (held_address==20'h7fe4 || held_address==20'h7ff0)) dump_rmw_ring();
`endif
                    if(held_write && held_address==20'h7fe4)
                        $display("CPU REPORT EAX=%h EBX=%h ECX=%h EDX=%h ESI=%h EDI=%h EBP=%h ESP=%h EIP=%h cycles=%0d DDR=%0d",
                          dut.cpu.core.EAX,dut.cpu.core.EBX,dut.cpu.core.ECX,dut.cpu.core.EDX,
                          dut.cpu.core.ESI,dut.cpu.core.EDI,dut.cpu.core.EBP,dut.cpu.core.ESP,dut.cpu.eip,rate_cycles,ddr_commands);
                    if(PM_PAYLOAD_TEST && held_write && held_address==20'h7fe0)
                        $display("PM FAIL stage=%0d crc=%h address=%h length=%h fault=%h DDR=%0d",
                          dut.cpu.core.EBP,dut.cpu.core.EAX,dut.cpu.core.EBX,dut.cpu.core.ECX,dut.cpu.core.ESI,ddr_commands);
                    if(PM_PAYLOAD_TEST && held_write && held_address==20'h7fe2)
                        $display("PM descriptor at %h: %h %h %h %h %h %h %h %h",held_data,
                          memory[20'h10000+held_data],memory[20'h10001+held_data],
                          memory[20'h10002+held_data],memory[20'h10003+held_data],
                          memory[20'h10004+held_data],memory[20'h10005+held_data],
                          memory[20'h10006+held_data],memory[20'h10007+held_data]);
                    if(held_write && held_address==20'h7ff0) begin
                        if(held_data!=16'h600d) $fatal(1,"protected-mode extended memory program failed");
                        if(PM_PAYLOAD_TEST && ddr_commands<PM_MIN_DDR)
                            $fatal(1,"Protected payload did not traverse extended memory");
                        if(PIT_PM_TEST) begin
                            if(irq_accepted<3 || irq_eoi<irq_accepted || irq_mask!=8'hff)
                                $fatal(1,"incomplete protected IRQ control accepted=%0d eoi=%0d mask=%h",irq_accepted,irq_eoi,irq_mask);
                            $display("PASS: protected32 IRQ/IRETD and real-mode restoration; accepted=%0d EOI=%0d window=%0d",irq_accepted,irq_eoi,irq_window);
                        end
                        for(integer j=0;j<16'h664;j=j+1)
                            if(has_resident && j>=16'h70 && memory[20'h058d0+j]!==resident_original[j])
                                $fatal(1,"resident driver code corrupted at %h",j);
                        if(verify_copy) begin
                            for(integer j=0;j<used;j=j+1)
                                if(keys[j][24:0]>=(32'h1000000>>3) && keys[j][24:0]<(32'h1004c00>>3)) begin
                                    if(words[j]!==pattern_word(keys[j]-(32'hef0000>>3)))
                                        $fatal(1,"XMS copied data mismatch at %h",keys[j]);
                                    checked_words=checked_words+1;
                                end
                            if(checked_words!=2432) $fatal(1,"incomplete XMS copy %0d words",checked_words);
                            if({memory[20'h05f3d],memory[20'h05f3c],memory[20'h05f3b],memory[20'h05f3a]}!=(resized ? 35 : 19))
                                $fatal(1,"incorrect grown/original handle size");
                        end
                        if($value$plusargs("dump=%s",dump_path)) begin
                            // Differential tests compare conventional RAM 40000h-9FFFFh with a reference CPU.
                            dump_fd=$fopen(dump_path,"wb");
                            for(integer a=32'h40000;a<32'ha0000;a=a+1) $fwrite(dump_fd,"%c",memory[a]);
                            $fclose(dump_fd);
                        end
                        $display("RATE speed=%0d cycles=%0d issued=%0d active=%0d",tb_cpu_speed,rate_cycles,rate_issued,rate_active);
                        $display("PASS: actual z486 resident XMS call; preserved driver code, verified %0d data bytes, resize=%0d DDR=%0d",checked_words*8,resized,ddr_commands);
                        $finish;
                    end
                end else begin
                    if(PEGC_ENABLE && pegc_mode256 &&
                       ((held_address>=20'ha8000 && held_address<20'hc0000) ||
                        (held_address>=20'he0000 && held_address<20'he8000)))
                        $fatal(1,"PEGC framebuffer/MMIO leaked onto legacy memory");
                    if(held_write) begin
                        if(held_address>=20'h05f00 && held_address<20'h06000) $display("XMS WRITE %h=%h mask=%b EIP=%h",held_address,held_data,held_select,dut.cpu.eip);
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
    string program_path,dump_path;
    integer program_cs;
    integer dump_fd;
    integer fd,loaded,i;
    initial begin
        for(i=0;i<1048576;i=i+1) memory[i]=0;
        if(!$value$plusargs("program=%s",program_path)) $fatal(1,"missing CPU program");
        fd=$fopen(program_path,"rb"); if(!fd) $fatal(1,"cannot open CPU program");
        program_cs=DOS_PROBE ? 16'h1000 : 0;
        void'($value$plusargs("program_cs=%h",program_cs));
        if(program_cs<0 || program_cs>16'he000)
            $fatal(1,"program segment outside conventional/upper RAM");
        loaded=$fread(memory,fd,(program_cs<<4)+(DOS_PROBE ? 256 : 4096)); $fclose(fd);
        if(!loaded) $fatal(1,"empty CPU program");
        has_resident=$value$plusargs("resident=%s",resident_path);
        if(has_resident) begin
            fd=$fopen(resident_path,"rb");
            if(!fd) $fatal(1,"missing separately supplied resident XMS snapshot");
            loaded=$fread(memory,fd,20'h058d0); $fclose(fd);
            if(loaded!=4096) $fatal(1,"invalid resident snapshot size");
            for(i=0;i<4096;i=i+1) resident_original[i]=memory[20'h058d0+i];
        end
        if($value$plusargs("resized=%d",resized)) begin
            if(!has_resident) $fatal(1,"XMS operation requires resident fixture");
            verify_copy=1;
        end
        memory[20'hffff0]=8'hea; memory[20'hffff1]=0; memory[20'hffff2]=DOS_PROBE ? 1 : 8'h10;
        memory[20'hffff3]=program_cs[7:0]; memory[20'hffff4]=program_cs[15:8];
        repeat(5) @(negedge clk); reset=0;
    end
`ifdef V86_IRQ_TRACE
    reg irq_do_d=0; integer irq_trace_n=0;
    always @(posedge clk) begin
        irq_do_d<=interrupt_do;
        if((interrupt_do!=irq_do_d || interrupt_done) && irq_trace_n<40) begin
            irq_trace_n<=irq_trace_n+1;
            $display("IRQTRACE t=%0t do=%b done=%b mask=%h acc=%0d eoi=%0d IF=%b VM=%b EIP=%h",$time,interrupt_do,interrupt_done,
                     irq_mask,irq_accepted,irq_eoi,dut.cpu.core.EFLAGS[9],dut.cpu.core.EFLAGS[17],dut.cpu.eip);
        end
    end
    integer uc_trace_left=0;
    reg good_traced=0;
    reg [11:0] last_uaddr=0;
    always @(posedge clk) begin
        if((interrupt_done && irq_accepted==0) || (dut.cpu.core.uaddr==12'h8b4 && dut.cpu.core.vm && !good_traced)) begin
            uc_trace_left<=(interrupt_done ? 700 : 700);
            if(!interrupt_done) good_traced<=1;
            $display("UCTRACE ---- start %s mem[10828]=%h %h %h %h %h %h %h %h mem[10850]=%h %h %h %h %h %h %h %h", interrupt_done ? "IRQ" : "GP-FROM-V86",
                memory[20'h10828],memory[20'h10829],memory[20'h1082a],memory[20'h1082b],memory[20'h1082c],memory[20'h1082d],memory[20'h1082e],memory[20'h1082f],
                memory[20'h10850],memory[20'h10851],memory[20'h10852],memory[20'h10853],memory[20'h10854],memory[20'h10855],memory[20'h10856],memory[20'h10857]);
        end
        else if(uc_trace_left>0) begin
            uc_trace_left<=uc_trace_left-1;
            if(dut.cpu.core.protection_unit_inst.result_now || dut.cpu.core.protection_unit_inst.jump_valid)
                $display("PROTTRACE t=%0t uaddr=%h jv=%b jaddr=%h redir=%b sv=%b cpl=%d ecpl=%d vm=%b pe=%b rpl=%d dpl=%d testaddr=%h gp=%b",
                    $time,dut.cpu.core.uaddr,dut.cpu.core.protection_unit_inst.jump_valid,dut.cpu.core.protection_unit_inst.jump_addr,
                    dut.cpu.core.protection_unit_inst.redirect_taken,dut.cpu.core.protection_unit_inst.state_vector_comb,
                    dut.cpu.core.protection_unit_inst.cpl,dut.cpu.core.protection_unit_inst.effective_cpl,dut.cpu.core.vm,
                    dut.cpu.core.protection_unit_inst.pe_mode,dut.cpu.core.protection_unit_inst.selector_rpl,
                    dut.cpu.core.protection_unit_inst.descriptor_dpl_live,dut.cpu.core.protection_unit_inst.pla_test_addr,dut.cpu.core.gp_fault_trigger);
            if(dut.cpu.core.uaddr!=last_uaddr) begin
                last_uaddr<=dut.cpu.core.uaddr;
                if(dut.cpu.core.uaddr>=12'h8b4 && dut.cpu.core.uaddr<=12'h8b9) $display("DESCTRACE uaddr=%h OPR_R=%h desc_hi=%h",dut.cpu.core.uaddr,dut.cpu.core.OPR_R,dut.cpu.core.desc_raw_hi);
                $display("UCTRACE t=%0t uaddr=%h EIP=%h ESP=%h CS=%h VM=%b stall=%b memreq=%b lin=%h fault=%b",$time,dut.cpu.core.uaddr,dut.cpu.eip,
                         dut.cpu.core.ESP,dut.cpu.core.CS,dut.cpu.core.EFLAGS[17],dut.cpu.core.stall,dut.cpu.core.mem_req_current,
                         dut.cpu.core.paging_inst.req_linear,dut.cpu.core.page_fault);
            end
        end
    end
`endif
`ifdef V86_TRACE
    always @(posedge clk) if(!reset && (dut.cpu.core.paging_inst.walk_request || dut.cpu.core.paging_inst.walk_fault ||
                               (dut.cpu.core.mem_req_current && dut.cpu.core.vm)))
        $display("V86TRACE t=%0t walkreq=%b fault=%b code=%b req_write=%b req_cpl=%d chk=%b | memreq=%b uc_wr=%b uc_cw=%b vslow=%b pgwr=%b pgcpl=%d lin=%h EIP=%h",
          $time,dut.cpu.core.paging_inst.walk_request,dut.cpu.core.paging_inst.walk_fault,dut.cpu.core.paging_inst.walk_fault_code,
          dut.cpu.core.paging_inst.req_is_write,dut.cpu.core.paging_inst.req_cpl,dut.cpu.core.paging_inst.req_check_only,
          dut.cpu.core.mem_req_current,dut.cpu.core.uc_is_write,dut.cpu.core.uc_is_check_write,dut.cpu.core.vipt_slow_submit,
          dut.cpu.core.paging_is_write_access,dut.cpu.core.pg_cpl,dut.cpu.core.paging_inst.req_linear,dut.cpu.eip);
`endif
`ifdef FLAG_TRACE
    // Per-cycle flag pipeline view while EIP is inside [ftrace_lo, ftrace_hi).
    reg [31:0] ftrace_lo=32'h0, ftrace_hi=32'h0;
    initial begin void'($value$plusargs("ftrace_lo=%h",ftrace_lo)); void'($value$plusargs("ftrace_hi=%h",ftrace_hi)); end
    always @(posedge clk) if(!reset && dut.cpu.eip>=ftrace_lo && dut.cpu.eip<ftrace_hi)
        $display("FT t=%0d eip=%h ua=%h issue=%b exec=%b stall=%b shcommit=%b zf=%b zf_fwd=%b eflags=%h aluop=%0d",
            ticks, dut.cpu.eip, dut.cpu.core.uaddr, dut.cpu.core.i_issue, dut.cpu.core.data_unit_inst.exec,
            dut.cpu.core.stall, dut.cpu.core.data_unit_inst.sh_flags_commit,
            dut.cpu.core.data_unit_inst.eflags[6], dut.cpu.core.data_unit_inst.eflags_fwd[6],
            dut.cpu.core.data_unit_inst.eflags, dut.cpu.core.data_unit_inst.aluop);
`endif
    reg [31:0] last_eip=0;
    integer shown=0;
    always @(posedge clk) if(!reset && dut.cpu.eip!=last_eip) begin
        last_eip<=dut.cpu.eip;
        if(shown<TRACE_LIMIT) begin
            shown<=shown+1;
            $display("XMS EIP=%h uaddr=%h DDR=%0d AX=%h BX=%h CX=%h DX=%h SI=%h DI=%h SP=%h DS=%h",dut.cpu.eip,dut.cpu.core.uaddr,ddr_commands,dut.cpu.core.EAX,dut.cpu.core.EBX,dut.cpu.core.ECX,dut.cpu.core.EDX,dut.cpu.core.ESI,dut.cpu.core.EDI,dut.cpu.core.ESP,dut.cpu.core.seg_unit.desc_cache[3].base);
        end
    end
    initial begin #1; repeat(watchdog_scale) #(WATCHDOG_NS); $fatal(1,"XMS watchdog EIP=%h uaddr=%h DDR=%0d triple=%b",dut.cpu.eip,dut.cpu.core.uaddr,ddr_commands,dut.cpu.triple_fault); end
endmodule
