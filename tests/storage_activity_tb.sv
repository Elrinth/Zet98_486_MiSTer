// SPDX-License-Identifier: GPL-3.0-or-later
`timescale 1ns/1ps
module storage_activity_tb;
    reg clk=0,reset=1,enabled=1;
    always #5 clk=~clk;
    reg [1:0] floppy_read=0,floppy_write=0;
    reg cd_read=0,hdd_read=0,hdd_write=0;
    reg [11:0] x=0,y=0,width=256,height=96;
    reg [11:0] crop_left=0,crop_top=0,crop_width=0,crop_height=0;
    reg in_ce=0,in_hs=0,in_vs=0,in_de=0;
    reg [7:0] in_r=0,in_g=0,in_b=0;
    wire out_ce,out_hs,out_vs,out_de;
    wire [7:0] out_r,out_g,out_b;
    storage_activity #(.HOLD_FRAMES(3),.ROM_FILE("rtl/assets/activity.mem")) dut(.*);
    reg [7:0] font[0:1023];
    reg [1:0] icons[0:6143];
    initial begin
        $readmemh("rtl/assets/boot-font.mem",font);
        $readmemh("rtl/assets/overlay-icons.mem",icons);
    end
    integer display_mode=-1,checks=0,icons_seen=0,text_seen=0;
    reg [1:0] ce_q=0;
    reg [26:0] pixels_q[0:1];
    reg [23:0] want;
    reg [26:0] held;
    reg [111:0] caption;
    integer px,py,kind,c,bit_index,frame_index,i,ox,oy;
    reg [1:0] pixel;
    function automatic [23:0] color(input integer k,input [1:0] p);
        case (k)
            0: case(p) 1:color=24'ha0a0a8;2:color=24'h1c50ff;default:color=24'hf4f4ff;endcase
            1: case(p) 1:color=24'hb894d8;2:color=24'h40e0a0;default:color=24'he8e4f4;endcase
            default: case(p) 1:color=24'h505058;2:color=24'hc0c0c8;default:color=24'h40ff40;endcase
        endcase
    endfunction
    always @(posedge clk) begin
        if(reset) ce_q=0;
        else begin
            held={out_r,out_g,out_b,out_hs,out_vs,out_de};
            want={in_r,in_g,in_b};
            ox=(crop_width ? crop_left+crop_width : width)-152;
            oy=(crop_height ? crop_top+crop_height : height)-52;
            px=x-ox; py=y-oy;
            case(display_mode)
                0:caption="LOADING D0... ";1:caption="LOADING D1... ";
                2:caption="WRITING D0... ";3:caption="WRITING D1... ";
                4:caption="READING CD... ";5:caption="READING HDD...";
                default:caption="WRITING HDD...";
            endcase
            kind=display_mode<4 ? 0 : display_mode==4 ? 1 : 2;
            if(display_mode>=0 && in_de && enabled) begin
                if(px>=0 && px<32 && py>=0 && py<32) begin
                    frame_index=dut.animation[3:2]*2;
                    pixel=icons[kind*2048+frame_index*256+(py/2)*16+px/2];
                    if(pixel) begin want=color(kind,pixel); if(in_ce) icons_seen=icons_seen+1; end
                end
                if(px>=36 && px<148 && py>=12 && py<20) begin
                    c=caption[111-((px-36)/8)*8 -:8];
                    bit_index=7-(px-36)%8;
                    if(font[c*8+py-12][bit_index]) begin want=24'he8e8ff; if(in_ce) text_seen=text_seen+1; end
                end
            end
            for(i=1;i>0;i=i-1) pixels_q[i]=pixels_q[i-1];
            pixels_q[0]={want,in_hs,in_vs,in_de};
            ce_q={ce_q[0],in_ce};
            #1;
            if(out_ce!==ce_q[1]) $fatal(1,"activity CE latency");
            if(out_ce) begin
                checks=checks+1;
                if({out_r,out_g,out_b,out_hs,out_vs,out_de}!==pixels_q[1])
                    $fatal(1,"activity pixel/sync mode=%0d x=%0d y=%0d want=%h got=%h",display_mode,x,y,pixels_q[1],{out_r,out_g,out_b,out_hs,out_vs,out_de});
            end else if({out_r,out_g,out_b,out_hs,out_vs,out_de}!==held)
                $fatal(1,"activity output changed without CE");
        end
    end
    task frame(input integer mode, input bit gaps);
        integer xx,yy;
        begin
            @(negedge clk); in_ce=1; in_de=0; in_vs=1;
            repeat(4) @(negedge clk);
            in_vs=0;display_mode=mode;
            if(mode>=0 && dut.active!==mode) $fatal(1,"wrong activity selection %0d/%0d",mode,dut.active);
            for(yy=0;yy<height+2;yy=yy+1) for(xx=0;xx<width+4;xx=xx+1) begin
                @(negedge clk);
                x=xx;y=yy;in_ce=1;in_de=xx<width && yy<height;in_hs=xx==width+1;
                {in_r,in_g,in_b}={8'(xx),8'(yy),8'(xx^yy)};
                if(gaps && ((xx*7+yy*13)%11==0)) begin
                    @(negedge clk);in_ce=0;
                    repeat((xx+yy)%3) @(negedge clk);
                end
            end
            @(negedge clk); in_de=0;in_ce=0;repeat(4) @(negedge clk);
        end
    endtask
    task request(input integer mode);
        begin
            floppy_read=0;floppy_write=0;cd_read=0;hdd_read=0;hdd_write=0;
            case(mode)
                0:floppy_read=1;1:floppy_read=2;2:floppy_write=1;3:floppy_write=2;
                4:cd_read=1;5:hdd_read=1;6:hdd_write=1;
            endcase
            repeat(5) @(negedge clk);
        end
    endtask
    integer mode,phase;
    initial begin
        repeat(4) @(negedge clk);reset=0;
        frame(-1,0);
        for(mode=0;mode<7;mode=mode+1) begin
            request(mode);
            for(phase=0;phase<16;phase=phase+1) frame(mode,phase[0]);
            request(-1);frame(mode,0);frame(mode,1);frame(mode,0);frame(-1,0);
        end
        // A readback/busy indication must not erase a brief write caption.
        request(2);frame(2,0);
        request(0);frame(2,1);frame(2,0);frame(2,1);frame(0,0);
        // Short writes between frames survive, and win over simultaneous reads.
        request(3);floppy_read=1;cd_read=1;hdd_read=1;
        repeat(5) @(negedge clk);request(-1);frame(3,1);
        frame(3,0);frame(3,1);frame(-1,0);
        // Crop-relative placement leaves the bottom function-key row clear.
        crop_left=32;crop_top=8;crop_width=192;crop_height=80;
        request(0);frame(0,1);frame(0,0);
        enabled=0;repeat(5) @(negedge clk);frame(-1,1);
        enabled=1;request(-1);frame(0,1);frame(0,0);frame(0,1);frame(-1,1);
        // Too-small viewports hide the badge rather than wrapping coordinates.
        crop_width=128;request(0);frame(-1,0);
        if(icons_seen<1000 || text_seen<1000) $fatal(1,"insufficient activity coverage");
        $display("PASS activity: %0d pixel/sync checks, all labels/frames, crop, hold, priority and bursty CE",checks);
        $finish;
    end
    initial begin #120000000;$fatal(1,"activity watchdog");end
endmodule
