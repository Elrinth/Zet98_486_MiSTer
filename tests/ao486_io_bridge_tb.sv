`timescale 1ns/1ps
module ao486_io_bridge_tb;
    reg clk = 0;
    always #5 clk = ~clk;
    reg reset = 1;
    reg io_read_do = 0, io_write_do = 0;
    reg [15:0] io_read_address = 0, io_write_address = 0;
    reg [2:0] io_read_length = 1, io_write_length = 1;
    reg [31:0] io_write_data = 0;
    wire [31:0] io_read_data;
    wire io_read_done, io_write_done, busy;
    wire [15:1] bus_address;
    wire [1:0] bus_select;
    wire [15:0] bus_writedata;
    wire bus_write, bus_strobe;
    reg [15:0] bus_readdata = 0;
    reg bus_ack = 0;
    ao486_io_bridge dut (.*);

    reg [7:0] ports [0:65535];
    reg [7:0] expected_ports [0:65535];
    integer peripheral_state = 0, wait_left = 0, ack_left = 0;
    integer transfers = 0, cases = 0, wait_setting = 0;
    reg [15:1] saved_address;
    reg [1:0] saved_select;
    reg [15:0] saved_data;
    reg saved_write;
    wire [15:0] even_port = {saved_address, 1'b0};
    wire [15:0] odd_port = {saved_address, 1'b1};

    // An independent byte-addressed peripheral model. Odd and even ports
    // hold different values and have independent side effects.
    always @(posedge clk) begin
        if (reset) begin
            peripheral_state <= 0;
            bus_ack <= 0;
        end else case (peripheral_state)
            0: if (bus_strobe) begin
                if (bus_select == 0) $fatal(1, "Empty peripheral transfer");
                saved_address <= bus_address;
                saved_select <= bus_select;
                saved_data <= bus_writedata;
                saved_write <= bus_write;
                wait_left <= wait_setting;
                peripheral_state <= 1;
            end
            1: begin
                if (!bus_strobe || bus_address !== saved_address ||
                    bus_select !== saved_select || bus_writedata !== saved_data ||
                    bus_write !== saved_write)
                    $fatal(1, "Request changed while peripheral was waiting");
                if (wait_left != 0) wait_left <= wait_left - 1;
                else begin
                    if (saved_write) begin
                        if (saved_select[0]) ports[even_port] <= saved_data[7:0];
                        if (saved_select[1]) ports[odd_port] <= saved_data[15:8];
                    end
                    bus_readdata <= {ports[odd_port], ports[even_port]};
                    bus_ack <= 1;
                    transfers <= transfers + 1;
                    peripheral_state <= 2;
                end
            end
            2: if (!bus_strobe) begin
                // Deliberately retain ACK after release, as a registered
                // target may do. It must never complete the next transfer.
                ack_left <= 2;
                peripheral_state <= 3;
            end
            3: begin
                if (bus_strobe) $fatal(1, "New transfer consumed a stale ACK");
                if (ack_left != 0) ack_left <= ack_left - 1;
                else begin
                    bus_ack <= 0;
                    peripheral_state <= 0;
                end
            end
        endcase
    end

    task automatic transaction(input bit wr, input [15:0] addr,
                               input integer size, input [31:0] data);
        integer before_count, expected_count, n, ticks;
        reg [31:0] expected_read;
        reg [15:0] port_index;
        begin
            before_count = transfers;
            expected_count = (size + int'(addr[0]) + 1) / 2;
            expected_read = 0;
            for (n = 0; n < size; n = n + 1) begin
                port_index = addr + n;
                expected_read[n*8 +: 8] = expected_ports[port_index];
            end
            @(negedge clk);
            io_write_do = wr;
            io_read_do = !wr;
            io_read_address = addr;
            io_write_address = addr;
            io_read_length = size;
            io_write_length = size;
            io_write_data = data;
            ticks = 0;
            while (!(io_read_done || io_write_done)) begin
                @(negedge clk);
                ticks = ticks + 1;
                if (ticks == 2) begin
                    // Only *_do is held now: the bridge must use its captured
                    // request, not resample payload during peripheral stalls.
                    io_write_address = ~addr;
                    io_read_address = ~addr;
                    io_write_data = ~data;
                    io_read_length = 1;
                    io_write_length = 1;
                end
                if (ticks > 250) $fatal(1, "Transaction timeout");
            end
            if (io_write_done !== wr || io_read_done !== !wr)
                $fatal(1, "Wrong completion signal");
            if (!wr && io_read_data !== expected_read)
                $fatal(1, "Read addr=%h size=%0d got=%h expected=%h",
                       addr, size, io_read_data, expected_read);
            io_write_do = 0;
            io_read_do = 0;
            if (wr) for (n = 0; n < size; n = n + 1) begin
                port_index = addr + n;
                expected_ports[port_index] = data[n*8 +: 8];
            end
            repeat (10) @(negedge clk);
            if (io_read_done || io_write_done || bus_strobe)
                $fatal(1, "Duplicate completion/request");
            if (transfers - before_count != expected_count)
                $fatal(1, "Wrong transfer count at addr=%h size=%0d", addr, size);
            for (n = 0; n < 65536; n = n + 1)
                if (ports[n] !== expected_ports[n])
                    $fatal(1, "Unexpected side effect at port %h", n);
            cases = cases + 1;
        end
    endtask

    integer i, size, wait_test;
    reg [15:0] test_addresses [0:9];
    initial begin
        test_addresses[0] = 16'h0000; test_addresses[1] = 16'h0001;
        test_addresses[2] = 16'h0002; test_addresses[3] = 16'h0003;
        test_addresses[4] = 16'h0188; test_addresses[5] = 16'h0189;
        test_addresses[6] = 16'h0640; test_addresses[7] = 16'h0641;
        test_addresses[8] = 16'hfffe; test_addresses[9] = 16'hffff;
        for (i = 0; i < 65536; i = i + 1) begin
            ports[i] = 8'h5a ^ i[7:0] ^ i[15:8];
            expected_ports[i] = ports[i];
        end
        repeat (3) @(negedge clk);
        reset = 0;
        for (wait_test = 0; wait_test < 3; wait_test = wait_test + 1) begin
            wait_setting = wait_test * 3;
            for (i = 0; i < 10; i = i + 1)
                for (size = 1; size <= 4; size = size * 2) begin
                    transaction(0, test_addresses[i], size, 0);
                    transaction(1, test_addresses[i], size, 32'hd4c3b2a1 ^ i);
                    transaction(0, test_addresses[i], size, 0);
                end
        end

        // Abort a request while the target is still waiting, then prove the
        // adapter can make a fresh request without stale completion/data.
        wait_setting = 30;
        @(negedge clk);
        io_write_address = 16'h0101;
        io_write_data = 32'hdeadbeef;
        io_write_length = 4;
        io_write_do = 1;
        repeat (4) @(negedge clk);
        reset = 1;
        io_write_do = 0;
        repeat (2) @(negedge clk);
        if (bus_strobe || io_write_done || io_read_done) $fatal(1, "Reset failed");
        reset = 0;
        wait_setting = 0;
        transaction(0, 16'h0100, 4, 0);
        transaction(1, 16'h0101, 4, 32'h11223344);
        transaction(0, 16'h0101, 4, 0);
        $display("PASS: %0d I/O requests; byte lanes, alignment, wrap, waits, ACK release and reset", cases);
        $finish;
    end
    initial begin
        #1000000;
        $fatal(1, "Global watchdog");
    end
endmodule
