//============================================================================
//  Zet/98
//
//  Port to MiSTer
//  Copyright (C) 2017,2020 Alexey Melnikov
//  Copyright (C) 2021 Puu
//
//  This program is free software; you can redistribute it and/or modify it
//  under the terms of the GNU General Public License as published by the Free
//  Software Foundation; either version 2 of the License, or (at your option)
//  any later version.
//
//  This program is distributed in the hope that it will be useful, but WITHOUT
//  ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or
//  FITNESS FOR A PARTICULAR PURPOSE.  See the GNU General Public License for
//  more details.
//
//  You should have received a copy of the GNU General Public License along
//  with this program; if not, write to the Free Software Foundation, Inc.,
//  51 Franklin Street, Fifth Floor, Boston, MA 02110-1301 USA.
//============================================================================

module emu
(
	//Master input clock
	input         CLK_50M,

	//Async reset from top-level module.
	//Can be used as initial reset.
	input         RESET,

	//Must be passed to hps_io module
	inout  [48:0] HPS_BUS,

	//Base video clock. Usually equals to CLK_SYS.
	output        CLK_VIDEO,

	//Multiple resolutions are supported using different CE_PIXEL rates.
	//Must be based on CLK_VIDEO
	output        CE_PIXEL,

	//Video aspect ratio for HDMI. Most retro systems have ratio 4:3.
	output  [7:0] VIDEO_ARX,
	output  [7:0] VIDEO_ARY,

	output  [7:0] VGA_R,
	output  [7:0] VGA_G,
	output  [7:0] VGA_B,
	output        VGA_HS,
	output        VGA_VS,
	output        VGA_DE,    // = ~(VBlank | HBlank)
	output        VGA_F1,
	output [1:0]  VGA_SL,
	output        VGA_SCALER, // Force VGA scaler

	input  [11:0] HDMI_WIDTH,
	input  [11:0] HDMI_HEIGHT,
	output        HDMI_FREEZE,

	output        LED_USER,  // 1 - ON, 0 - OFF.

	// b[1]: 0 - LED status is system status OR'd with b[0]
	//       1 - LED status is controled solely by b[0]
	// hint: supply 2'b00 to let the system control the LED.
	output  [1:0] LED_POWER,
	output  [1:0] LED_DISK,

	// I/O board button press simulation (active high)
	// b[1]: user button
	// b[0]: osd button
	output  [1:0] BUTTONS,

	input         CLK_AUDIO, // 24.576 MHz
	output [15:0] AUDIO_L,
	output [15:0] AUDIO_R,
	output        AUDIO_S, // 1 - signed audio samples, 0 - unsigned
	output  [1:0] AUDIO_MIX, // 0 - no mix, 1 - 25%, 2 - 50%, 3 - 100% (mono)

	//ADC
	inout   [3:0] ADC_BUS,

	//SD-SPI
	output        SD_SCK,
	output        SD_MOSI,
	input         SD_MISO,
	output        SD_CS,
	input         SD_CD,

	//High latency DDR3 RAM interface
	//Use for non-critical time purposes
	output        DDRAM_CLK,
	input         DDRAM_BUSY,
	output  [7:0] DDRAM_BURSTCNT,
	output [28:0] DDRAM_ADDR,
	input  [63:0] DDRAM_DOUT,
	input         DDRAM_DOUT_READY,
	output        DDRAM_RD,
	output [63:0] DDRAM_DIN,
	output  [7:0] DDRAM_BE,
	output        DDRAM_WE,

	//SDRAM interface with lower latency
	output        SDRAM_CLK,
	output        SDRAM_CKE,
	output [12:0] SDRAM_A,
	output  [1:0] SDRAM_BA,
	inout  [15:0] SDRAM_DQ,
	output        SDRAM_DQML,
	output        SDRAM_DQMH,
	output        SDRAM_nCS,
	output        SDRAM_nCAS,
	output        SDRAM_nRAS,
	output        SDRAM_nWE,

	input         UART_CTS,
	output        UART_RTS,
	input         UART_RXD,
	output        UART_TXD,
	output        UART_DTR,
	input         UART_DSR,

	// Open-drain User port.
	// 0 - D+/RX
	// 1 - D-/TX
	// 2..6 - USR2..USR6
	// Set USER_OUT to 1 to read from USER_IN.
	input   [6:0] USER_IN,
	output  [6:0] USER_OUT,

	input         OSD_STATUS
);

assign ADC_BUS  = 'Z;
assign USER_OUT  = '1;

assign AUDIO_MIX = 0;
assign VGA_SL    = 0;
assign VGA_F1    = 0;
assign VGA_SCALER = 0;
assign HDMI_FREEZE = 0;
assign {UART_RTS, UART_TXD, UART_DTR} = 0;
assign DDRAM_CLK = clk_sys;

