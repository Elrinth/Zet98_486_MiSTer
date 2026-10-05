// SPDX-License-Identifier: GPL-3.0-or-later
`timescale 1ns/1ps
module ao486_memory_bridge_tb #(
    parameter NARROW_READS = 1'b1,
    parameter SKIP_EMPTY_HALVES = 1'b1,
    parameter RAM_DWORD_READ = 1'b0
);
    reg clk = 0;
    always #5 clk = !clk;
    reg reset = 1;
    reg [29:0] avm_address = 0;
    reg [31:0] avm_writedata = 0;
    reg [3:0] avm_byteenable = 0, avm_burstcount = 1;
    reg avm_write = 0, avm_read = 0;
    wire avm_waitrequest, avm_readdatavalid, avm_write_done, busy;
    wire [31:0] avm_readdata;
    wire [31:1] bus_address;
    wire [1:0] bus_select;
    wire [15:0] bus_writedata;
    wire bus_write, bus_strobe;
    reg [15:0] bus_readdata = 0;
    reg bus_ack = 0;
    wire bus_dword_valid = bus_ack && !bus_write && !bus_address[1] && in_ram({bus_address,1'b0});
    reg [31:0] bus_dword_data = 0;
    ao486_memory_bridge #(.NARROW_READS(NARROW_READS),.SKIP_EMPTY_HALVES(SKIP_EMPTY_HALVES),.RAM_DWORD_READ(RAM_DWORD_READ)) dut (
        .wide_linear_enable(1'b0),.wide_waitrequest(1'b1),
        .wide_readdatavalid(1'b0),.wide_readdata(32'b0),
        .wide_address(),.wide_writedata(),.wide_byteenable(),.wide_burstcount(),
        .wide_read(),.wide_write(),.*);
    integer clock_cycles = 0;
    always @(posedge clk) clock_cycles <= clock_cycles+1;

    reg [7:0] memory [0:8191];
    reg [7:0] expected_memory [0:8191];
    reg [31:0] expected_address [0:8191];
    reg [1:0] expected_select [0:8191];
    reg expected_write [0:8191];
    reg [15:0] expected_data [0:8191];
    reg [31:0] expected_read [0:4095];
    integer bus_head = 0, bus_tail = 0, read_head = 0, read_tail = 0;
    integer model_state = 0, delay_left = 0, hold_left = 0;
    integer stall_cycles = 0, ack_hold_cycles = 0, requests = 0;
    reg [31:0] held_address;
    reg [1:0] held_select;
    reg [15:0] held_data;
    reg held_write;
    reg [31:0] completed_address[0:1023], completed_data[0:1023];
    reg [3:0] completed_mask[0:1023];
    integer write_head=0,write_tail=0;

    // The completion indication lets z486 execute its next instruction while
    // legacy ACK is still releasing. Every selected byte must already have
    // reached the independent memory model; first-half completion is unsafe.
    always @(negedge clk) if (!reset && avm_write_done) begin
        if (write_head == write_tail) $fatal(1,"duplicate/unowned write completion");
        for (integer lane=0;lane<4;lane++)
            if (completed_mask[write_head][lane] &&
                memory[index_of(completed_address[write_head]+lane)] !==
                    completed_data[write_head][lane*8+:8])
                $fatal(1,"write completed before all selected bytes reached memory");
        write_head++;
    end

    function automatic integer index_of(input reg [31:0] a);
        index_of = a[12:0] ^ a[25:13] ^ {7'b0, a[31:26]};
    endfunction

    // Independent byte-addressed model, with full physical address checking.
    // Acknowledgement can remain high AFTER strobe drops, as in legacy fabric.
    always @(negedge clk) begin
        if (reset) begin
            bus_ack = 0;
            model_state = 0;
        end else begin
            if (avm_readdatavalid) begin
                if (read_head == read_tail) $fatal(1, "unexpected read response");
                if (avm_readdata !== expected_read[read_head])
                    $fatal(1, "read response %0d: got %h expected %h", read_head,
                           avm_readdata, expected_read[read_head]);
                read_head = read_head + 1;
            end
            case (model_state)
                0: if (bus_strobe) begin
                    if (bus_head == bus_tail) $fatal(1, "unexpected memory transfer");
                    if ({bus_address, 1'b0} !== expected_address[bus_head] ||
                        bus_select !== expected_select[bus_head] ||
                        bus_write !== expected_write[bus_head])
                        $fatal(1, "memory transfer %0d mismatch: address %h expected %h, select %b expected %b",
                               bus_head, {bus_address, 1'b0}, expected_address[bus_head],
                               bus_select, expected_select[bus_head]);
                    if (bus_write &&
                        ((bus_select[0] && bus_writedata[7:0] !== expected_data[bus_head][7:0]) ||
                         (bus_select[1] && bus_writedata[15:8] !== expected_data[bus_head][15:8])))
                        $fatal(1, "write data mismatch");
                    held_address = {bus_address, 1'b0};
                    held_select = bus_select;
                    held_write = bus_write;
                    held_data = bus_writedata;
                    delay_left = stall_cycles;
                    model_state = 1;
                end
                1: begin
                    if (!bus_strobe || {bus_address, 1'b0} !== held_address ||
                        bus_select !== held_select || bus_write !== held_write ||
                        bus_writedata !== held_data)
                        $fatal(1, "legacy request changed while stalled");
                    if (delay_left != 0) delay_left = delay_left - 1;
                    else begin
                        if (held_write) begin
                            if (held_select[0]) memory[index_of(held_address)] = held_data[7:0];
                            if (held_select[1]) memory[index_of(held_address + 1)] = held_data[15:8];
                        end
                        bus_readdata = {memory[index_of(held_address + 1)], memory[index_of(held_address)]};
                        bus_dword_data = {memory[index_of(held_address + 3)], memory[index_of(held_address + 2)],
                                          memory[index_of(held_address + 1)], memory[index_of(held_address)]};
                        bus_ack = 1;
                        bus_head = bus_head + 1;
                        model_state = 2;
                    end
                end
                2: if (!bus_strobe) begin
                    hold_left = ack_hold_cycles;
                    model_state = 3;
                end
                3: begin
                    if (bus_strobe) $fatal(1, "new transfer before acknowledgement release");
                    if (hold_left != 0) hold_left = hold_left - 1;
                    else begin
                        bus_ack = 0;
                        model_state = 0;
                    end
                end
            endcase
        end
    end

    function automatic bit in_vram(input reg [31:0] addr);
        in_vram = (addr >= 32'ha8000 && addr <= 32'hbffff) ||
                  (addr >= 32'he0000 && addr <= 32'he7fff);
    endfunction
    function automatic bit in_ram(input reg [31:0] addr);
        in_ram = addr >= 32'h00100000 && addr < 32'h04000000 &&
                 !(addr >= 32'h00f00000 && addr < 32'h01000000);
    endfunction
    task automatic enqueue(input bit wr, input reg [31:0] addr,
                           input reg [3:0] be, input reg [31:0] data,
                           input integer beats);
        integer beat, lane, halfword;
        reg [31:0] a, rd;
        reg [1:0] sel;
        begin
            for (beat = 0; beat < beats; beat = beat + 1) begin
                a = addr + beat * 4;
                for (halfword = 0; halfword < 2; halfword = halfword + 1) begin
                    // Writes carry their byte lanes; reads do too inside the
                    // graphics VRAM windows (EGC byte shifting), where a
                    // single-beat narrow read skips its empty half. Other
                    // reads are full words.
                    sel = (NARROW_READS && !wr && beats == 1 && be != 0 &&
                           ((be >> (halfword * 2)) & 3) == 0) ? 0 :
                          (wr || (NARROW_READS && beats == 1 && be != 0 && in_vram(a))) ?
                              ((be >> (halfword * 2)) & 3) : 3;
                    if (sel != 0 && !(RAM_DWORD_READ && !wr && in_ram(a) && halfword==1 &&
                        (!NARROW_READS || beats!=1 || be==0 || (be[1:0]!=0 && be[3:2]!=0)))) begin
                        expected_address[bus_tail] = a + halfword * 2;
                        expected_select[bus_tail] = sel;
                        expected_write[bus_tail] = wr;
                        expected_data[bus_tail] = data >> (halfword * 16);
                        bus_tail = bus_tail + 1;
                    end
                end
                for (lane = 0; lane < 4; lane = lane + 1) begin
                    if (wr && be[lane]) expected_memory[index_of(a + lane)] = data >> (lane * 8);
                    rd[lane*8 +: 8] = expected_memory[index_of(a + lane)];
                end
                if (!wr) begin
                    // Only bytes requested by the single-beat master are
                    // meaningful; the bridge specifies FFFF for an omitted half.
                    if (NARROW_READS && beats == 1 && be != 0) begin
                        if (be[1:0] == 0) rd[15:0] = 16'hffff;
                        if (be[3:2] == 0) rd[31:16] = 16'hffff;
                    end
                    expected_read[read_tail] = rd;
                    read_tail = read_tail + 1;
                end
            end
        end
    endtask

    task automatic issue(input bit wr, input reg [31:0] addr,
                         input reg [3:0] be, input reg [31:0] data,
                         input integer beats);
        begin
            if (wr) begin
                completed_address[write_tail]=addr;
                completed_data[write_tail]=data;
                completed_mask[write_tail]=be;
                write_tail++;
            end
            enqueue(wr, addr, be, data, beats);
            @(negedge clk);
            avm_address = addr[31:2];
            avm_writedata = data;
            avm_byteenable = be;
            avm_burstcount = beats;
            avm_read = !wr;
            avm_write = wr;
            // Keep the next command asserted even while the previous one drains.
            // This exercises the master's waitrequest handshake and ordering.
            @(posedge clk);
            while (avm_waitrequest) @(posedge clk);
            #1;
            if (!busy) $fatal(1, "accepted command was not retained");
            @(negedge clk);
            avm_read = 0;
            avm_write = 0;
            avm_address = ~addr[31:2];
            avm_writedata = ~data;
            avm_byteenable = ~be;
            avm_burstcount = 0;
            requests = requests + 1;
        end
    endtask

    task automatic drain;
        begin
            @(posedge clk);
            while (avm_waitrequest) @(posedge clk);
            repeat (3) @(posedge clk);
            if (bus_head != bus_tail || read_head != read_tail)
                $fatal(1, "missing transfers/responses");
            if (write_head != write_tail) $fatal(1,"missing physical write completion");
        end
    endtask

    integer i, be, burst, delay_mode, address_case;
    reg [31:0] base;
    initial begin
        for (i = 0; i < 8192; i = i + 1) begin
            memory[i] = (i * 37) ^ (i >> 4) ^ 8'ha7;
            expected_memory[i] = memory[i];
        end
        repeat (3) @(posedge clk);
        @(negedge clk); reset = 0;
        for (delay_mode = 0; delay_mode < 3; delay_mode = delay_mode + 1) begin
            stall_cycles = delay_mode * 3;
            ack_hold_cycles = delay_mode * 2;
            for (address_case = 0; address_case < 11; address_case = address_case + 1) begin
                case (address_case)
                    0: base = 32'h0000_0000;
                    1: base = 32'h000f_fffc;
                    2: base = 32'h0010_0000;
                    3: base = 32'hfffe_0020;
                    4: base = 32'hffff_fff0;
                    5: base = 32'h000a_8000;      // graphics VRAM: byte-precise reads
                    6: base = 32'h000e_7ffc;
                    7: base = 32'h00ef_fffc;      // RAM -> graphics aperture
                    8: base = 32'h00ff_fffc;      // aperture -> high RAM
                    9: base = 32'h03ff_fffc;      // last RAM DWORD -> unmapped
                    10: base = 32'h0100_0004;     // high DWORD in DDR word
                endcase
                for (be = 0; be < 16; be = be + 1) begin
                    issue(1, base, be, 32'h3c96a55a ^ (be * 32'h07030109), 1);
                    issue(0, base, be, 0, 1);
                end
                for (burst = 1; burst <= 8; burst = burst + 1)
                    issue(0, base, burst & 15, 0, burst);
                drain();
            end
        end
        for (i = 0; i < 8192; i = i + 1)
            if (memory[i] !== expected_memory[i]) $fatal(1, "incorrect write side effect at %0d", i);

        // Reset during a stalled burst must cancel its pending response.
        stall_cycles = 100;
        issue(0, 32'h01000000, 15, 0, 8);
        repeat (5) @(posedge clk);
        @(negedge clk); reset = 1;
        #1;
        if (bus_strobe || !avm_waitrequest) $fatal(1, "reset did not inhibit the bus");
        repeat (3) @(posedge clk);
        @(negedge clk);
        bus_head = bus_tail;
        read_head = read_tail;
        reset = 0;
        stall_cycles = 0;
        issue(1, 32'h12345678, 15, 32'h90abcdef, 1);
        issue(0, 32'h12345678, 0, 0, 1);
        drain();
        $display("PASS: ao486 memory bridge: %0d commands, %0d transfers, narrow=%0d, byte masks, bursts, high addresses, stalls, reset",
                 requests, bus_tail, NARROW_READS);
        $display("memory_bridge_cycles=%0d",clock_cycles);
        $finish;
    end
    initial begin
        #2000000;
        $fatal(1, "memory bridge watchdog timeout");
    end
endmodule
