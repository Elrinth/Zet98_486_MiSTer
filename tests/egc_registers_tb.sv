`timescale 1ns/1ps
// Exercise the production CPU I/O splitter, including odd words and DWORDs.
// Reference state is updated from software byte addresses, not RTL indexes.
module egc_registers_tb;
    reg clk=0, reset=1, egc_enable=0;
    always #5 clk=~clk;
    reg io_read_do=0, io_write_do=0;
    reg [15:0] io_read_address=0, io_write_address=0;
    reg [2:0] io_read_length=1, io_write_length=1;
    reg [31:0] io_write_data=0;
    wire [31:0] io_read_data;
    wire io_read_done,io_write_done,busy;
    wire [15:1] bus_address;
    wire [1:0] bus_select;
    wire [15:0] bus_writedata;
    wire bus_write,bus_strobe;
    reg bus_ack=0;
    wire [15:0] bus_readdata=16'hffff;
    integer waits=0,hold=3;
    ao486_io_bridge bridge(.*);

    reg decode_sweep=0;
    reg [15:1] sweep_address=0;
    wire [15:1] address=decode_sweep ? sweep_address : bus_address;
    wire selected,committed,reload,op_written;
    wire [15:0] regs [0:7];
    wire [63:0] fg_words,bg_words;
    pc98_egc_registers dut(
        .clk(clk),.reset(reset),.egc_enable(egc_enable),
        .io_address(address),.io_select(bus_select),.io_writedata(bus_writedata),
        .io_strobe(bus_strobe),.io_write(bus_write),.port_selected(selected),
        .access_control(regs[0]),.color_select(regs[1]),.operation(regs[2]),
        .foreground(regs[3]),.pixel_mask(regs[4]),.background(regs[5]),
        .shift_control(regs[6]),.bit_length(regs[7]),
        .foreground_words(fg_words),.background_words(bg_words),
        .write_committed(committed),.shift_reload(reload),.operation_written(op_written));
    always @(posedge clk) begin
        if(reset || !bus_strobe) begin bus_ack<=0; waits<=0; end
        else if(waits<hold) waits<=waits+1;
        else bus_ack<=1;
    end

    reg [7:0] model [0:15];
    integer writes=0,reloads=0,operations=0;
    integer want_writes=0,want_reloads=0,want_operations=0,commands=0;
    integer n,trial;
    reg [31:0] random=32'h18a39c51;
    always @(posedge clk) if(!reset) begin
        if(committed) writes=writes+1;
        if(reload) reloads=reloads+1;
        if(op_written) operations=operations+1;
    end
    task check;
        integer i;
        begin
            for(i=0;i<8;i=i+1)
                if(regs[i] !== {model[2*i+1],model[2*i]})
                    $fatal(1,"EGC register mismatch reg=%0d actual=%h expected=%h%h",
                           i,regs[i],model[2*i+1],model[2*i]);
            for(i=0;i<4;i=i+1) begin
                if(fg_words[16*i +:16] !== (model[6][i] ? 16'hffff : 0))
                    $fatal(1,"EGC foreground expansion mismatch");
                if(bg_words[16*i +:16] !== (model[10][i] ? 16'hffff : 0))
                    $fatal(1,"EGC background expansion mismatch");
            end
            if(writes!=want_writes || reloads!=want_reloads || operations!=want_operations)
                $fatal(1,"EGC write pulse mismatch writes=%0d/%0d reload=%0d/%0d op=%0d/%0d",
                       writes,want_writes,reloads,want_reloads,operations,want_operations);
        end
    endtask
    task restart;
        integer i;
        begin
            @(negedge clk); reset=1; io_read_do=0; io_write_do=0;
            repeat(3) @(negedge clk);
            for(i=0;i<16;i=i+1) model[i]=0;
            model[0]=8'hf0; model[1]=8'hff; model[2]=8'hff;
            model[8]=8'hff; model[9]=8'hff; model[14]=8'h0f;
            writes=0; reloads=0; operations=0;
            want_writes=0; want_reloads=0; want_operations=0;
            reset=0; repeat(2) @(negedge clk); check;
        end
    endtask
    task reference_write(input integer addr, input integer length, input reg [31:0] data);
        integer pos,take,i,at;
        reg blocked;
        begin
            pos=0;
            while(pos<length) begin
                take=((addr+pos)%2==0 && length-pos>=2) ? 2 : 1;
                at=addr+pos-16'h04a0;
                if(egc_enable && at>=0 && at<16) begin
                    blocked=(at==8 || at==9) && (model[3]&8'h60)!=0;
                    if(!blocked) begin
                        for(i=0;i<take;i=i+1) model[at+i]=(data>>(8*(pos+i))) & 255;
                        want_writes=want_writes+1;
                        if(at>=12) want_reloads=want_reloads+1;
                        if(at==4 || at==5) want_operations=want_operations+1;
                    end
                end
                pos=pos+take;
            end
        end
    endtask
    task write_io(input reg [15:0] addr,input reg [2:0] length,input reg [31:0] data);
        integer watchdog;
        begin
            reference_write(addr,length,data);
            @(negedge clk);
            io_write_address=addr; io_write_length=length; io_write_data=data; io_write_do=1;
            watchdog=0;
            while(!io_write_done && watchdog<100) begin @(negedge clk); watchdog=watchdog+1; end
            if(!io_write_done) $fatal(1,"EGC I/O timeout");
            io_write_do=0;
            while(busy || bus_ack) @(negedge clk);
            repeat(2) @(negedge clk);
            check; commands=commands+1;
        end
    endtask
    task read_io(input reg [15:0] addr,input reg [2:0] length);
        integer watchdog;
        reg [31:0] expected;
        begin
            @(negedge clk);
            io_read_address=addr; io_read_length=length; io_read_do=1;
            watchdog=0;
            while(!io_read_done && watchdog<100) begin @(negedge clk); watchdog=watchdog+1; end
            if(!io_read_done) $fatal(1,"EGC read timeout");
            case(length)
                1: expected=32'h000000ff;
                2: expected=32'h0000ffff;
                default: expected=32'hffffffff;
            endcase
            if(io_read_data!==expected) $fatal(1,"EGC write-only port changed open-bus data");
            io_read_do=0;
            while(busy || bus_ack) @(negedge clk);
            repeat(2) @(negedge clk);
            check; commands=commands+1;
        end
    endtask
    initial begin
        restart;
        decode_sweep=1;
        for(n=0;n<32768;n=n+1) begin
            sweep_address=n; #1;
            if(selected !== (n>=16'h0250 && n<=16'h0257))
                $fatal(1,"EGC port decode aliases address %h",n*2);
        end
        decode_sweep=0;
        // Disabled writes must neither change registers nor issue reloads.
        for(n=0;n<16;n=n+1) write_io(16'h04a0+n,1,32'hbadc1234);
        egc_enable=1;
        for(trial=0;trial<2;trial=trial+1) begin
            hold=trial==0 ? 0 : 7;
            for(n=0;n<16;n=n+1) begin
                write_io(16'h04a0+n,1,32'hc192e53a ^ (n*32'h5193));
                write_io(16'h04a0+n,2,32'h38da91e7 ^ (n*32'h8435));
                write_io(16'h04a0+n,4,32'h6579c23a ^ (n*32'h95a7419));
            end
        end
        // All four pattern selections: only 00 allows pixel-mask writes.
        for(n=0;n<4;n=n+1) begin
            write_io(16'h04a2,2,n<<13);
            write_io(16'h04a8,2,16'h1357+n);
            write_io(16'h04a9,1,8'hac+n);
        end
        for(n=0;n<16;n=n+1) begin
            write_io(16'h04a6,2,16'hb1f0+n);
            write_io(16'h04aa,2,16'h5ae0+15-n);
            read_io(16'h04a0+n,1<<(n%3));
        end
        for(trial=0;trial<2000;trial=trial+1) begin
            random={random[30:0],random[31]^random[21]^random[1]^random[0]};
            egc_enable=random[7:6]!=0; hold=random[4:2];
            // Span both boundaries, and cycle byte/word/DWORD sizes.
            write_io(16'h049e+(random[17:8]%20),1<<(trial%3),random);
        end
        egc_enable=0;
        restart;
        egc_enable=1;
        write_io(16'h04ac,4,32'h0f31105a);
        if(commands!=2173) $fatal(1,"Incomplete EGC I/O coverage: %0d requests",commands);
        $display("PASS EGC registers: 32768 port addresses, %0d CPU I/O requests, odd words/DWORDs, held strobes, mask protection, colors, reset",commands);
        $finish;
    end
    initial begin #10000000; $fatal(1,"EGC register test watchdog"); end
endmodule