assign LED_USER  = ioctl_download & ~ldr_done;
assign LED_DISK  = {disk_led, sd_act};
assign LED_POWER = 0;
assign BUTTONS   = 0;
 
// MiSTer treats a zero ratio as full-screen scaling. Keep bit 1's existing
// 4:3/16:9 meanings so saved settings remain compatible.
assign VIDEO_ARX = status[2] ? 8'd0 : (status[1] ? 8'd16 : 8'd4);
assign VIDEO_ARY = status[2] ? 8'd0 : (status[1] ? 8'd9  : 8'd3);

`include "build_id.v" 
parameter CONF_STR = {
	"Zet98;;",
	"-;",
	"O12,Aspect ratio,4:3,16:9,Full Screen;",
	"O3,Video test,Off,Color bars;",
	"O4,Startup mute,10s,Off;",
	"O5,Floppy icon,On,Off;",
	"-;",
	"R6,Reset;",
	"-;",
	"S0,D88,FDD0;",
	"S1,D88,FDD1;",
	"S2,HDF,SASI;",
	"S3,RAM,NVRAM;",
	"-;",
	"R7,SYNC FD0;",
	"R8,SYNC FD1;",
	"-;",
	"R9,EJECT FD0;",
	"RA,EJECT FD1;",
	"-;",
	"RB,LOAD SRAM;",
	"RC,STORE SRAM;",
	"-;",
	"OD,DIP1-8 HGC,Extend,Normal;",
	"OE,DIP1-3 Display,Plasma,Normal;",
	"OF,DIP2-1 NOP,0,1;",
	"OG,DIP2-2 Basic mode,Terminal,Basic;",
	"OH,DIP2-3 Cols,80,40;",
	"OI,DIP2-4 Lines,25,20;",
	"OJ,DIP2-5 Memory SW,Keep,Clear;",
	"OK,DIP2-6 Int.HDD,Disconnect,Connect;",
	"OL,DIP2-7 FDD Motor,Control,ON;",
	"OM,DIP2-8 GDC clock,5MHz,2.5MHz;",
	"J,Fire 1,Fire 2;",
	"V,v",`BUILD_DATE
};

/////////////////  CLOCKS  ////////////////////////

wire clk_ram, clk_sys, clk_vid;
wire pll_locked;

// Compile-time experiment: keep wall-clock peripheral rates consistent with
// the PLL setting. The default remains the original 20 MHz Zet baseline.
`ifdef ZET98_TURBO40
localparam integer SYS_CLK_KHZ = 40000;
`else
localparam integer SYS_CLK_KHZ = 20000;
`endif
`ifdef ZET98_AO486
localparam integer CPU486_ENABLED = 1;
`else
localparam integer CPU486_ENABLED = 0;
`endif

pll pll
(
	.refclk(CLK_50M),
	.rst(0),
	.outclk_0(clk_ram),
	.outclk_1(clk_sys),
	.outclk_2(clk_vid),
	.locked(pll_locked)
);

