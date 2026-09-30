// SPDX-License-Identifier: GPL-3.0-or-later
// z486's unified ready/valid bus to the existing PC-98 memory and I/O bridges.
// Memory reads return individual DWORDs, including four-beat instruction lines.
// I/O is acknowledged only on completion, retaining byte-lane side effects.
module z486_pc98_adapter #(
    parameter EXT_RAM_MB = 0,
    parameter CLOCK_RATE_MHZ = 90
) (
    input wire clk, rst_n, a20_enable, cache_disable, cache_invalidate,
    input wire fabric_idle,
    input wire [1:0] cpu_speed_sel,
    output wire [35:0] debug_state,
    output wire crash_tx,               // debug builds: crash recorder UART
    input wire cache_upper_ram,
    input wire interrupt_do,
    input wire [7:0] interrupt_vector,
    output wire interrupt_done,
    output wire [29:0] avm_address,
    output wire [31:0] avm_writedata,
    output wire [3:0] avm_byteenable, avm_burstcount,
    output wire avm_write, avm_read,
    input wire avm_waitrequest, avm_readdatavalid,
    input wire [31:0] avm_readdata,
    input wire [23:0] dma_address,
    input wire dma_16bit, dma_write, dma_read,
    input wire [15:0] dma_writedata,
    output wire [15:0] dma_readdata,
    output wire dma_readdatavalid, dma_waitrequest,
    output wire io_read_do,
    output wire [15:0] io_read_address,
    output wire [2:0] io_read_length,
    input wire [31:0] io_read_data,
    input wire io_read_done,
    output wire io_write_do,
    output wire [15:0] io_write_address,
    output wire [2:0] io_write_length,
    output wire [31:0] io_write_data,
    input wire io_write_done
);
    wire [29:0] address;
    wire [3:0] byte_enable;
    wire [7:0] burst;
    wire [31:0] write_data, read_data;
    wire valid, write, io, inta, ready, response;
    wire triple_fault;
    wire [31:0] eip;
    wire protected_mode;
    wire [15:0] dbg_cs, dbg_sp;
    wire dbg_vm, dbg_gate_read;
    wire [31:0] dbg_gate_addr, dbg_pf_addr, dbg_eflags;
    wire [2:0] dbg_pf_code;
    wire dbg_page_fault;
    wire [31:0] dbg_walk_pde, dbg_walk_pte, dbg_cr3;
    wire real_mode = !protected_mode;
    reg second_inta;
    reg write_accepted;
    reg [3:0] triple_reset;
    wire reset_request_n = rst_n && triple_reset == 0;
    // Assert immediately, but release the core only on local clock edges.
    // Loader/control reset and triple-fault counter decode must not directly
    // drive recovery and combinational issue paths throughout the CPU.
    (* preserve, altera_attribute = "-name SYNCHRONIZER_IDENTIFICATION FORCED_IF_ASYNCHRONOUS" *)
    reg [1:0] reset_release = 2'b00;
    always @(posedge clk or negedge reset_request_n) begin
        if (!reset_request_n) reset_release <= 2'b00;
        else reset_release <= {reset_release[0], 1'b1};
    end
    wire cpu_reset_n = reset_release[1];
    // Trace/debug snapshot only: with a 16-bit EIP (real/V86 mode) the upper
    // half carries CS, so the trace's X lines read CS:IP.
    assign debug_state = {(eip[31:16] == 16'd0 ? {dbg_cs, eip[15:0]} : eip),
        triple_fault,write_accepted,valid,ready};
    wire [1:0] first_lane = byte_enable[0] ? 2'd0 : byte_enable[1] ? 2'd1 :
                                 byte_enable[2] ? 2'd2 : 2'd3;
    wire [2:0] byte_count = {2'b0,byte_enable[0]} + {2'b0,byte_enable[1]} +
                            {2'b0,byte_enable[2]} + {2'b0,byte_enable[3]};
    wire io_done = write ? io_write_done : io_read_done;
    assign avm_address = address;
    assign avm_writedata = write_data;
    assign avm_byteenable = byte_enable;
    assign avm_burstcount = burst[3:0];
    assign avm_read = cpu_reset_n && valid && !io && !inta && !write;
    assign avm_write = cpu_reset_n && valid && !io && !inta && write && !write_accepted;
    assign io_read_do = cpu_reset_n && valid && io && !inta && !write;
    assign io_write_do = cpu_reset_n && valid && io && !inta && write;
    assign io_read_address = {address[13:0], first_lane};
    assign io_write_address = io_read_address;
    assign io_read_length = byte_count;
    assign io_write_length = byte_count;
    assign io_write_data = write_data >> (first_lane * 8);
    // The PC-98 PIC presents its vector while interrupt_done is asserted.
    assign interrupt_done = cpu_reset_n && valid && inta && second_inta;
    // Complete stores at the physical fabric before releasing their owner.
    // This also orders bank-window aliases against internal RAM-cache hits.
    assign ready = cpu_reset_n && (inta ? 1'b1 : io ? io_done :
                                  write ? write_accepted && fabric_idle : !avm_waitrequest);
    assign response = cpu_reset_n && ((valid && inta) || io_read_done || avm_readdatavalid);
    assign read_data = inta ? (second_inta ? {24'b0,interrupt_vector} : 32'b0) :
                       io ? (io_read_data << (first_lane * 8)) : avm_readdata;
    assign dma_readdata = 16'hffff;
    assign dma_readdatavalid = 1'b0;
    assign dma_waitrequest = 1'b1;

    always @(posedge clk) begin
        if (!rst_n) triple_reset <= 0;
        else if (triple_fault) triple_reset <= 8;
        else if (triple_reset != 0) triple_reset <= triple_reset - 1'b1;
        if (!cpu_reset_n) second_inta <= 0;
        else if (valid && inta && ready) second_inta <= !second_inta;
        if (!cpu_reset_n) write_accepted <= 0;
        else if (avm_write && !avm_waitrequest) write_accepted <= 1;
        else if (valid && !io && !inta && write && ready) write_accepted <= 0;
    end

    z486 #(.PROTECT_UMA_ROM(0), .DCACHE_SET_BITS(7), .ICACHE_SET_BITS(7),
           .ENABLE_X87(0), .PC98_MODE(1), .PC98_EXT_RAM_MB(EXT_RAM_MB),
           .CLOCK_RATE_MHZ(CLOCK_RATE_MHZ)) core (
        .clk(clk), .reset_n(cpu_reset_n), .cache_invalidate(cache_invalidate),
        .cache_upper_ram(cache_upper_ram),
        .device_mmio_enable(1'b0), .device_mmio_base(32'b0),
        .addr(address), .be(byte_enable), .burstcount(burst), .line_read(),
        .din(read_data), .line_din(128'b0), .dout(write_data), .valid(valid),
        .ready(ready), .write(write), .io(io), .resp_valid(response), .line_resp_valid(1'b0),
        .intr(interrupt_do), .nmi(1'b0), .inta(inta), .snoop_addr(32'b0), .snoop_valid(1'b0),
        .win0_unmapped(1'b0), .a20_enable(a20_enable), .cpu_speed_sel(cpu_speed_sel), .single_step(1'b0),
        .dbg_CS(dbg_cs), .dbg_EIP(eip), .dbg_CS_base(), .dbg_pe(protected_mode), .dbg_vm(dbg_vm), .dbg_x87_state(),
        .dbg_gate_read(dbg_gate_read), .dbg_gate_addr(dbg_gate_addr), .dbg_pf_code(dbg_pf_code),
        .dbg_pf_addr(dbg_pf_addr), .dbg_eflags(dbg_eflags), .dbg_page_fault(dbg_page_fault),
        .dbg_walk_pde(dbg_walk_pde), .dbg_walk_pte(dbg_walk_pte), .dbg_cr3(dbg_cr3), .dbg_SP(dbg_sp),
        .triple_fault_reset(triple_fault)
    );
`ifdef ZET98_Z486_DEBUG
`ifndef VERILATOR   // hardware debug builds only (tests/crash_recorder_tb.sv covers it)
`ifdef ZET98_RECORDER_IO
    localparam RECORDER_IO = 1;   // CD/IDE task-file trace instead of crash events
`else
    localparam RECORDER_IO = 0;
`endif
`ifdef ZET98_RECORDER_FREEZE_CS
    localparam [15:0] RECORDER_FREEZE_CS = `ZET98_RECORDER_FREEZE_CS;
`else
    localparam [15:0] RECORDER_FREEZE_CS = 16'h0000;
`endif
`ifdef ZET98_RECORDER_FREEZE_IP
    localparam [16:0] RECORDER_FREEZE_IP = {1'b1, 16'(`ZET98_RECORDER_FREEZE_IP)};
`else
    localparam [16:0] RECORDER_FREEZE_IP = 17'h00000;
`endif
`ifdef ZET98_RECORDER_FREEZE_VECTOR
    localparam [8:0] RECORDER_FREEZE_VECTOR = {1'b1, 8'(`ZET98_RECORDER_FREEZE_VECTOR)};
`else
    localparam [8:0] RECORDER_FREEZE_VECTOR = 9'h000;
`endif
`ifdef ZET98_RECORDER_FREEZE_SECONDS
    localparam integer RECORDER_FREEZE_SECONDS = `ZET98_RECORDER_FREEZE_SECONDS;
`else
    localparam integer RECORDER_FREEZE_SECONDS = 0;
`endif
`ifdef ZET98_RECORDER_DE
    localparam RECORDER_DE = 1;   // freeze on the first real-mode divide error
`else
    localparam RECORDER_DE = 0;
`endif
    z486_crash_recorder #(.CLOCK_HZ(CLOCK_RATE_MHZ * 1000000), .IO_MODE(RECORDER_IO),
                          .DE_TRIGGER(RECORDER_DE), .DE_FREEZE_CS(RECORDER_FREEZE_CS),
                          .DE_FREEZE_IP(RECORDER_FREEZE_IP),
                          .DE_FREEZE_VECTOR(RECORDER_FREEZE_VECTOR),
                          .DE_FREEZE_SECONDS(RECORDER_FREEZE_SECONDS)) crash_recorder (
        .clk(clk), .gate_read(dbg_gate_read), .gate_addr(dbg_gate_addr), .cs(dbg_cs), .eip(eip),
        .eflags(dbg_eflags), .pe(protected_mode), .vm(dbg_vm), .pf_code(dbg_pf_code), .pf_addr(dbg_pf_addr),
        .triple_fault(triple_fault), .port_f0_write(io_write_do && io_write_address == 16'h00f0),
        .port_f0_data(io_write_data[7:0]), .page_fault(dbg_page_fault), .walk_pde(dbg_walk_pde),
        .walk_pte(dbg_walk_pte), .cr3(dbg_cr3), .a20(a20_enable), .sp(dbg_sp),
        .mem_write(avm_write && !avm_waitrequest), .mem_addr({address, 2'b00}), .mem_data(write_data),
        .mem_be(byte_enable), .io_wr(io_write_do && io_write_done), .io_rd(io_read_do && io_read_done),
        .io_addr(io_write_do ? io_write_address : io_read_address), .io_wdata(io_write_data),
        .io_rdata(io_read_data), .tx(crash_tx));
`else
    assign crash_tx = 1'b1;
`endif
`else
    assign crash_tx = 1'b1;
`endif
    // synthesis translate_off
    always @(posedge clk) if (cpu_reset_n && valid) begin
        if (burst != 1 && burst != 4) $fatal(1,"unsupported z486 bus burst");
        if ((dma_read || dma_write)) $fatal(1,"PC-98 DMA must use the external fabric");
    end
    // synthesis translate_on
endmodule
