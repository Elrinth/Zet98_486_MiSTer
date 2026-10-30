# B269 release bitstream: B268's placed and routed database with one LUT edited.
#
# The Zavas II fix (KNJRAMCONT: Kanji-mode CG reads drop JISCODE(7)) is a
# one-bit logic change, but every new 90 MHz placement of it failed Windows 95
# on the reference board. In B268's netlist JISCODE(7) reaches the Kanji-mode
# path only through KNJRAMADDR[4]~7, knjaddrcnv's right-half flag
# l_rn = kcode(15) or kcode(7). Its JISCODE[7] input (DATAC) is the inverted
# register: with DATAC=0 the cell is constant 1. The fixed function is the old
# one at DATAC=1 (JISCODE(7)=0), so the input stays connected and unused.
# Routing and placement are unchanged; timing equals B268.
#
# Run from Zet98/v17 of the B268 build tree (B268 source, seed 10, whose
# release-Zet98MiSTer.rbf md5 is e732acc379e6bb0aa8e17c26ec2e4a4c), then:
#   quartus_cdb -t ../../scripts/eco-b269-zavas-cg.tcl
#   quartus_asm Zet98 -c release-Zet98MiSTer
# The result is PC98_Z486_90_B269_20261030.rbf (md5 2483eabd425e8284a1f444e8388d089b).
package require ::quartus::chip_planner
project_open Zet98 -revision release-Zet98MiSTer
read_netlist

# Chip Planner node ids are stable for one database; check the name anyway.
set n 46561
set name "|sys_top|emu:emu|Zet98MiSTer:Zet98_top|KNJRAMCONT:KRAMC|KNJRAMADDR\[4\]~7"
if {[get_node_info -node $n -info full_name] ne $name} {
    error "node $n is not KNJRAMADDR\[4\]~7: not the B268 database"
}

set quarters {{F0 LUT Mask} {F1 LUT Mask} {F2 LUT Mask} {F3 LUT Mask}}
set old {}
foreach q $quarters { lappend old [get_node_info -node $n -info $q] }
if {$old ne "FF5F FF5F AF0F AF0F"} { error "unexpected LUT quarters $old" }

# Cyclone V accepts the 16-bit quarters, not the 64-bit mask.
foreach q $quarters v {FF55 FF55 AA00 AA00} { set_node_info -node $n -info $q $v }
if {[get_node_info -node $n -info {LUT Mask}] ne "AA00AA00FF55FF55"} {
    error "LUT mask read-back failed"
}
if {![check_netlist_and_save]} { error "ECO netlist check failed" }
puts "B269 ECO applied: KNJRAMADDR\[4\]~7 AF0FAF0FFF5FFF5F -> AA00AA00FF55FF55"
