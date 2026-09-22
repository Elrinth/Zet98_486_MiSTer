"""Execute exact production SDC against representative endpoint inventories."""
from pathlib import Path
import tkinter
import unittest

ROOT = Path(__file__).resolve().parents[1] / 'Zet98/v17'


class Guards(unittest.TestCase):
    def run_sdc(self, name, bad='', missing_bit=False, extra_bit=False,
                duplicates=False, missing_target=False):
        t = tkinter.Tcl()
        t.setvar('bad', bad)
        names = ['hdmi_out_vs', 'hdmi_out_vs~Duplicate_1', 'hdmi_vs_meta', 'hdmi_vs_sync']
        for signal in ['source_status', 'status_meta', 'status_sync']:
            names += [f'emu|Zet98_top|retrace_status|{signal}[{bit}]' for bit in range(2)]
        for port, width in [('cpu', 64), ('sub', 64), ('fde', 10), ('fec', 16)]:
            for signal in [f'{port}_read_words' if port in ('cpu', 'sub') else f'{port}_read_data',
                           f'{port.upper()}RDAT']:
                count = width
                if port == 'fde' and signal == 'fde_read_data':
                    count += int(extra_bit) - int(missing_bit)
                names += [f'emu|Zet98_top|ram|{signal}[{bit}]' for bit in range(count)]
        if missing_target:
            names.remove('emu|Zet98_top|ram|FDERDAT[6]')
        if duplicates:
            names += [f'emu|Zet98_top|ram|FDERDAT[{bit}]~DUPLICATE' for bit in (7, 8, 9)]
            names += ['emu|Zet98_top|ram|fec_read_data[15]~Duplicate_1']
        t.setvar('inventory', tuple(names))
        t.eval('''
            set exceptions {}
            set bounds {}
            proc get_collection_size {x} {llength $x}
            proc get_node_info {node args} {return $node}
            proc foreach_in_collection {var nodes body} {
                upvar 1 $var item
                foreach item $nodes {uplevel 1 $body}
            }
            proc get_registers {pattern} {
                global bad inventory
                if {$bad ne "" && [string first $bad $pattern]>=0} {return {}}
                set result {}
                foreach node $inventory {
                    if {[string match $pattern $node]} {lappend result $node}
                }
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

    def test_missing_live_fde_bit_aborts(self):
        with self.assertRaises(tkinter.TclError):
            self.run_sdc('pc98-read-transfer.sdc', missing_bit=True)

    def test_unexpected_fde_width_aborts(self):
        with self.assertRaises(tkinter.TclError):
            self.run_sdc('pc98-read-transfer.sdc', extra_bit=True)

    def test_routing_duplicates_are_all_bounded(self):
        t = self.run_sdc('pc98-read-transfer.sdc', duplicates=True)
        self.assertEqual(int(t.eval('llength $exceptions')), 0)
        # Exact post-fit FDE inventory: ten logical bits, thirteen captures.
        self.assertEqual(int(t.eval('llength [lindex [lindex $bounds 2] 3]')), 13)
        t.eval('foreach bound $bounds {if {[lindex $bound end] != 5.0} {error bound}}')

    def test_duplicate_cannot_conceal_missing_capture(self):
        with self.assertRaises(tkinter.TclError):
            self.run_sdc('pc98-read-transfer.sdc', duplicates=True, missing_target=True)


if __name__ == '__main__':
    unittest.main()
