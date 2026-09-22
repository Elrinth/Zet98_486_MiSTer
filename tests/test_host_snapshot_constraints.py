"""Execute the production Tcl guards against representative register collections.

This checks guard/exception scope, not fitter timing or metastability behavior.
Windows Python's bundled Tcl suffices; actual TimeQuest is still required.
"""
from pathlib import Path
import tkinter
import unittest

SOURCE = Path(__file__).resolve().parents[1]/'Zet98/v17/pc98-host-video-settings.sdc'
TARGET = 'emu|hdmi_scale|host_scale_settings|request'
FIRST = 'emu|hdmi_scale|host_scale_settings|request_sync[0]'


class ConstraintGuards(unittest.TestCase):
    def run_sdc(self, scenario):
        t = tkinter.Tcl()
        t.setvar('scenario', scenario)
        t.setvar('launch_target', TARGET)
        t.setvar('first_target', FIRST)
        t.eval('''
            set exceptions {}
            proc post_message {args} {}
            proc set_max_delay {args} {}
            proc get_collection_size {collection} {llength $collection}
            proc get_registers {args} {
                global scenario launch_target first_target
                set name [lindex $args end]
                set original_only [expr {[lindex $args 0] eq "-no_duplicates"}]
                if {$name eq $launch_target} {
                    if {$scenario eq "missing_launch"} {return {}}
                    if {$scenario eq "ambiguous_original"} {return [list $name unexpected]}
                    if {$scenario eq "duplicate_launch" && !$original_only} {
                        return [list $name ${name}~DUPLICATE]
                    }
                }
                if {$name eq $first_target} {
                    if {$scenario eq "missing_first"} {return {}}
                    if {$scenario eq "duplicated_first"} {return [list $name ${name}~DUPLICATE]}
                }
                if {$scenario eq "missing_payload" && [string match {*held_data*} $name]} {return {}}
                return [list $name]
            }
            proc set_false_path {args} {global exceptions; lappend exceptions $args}
        ''')
        t.call('source', str(SOURCE))
        return t

    def test_single_launch(self):
        t=self.run_sdc('normal')
        self.assertEqual(int(t.eval('llength $exceptions')),17)  # four holds, eight controls, five one-bit hints

    def test_all_physical_launch_copies_get_only_first_stage_exception(self):
        t=self.run_sdc('duplicate_launch')
        t.eval('''
            set found 0
            foreach path $exceptions {
                if {[lindex $path 0] eq "-from" && [lindex $path 1] eq [list $launch_target ${launch_target}~DUPLICATE]} {
                    if {[lindex $path 2] ne "-to" || [lindex $path 3] ne [list $first_target]} {
                        error "Duplicate exception escaped first stage"
                    }
                    incr found
                }
            }
        ''')
        self.assertEqual(int(t.getvar('found')),1)

    def test_missing_or_ambiguous_endpoints_still_abort(self):
        for scenario in ('missing_launch','ambiguous_original','missing_first','duplicated_first','missing_payload'):
            with self.subTest(scenario=scenario), self.assertRaises(tkinter.TclError):
                self.run_sdc(scenario)


if __name__=='__main__':
    unittest.main()
