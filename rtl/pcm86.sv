// SPDX-License-Identifier: GPL-3.0-or-later
`timescale 1ns/1ps
// Experimental PC-9801-86 playback registers and 32 KB PCM FIFO.
// Register behavior is based on NP2kai pcm86io/pcm86g and the original
// FreeBSD(98)/Linux98 PCM driver; see PCM86.md. ADC recording is unsupported.
module pcm86 #(parameter CLOCK_HZ=20000000) (
    input wire clk, reset,
    input wire [15:0] address,
    input wire read, write,
    input wire [7:0] writedata,
    output reg [7:0] readdata,
    output wire selected,
    output wire irq,
    output wire opna_extended, opna_muted,
    output wire signed [15:0] audio_l, audio_r,
    output reg sample_valid
);
    reg [7:0] control, format;
    reg [1:0] board_control;
    reg [3:0] volume;
    reg mute, irq_pending, write_seen;
    // Last bit 4 written to A468h. Preserve low-FIFO requests on repeated
    // control writes with bit 4 clear (the Policenauts lost-refill fix).
    // Once refilled above the threshold, a bit-4-clear write must clear the
    // stale request even without a preceding bit-4-set write: AVSDRV uses
    // IN A468 / AND AL,EF / OUT A468 both before and after each refill.
    reg ack_bit;
    reg [15:0] threshold, count;
    reg [14:0] rdptr, wrptr;
    reg [7:0] fifo [0:32767];
    reg [7:0] fifo_q;
    reg [31:0] phase;
    reg [18:0] rate8;
    localparam [31:0] PERIOD8 = CLOCK_HZ * 8;
    wire [31:0] next_phase = phase + rate8;
    wire sample_tick = next_phase >= PERIOD8;
    wire decode = (address[15:4]==12'ha46 && !address[0]) || address==16'ha66e;
    assign selected = decode && read;
    wire write_event = decode && write && !write_seen;
    wire reset_fifo = write_event && address==16'ha468 && writedata[3] && !control[3];
    reg [1:0] state;
    localparam IDLE=0, WAIT_RAM=1, TAKE_BYTE=2;
    reg [2:0] bytes_left;
    reg [1:0] byte_index;
    reg [2:0] active_format;
    reg [23:0] sample_bytes;
    reg signed [15:0] sample_l, sample_r;
    wire pop = state==TAKE_BYTE && !reset_fifo && !reset;
    wire push = write_event && address==16'ha46c && (count<32768 || pop) && !reset;
    wire [15:0] next_count = count + (push ? 16'd1 : 16'd0) - (pop ? 16'd1 : 16'd0);
    wire stereo = format[5:4]==3;
    wire [2:0] frame_bytes = format[6] ? (stereo ? 3'd2 : 3'd1) : (stereo ? 3'd4 : 3'd2);
    assign irq = irq_pending && control[5];
    assign opna_extended=board_control[0];
    assign opna_muted=board_control[1];
    // Linear volume approximation; analog mixer/recording paths are not modeled.
    wire signed [20:0] scaled_l = sample_l * $signed({1'b0,volume});
    wire signed [20:0] scaled_r = sample_r * $signed({1'b0,volume});
    assign audio_l = mute ? 16'sd0 : volume==15 ? sample_l : scaled_l >>> 4;
    assign audio_r = mute ? 16'sd0 : volume==15 ? sample_r : scaled_r >>> 4;

    always @* begin
        case(control[2:0])
            0:rate8=352800; 1:rate8=264600; 2:rate8=176400; 3:rate8=132300;
            4:rate8=88200; 5:rate8=66150; 6:rate8=44100; 7:rate8=33075;
        endcase
        readdata=0;
        case(address)
            16'ha460:readdata={6'b010000,board_control};
            16'ha466:readdata={count==32768,count<frame_bytes,5'b0,phase >= PERIOD8/2};
            16'ha468:readdata={control[7:5],irq_pending,control[3:0]};
            16'ha46a:readdata=format;
            16'ha66e:readdata={7'b0,mute};
            default:;
        endcase
    end

    // Separate synchronous RAM ports permit inferred FPGA block memory.
    always @(posedge clk) begin
        if(push) fifo[wrptr] <= writedata;
        fifo_q <= fifo[rdptr];
    end
    always @(posedge clk) begin
        if(reset) begin
            control<=0; format<=8'h32; board_control<=0; volume<=0; mute<=0;
            irq_pending<=0; write_seen<=0; threshold<=128; ack_bit<=0;
            count<=0; rdptr<=0; wrptr<=0; phase<=0;
            state<=IDLE; bytes_left<=0; byte_index<=0; active_format<=0;
            sample_bytes<=0; sample_l<=0; sample_r<=0; sample_valid<=0;
        end else begin
            write_seen<=decode && write;
            sample_valid<=0;
            phase<=sample_tick ? next_phase-PERIOD8 : next_phase;
            count<=next_count;
            if(push) wrptr<=wrptr+1'b1;
            if(pop) rdptr<=rdptr+1'b1;
            if(sample_tick && control[7] && !control[6] && control[5] && count<=threshold)
                irq_pending<=1;
            case(state)
                IDLE: if(sample_tick && control[7] && !control[6] &&
                         format[5:4]!=0 && count>=frame_bytes && !control[3]) begin
                    active_format<=format[6:4];
                    bytes_left<=frame_bytes;
                    byte_index<=0;
                    state<=WAIT_RAM;
                end
                WAIT_RAM:state<=TAKE_BYTE;
                TAKE_BYTE: begin
                    bytes_left<=bytes_left-1'b1;
                    byte_index<=byte_index+1'b1;
                    case(byte_index)
                        0:sample_bytes[23:16]<=fifo_q;
                        1:sample_bytes[15:8]<=fifo_q;
                        2:sample_bytes[7:0]<=fifo_q;
                    endcase
                    state<=WAIT_RAM;
                    if(bytes_left==1) begin
                        state<=IDLE;
                        sample_valid<=1;
                        case(active_format)
                            3'b101:begin sample_l<=0; sample_r<={fifo_q,8'b0}; end
                            3'b110:begin sample_l<={fifo_q,8'b0}; sample_r<=0; end
                            3'b111:begin sample_l<={sample_bytes[23:16],8'b0}; sample_r<={fifo_q,8'b0}; end
                            3'b001:begin sample_l<=0; sample_r<={sample_bytes[23:16],fifo_q}; end
                            3'b010:begin sample_l<={sample_bytes[23:16],fifo_q}; sample_r<=0; end
                            3'b011:begin sample_l<=sample_bytes[23:8]; sample_r<={sample_bytes[7:0],fifo_q}; end
                            default:;
                        endcase
                        if(control[5] && next_count<=threshold) irq_pending<=1;
                    end
                end
                default:state<=IDLE;
            endcase
            if(write_event) case(address)
                16'ha460:board_control<=writedata[1:0];
                16'ha466:if(writedata[7:5]==3'b101) volume<=~writedata[3:0];
                16'ha468:begin
                    control<=writedata & 8'hef;
                    if(writedata[2:0]!=control[2:0]) phase<=0;
                    if(!writedata[4] && (ack_bit || next_count>threshold)) irq_pending<=0;
                    ack_bit<=writedata[4];
                end
                16'ha46a:if(control[5]) threshold<=writedata==255 ? 16'h7ffc : ({8'b0,writedata}+16'd1)<<7;
                    else format<=writedata;
                16'ha66e:mute<=writedata[0];
                default:;
            endcase
            if(reset_fifo) begin
                count<=0; rdptr<=0; wrptr<=0; state<=IDLE;
                sample_l<=0; sample_r<=0; sample_valid<=0; irq_pending<=0;
            end
        end
    end
endmodule
