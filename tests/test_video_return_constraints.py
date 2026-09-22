"""Execute exact production SDC against representative endpoint inventories."""
from pathlib import Path
import tkinter
import unittest

ROOT = Path(__file__).resolve().parents[1] / 'Zet98/v17'


class Guards(unittest.TestCase):
    def run_sdc(self, name, bad=''):
        t = tkinter.Tcl()
        t.setvar('bad', bad)
        t.eval('''
            set exceptions {}
            set bounds {}
            proc get_collection_size {x} {llength $x}
            proc get_registers {pattern} {
                global bad
                if {$bad ne "" && [string first $bad $pattern]>=0} {return {}}
                set count 1
                if {[string first "hdmi_out_vs" $pattern]>=0} {set count 2}
                if {[string first "retrace_status" $pattern]>=0} {set count 2}
                if {[string first "|ram|" $pattern]>=0} {set count 16}
                set result {}
                for {set i 0} {$i<$count} {incr i} {lappend result "${pattern}:$i"}
                return $result
            }
            proc set_false_path {args} {global exceptions; lappend exceptions $args}
            proc set_max_delay {args} {global bounds; lappend bounds $args}
        ''')
        t.call('source', str(ROOT / name))
        return t

    def test_video_only_first_stages_are_excluded(self):
        t = self.run_sdc('pc98-video-status.sdc')
        self.assertEqual(int(t.eval('llength $exceptions')), 2)
        t.eval('''
            foreach path $exceptions {
                if {[lindex $path 0] ne "-from" || [lindex $path 2] ne "-to"} {error scope}
                set target [lindex $path 3]
                if {[string first "meta" $target]<0 || [string first "sync" $target]>=0} {error stage}
            }
        ''')

    def test_return_data_remains_bounded(self):
        t = self.run_sdc('pc98-read-transfer.sdc')
        self.assertEqual(int(t.eval('llength $exceptions')), 0)
        self.assertEqual(int(t.eval('llength $bounds')), 4)
        t.eval('foreach bound $bounds {if {[lindex $bound end] != 5.0} {error bound}}')

    def test_missing_endpoints_abort(self):
        for bad in ['hdmi_out_vs','hdmi_vs_meta','hdmi_vs_sync','source_status','status_meta','status_sync']:
            with self.subTest(bad=bad), self.assertRaises(tkinter.TclError):
                self.run_sdc('pc98-video-status.sdc', bad)
        for bad in ['fde_read_data','fec_read_data','FDERDAT','FECRDAT']:
            with self.subTest(bad=bad), self.assertRaises(tkinter.TclError):
                self.run_sdc('pc98-read-transfer.sdc', bad)


if __name__ == '__main__':
    unittest.main()
