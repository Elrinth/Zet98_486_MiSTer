# B278 release bitstream: B277's placed and routed database (seed 4, release-Zet98MiSTer.rbf md5
# a422e916...) with the PCM86 below-threshold refill interrupt (rtl/pcm86.sv low_fire) added.
#
# Ultima VIII starts every speech sample with playback and interrupts on: FIFO reset, then 256
# bytes against a 768-byte threshold, and it feeds the rest from the PCM interrupt. B277 sends
# that interrupt only when the level falls from above the threshold or on an enable write, so
# the speech never continued and the intro stopped. NP2kai interrupts once such a burst is
# written. New logic beside the untouched (retimed) request logic:
#
#   u8_pushed (FF) <= push | (u8_pushed & !tick)               FIFO data since the last sample tick
#   u8_arm    (FF) <= !(reset | FIFO reset) & (push | (u8_arm & !irq_line))
#   u8_fire   (FF) <= irq_pending~3 & control[5] & u8_arm & !u8_pushed
#                     (irq_pending~3 = sample tick & control[7] & !control[6] & count<=threshold)
#   u8_hold   (FF) <= irq_line | u8_fire
#   irq_line~1 DATAD: irq_line_NEW_REG14055 -> u8_hold   (mask unchanged: !F & !C & (D | A))
#
# irq_line~1 is the retimed irq_line: D = its hold register (irq_line_NEW_REG14055 <= irq_line~1),
# A = the registered original fire, C/F = the registered clears. u8_hold takes over the hold and
# also sets irq_line after u8_fire, so the existing acknowledgement and FIFO-reset clears end it
# as for the original fire. irq_line~1 can take no new input (its ALM partner irq_gap[0]~1 leaves
# no shared A-C pin; Error 170208), but D is the cell's own pin. tick = !LessThan0~5,
# push = push~1, reset | FIFO reset = pop~0.
#
# Placement: each new LUT shares an otherwise empty ALM with its register, in LABs already
# clocked by the same PLL output. Free ALMs are scarce (155 on the device). hold and pushed sit in
# LAB X53_Y14 (hold close to irq_line~1), fire in X62_Y5, arm in X34_Y11. Refused earlier: X70_Y23
# (Error 170070), X46_Y34 (another clock: router internal error), and all four LUTs in X53_Y14
# with six new inputs (LAB block interconnect conflict).
#
# Run from Zet98/v17 of the B277 seed 4 tree (docker image zet98-b277-eco:1), then:
#   quartus_cdb -t ../../scripts/eco-b278-pcm-refill.tcl
#   quartus_asm Zet98 -c release-Zet98MiSTer
package require ::quartus::chip_planner
project_open Zet98 -revision release-Zet98MiSTer
read_netlist

