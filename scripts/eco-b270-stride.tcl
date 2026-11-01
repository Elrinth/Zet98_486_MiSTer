# B270 release bitstream: B269's placed and routed database plus eight LUTs
# for the GDC 5 MHz planar line step, added by a Chip Planner ECO.
#
# GRAPHSCR98 advances each planar line by the GDC pitch in words. With the GDC
# at 5 MHz the pitch counts a line twice (Windows 95's EGC driver: pitch 80 for
# 40 words), so the frame copy pitch_frame takes the pitch halved:
#   pitch_frame[i] <= FAST ? pitch_pixel[i+1] : pitch_pixel[i]   (bit 7: 0)
# Each pitch_frame register loads through SDATA, so a new LUT computes that
# mux and drives SDATA instead of pitch_pixel[i]. FAST is pegc_raster's fast_p,
# the same pixel-clock copy of the GDC clock latches that GRAPHSCR98's
# fast_pixel is in the source. Nothing else changes: the ECO router keeps
# 99.98% of the routes and B269's timing (worst slack -7.075 ns).
#
# Rules found the hard way (Quartus Lite 17.0, Cyclone V):
# - Chip Planner LUT masks are the bit reversal of the logical function (the
#   .vo netlist shows the same masks with every data input negated). The mux
#   C ? B : A is 5353; !C & A is 5050.
# - Until the ECO fitter legalizes it, a new cell maps onto all four LUT blocks
#   of its ALM: a second cell there, new or existing, shares and overwrites
#   them. Each new cell therefore gets an otherwise empty ALM (the one at
#   X83_Y26 and the empty ALMs of X87_Y36 and X88_Y36 near the GRAPHSCR98
#   registers). Halves beside "~feeder" LUTs refuse new cells.
# - A quarter's stored bits can read back with inputs permuted, so each quarter
#   is written by probing the identity masks and checked against the 64-bit
#   LUT Mask read-back.
#
# Run from Zet98/v17 of the B269 database (B268 build tree after
# eco-b269-zavas-cg.tcl and quartus_asm), then:
#   quartus_cdb -t ../../scripts/eco-b270-stride.tcl
#   quartus_asm Zet98 -c release-Zet98MiSTer
package require ::quartus::chip_planner
project_open Zet98 -revision release-Zet98MiSTer
read_netlist

set top "|sys_top|emu:emu|Zet98MiSTer:Zet98_top|"
set grp "CRTC98:VID|GRAPHSCR98:GRP|"
proc name_of {n} { return [string map [list $::top ""] [get_node_info -node $n -info full_name]] }
# Chip Planner node ids are stable for one database; check every name anyway.
proc need {n name} {
    if {[name_of $n] ne $name} { error "node $n is [name_of $n], not $name: not the B269 database" }
}
proc oport_of {n type} {
    set r ""
    foreach_in_collection op [get_oports -node $n] {
        if {$r eq "" && ($type eq "" ||
            [get_port_info -node $n -port_id $op -type oport -info port_type] eq $type)} { set r $op }
    }
    if {$r eq ""} { error "no $type output on [name_of $n]" }
    return $r
}
# Port ids are collected first: a port inside an open collection loop cannot
# be removed.
proc sdata_port {n} {
    set r ""; set src ""
    foreach_in_collection ip [get_iports -node $n] {
        if {[get_port_info -node $n -port_id $ip -type iport -info port_type] eq "SDATA"} {
            set r $ip
            set src [get_port_info -node $n -port_id $ip -type iport -info {Input Port Source Atom Id}]
        }
    }
    return [list $r $src]
}
set quarter_names {{F0 LUT Mask} {F1 LUT Mask} {F2 LUT Mask} {F3 LUT Mask}}
set identity {AAAA CCCC F0F0 FF00}
proc segment {n j} {
    return [string range [get_node_info -node $n -info {LUT Mask}] [expr {12 - 4*$j}] [expr {15 - 4*$j}]]
}
proc store {n j v} { set_node_info -node $n -info [lindex $::quarter_names $j] $v }
proc write_quarter {n j want} {
    set perm {}; set inv {}
    for {set k 0} {$k < 4} {incr k} {
        store $n $j [lindex $::identity $k]
        set got [segment $n $j]; set found 0
        for {set m 0} {$m < 4} {incr m} {
            set id [lindex $::identity $m]
            if {$got eq $id} { lappend perm $m; lappend inv 0; set found 1; break }
            if {$got eq [format %04X [expr {~[scan $id %x] & 0xFFFF}]]} { lappend perm $m; lappend inv 1; set found 1; break }
        }
        if {!$found} { error "[name_of $n] quarter $j: identity [lindex $::identity $k] reads $got" }
    }
    set w [scan $want %x]; set v 0
    for {set i 0} {$i < 16} {incr i} {
        set d 0
        for {set k 0} {$k < 4} {incr k} {
            set d [expr {$d | (((($i >> $k) & 1) ^ [lindex $inv $k]) << [lindex $perm $k])}]
        }
        if {($w >> $d) & 1} { set v [expr {$v | (1 << $i)}] }
    }
    store $n $j [format %04X $v]
    if {[segment $n $j] ne $want} { error "[name_of $n] quarter $j reads [segment $n $j], not $want" }
}

