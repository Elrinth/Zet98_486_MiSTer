// SPDX-License-Identifier: GPL-3.0-or-later
// Native pixel aspect and optional exact-integer viewports. The crop controls
// are consumed only by the HDMI capture path, never by native analogue RGB.
module pc98_video_scale (
    input wire clk, source_clk, reset, ce, vs, de,
    input wire [11:0] hdmi_width, hdmi_height,
    input wire [2:0] mode,
    input wire [11:0] custom_x, custom_y,
    output reg [12:0] arx, ary,
    output reg [11:0] crop_left, crop_top, crop_width, crop_height
);
    // Mode/custom aspect arrive on clk_sys; dimensions already use clk_vid.
    // Keep the local two-cycle dimension latency and handshake only host data.
    wire [26:0] settings_video;
    video_config_snapshot #(27) host_scale_settings (
        .source_clk(source_clk), .video_clk(clk),
        .source_data({mode,custom_x,custom_y}), .video_data(settings_video)
    );
    reg [23:0] dimensions_meta, dimensions_video;
    wire [11:0] video_width=dimensions_video[23:12];
    wire [11:0] video_height=dimensions_video[11:0];
    wire [2:0] video_mode=settings_video[26:24];
    wire [11:0] video_custom_x=settings_video[23:12];
    wire [11:0] video_custom_y=settings_video[11:0];
    always @(posedge clk) begin
        if (reset) begin dimensions_meta<=0; dimensions_video<=0; end
        else begin
            dimensions_meta<={hdmi_width,hdmi_height};
            dimensions_video<=dimensions_meta;
        end
    end
    reg old_de, old_vs;
    reg [11:0] pixels, lines, first_width;
    reg [11:0] source_width, source_height;
    always @(posedge clk) begin
        if (reset) begin
            old_de<=0; old_vs<=0; pixels<=0; lines<=0; first_width<=0;
            source_width<=640; source_height<=400;
        end else if (ce) begin
            old_de<=de; old_vs<=vs;
            if (de && pixels!=4095) pixels<=pixels+1'b1;
            if (!de && old_de) begin
                if (!lines) first_width<=pixels;
                if (lines!=4095) lines<=lines+1'b1;
                pixels<=0;
            end
            if (vs && !old_vs) begin
                if (first_width && lines) begin
                    source_width<=first_width; source_height<=lines;
                end
                pixels<=0; lines<=0;
            end
        end
    end

    localparam START=0, SEARCH=1, CROP_X=2, CROP_Y=3, FINISH=4;
    reg [2:0] state, selected_mode;
    reg [11:0] sw, sh, ow, oh, factor, best_w, best_h;
    reg [12:0] candidate_w, candidate_h;
    reg [11:0] remaining, columns, rows, viewport_w, viewport_h;
    // Repeated addition/subtraction avoids a combinational divider on the
    // pixel clock. Even a 4095-pixel output finishes well inside one frame.
    always @(posedge clk) begin
        if (reset) begin
            state<=START; selected_mode<=0;
            sw<=640; sh<=400; ow<=0; oh<=0; factor<=1;
            best_w<=0; best_h<=0; candidate_w<=0; candidate_h<=0;
            remaining<=0; columns<=0; rows<=0; viewport_w<=0; viewport_h<=0;
            arx<=640; ary<=400;
            crop_left<=0; crop_top<=0; crop_width<=0; crop_height<=0;
        end else case (state)
            START: begin
                sw<=source_width; sh<=source_height;
                ow<=video_width; oh<=video_height; selected_mode<=video_mode;
                candidate_w<={1'b0,source_width};
                candidate_h<={1'b0,source_height};
                best_w<=0; best_h<=0; factor<=1;
                if ((video_mode==1 || video_mode==2) && video_width && video_height)
                    state<=SEARCH;
                else begin
                    crop_left<=0; crop_top<=0; crop_width<=0; crop_height<=0;
                    case (video_mode)
                        3: begin arx<=0; ary<=0; end // Stretch to output.
                        4: begin arx<=4; ary<=3; end // Traditional CRT shape.
                        5: begin arx<={1'b0,video_custom_x}; ary<={1'b0,video_custom_y}; end
                        default: begin arx<={1'b0,source_width}; ary<={1'b0,source_height}; end
                    endcase
                end
            end
            SEARCH: begin
                if (candidate_w<=ow && candidate_h<=oh) begin
                    best_w<=candidate_w[11:0]; best_h<=candidate_h[11:0];
                    if (candidate_w==ow || candidate_h==oh) begin
                        arx<={1'b1,candidate_w[11:0]}; ary<={1'b1,candidate_h[11:0]};
                        crop_left<=0; crop_top<=0; crop_width<=0; crop_height<=0;
                        state<=START;
                    end else begin
                        candidate_w<=candidate_w+{1'b0,sw};
                        candidate_h<=candidate_h+{1'b0,sh}; factor<=factor+1'b1;
                    end
                end else if (selected_mode==1 || !best_w) begin
                    arx<=best_w ? {1'b1,best_w} : {1'b0,sw};
                    ary<=best_h ? {1'b1,best_h} : {1'b0,sh};
                    crop_left<=0; crop_top<=0; crop_width<=0; crop_height<=0;
                    state<=START;
                end else begin
                    remaining<=ow; columns<=0; rows<=0; viewport_w<=0; viewport_h<=0;
                    state<=CROP_X;
                end
            end
            CROP_X: begin
                if (remaining>=factor && columns<sw) begin
                    remaining<=remaining-factor; columns<=columns+1'b1;
                    viewport_w<=viewport_w+factor;
                end else begin remaining<=oh; state<=CROP_Y; end
            end
            CROP_Y: begin
                if (remaining>=factor && rows<sh) begin
                    remaining<=remaining-factor; rows<=rows+1'b1;
                    viewport_h<=viewport_h+factor;
                end else state<=FINISH;
            end
            FINISH: begin
                arx<={1'b1,viewport_w}; ary<={1'b1,viewport_h};
                crop_left<=(sw-columns)>>1; crop_top<=(sh-rows)>>1;
                crop_width<=columns; crop_height<=rows;
                state<=START;
            end
            default: state<=START;
        endcase
    end
endmodule

// Zero-latency DE mask at the final HDMI scaler input. Position advances only
// on CE; RGB, sync and the native VGA path are untouched. Latch one complete
// crop rectangle during VS so a menu change cannot split a captured frame.
module pc98_hdmi_crop (
    input wire clk, reset, ce, vs, de,
    input wire [11:0] left, top, width, height,
    output wire cropped_de
);
    reg old_de=0, old_vs=0;
    reg [11:0] x=0, y=0, x0=0, y0=0;
    reg [12:0] x1=0, y1=0;
    reg enabled=0;
    assign cropped_de=de && (!enabled ||
        (x>=x0 && {1'b0,x}<x1 && y>=y0 && {1'b0,y}<y1));
    always @(posedge clk) begin
        if (reset) begin
            old_de<=0; old_vs<=0; x<=0; y<=0; enabled<=0;
            x0<=0; y0<=0; x1<=0; y1<=0;
        end else if (ce) begin
            old_de<=de; old_vs<=vs;
            if (de && x!=4095) x<=x+1'b1;
            if (!de && old_de) begin x<=0; if (y!=4095) y<=y+1'b1; end
            if (vs && !old_vs) begin
                x<=0; y<=0; enabled<=|width && |height;
                x0<=left; y0<=top;
                x1<={1'b0,left}+{1'b0,width}; y1<={1'b0,top}+{1'b0,height};
            end
        end
    end
endmodule
