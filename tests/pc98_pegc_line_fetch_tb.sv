// SPDX-License-Identifier: GPL-3.0-or-later
`timescale 1ns/1ps
module pc98_pegc_line_fetch_tb;
    parameter CPU_HALF_PS=5556, VIDEO_PHASE_PS=1300;
    reg cpu_clk=0,video_clk=0,reset=1,video_running=1;
    always #(CPU_HALF_PS/1000.0)cpu_clk=~cpu_clk;
    initial begin #(VIDEO_PHASE_PS/1000.0);forever begin #19.861;if(video_running)video_clk=~video_clk;end end
    reg line_start=0,line_enable=1,active=0;
    reg page_wrap=0;
    reg [18:3] line_address=0;
    reg [9:0] pixel_x=0;
    wire [7:0] pixel_data;
    wire pixel_valid,underrun,line_busy;
    wire [18:3] memory_address;
    wire [4:0] memory_burstcount;
    wire memory_read;
    reg memory_busy=1,memory_readdatavalid=0;
    reg [63:0] memory_readdata=0;
    wire [18:3] fetch_address;
    wire [4:0] fetch_count;
    wire fetch_read,fetch_busy,fetch_valid;
    wire [63:0] fetch_data;
    wire [28:0] ddr_address;
    wire [7:0] ddr_count;
    wire ddr_write;
    pc98_pegc_line_fetch dut(.cpu_clk(cpu_clk),.video_clk(video_clk),.reset(reset),
        .line_start(line_start),.line_enable(line_enable),.line_address(line_address),.page_wrap(page_wrap),
        .active(active),.pixel_x(pixel_x),.pixel_data(pixel_data),.pixel_valid(pixel_valid),
        .underrun(underrun),.line_busy(line_busy),.memory_address(fetch_address),
        .memory_burstcount(fetch_count),.memory_read(fetch_read),.memory_busy(fetch_busy),
        .memory_readdatavalid(fetch_valid),.memory_readdata(fetch_data));
    // Use the production arbiter under continuous competing CPU requests.
    // Responses to those clients must never enter the video line buffer.
    pc98_pegc_ddr_arbiter arbiter(.clk(cpu_clk),.reset(reset),
        .ram_address(29'h06020000),.ram_writedata(64'b0),.ram_byteenable(8'hff),
        .ram_read(1'b1),.ram_write(1'b0),.ram_busy(),.ram_readdatavalid(),
        .fb_address(29'h061e6000),.fb_writedata(64'b0),.fb_byteenable(8'hff),
        .fb_read(1'b1),.fb_write(1'b0),.fb_busy(),.fb_readdatavalid(),
        .video_address(fetch_address),.video_burstcount(fetch_count),.video_read(fetch_read),
        .video_busy(fetch_busy),.video_readdatavalid(fetch_valid),.client_readdata(fetch_data),
        .ddr_address(ddr_address),.ddr_writedata(),.ddr_byteenable(),.ddr_burstcount(ddr_count),
        .ddr_read(memory_read),.ddr_write(ddr_write),.ddr_busy(memory_busy),
        .ddr_readdatavalid(memory_readdatavalid),.ddr_readdata(memory_readdata));
    assign memory_address=ddr_address[15:0];
    assign memory_burstcount=ddr_count[4:0];
    integer checks=0,commands=0,beats=0,underruns=0,ticks=0,remaining=0,delay_left=0,pos=0;
    reg force_stall=0;
    reg expected_visible=0,expected_valid=0;
    reg [18:0] expected_base=0;
    reg [7:0] expected_pixel=0;
    reg stalled=0;
    reg [20:0] held_command;
    function automatic [7:0] pixel(input integer address);
        pixel=(address*7)^(address>>8)^(address>>16)^8'ha7;
    endfunction
    task check(input bit yes,input string reason);
        begin checks=checks+1;if(!yes)$fatal(1,"PEGC line: %s",reason);end
    endtask
    task release_reset;
        begin
            reset=0;
            fork
                begin
                    @(posedge cpu_clk);#0.001;check(dut.cpu_reset===1,"CPU reset released before two local edges");
                    @(posedge cpu_clk);#0.001;check(dut.cpu_reset===0,"CPU reset not released after two local edges");
                end
                begin
                    @(posedge video_clk);#0.001;check(dut.video_reset===1,"pixel reset released before two local edges");
                    @(posedge video_clk);#0.001;check(dut.video_reset===0,"pixel reset not released after two local edges");
                end
            join
            repeat(2)@(negedge video_clk);
        end
    endtask
    always @(posedge cpu_clk) begin
        ticks<=ticks+1;
        memory_busy<=force_stall || ticks%7<2;
        memory_readdatavalid<=0;
        if(stalled && !reset)check(memory_read && held_command==={memory_address,memory_burstcount},"stalled command changed");
        stalled<=memory_read && memory_busy && !reset;
        held_command<={memory_address,memory_burstcount};
        if(remaining!=0)begin
            if(delay_left!=0)delay_left<=delay_left-1;
            else begin
                for(integer b=0;b<8;b=b+1)memory_readdata[b*8+:8]<=pixel(pos*8+b);
                memory_readdatavalid<=1;pos<=pos+1;remaining<=remaining-1;
                delay_left<=ticks%3;
            end
        end
        if(memory_read && !memory_busy)begin
            check(!reset,"read while reset");
            check(!ddr_write && (ddr_address[28:16]==13'h61e || ddr_address==29'h06020000),"DDR region");
            check(remaining==0 && !memory_readdatavalid,"read overtook response");
            check(memory_burstcount>=1 && memory_burstcount<=16,"burst bound");
            check({1'b0,memory_address}+memory_burstcount<=65536,"burst crossed framebuffer end");
            commands<=commands+1;pos<=memory_address;remaining<=memory_burstcount;delay_left<=ticks%11+4;
        end
        if(memory_readdatavalid)beats<=beats+1;
    end
    // Independent expected byte stream; never derives visibility from DUT.
    always @(posedge video_clk) begin
        #0.001;
        if(reset)expected_valid=0;
        check(pixel_valid===expected_valid,"pixel validity/deadline alignment");
        if(expected_valid)check(pixel_data===expected_pixel,"packed pixel order/stale line");
        expected_valid=!reset && active && expected_visible && line_enable && pixel_x<640;
        expected_pixel=pixel(page_wrap ? ((expected_base&19'h40000)|((expected_base+pixel_x)&19'h3ffff)) : ((expected_base+pixel_x)&19'h7ffff));
        if(underrun)underruns=underruns+1;
    end
    task row(input [18:0] base,input bit visible);
        begin
            @(negedge video_clk);active=0;line_start=1;line_address=base[18:3];
            expected_base=base;expected_visible=visible;
            @(negedge video_clk);line_start=0;
            repeat(159)@(negedge video_clk); // 160 clocks including line_start: actual 6.36 us blank
            for(integer x=0;x<640;x=x+1)begin
                active=1;pixel_x=x;@(negedge video_clk);
            end
            active=0;repeat(3)@(negedge video_clk);
        end
    endtask
    integer i,old_underruns;
    initial begin
        repeat(4)@(negedge video_clk);release_reset();
        row(0,1);row(640,1);row(19'h7ffb8,1); // wrap after nine 64-bit words
        row(19'h3fff8,1);row(19'h40000,1);
        page_wrap=1;row(19'h3fff8,1);row(19'h7fff8,1);page_wrap=0;
        old_underruns=underruns;
        // Keep one fetch stalled across two rows. Releasing it during the
        // second active row must not publish its old address or partial data.
        force_stall=1;
        row(19'h11100,0);
        fork
            row(19'h22200,0);
            begin repeat(330)@(negedge video_clk);force_stall=0;end
        join
        check(underruns==old_underruns+2,"missing late-line underrun report");
        row(19'h33300,1);
        // Disable at a row boundary: no new DDR fetch or visible data.
        line_enable=0;row(19'h44400,0);line_enable=1;row(19'h55500,1);
        // Reset in the middle of a gapped DDR return, then request a new row.
        @(negedge video_clk);line_start=1;line_address=16'h6000;expected_visible=0;
        @(negedge video_clk);line_start=0;
        while(!fetch_valid)@(negedge cpu_clk);
        reset=1;repeat(4)@(negedge video_clk);release_reset();
        row(19'h12340,1);
        // Reset with pixel clock stopped while valid pixels were in flight.
        // Restart must not expose the old pipeline for even one pixel.
        @(negedge video_clk);active=1;pixel_x=0;
        repeat(3)@(negedge video_clk);
        video_running=0;reset=1;active=0;expected_visible=0;expected_valid=0;
        repeat(5)@(negedge cpu_clk);check(!pixel_valid,"stopped-clock reset left valid pixel");
        reset=0;repeat(5)@(negedge cpu_clk);
        check(dut.video_reset===1,"pixel reset released with stopped clock");video_running=1;
        repeat(4)@(negedge video_clk);row(19'h56780,1);
        check(!line_busy,"unfinished line transaction");
        $display("PASS: PEGC line CPU half=%0d phase=%0d: %0d commands/%0d beats/%0d checks, wrap/underrun/reset",CPU_HALF_PS,VIDEO_PHASE_PS,commands,beats,checks);
        $finish;
    end
    initial begin #2000000;$fatal(1,"PEGC line watchdog");end
endmodule
