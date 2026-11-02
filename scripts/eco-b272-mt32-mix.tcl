# B272 release bitstream: B271's placed and routed database with one LUT edited.
#
# The MT32-pi's audio comes back over I2S on the USER port. Zet98.sv mixed it
# into the core's output only once the MT32-pi had identified itself over I2C
# (mt32_available), so an MT32-pi without the MiSTer I2C control ("mister = on"
# in mt32-pi.cfg) played the music but was never heard. ao486 mixes it whenever
# it is not muted; the mix now follows the OSD's "USER port: MT32-pi" alone.
#
# In B271's netlist mt32_use = status[51] & mt32_available drives only the
# clock-crossing register mt32_cfg_meta[3] (its MidiLink use has its own
# copy). The LUT keeps both inputs and now passes status[51]. Routing and
# placement are unchanged; timing equals B271.
#
# Run from Zet98/v17 of the B271 build tree (B270's database after
# eco-b271-bios-cache.tcl and quartus_asm, release-Zet98MiSTer.rbf md5
# 47c2c526d827ae262d80cdfe25e9023a), then:
#   quartus_cdb -t ../../scripts/eco-b272-mt32-mix.tcl
#   quartus_asm Zet98 -c release-Zet98MiSTer
package require ::quartus::chip_planner
project_open Zet98 -revision release-Zet98MiSTer
read_netlist

# Chip Planner node ids are stable for one database; check the name anyway.
set n 94162
if {[get_node_info -node $n -info full_name] ne "|sys_top|emu:emu|mt32_use"} {
    error "node $n is not mt32_use: not the B271 database"
}

set quarters {{F0 LUT Mask} {F1 LUT Mask} {F2 LUT Mask} {F3 LUT Mask}}
set old {}
foreach q $quarters { lappend old [get_node_info -node $n -info $q] }
if {$old ne "0505 0505 0505 0505"} { error "unexpected LUT quarters $old" }

# Cyclone V accepts the 16-bit quarters, not the 64-bit mask. 5555 depends on
# input A (status[51]) only.
foreach q $quarters { set_node_info -node $n -info $q 5555 }
if {[get_node_info -node $n -info {LUT Mask}] ne "5555555555555555"} {
    error "LUT mask read-back failed"
}
if {![check_netlist_and_save]} { error "ECO netlist check failed" }
puts "B272 ECO applied: mt32_use 0505050505050505 -> 5555555555555555"
