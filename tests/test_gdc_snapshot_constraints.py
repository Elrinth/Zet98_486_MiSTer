"""Check the scope of the production GDC snapshot timing exceptions."""
from pathlib import Path
import tkinter
import unittest

SOURCE = Path(__file__).resolve().parents[1]/'Zet98/v17/pc98-video-settings.sdc'


class SnapshotConstraints(unittest.TestCase):
    def evaluate(self, scenario='normal'):
        t = tkinter.Tcl()
        t.setvar('scenario', scenario)
        t.setvar('pegc_enabled', 1)
        t.eval('''
            set exceptions {}; set bounds {}
            proc get_collection_size {x} {llength $x}
            proc get_node_info {x args} {return $x}
            proc foreach_in_collection {name items body} {
                upvar 1 $name item
                foreach item $items {uplevel 1 $body}
            }
            proc get_registers {pattern} {
                global scenario
                foreach field {held_data received_data} {
                    if {[string first $field $pattern]>=0} {
                        set result {}
                        for {set i 0} {$i<128} {incr i} {
                            if {$scenario eq "missing_$field" && $i==62} {continue}
                            if {$scenario eq "missing_atrsel_$field" && $i==121} {continue}
                            if {$scenario eq "missing_pegc_$field" && $i==127} {continue}
                            if {$scenario eq "missing_partition_$field" && $i==100} {continue}
                            lappend result [format {emu|Zet98_top|gdc_settings|%s[%d]} $field $i]
                        }
                        if {$scenario eq "copies"} {
                            lappend result [format {emu|Zet98_top|gdc_settings|%s[62]~DUPLICATE} $field]
                        }
                        return $result
                    }
                }
                return [list $pattern]
            }
            proc get_pins {args} {return {reset0 reset1}}
            proc set_max_delay {args} {global bounds; lappend bounds $args}
            proc set_false_path {args} {global exceptions; lappend exceptions $args}
        ''')
        t.call('source', str(SOURCE))
        return t

    def test_hold_only_and_same_payload_setup_bound(self):
        for scenario in ('normal', 'copies'):
            with self.subTest(scenario=scenario):
                t = self.evaluate(scenario)
                t.eval('''
                    if {[llength $bounds]!=1 || [llength $exceptions]!=5} {error "Exception count"}
                    set max_expected [list -from $settings_payload -to $settings_capture 20.000]
                    set hold_expected [list -hold -from $settings_payload -to $settings_capture]
                    if {[lindex $bounds 0] ne $max_expected} {error "Setup bound changed"}
                    if {[lindex $exceptions 0] ne $hold_expected} {error "Hold scope changed"}
                    foreach path [lrange $exceptions 1 end] {
                        if {[string first held_data $path]>=0 || [string first received_data $path]>=0} {
                            error "Unbounded payload exception"
                        }
                    }
                ''')
                self.assertEqual(int(t.eval('llength $settings_payload')),129 if scenario=='copies' else 128)

    def test_missing_payload_bit_aborts(self):
        for scenario in ('missing_held_data', 'missing_received_data', 'missing_atrsel_held_data', 'missing_atrsel_received_data',
                         'missing_pegc_held_data', 'missing_pegc_received_data', 'missing_partition_held_data', 'missing_partition_received_data'):
            with self.subTest(scenario=scenario), self.assertRaises(tkinter.TclError):
                self.evaluate(scenario)


if __name__ == '__main__':
    unittest.main()
