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
`elsif ZET98_MPU_UART
	"PC98;UART31250,MIDI31250;",
`else
	"PC98;;",
`endif
	"-;",
	"O12,Aspect ratio,4:3,16:9,Full Screen;",
	"ONP,HDMI scaling,Fit native,Integer fit,Integer zoom,Stretch,CRT 4:3,Custom aspect;",
	"O3,Video test,Off,Color bars;",
	"O4,Startup mute,10s,Off;",
	"o2,Audio filter,On,Off;",
	"o6,SNAC PS pads,Off,On;",
	"O5,Loading text,On,Off;",
`ifdef ZET98_MPU_UART
	"OQ,MPU MIDI,Off,UART;",
	"o35,MIDI volume,100%,75%,50%,25%,Mute,125%,150%,200%;",
`endif
	"-;",
	"R6,Reset;",
	"OR,Empty boot,Wait for disk,Start BIOS;",
	"-;",
	"S0,D88HDMFDI,FDD0;",
	"S1,D88HDMFDI,FDD1;",
`ifdef ZET98_RAW_IDE
	"S2,VHDIMGHDI,IDE hard disk;",
`else
	"S2,HDF,SASI;",
`endif
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
	"o0,DIP1-3 Display,Normal,Plasma;",
	"OF,DIP2-1 NOP,0,1;",
	"OG,DIP2-2 Basic mode,Terminal,Basic;",
	"OH,DIP2-3 Cols,80,40;",
	"OI,DIP2-4 Lines,25,20;",
	"OJ,DIP2-5 Memory SW,Keep,Clear;",
	"OK,DIP2-6 Int.HDD,Disconnect,Connect;",
	"OL,DIP2-7 FDD Motor,Control,ON;",
	"o1,DIP2-8 GDC clock,2.5MHz,5MHz;",
	"J,Fire 1,Fire 2;",
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
audio_decimator audio_decimator (
	.clk(CLK_AUDIO), .enable(~status[34]),
	.in_l(core_snd_l), .in_r(core_snd_r),
	.out_l(AUDIO_L), .out_r(AUDIO_R)
);

wire  [1:0] buttons;

wire [15:0] joystick_0, joystick_1;

// PlayStation pads on the user port (SNAC) add to USB joysticks 1 and 2.
wire  [5:0] snac_joy1, snac_joy2;
snac_psx_pad #(.CLK_HZ(SYS_CLK_KHZ*1000)) snac_pads (
	.clk(clk_sys), .enable(status[38]), .user_in(USER_IN), .user_out(USER_OUT),
	.joy1(snac_joy1), .joy2(snac_joy2)
);
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
pc98_image_bridge #(.ENABLE(NATIVE_IMAGES),.RAW_IDE(RAW_IDE)) images (
    .clk(clk_sys),.image_mounted(img_mounted),.image_readonly(img_readonly),.image_size(img_size),
    .core_mounted(core_img_mounted),.core_readonly(core_img_readonly),.core_size(core_img_size),
    .disk_lba(sd_slot_lba),.disk_rd(sd_rd),.disk_wr(sd_wr),.disk_buff_din(sd_slot_buff_din),
    .disk_ack(core_sd_ack),.disk_buff_wr(core_buff_wr),.disk_buff_addr(core_buff_addr),.disk_buff_dout(core_buff_dout),
    .host_lba(host_slot_lba),.host_rd(host_rd),.host_wr(host_wr),.host_buff_din(host_slot_buff_din),
    .host_ack(sd_ack),.host_buff_wr(sd_buff_wr),.host_buff_addr(sd_buff_addr),.host_buff_dout(sd_buff_dout),
    .invalid(invalid_image)
);
wire [1:0] legacy_buffer_slot = core_sd_ack[0] ? 0 : core_sd_ack[1] ? 1 : core_sd_ack[3] ? 3 : 2;

generate if(RAW_IDE) begin : raw_ide
	pc98_ide controller (
		.clk(clk_sys), .reset(!ide_resetn),
		.io_address(ide_address), .io_writedata(ide_writedata), .io_select(ide_select),
		.io_read(ide_read), .io_write(ide_write), .io_readdata(ide_readdata),
		.io_oe(ide_oe), .irq(ide_irq),
		.image_mounted(core_img_mounted[2]), .image_readonly(core_img_readonly), .image_size(core_img_size),
		.sd_lba(ide_lba), .sd_rd(ide_rd), .sd_wr(ide_wr), .sd_ack(core_sd_ack[2]),
		.sd_buff_addr(core_buff_addr[2]), .sd_buff_dout(core_buff_dout[2]),
		.sd_buff_din(ide_buff_din), .sd_buff_wr(core_buff_wr[2])
	);
end else begin : no_raw_ide
	assign {ide_lba,ide_rd,ide_wr,ide_buff_din,ide_oe,ide_irq}=0;
	assign ide_readdata=16'hffff;
end endgenerate

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
pc98_debug_uart #(.CLOCK_HZ(SYS_CLK_KHZ*1000)) boot_debug (
    .clk(clk_sys), .reset(!pll_locked), .snapshot(cpu_debug_snapshot), .tx(UART_TXD)
);
`else
assign UART_TXD=1'b1;
`endif
`endif

wire [65:0] ps2_key;
wire [64:0] sysrtc;

hps_io #(.CONF_STR(CONF_STR), .PS2DIV(2400 * SYS_CLK_KHZ / 20000), .PS2WE(1), .VDNUM(4)) hps_io
(
	.clk_sys(clk_sys),
	.HPS_BUS(HPS_BUS),
	
	.buttons(buttons),
	.status(status),
	
	.TIMESTAMP(TIMESTAMP),

	.sd_lba(host_slot_lba),
	.sd_blk_cnt(sd_slot_blk_cnt),
	.sd_rd(host_rd),
	.sd_wr(host_wr),
	.sd_ack(sd_ack),
	.sd_buff_addr(sd_buff_addr),
	.sd_buff_dout(sd_buff_dout),
	.sd_buff_din(host_slot_buff_din),
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
wire native_ce, native_hs, native_vs, native_de;
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
floppy_overlay floppy_icon (
	.clk(clk_vid), .reset(!pll_locked), .enabled(!status[5]),
	.activity(floppy_access | sd_rd[1:0] | sd_wr[1:0]),
	.crop_left(HDMI_CROP_LEFT), .crop_top(HDMI_CROP_TOP),
	.crop_width(HDMI_CROP_WIDTH), .crop_height(HDMI_CROP_HEIGHT),
	.in_ce(output_ce), .in_hs(output_hs), .in_vs(output_vs), .in_de(output_de),
	.in_r(output_r), .in_g(output_g), .in_b(output_b),
	.out_ce(CE_PIXEL), .out_hs(VGA_HS), .out_vs(VGA_VS), .out_de(VGA_DE),
	.out_r(VGA_R), .out_g(VGA_G), .out_b(VGA_B)
);

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
	.pIDEReadData(ide_readdata), .pIDEOE(ide_oe), .pIDEIRQ(ide_irq),
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
