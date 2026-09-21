`timescale 1ns/1ps
module pc98_lowmem_cache_tb;
    reg clk=0; always #5 clk=!clk;
    reg reset=1, invalidate=0;
    reg [19:1] address=0;
    reg [1:0] select=0;
    reg write=0, io=0, strobe=0;
    wire legacy_strobe, ack;
    reg legacy_ack=0;
    reg [15:0] legacy_readdata=0;
    wire [15:0] readdata;
    reg [15:0] writedata=0;
    pc98_lowmem_cache dut(.*);
    reg [15:0] memory[0:524287];
    reg [15:0] ports[0:32767];
    integer phase=0, delay_left=0, transfers=0, reads=0, writes=0;
    integer held_addr;
    reg [1:0] held_select;
    reg held_write, held_io;
    reg [15:0] held_data;
    always @(posedge clk) begin
        if(reset) begin phase<=0; legacy_ack<=0; end
        else case(phase)
            0: if(legacy_strobe) begin
                held_addr=address; held_select=select; held_write=write;
                held_io=io; held_data=writedata;
                delay_left<=5; phase<=1;
            end
            1: begin
                if(!legacy_strobe || address!=held_addr || select!=held_select ||
                   write!=held_write || io!=held_io || writedata!=held_data)
                    $fatal(1,"legacy request changed while stalled");
                if(delay_left!=0) delay_left<=delay_left-1;
                else if(!invalidate) begin
                    if(write) begin
                        if(select[0]) memory[address][7:0]=writedata[7:0];
                        if(select[1]) memory[address][15:8]=writedata[15:8];
                        writes<=writes+1;
                    end else reads<=reads+1;
                    legacy_readdata<=io ? ports[address[15:1]] : memory[address]; legacy_ack<=1;
                    phase<=2; transfers<=transfers+1;
                end
            end
            2: if(!legacy_strobe) begin delay_left<=3; phase<=3; end
            3: if(delay_left!=0) delay_left<=delay_left-1;
               else begin legacy_ack<=0; phase<=0; end
        endcase
    end
    task begin_request(input bit wr,input reg [19:0] a,input reg [1:0] be,input reg [15:0] d,input bit port);
        begin
            @(negedge clk);
            if(ack) $fatal(1,"new transaction before ACK release");
            address=a[19:1]; select=be; writedata=d; write=wr; io=port; strobe=1;
        end
    endtask
    task finish_request;
        reg [15:0] answer;
        begin
            @(negedge clk); while(!ack) @(negedge clk);
            answer=readdata;
            if(!write && answer!==(io ? ports[address[15:1]] : memory[address]))
                $fatal(1,"low RAM stale read at %h actual=%h expected=%h",{address,1'b0},answer,io ? ports[address[15:1]] : memory[address]);
            repeat(2) begin
                @(negedge clk);
                if(!ack || (!write && readdata!==answer)) $fatal(1,"ACK/data not held");
            end
            strobe=0;
            @(negedge clk); while(ack) @(negedge clk);
            @(negedge clk);
        end
    endtask
    task transact(input bit wr,input reg [19:0] a,input reg [1:0] be,input reg [15:0] d,input bit port);
        begin begin_request(wr,a,be,d,port); finish_request; end
    endtask
    integer i,n,before_count;
    reg [19:0] a;
    reg [31:0] random_state=32'h1759cf31;
    initial begin
        for(i=0;i<524288;i=i+1) memory[i]=(i*907)^16'ha55a;
        for(i=0;i<32768;i=i+1) ports[i]=(i*317)^16'h916d;
        repeat(4) @(negedge clk); reset=0;
        transact(0,20'h1234,3,0,0);
        before_count=transfers;
        repeat(8) transact(0,20'h1234,3,0,0);
        if(transfers!=before_count) $fatal(1,"warm read missed");
        for(n=0;n<4;n=n+1) begin
            transact(1,20'h1234,n,16'h6cb7^(n*103),0);
            transact(0,20'h1234,3,0,0);
        end
        // Same index, distinct physical tags.
        transact(0,20'h3234,3,0,0); transact(0,20'h1234,3,0,0);
        // I/O and every upper-memory region must always fetch current data.
        for(n=0;n<9;n=n+1) begin
            a=n==8 ? 20'h1234 : 20'h80000+n*20'h10000;
            transact(0,a,3,0,n==8);
            if(n==8) ports[a>>1]=ports[a>>1]^16'h7182;
            else memory[a>>1]=memory[a>>1]^16'h7182;
            before_count=transfers;
            transact(0,a,3,0,n==8);
            if(transfers!=before_count+1) $fatal(1,"uncacheable read hit cache");
        end
        // Clear all valid slots, including entries away from the current index.
        for(n=0;n<4096;n=n+1) transact(0,n*2,3,0,0);
        @(negedge clk); invalidate=1;
        for(n=0;n<4096;n=n+1) memory[n]=memory[n]^16'h49d3;
        repeat(4) @(negedge clk); invalidate=0;
        for(n=0;n<4096;n=n+1) transact(0,n*2,3,0,0);
        // Invalidation during an outstanding miss must prevent stale refills.
        begin_request(0,20'h6234,3,0,0);
        @(negedge clk); while(!legacy_strobe) @(negedge clk);
        invalidate=1; memory[20'h6234>>1]=16'hfa91;
        repeat(5) @(negedge clk); invalidate=0;
        finish_request;
        memory[20'h6234>>1]=16'h9347;
        before_count=transfers;
        transact(0,20'h6234,3,0,0);
        if(transfers!=before_count+1) $fatal(1,"invalidated miss incorrectly refilled cache");
        // Invalidate a hit before its ACK can be accepted.
        begin_request(0,20'h6234,3,0,0);
        @(negedge clk); while(dut.state!=3) @(negedge clk);
        invalidate=1; memory[20'h6234>>1]=16'h571c;
        #1; if(ack) $fatal(1,"invalidated hit acknowledged stale data");
        repeat(5) @(negedge clk); invalidate=0;
        finish_request;
        for(n=0;n<3000;n=n+1) begin
            random_state=random_state^(random_state<<13);
            random_state=random_state^(random_state>>17);
            random_state=random_state^(random_state<<5);
            a={random_state[15:0],4'b0}&20'h7ffff;
            transact(0,a,3,0,0); transact(0,a,3,0,0);
            transact(1,a,random_state[17:16],random_state[31:16],0);
            transact(0,a,3,0,0);
        end
        @(negedge clk); reset=1;
        memory[20'h6234>>1]=16'ha4e6;
        repeat(3) @(negedge clk); reset=0;
        transact(0,20'h6234,3,0,0);
        $display("PASS: low RAM read cache: warm hits, tags, all byte masks, 4096-slot flush, in-flight invalidation, uncached I/O/VRAM/ROM, reset; %0d transfers",transfers);
        $finish;
    end
    initial begin #5000000; $fatal(1,"low RAM cache watchdog"); end
endmodule