set fast 64121
need $fast "CRTC98:VID|pegc_raster:packed_raster|fast_p"
set frame {83230 83312 83317 83322 83327 83332 83337 83342}
set pixel {84943 84976 84980 84984 84988 84992 84996 85000}
set sites {LABCELL_X83_Y26_N30 MLABCELL_X87_Y36_N0 MLABCELL_X87_Y36_N6 MLABCELL_X87_Y36_N30
           MLABCELL_X87_Y36_N36 LABCELL_X88_Y36_N0 LABCELL_X88_Y36_N6 LABCELL_X88_Y36_N12}
for {set i 0} {$i < 8} {incr i} {
    need [lindex $frame $i] "${grp}pitch_frame\[$i\]"
    need [lindex $pixel $i] "${grp}pitch_pixel\[$i\]"
    if {[lindex [sdata_port [lindex $frame $i]] 1] != [lindex $pixel $i]} {
        error "pitch_frame\[$i\] does not load pitch_pixel\[$i\]"
    }
}
set cells {}
for {set i 0} {$i < 8} {incr i} {
    set n [add_new_cell -comb -cell_name GRP_pitch_half_$i -location [lindex $sites $i]]
    if {![string is integer -strict $n] || $n < 0} { error "cannot add GRP_pitch_half_$i at [lindex $sites $i]" }
    set inputs [list DATAA [lindex $pixel $i] DATAC $fast]
    if {$i < 7} { lappend inputs DATAB [lindex $pixel [expr {$i + 1}]] }
    foreach {port src} $inputs {
        if {[make_ape_connection -src_node $src -src_port [oport_of $src ""] -dst_node $n -port_type $port] != 1} {
            error "connecting [name_of $src] to GRP_pitch_half_$i failed"
        }
    }
    set f [lindex $frame $i]
    if {[remove_ape_connection -dst_node $f -dst_port [lindex [sdata_port $f] 0]] != 1} { error "removing pitch_frame\[$i\] SDATA failed" }
    if {[make_ape_connection -src_node $n -src_port [oport_of $n COMBOUT] -dst_node $f -port_type SDATA] != 1} {
        error "connecting GRP_pitch_half_$i to pitch_frame\[$i\] failed"
    }
    lappend cells $n [expr {$i < 7 ? "5353" : "5050"}]
}
# Masks after all connections: the quarter read-back depends on them.
foreach {n q} $cells {
    for {set j 0} {$j < 4} {incr j} { write_quarter $n $j $q }
}
foreach {n q} $cells {
    if {[get_node_info -node $n -info {LUT Mask}] ne "$q$q$q$q"} { error "[name_of $n] LUT mask read-back failed" }
}
if {![check_netlist_and_save]} { error "ECO netlist check or routing failed" }
puts "B270 ECO applied: GDC 5 MHz planar line step"
