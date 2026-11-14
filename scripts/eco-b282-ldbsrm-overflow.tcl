# B282 release bitstream: B281's placed and routed database with one LUT edited.
#
# Creamy Mami lost the script line after every text line: IMUL returned 0.
# The z486 shifter keeps an overflow bit for SHL/SHR/SAR with a count >= the
# operand width. SHIFT1 sets it; LDBSLM, LDBSRU and LDBSLU clear it; LDBSRM,
# the count load in front of the IMUL product SHIFT, kept it. After a shift
# such as SHR AL,CL with CL=8 the next IMUL gave 0. The RTL fix is one line in
# rtl/vendor/z486/shifter.sv (LDBSRM: overflow <= 0).
#
# In B281's netlist the overflow register keeps its value unless
# overflow~2 is 0 while count[5]~0 (exec & !aluop[2] & aluop[4] == aluop[5])
# holds. overflow~2 reads A=aluop[0] B=instr_is_shxd C=aluop[3] D=aluop[6]
# E=aluop[5] F=aluop[1]; its aluop[5]=1/aluop[1]=0 quarter cleared on
# aluop[0] & aluop[3] & aluop[6] (79h only) and now clears on aluop[3] &
# aluop[6] (78h and 79h). Mask FFFFFFFA7FFFFFF0 -> FFFFFFF07FFFFFF0 (F2 quarter
# FFFA -> FFF0). Placement and routing are unchanged.
#
# Run from Zet98/v17 of the B281 build tree (v90vs seed 3, release rbf md5
# 529f1c409ff01bdcb41d3684127942ea), then:
#   quartus_cdb -t ../../scripts/eco-b282-ldbsrm-overflow.tcl
#   quartus_asm Zet98 -c release-Zet98MiSTer
package require ::quartus::chip_planner
project_open Zet98 -revision release-Zet98MiSTer
read_netlist

# Chip Planner node ids are stable for one database; check the name anyway.
set n 97046
set want {pc98_ao486:\ao486_cpu:cpu|z486_pc98_adapter:cpu|z486:core|data_unit:data_unit_inst|shifter:shifter_inst|overflow~2}
if {[string first $want [get_node_info -node $n -info full_name]] < 0} {
    error "node $n is not shifter overflow~2: not the B281 database"
}
set quarters {{F0 LUT Mask} {F1 LUT Mask} {F2 LUT Mask} {F3 LUT Mask}}
set old {}
foreach q $quarters { lappend old [get_node_info -node $n -info $q] }
if {$old ne "FFF0 7FFF FFFA FFFF"} { error "unexpected LUT quarters $old" }
if {[get_node_info -node $n -info {LUT Mask}] ne "FFFFFFFA7FFFFFF0"} { error "unexpected LUT mask" }

set_node_info -node $n -info {F2 LUT Mask} FFF0
set got [get_node_info -node $n -info {LUT Mask}]
if {$got ne "FFFFFFF07FFFFFF0"} { error "LUT mask read-back $got" }
puts "EQ [get_node_info -node $n -info {Combout Equation}]"
if {![check_netlist_and_save]} { error "ECO netlist check failed" }
puts "B282 ECO applied: shifter overflow~2 FFFFFFFA7FFFFFF0 -> FFFFFFF07FFFFFF0"
