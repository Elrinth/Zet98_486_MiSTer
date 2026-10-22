`timescale 1ns/1ps
// pc98_dma_ddr: random CPU DDR traffic (bursts, writes, busy, latency) mixed
// with DMA byte cycles. Checks data both ways, DDR command stability while
// busy, response routing and a DMA service bound.
module pc98_dma_ddr_tb;
    parameter SEED = 1;
    reg clk=0, reset=1;
    always #5 clk=!clk;

    reg [23:0] dma_address=0;
    reg dma_read=0, dma_write=0;
    reg [7:0] dma_writedata=0;
    wire dma_ack;
    wire [7:0] dma_readdata;
    reg [28:0] cpu_address=0;
    reg [63:0] cpu_writedata=0;
    reg [7:0] cpu_byteenable=0, cpu_burstcount=1;
    reg cpu_read=0, cpu_write=0;
    wire cpu_busy, cpu_readdatavalid;
    wire [28:0] ddr_address;
    wire [63:0] ddr_writedata;
    wire [7:0] ddr_byteenable, ddr_burstcount;
    wire ddr_read, ddr_write;
    reg ddr_busy=0, ddr_readdatavalid=0;
    reg [63:0] ddr_readdata=0;
    pc98_dma_ddr dut(.*);

    // DDR model: 4096 words, address bits 11:0. CPU uses words 800h-FFFh,
    // DMA bytes 100000h-103FFFh (words 30000000h/8 + 20000h.. -> 000h-7FFh).
    reg [63:0] mem[0:4095];
    reg [63:0] shadow[0:4095];          // expected contents
    reg [11:0] q_addr[0:255];
    integer q_head=0, q_tail=0, q_wait=0, seed=SEED, i, errors=0;
    reg [28:0] last_address; reg [63:0] last_data; reg [7:0] last_be, last_count;
    reg last_read=0, last_write=0, last_refused=0;
    function automatic [11:0] widx(input [28:0] a); widx=a[11:0]; endfunction
    always @(posedge clk) begin
        ddr_busy <= ($random(seed) & 3) == 0;
        ddr_readdatavalid <= 0;
        // Avalon: a refused command must be presented unchanged.
        if (last_refused && !(ddr_read==last_read && ddr_write==last_write &&
            ddr_address==last_address && ddr_writedata==last_data &&
            ddr_byteenable==last_be && ddr_burstcount==last_count)) begin
            $display("FAIL: command changed while busy at %0t", $time); errors=errors+1;
        end
        last_refused <= (ddr_read || ddr_write) && ddr_busy;
        {last_read,last_write,last_address,last_data,last_be,last_count} <=
            {ddr_read,ddr_write,ddr_address,ddr_writedata,ddr_byteenable,ddr_burstcount};
        if (ddr_write && !ddr_busy)
            for (i=0;i<8;i=i+1) if (ddr_byteenable[i]) mem[widx(ddr_address)][i*8+:8] <= ddr_writedata[i*8+:8];
        if (ddr_read && !ddr_busy)
            for (i=0;i<ddr_burstcount;i=i+1) begin q_addr[q_tail[7:0]] = widx(ddr_address)+i; q_tail = q_tail+1; end
        if (q_head!=q_tail) begin
            if (q_wait==0) q_wait = 1 + ($random(seed) & 7);
            else if (q_wait==1) begin
                ddr_readdatavalid <= 1; ddr_readdata <= mem[q_addr[q_head[7:0]]];
                q_head = q_head+1; q_wait = 0;
            end else q_wait = q_wait-1;
        end
    end

    // CPU master: random reads (bursts 1-4) and writes on words 800h-FFFh.
    integer cpu_ops=0, cpu_beats_left=0, cpu_expect_idx=0;
    reg [11:0] cpu_base;
    always @(posedge clk) if (!reset) begin
        if (cpu_readdatavalid) begin
            if (cpu_beats_left==0) begin $display("FAIL: stray CPU response"); errors=errors+1; end
            else begin
                if (ddr_readdata !== shadow[cpu_expect_idx]) begin
                    $display("FAIL: CPU read %h got %h want %h", cpu_expect_idx, ddr_readdata, shadow[cpu_expect_idx]);
                    errors=errors+1;
                end
                cpu_expect_idx = cpu_expect_idx+1; cpu_beats_left = cpu_beats_left-1;
            end
        end
        if ((cpu_read||cpu_write) && !cpu_busy) begin
            if (cpu_write) begin
                for (i=0;i<8;i=i+1) if (cpu_byteenable[i]) shadow[widx(cpu_address)][i*8+:8] = cpu_writedata[i*8+:8];
            end else begin
                cpu_expect_idx = widx(cpu_address); cpu_beats_left = cpu_burstcount;
            end
            cpu_read <= 0; cpu_write <= 0; cpu_ops = cpu_ops+1;
        end else if (!cpu_read && !cpu_write && cpu_beats_left==0 && ($random(seed)&1)) begin
            cpu_base = 12'h800 | ($random(seed) & 12'h7f8);
            cpu_address <= {4'h3,13'h0,cpu_base};
            if ($random(seed) & 1) begin
                cpu_write <= 1; cpu_burstcount <= 1;
                cpu_writedata <= {$random(seed),$random(seed)};
                cpu_byteenable <= $random(seed) | 8'h01;
            end else begin
                cpu_read <= 1; cpu_burstcount <= 1 + ($random(seed) & 3);
            end
        end
    end

    // DMA: byte writes/reads at 100000h-103FFFh, strobe held until ack.
    integer dma_ops=0, dma_wait=0, dma_max=0, idle=0;
    reg [7:0] want;
    always @(posedge clk) if (!reset) begin
        if (dma_read || dma_write) begin
            dma_wait = dma_wait+1;
            if (dma_ack) begin
                if (dma_read) begin
                    want = shadow[{1'b0,dma_address[13:3]}][dma_address[2:0]*8+:8];
                    if (dma_readdata !== want) begin
                        $display("FAIL: DMA read %h got %h want %h", dma_address, dma_readdata, want); errors=errors+1;
                    end
                end else shadow[{1'b0,dma_address[13:3]}][dma_address[2:0]*8+:8] = dma_writedata;
                if (dma_wait>dma_max) dma_max=dma_wait;
                dma_read<=0; dma_write<=0; dma_ops=dma_ops+1; idle=0;
            end
        end else if (dut.state==0 && !dma_ack) begin
            idle = idle+1;
            if (idle>2 && ($random(seed)&7)==0) begin
                dma_wait=0;
                dma_address <= 24'h100000 | ($random(seed) & 24'h3fff);
                dma_writedata <= $random(seed);
                if ($random(seed)&1) dma_write<=1; else dma_read<=1;
            end
        end
    end

    initial begin
        for (i=0;i<4096;i=i+1) begin mem[i]={i[15:0],~i[15:0],i[15:0]^16'h5a5a,16'h1234}; shadow[i]=mem[i]; end
        repeat(4) @(posedge clk);
        reset<=0;
        repeat(60000) @(posedge clk);
        for (i=0;i<4096;i=i+1) if (mem[i]!==shadow[i]) begin
            if (errors<10) $display("FAIL: word %h is %h want %h", i, mem[i], shadow[i]);
            errors=errors+1;
        end
        if (dma_ops<500 || cpu_ops<5000) begin $display("FAIL: too little traffic dma %0d cpu %0d", dma_ops, cpu_ops); errors=errors+1; end
        if (dma_max>200) begin $display("FAIL: DMA waited %0d clocks", dma_max); errors=errors+1; end
        if (errors) begin $display("FAIL seed %0d: %0d errors", SEED, errors); $fatal(1); end
        $display("PASS seed %0d: %0d DMA bytes (max wait %0d), %0d CPU commands", SEED, dma_ops, dma_max, cpu_ops);
        $finish;
    end
endmodule
