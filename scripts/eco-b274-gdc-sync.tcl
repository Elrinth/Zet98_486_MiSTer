# B274 release bitstream: B273's placed and routed database with one LUT edited.
#
# The graphics GDC (Zet98/GDC/gragdc.vhd) turned its display on for START
# (6Bh) and BCTRL (0Dh) and off for BCTRL (0Ch), but ignored the display-enable
# bit of SYNC (0Fh on, 0Eh off), which a uPD7220 and NP2kai honour. Libros de
# Chilam Balam starts its graphics with a bare SYNC 0Fh, so the screen stayed
# black after loading. (The text GDC is left as it is: the Open BIOS's INT 18h
# AH=30h sends SYNC 0Eh to the text GDC and does not restart it.)
#
# GRAPHEN's next state is Mux1~1(GRAPHEN, cmd[3], Mux1~0, cmd[7], cmd[4]) with
# Mux1~0(cmd[0], cmd[5], GRAPHEN, cmd[1], cmd[2], cmd[6]). Mux1~1 already
# selects Mux1~0 for every command with cmd[7]=0, cmd[4]=0, cmd[3]=1 (0Ch-0Fh
# and 6Bh), so only Mux1~0's function changes: 0Eh now gives 0 and 0Fh gives 1
# instead of holding GRAPHEN. Checked exhaustively over all 512 (command,
# GRAPHEN) inputs against both specifications. Routing and placement are
# unchanged.
#
# Run from Zet98/v17 of the B273 build tree (B272's database after
# eco-b273-fdc-dma-lane.tcl, release-Zet98MiSTer.rbf md5 525b201c...), then:
#   quartus_cdb -t ../../scripts/eco-b274-gdc-sync.tcl
#   quartus_asm Zet98 -c release-Zet98MiSTer
package require ::quartus::chip_planner
project_open Zet98 -revision release-Zet98MiSTer
read_netlist

set n 84268
set name [get_node_info -node $n -info full_name]
if {![string match {*graphgdc|Mux1~0} $name]} {
    error "node $n is $name, not graphgdc|Mux1~0: not the B273 database"
}

set quarters {{F0 LUT Mask} {F1 LUT Mask} {F2 LUT Mask} {F3 LUT Mask}}
set old {}
foreach q $quarters { lappend old [get_node_info -node $n -info $q] }
if {$old ne "0F0F 01FF 470F 00FF"} { error "unexpected LUT quarters $old" }
if {[get_node_info -node $n -info {LUT Mask}] ne "0F0F470F0F1F0F0F"} {
    error "unexpected LUT mask"
}

# Only the third quarter changes; F1/F3 hold C and D swapped and stay as read.
set_node_info -node $n -info {F2 LUT Mask} 4747
set mask [get_node_info -node $n -info {LUT Mask}]
set eq [get_node_info -node $n -info {Combout Equation}]
puts "read back: $mask $eq"
if {$mask ne "0F0F47470F1F0F0F"} { error "LUT mask read-back failed: $mask" }
if {![check_netlist_and_save]} { error "ECO netlist check failed" }
puts "ECO_RESULT 1"
puts "B274 ECO applied: graphgdc|Mux1~0 0F0F470F0F1F0F0F -> 0F0F47470F1F0F0F ($eq)"
