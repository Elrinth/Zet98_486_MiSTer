// SPDX-License-Identifier: GPL-3.0-or-later
// PC-9801-86 bus/clock adapter for PC88_MiSTer's JT08 (YM2608).
// The board's separate PCM FIFO/DAC remains in pcm86.sv.
module opna_jt08 #(
    parameter integer SYSFREQ=20000,
    parameter RHYTHM_HEX="../../rtl/vendor/jt08/rhythm.hex"
)(
    input wire clk, rstn,
    input wire [7:0] din,
    input wire [1:0] adr,
    input wire csn, rdn, wrn,
    output reg [7:0] dout,
    output wire doe, waitn, irqn,
    output wire signed [15:0] snd_l,snd_r,
    output wire [15:0] snd_psg,
    input wire [7:0] pain,pbin,
    output wire [7:0] paout,pbout,
    output wire paoe,pboe
);
    localparam integer DEN=SYSFREQ*5;
    reg [$clog2(DEN)-1:0] phase;
    reg cen;
    reg [9:0] reset_ticks;
    wire synth_reset=!rstn || !reset_ticks[9];
    always @(posedge clk) begin
        if(!rstn) begin phase<=0; cen<=0; reset_ticks<=0; end
        else begin
            if(phase>=DEN-39936) begin phase<=phase-(DEN-39936); cen<=1; end
            else begin phase<=phase+39936; cen<=0; end
            if(cen && !reset_ticks[9]) reset_ticks<=reset_ticks+1'b1;
        end
    end

    // Stall only the selected sound IO transaction until it is delivered.
    // Native busy protects operator-register updates even when software uses
    // delays calibrated for a slower CPU. A held CPU strobe becomes one write.
    localparam IDLE=0, PREPARE=1, WRITE=2, READ=3, SETTLE=4, DONE=5;
    reg [2:0] state;
    reg [2:0] delay_count;
    reg [1:0] latched_adr;
    reg [7:0] latched_din;
    reg latched_write;
    wire active=!csn && (!rdn || !wrn);
    wire same_access=adr==latched_adr && (!wrn)==latched_write &&
        (!latched_write || din==latched_din);
    wire synth_busy;
    wire [7:0] synth_dout;
    assign doe=!csn && !rdn;
    assign waitn=!active || (state==DONE && same_access);

    always @(posedge clk) begin
        if(!rstn) begin
            state<=IDLE; delay_count<=0; latched_adr<=0;
            latched_din<=0; latched_write<=0; dout<=0;
        end else begin
            case(state)
                IDLE: if(active) begin
                    latched_adr<=adr; latched_din<=din; latched_write<=!wrn;
                    state<=PREPARE;
                end
                PREPARE: if(!synth_reset) begin
                    if(!latched_write) begin state<=READ; delay_count<=0; end
                    else if(!synth_busy) state<=WRITE;
                end
                WRITE: begin state<=SETTLE; delay_count<=0; end
                READ: begin
                    // JT49 PSG readback and JT08 status are registered.
                    if(delay_count==4) begin dout<=synth_dout; state<=DONE; end
                    else delay_count<=delay_count+1'b1;
                end
                SETTLE: if(delay_count==3) state<=DONE;
                        else delay_count<=delay_count+1'b1;
                DONE: if(!active) state<=IDLE;
                      else if(!same_access) begin
                          latched_adr<=adr; latched_din<=din;
                          latched_write<=!wrn; state<=PREPARE;
                      end
                default: state<=IDLE;
            endcase
        end
    end

    wire [19:0] rhythm_addr;
    wire rhythm_oe_n;
    reg [7:0] rhythm_data;
    (* ramstyle="M10K" *) reg [7:0] rhythm_rom[0:8191];
    initial $readmemh(RHYTHM_HEX,rhythm_rom);
    always @(posedge clk) if(!rhythm_oe_n) rhythm_data<=rhythm_rom[rhythm_addr[12:0]];
    wire [11:0] psg;
    assign snd_psg={1'b0,psg,3'b000};

    jt08 synth(
        .rst(synth_reset),.clk(clk),.cen(cen),.din(latched_din),.addr(latched_adr),
        .cs_n(!(state==WRITE || state==READ)),.wr_n(state!=WRITE),.rd_n(state!=READ),
        .dout(synth_dout),.irq_n(irqn),.busy(synth_busy),
        .IOA_in(pain),.IOB_in(pbin),.IOA_out(paout),.IOB_out(pbout),.IOA_oe(paoe),.IOB_oe(pboe),
        .adpcma_addr(rhythm_addr),.adpcma_roe_n(rhythm_oe_n),.adpcma_data(rhythm_data),
        // A stock PC-9801-86 has no external OPNA ADPCM sample RAM.
        .adpcmb_addr(),.adpcmb_roe_n(),.adpcmb_din(8'd0),.adpcmb_wr_n(),.adpcmb_dout(),
        .psg_A(),.psg_B(),.psg_C(),.psg_snd(psg),
        .fm_snd_right(snd_r),.fm_snd_left(snd_l),.snd_right(),.snd_left(),.snd_sample()
    );
endmodule
