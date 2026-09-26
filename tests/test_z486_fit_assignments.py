"""Guard QSF target spelling and the production preflight's failure modes."""
from pathlib import Path
import tempfile
import tkinter
import unittest

ROOT = Path(__file__).resolve().parents[1]
SCRIPT = ROOT / 'scripts/check-z486-fit-assignments.tcl'
GOOD = '''set_instance_assignment -name QII_AUTO_PACKED_REGISTERS OFF -to "*|ram|FECRDAT*"
'''


class FitAssignments(unittest.TestCase):
    def check(self, qsf=GOOD, missing=False, packing='SPARSE AUTO'):
        t = tkinter.Tcl()
        t.eval('''
            package provide ::quartus::project 1.0
            proc project_open {args} {}
            proc project_close {} {}
            proc get_global_assignment {args} {global packing; return $packing}
            proc get_instance_assignment {args} {
                global missing checked
                lappend checked $args
                if {$missing && [lindex $args 1] eq "ALLOW_SYNCH_CTRL_USAGE"} {return ""}
                return OFF
            }
            set checked {}
        ''')
        t.setvar('missing', int(missing))
        t.setvar('packing', packing)
        # Substitute only the input file location; execute the guard itself.
        with tempfile.TemporaryDirectory() as d:
            p = Path(d) / 'release-Zet98MiSTer.qsf'
            p.write_text(qsf)
            script = SCRIPT.read_text().replace('open release-Zet98MiSTer.qsf r',
                                                'open {' + p.as_posix() + '} r')
            t.eval(script)
        return t

    def test_exact_queries(self):
        t = self.check()
        self.assertEqual(int(t.eval('llength $checked')), 5)
        t.eval('''foreach q $checked {
            if {[lindex $q 2] ne "-to" || [string match {*\{*} [lindex $q 3]]} {error target}
        }''')

    def test_old_braces_rejected(self):
        with self.assertRaisesRegex(tkinter.TclError, 'Braced QSF target'):
            self.check(GOOD.replace('"*|ram|FECRDAT*"', '{*|ram|FECRDAT*}'))

    def test_parser_missing_setting_rejected(self):
        with self.assertRaisesRegex(tkinter.TclError, 'Missing OFF assignment'):
            self.check(missing=True)

    def test_normal_packing_keeps_all_instance_guards(self):
        t = self.check(packing='NORMAL')
        self.assertEqual(int(t.eval('llength $checked')), 5)

    def test_unexpected_packing_rejected(self):
        with self.assertRaisesRegex(tkinter.TclError, 'Unexpected global register packing'):
            self.check(packing='OFF')

    def test_builder_emits_quoted_targets_and_runs_guard_first(self):
        builder = (ROOT / 'scripts/build.ps1').read_text()
        for target in ('*|ram|FECRDAT*', '*|VLINESC*', '*|vlines_pixel_source*'):
            self.assertNotIn('-to {' + target + '}', builder)
            self.assertIn('-to "' + target + '"', builder)
        self.assertIn("check-z486-fit-assignments.tcl && ' + $compileCommand", builder)


if __name__ == '__main__':
    unittest.main()
