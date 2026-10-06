import importlib.util
from pathlib import Path
import unittest

spec = importlib.util.spec_from_file_location('install',
    Path(__file__).resolve().parents[1] / 'scripts/mister_midi_install.py')
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)


class StartupTest(unittest.TestCase):
    def test_idempotent_and_reversible(self):
        original = '#!/bin/sh\necho unrelated\n'
        installed = module.startup_text(original, True)
        self.assertEqual(module.startup_text(installed, True), installed)
        self.assertEqual(module.startup_text(installed, False).strip(), original.strip())
        self.assertEqual(installed.count(module.BEGIN), 1)

    def test_preserve_final_exit(self):
        original = '#!/bin/sh\necho unrelated\nexit 0\n'
        installed = module.startup_text(original, True)
        self.assertTrue(installed.endswith('exit 0\n'))
        self.assertEqual(module.startup_text(installed, False), original)

    def test_migrate_earlier_helper_only(self):
        original = '#!/bin/sh\necho unrelated\n' + module.OLD
        installed = module.startup_text(original, True)
        self.assertNotIn('PC98_MIDI_Timing.py', installed)
        self.assertIn('echo unrelated', installed)

    def test_incomplete_marker_fails_without_rewriting(self):
        with self.assertRaises(ValueError):
            module.startup_text('#!/bin/sh\n' + module.BEGIN, True)


if __name__ == '__main__':
    unittest.main()
