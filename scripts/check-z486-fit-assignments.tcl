# SPDX-License-Identifier: GPL-3.0-or-later
# Run before compilation, with Quartus's real QSF parser. QSF braces were
# retained as literal name characters and caused B146/B147 repair settings
# to be silently ignored by synthesis (Critical Warning 136021).
package require ::quartus::project
project_open Zet98 -revision release-Zet98MiSTer
set fh [open release-Zet98MiSTer.qsf r]
set settings [read $fh]
close $fh
set packing [get_global_assignment -name QII_AUTO_PACKED_REGISTERS]
if {$packing ni {NORMAL {SPARSE AUTO}}} {
    error "Unexpected global register packing profile '$packing'"
}
puts "PASS: parsed global register packing $packing"
if {[regexp {set_instance_assignment[^\n]*-to\s+\{} $settings]} {
    error "Braced QSF target: use double quotes, not Tcl brace grouping"
}
foreach {assignment target} {
    QII_AUTO_PACKED_REGISTERS *|vlines_pixel_source*
    QII_AUTO_PACKED_REGISTERS *|VLINESC*
    QII_AUTO_PACKED_REGISTERS *|ram|FECRDAT*
    ALLOW_SYNCH_CTRL_USAGE *|ram|FECRDAT*
    AUTO_CLOCK_ENABLE_RECOGNITION *|ram|FECRDAT*
} {
    set actual [get_instance_assignment -name $assignment -to $target]
    if {![string equal -nocase $actual OFF]} {
        error "Missing OFF assignment for $assignment at exact target $target (got '$actual')"
    }
    puts "PASS: parsed $assignment OFF -to $target"
}
project_close
