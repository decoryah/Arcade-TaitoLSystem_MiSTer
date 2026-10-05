// PLL for the raster: 50 MHz reference in, 4 x the board's pixel clock out: the board's 13.33056 MHz oscillator / 2 =
// 6.66528 MHz pixels, so 26.66112 MHz here (pixel clock = this / 4).
// 26.66112 / 50 = 41658 / 78125: not an integer ratio, so the fractional VCO multiplier is used (VCO = 50 MHz x M with M
// fractional, then a counter). The output is accurate to a few ppb; what the fitter achieves is in the fit report.
`timescale 1 ps / 1 ps
module pll_vid (
		input  wire  refclk,
		input  wire  rst,
		output wire  outclk_0,   // 26.66112 MHz
		output wire  locked
	);

	altera_pll #(
		.fractional_vco_multiplier("true"),
		.reference_clock_frequency("50.0 MHz"),
		.operation_mode("direct"),
		.number_of_clocks(1),
		.output_clock_frequency0("26.661120 MHz"),
		.phase_shift0("0 ps"),
		.duty_cycle0(50),
		.pll_type("General"),
		.pll_subtype("General")
	) altera_pll_i (
		.rst	(rst),
		.outclk	(outclk_0),
		.locked	(locked),
		.fboutclk	( ),
		.fbclk	(1'b0),
		.refclk	(refclk)
	);
endmodule
