# B273 release bitstream: B272's placed and routed database with one LUT edited.
#
# A floppy write whose DMA buffer is in graphics VRAM stored every even byte
# twice: the GRCG/EGC port drives both data lanes on every VRAM read, and the
# memory-to-FDC mux took the low lane whenever any low-lane source was valid,
# also for odd DMA addresses. Eye of the Beholder writes its save disk from
# VRAM; the disk came out with a broken boot sector and FAT.
# (tests/hardware/fdvram98.asm: G-VRAM got 00 00 0E 0E 1C 1C, want 00 07 0E 15 1C 23.)
#
# fdc_wdata~2 is the netlist's shared lane select for the eight FDC write-data
# bits. Its inputs are
#   A = CPUWRDAT[7]~1   main RAM / plain VRAM low-lane read
#   C = fdc_wdata~1     odd memory read with no UMA, DMA-above-1MB or GRCG source
#   D = bussel[0]~1     low lane selected (DMA: even address)
#   F = dbus_low~47     no text, attribute or NVRAM low-lane source
# and it computed (F & (!C # (!A & D))) # !F. During a DMA memory read the
# right choice is the low lane for even addresses and for the byte-wide
# sources only, which the same inputs give as D # !F. DMA above 1 MB takes
# its data before this select (CPUWRDAT~70), so it is unaffected. The RTL
# change (Zet98MiSTer.vhd dma_mem_low/high) qualifies the GRCG and IDE-ROM
# lanes by bussel. Routing and placement are unchanged.
#
# Run from Zet98/v17 of the B272 build tree (release-Zet98MiSTer.rbf md5
# 84235a10...), then:
#   quartus_cdb -t ../../scripts/eco-b273-fdc-dma-lane.tcl
#   quartus_asm Zet98 -c release-Zet98MiSTer
package require ::quartus::chip_planner
project_open Zet98 -revision release-Zet98MiSTer
read_netlist

set n 64889
set name [get_node_info -node $n -info full_name]
if {![string match {*Zet98_top|fdc_wdata~2} $name]} {
    error "node $n is $name, not fdc_wdata~2: not the B272 database"
}

set quarters {{F0 LUT Mask} {F1 LUT Mask} {F2 LUT Mask} {F3 LUT Mask}}
set old {}
foreach q $quarters { lappend old [get_node_info -node $n -info $q] }
if {$old ne "F0FA F0FA FFFF FFFF"} { error "unexpected LUT quarters $old" }

# Cyclone V accepts the 16-bit quarters, not the 64-bit mask.
set new {00FF 00FF FFFF FFFF}
foreach q $quarters v $new { set_node_info -node $n -info $q $v }
set mask [get_node_info -node $n -info {LUT Mask}]
set eq [get_node_info -node $n -info {Combout Equation}]
puts "read back: $mask $eq"
if {$mask ne "FFFFFFFF00FF00FF"} { error "LUT mask read-back failed: $mask" }
if {![check_netlist_and_save]} { error "ECO netlist check failed" }
puts "ECO_RESULT 1"
puts "B273 ECO applied: fdc_wdata~2 FFFFFFFFF0FAF0FA -> FFFFFFFF00FF00FF ($eq)"
