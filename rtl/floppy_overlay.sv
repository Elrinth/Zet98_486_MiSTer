// SPDX-License-Identifier: GPL-3.0-or-later
// A small rotating floppy in the measured active raster's bottom-right corner.
// All video signals receive the same one-clock delay. Blanking is untouched.
module floppy_overlay #(
    parameter HOLD_FRAMES = 15,
    parameter ROTATE_FRAME_BITS = 2
) (
    input wire clk, reset, enabled, activity,
    input wire in_ce, in_hs, in_vs, in_de,
    input wire [7:0] in_r, in_g, in_b,
    output reg out_ce, out_hs, out_vs, out_de,
    output reg [7:0] out_r, out_g, out_b
);
    (* altera_attribute = "-name SYNCHRONIZER_IDENTIFICATION FORCED_IF_ASYNCHRONOUS" *)
    reg activity_meta, activity_sync, enabled_meta, enabled_sync;
    reg prev_de, prev_vs, sized;
    reg [11:0] x, y, max_width, width, height;
    reg [$clog2(HOLD_FRAMES+1)-1:0] hold_frames;
    reg [ROTATE_FRAME_BITS+1:0] rotation;
    wire frame_start = in_ce && in_vs && !prev_vs;
    wire visible = enabled_sync && sized && hold_frames != 0 && in_de &&
        x >= width - 12'd20 && x < width - 12'd4 &&
        y >= height - 12'd20 && y < height - 12'd4;
    wire [3:0] dx = x - (width - 12'd20);
    wire [3:0] dy = y - (height - 12'd20);
    reg [3:0] rx, ry;
    always @* begin
        case (rotation[ROTATE_FRAME_BITS+1:ROTATE_FRAME_BITS])
            0: begin rx=dx; ry=dy; end
            1: begin rx=dy; ry=15-dx; end
            2: begin rx=15-dx; ry=15-dy; end
            3: begin rx=15-dy; ry=dx; end
        endcase
    end
    wire body = rx >= 1 && rx <= 14 && ry >= 1 && ry <= 14 &&
        !(rx >= 12 && ry <= 2);
    wire outline = rx == 1 || rx == 14 || ry == 1 || ry == 14;
    wire shutter = rx >= 3 && rx <= 10 && ry <= 6;
    wire slot = rx >= 8 && rx <= 9 && ry >= 2 && ry <= 5;
    wire label_area = rx >= 3 && rx <= 12 && ry >= 9 && ry <= 12;
    wire [23:0] color = outline ? 24'h102030 :
        slot ? 24'h102030 : (shutter || label_area) ? 24'he8f0f0 : 24'h3090e0;

    always @(posedge clk or posedge reset) begin
        if (reset) begin
            activity_meta<=0; activity_sync<=0;
            enabled_meta<=0; enabled_sync<=0;
            prev_de<=0; prev_vs<=0; sized<=0;
            x<=0; y<=0; max_width<=0; width<=0; height<=0;
            hold_frames<=0; rotation<=0;
            out_ce<=0; out_hs<=0; out_vs<=0; out_de<=0;
            out_r<=0; out_g<=0; out_b<=0;
        end else begin
            activity_meta<=activity; activity_sync<=activity_meta;
            enabled_meta<=enabled; enabled_sync<=enabled_meta;
            if (activity_sync) hold_frames<=HOLD_FRAMES;
            else if (frame_start && hold_frames != 0) hold_frames<=hold_frames-1'b1;
            if (hold_frames == 0) rotation<=0;
            else if (frame_start) rotation<=rotation+1'b1;
            if (in_ce) begin
                prev_de<=in_de; prev_vs<=in_vs;
                if (frame_start) begin
                    width<=max_width; height<=y;
                    sized<=max_width >= 24 && y >= 24;
                    x<=0; y<=0; max_width<=0;
                end else if (in_de) x<=x+1'b1;
                else begin
                    x<=0;
                    if (prev_de) begin
                        y<=y+1'b1;
                        if (x > max_width) max_width<=x;
                    end
                end
            end
            out_ce<=in_ce;
            if (in_ce) begin
                out_hs<=in_hs; out_vs<=in_vs; out_de<=in_de;
                if (visible && body) {out_r,out_g,out_b}<=color;
                else {out_r,out_g,out_b}<={in_r,in_g,in_b};
            end
        end
    end
endmodule
