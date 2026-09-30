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

module emu #(parameter NATIVE_IMAGES=1)
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
	output [12:0] VIDEO_ARX,
	output [12:0] VIDEO_ARY,

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
	output [11:0] HDMI_CROP_LEFT, HDMI_CROP_TOP, HDMI_CROP_WIDTH, HDMI_CROP_HEIGHT,
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
	// Linux (MidiLink/FluidSynth) audio gain, applied in sys_top:
	// 0 100%, 1 75%, 2 50%, 3 25%, 4 mute, 5 125%, 6 150%, 7 200%.
	output  [2:0] ALSA_GAIN,

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

assign AUDIO_MIX = 0;
`ifdef ZET98_MPU_UART
assign ALSA_GAIN = status[37:35];
`else
assign ALSA_GAIN = 0;
`endif
assign VGA_SL    = 0;
assign VGA_F1    = 0;
assign VGA_SCALER = 0;
assign HDMI_FREEZE = 0;
assign {UART_RTS, UART_DTR} = 0;
assign DDRAM_CLK = clk_sys;

assign LED_USER  = ioctl_download & ~ldr_done;
assign LED_DISK  = {disk_led, sd_act};
assign LED_POWER = 0;
assign BUTTONS   = 0;
 
// MiSTer treats a zero ratio as full-screen scaling. Keep bit 1's existing
// 4:3/16:9 meanings so saved settings remain compatible.
wire [11:0] aspect_x = status[2] ? 12'd0 : (status[1] ? 12'd16 : 12'd4);
wire [11:0] aspect_y = status[2] ? 12'd0 : (status[1] ? 12'd9 : 12'd3);

`include "build_id.v" 
parameter CONF_STR = {
`ifdef ZET98_Z486_DEBUG
    "PC98;UART115200;",
`elsif ZET98_CD_TRACE
	// Same header as the MIDI build (B193's "PC98;UART115200;" gave no HDMI
	// with this Main); the capture tool sets 115200 itself.
	"PC98;UART31250,MIDI31250;",
`elsif ZET98_MPU_UART
	"PC98;UART31250,MIDI31250;",
`else
	"PC98;;",
`endif
	"-;",
	// Everyday controls first: disk swaps, reset, video; the rest lives in
	// sub-pages. Reset stands apart between separators, never under the
	// cursor when the menu opens.
	"S0,D88HDMFDI,FDD0;",
	"S1,D88HDMFDI,FDD1;",
`ifdef ZET98_RAW_IDE
	"S2,VHDIMGHDIIMA,IDE hard disk;",
	"S4,ISOBINPCD,CD-ROM (ISO/BIN/PCD);",
`else
	"S2,HDF,SASI;",
`endif
	"-;",
	"R6,Reset;",
	"-;",
	"ONP,HDMI scaling,Fit native,Integer fit,Integer zoom,Stretch,CRT 4:3,Custom aspect;",
	"O12,Aspect ratio,4:3,16:9,Full Screen;",
	"-;",
	"P1,Audio & Video;",
	"P1O3,Video test,Off,Color bars;",
	"P1O4,Startup mute,10s,Off;",
	"P1o2,Audio filter,On,Off;",
`ifdef ZET98_MPU_UART
	"P1OQ,MPU MIDI,Off,UART;",
	"P1o35,MIDI volume,100%,75%,50%,25%,Mute,125%,150%,200%;",
`endif
	"P3,Input;",
	"P3o6,SNAC PS pads,On,Off;",
	"P3o7,Right stick mouse,On,Off;",
	"P4,Boot & storage;",
	"P4OR,Empty boot,Wait for disk,Start BIOS;",
	"P4R9,Eject FD0;",
	"P4RA,Eject FD1;",
	"P4S3,RAM,NVRAM;",
	"P4R7,Sync FD0;",
	"P4R8,Sync FD1;",
	"P4RB,Load SRAM;",
	"P4RC,Store SRAM;",
	"P5,DIP switches;",
	"P5OD,DIP1-8 HGC,Extend,Normal;",
	"P5o0,DIP1-3 Display,Normal,Plasma;",
	"P5OF,DIP2-1 NOP,0,1;",
	"P5OG,DIP2-2 Basic mode,Terminal,Basic;",
	"P5OH,DIP2-3 Cols,80,40;",
	"P5OI,DIP2-4 Lines,25,20;",
	"P5OJ,DIP2-5 Memory SW,Keep,Clear;",
	"P5OK,DIP2-6 Int.HDD,Disconnect,Connect;",
	"P5OL,DIP2-7 FDD Motor,Control,ON;",
	"P5o1,DIP2-8 GDC clock,2.5MHz,5MHz;",
	"J,Fire 1,Fire 2,Mouse L,Mouse R;",
	"V,v",`BUILD_DATE
};

/////////////////  CLOCKS  ////////////////////////

wire clk_ram, clk_sys, clk_vid;
wire pll_locked;

// Compile-time experiment: keep wall-clock peripheral rates consistent with
// the PLL setting. The default remains the original 20 MHz Zet baseline.
`ifdef ZET98_TURBO100
localparam integer SYS_CLK_KHZ = 100000;
`elsif ZET98_TURBO90
localparam integer SYS_CLK_KHZ = 90000;
`elsif ZET98_TURBO75
localparam integer SYS_CLK_KHZ = 75000;
`elsif ZET98_TURBO60
localparam integer SYS_CLK_KHZ = 60000;
`elsif ZET98_TURBO50
localparam integer SYS_CLK_KHZ = 50000;
`elsif ZET98_TURBO40
localparam integer SYS_CLK_KHZ = 40000;
`else
localparam integer SYS_CLK_KHZ = 20000;
`endif
`ifdef ZET98_AO486
localparam integer CPU486_ENABLED = 1;
`else
localparam integer CPU486_ENABLED = 0;
`endif
`ifdef ZET98_JT08
localparam integer USE_JT08 = 1;
`else
localparam integer USE_JT08 = 0;
`endif
`ifdef ZET98_PCM86
localparam integer SOUND_MODEL = 3;
`else
localparam integer SOUND_MODEL = 2;
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

wire [63:0] status;

// Band-limit the core mix to 48 kHz on the framework's audio clock so the
// OPNA/PCM86 staircases do not alias (rtl/audio_decimator.sv).
wire [15:0] core_snd_l, core_snd_r;
// CD audio (PCD images) joins the mix at half scale, saturating.
wire signed [15:0] cd_audio_l, cd_audio_r;
wire  [1:0] cd_activity;
wire [91:0] cd_trace;                    // CD trace builds (ZET98_CD_TRACE)
wire native_ce, native_hs, native_vs, native_de;
wire [71:0] video_debug;                 // GDC areas and video mode (trace builds)
reg  [15:0] snd_mix_l, snd_mix_r;
function automatic [15:0] mix_sat(input [15:0] a, input signed [15:0] b);
	reg signed [16:0] sum;
	begin
		sum = $signed({a[15], a}) + (b >>> 1);
		mix_sat = sum[16] != sum[15] ? {sum[16], {15{!sum[16]}}} : sum[15:0];
	end
endfunction
always @(posedge clk_sys) begin
	snd_mix_l <= mix_sat(core_snd_l, cd_audio_l);
	snd_mix_r <= mix_sat(core_snd_r, cd_audio_r);
end
audio_decimator audio_decimator (
	.clk(CLK_AUDIO), .enable(~status[34]),
	.in_l(snd_mix_l), .in_r(snd_mix_r),
	.out_l(AUDIO_L), .out_r(AUDIO_R)
);

wire  [1:0] buttons;

wire [15:0] joystick_0, joystick_1;

// PlayStation pads on the user port (SNAC) add to USB joysticks 1 and 2.
wire  [5:0] snac_joy1, snac_joy2;
wire  [1:0] snac_analog, snac_mbtn1, snac_mbtn2;
wire [15:0] snac_right1, snac_right2;
wire [63:0] snac_raw1;
wire [15:0] joystick_r0, joystick_r1;
snac_psx_pad #(.CLK_HZ(SYS_CLK_KHZ*1000)) snac_pads (
	.clk(clk_sys), .enable(!status[38]), .user_in(USER_IN), .user_out(USER_OUT),
	.joy1(snac_joy1), .joy2(snac_joy2),
	.analog(snac_analog), .right1(snac_right1), .right2(snac_right2),
	.mbtn1(snac_mbtn1), .mbtn2(snac_mbtn2), .raw1(snac_raw1)
);
// Right stick of USB controllers or SNAC DualShocks moves the PC-98 mouse;
// buttons "Mouse L/R" (USB) and L3/L1, R3/R1 (SNAC) click. A USB mouse
// keeps working; both add up.
wire signed [7:0] stick_dx, stick_dy;
wire        stick_stb;
stick_mouse #(.CLK_HZ(SYS_CLK_KHZ*1000)) stick_mouse (
	.clk(clk_sys), .enable(!status[39]),
	.usb_r0(joystick_r0), .usb_r1(joystick_r1),
	.snac_valid(snac_analog), .snac_r0(snac_right1), .snac_r1(snac_right2),
	.dx(stick_dx), .dy(stick_dy), .strobe(stick_stb)
);
wire  [1:0] stick_buttons = status[39] ? 2'b00 :
	(joystick_0[7:6] | joystick_1[7:6] | snac_mbtn1 | snac_mbtn2);
wire  [5:0] joy0_bits = joystick_0[5:0] | snac_joy1;
wire  [5:0] joy1_bits = joystick_1[5:0] | snac_joy2;
wire  [5:0] joyA = ~{joy0_bits[5:4],joy0_bits[0],joy0_bits[1],joy0_bits[2],joy0_bits[3]};
wire  [5:0] joyB = ~{joy1_bits[5:4],joy1_bits[0],joy1_bits[1],joy1_bits[2],joy1_bits[3]};

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
wire   [3:0] legacy_sd_rd, legacy_sd_wr;
wire  [31:0] ide_lba;
wire         ide_rd, ide_wr;
wire   [7:0] ide_buff_din;
wire  [15:0] ide_address, ide_writedata, ide_readdata;
wire   [1:0] ide_select;
wire         ide_read, ide_write, ide_oe, ide_irq, ide_resetn;
`ifdef ZET98_RAW_IDE
localparam RAW_IDE=1;
`else
localparam RAW_IDE=0;
`endif
assign sd_rd = RAW_IDE ? {legacy_sd_rd[3],ide_rd,legacy_sd_rd[1:0]} : legacy_sd_rd;
assign sd_wr = RAW_IDE ? {legacy_sd_wr[3],ide_wr,legacy_sd_wr[1:0]} : legacy_sd_wr;

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
	assign sd_slot_lba[slot] = RAW_IDE && slot==2 ? ide_lba : sd_lba;
	assign sd_slot_blk_cnt[slot] = 6'd0; // One 512-byte block per diskemu request.
	assign sd_slot_buff_din[slot] = RAW_IDE && slot==2 ? ide_buff_din : sd_buff_din;
end
endgenerate
wire        sd_buff_wr;
wire [15:0] sd_req_type = 0;
wire  [3:0] img_mounted;
wire        img_readonly;
wire [63:0] img_size;
wire [3:0] core_img_mounted, core_sd_ack, core_buff_wr;
wire core_img_readonly;
wire [63:0] core_img_size;
wire [8:0] core_buff_addr[4];
wire [7:0] core_buff_dout[4];
wire [31:0] host_slot_lba[4];
wire [7:0] host_slot_buff_din[4];
wire [3:0] host_rd,host_wr;
wire [2:0] invalid_image;
wire [17:0] hdi_info;
pc98_image_bridge #(.ENABLE(NATIVE_IMAGES),.RAW_IDE(RAW_IDE)) images (
    .clk(clk_sys),.image_mounted(img_mounted),.image_readonly(img_readonly),.image_size(img_size),
    .core_mounted(core_img_mounted),.core_readonly(core_img_readonly),.core_size(core_img_size),
    .disk_lba(sd_slot_lba),.disk_rd(sd_rd),.disk_wr(sd_wr),.disk_buff_din(sd_slot_buff_din),
    .disk_ack(core_sd_ack),.disk_buff_wr(core_buff_wr),.disk_buff_addr(core_buff_addr),.disk_buff_dout(core_buff_dout),
    .host_lba(host_slot_lba),.host_rd(host_rd),.host_wr(host_wr),.host_buff_din(host_slot_buff_din),
    .host_ack(sd_ack),.host_buff_wr(sd_buff_wr),.host_buff_addr(sd_buff_addr),.host_buff_dout(sd_buff_dout),
    .invalid(invalid_image),.hdi_info(hdi_info)
);
wire [1:0] legacy_buffer_slot = core_sd_ack[0] ? 0 : core_sd_ack[1] ? 1 : core_sd_ack[3] ? 3 : 2;

