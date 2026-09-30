// SPDX-License-Identifier: GPL-3.0-or-later
// Video clock for the PC-98 24.8 kHz / 56.4 Hz raster: 63.157895 MHz
// (50 MHz x 24 / 19, VCO 1200 MHz), divided by 3 into the 21.0526 MHz dot
// clock of a real PC-98 in 400-line mode. The main PLL's 900 MHz VCO cannot
// produce it next to the 90 MHz CPU clock.
`timescale 1ns/10ps
module pll_vid (
	input  wire refclk,
	input  wire rst,
	output wire outclk_0,
	output wire locked
);
	altera_pll #(
		.fractional_vco_multiplier("false"),
		.reference_clock_frequency("50.0 MHz"),
		.operation_mode("direct"),
		.number_of_clocks(1),
		.output_clock_frequency0("63.157894 MHz"),
		.phase_shift0("0 ps"),
		.duty_cycle0(50),
		.pll_type("General"),
		.pll_subtype("General")
	) altera_pll_i (
		.rst(rst),
		.outclk({outclk_0}),
		.locked(locked),
		.fboutclk(),
		.fbclk(1'b0),
		.refclk(refclk)
	);
endmodule