proc nname {n} { return [string map {"|sys_top|emu:emu|Zet98MiSTer:Zet98_top|" ""} [get_node_info -node $n -info full_name]] }
proc need {n suffix} {
    set nm [nname $n]
    # literal suffix (string match would read [5] as a character class)
    if {[string range $nm end-[expr {[string length $suffix] - 1}] end] ne $suffix} { error "node $n is $nm, not $suffix: not the B277 database" }
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
proc conn {src dst type {stype ""}} {
    make_ape_connection -src_node $src -src_port [oport_of $src $stype] -dst_node $dst -port_type $type
}
proc newcell {kind name loc} {
    set r -1
    catch {set r [add_new_cell $kind -cell_name $name -location $loc]}
    if {![string is integer -strict $r] || $r < 0} { error "add_new_cell $kind $name at $loc failed: $r" }
    set outs {}
    foreach_in_collection op [get_oports -node $r] { lappend outs [get_port_info -node $r -port_id $op -type oport -info port_type] }
    set want [expr {$kind eq "-ff" ? "REGOUT" : "COMBOUT"}]
    if {[lsearch $outs $want] < 0} { make_output_port -node $r -port_type $want }
    return $r
}

set L1   57594;  need $L1   {board86:pcm|irq_line~1}
set HOLD 111348; need $HOLD {board86:pcm|irq_line_NEW_REG14055}
set PUSH 57570;  need $PUSH {board86:pcm|push~1}
set LT0  67361;  need $LT0  {board86:pcm|LessThan0~5}
set IP3  69550;  need $IP3  {board86:pcm|irq_pending~3}
set C5   559187; need $C5   {board86:pcm|control[5]~DUPLICATE}
set POP  57590;  need $POP  {board86:pcm|pop~0}
set CLKN 103512; need $CLKN {outclk_wire[1]~CLKENA0}
if {[get_node_info -node $L1 -info {LUT Mask}] ne "50F050F000000000"} { error "unexpected irq_line~1 mask" }
if {[get_node_info -node $IP3 -info {LUT Mask}] ne "00000000D450D450"} { error "unexpected irq_pending~3 mask" }
if {[get_node_info -node $POP -info {LUT Mask}] ne "FF00FF00FF0FFF0F"} { error "unexpected pop~0 mask" }
if {[src_of $L1 DATAD] != $HOLD} { error "irq_line~1 DATAD is not irq_line_NEW_REG14055" }
if {[src_of $HOLD DATAIN] != $L1} { error "irq_line_NEW_REG14055 DATAIN is not irq_line~1" }

# 1) the cells: each LUT with its register in an otherwise empty ALM
set HD [newcell -comb u8_hold_d   LABCELL_X53_Y14_N0]
set HQ [newcell -ff   u8_hold     FF_X53_Y14_N1]
set PD [newcell -comb u8_pushed_d LABCELL_X53_Y14_N6]
set PQ [newcell -ff   u8_pushed   FF_X53_Y14_N7]
set FD [newcell -comb u8_fire_d   LABCELL_X62_Y5_N54]
set FQ [newcell -ff   u8_fire     FF_X62_Y5_N55]
set AD [newcell -comb u8_arm_d    MLABCELL_X34_Y11_N24]
set AQ [newcell -ff   u8_arm      FF_X34_Y11_N25]
foreach {d q} [list $HD $HQ $PD $PQ $FD $FQ $AD $AQ] {
    conn $CLKN $q CLK CLK
    conn $d $q DATAIN COMBOUT
}
# 2) u8_pushed_d = push | (u8_pushed & !tick)        A = push~1, B = u8_pushed, C = LessThan0~5
conn $PUSH $PD DATAA
conn $PQ   $PD DATAB REGOUT
conn $LT0  $PD DATAC
setmask64 $PD 5757575757575757
# 3) u8_arm_d = !pop~0 & (push | (u8_arm & !irq_line))   A = pop~0, B = push~1, C = u8_arm, D = irq_line~1
conn $POP  $AD DATAA
conn $PUSH $AD DATAB
conn $AQ   $AD DATAC REGOUT
conn $L1   $AD DATAD
setmask64 $AD 2A222A222A222A22
# 4) u8_fire_d = irq_pending~3 & control[5] & u8_arm & !u8_pushed
#    A = irq_pending~3, B = control[5], C = u8_arm, D = u8_pushed
conn $IP3 $FD DATAA
conn $C5  $FD DATAB REGOUT
conn $AQ  $FD DATAC REGOUT
conn $PQ  $FD DATAD REGOUT
setmask64 $FD 0100010001000100
# 5) u8_hold_d = irq_line | u8_fire                   A = u8_fire, F = irq_line~1
conn $FQ $HD DATAA REGOUT
conn $L1 $HD DATAF
setmask64 $HD 55555555FFFFFFFF
# 6) irq_line~1 holds through u8_hold (its own D pin; mask unchanged)
foreach {t ip sa} [inputs $L1] { if {$t eq "DATAD"} { remove_ape_connection -dst_node $L1 -dst_port $ip } }
conn $HQ $L1 DATAD REGOUT
if {[get_node_info -node $L1 -info {LUT Mask}] ne "50F050F000000000"} { setmask64 $L1 50F050F000000000 }

foreach n [list $HD $PD $FD $AD $L1] {
    puts "[nname $n] @[get_node_info -node $n -info {Location String}]: [get_node_info -node $n -info {LUT Mask}] [get_node_info -node $n -info {Combout Equation}]"
    foreach {t ip sa} [inputs $n] { if {[string is integer -strict $sa] && $sa >= 0} { puts "    $t <- [nname $sa]" } }
}
foreach q [list $HQ $PQ $FQ $AQ] {
    puts "[nname $q] @[get_node_info -node $q -info {Location String}]"
    foreach {t ip sa} [inputs $q] { if {[string is integer -strict $sa] && $sa >= 0} { puts "    $t <- [nname $sa]" } }
}
if {[src_of $HQ DATAIN] != $HD || [src_of $PQ DATAIN] != $PD || [src_of $FQ DATAIN] != $FD || [src_of $AQ DATAIN] != $AD || [src_of $L1 DATAD] != $HQ || [src_of $HD DATAA] != $FQ || [src_of $FD DATAC] != $AQ || [src_of $AD DATAD] != $L1} { error "wiring check failed" }
if {![check_netlist_and_save]} { error "ECO netlist check failed" }
puts "ECO_RESULT 1"
