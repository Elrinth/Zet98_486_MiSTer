// Fixed-clock architectural execution-rate controller. Memory and peripherals
// continue at clk speed while execution cycles accrue and repay rate debt.
//
// Every charged execution cycle adds (CLOCK_RATE_MHZ - target) to the debt and
// every other cycle repays target, so execution occupies target/CLOCK_RATE_MHZ
// of the wall clock. While debt >= target (hold) z486 launches no new
// instruction; timers, video, sound and DMA keep their own clocks. A REP
// string instruction whose debt reaches debt_high takes its interrupt/restart
// exit (z486.sv) so it is repaid between iterations, as a real CPU would
// service interrupts there.
//
// PC98_MODE targets (MHz of z486 execution cycles; throttled z486 needs ~4
// cycles per typical 16-bit instruction, see tests/run-z486-cpu-speed.sh):
//   1: 33 MHz ~8 MIPS   386DX-33/486SX-25 class
//   2:  8 MHz ~2 MIPS   286-12/386SX-16 class
//   3:  3 MHz ~0.8 MIPS V30 8-10 MHz class (PC-9801 VM/UV/VX)
module cpu_throttle #(
    parameter logic [6:0] CLOCK_RATE_MHZ = 7'd85,
    parameter PC98_MODE = 0
)(
    input  logic       clk,
    input  logic       reset_n,
    input  logic [1:0] speed_sel,
    input  logic       active_cycle,
    output logic       hold,
    output logic       release_cycle,
    output logic       full_speed,
    output logic       debt_high       // >= 16384: interrupt a REP string
);

logic [19:0] debt;
logic  [1:0] speed_r;
logic        release_r;

wire  [6:0] target_mhz = PC98_MODE ?
    (speed_r == 2'd1 ? 7'd33 : speed_r == 2'd2 ? 7'd8 : 7'd3) :
    (speed_r == 2'd1 ? 7'd15 : speed_r == 2'd2 ? 7'd30 : 7'd56);
wire [19:0] target = {13'd0, target_mhz};
wire  [6:0] charge = CLOCK_RATE_MHZ - target_mhz;
wire [20:0] target_twice = {target, 1'b0};
wire [20:0] debt_sum = {1'b0, debt} + {14'd0, charge};
// Every cycle without execution is elapsed time and repays (floor zero):
// launch gaps and memory waits count toward the target rate.
wire [19:0] debt_repaid = (debt > target) ? debt - target : 20'd0;

assign full_speed = speed_r == 2'd0 || target_mhz >= CLOCK_RATE_MHZ;
assign release_cycle = release_r;
assign debt_high = |debt[19:14];

always_ff @(posedge clk) begin
    if (!reset_n) begin
        debt      <= 20'd0;
        speed_r   <= 2'd0;
        hold      <= 1'b0;
        release_r <= 1'b0;
    end else if (speed_sel != speed_r) begin
        debt      <= 20'd0;
        speed_r   <= speed_sel;
        hold      <= 1'b0;
        release_r <= 1'b0;
    end else if (full_speed) begin
        debt      <= 20'd0;
        hold      <= 1'b0;
        release_r <= 1'b0;
    end else if (active_cycle) begin
        debt      <= debt_sum[20] ? 20'hfffff : debt_sum[19:0];
        hold      <= debt_sum >= {1'b0, target};
        release_r <= debt_sum >= {1'b0, target} &&
                     debt_sum < target_twice;
    end else if (debt != 20'd0) begin
        debt      <= debt_repaid;
        hold      <= debt_repaid >= target;
        release_r <= debt_repaid >= target &&
                     {1'b0, debt_repaid} < target_twice;
    end
end

endmodule
