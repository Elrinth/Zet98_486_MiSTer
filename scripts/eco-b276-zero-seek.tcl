# B276 release bitstream: B275's placed and routed database (seed 9, release-Zet98MiSTer.rbf md5
# a92bdffd...) with one LUT of the FDC seek engine added and one edited.
#
# A SEEK to the cylinder the head is already on ended in the cycle after the command
# (FDC/headseek.vhd headseek4: ST_IDLE -> ST_NOP with reach). Star Cruiser's own floppy driver
# stores "wait for the seek" right after the last SEEK byte; the interrupt came first, its
# INT 13h handler had already cleared that state, and the game waited for good. A uPD765
# compares NCN with PCN on its step timing, so the seek now ends on the next seek tick: ST_NOP
# holds until esft, and reach rises on that tick.
#
#   new LUT hs_nop_hold:            A&!B                 A = state.ST_NOP, B = esft~1
#   Selector44~0 (state.ST_NOP D):  F&C  ->  (F&C) | D   D = hs_nop_hold
#   Selector50~1 (reach D):  (F&A&B&!C) | D  ->  (F&A&B&!C) | (D&A),  D: Selector44~0 -> state.ST_NOP
#
# ST_NOP's register takes its D input only from Selector44~0 (packed in the same ALM), and that
# ALM has one free input pin (D; A-C are full with its partner's signals, E is not changeable),
# so the hold term is computed by a new LUT in an empty ALM two rows up. ST_NOP is entered only
# from the zero-step term, so every other path is unchanged. Checked on the B275 netlist (hseco/scen.py: zero-step seeks
# end on the next tick with a one-cycle reach; normal seeks and recalibrate unchanged).
#
# Run from Zet98/v17 of the B275 seed 9 tree (docker image zet98-b275-eco:1), then:
#   quartus_cdb -t ../../scripts/eco-b276-zero-seek.tcl
#   quartus_asm Zet98 -c release-Zet98MiSTer
package require ::quartus::chip_planner
project_open Zet98 -revision release-Zet98MiSTer
read_netlist

proc nname {n} { return [string map {"|sys_top|emu:emu|Zet98MiSTer:Zet98_top|" ""} [get_node_info -node $n -info full_name]] }
proc need {n suffix} {
    set nm [nname $n]
    if {![string match "*$suffix" $nm]} { error "node $n is $nm, not $suffix: not the B275 database" }
}
proc oport_of {n type} {
    set r ""
    foreach_in_collection op [get_oports -node $n] {
        if {$r eq "" && ($type eq "" || [get_port_info -node $n -port_id $op -type oport -info port_type] eq $type)} { set r $op }
    }
    if {$r eq ""} { error "no $type oport on [nname $n]" }
    return $r
}
proc inputs {n} {
    set r {}
    foreach_in_collection ip [get_iports -node $n] {
        set t [get_port_info -node $n -port_id $ip -type iport -info port_type]
        set sa ""; catch {set sa [get_port_info -node $n -port_id $ip -type iport -info {Input Port Source Atom Id}]}
        lappend r $t $ip $sa
    }
    return $r
}
proc src_of {n type} {
    foreach {t ip sa} [inputs $n] { if {$t eq $type} { return $sa } }
    return ""
}
# A quarter's stored bits can read back permuted (C and D swap): probe each quarter with the
# four identity masks, then store the bits that read back as the target (as in B270's ECO).
set ::qname {{F0 LUT Mask} {F1 LUT Mask} {F2 LUT Mask} {F3 LUT Mask}}
set ::basis {AAAA CCCC F0F0 FF00}
proc seg {n j} { return [string range [get_node_info -node $n -info {LUT Mask}] [expr {12 - 4*$j}] [expr {15 - 4*$j}]] }
proc setquarter {n j v} { set_node_info -node $n -info [lindex $::qname $j] $v }
proc hex16 {v} { return [format %04X [expr {$v & 0xFFFF}]] }
proc writequarter {n j t} {
    set perm {}; set inv {}
    for {set k 0} {$k < 4} {incr k} {
        setquarter $n $j [lindex $::basis $k]
        set r [seg $n $j]; set found 0
        for {set m 0} {$m < 4} {incr m} {
            set b [lindex $::basis $m]
            if {$r eq $b} { lappend perm $m; lappend inv 0; set found 1; break }
            if {$r eq [hex16 [expr {~[scan $b %x]}]]} { lappend perm $m; lappend inv 1; set found 1; break }
        }
        if {!$found} { error "[nname $n] quarter $j: identity [lindex $::basis $k] reads $r" }
    }
    set tv [scan $t %x]; set sv 0
    for {set i 0} {$i < 16} {incr i} {
        set d 0
        for {set k 0} {$k < 4} {incr k} {
            set bit [expr {(($i >> $k) & 1) ^ [lindex $inv $k]}]
            set d [expr {$d | ($bit << [lindex $perm $k])}]
        }
        if {($tv >> $d) & 1} { set sv [expr {$sv | (1 << $i)}] }
    }
    setquarter $n $j [hex16 $sv]
    if {[seg $n $j] ne $t} { error "[nname $n] quarter $j reads [seg $n $j], want $t" }
}
proc setmask64 {n t} {
    for {set j 0} {$j < 4} {incr j} { writequarter $n $j [string range $t [expr {12 - 4*$j}] [expr {15 - 4*$j}]] }
    if {[get_node_info -node $n -info {LUT Mask}] ne $t} { error "[nname $n] LUT mask [get_node_info -node $n -info {LUT Mask}], want $t" }
}

