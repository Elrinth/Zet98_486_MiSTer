"""Run production PEGC CDC constraints against representative fitted endpoints."""
from pathlib import Path
import tkinter
import unittest

SOURCE = Path(__file__).resolve().parents[1] / 'Zet98/v17/pc98-pegc-transfer.sdc'


class PegcConstraints(unittest.TestCase):
    def evaluate(self, missing='', copies=False):
        names = [f'emu|Zet98_top|packed_fetch|request_payload[{i}]' for i in range(18)]
        names += [f'emu|Zet98_top|packed_fetch|next_address[{i}]' for i in range(3, 19)]
        names += [f'emu|Zet98_top|packed_fetch|{n}' for n in
                  ('write_bank', 'wrap_page', 'request_toggle', 'acknowledge_toggle',
                   'request_sync[0]', 'request_sync[1]', 'acknowledge_sync[0]', 'acknowledge_sync[1]')]
        # Unrelated endpoint deliberately shares the signal name suffix.
        names += ['emu|another_block|request_payload[0]', 'emu|another_block|next_address[3]']
        if copies:
            names += ['emu|Zet98_top|packed_fetch|request_payload[2]~DUPLICATE',
                      'emu|Zet98_top|packed_fetch|next_address[5]~DUPLICATE']
        if missing:
            stem = 'emu|Zet98_top|packed_fetch|' + missing
            names = [name for name in names if name != stem and not name.startswith(stem + '~')]
        t = tkinter.Tcl()
        t.setvar('inventory', tuple(names))
        pins = [f'emu|Zet98_top|packed_fetch|{chain}[{i}]|clrn'
                for chain in ('cpu_reset_sync', 'video_reset_sync') for i in range(2)]
        pins += ['emu|another_block|cpu_reset_sync[0]|clrn',
                 'emu|Zet98_top|packed_fetch|display_bank|clrn',
                 'emu|Zet98_top|packed_fetch|request_sync[0]|clrn']
        t.setvar('pins', tuple(p for p in pins if not missing or missing not in p))
        t.setvar('missing', missing)
        t.eval('''
            set bounds {}; set minima {}; set exceptions {}
            proc get_collection_size {x} {llength $x}
            proc get_node_info {x args} {return $x}
            proc foreach_in_collection {name items body} {
                upvar 1 $name item
                foreach item $items {uplevel 1 $body}
            }
            proc get_registers {patterns} {
                global inventory
                set result {}
                foreach pattern $patterns {
                    # TimeQuest names use literal bus indices, unlike Tcl glob brackets.
                    set pattern [string map [list {[} {\[} {]} {\]}] $pattern]
                    foreach node $inventory {
                        if {[string match $pattern $node]} {lappend result $node}
                    }
                }
                return $result
            }
            proc set_max_delay {args} {global bounds; lappend bounds $args}
            proc get_pins {args} {
                global pins
                set pattern [lindex $args end]
                set result {}
                foreach pin $pins {
                    if {[string match $pattern $pin]} {lappend result $pin}
                }
                return $result
            }
            proc set_min_delay {args} {global minima; lappend minima $args}
            proc set_false_path {args} {global exceptions; lappend exceptions $args}
        ''')
        t.call('source', str(SOURCE))
        return t

    def test_complete_payload_is_bounded_in_both_directions(self):
        for copies in (False, True):
            t = self.evaluate(copies=copies)
            self.assertEqual(int(t.eval('llength $pegc_request')), 18 + copies)
            self.assertEqual(int(t.eval('llength $pegc_capture')), 18 + copies)
            t.eval('''
                if {$bounds ne [list [list -from $pegc_request -to $pegc_capture 20.000]]} {error maximum}
                if {$minima ne [list [list -from $pegc_request -to $pegc_capture 0.500]]} {error minimum}
                if {[llength $exceptions]!=4} {error count}
                foreach path [lrange $exceptions 0 1] {
                    if {[lindex $path 0] ne "-from" || [lindex $path 2] ne "-to"} {error scope}
                    set target [lindex [lindex $path 3] 0]
                    if {![string match {*_sync\[0\]} $target]} {error stage}
                    if {[string first "payload" $path]>=0 || [string first "next_address" $path]>=0} {error payload_exception}
                }
                foreach path [lrange $exceptions 2 end] {
                    if {[lindex $path 0] ne "-to" || [llength [lindex $path 1]]!=2} {error reset_scope}
                    foreach node [lindex $path 1] {
                        if {[string first "reset_sync" $node]<0 || [string first "|clrn" $node]<0} {error reset_pin}
                    }
                }
            ''')

    def test_missing_any_payload_bit_is_rejected(self):
        for field, indices in [('request_payload', range(1, 18)), ('next_address', range(4, 19))]:
            for index in indices:
                with self.subTest(field=field, index=index), self.assertRaises(tkinter.TclError):
                    self.evaluate(f'{field}[{index}]', copies=True)

    def test_only_proven_alignment_constants_may_be_folded(self):
        for field in ('request_payload[0]', 'next_address[3]'):
            self.evaluate(field)

    def test_missing_flags_or_controls_are_rejected(self):
        for field in ('write_bank', 'wrap_page', 'request_toggle', 'acknowledge_toggle',
                      'request_sync[0]', 'acknowledge_sync[0]'):
            with self.subTest(field=field), self.assertRaises(tkinter.TclError):
                self.evaluate(field)

    def test_missing_reset_chains_are_rejected(self):
        for chain in ('cpu_reset_sync', 'video_reset_sync', 'cpu_reset_sync[0]', 'video_reset_sync[1]'):
            with self.subTest(chain=chain), self.assertRaises(tkinter.TclError):
                self.evaluate(chain)


if __name__ == '__main__':
    unittest.main()
