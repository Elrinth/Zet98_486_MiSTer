// SPDX-License-Identifier: GPL-3.0-or-later
`timescale 1ns/1ps
// Single-outstanding DDR arbiter. All clients run on DDR's CPU clock.
// Round-robin among ordinary CPU RAM, CPU framebuffer and video (read-only).
// CPU transactions are one 64-bit word; video bursts are bounded to 1..16.
// A grant stays fixed under waitrequest. Read ownership lasts through the
// final return beat, including gaps and guest reset. Reset blocks new commands
// but forwards outstanding responses so each client can drain its own request.
module pc98_pegc_ddr_arbiter (
    input wire clk, reset,
    input wire [28:0] ram_address,
    input wire [63:0] ram_writedata,
    input wire [7:0] ram_byteenable,
    input wire ram_read, ram_write,
    output wire ram_busy, ram_readdatavalid,
    input wire [28:0] fb_address,
    input wire [63:0] fb_writedata,
    input wire [7:0] fb_byteenable,
    input wire fb_read, fb_write,
    output wire fb_busy, fb_readdatavalid,
    input wire [18:3] video_address,
    input wire [4:0] video_burstcount,
    input wire video_read,
    output wire video_busy, video_readdatavalid,
    output wire [63:0] client_readdata,
    output reg [28:0] ddr_address,
    output reg [63:0] ddr_writedata,
    output reg [7:0] ddr_byteenable, ddr_burstcount,
    output wire ddr_read, ddr_write,
    input wire ddr_busy, ddr_readdatavalid,
    input wire [63:0] ddr_readdata
);
    reg grant_valid=0;
    reg [1:0] grant=0, next_client=0, read_owner=0;
    reg [4:0] remaining=0;
    wire [16:0] video_end = {1'b0,video_address} + {12'b0,video_burstcount};
    wire valid_video = video_read && video_burstcount>=1 && video_burstcount<=16 &&
                       video_end<=17'h10000;
    wire [2:0] requests = {valid_video,fb_read||fb_write,ram_read||ram_write};
    reg chosen_read, chosen_write;
    always @* begin
        ddr_address=0; ddr_writedata=0; ddr_byteenable=0;
        ddr_burstcount=1; chosen_read=0; chosen_write=0;
        case(grant)
            0: begin
                ddr_address=ram_address; ddr_writedata=ram_writedata;
                ddr_byteenable=ram_byteenable;
                chosen_read=ram_read; chosen_write=ram_write;
            end
            1: begin
                ddr_address=fb_address; ddr_writedata=fb_writedata;
                ddr_byteenable=fb_byteenable;
                chosen_read=fb_read; chosen_write=fb_write;
            end
            2: begin
                ddr_address=(32'h30f00000 >> 3) | {13'b0,video_address};
                ddr_byteenable=8'hff; ddr_burstcount={3'b0,video_burstcount};
                chosen_read=valid_video;
            end
            default: ;
        endcase
    end
    wire command_window = grant_valid && remaining==0 && !reset;
    assign ddr_read = command_window && chosen_read;
    assign ddr_write = command_window && chosen_write;
    wire accepted = (ddr_read || ddr_write) && !ddr_busy;
    wire read_accepted = ddr_read && !ddr_busy;
    wire [1:0] response_owner = remaining!=0 ? read_owner : grant;
    wire response_valid = ddr_readdatavalid && (remaining!=0 || read_accepted);
    assign client_readdata=ddr_readdata;
    assign ram_readdatavalid=response_valid && response_owner==0;
    assign fb_readdatavalid=response_valid && response_owner==1;
    assign video_readdatavalid=response_valid && response_owner==2;
    assign ram_busy=!(command_window && grant==0) || ddr_busy;
    assign fb_busy=!(command_window && grant==1) || ddr_busy;
    assign video_busy=!(command_window && grant==2 && valid_video) || ddr_busy;

    always @(posedge clk) begin
        // Do not erase an outstanding response tag on a soft reset.
        if(remaining!=0 && ddr_readdatavalid) remaining<=remaining-1'b1;
        if(reset) begin
            grant_valid<=0; next_client<=0;
        end else if(remaining==0) begin
            if(!grant_valid) begin
                // Explicit, bounded priority permutations also suit Quartus17.
                case(next_client)
                    0: if(requests[0]) begin grant<=0;grant_valid<=1;end
                       else if(requests[1]) begin grant<=1;grant_valid<=1;end
                       else if(requests[2]) begin grant<=2;grant_valid<=1;end
                    1: if(requests[1]) begin grant<=1;grant_valid<=1;end
                       else if(requests[2]) begin grant<=2;grant_valid<=1;end
                       else if(requests[0]) begin grant<=0;grant_valid<=1;end
                    2: if(requests[2]) begin grant<=2;grant_valid<=1;end
                       else if(requests[0]) begin grant<=0;grant_valid<=1;end
                       else if(requests[1]) begin grant<=1;grant_valid<=1;end
                    default: next_client<=0;
                endcase
            end else if(accepted) begin
                grant_valid<=0;
                next_client<=grant==2 ? 0 : grant+1'b1;
                if(read_accepted) begin
                    read_owner<=grant;
                    remaining<=ddr_burstcount[4:0] - (ddr_readdatavalid ? 5'd1 : 5'd0);
                end
            end else if(!requests[grant]) begin
                // Cancellation before acceptance is safe (e.g. CPU reset).
                grant_valid<=0;
            end
        end
    end
endmodule
