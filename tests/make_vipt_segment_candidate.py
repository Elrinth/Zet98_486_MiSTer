"""Generate a simulation-only admission experiment; never edit production RTL."""
from pathlib import Path
import sys

source = Path('rtl/vendor/z486/z486.sv').read_text()
needle = 'assign d2_vipt_candidate = !hardwired_off &&'
assert source.count(needle) == 1
guard = '''// SIMULATION EXPERIMENT: qualify the issuing instruction's offset/width.
// A rejected shortcut uses the existing microcode fault/restart path.
wire [31:0] test_vipt_offset = issue_eff_mask ? ea_early : {16'b0, ea_early[15:0]};
// Decoder size is log2(bytes): 0/1/2, not bytes-minus-one 0/1/3.
wire [1:0] test_vipt_extra = d2_vipt_mem_size[1] ? 2'd3 : d2_vipt_mem_size;
wire [32:0] test_vipt_last = {1'b0, test_vipt_offset} + {31'b0, test_vipt_extra};
wire [31:0] test_vipt_limit = seg_effective_limit(desc_cache[i_bus.mem_seg[2:0]]);
wire test_vipt_segment_ok = i_bus.mem_seg <= SEG_GS &&
    !test_vipt_last[32] && test_vipt_last[31:0] <= test_vipt_limit;
assign d2_vipt_candidate = test_vipt_segment_ok && !hardwired_off &&'''
source = source.replace(needle, guard)
monitor = '''
// Test-copy-only coverage: identify the tested nonzero-base FS access.
integer test_overlap_lines = 0;
always @(posedge clk) begin
    if (reset_n && i_issue && d2_vipt_load && vipt_load_ex_r.valid && test_overlap_lines < 24) begin
        test_overlap_lines = test_overlap_lines + 1;
        $display("SEG OVERLAP older=%h hit=%b younger=%h segment=%d",vipt_load_ex_r.linear_addr,
                 vipt_load_ex_hit,issue_ind_linear,i_bus.mem_seg);
    end
    if (reset_n && vipt_load_replay_r.valid && test_overlap_lines < 24) begin
        test_overlap_lines = test_overlap_lines + 1;
        $display("SEG REPLAY address=%h",vipt_load_replay_r.linear_addr);
    end
    if (reset_n && i_issue && i_bus.mem_seg == SEG_FS && i_bus.has_modrm &&
        i_bus.modrm[7:6] != 2'b11)
        $display("SEG ADMIT offset=%h last=%h limit=%h size=%d fast=%b", test_vipt_offset,
                 test_vipt_last, test_vipt_limit, d2_vipt_mem_size, d2_vipt_load);
    if (reset_n && vipt_load_ex_r.valid && vipt_load_ex_probed_r &&
        vipt_load_ex_r.linear_addr >= 32'h110100 && vipt_load_ex_r.linear_addr < 32'h110200)
        $display("SEG EX hit=%b address=%h",vipt_load_ex_hit,vipt_load_ex_r.linear_addr);
end
'''
assert source.count('endmodule') == 1
Path(sys.argv[1]).write_text(source if '--no-monitor' in sys.argv else source.replace('endmodule', monitor+'\nendmodule'))