set NOP 57452;  need $NOP {headseek4:hds|state.ST_NOP}
set ESFT 57442; need $ESFT {headseek4:hds|esft~1}
set S44 66636;  need $S44 {headseek4:hds|Selector44~0}
set S50 66637;  need $S50 {headseek4:hds|Selector50~1}
if {[get_node_info -node $S44 -info {LUT Mask}] ne "000000000F0F0F0F"} { error "unexpected Selector44~0 mask" }
if {[get_node_info -node $S50 -info {LUT Mask}] ne "00FF00FF10FF10FF"} { error "unexpected Selector50~1 mask" }
if {[src_of $S50 DATAD] != $S44} { error "Selector50~1 DATAD is not Selector44~0" }
if {[src_of $NOP DATAIN] != $S44} { error "state.ST_NOP DATAIN is not Selector44~0" }
if {[src_of $S44 DATAD] ne ""} { error "Selector44~0 DATAD in use" }

# 1) ST_NOP holds until the seek tick: hs_nop_hold = ST_NOP & !esft into Selector44~0's free D pin
set H -1
foreach loc {LABCELL_X85_Y32_N0 LABCELL_X88_Y31_N0} {
    set r -1
    catch {set r [add_new_cell -comb -cell_name hs_nop_hold -location $loc]}
    if {[string is integer -strict $r] && $r >= 0} { set H $r; break }
}
if {$H < 0} { error "no location for hs_nop_hold" }
make_ape_connection -src_node $NOP -src_port [oport_of $NOP {}] -dst_node $H -port_type DATAA
make_ape_connection -src_node $ESFT -src_port [oport_of $ESFT {}] -dst_node $H -port_type DATAB
set outs {}
foreach_in_collection op [get_oports -node $H] { lappend outs [get_port_info -node $H -port_id $op -type oport -info port_type] }
if {[lsearch $outs COMBOUT] < 0} { make_output_port -node $H -port_type COMBOUT }
setmask64 $H 4444444444444444
make_ape_connection -src_node $H -src_port [oport_of $H COMBOUT] -dst_node $S44 -port_type DATAD
setmask64 $S44 00FF00FF0FFF0FFF
# 2) reach on the tick that ends ST_NOP, not when the zero-step seek starts
foreach {t ip sa} [inputs $S50] { if {$t eq "DATAD"} { remove_ape_connection -dst_node $S50 -dst_port $ip } }
make_ape_connection -src_node $NOP -src_port [oport_of $NOP {}] -dst_node $S50 -port_type DATAD
setmask64 $S50 0055005510551055

foreach n [list $H $S44 $S50] {
    puts "[nname $n]: [get_node_info -node $n -info {LUT Mask}] [get_node_info -node $n -info {Combout Equation}]"
    foreach {t ip sa} [inputs $n] { if {$sa ne "" && $sa >= 0} { puts "    $t <- [nname $sa]" } }
}
if {[src_of $H DATAA] != $NOP || [src_of $H DATAB] != $ESFT || [src_of $S44 DATAD] != $H || [src_of $NOP DATAIN] != $S44 || [src_of $S50 DATAD] != $NOP} { error "rewiring failed" }
puts "hs_nop_hold @[get_node_info -node $H -info {Location String}]"
if {![check_netlist_and_save]} { error "ECO netlist check failed" }
puts "ECO_RESULT 1"
