// SPDX-License-Identifier: GPL-3.0-or-later
// Debug-build crash recorder for the z486 (ZET98_Z486_DEBUG, UART instead of
// MIDI). Once protected mode has been entered it keeps the last 256 CPU
// events: IDT gate reads (exception/interrupt entry), PE/VM changes, triple
// faults, port F0h (CPU reset) writes and arrival at the reset vector. The
// first reset-type event freezes the ring; the ring is then dumped once a
// second, oldest first, as "E" + 32 hex digits + LF at 115200 8N1, framed by
// "B" and "Z" lines. Before that a heartbeat "H" + the newest entry is sent
// once a second. Entry layout (tools: tests/hardware/decode_crash.py):
//   [127:124] type 1 gate, 2 mode, 3 triple, 4 port F0, 5 reset vector,
//             6 page fault (payload PTE), 7 walk context: EIP field = PDE,
//             payload = CR3, CS field = A20 (logged right after type 6)
//             8 nonzero memory write in WATCH page: EIP field = address,
//               payload = data, CS field = byte enables
//             9 every 1024th memory write above 1 MB (same layout)
//            10 I/O write, 11 I/O read (IO_MODE): CS field = port, EIP field = data,
//               payload = {CS, IP[15:0]} of the instruction
// IO_MODE=1 logs only CD/IDE task-file I/O (640h-64Fh, 74Ch, 432h writes;
// 642h/644h reads) and dumps every 10 s without freezing for good.
//   [123:108] CS  [107:76] EIP  [75:44] payload (gate address, EFLAGS, data)
//   [43:41] #PF code  [40:9] CR2  [8] VM  [7] PE  [6:0] sequence
// It is never reset (only by loading the core) so it survives CPU resets.
module z486_crash_recorder #(parameter integer CLOCK_HZ = 90000000,
                             parameter [19:0] WATCH_PAGE = 20'h00120,
                             parameter IO_MODE = 0) (
    input wire clk,
    input wire gate_read,
    input wire [31:0] gate_addr,
    input wire [15:0] cs,
    input wire [31:0] eip,
    input wire [31:0] eflags,
    input wire pe, vm,
    input wire [2:0] pf_code,
    input wire [31:0] pf_addr,
    input wire triple_fault,
    input wire port_f0_write,
    input wire [7:0] port_f0_data,
    input wire page_fault,
    input wire [31:0] walk_pde, walk_pte, cr3,
    input wire a20,
    input wire mem_write,            // one pulse per accepted memory write
    input wire [31:0] mem_addr, mem_data,
    input wire [3:0] mem_be,
    input wire io_wr, io_rd,         // one pulse per completed I/O access
    input wire [15:0] io_addr,
    input wire [31:0] io_wdata, io_rdata,
    output wire tx
);
    // ---- capture -----------------------------------------------------------
    reg armed = 0, frozen = 0, prev_pe = 0, prev_vm = 0;
    reg pf_d1 = 0, pf_d2 = 0;          // log after the latched CR2/code update
    reg [9:0] ext_writes = 0;
    wire watch_write = mem_write && mem_addr[31:12] == WATCH_PAGE && mem_data != 0;
    wire ext_sample = mem_write && mem_addr[31:20] != 0 && ext_writes == 0;
    reg [7:0] wp = 0;
    reg [6:0] seq = 0;
    reg [3:0] ev_type;
    reg [31:0] ev_payload;
    reg ev_valid;
    reg pause = 0;                   // IO_MODE: recording paused while dumping
    wire ide_port = io_addr[15:4] == 12'h064 || io_addr == 16'h074c || io_addr == 16'h0432;
    wire io_wr_ev = IO_MODE && io_wr && ide_port;
    wire io_rd_ev = IO_MODE && io_rd && (io_addr == 16'h0642 || io_addr == 16'h0644);
    always @* begin
        ev_valid = 1'b1; ev_type = 4'd0; ev_payload = 32'd0;
        if (IO_MODE) begin
            if (io_wr_ev) begin ev_type = 4'd10; ev_payload = {cs, eip[15:0]}; end
            else if (io_rd_ev) begin ev_type = 4'd11; ev_payload = {cs, eip[15:0]}; end
            else ev_valid = 1'b0;
        end else if (pf_d2) begin ev_type = 4'd7; ev_payload = cr3; end
        else if (pf_d1 && pe) begin ev_type = 4'd6; ev_payload = walk_pte; end
        else if (triple_fault) begin ev_type = 4'd3; end
        else if (port_f0_write) begin ev_type = 4'd4; ev_payload = {24'd0, port_f0_data}; end
        else if (cs == 16'hF000 && eip == 32'h0000FFF0) begin ev_type = 4'd5; end
        else if (gate_read && pe && !gate_addr[2]) begin ev_type = 4'd1; ev_payload = gate_addr; end
        else if (pe != prev_pe || vm != prev_vm) begin ev_type = 4'd2; ev_payload = eflags; end
        else if (watch_write) begin ev_type = 4'd8; ev_payload = mem_data; end
        else if (ext_sample) begin ev_type = 4'd9; ev_payload = mem_data; end
        else ev_valid = 1'b0;
    end
    wire [127:0] entry = ev_type >= 4'd10 ? {ev_type, io_addr, io_wr_ev ? io_wdata : io_rdata, ev_payload, 3'd0, 32'd0, vm, pe, seq} :
                         ev_type == 4'd7 ? {ev_type, 15'd0, a20, walk_pde, ev_payload, pf_code, pf_addr, vm, pe, seq} :
                         ev_type >= 4'd8 ? {ev_type, 12'd0, mem_be, mem_addr, ev_payload, pf_code, pf_addr, vm, pe, seq}
                                         : {ev_type, cs, eip, ev_payload, pf_code, pf_addr, vm, pe, seq};
    (* ramstyle = "M10K" *) reg [127:0] ring[0:255];
    reg [127:0] ring_q, newest;
    reg [7:0] raddr;
    always @(posedge clk) begin
        prev_pe <= pe; prev_vm <= vm;
        pf_d1 <= page_fault; pf_d2 <= pf_d1 && pe;
        if (mem_write && mem_addr[31:20] != 0) ext_writes <= ext_writes + 1'b1;
        if (pe || IO_MODE) armed <= 1'b1;
        if (armed && !frozen && !pause && ev_valid && !(ev_type == 4'd5 && !armed)) begin
            ring[wp] <= entry;
            newest <= entry;
            wp <= wp + 1'b1;
            seq <= seq + 1'b1;
            if (ev_type >= 4'd3 && ev_type <= 4'd5) frozen <= 1'b1;
        end
        ring_q <= ring[raddr];
    end

    // ---- UART dump ---------------------------------------------------------
    localparam integer DIV = (CLOCK_HZ + 57600) / 115200;
    localparam integer SECOND = CLOCK_HZ;
    reg [$clog2(DIV+1)-1:0] baud = 0;
    reg [9:0] shift = 10'h3ff;
    reg [3:0] bits = 0;
    reg [$clog2(SECOND*10+1)-1:0] timer = 0;
    // Line generator: kind 'H' (heartbeat), 'B', 'E' x256, 'Z'.
    localparam S_IDLE = 0, S_LOAD = 1, S_LINE = 2;
    reg [1:0] st = S_IDLE;
    reg [7:0] kind;
    reg [8:0] line_no;               // dump: 0 = B, 1..256 = E, 257 = Z
    reg [5:0] pos;                   // character within the line
    reg [127:0] held;
    wire [3:0] nib = held[127:124];
    wire [7:0] hex = nib < 10 ? 8'h30 + nib : 8'h41 + nib - 10;
    wire has_hex = kind == "H" || kind == "E";
    wire [5:0] last_pos = has_hex ? 6'd33 : 6'd1;
    wire [7:0] ch = pos == 0 ? kind : pos == last_pos ? 8'h0a : hex;
    assign tx = shift[0];
    always @(posedge clk) begin
        if (bits != 0) begin
            if (baud == 0) begin shift <= {1'b1, shift[9:1]}; bits <= bits - 1'b1; baud <= DIV - 1; end
            else baud <= baud - 1'b1;
        end else case (st)
            S_IDLE: if (timer != 0) timer <= timer - 1'b1;
                    else if (frozen || IO_MODE) begin line_no <= 0; kind <= "B"; pos <= 0; st <= S_LINE; pause <= 1'b1; end
                    else begin held <= newest; kind <= "H"; pos <= 0; st <= S_LINE; end
            S_LOAD: begin held <= ring_q; kind <= "E"; pos <= 0; st <= S_LINE; end   // ring_q valid (raddr set 2+ clocks ago)
            default: begin
                shift <= {1'b1, ch, 1'b0}; bits <= 10; baud <= DIV - 1;
                if (pos != 0 && pos != last_pos) held <= {held[123:0], 4'b0};
                if (pos != last_pos) pos <= pos + 1'b1;
                else if (kind == "H" || kind == "Z") begin
                    st <= S_IDLE; pause <= 1'b0;
                    timer <= IO_MODE ? SECOND * 10 - 1 : SECOND - 1;
                end
                else begin
                    // next dump line: entries oldest (wp) first
                    line_no <= line_no + 1'b1;
                    if (line_no == 256) begin kind <= "Z"; pos <= 0; end
                    else begin raddr <= wp + line_no[7:0]; st <= S_LOAD; end
                end
            end
        endcase
    end
endmodule
