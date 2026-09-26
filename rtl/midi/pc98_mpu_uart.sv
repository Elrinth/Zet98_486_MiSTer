// SPDX-License-Identifier: GPL-3.0-or-later
`timescale 1ns/1ps
// Original implementation of the MPU-PC98II UART subset, E0D0/E0D2, IRQ6.
// FF resets; FE is returned only outside UART mode. 3F enters UART mode and
// returns FE. Intelligent sequencing/clock-to-host commands are NOT emulated.
// All state is on clk; serial input alone crosses through a two-flop synchronizer.
module pc98_mpu_uart #(
    parameter integer CLOCK_HZ = 50000000,
    parameter integer BAUD = 31250,
    parameter integer FIFO_BITS = 4,
    parameter integer RESET_PANIC = 0
) (
    input wire clk, reset, enable,
    input wire [15:0] io_address, io_writedata,
    input wire [1:0] io_select,
    input wire io_read, io_write,
    output reg [7:0] io_readdata,
    output wire io_oe, irq,
    input wire midi_rx,
    output wire midi_tx,
    output reg rx_overrun, rx_framing_error, tx_overrun
);
    localparam integer BIT_TICKS = (CLOCK_HZ + BAUD/2) / BAUD;
    localparam integer TIMER_BITS = $clog2(BIT_TICKS);
    localparam integer FIFO_DEPTH = 1 << FIFO_BITS;
    reg previous_read, previous_write;
    wire decoded = enable && io_select[0] &&
                   (io_address == 16'he0d0 || io_address == 16'he0d2);
    wire read_start = decoded && io_read && !previous_read;
    wire write_start = decoded && io_write && !previous_write;
    wire command_write = write_start && io_address[1];
    wire data_read = read_start && !io_address[1];
    wire reset_command = command_write && io_writedata[7:0] == 8'hff;
    wire clear = reset || !enable || reset_command;
    reg uart_mode, ack_pending;

    reg [7:0] tx_fifo[0:FIFO_DEPTH-1], rx_fifo[0:FIFO_DEPTH-1];
    reg [FIFO_BITS-1:0] tx_head, tx_tail, rx_head, rx_tail;
    reg [FIFO_BITS:0] tx_count, rx_count;
    wire tx_full = tx_count == FIFO_DEPTH;
    wire rx_full = rx_count == FIFO_DEPTH;
    wire tx_push = write_start && !io_address[1] && uart_mode && !tx_full;
    reg [9:0] tx_shift = 10'h3ff;
    reg [3:0] tx_bits = 0;
    reg [TIMER_BITS-1:0] tx_timer = 0;
    reg reset_seen = 0, enable_seen = 0;
    reg panic_pending = 0, panic_lead = 1;
    reg [3:0] panic_channel = 0, panic_phase = 0;
    wire panic_event = RESET_PANIC && (reset_command ||
        (reset && !reset_seen && enable) || (enable != enable_seen));
    wire tx_pop = !clear && !tx_bits && tx_count != 0 && !panic_pending && !panic_event;
    wire [7:0] panic_byte = panic_lead ? 8'hf7 : // End interrupted SysEx.
        (panic_phase == 0 || panic_phase == 3 || panic_phase == 6 || panic_phase == 9) ? {4'hb,panic_channel} :
        panic_phase == 1 ? 8'd64 :  // Sustain off.
        panic_phase == 4 ? 8'd120 : // All Sound Off, including sustained voices.
        panic_phase == 7 ? 8'd123 : // All Notes Off.
        panic_phase == 10 ? 8'd121 : 8'd0; // Reset All Controllers.
    assign midi_tx = (!RESET_PANIC && (!enable || reset)) || !tx_bits ? 1'b1 : tx_shift[0];
    assign io_oe = decoded && io_read;
    assign irq = enable && !reset && (ack_pending || rx_count != 0);

    // Register a read result once, before its destructive FIFO/ACK side effect.
    // The legacy bus keeps RD asserted for multiple clocks while the CPU waits.
    always @(posedge clk) begin
        if (reset || !enable) begin
            previous_read <= 0;
            previous_write <= 0;
            io_readdata <= 8'hff;
        end else begin
            previous_read <= io_read;
            previous_write <= io_write;
            if (read_start) begin
                if (io_address[1])
                    io_readdata <= {!(ack_pending || rx_count != 0), tx_full, 6'b0};
                else io_readdata <= ack_pending ? 8'hfe :
                                    rx_count != 0 ? rx_fifo[rx_head] : 8'hff;
            end
        end
    end

    always @(posedge clk) begin
        if (clear) begin
            uart_mode <= 0;
            // Roland technical reference p22: leaving UART mode via FF
            // does not return FE. A later reset outside UART mode does.
            ack_pending <= reset_command && enable && !reset && !uart_mode;
        end else begin
            if (data_read && ack_pending) ack_pending <= 0;
            if (command_write && !uart_mode && io_writedata[7:0] == 8'h3f) begin
                uart_mode <= 1;
                ack_pending <= 1;
            end
        end
    end

    // Full queues apply normal MPU busy backpressure; a software violation is
    // dropped and latched in tx_overrun, never allowed to overwrite queued data.
    always @(posedge clk) begin
        if (clear) begin
            tx_head <= 0; tx_tail <= 0; tx_count <= 0;
            tx_overrun <= 0;
        end else begin
            if (write_start && !io_address[1] && uart_mode && tx_full)
                tx_overrun <= 1;
            if (tx_push) begin
                tx_fifo[tx_tail] <= io_writedata[7:0];
                tx_tail <= tx_tail + 1'b1;
            end
            if (tx_pop) tx_head <= tx_head + 1'b1;
            case ({tx_push, tx_pop})
                2'b10: tx_count <= tx_count + 1'b1;
                2'b01: tx_count <= tx_count - 1'b1;
                default: ;
            endcase
        end
    end

    // The serializer survives guest reset long enough to finish its current
    // byte and send panic. Queued game bytes are discarded by clear above.
    // New game traffic queues behind panic with ordinary FIFO backpressure.
    always @(posedge clk) begin
        reset_seen <= reset;
        enable_seen <= enable;
        if (!RESET_PANIC && clear) begin
            tx_shift <= 10'h3ff; tx_bits <= 0; tx_timer <= 0;
        end else begin
            if (!tx_bits) begin
                if (panic_pending && !panic_event) begin
                    tx_shift <= {1'b1,panic_byte,1'b0};
                    tx_bits <= 10; tx_timer <= BIT_TICKS-1;
                    if (panic_lead) panic_lead <= 0;
                    else if (panic_phase == 11) begin
                        panic_phase <= 0;
                        panic_channel <= panic_channel + 1'b1;
                        if (panic_channel == 15) panic_pending <= 0;
                    end else panic_phase <= panic_phase + 1'b1;
                end else if (tx_pop) begin
                    tx_shift <= {1'b1,tx_fifo[tx_head],1'b0};
                    tx_bits <= 10; tx_timer <= BIT_TICKS-1;
                end
            end else if (tx_timer != 0) tx_timer <= tx_timer - 1'b1;
            else begin
                tx_shift <= {1'b1,tx_shift[9:1]};
                tx_bits <= tx_bits - 1'b1;
                tx_timer <= BIT_TICKS-1;
            end
            if (panic_event) begin
                panic_pending <= 1; panic_lead <= 1;
                panic_channel <= 0; panic_phase <= 0;
            end
        end
    end

    (* async_reg = "true" *) reg rx_meta = 1, rx_sync = 1;
    always @(posedge clk) begin
        rx_meta <= midi_rx;
        rx_sync <= rx_meta;
    end
    localparam RX_IDLE=0, RX_START=1, RX_DATA=2, RX_STOP=3, RX_BREAK=4;
    reg [2:0] rx_state;
    reg [2:0] rx_bit;
    reg [7:0] rx_shift;
    reg [TIMER_BITS-1:0] rx_timer;
    wire rx_finish = rx_state == RX_STOP && rx_timer == 0;
    wire rx_pop = data_read && !ack_pending && rx_count != 0;
    wire rx_push = rx_finish && rx_sync && uart_mode && (!rx_full || rx_pop);
    always @(posedge clk) begin
        if (clear) begin
            rx_state <= RX_IDLE; rx_bit <= 0; rx_timer <= 0; rx_shift <= 0;
            rx_head <= 0; rx_tail <= 0; rx_count <= 0;
            rx_overrun <= 0; rx_framing_error <= 0;
        end else begin
            if (rx_push) begin
                rx_fifo[rx_tail] <= rx_shift;
                rx_tail <= rx_tail + 1'b1;
            end
            if (rx_pop) rx_head <= rx_head + 1'b1;
            case ({rx_push, rx_pop})
                2'b10: rx_count <= rx_count + 1'b1;
                2'b01: rx_count <= rx_count - 1'b1;
                default: ;
            endcase
            if (rx_finish && !rx_sync) rx_framing_error <= 1;
            if (rx_finish && rx_sync && uart_mode && rx_full && !rx_pop)
                rx_overrun <= 1;
            case (rx_state)
                RX_IDLE: if (!rx_sync) begin
                    rx_state <= RX_START;
                    rx_timer <= BIT_TICKS/2-1;
                end
                RX_START: if (rx_timer != 0) rx_timer <= rx_timer - 1'b1;
                    else if (rx_sync) rx_state <= RX_IDLE;
                    else begin
                        rx_state <= RX_DATA;
                        rx_bit <= 0;
                        rx_timer <= BIT_TICKS-1;
                    end
                RX_DATA: if (rx_timer != 0) rx_timer <= rx_timer - 1'b1;
                    else begin
                        rx_shift[rx_bit] <= rx_sync;
                        rx_bit <= rx_bit + 1'b1;
                        rx_timer <= BIT_TICKS-1;
                        if (rx_bit == 7) rx_state <= RX_STOP;
                    end
                RX_STOP: if (rx_timer != 0) rx_timer <= rx_timer - 1'b1;
                    else rx_state <= rx_sync ? RX_IDLE : RX_BREAK;
                RX_BREAK: if (rx_sync) rx_state <= RX_IDLE;
                default: rx_state <= RX_IDLE;
            endcase
        end
    end
endmodule
