// SPDX-License-Identifier: GPL-3.0-or-later
`timescale 1ns/1ps
module pc98_pegc_ddr_tb;
    parameter SEED=1;
    reg clk=0,reset=1;
    always #5 clk=~clk;
    reg [18:1] address=0;
    reg [1:0] select=3;
    reg [15:0] writedata=0;
    reg write=0,strobe=0;
    wire ack;
    wire [15:0] readdata;
    wire [28:0] fb_address;
    wire [63:0] fb_writedata;
    wire [7:0] fb_byteenable;
    wire fb_read,fb_write,fb_busy,fb_readdatavalid;
    reg [28:0] ram_address=0;
    reg [63:0] ram_writedata=0;
    reg [7:0] ram_byteenable=0;
    reg ram_read=0,ram_write=0;
    wire ram_busy,ram_readdatavalid;
    reg [18:3] video_address=0;
    reg [4:0] video_burstcount=0;
    reg video_read=0;
    wire video_busy,video_readdatavalid;
    wire [63:0] client_readdata;
    wire [28:0] ddr_address;
    wire [63:0] ddr_writedata;
    wire [7:0] ddr_byteenable,ddr_burstcount;
    wire ddr_read,ddr_write;
    reg ddr_busy=1,ddr_readdatavalid=0;
    reg [63:0] ddr_readdata=0;
    pc98_pegc_memory cpu_fb(.clk(clk),.reset(reset),.address(address),.select(select),
        .writedata(writedata),.write(write),.strobe(strobe),.ack(ack),.readdata(readdata),
        .ddr_address(fb_address),.ddr_writedata(fb_writedata),.ddr_byteenable(fb_byteenable),
        .ddr_read(fb_read),.ddr_write(fb_write),.ddr_busy(fb_busy),
        .ddr_readdatavalid(fb_readdatavalid),.ddr_readdata(client_readdata));
    pc98_pegc_ddr_arbiter arbiter(.*);
    localparam FB_BASE=(32'h30f00000>>3), RAM_BASE=(32'h30100000>>3);
    reg [63:0] pixels[0:65535],ram[0:255];
    reg [63:0] expected_fb[0:65535];
    integer cycles=0,commands=0,returns=0,checks=0,read_left=0,delay_left=0;
    integer read_pos=0,owner=-1,command_owner=-1;
    reg read_fb=0;
    reg [31:0] random_state=SEED;
    reg force_busy=0,force_delay=0;
    reg was_stalled=0;
    reg [111:0] stalled_command;
    reg [28:0] return_address;
    integer lane;
    task check(input bit good,input string reason);
        begin checks=checks+1;if(!good)$fatal(1,"PEGC DDR: %s",reason);end
    endtask
    function automatic [63:0] initial_pixel(input integer pos);
        initial_pixel={32'h62550000^(pos*32'd37),32'ha0b10000^(pos*32'd137)};
    endfunction
    // MiSTer DDR model: independent waitrequest and gapped, tagged responses.
    // It does NOT reset with the guest, just like an accepted real DDR read.
    always @(posedge clk) begin
        cycles<=cycles+1;
        random_state<={random_state[30:0],random_state[31]^random_state[21]^random_state[1]^random_state[0]};
        ddr_busy<=force_busy || random_state[3:0]<5;
        ddr_readdatavalid<=0;
        if(was_stalled && !reset) begin
            check(ddr_read || ddr_write,"stalled command withdrawn");
            check({ddr_address,ddr_writedata,ddr_byteenable,ddr_burstcount,ddr_read,ddr_write}===stalled_command,
                  "stalled command changed owner/data");
        end
        was_stalled<=(ddr_read || ddr_write) && ddr_busy && !reset;
        stalled_command<={ddr_address,ddr_writedata,ddr_byteenable,ddr_burstcount,ddr_read,ddr_write};
        if(ddr_readdatavalid) begin
            check((ram_readdatavalid+{1'b0,fb_readdatavalid}+{1'b0,video_readdatavalid})==1,"response fanout/loss");
            check(owner==0 ? ram_readdatavalid : owner==1 ? fb_readdatavalid : video_readdatavalid,
                  "late response reached wrong owner");
            returns<=returns+1;
        end
        if(read_left!=0) begin
            if(delay_left!=0) delay_left<=delay_left-1;
            else begin
                ddr_readdata<=read_fb ? pixels[read_pos] : ram[read_pos];
                ddr_readdatavalid<=1;
                read_left<=read_left-1;read_pos<=read_pos+1;
                delay_left<=random_state[6:4];
            end
        end
        if((ddr_read || ddr_write) && !ddr_busy) begin
            check(!reset,"command accepted during reset");
            check(!(ddr_read && ddr_write),"simultaneous read/write");
            check(read_left==0 && !ddr_readdatavalid,"command overtook read response");
            command_owner = !ram_busy && (ram_read || ram_write) ? 0 :
                            !fb_busy && (fb_read || fb_write) ? 1 :
                            !video_busy && video_read ? 2 : -1;
            check(command_owner>=0,"accepted command without client");
            check(command_owner==2 ? ddr_burstcount>=1 && ddr_burstcount<=16 : ddr_burstcount==1,"burst bound");
            if(command_owner!=0) begin
                check(ddr_address>=FB_BASE && ddr_address+ddr_burstcount<=FB_BASE+65536,"framebuffer escaped reserved region");
            end else check(ddr_address>=RAM_BASE && ddr_address+ddr_burstcount<=RAM_BASE+256,"ordinary RAM address");
            if(ddr_write) begin
                for(lane=0;lane<8;lane=lane+1) if(ddr_byteenable[lane]) begin
                    if(command_owner==1)pixels[ddr_address-FB_BASE][lane*8+:8]=ddr_writedata[lane*8+:8];
                    else ram[ddr_address-RAM_BASE][lane*8+:8]=ddr_writedata[lane*8+:8];
                end
            end else begin
                read_fb<=command_owner!=0;
                read_pos<=ddr_address-(command_owner==0 ? RAM_BASE : FB_BASE);
                owner<=command_owner;read_left<=ddr_burstcount;
                delay_left<=force_delay ? 90 : (3+random_state[10:7]);
            end
            commands<=commands+1;
        end
    end
    task fb_start(input bit wr,input [18:0] bytepos,input [1:0] be,input [15:0] data);
        begin @(negedge clk);address=bytepos[18:1];select=be;writedata=data;write=wr;strobe=1;end
    endtask
    task fb_finish;
        integer count;
        begin
            count=0;
            while(!ack)begin @(negedge clk);count=count+1;check(count<1200,"framebuffer starvation");end
            repeat(3)begin @(negedge clk);check(ack,"ack not held");end
            strobe=0;@(negedge clk);check(!ack,"ack failed release");
        end
    endtask
    task fb_case(input [18:0] a,input [1:0] mask,input [15:0] value);
        integer wordpos,bitpos;
        begin
            wordpos=a>>3;bitpos=(a&7)*8;
            fb_start(1,a,mask,value);fb_finish;
            if(mask[0])expected_fb[wordpos][bitpos+:8]=value[7:0];
            if(mask[1])expected_fb[wordpos][bitpos+8+:8]=value[15:8];
            fb_start(0,a,3,0);fb_finish;
            check(readdata===expected_fb[wordpos][bitpos+:16],"CPU framebuffer byte-write/read mismatch");
        end
    endtask
    task ordinary_case(input integer idx);
        reg [63:0] value;
        integer count;
        begin
            value={32'h19830000+idx,32'h20260000^idx};
            @(negedge clk);ram_address=RAM_BASE+idx;ram_writedata=value;ram_byteenable=255;ram_write=1;
            count=0;
            @(posedge clk);while(ram_busy)begin @(posedge clk);count=count+1;check(count<1200,"ordinary RAM starvation");end
            @(negedge clk);ram_write=0;ram_read=1;
            @(posedge clk);while(ram_busy)@(posedge clk);
            @(negedge clk);ram_read=0;
            while(!ram_readdatavalid)@(negedge clk);
            check(client_readdata===value,"ordinary RAM response/data");
            @(negedge clk);
        end
    endtask
    task video_chunk(input [15:0] pos,input [4:0] count);
        integer n,waited;
        begin
            @(negedge clk);video_address=pos;video_burstcount=count;video_read=1;waited=0;
            @(posedge clk);while(video_busy)begin @(posedge clk);waited=waited+1;check(waited<1200,"video starvation");end
            @(negedge clk);video_read=0;n=0;
            while(n<count)begin
                if(video_readdatavalid)begin
                    check(client_readdata===expected_fb[pos+n],"video framebuffer byte order/data");n=n+1;
                end
                @(negedge clk);
            end
        end
    endtask
    integer i,commands_before;
    initial begin
        for(i=0;i<65536;i=i+1)begin pixels[i]=initial_pixel(i);expected_fb[i]=initial_pixel(i);end
        for(i=0;i<256;i=i+1)ram[i]=0;
        repeat(4)@(negedge clk);reset=0;
        fork
            begin for(integer r=0;r<120;r=r+1)ordinary_case(r);end
            begin for(integer a=0;a<256;a=a+1)fb_case(a*2,a%4,16'ha56c^(a*131));end
            begin for(integer v=0;v<100;v=v+1)video_chunk(16'h4000+v*16,1+v%16);end
        join
        // CPU writes must be visible to the other read client, all lanes.
        for(i=0;i<64;i=i+16)video_chunk(i,16);
        for(i=0;i<16;i=i+1)fb_case(i*32768+32766,3,i*313+19);
        video_chunk(16'hfff0,16);
        // Reject invalid video requests, including crossing the reserved end.
        for(i=0;i<3;i=i+1)begin
            @(negedge clk);commands_before=commands;video_read=1;
            video_address=i==2?16'hffff:0;video_burstcount=i==0?0:i==1?17:2;
            repeat(15)@(negedge clk);
            check(video_busy && commands==commands_before,"invalid video burst accepted");video_read=0;
        end
        // Cancel unaccepted framebuffer write during a forced DDR stall.
        force_busy=1;repeat(3)@(negedge clk);commands_before=commands;
        fb_start(1,19'h01234,3,16'hdead);repeat(5)@(negedge clk);
        reset=1;strobe=0;repeat(3)@(negedge clk);force_busy=0;reset=0;
        repeat(8)@(negedge clk);check(commands==commands_before,"pre-accept cancellation wrote memory");
        // Accepted framebuffer read survives reset in DDR, but must be drained
        // into its original bridge, not delivered to the next CPU transaction.
        force_delay=1;fb_start(0,19'h1ffe0,3,0);
        while(read_left==0)@(negedge clk);
        reset=1;strobe=0;repeat(3)@(negedge clk);reset=0;force_delay=0;
        fork
            begin fb_start(0,19'h03ffe,3,0);fb_finish;
                check(readdata===expected_fb[19'h03ffe>>3][63:48],"stale framebuffer response survived reset");end
            ordinary_case(200);
            video_chunk(16'h6000,16);
        join
        // Reset while a gapped video burst is returning. All remaining beats
        // retain their tag even when clients have dropped their commands.
        force_delay=1;
        @(negedge clk);video_address=16'h6100;video_burstcount=16;video_read=1;
        @(posedge clk);while(video_busy)@(posedge clk);
        @(negedge clk);video_read=0;
        while(!video_readdatavalid)@(negedge clk);
        reset=1;repeat(3)@(negedge clk);reset=0;force_delay=0;
        fork
            ordinary_case(201);
            begin fb_start(0,0,3,0);fb_finish;check(readdata===expected_fb[0][15:0],"video reset contaminated CPU");end
        join
        check(read_left==0,"test ended with outstanding DDR data");
        $display("PASS: PEGC DDR seed=%0d, %0d commands/%0d returns/%0d checks: lanes, stalls, fairness, reset drain, region bounds",SEED,commands,returns,checks);
        $finish;
    end
    initial begin #10000000;$fatal(1,"PEGC DDR watchdog");end
endmodule
