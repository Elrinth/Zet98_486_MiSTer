"""Prepare two identical isolated Quartus projects except comparison FORM."""
from pathlib import Path
import hashlib,json,argparse
parser=argparse.ArgumentParser()
parser.add_argument("--output",type=Path,required=True)
args=parser.parse_args()
def write_lf(path,text):
    path.write_bytes(text.replace("\r\n","\n").encode())
root=args.output
assert not root.exists(), 'One-shot preparation; inspect existing bundle instead'
root.mkdir(parents=True)
qsf='''set_global_assignment -name FAMILY "Cyclone V"
set_global_assignment -name DEVICE 5CSEBA6U23I7
set_global_assignment -name TOP_LEVEL_ENTITY segment_compare_timing
set_global_assignment -name SYSTEMVERILOG_FILE segment_compare_timing.sv
set_global_assignment -name SYSTEMVERILOG_FILE vipt_segment_compare.sv
set_global_assignment -name SDC_FILE compare.sdc
set_global_assignment -name PROJECT_OUTPUT_DIRECTORY output_files
set_global_assignment -name QII_AUTO_PACKED_REGISTERS NORMAL
set_global_assignment -name SEED 7
set_global_assignment -name NUM_PARALLEL_PROCESSORS 1
set_global_assignment -name OPTIMIZE_HOLD_TIMING "ALL PATHS"
set_location_assignment PIN_V11 -to clk
set_instance_assignment -name IO_STANDARD "3.3-V LVTTL" -to clk
set_instance_assignment -name VIRTUAL_PIN ON -to offset_bit
set_instance_assignment -name VIRTUAL_PIN ON -to limit_bit
set_instance_assignment -name VIRTUAL_PIN ON -to size_in[0]
set_instance_assignment -name VIRTUAL_PIN ON -to size_in[1]
set_instance_assignment -name VIRTUAL_PIN ON -to accepted
set_parameter -name FORM {form}
'''
sdc='''create_clock -name probe -period 11.111 [get_ports clk]
set_input_delay -clock probe 0 [get_ports {offset_bit limit_bit size_in[*]}]
set_output_delay -clock probe 0 [get_ports accepted]
derive_clock_uncertainty
'''
tcl='''project_open compare
create_timing_netlist
read_sdc
update_timing_netlist
set result [get_registers {*accepted_r*}]
if {[get_collection_size $result] != 1} {error "Expected one retained output register"}
foreach {group pattern count} {offset {*offset_r*} 32 limit {*limit_r*} 32 size {*size_r*} 2} {
 set source($group) [get_registers $pattern]
 set base_indices {}
 foreach_in_collection reg $source($group) {
  set name [get_node_info -name $reg]
  set expression [format {^%s_r\[([0-9]+)\](~DUPLICATE[0-9]*)?$} $group]
  if {![regexp $expression $name match bit suffix]} {error "Unexpected $group register $name"}
  if {$bit < 0 || $bit >= $count} {error "Unexpected $group bit $bit"}
  if {$suffix eq ""} {lappend base_indices $bit}
 }
 if {[llength [lsort -unique $base_indices]] != $count} {error "Missing original $group register"}
 puts "PROBE_REGISTERS $group logical=$count physical=[get_collection_size $source($group)]"
}
set corner 0
foreach_in_collection condition [get_available_operating_conditions] {
 set_operating_conditions $condition
 update_timing_netlist
 puts "PROBE_CORNER $corner model=[get_operating_conditions_info $condition -model] temperature=[get_operating_conditions_info $condition -temperature]"
 foreach group {offset limit size} {
  report_timing -setup -from $source($group) -to $result -npaths 1 -detail full_path -file output_files/corner-${corner}-${group}.txt
 }
 report_timing -hold -npaths 1 -detail full_path -file output_files/corner-${corner}-hold.txt
 incr corner
}
puts "PASS SEGMENT_TIMING_REGISTERS 32 32 2 1"
delete_timing_netlist
project_close
'''
for name,form in [('sum',0),('parallel',1)]:
    folder=root/name;folder.mkdir()
    for source in ('segment_compare_timing.sv','vipt_segment_compare.sv'):
        (folder/source).write_bytes((Path('tests')/source).read_bytes())
    write_lf(folder/'compare.qpf','PROJECT_REVISION = "compare"\n')
    write_lf(folder/'compare.qsf',qsf.format(form=form))
    write_lf(folder/'compare.sdc',sdc)
    write_lf(folder/'report.tcl',tcl)
write_lf(root/'run.sh','''#!/usr/bin/env bash
set -euo pipefail
cd /project
archive() {
 status=$?
 cd /project
 find . -type f -print0 | sort -z | xargs -0 sha256sum > /export.sha256
 tar -cf /export.tar -C /project .
 exit "$status"
}
trap archive EXIT
for name in sum parallel; do
 cd /project/$name
 quartus_map compare > map.log 2>&1
 quartus_fit compare > fit.log 2>&1
 quartus_sta -t report.tcl > sta.log 2>&1
 if grep -Ei 'Ignored.*assignment|Ignored.*constraint|Critical Warning' map.log fit.log sta.log; then
  echo 'FAIL: investigate ignored assignments/constraints or critical warnings'; exit 1
 fi
 grep 'PASS SEGMENT_TIMING_REGISTERS' sta.log
 echo "Completed isolated $name comparison"
done
''')
write_lf(root/'manifest.json',json.dumps(dict(state='Prepared, not started',scope='Isolated formula timing only; no production RTL/profile/constraints modified; no RBF generated',formula_sha256=hashlib.sha256(Path('tests/vipt_segment_compare.sv').read_bytes()).hexdigest(),variants=['sum','parallel'],timeout_seconds=600),indent=2))
print(root)
