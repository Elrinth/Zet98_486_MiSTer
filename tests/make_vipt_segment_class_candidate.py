"""Generate a simulation-only, conservative direct-load admission variant."""

from pathlib import Path
import sys

source = Path('rtl/vendor/z486/z486.sv').read_text()
needle = 'assign d2_vipt_candidate = !hardwired_off &&'
assert source.count(needle) == 1
guard = '''// TEST COPY ONLY: admit direct loads for the two common complete limit classes.
// Other descriptor limits use the existing microcode fault/restart path.
wire [31:0] test_vipt_offset = issue_eff_mask ? ea_early : {16'b0, ea_early[15:0]};
wire [31:0] test_vipt_limit = seg_effective_limit(desc_cache[i_bus.mem_seg[2:0]]);
wire test_vipt_64k_end_ok = (d2_vipt_mem_size == 2'd0) ||
    ((d2_vipt_mem_size == 2'd1) && (test_vipt_offset[15:0] != 16'hffff)) ||
    ((d2_vipt_mem_size == 2'd2) && (test_vipt_offset[15:0] <= 16'hfffc));
wire test_vipt_4g_end_ok = (d2_vipt_mem_size == 2'd0) ||
    ((d2_vipt_mem_size == 2'd1) && (test_vipt_offset != 32'hffffffff)) ||
    ((d2_vipt_mem_size == 2'd2) && (test_vipt_offset <= 32'hfffffffc));
wire test_vipt_segment_ok = (i_bus.mem_seg <= SEG_GS) &&
    (((test_vipt_limit == 32'h0000ffff) && (test_vipt_offset[31:16] == 0) && test_vipt_64k_end_ok) ||
     ((test_vipt_limit == 32'hffffffff) && test_vipt_4g_end_ok));
assign d2_vipt_candidate = test_vipt_segment_ok && !hardwired_off &&'''
source = source.replace(needle, guard)
monitor = '''
integer test_class_admits = 0;
always @(posedge clk) begin
    if (reset_n && i_issue && d2_vipt_candidate && test_class_admits < 24) begin
        test_class_admits = test_class_admits + 1;
        $display("SEG CLASS ADMIT offset=%h limit=%h size=%d direct=%b", test_vipt_offset,
                 test_vipt_limit, d2_vipt_mem_size, d2_vipt_load);
    end
end
'''
assert source.count('endmodule') == 1
Path(sys.argv[1]).write_text(source if '--no-monitor' in sys.argv else source.replace('endmodule', monitor + '\nendmodule'))
