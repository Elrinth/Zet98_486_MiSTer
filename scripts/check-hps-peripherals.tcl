# SPDX-License-Identifier: GPL-3.0-or-later
# Inspect actual fitted primitives, not just requested QSF assignments.
# Optional argument 1 requires UART1 as well as the shared SPI/HDMI routes.
package require ::quartus::project
package require ::quartus::atoms
if {[llength $argv] > 1} {error "Usage: check-hps-peripherals.tcl ?require_uart?"}
set require_uart 0
if {[llength $argv]} {set require_uart [lindex $argv 0]}
if {$require_uart ni {0 1}} {error "require_uart must be 0 or 1"}
set expected [dict create \
    spi {HPS_INTERFACE_PERIPHERAL_SPI_MASTER HPSINTERFACEPERIPHERALSPIMASTER_X52_Y72_N111} \
    hdmi_i2c {HPS_INTERFACE_PERIPHERAL_I2C HPSINTERFACEPERIPHERALI2C_X52_Y60_N111}]
if {$require_uart} {
    dict set expected uart {HPS_INTERFACE_PERIPHERAL_UART HPSINTERFACEPERIPHERALUART_X52_Y67_N111}
}
project_open Zet98 -revision release-Zet98MiSTer
read_atom_netlist -type cmp
set found [dict create]
foreach_in_collection node [get_atom_nodes] {
    set name [get_atom_node_info -node $node -key NAME]
    if {[dict exists $expected $name]} {
        set kind [get_atom_node_info -node $node -key TYPE]
        set location [get_atom_node_info -node $node -key LOCATION]
        if {[list $kind $location] ne [dict get $expected $name]} {
            error "HPS peripheral $name is misplaced: $kind at $location"
        }
        dict incr found $name
    }
}
dict for {name assignment} $expected {
    if {![dict exists $found $name] || [dict get $found $name] != 1} {
        error "Expected exactly one fitted HPS peripheral $name"
    }
    puts "PASS: fitted $name at [lindex $assignment 1]"
}
project_close