// Slot 4 is the ATAPI CD-ROM image (read-only), connected directly.
wire [31:0] cd_lba;
wire        cd_rd;
wire [31:0] hps_lba [5];
wire  [5:0] hps_blk_cnt [5];
wire  [7:0] hps_buff_din [5];
wire  [4:0] hps_ack, hps_mounted;
genvar hslot;
generate for (hslot = 0; hslot < 4; hslot = hslot + 1) begin : hps_slots
	assign hps_lba[hslot] = host_slot_lba[hslot];
	assign hps_buff_din[hslot] = host_slot_buff_din[hslot];
	assign hps_blk_cnt[hslot] = sd_slot_blk_cnt[hslot];
end endgenerate
assign hps_lba[4] = cd_lba;
assign hps_buff_din[4] = 8'h00;
wire  [5:0] cd_blk_cnt;
assign hps_blk_cnt[4] = cd_blk_cnt;
assign sd_ack = hps_ack[3:0];
assign img_mounted = hps_mounted[3:0];

generate if(RAW_IDE) begin : raw_ide
	pc98_ide #(.CLK_HZ(SYS_CLK_KHZ*1000)) controller (
		.clk(clk_sys), .reset(!ide_resetn),
		.io_address(ide_address), .io_writedata(ide_writedata), .io_select(ide_select),
		.io_read(ide_read), .io_write(ide_write), .io_readdata(ide_readdata),
		.io_oe(ide_oe), .irq(ide_irq),
		.image_mounted(core_img_mounted[2]), .image_readonly(core_img_readonly), .image_size(core_img_size),
		.hdi_info(hdi_info),
		.sd_lba(ide_lba), .sd_rd(ide_rd), .sd_wr(ide_wr), .sd_ack(core_sd_ack[2]),
		.sd_buff_addr(core_buff_addr[2]), .sd_buff_dout(core_buff_dout[2]),
		.sd_buff_din(ide_buff_din), .sd_buff_wr(core_buff_wr[2]),
		.cd_mounted(hps_mounted[4]), .cd_size(img_size),
		.cd_lba(cd_lba), .cd_rd(cd_rd), .cd_blk_cnt(cd_blk_cnt), .cd_ack(hps_ack[4]),
		.cd_buff_addr(sd_buff_addr), .cd_buff_dout(sd_buff_dout), .cd_buff_wr(sd_buff_wr),
		.cd_audio_l(cd_audio_l), .cd_audio_r(cd_audio_r), .cd_activity(cd_activity),
		.cd_trace(cd_trace)
	);
