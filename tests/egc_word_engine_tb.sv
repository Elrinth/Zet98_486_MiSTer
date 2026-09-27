`timescale 1ns/1ps
module egc_word_engine_tb;
    parameter integer CPU_MHZ=60, MEM_PHASE_PS=0, FULL=1;
    initial if ($test$plusargs("trace")) begin
        $dumpfile("egc-engine.vcd");
        $dumpvars(0,egc_word_engine_tb);
    end
    reg clk=0,memclk=0,reset=1,soft_reset=0,egc_enable=1;
    always #(500.0/CPU_MHZ) clk=~clk;
    initial begin #(MEM_PHASE_PS/1000.0); forever #5 memclk=~memclk; end
    reg [15:1] io_address=0;
    reg [1:0] io_select=0;
    reg [15:0] io_writedata=0;
    reg io_strobe=0,io_write=0,request=0,request_write=0;
    reg [21:0] request_address=0;
    reg [1:0] request_bank=0,request_bytes=3;
    reg [15:0] request_writedata=0;
    wire busy,acknowledge,fault;
    wire [15:0] readdata;
    wire [21:0] memory_address;
    wire [1:0] memory_bank,memory_bytes;
    wire [3:0] memory_planes;
    wire [63:0] memory_base,memory_xor_mask,memory_readdata;
    wire memory_read4,memory_rmw4,memory_acknowledge;
    pc98_egc_word_engine dut(.*);
    wire ready,cke,cs,ras,cas,we;
    wire [1:0] dqm,ba;
    wire [12:0] ma;
    wire [15:0] dq;
    reg [15:0] read_source=16'hzzzz;
    assign dq=read_source;
    egc_sdram_port ram(.cpuclk(clk),.memclk(memclk),.reset(reset),
        .read4(memory_read4),.rmw4(memory_rmw4),.address(memory_address),
        .bank(memory_bank),.bytes(memory_bytes),.planes(memory_planes),
        .base_words(memory_base),.xor_masks(memory_xor_mask),.read_words(memory_readdata),
        .ack(memory_acknowledge),.ready(ready),.cke(cke),.cs(cs),.ras(ras),.cas(cas),.we(we),
        .dqm(dqm),.ba(ba),.ma(ma),.dq(dq));

    reg active=0,want_write=0;
    reg [21:0] wanted_address;
    reg [1:0] wanted_bank;
    reg [3:0] wanted_planes;
    reg [63:0] supplied_words,expected_words;
    integer activations=0,reads=0,writes=0,beats=0,burst_left=0,lane=0,requests=0;
    always @(negedge memclk) if(!reset && ready) begin
        if(!cs && !ras && cas && we) begin
            if(!active || ma!==wanted_address[21:9] || ba!==wanted_bank)
                $fatal(1,"EGC SDRAM row/bank mismatch");
            activations=activations+1;
        end
        if(!cs && ras && !cas) begin
            if(!active || ma[9:0]!==wanted_address[9:0] || ba!==wanted_bank)
                $fatal(1,"EGC SDRAM column/bank mismatch");
            if(we) begin
                reads=reads+1;
                read_source<=#20 supplied_words[15:0];
                read_source<=#30 supplied_words[31:16];
                read_source<=#40 supplied_words[47:32];
                read_source<=#50 supplied_words[63:48];
                // Release after the fourth sampling edge, before the next
                // falling-edge write check. Holding until that check creates
                // a Verilog NBA race and artificial read/write contention.
                read_source<=#55 16'hzzzz;
            end else begin
                if(!want_write) $fatal(1,"EGC read issued a write");
                writes=writes+1; burst_left=3; lane=0;
            end
        end else if(burst_left>0) begin lane=4-burst_left; burst_left=burst_left-1; end
        else lane=0;
        if((!cs && ras && !cas && !we) || lane>0) begin
            if(dqm !== (wanted_planes[lane] ? 2'b00 : 2'b11))
                $fatal(1,"EGC write plane mask mismatch lane=%0d",lane);
            if(dq!==expected_words[16*lane +:16])
                $fatal(1,"EGC write result mismatch request=%0d lane=%0d actual=%h expected=%h",
                    requests,lane,dq,expected_words[16*lane +:16]);
            beats=beats+1;
        end
        lane=0;
    end

    reg [15:0] regs[0:7];
    reg [63:0] model_source=0,model_pattern=0;
    reg [15:0] model_clip=16'hffff;
    reg [31:0] pixel_queue[0:3];
    integer queued=0,src_skip=0,dst_skip=0,left_pixels=16;
    function automatic integer native_bit(input integer pixel,input bit reverse_order);
        if(reverse_order) native_bit=pixel<8 ? pixel+8 : pixel-8;
        else native_bit=pixel<8 ? 7-pixel : 23-pixel;
    endfunction
    task restart_shift;
        begin
            queued=0;src_skip=regs[6][3:0];dst_skip=regs[6][7:4];left_pixels=regs[7][11:0]+1;
            for(integer p=0;p<4;p=p+1) pixel_queue[p]=0;
        end
    endtask
    task consume_source(input [63:0] value);
        integer need,available,native;
        begin
            available=queued+16-src_skip;
            for(integer p=0;p<4;p=p+1)
                for(integer j=src_skip;j<16;j=j+1)
                    pixel_queue[p][queued+j-src_skip]=value[16*p+native_bit(j,regs[6][12])];
            src_skip=0;queued=available;need=16-dst_skip;model_clip=0;
            if(available>=need) begin
                model_source=0;
                for(integer j=dst_skip;j<16;j=j+1) begin
                    native=native_bit(j,regs[6][12]);
                    if(j-dst_skip<left_pixels) model_clip[native]=1;
                    for(integer p=0;p<4;p=p+1)
                        model_source[16*p+native]=pixel_queue[p][j-dst_skip];
                end
                for(integer p=0;p<4;p=p+1) pixel_queue[p]=pixel_queue[p] >> need;
                queued=queued-need;left_pixels=left_pixels-need;dst_skip=0;
                if(left_pixels<=0) restart_shift();
            end
        end
    endtask
    task program_register(input integer index,input [15:0] value);
        begin
            @(negedge clk);io_address=(16'h04a0+2*index)>>1;io_select=3;
            io_writedata=value;io_strobe=1;io_write=1;
            repeat(3) @(negedge clk);
            io_strobe=0;io_write=0;
            regs[index]=value;
            if(index==6 || index==7) begin restart_shift();model_clip=16'hffff;end
            repeat(3) @(negedge clk);
        end
    endtask
    function automatic [63:0] raster(input [15:0] data,input [63:0] destination);
        reg [63:0] source,pattern,value,enabled;
        integer index;
        begin
            source=model_source;pattern=model_pattern;
            if(regs[1][14:13]==1 || regs[1][14:13]==2)
                for(integer p=0;p<4;p=p+1)
                    pattern[p*16 +:16]={16{regs[regs[1][14:13]==1 ? 5 : 3][p]}};
            else if(regs[2][9:8]==2) pattern=destination;
            else if(regs[2][12:11]==1 && regs[2][9:8]==1) pattern=source;
            value=0;enabled=0;
            for(integer j=0;j<64;j=j+1) begin
                index=4*source[j]+2*destination[j]+pattern[j];value[j]=regs[2][index];
                enabled[j]=!regs[0][j/16] && regs[4][j%16] && model_clip[j%16];
            end
            if(regs[2][12:11]==0) value={4{data}};
            if(regs[2][12:11]==2) value=pattern;
            raster=(value & enabled) | (destination & ~enabled);
        end
    endfunction
    task transaction(input bit wr,input [21:0] address,input [1:0] bank,
                     input [15:0] data,input [63:0] incoming);
        integer old_reads,old_writes,old_activations,old_beats,watch;
        reg [15:0] expected_read;
        begin
            if(!wr && !regs[2][10]) consume_source(incoming);
            if(wr && (regs[2][12:11]!=1 || regs[2][10])) consume_source({4{data}});
            if(!wr && regs[2][9:8]==1) model_pattern=incoming;
            expected_words=raster(data,incoming);
            if(regs[2][13]) expected_read=incoming[16*address[1:0] +:16];
            else if(regs[2][10]) expected_read=incoming[16*regs[1][9:8] +:16];
            else expected_read=model_source[16*regs[1][9:8] +:16];
            wanted_address={address[21:2],2'b00};wanted_bank=bank;wanted_planes=~regs[0][3:0];
            supplied_words=incoming;want_write=wr;active=1;
            old_reads=reads;old_writes=writes;old_activations=activations;old_beats=beats;
            @(negedge clk);request=1;request_write=wr;request_address=address;
            request_bank=bank;request_bytes=3;request_writedata=data;
            @(negedge clk);
            // Change every live CPU input while the accepted operation waits.
            request_write=~wr;request_address=~address;request_bank=~bank;request_bytes=1;request_writedata=~data;
            watch=0;
            while(!acknowledge && watch<1000) begin @(negedge clk);watch=watch+1;end
            if(!acknowledge || fault) $fatal(1,"EGC request did not complete normally");
            if(wr) begin
                // Posted write: the CPU is released before the RMW reaches memory,
                // and the engine stays busy until the write has completed.
                if(writes!=old_writes) $fatal(1,"EGC write was not posted (acknowledged after the memory write)");
                if(!busy) $fatal(1,"EGC posted write left the engine idle before its memory write");
                watch=0;
                while(busy && watch<1000) begin
                    @(negedge clk);watch=watch+1;
                    if(acknowledge) $fatal(1,"EGC posted write acknowledged twice");
                end
            end
            if(!wr && readdata!==expected_read)
                $fatal(1,"EGC read result mismatch actual=%h expected=%h memory=%h source=%h",
                    readdata,expected_read,memory_readdata,dut.selected_source);
            if(wr && regs[2][9:8]==2) model_pattern=incoming;
            if(reads!=old_reads+1 || writes!=old_writes+wr || activations!=old_activations+1 || beats!=old_beats+4*wr)
                $fatal(1,"EGC memory transaction count mismatch");
            repeat(7) begin @(negedge clk);if(acknowledge || memory_read4 || memory_rmw4) $fatal(1,"EGC held CPU strobe replayed");end
            request=0;active=0;
            repeat(3) @(negedge clk);
            if(busy) $fatal(1,"EGC failed to rearm");
            requests=requests+1;
        end
    endtask
    function automatic [63:0] varying(input integer seed);
        varying={16'(seed*919+16'h93ed),16'(seed*237+16'ha732),16'(seed*41+16'h60c5),16'(seed*811+16'h715e)};
    endfunction
    task abort_transaction(input bit wr,input bit late_reset);
        integer old_reads,old_writes,old_beats,watch;
        begin
            // Non-default source, mask and pattern make clearing registers
            // before the memory write completes observable on the real pins.
            program_register(0,16'hfff2);program_register(1,0);
            program_register(2,16'h0200);program_register(4,16'h5aa5);
            program_register(6,0);program_register(7,15);
            consume_source({4{16'h3ca9}});
            expected_words=raster(16'h3ca9,varying(91));
            wanted_address=22'h30600;wanted_bank=2;wanted_planes=4'b1101;
            supplied_words=varying(91);want_write=wr;active=1;
            old_reads=reads;old_writes=writes;old_beats=beats;
            @(negedge clk);request=1;request_write=wr;request_address=wanted_address;
            request_bank=2;request_bytes=3;request_writedata=16'h3ca9;
            wait(memory_read4 || memory_rmw4);
            if(late_reset) wait(reads>old_reads);
            @(negedge clk);soft_reset=1;request=0;
            repeat(3) begin
                @(negedge clk);
                if(acknowledge || fault) $fatal(1,"EGC aborted request acknowledged");
            end
            soft_reset=0;watch=0;
            while(busy && watch<1000) begin
                @(negedge clk);watch=watch+1;
                if(acknowledge || fault) $fatal(1,"EGC aborted request acknowledged");
            end
            if(busy || reads!=old_reads+1 || writes!=old_writes+wr || beats!=old_beats+4*wr)
                $fatal(1,"EGC reset failed to drain complete memory transaction");
            if(dut.access_control!==16'hfff0 || dut.operation!==0 || dut.pattern_latch!==0 ||
               dut.retained_source!==0 || dut.source_advanced!==0)
                $fatal(1,"EGC soft reset did not clear programming and retained state");
            active=0;
            regs[0]=16'hfff0;regs[1]=16'h00ff;regs[2]=0;regs[3]=0;
            regs[4]=16'hffff;regs[5]=0;regs[6]=0;regs[7]=15;
            model_source=0;model_pattern=0;model_clip=16'hffff;restart_shift();
            repeat(4) @(negedge clk);
            // A new operation must not consume an old completion toggle.
            transaction(1,22'h30610,1,16'h8d17,varying(113));
        end
    endtask
    integer op,alignment,step,rows,copy_case;
    initial begin
        regs[0]=16'hfff0;regs[1]=16'h00ff;regs[2]=0;regs[3]=0;
        regs[4]=16'hffff;regs[5]=0;regs[6]=0;regs[7]=15;
        restart_shift();#137;reset=0;wait(ready);repeat(8) @(negedge clk);
        // CPU, color and retained/raw/fresh-destination pattern operations.
        for(op=0;op<(FULL ? 256 : 16);op=op+1) begin
            program_register(1,0);program_register(4,16'(op*1031) | 16'h00ff);
            program_register(0,16'hfff0 | (op%16));
            program_register(3,op%16);program_register(5,(op+5)%16);
            program_register(6,0);program_register(7,15);
            program_register(1,(op%3)<<13);
            program_register(2,16'h0900 | op);
            transaction(0,22'h12304+(op%4),op%4,0,varying(op));
            program_register(2,16'h0800 | ((op%3)<<8) | op);
            transaction(1,22'h23604,op%4,16'(op*37),varying(op+11));
            program_register(1,0);program_register(2,16'h1000);
            transaction(1,22'h34508,op%4,16'h9aca,varying(op+29));
            program_register(2,16'h0400);
            transaction(1,22'h1450c,op%4,16'(op*19),varying(op+53));
        end
        // All direction/source/destination alignments. Include priming reads,
        // two rows without reprogramming, and writes that must not re-advance S.
        program_register(1,0);program_register(4,16'hffff);program_register(0,16'hfff0);
        program_register(2,16'h28f0);
        for(alignment=0;alignment<(FULL ? 512 : 24);alignment=alignment+1) begin
            program_register(6,((alignment>>8)<<12) | (alignment & 255));
            program_register(7,23);
            for(rows=0;rows<2;rows=rows+1) begin
                step=0;
                do begin
                    transaction(0,22'h20010+4*step,rows,0,varying(alignment*17+step+rows*31));
                    transaction(1,22'h30100+4*step,rows,16'hffff,varying(alignment*7+step));
                    step=step+1;
                end while(!(queued==0 && src_skip==regs[6][3:0] && left_pixels==24) && step<5);
                if(step>=5) $fatal(1,"EGC alignment row did not finish");
            end
        end
        // Game-shaped copies: 640 pixels aligned and 624 pixels with eight
        // source pixels skipped. Both consume forty word pairs per row; the
        // shifted case primes once before writing its 39 useful words.
        // Synthetic pixels only; no game code or assets are included.
        for(copy_case=0;copy_case<2;copy_case=copy_case+1) begin
            program_register(1,16'h00ff);program_register(2,16'h28f0);
            program_register(6,copy_case ? 8 : 0);
            program_register(7,copy_case ? 623 : 639);
            for(rows=0;rows<(FULL ? 3 : 1);rows=rows+1) begin
                for(step=0;step<40;step=step+1) begin
                    transaction(0,22'h20400+4*step+160*rows,0,0,varying(rows*41+step));
                    transaction(1,22'h30500+4*step+160*rows,1,16'hffff,varying(rows*53+step));
                end
                if(queued!=0 || src_skip!=regs[6][3:0] || left_pixels!=(copy_case ? 624 : 640))
                    $fatal(1,"EGC game-shaped row did not complete at forty words");
            end
        end
        abort_transaction(0,0);abort_transaction(0,1);
        abort_transaction(1,0);abort_transaction(1,1);
        // Byte accesses are explicitly rejected while this engine is word-only.
        @(negedge clk);request=1;request_write=1;request_bytes=1;
        wait(acknowledge);#1;
        if(!fault || memory_read4 || memory_rmw4) $fatal(1,"EGC byte access was silently accepted");
        @(negedge clk);request=0;repeat(3) @(negedge clk);
        $display("PASS: EGC word engine/actual SDRAMC %0d transactions at %0dMHz phase=%0d",requests,CPU_MHZ,MEM_PHASE_PS);
        $finish;
    end
    initial begin #20000000;$fatal(1,"EGC word engine watchdog");end
endmodule