altddio_out
#(
	.extend_oe_disable("OFF"),
	.intended_device_family("Cyclone V"),
	.invert_output("OFF"),
	.lpm_hint("UNUSED"),
	.lpm_type("altddio_out"),
	.oe_reg("UNREGISTERED"),
	.power_up_high("OFF"),
	.width(1)
)
sdramclk_ddr
(
	.datain_h(1'b0),
	.datain_l(1'b1),
	.outclock(clk_ram),
	.dataout(SDRAM_CLK),
	.aclr(1'b0),
	.aset(1'b0),
	.oe(1'b1),
	.outclocken(1'b1),
	.sclr(1'b0),
	.sset(1'b0)
);

/////////////////  HPS  ///////////////////////////

wire [31:0] status;
wire  [1:0] buttons;

wire [15:0] joystick_0, joystick_1;

wire  [5:0] joyA = ~{joystick_0[5:4],joystick_0[0],joystick_0[1],joystick_0[2],joystick_0[3]};
wire  [5:0] joyB = ~{joystick_1[5:4],joystick_1[0],joystick_1[1],joystick_1[2],joystick_1[3]};

wire        ioctl_download;
wire  [7:0] ioctl_index;
wire        ioctl_wr;
wire [24:0] ioctl_addr;
wire  [7:0] ioctl_dout;

wire        ps2_kbd_clk_out;
wire        ps2_kbd_data_out;
wire        ps2_kbd_clk_in;
wire        ps2_kbd_data_in;
wire        ps2_mouse_clk_out;
wire        ps2_mouse_data_out;
wire        ps2_mouse_clk_in;
wire        ps2_mouse_data_in;

wire  [31:0] sd_lba;
wire   [3:0] sd_rd;
wire   [3:0] sd_wr;

wire  [3:0] sd_ack;
wire  [8:0] sd_buff_addr;
wire  [7:0] sd_buff_dout;
wire  [7:0] sd_buff_din;
wire [31:0] sd_slot_lba [4];
wire  [5:0] sd_slot_blk_cnt [4];
wire  [7:0] sd_slot_buff_din [4];
genvar slot;
generate
for (slot = 0; slot < 4; slot = slot + 1) begin : disk_slots
	assign sd_slot_lba[slot] = sd_lba;
	assign sd_slot_blk_cnt[slot] = 6'd0; // One 512-byte block per diskemu request.
	assign sd_slot_buff_din[slot] = sd_buff_din;
end
endgenerate
wire        sd_buff_wr;
wire [15:0] sd_req_type = 0;
wire  [3:0] img_mounted;
wire        img_readonly;
wire [63:0] img_size;

wire [65:0] ps2_key;
wire [64:0] sysrtc;

hps_io #(.CONF_STR(CONF_STR), .PS2DIV(2400 * (SYS_CLK_KHZ / 20000)), .PS2WE(1), .VDNUM(4)) hps_io
(
	.clk_sys(clk_sys),
	.HPS_BUS(HPS_BUS),
	
	.buttons(buttons),
	.status(status),
	
	.TIMESTAMP(TIMESTAMP),

	.sd_lba(sd_slot_lba),
	.sd_blk_cnt(sd_slot_blk_cnt),
	.sd_rd(sd_rd),
	.sd_wr(sd_wr),
	.sd_ack(sd_ack),
	.sd_buff_addr(sd_buff_addr),
	.sd_buff_dout(sd_buff_dout),
	.sd_buff_din(sd_slot_buff_din),
	.sd_buff_wr(sd_buff_wr),

	.img_mounted(img_mounted),
	.img_readonly(img_readonly),
	.img_size(img_size),

	.ioctl_download(ioctl_download),
	.ioctl_index(ioctl_index),
	.ioctl_wr(ioctl_wr),
	.ioctl_addr(ioctl_addr),
	.ioctl_dout(ioctl_dout),
	.ioctl_wait(ldr_wr),

	.ps2_kbd_clk_out(ps2_kbd_clk_out),
	.ps2_kbd_data_out(ps2_kbd_data_out),
	.ps2_kbd_clk_in(ps2_kbd_clk_in),
	.ps2_kbd_data_in(ps2_kbd_data_in),
	.ps2_mouse_clk_out(ps2_mouse_clk_out),
	.ps2_mouse_data_out(ps2_mouse_data_out),
	.ps2_mouse_clk_in(ps2_mouse_clk_in),
	.ps2_mouse_data_in(ps2_mouse_data_in),

	.ps2_key(ps2_key),
	
	.RTC(sysrtc),

	.joystick_0(joystick_0),
	.joystick_1(joystick_1)
);

/////////////////  RESET  /////////////////////////

reg reset_n = 0;
always @(posedge clk_sys) begin
	reg old_download;
	
	old_download <= ioctl_download;
	if(~old_download & ioctl_download) reset_n <= 1;
end

wire reset = buttons[1] | status[6];
///////////////////////////////////////////////////


wire [1:0] fdsync = status[8:7];
wire [1:0] fdeject = status[10:9];
wire sramld	= status[11];
wire sramst = status[12];
wire [1:0]pdip1 = status[14:13];
wire [7:0]pdip2 = status[22:15];

assign CLK_VIDEO = clk_vid;
assign AUDIO_S = 1;

wire disk_led;
wire floppy_access;
wire native_ce, native_hs, native_vs, native_de;
wire [7:0] native_r, native_g, native_b;
wire output_ce, output_hs, output_vs, output_de;
wire [7:0] output_r, output_g, output_b;

video_output video_out (
	.clk(clk_vid), .reset(!pll_locked), .test_pattern(status[3]),
	.native_ce(native_ce), .native_r(native_r), .native_g(native_g), .native_b(native_b),
	.native_hs(native_hs), .native_vs(native_vs), .native_de(native_de),
	.ce(output_ce), .r(output_r), .g(output_g), .b(output_b),
	.hs(output_hs), .vs(output_vs), .de(output_de)
);
floppy_overlay floppy_icon (
	.clk(clk_vid), .reset(!pll_locked), .enabled(!status[5]),
	.activity(floppy_access | (|sd_rd[1:0]) | (|sd_wr[1:0])),
	.in_ce(output_ce), .in_hs(output_hs), .in_vs(output_vs), .in_de(output_de),
	.in_r(output_r), .in_g(output_g), .in_b(output_b),
	.out_ce(CE_PIXEL), .out_hs(VGA_HS), .out_vs(VGA_VS), .out_de(VGA_DE),
	.out_r(VGA_R), .out_g(VGA_G), .out_b(VGA_B)
);

`ifdef ZET98_EXT_RAM_MB
localparam EXT_RAM_MB = `ZET98_EXT_RAM_MB;
`else
localparam EXT_RAM_MB = 0;
`endif
Zet98MiSTer #(.SYSFREQ(SYS_CLK_KHZ), .CPU486(CPU486_ENABLED), .EXT_RAM_MB(EXT_RAM_MB)) Zet98_top
(
	.ramclk(clk_ram),
	.cpuclk(clk_sys),
	.vidclk(clk_vid),
	.plllock(pll_locked),
	
	.sysrtc(sysrtc),

	.pMemCke(SDRAM_CKE),
	.pMemCs_n(SDRAM_nCS),
	.pMemRas_n(SDRAM_nRAS),
	.pMemCas_n(SDRAM_nCAS),
	.pMemWe_n(SDRAM_nWE),
	.pMemUdq(SDRAM_DQMH),
	.pMemLdq(SDRAM_DQML),
	.pMemBa1(SDRAM_BA[1]),
	.pMemBa0(SDRAM_BA[0]),
	.pMemAdr(SDRAM_A),
	.pMemDat(SDRAM_DQ),
	.pDdrAddress(DDRAM_ADDR), .pDdrWriteData(DDRAM_DIN),
	.pDdrByteEnable(DDRAM_BE), .pDdrBurstCount(DDRAM_BURSTCNT),
	.pDdrRead(DDRAM_RD), .pDdrWrite(DDRAM_WE), .pDdrBusy(DDRAM_BUSY),
	.pDdrReadValid(DDRAM_DOUT_READY), .pDdrReadData(DDRAM_DOUT),

	.LDR_ADDR(ioctl_addr[19:0]),
	.LDR_WDAT(ioctl_dout),
	.LDR_OE(ioctl_download & ~ldr_done),
	.LDR_WR(ldr_wr),
	.LDR_ACK(ldr_ack),
	.LDR_DONE(ldr_done),

	.pPs2Clkin(ps2_kbd_clk_out),
	.pPs2Clkout(ps2_kbd_clk_in),
	.pPs2Datin(ps2_kbd_data_out),
	.pPs2Datout(ps2_kbd_data_in),

	.pPmsClkin(ps2_mouse_clk_out),
	.pPmsClkout(ps2_mouse_clk_in),
	.pPmsDatin(ps2_mouse_data_out),
	.pPmsDatout(ps2_mouse_data_in),

	.pJoyA(joyA),
	.pJoyB(joyB),

	.pFDSYNC(fdsync),
	.pFDEJECT(fdeject),

	.mist_mounted(img_mounted),
	.mist_readonly({4{img_readonly}}),
	.mist_imgsize(img_size),

	.mist_lba(sd_lba),
	.mist_rd(sd_rd),
	.mist_wr(sd_wr),
	// diskemu serializes all four image slots onto one buffer/acknowledgement.
	// hps_io returns a one-hot ACK: narrowing it to one bit loses slots 1..3.
	.mist_ack(|sd_ack),

	.mist_buffaddr(sd_buff_addr),
	.mist_buffdout(sd_buff_dout),
	.mist_buffdin(sd_buff_din),
	.mist_buffwr(sd_buff_wr),

	.pLed(disk_led),
	.pFloppyAccess(floppy_access),
	.pDip1(pdip1),
	.pDip2(pdip2),
	.pSramld(sramld),
	.pSramst(sramst),

	.pVideoR(native_r),
	.pVideoG(native_g),
	.pVideoB(native_b),
	.pVideoHS(native_hs),
	.pVideoVS(native_vs),
	.pVideoEN(native_de),
	.pVideoClk(native_ce),

	.pSndL(AUDIO_L),
	.pSndR(AUDIO_R),
	.pStartupBeeps(status[4]),

	.rstn(reset_n & ~reset)
);

wire ldr_ack;
reg ldr_wr = 0;
reg ldr_done = 0;
always @(posedge clk_sys) begin
	reg old_ack, old_download;

	old_download <= ioctl_download;
	old_ack <= ldr_ack;

	if(~old_ack & ldr_ack & ldr_wr) ldr_wr <= 0;
	if(ioctl_wr & ~ldr_done) ldr_wr <= 1;

	if(old_download & ~ioctl_download) ldr_done <= 1;
end


//////////////////   SD LED   ///////////////////
reg sd_act;

always @(posedge clk_sys) begin
	reg old_mosi, old_miso;
	integer timeout = 0;

	old_mosi <= SD_MOSI;
	old_miso <= SD_MISO;

	sd_act <= 0;
	if(timeout < 1000000) begin
		timeout <= timeout + 1;
		sd_act <= 1;
	end

	if((old_mosi ^ SD_MOSI) || (old_miso ^ SD_MISO)) timeout <= 0;
end

endmodule
