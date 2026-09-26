// SPDX-License-Identifier: GPL-3.0-or-later
`timescale 1ns/1ps
// Packed 640-pixel line fetch. Start during the leading horizontal blank.
// Two 1 KB line-buffer banks prevent a late fill from corrupting scanout.
// Request address/bank is held across a toggle/ack handshake; only complete
// lines can be published. Missed deadlines blank the whole line, never expose
// a partly-filled buffer. Controls supplied here must already be video-local.
// CPU-side DDR requests are 1..16 words and wrap inside the 512 KB framebuffer.
module pc98_pegc_line_fetch (
    input wire cpu_clk, video_clk, reset,
    input wire line_start, line_enable,
    input wire [18:3] line_address,
    input wire page_wrap,
    input wire active,
    input wire [9:0] pixel_x,
    output reg [7:0] pixel_data,
    output reg pixel_valid,
    output reg underrun,
    output wire line_busy,
    output wire [18:3] memory_address,
    output wire [4:0] memory_burstcount,
    output wire memory_read,
    input wire memory_busy, memory_readdatavalid,
    input wire [63:0] memory_readdata
);
    // The top-level reset combines CPU and video readiness. Assert both
    // domains immediately, but release each only on its own clock edges.
    // A CPU-domain release must never drive pixel-register asynchronous clears.
    (* preserve, altera_attribute="-name SYNCHRONIZER_IDENTIFICATION FORCED_IF_ASYNCHRONOUS" *)
        reg [1:0] cpu_reset_sync=2'b11, video_reset_sync=2'b11;
    always @(posedge cpu_clk or posedge reset)
        if(reset) cpu_reset_sync<=2'b11;
        else cpu_reset_sync<={cpu_reset_sync[0],1'b0};
    always @(posedge video_clk or posedge reset)
        if(reset) video_reset_sync<=2'b11;
        else video_reset_sync<={video_reset_sync[0],1'b0};
    wire cpu_reset=cpu_reset_sync[1], video_reset=video_reset_sync[1];
    (* ramstyle="M10K, no_rw_check" *) reg [63:0] line_buffer[0:255];
    (* preserve *) reg [17:0] request_payload;
    wire [17:0] request_transfer = request_payload;
    reg request_toggle, acknowledge_toggle=0;
    (* altera_attribute="-name SYNCHRONIZER_IDENTIFICATION FORCED_IF_ASYNCHRONOUS" *)
        reg [1:0] request_sync=0, acknowledge_sync;
    reg busy_video, current_request, active_started, display_bank, line_valid;
    assign line_busy=busy_video;

    always @(posedge video_clk or posedge video_reset) begin
        if(video_reset) begin
            request_payload<=0;request_toggle<=0;acknowledge_sync<=0;
            busy_video<=0;current_request<=0;active_started<=0;
            display_bank<=0;line_valid<=0;underrun<=0;
        end else begin
            acknowledge_sync<={acknowledge_sync[0],acknowledge_toggle};
            underrun<=0;
            if(line_start) begin
                line_valid<=0;active_started<=0;current_request<=0;
                if(line_enable && !busy_video) begin
                    request_payload<={page_wrap,~display_bank,line_address};
                    request_toggle<=!request_toggle;
                    busy_video<=1;current_request<=1;
                end
            end else if(active) begin
                active_started<=1;
                if(!active_started && line_enable && !line_valid) underrun<=1;
            end
            if(busy_video && acknowledge_sync[1]==request_toggle) begin
                busy_video<=0;
                // An old completion must not make a subsequent row visible.
                if(current_request && !line_start && !active_started && !active && line_enable) begin
                    display_bank<=request_payload[16];line_valid<=1;
                end
            end
        end
    end

    // Synchronous wide read followed by byte selection. Pixel validity follows
    // the same two registers; the palette/compositor must retain that alignment.
    reg [63:0] video_word;
    reg [2:0] video_lane;
    reg video_word_valid;
    always @(posedge video_clk) begin
        video_word<=line_buffer[{display_bank,pixel_x[9:3]}];
        video_lane<=pixel_x[2:0];
        pixel_data<=video_word[{video_lane,3'b0}+:8];
    end
    always @(posedge video_clk or posedge video_reset) begin
        if(video_reset) begin video_word_valid<=0;pixel_valid<=0;end
        else begin
            video_word_valid<=line_valid && line_enable && active && pixel_x<640;
            pixel_valid<=video_word_valid;
        end
    end

    localparam IDLE=0, ISSUE=1, RETURN_DATA=2, DONE=3;
    reg [1:0] state=IDLE;
    reg [18:3] next_address;
    reg [6:0] words_left, write_index;
    reg [4:0] burst_left=0;
    reg write_bank, active_request, wrap_page, cancelled=1;
    wire [16:0] until_wrap=wrap_page ? 17'h08000-{2'b0,next_address[17:3]} : 17'h10000-{1'b0,next_address};
    wire [4:0] bounded_count=words_left>=16 ? 5'd16 : words_left[4:0];
    wire [4:0] request_count=until_wrap<bounded_count ? until_wrap[4:0] : bounded_count;
    wire [15:0] advanced_address=next_address+request_count;
    assign memory_address=next_address;
    assign memory_burstcount=request_count;
    assign memory_read=state==ISSUE && !cpu_reset && !cancelled;
    wire accepted=memory_read && !memory_busy;
    wire beat=(state==RETURN_DATA || accepted) && memory_readdatavalid;
    always @(posedge cpu_clk) begin
        if(beat && !cpu_reset && !cancelled)
            line_buffer[{write_bank,write_index}]<=memory_readdata;
    end
    always @(posedge cpu_clk) begin
        request_sync<={request_sync[0],request_toggle};
        if(cpu_reset) begin
            request_sync<=0;acknowledge_toggle<=0;cancelled<=1;
            // DDR cannot cancel a burst already accepted by the arbiter.
            if(state==RETURN_DATA && burst_left!=0) begin
                if(memory_readdatavalid) begin
                    burst_left<=burst_left-1'b1;
                    if(burst_left==1) state<=IDLE;
                end
            end else state<=IDLE;
        end else case(state)
            IDLE: if(request_sync[1]!=acknowledge_toggle) begin
                next_address<=request_transfer[15:0];write_bank<=request_transfer[16];
                wrap_page<=request_transfer[17];
                active_request<=request_sync[1];write_index<=0;words_left<=80;
                cancelled<=0;state<=ISSUE;
            end
            ISSUE: if(accepted) begin
                if(wrap_page) next_address<={next_address[18],advanced_address[14:0]};
                else next_address<=advanced_address;
                words_left<=words_left-request_count;
                burst_left<=request_count-(memory_readdatavalid ? 5'd1 : 5'd0);
                if(memory_readdatavalid) write_index<=write_index+1'b1;
                if(request_count==1 && memory_readdatavalid)
                    state<=words_left==1 ? DONE : ISSUE;
                else state<=RETURN_DATA;
            end
            RETURN_DATA: if(memory_readdatavalid) begin
                burst_left<=burst_left-1'b1;write_index<=write_index+1'b1;
                if(burst_left==1)
                    state<=cancelled ? IDLE : words_left==0 ? DONE : ISSUE;
            end
            DONE: begin acknowledge_toggle<=active_request;state<=IDLE;end
        endcase
    end
endmodule
