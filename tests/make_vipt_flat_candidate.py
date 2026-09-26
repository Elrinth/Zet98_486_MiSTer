"""Generate a test-only conservative direct-load admission variant.

Production z486.sv and all deployable build snapshots remain untouched.
"""

from pathlib import Path
import hashlib
import sys


BASE_SHA256 = "af28b02bf843fffb35d41fea3e5f21f9aa9a607cc4b6be55ce9b2137b841e1f1"
base = Path("rtl/vendor/z486/z486.sv").read_bytes()
assert hashlib.sha256(base).hexdigest() == BASE_SHA256
source = base.decode()
needle = "assign d2_vipt_candidate = !hardwired_off &&"
assert source.count(needle) == 1

# For the common full-range protected-mode descriptor, only an offset crossing
# 4 GiB can fault. All other descriptors fall back to the existing checked path.
# Size codes 0/1/2/3 represent 1/2/4/4 bytes for this direct-load candidate.
guard = """// TEST COPY ONLY: admit direct loads through full-range descriptors.
wire [31:0] test_flat_offset = issue_eff_mask ? ea_early : {16'b0, ea_early[15:0]};
wire test_flat_descriptor = desc_cache[i_bus.mem_seg[2:0]].G &&
                            (&desc_cache[i_bus.mem_seg[2:0]].limit);
wire test_flat_no_wrap = (d2_vipt_mem_size == 2'd0) ||
    ((d2_vipt_mem_size == 2'd1) && test_flat_offset != 32'hffffffff) ||
    ((d2_vipt_mem_size[1]) && test_flat_offset <= 32'hfffffffc);
wire test_vipt_segment_ok = i_bus.mem_seg <= SEG_GS &&
                             test_flat_descriptor && test_flat_no_wrap;
assign d2_vipt_candidate = test_vipt_segment_ok && !hardwired_off &&"""
source = source.replace(needle, guard)
monitor = """
// TEST COPY ONLY: bounded evidence for actual direct admissions.
integer test_flat_admissions = 0;
always @(posedge clk) begin
    if (reset_n && i_issue && d2_vipt_load && i_bus.mem_seg == SEG_FS &&
        test_flat_admissions < 16) begin
        test_flat_admissions = test_flat_admissions + 1;
        $display("VIPT FLAT FAST offset=%h size=%d", test_flat_offset, d2_vipt_mem_size);
    end
end
"""
assert source.count("endmodule") == 1
if "--no-monitor" not in sys.argv:
    source = source.replace("endmodule", monitor + "\nendmodule")
Path(sys.argv[1]).write_bytes(source.encode())
