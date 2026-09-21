# SPDX-License-Identifier: GPL-3.0-or-later
# Inspect the actual fitted primitive, not just the requested QSF assignment.
package require ::quartus::project
package require ::quartus::atoms
project_open Zet98 -revision release-Zet98MiSTer
read_atom_netlist -type cmp
set found 0
foreach_in_collection node [get_atom_nodes] {
    if {[get_atom_node_info -node $node -key NAME] eq "uart"} {
        set kind [get_atom_node_info -node $node -key TYPE]
        set location [get_atom_node_info -node $node -key LOCATION]
        if {$kind ne "HPS_INTERFACE_PERIPHERAL_UART" ||
            $location ne "HPSINTERFACEPERIPHERALUART_X52_Y67_N111"} {
            error "MIDI UART is misplaced: $kind at $location; expected HPS UART1"
        }
        incr found
    }
}
if {$found != 1} {error "Expected one fitted HPS UART1, found $found"}
puts "PASS: fitted MIDI UART connects to HPS UART1 (/dev/ttyS1)"
project_close
