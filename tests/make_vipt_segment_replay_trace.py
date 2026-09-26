"""Simulation-copy counters only; no forced or modified pipeline states."""
from pathlib import Path
import subprocess,sys
p=Path(sys.argv[1])
subprocess.run([sys.executable,'tests/make_vipt_segment_candidate.py',str(p),'--no-monitor'],check=True)
s=p.read_text()
monitor='''
integer trace_store_wait=0, trace_replay=0, trace_overlap=0, trace_loads=0;
integer trace_lines=0;
integer trace_rejected_while_older=0;
always @(posedge clk) begin
 if(reset_n) begin
  if(d2_valid && vipt_load_ex_r.valid && i_bus.mem_seg==SEG_FS &&
     !test_vipt_segment_ok && test_vipt_offset==32'h100) begin
   trace_rejected_while_older=trace_rejected_while_older+1;
   $display("REPLAY_REJECT older=%h hit=%b younger=%h issue=%b",vipt_load_ex_r.linear_addr,
     vipt_load_ex_hit,test_vipt_offset,i_issue);
  end
  if(vipt_issue_load && issue_ind_linear>=32'h110000 && issue_ind_linear<32'h111000) begin
   trace_loads=trace_loads+1;
   if(vipt_issue_store_wait) trace_store_wait=trace_store_wait+1;
   if(vipt_load_ex_r.valid) trace_overlap=trace_overlap+1;
   if(trace_lines<80) begin
    trace_lines=trace_lines+1;
    $display("REPLAY_ISSUE address=%h storewait=%b older=%b hit=%b split=%b",issue_ind_linear,
      vipt_issue_store_wait,vipt_load_ex_r.valid,vipt_load_ex_hit,d2_ea_split_done_r);
   end
  end
  if(vipt_replay_try && dcache_vipt_probe_direct_accepted &&
     vipt_load_replay_r.linear_addr>=32'h110000 && vipt_load_replay_r.linear_addr<32'h111000) begin
   trace_replay=trace_replay+1;
   $display("REPLAY_ACCEPT address=%h",vipt_load_replay_r.linear_addr);
  end
 end
end
final $display("REPLAY_COVERAGE loads=%0d store_wait=%0d replay=%0d overlap=%0d rejected_while_older=%0d",
 trace_loads,trace_store_wait,trace_replay,trace_overlap,trace_rejected_while_older);
'''
assert s.count('endmodule')==1
p.write_text(s.replace('endmodule',monitor+'\nendmodule'))
