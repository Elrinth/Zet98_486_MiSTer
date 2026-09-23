# SPDX-License-Identifier: GPL-3.0-or-later
# Run with quartus_cdb after fitting the explicit CPU ready-mux build.
package require ::quartus::project
package require ::quartus::atoms
project_open Zet98 -revision release-Zet98MiSTer
read_atom_netlist -type cmp
set bits [dict create]
foreach_in_collection node [get_atom_nodes] {
    set name [get_atom_node_info -node $node -key NAME]
    if {[string match {*decode_regs_inst*} $name] &&
        ([regexp {ready_mux\[([0-9]+)\]\.mux} $name -> bit] ||
         [regexp {selected_step\[([0-9]+)\]} $name -> bit])} {
        dict set bits $bit [get_atom_node_info -node $node -key TYPE]
    }
}
set missing [list]
for {set bit 0} {$bit < 104} {incr bit} {
    if {![dict exists $bits $bit]} {lappend missing $bit}
}
puts "Ready mux atom indices found: [dict size $bits]"
puts "Ready mux atom types: [lsort -unique [dict values $bits]]"
if {[llength $missing]} {
    puts "Indices absent or renamed/optimized: $missing"
    error "Inspect fitted mux coverage before treating this check as passed"
}
puts "PASS: all 104 CPU ready mux output indices found in fitted netlist"
project_close