end else begin : no_raw_ide
	assign cd_trace=0;
	assign {ide_lba,ide_rd,ide_wr,ide_buff_din,ide_oe,ide_irq}=0;
	assign {cd_lba,cd_rd,cd_blk_cnt}=0;
	assign {cd_audio_l,cd_audio_r,cd_activity}=0;
	assign ide_readdata=16'hffff;
end endgenerate

// ARTIC 307.2 kHz counter at 5Ch-5Fh (NEC's CD-ROM driver times with it).
wire [15:0] artic_readdata;
wire artic_oe;
pc98_artic #(.CLK_HZ(SYS_CLK_KHZ*1000)) artic (
	.clk(clk_sys), .io_address(ide_address), .io_read(ide_read),
	.io_readdata(artic_readdata), .io_oe(artic_oe)
);

// MPU-PC98II uses even low-byte ports E0D0/E0D2 and the otherwise unused
// master PIC IRQ6. Reuse the exported CPU I/O request, not IDE's decode.
wire [7:0] mpu_readdata;
wire mpu_oe, mpu_irq;
wire [127:0] cpu_debug_snapshot;
`ifdef ZET98_MPU_UART
pc98_mpu_uart #(.CLOCK_HZ(SYS_CLK_KHZ*1000), .RESET_PANIC(1)) mpu (
    .clk(clk_sys), .reset(!ide_resetn), .enable(status[26]),
    .io_address(ide_address), .io_writedata(ide_writedata), .io_select(ide_select),
    .io_read(ide_read), .io_write(ide_write), .io_readdata(mpu_readdata),
    .io_oe(mpu_oe), .irq(mpu_irq), .midi_rx(UART_RXD), .midi_tx(UART_TXD),
    .rx_overrun(), .rx_framing_error(), .tx_overrun()
);
`else
assign mpu_readdata=8'hff;
assign {mpu_oe,mpu_irq}=0;
`ifdef ZET98_Z486_DEBUG
// Debug builds: the z486 crash recorder's UART rides bit 0 of the snapshot.
assign UART_TXD = cpu_debug_snapshot[0];
`elsif ZET98_CD_TRACE
// CD trace builds: CD-ROM command/audio events as text at 115200 baud.
// Graphics GDC display areas as the game programs them, snooped from its
// port writes (A2h command, A0h parameter): PRAM bytes 0-7 (area 1/2 start
// address and line count) and the PITCH parameter, logged as "G pp s7..s0".
reg [7:0] gdc_pram [0:7];
reg [7:0] gdc_pitch = 0;
reg [3:0] gdc_ptr = 0;
reg gdc_mode_pram = 0, gdc_mode_pitch = 0, gdc_wr_d = 0;
wire gdc_wr = ide_write && ide_select[0] && (ide_address == 16'h00a0 || ide_address == 16'h00a2);
always @(posedge clk_sys) begin
	gdc_wr_d <= gdc_wr;
	if (gdc_wr && !gdc_wr_d) begin
		if (ide_address == 16'h00a2) begin
			gdc_mode_pram <= ide_writedata[7:4] == 4'h7;
			gdc_mode_pitch <= ide_writedata[7:0] == 8'h47;
			gdc_ptr <= ide_writedata[3:0];
		end else if (gdc_mode_pram) begin
			if (gdc_ptr < 8) gdc_pram[gdc_ptr[2:0]] <= ide_writedata[7:0];
			gdc_ptr <= gdc_ptr + 1'b1;
		end else if (gdc_mode_pitch) begin
			gdc_pitch <= ide_writedata[7:0]; gdc_mode_pitch <= 0;
		end
	end
end
// PC-9801-86 PCM port writes (A466h-A46Ch), one strobe per CPU write.
reg pcm_wr_d = 0;
wire pcm_wr = ide_write && ide_select[0] && ide_address[15:4] == 12'ha46 &&
              (ide_address[3:0] == 4'h6 || ide_address[3:0] == 4'h8 ||
               ide_address[3:0] == 4'ha || ide_address[3:0] == 4'hc);
always @(posedge clk_sys) pcm_wr_d <= pcm_wr;
wire pcm_ctl_stb = pcm_wr && !pcm_wr_d && ide_address[3:0] != 4'hc;
wire pcm_push_stb = pcm_wr && !pcm_wr_d && ide_address[3:0] == 4'hc;
// Graphics register writes: EGC 4A0h-4AEh (words), GRCG 7Ch/7Eh, 6Ah, A4h, A6h.
reg gfx_wr_d = 0;
wire gfx_egc = ide_address[15:4] == 12'h04a;
wire gfx_hit = ide_write && (gfx_egc || ide_address == 16'h007c || ide_address == 16'h007e ||
               ide_address == 16'h006a || ide_address == 16'h00a4 || ide_address == 16'h00a6);
always @(posedge clk_sys) gfx_wr_d <= gfx_hit;
wire gfx_wr_stb = gfx_hit && !gfx_wr_d;
wire [3:0] gfx_reg = gfx_egc ? {1'b0, ide_address[3:1]} :
                     ide_address == 16'h007c ? 4'h8 : ide_address == 16'h007e ? 4'h9 :
                     ide_address == 16'h006a ? 4'ha : ide_address == 16'h00a4 ? 4'hb : 4'hc;
wire [15:0] gfx_data = gfx_egc ? {ide_select[1] ? ide_writedata[15:8] : 8'h00,
                                  ide_select[0] ? ide_writedata[7:0] : 8'h00} : {8'h00, ide_writedata[7:0]};
// Per-frame display state (V events): at each vertical sync, the pages and
// when the game last wrote the display page (A4h) and started a PRAM write.
reg [2:0] vs_sync = 0;
always @(posedge clk_sys) vs_sync <= {vs_sync[1:0], native_vs};
wire frame_tick = vs_sync[1] && !vs_sync[2];
reg [9:0] vdiv = 0;
reg [15:0] since_vs = 0, a4_time = 16'hffff, pram_time = 16'hffff;
reg [7:0] frame_no = 0;
reg a4_val = 0, a6_val = 0, frame_ev = 0;
reg [71:0] frame_data = 0;
reg page_wr_d = 0;
wire page_wr = ide_write && ide_select[0] && (ide_address == 16'h00a4 || ide_address == 16'h00a6);
always @(posedge clk_sys) begin
	frame_ev <= 0;
	page_wr_d <= page_wr;
	vdiv <= vdiv + 1'b1;
	if (vdiv == 10'h3ff && since_vs != 16'hfffe) since_vs <= since_vs + 1'b1;
	if (page_wr && !page_wr_d) begin
		if (ide_address == 16'h00a4) begin a4_val <= ide_writedata[0]; a4_time <= since_vs; end
		else a6_val <= ide_writedata[0];
	end
	if (gdc_wr && !gdc_wr_d && ide_address == 16'h00a2 && ide_writedata[7:4] == 4'h7)
		pram_time <= since_vs;
	if (frame_tick) begin
		frame_ev <= 1;
		frame_data <= {frame_no, 6'b0, a6_val, a4_val, a4_time, pram_time,
		               gdc_pram[0], gdc_pram[1], gdc_pram[2]};
		frame_no <= frame_no + 1'b1;
		since_vs <= 0; a4_time <= 16'hffff; pram_time <= 16'hffff;
	end
end
wire [71:0] gdc_shadow = {gdc_pitch, gdc_pram[7], gdc_pram[6], gdc_pram[5], gdc_pram[4],
                          gdc_pram[3], gdc_pram[2], gdc_pram[1], gdc_pram[0]};
pc98_cd_trace #(.CLK_HZ(SYS_CLK_KHZ*1000)) cd_trace_uart (
	.clk(clk_sys), .trace(92'd0), .hdd_busy(1'b0),   // CD events off: frees logic (stutter is PCM)
	.fdd_busy(1'b0), .pad1(snac_raw1), .video(72'h0),
	// PCM, EGC and sampled GDC logging off in this build (area): per-frame V only.
	.pcm_ctl(1'b0), .pcm_port(8'h0), .pcm_data(8'h0),
	.pcm_push(1'b0), .gfx_wr(1'b0), .gfx_reg(4'h0), .gfx_data(16'h0),
	.frame_ev(frame_ev), .frame_data(frame_data),
	// {EIP, last I/O port, last I/O data} from the CPU snapshot
	.cpu_sample({cpu_debug_snapshot[127:96], cpu_debug_snapshot[63:48], cpu_debug_snapshot[47:32]}),
	.tx(UART_TXD)
);
`else
assign UART_TXD=1'b1;
`endif
`endif

wire [65:0] ps2_key;
wire [64:0] sysrtc;

hps_io #(.CONF_STR(CONF_STR), .PS2DIV(2400 * SYS_CLK_KHZ / 20000), .PS2WE(1), .VDNUM(5)) hps_io
(
	.clk_sys(clk_sys),
	.HPS_BUS(HPS_BUS),
	
	.buttons(buttons),
	.status(status),
	
	.TIMESTAMP(TIMESTAMP),

	.sd_lba(hps_lba),
	.sd_blk_cnt(hps_blk_cnt),
	.sd_rd({cd_rd, host_rd}),
	.sd_wr({1'b0, host_wr}),
	.sd_ack(hps_ack),
	.sd_buff_addr(sd_buff_addr),
	.sd_buff_dout(sd_buff_dout),
	.sd_buff_din(hps_buff_din),
	.sd_buff_wr(sd_buff_wr),

	.img_mounted(hps_mounted),
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
	.joystick_1(joystick_1),
	.joystick_r_analog_0(joystick_r0),
	.joystick_r_analog_1(joystick_r1)
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
// Display and GDC clock moved to status[32]/[33] so a fresh setup defaults
// to Normal display and 2.5 MHz GDC (5 MHz tiles e.g. Nightslave). Old bits
// 14/22 stay reserved so earlier saved settings cannot alias the new ones.
wire [1:0]pdip1 = {~status[32], status[13]};
wire [7:0]pdip2 = {~status[33], status[21:15]};

assign CLK_VIDEO = clk_vid;
assign AUDIO_S = 1;

wire disk_led;
wire [1:0] floppy_access;
wire [1:0] floppy_present;
wire boot_hold;
wire [2:0] boot_prompt;
wire [2:0] boot_prompt_video;
video_config_snapshot #(.WIDTH(3)) boot_prompt_cdc (
    .source_clk(clk_sys), .video_clk(clk_vid),
    .source_data(boot_prompt), .video_data(boot_prompt_video)
);
boot_media_control #(.RAW_IDE(RAW_IDE)) boot_control (
    .clk(clk_sys), .reset(!pll_locked), .restart(reset), .rom_ready(ldr_done),
    .start_without_disk(status[27]), .floppy_ready(floppy_present),
    .image_mounted(core_img_mounted), .image_size(core_img_size),
    .hold_boot(boot_hold), .prompt(boot_prompt)
);
// (native_ce/hs/vs/de are declared above, with the trace wires)
wire [7:0] native_r, native_g, native_b;
wire output_ce, output_hs, output_vs, output_de;
wire [7:0] output_r, output_g, output_b;

video_output video_out (
	.clk(clk_vid), .reset(!pll_locked), .test_pattern(status[3]),
    .boot_prompt(boot_prompt_video),
	.native_ce(native_ce), .native_r(native_r), .native_g(native_g), .native_b(native_b),
	.native_hs(native_hs), .native_vs(native_vs), .native_de(native_de),
	.ce(output_ce), .r(output_r), .g(output_g), .b(output_b),
	.hs(output_hs), .vs(output_vs), .de(output_de)
);
// The on-screen disk/CD/HDD access icons (floppy_overlay) were removed to
// free ~380 ALMs for the memory-system work; the design had no room left.
assign CE_PIXEL = output_ce;
assign VGA_HS = output_hs;
assign VGA_VS = output_vs;
assign VGA_DE = output_de;
assign VGA_R = output_r;
assign VGA_G = output_g;
assign VGA_B = output_b;

// Report native pixel aspect by default. Optional crop is HDMI-only.
pc98_video_scale hdmi_scale (
    .source_clk(clk_sys), .clk(clk_vid), .reset(!pll_locked), .ce(CE_PIXEL), .vs(VGA_VS), .de(VGA_DE),
    .hdmi_width(HDMI_WIDTH), .hdmi_height(HDMI_HEIGHT), .mode(status[25:23]),
    .custom_x(aspect_x), .custom_y(aspect_y), .arx(VIDEO_ARX), .ary(VIDEO_ARY),
    .crop_left(HDMI_CROP_LEFT), .crop_top(HDMI_CROP_TOP),
    .crop_width(HDMI_CROP_WIDTH), .crop_height(HDMI_CROP_HEIGHT)
);

`ifdef ZET98_EXT_RAM_MB
localparam EXT_RAM_MB = `ZET98_EXT_RAM_MB;
`else
localparam EXT_RAM_MB = 0;
`endif
`ifdef ZET98_LOWMEM_CACHE
localparam LOWMEM_CACHE = 1;
`else
localparam LOWMEM_CACHE = 0;
`endif
`ifdef ZET98_LOWMEM_CACHE_KB
localparam LOWMEM_CACHE_KB = `ZET98_LOWMEM_CACHE_KB;
`else
localparam LOWMEM_CACHE_KB = 8;
`endif
`ifdef ZET98_UPPER_RAM_ICACHE
localparam UPPER_RAM_ICACHE = 1;
`else
localparam UPPER_RAM_ICACHE = 0;
`endif
`ifdef ZET98_PEGC
localparam PEGC_ENABLED = 1;
`else
localparam PEGC_ENABLED = 0;
`endif
Zet98MiSTer #(.SYSFREQ(SYS_CLK_KHZ), .CPU486(CPU486_ENABLED), .EXT_RAM_MB(EXT_RAM_MB), .LOWMEM_CACHE(LOWMEM_CACHE), .LOWMEM_CACHE_KB(LOWMEM_CACHE_KB), .UPPER_RAM_ICACHE(UPPER_RAM_ICACHE), .PEGC_ENABLE(PEGC_ENABLED), .SND(SOUND_MODEL), .USE_JT08(USE_JT08), .USE_IDE_BOOTROM(RAW_IDE)) Zet98_top
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
    .pBootHold(boot_hold), .pFloppyPresent(floppy_present),

	.pPs2Clkin(ps2_kbd_clk_out),
	.pPs2Clkout(ps2_kbd_clk_in),
	.pPs2Datin(ps2_kbd_data_out),
	.pPs2Datout(ps2_kbd_data_in),

	.pPmsClkin(ps2_mouse_clk_out),
	.pPmsClkout(ps2_mouse_clk_in),
	.pPmsDatin(ps2_mouse_data_out),
	.pPmsDatout(ps2_mouse_data_in),
	.pMsExtDX(stick_dx), .pMsExtDY(stick_dy), .pMsExtStb(stick_stb), .pMsExtBtn(stick_buttons),

	.pJoyA(joyA),
	.pJoyB(joyB),

	.pFDSYNC(fdsync),
	.pFDEJECT(fdeject),

	.mist_mounted(core_img_mounted & (RAW_IDE ? 4'b1011 : 4'b1111)),
	.mist_readonly({4{core_img_readonly}}),
	.mist_imgsize(core_img_size),

	.mist_lba(sd_lba),
	.mist_rd(legacy_sd_rd),
	.mist_wr(legacy_sd_wr),
	// diskemu serializes all four image slots onto one buffer/acknowledgement.
	// hps_io returns a one-hot ACK: narrowing it to one bit loses slots 1..3.
	.mist_ack(|(core_sd_ack & (RAW_IDE ? 4'b1011 : 4'b1111))),

	.mist_buffaddr(core_buff_addr[legacy_buffer_slot]),
	.mist_buffdout(core_buff_dout[legacy_buffer_slot]),
	.mist_buffdin(sd_buff_din),
	.mist_buffwr(|(core_buff_wr & (RAW_IDE ? 4'b1011 : 4'b1111))),
	.pIDEAddress(ide_address), .pIDESelect(ide_select), .pIDEWriteData(ide_writedata),
	.pIDERead(ide_read), .pIDEWrite(ide_write), .pIDEResetn(ide_resetn),
	.pIDEReadData(artic_oe ? artic_readdata : ide_readdata), .pIDEOE(ide_oe | artic_oe), .pIDEIRQ(ide_irq),
	// Full compiled clock only. Keep saved status bits 29:28 reserved so an
	// old slower-speed selection cannot re-enable the unqualified throttle.
	.pCPUSpeed(2'b00),
	.pMPUReadData(mpu_readdata), .pMPUOE(mpu_oe), .pMPUIRQ(mpu_irq),
    .pCPUDebug(cpu_debug_snapshot),

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

	.pSndL(core_snd_l),
	.pSndR(core_snd_r),
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
