# B271 release bitstream: B270's placed and routed database with one LUT edited.
#
# z486 fetched BIOS code (E8000h-FFFFFh) uncached over the 16-bit bus, about
# 0.7 us per instruction: an INT 1Ch clock read took 400 us with interrupts off
# (Elvira's bottom-panel palette split slipped), LIO drawing crawled (Tokimeki
# Bishoujo took about three minutes to reach its title). memory.sv now lets the
# instruction cache fill from E0000h-FFFFFh.
#
# In B270's netlist that decision is registered into the icache's
# req_uncacheable_r through comb~20 <- comb~21 <- comb~18, and comb~18 is the
# below-1 MB "cacheable" term over A=a21 B=a22 C=a18 D=a19 E=a17
# F=cache_upper_ram: a21 | a22 | !a19 | (F & !a17 & !a18). ORing in a18 & a17
# (inputs it already has) adds E0000h-FFFFFh. Routing and placement are
# unchanged; timing equals B270.
#
# Run from Zet98/v17 of the B270 build tree (B269's database after
# eco-b270-stride.tcl and quartus_asm, release-Zet98MiSTer.rbf md5
# a4e4d1c7a32014020d419c48e5ca3179), then:
#   quartus_cdb -t ../../scripts/eco-b271-bios-cache.tcl
#   quartus_asm Zet98 -c release-Zet98MiSTer
# The result has release-Zet98MiSTer.rbf md5 47c2c526d827ae262d80cdfe25e9023a.
package require ::quartus::chip_planner
project_open Zet98 -revision release-Zet98MiSTer
read_netlist

# Chip Planner node ids are stable for one database; check the name anyway.
set n 48775
set name {|sys_top|emu:emu|Zet98MiSTer:Zet98_top|pc98_ao486:\ao486_cpu:cpu|z486_pc98_adapter:cpu|z486:core|memory:memory_inst|comb~18}
if {[get_node_info -node $n -info full_name] ne $name} {
    error "node $n is not memory_inst|comb~18: not the B270 database"
}

set quarters {{F0 LUT Mask} {F1 LUT Mask} {F2 LUT Mask} {F3 LUT Mask}}
set old {}
foreach q $quarters { lappend old [get_node_info -node $n -info $q] }
if {$old ne "FF77 FFF7 FF77 F7F7"} { error "unexpected LUT quarters $old" }

# Cyclone V accepts the 16-bit quarters, not the 64-bit mask. F3 stores its
# inputs C and D swapped (it reads back as FF77).
foreach q $quarters v {FF7F FFF7 FF7F F7F7} { set_node_info -node $n -info $q $v }
if {[get_node_info -node $n -info {LUT Mask}] ne "FF77FF7FFFF7FF7F"} {
    error "LUT mask read-back failed"
}
if {![check_netlist_and_save]} { error "ECO netlist check failed" }
puts "B271 ECO applied: memory_inst|comb~18 FF77FF77FFF7FF77 -> FF77FF7FFFF7FF7F"
