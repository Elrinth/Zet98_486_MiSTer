# Verify physical FEC return buffers survived optimization; timing is checked separately.
package require ::quartus::project
package require ::quartus::atoms
project_open Zet98 -revision release-Zet98MiSTer
read_atom_netlist -type cmp
set found [dict create]
foreach_in_collection node [get_atom_nodes] {
    set name [get_atom_node_info -node $node -key NAME]
    if {[string match {*fec_hold_stages*routed*} $name]} {
        set kind [get_atom_node_info -node $node -key TYPE]
        if {$kind ne "LCELL_COMB"} {error "Unexpected FEC route atom $kind: $name"}
        if {![regexp {fec_hold_stages:([0-3]):fec_hold_bits:([0-9]+):routed$} $name all stage bit]} {
            error "Unexpected FEC route atom name: $name"
        }
        if {$bit > 15} {error "Unexpected FEC route bit: $name"}
        dict incr found "$stage,$bit"
        puts "FEC_ROUTE_ATOM $kind $name"
    }
}
for {set stage 0} {$stage < 4} {incr stage} {
    for {set bit 0} {$bit < 16} {incr bit} {
        set key "$stage,$bit"
        if {![dict exists $found $key] || [dict get $found $key] != 1} {
            error "Expected exactly one FEC route cell at $key"
        }
    }
}
puts "PASS FEC_ROUTE_ATOMS 64 (four stages for each of sixteen bits)"
project_close
