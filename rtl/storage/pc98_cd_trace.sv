// SPDX-License-Identifier: GPL-3.0-or-later
`timescale 1ns/1ps
// CD trace (debug builds only): streams CD-ROM events as text lines on a
// 115200 8N1 UART, to find out why CD audio stutters.
//   tttttt C oo aa bb cc dd ee ff gg hh ii   packet command (CDB bytes 0..9)
//   tttttt R nn nn                           the previous READ SUB-CHANNEL (42h) was
//                                            repeated nnnn more times (games poll it)
//   tttttt S ss                              audio status changed (11 play, 12 pause, 13 done, 15 none)
//   tttttt U                                 audio output starved (buffer empty while playing)
//   tttttt u dd dd                           starvation ended after dddd ms
//   tttttt F dd dd ff                        audio fetch took dddd ms (>= 12 ms only);
//                                            ff bit0 HDD busy, bit1 floppy busy, bit2 CD data read, during it
//   tttttt P id hs bl bh rx ry lx ly         SNAC port 1 pad bytes (on change, <= 10/s)
//   tttttt G pp s7 s6 .. s0                  graphics GDC as programmed by the game: PITCH,
//                                            PRAM bytes 7..0 (area 2: s7..s4, area 1: s3..s0:
//                                            SAD low, SAD mid, SAD hi | LEN low << 4, LEN hi)
//                                            on change, <= 10/s
//   tttttt K aa dd                           PC-9801-86 PCM register write: port A4aah = dd
//                                            (66 volume/FIFO flags, 68 control, 6A format/threshold)
//   tttttt W nn nn                           bytes the game pushed into the PCM FIFO (A46Ch)
//                                            during the last 100 ms (only when nonzero)
//   tttttt E rr hh ll                        graphics register write, only when the value
//                                            changes: rr 00-07 EGC 4A0h-4AEh (hh:ll word),
//                                            08 GRCG mode 7Ch, 09 GRCG tile 7Eh, 0A mode 6Ah,
//                                            0B display page A4h, 0C drawing page A6h
//   tttttt V nn pp aaaa rrrr s0 s1 s2        one per frame (at vertical sync): frame number,
//                                            pages (bit0 display A4h, bit1 drawing A6h), time
//                                            of the last A4h write and of the last PRAM command
//                                            in the previous frame (1024-clock units since
//                                            vsync, ffff = none), area 1 start (PRAM 0-2)
//   tttttt X ee ee ee ee aa aa dd dd         every 100 ms: CPU EIP, last I/O port and data
//   tttttt I ee ee ee ee pp pp dd dd ww      ring-0 I/O (EIP >= C0000000): EIP, port, data,
//                                            ww 01 write / 00 read; PIC, PIT, CG font, 5Fh
//                                            and mouse ports are left out, and so are
//                                            repeats of the previous identical access
//   tttttt D cc ss ss oo oo ll ll ll ll      ATA command (write to 64Eh) from any mode: command,
//                                            CS:IP (EIP when 32-bit), then LBA 27..0 from
//                                            64Ch/64Ah/648h/646h (dev/head, cyl hi, cyl lo, sector)
//                                            (a read of the next sequential sector is not logged)
//   tttttt J ee ee ee ee                     control transfer to C037xxxx (Windows 95 IFSMgr init)
//                                            or to V86/real code (CS:IP, not FD80/FB5x stubs) once
//                                            IFSMgr has opened IFS$HLP$ (C03712A0-C03712CF)
//   tttttt G gg gg vv ee ee ee ee            interrupt/exception entry once armed (see J): IDT gate
//                                            address bits 15..0, VM flag, CS:IP/EIP
//   tttttt O                                 events were lost (FIFO full)
// tttttt is a millisecond timestamp, all numbers hex.
module pc98_cd_trace #(
    parameter integer CLK_HZ = 90000000
) (
    input wire clk,
    input wire [91:0] trace,             // pc98_atapi trace port
    input wire hdd_busy, fdd_busy,
    input wire [63:0] pad1,              // snac_psx_pad raw1
    input wire [71:0] video,             // GDC PITCH and PRAM 7..0 (see Zet98.sv)
    input wire pcm_ctl,                  // strobe: write to A466h/A468h/A46Ah
    input wire [7:0] pcm_port, pcm_data,
    input wire pcm_push,                 // strobe: write to A46Ch (FIFO data)
    input wire gfx_wr,                   // strobe: graphics register write (see E)
    input wire [3:0] gfx_reg,
    input wire [15:0] gfx_data,
    input wire [63:0] cpu_sample,        // {EIP, last I/O port, last I/O data}
    input wire io_ev, io_wr,             // strobe: an I/O access completed (port/data in cpu_sample)
    input wire [17:0] gate,              // {IDT gate read, VM, gate address 15..0}
    input wire frame_ev,                 // strobe: one per frame
    input wire [71:0] frame_data,
    output reg tx = 1
);
    // ---- decode the trace port ----------------------------------------------
    wire cmd = trace[0];
    wire [79:0] cdb = trace[80:1];
    wire a_req = trace[81];
    wire starving = trace[82];
    wire [7:0] status = trace[90:83];
    wire host_req = trace[91];

    // ---- millisecond timestamp ------------------------------------------------
    localparam integer MS = CLK_HZ / 1000;
    reg [$clog2(MS)-1:0] ms_div = 0;
    reg [23:0] now = 0;
    wire ms_tick = ms_div == MS - 1;
    always @(posedge clk) begin
        ms_div <= ms_tick ? 0 : ms_div + 1'b1;
        if (ms_tick) now <= now + 1'b1;
    end

    // ---- event detection ------------------------------------------------------
    reg a_req_d = 0, starving_d = 0;
    reg [7:0] status_d = 8'h15;
    reg [15:0] fetch_ms = 0, starve_ms = 0;
    reg [2:0] fetch_flags = 0;
    reg [7:0] ev_type;
    reg [79:0] ev_data;
    reg ev = 0;
    // Repeated identical 42h commands are counted, not logged one by one.
    reg [79:0] last_cdb = 0;
    reg [15:0] repeats = 0;
    reg [79:0] held_cdb = 0;
    reg held = 0;                        // a command waits behind its R line
    reg [9:0] rep_ms = 0;
    wire repeat_cmd = cmd && cdb == last_cdb && cdb[7:0] == 8'h42;
    reg [63:0] pad_d = 0;
    reg [6:0] pad_wait = 0;              // ms until the next pad line may go out
    reg [71:0] video_d = 0;
    reg [15:0] push_count = 0;
    reg [6:0] push_ms = 0;
    reg push_report = 0;
    reg [15:0] push_total = 0;
    reg [6:0] x_ms = 0;
    reg x_due = 0;
    reg [15:0] gfx_last [0:15];
    reg [15:0] gfx_valid = 0;
    wire gfx_change = gfx_wr && (!gfx_valid[gfx_reg] || gfx_last[gfx_reg] != gfx_data);
    reg [6:0] video_wait = 0;
    // Ring-0 I/O for the Windows 95 boot trace; the strobe is one clock behind
    // the sample, so it is delayed by one more clock here.
    reg io_ev_d = 0, io_wr_d = 0;
    wire [15:0] io_port = cpu_sample[31:16];
    wire io_noisy = io_port == 16'h00 || io_port == 16'h02 || io_port == 16'h08 || io_port == 16'h0a ||
                    io_port == 16'h71 || io_port == 16'h77 || io_port == 16'h5f ||
                    io_port == 16'ha1 || io_port == 16'ha3 || io_port == 16'ha5 || io_port == 16'ha9 ||
                    io_port[15:4] == 12'h7fd;
    // Polling loops (GDC status, IDE status) repeat the same access: only the
    // first of a run of identical ones (EIP, port, data, direction) is logged.
    reg [64:0] io_last = 0;
    wire io_trace = io_ev_d && cpu_sample[63:60] == 4'hc && !io_noisy && {cpu_sample, io_wr_d} != io_last;
    // ATA task file snoop for D lines (byte writes to the even ports)
    reg [7:0] ata_cnt = 0, ata_sec = 0, ata_cyl_lo = 0, ata_cyl_hi = 0, ata_dev = 0;
    // Sequential single-sector reads (command 20h at the previous LBA + 1) are
    // not logged: only the first sector of each run.
    reg [27:0] ata_prev = 0;
    wire [27:0] ata_lba = {ata_dev[3:0], ata_cyl_hi, ata_cyl_lo, ata_sec};
    wire ata_go = io_ev_d && io_wr_d && io_port == 16'h064e;
    wire ata_cmd = ata_go && !(cpu_sample[7:0] == 8'h20 && ata_lba == ata_prev + 1'b1);
    // Branch points of VMM's UNICODE.BIN loader (Windows 95, VMM init code)
    wire [31:0] cpu_eip = cpu_sample[63:32];
    wire [15:0] eip_lo = cpu_eip[15:0];
    // V86/real code is sampled as CS:IP (EIP < 10000h): watch it too, except the
    // BIOS timer path and VMM's V86 callback stubs that run on every tick.
    wire v86_code = cpu_eip[31:28] != 4'hc && cpu_eip[31:16] != 16'hfd80 &&
                    cpu_eip[31:16] != 16'hfb50 && cpu_eip[31:16] != 16'hfb5c && cpu_eip[31:16] != 16'hfb5d;
    // V86 logging is armed when IFSMgr returns from opening IFS$HLP$ (C03712AEh;
    // the sample runs ~14h ahead), so the FIFO holds the IOCTL call's own path.
    reg v86_armed = 0;
    reg gate_d = 0;
    wire gate_ev = v86_armed && gate[17] && !gate_d;
    wire eip_watch = cpu_eip[31:16] == 16'hc037 || (v86_armed && v86_code);
    reg [31:0] eip_last = 0;
    // Only control transfers: an EIP that is not a short forward step from the last one.
    wire [31:0] eip_step = cpu_eip - eip_last;
    wire eip_hit = eip_watch && cpu_eip != eip_last && eip_step > 32'd16;
    always @(posedge clk) begin
        io_ev_d <= io_ev; io_wr_d <= io_wr;
        eip_last <= cpu_eip;
        gate_d <= gate[17];
        if (cpu_eip >= 32'hc03712a0 && cpu_eip < 32'hc03712d0) v86_armed <= 1;
        if (ata_go) ata_prev <= ata_lba;
        if (io_ev_d && io_wr_d) case (io_port)
            16'h0644: ata_cnt <= cpu_sample[7:0];
            16'h0646: ata_sec <= cpu_sample[7:0];
            16'h0648: ata_cyl_lo <= cpu_sample[7:0];
            16'h064a: ata_cyl_hi <= cpu_sample[7:0];
            16'h064c: ata_dev <= cpu_sample[7:0];
            default: ;
        endcase
        if (io_ev_d && cpu_sample[63:60] == 4'hc && !io_noisy) io_last <= {cpu_sample, io_wr_d};
        a_req_d <= a_req; starving_d <= starving; status_d <= status;
        if (a_req && !a_req_d) begin fetch_ms <= 0; fetch_flags <= 0; end
        else if (a_req) begin
            if (ms_tick && fetch_ms != 16'hffff) fetch_ms <= fetch_ms + 1'b1;
            fetch_flags <= fetch_flags | {host_req, fdd_busy, hdd_busy};
        end
        if (starving && !starving_d) starve_ms <= 0;
        else if (starving && ms_tick && starve_ms != 16'hffff) starve_ms <= starve_ms + 1'b1;
        // One event per clock; priorities follow how rare each one is.
        ev <= 1;
        if (ms_tick && rep_ms != 0) rep_ms <= rep_ms - 1'b1;
        if (repeat_cmd) begin
            if (repeats != 16'hffff) repeats <= repeats + 1'b1;
            if (repeats == 0) rep_ms <= 500;
            ev <= 0;
        end else if (cmd && repeats != 0) begin
            // Report the count first; the new command follows next clock.
            ev_type <= "R"; ev_data <= {64'b0, repeats}; repeats <= 0;
            held_cdb <= cdb; held <= 1; last_cdb <= cdb;
        end else if (held) begin
            ev_type <= "C"; ev_data <= held_cdb; held <= 0;
        end else if (cmd) begin ev_type <= "C"; ev_data <= cdb; last_cdb <= cdb; end
        else if (repeats != 0 && rep_ms == 0) begin
            // Long polling runs: report the count twice a second.
            ev_type <= "R"; ev_data <= {64'b0, repeats}; repeats <= 0;
        end
        else if (status != status_d) begin ev_type <= "S"; ev_data <= {72'b0, status}; end
        else if (starving && !starving_d) begin ev_type <= "U"; ev_data <= 0; end
        else if (!starving && starving_d) begin ev_type <= "u"; ev_data <= {64'b0, starve_ms}; end
        else if (!a_req && a_req_d && fetch_ms >= 12) begin
            ev_type <= "F"; ev_data <= {56'b0, fetch_ms, 5'b0, fetch_flags};
        end else if (gate_ev) begin
            ev_type <= "G"; ev_data <= {24'b0, gate[15:0], 7'b0, gate[16], cpu_eip};
        end else if (eip_hit) begin
            ev_type <= "J"; ev_data <= {48'b0, cpu_eip};
        end else if (ata_cmd) begin
            ev_type <= "D"; ev_data <= {8'b0, cpu_sample[7:0], cpu_sample[63:32], ata_dev, ata_cyl_hi, ata_cyl_lo, ata_sec};
        end else if (io_trace) begin
            ev_type <= "I"; ev_data <= {8'b0, cpu_sample, 7'b0, io_wr_d};
        end else if (x_due) begin
            ev_type <= "X"; ev_data <= {16'b0, cpu_sample}; x_due <= 0;
        end else if (frame_ev) begin
            ev_type <= "V"; ev_data <= {8'b0, frame_data};
        end else if (gfx_change) begin
            ev_type <= "E"; ev_data <= {56'b0, 4'b0, gfx_reg, gfx_data};
            gfx_last[gfx_reg] <= gfx_data; gfx_valid[gfx_reg] <= 1;
        end else if (pcm_ctl) begin
            ev_type <= "K"; ev_data <= {64'b0, pcm_port, pcm_data};
        end else if (push_report) begin
            ev_type <= "W"; ev_data <= {64'b0, push_total}; push_report <= 0;
        end else if (video != video_d && video_wait == 0) begin
            ev_type <= "G"; ev_data <= {8'b0, video}; video_d <= video; video_wait <= 100;
        end else if (pad1 != pad_d && pad_wait == 0) begin
            ev_type <= "P"; ev_data <= {16'b0, pad1}; pad_d <= pad1; pad_wait <= 100;
        end else ev <= 0;
        if (ms_tick && pad_wait != 0) pad_wait <= pad_wait - 1'b1;
        if (ms_tick && video_wait != 0) video_wait <= video_wait - 1'b1;
        if (ms_tick) begin
            if (x_ms == 99) begin x_ms <= 0; x_due <= 1; end else x_ms <= x_ms + 1'b1;
        end
        // FIFO pushes per 100 ms window.
        if (ms_tick && push_ms == 99) begin
            push_ms <= 0;
            if (push_count != 0 || pcm_push) begin
                push_total <= push_count + pcm_push; push_report <= 1;
            end
            push_count <= 0;
        end else begin
            if (ms_tick) push_ms <= push_ms + 1'b1;
            if (pcm_push && push_count != 16'hffff) push_count <= push_count + 1'b1;
        end
    end

    // ---- event FIFO ---------------------------------------------------------------
    (* ramstyle="M10K, no_rw_check" *) reg [111:0] fifo[0:255];
    reg [7:0] wp = 0, rp = 0;
    wire [7:0] wp_next = wp + 1'b1;
    reg lost = 0;
    reg [111:0] rec;
    reg pop = 0;
    always @(posedge clk) begin
        if (ev) begin
            if (wp_next != rp) begin fifo[wp] <= {ev_type, now, ev_data}; wp <= wp_next; end
            else lost <= 1;
        end
        rec <= fifo[rp];
        if (pop) begin rp <= rp + 1'b1; end
        if (pop_lost) lost <= 0;
    end

    // ---- line formatter ---------------------------------------------------------------
    // Characters: 6 time digits, space, type, then per payload byte " hh",
    // then CR LF. Payload byte counts per type.
    function automatic [7:0] hex(input [3:0] v);
        hex = v < 10 ? "0" + v : "a" + v - 10;
    endfunction
    function automatic [3:0] payload_bytes(input [7:0] t);
        case (t)
            "C": payload_bytes = 10;
            "S": payload_bytes = 1;
            "u": payload_bytes = 2;
            "R": payload_bytes = 2;
            "F": payload_bytes = 3;
            "P": payload_bytes = 8;
            "G": payload_bytes = 9;
            "K": payload_bytes = 2;
            "E": payload_bytes = 3;
            "V": payload_bytes = 9;
            "X": payload_bytes = 8;
            "I": payload_bytes = 9;
            "D": payload_bytes = 9;
            "J": payload_bytes = 4;
            "G": payload_bytes = 7;
            "W": payload_bytes = 2;
            default: payload_bytes = 0;
        endcase
    endfunction
    localparam F_IDLE = 0, F_LOAD = 1, F_EMIT = 2, F_WAIT = 3;
    reg [1:0] fstate = F_IDLE;
    reg [111:0] line;
    reg [5:0] pos = 0;                   // character index within the line
    reg [5:0] line_len;
    reg [7:0] ch;
    reg send = 0;
    wire busy_tx;
    reg pop_lost = 0;
    // Character at pos: 0-5 time, 6 space, 7 type, then 3 per payload byte
    // (space, high, low) with byte k at line[8*(9-k) +: 8] for C (CDB 0 first);
    // shorter payloads are right-aligned in ev_data, so index from the end.
    wire [7:0] t_type = line[111:104];
    wire [23:0] t_time = line[103:80];
    wire [79:0] t_data = line[79:0];
    wire [3:0] nbytes = payload_bytes(t_type);
    wire [5:0] rel = pos - 6'd8;
    wire [3:0] k = rel / 3;
    wire [1:0] kpos = rel % 3;
    wire [3:0] byte_sel = t_type == "C" ? k : (nbytes - 1'b1 - k);   // index into t_data bytes
    wire [7:0] pbyte = t_type == "C" ? t_data[8*k +: 8] : t_data[8*byte_sel +: 8];
    always @* begin
        if (pos < 6) ch = hex(t_time[4*(5-pos) +: 4]);
        else if (pos == 6) ch = " ";
        else if (pos == 7) ch = t_type;
        else if (pos < 8 + 3*nbytes) ch = kpos == 0 ? " " : kpos == 1 ? hex(pbyte[7:4]) : hex(pbyte[3:0]);
        else if (pos == 8 + 3*nbytes) ch = 8'h0d;
        else ch = 8'h0a;
    end
    always @(posedge clk) begin
        pop <= 0; send <= 0; pop_lost <= 0;
        case (fstate)
            F_IDLE: if (lost) begin
                        line <= {"O", now, 80'b0}; pos <= 0; pop_lost <= 1; fstate <= F_EMIT;
                    end else if (rp != wp && !pop) begin fstate <= F_LOAD; end
            F_LOAD: begin line <= rec; pos <= 0; pop <= 1; fstate <= F_EMIT; end
            F_EMIT: if (!busy_tx && !send) begin send <= 1; fstate <= F_WAIT; end
            F_WAIT: if (!send && !busy_tx) begin
                        if (pos == 9 + 3*nbytes) fstate <= F_IDLE;
                        else begin pos <= pos + 1'b1; fstate <= F_EMIT; end
                    end
        endcase
    end

    // ---- UART transmitter ------------------------------------------------------------------
    localparam integer BAUD_DIV = CLK_HZ / 115200;
    reg [$clog2(BAUD_DIV)-1:0] baud = 0;
    // Start bit goes out at once; ticks 1-8 send the data bits LSB first,
    // tick 9 the stop bit, and tick 10 ends its full bit period.
    reg [8:0] shift = 9'h1ff;
    reg [3:0] bits = 0;
    assign busy_tx = bits != 0;
    always @(posedge clk) begin
        if (send && bits == 0) begin
            tx <= 0; shift <= {1'b1, ch}; bits <= 10; baud <= 0;
        end else if (bits != 0) begin
            if (baud == BAUD_DIV - 1) begin
                baud <= 0; tx <= shift[0]; shift <= {1'b1, shift[8:1]}; bits <= bits - 1'b1;
            end else baud <= baud + 1'b1;
        end
    end
endmodule
