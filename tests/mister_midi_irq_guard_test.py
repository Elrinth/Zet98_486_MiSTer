"""Lifecycle checks for the host IRQ fix; never touches real /proc."""
import importlib.util
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch
from types import SimpleNamespace

spec = importlib.util.spec_from_file_location(
    'guard', Path(__file__).resolve().parents[1] / 'scripts/mister_midi_irq_guard.py')
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)


class GuardTest(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.core = self.root / 'CORENAME'
        self.core.write_text('PC98')
        self.interrupts = self.root / 'interrupts'
        self.interrupts.write_text(' CPU0 CPU1\n50: 100 0 GIC-0 160 Level ffb40000.usb, dwc2_hsotg:usb1\n')
        self.affinity = self.root / 'irq/50/smp_affinity'
        self.affinity.parent.mkdir(parents=True)
        self.affinity.write_text('3\n')
        self.guard = module.Guard(self.root, self.core, lambda _: None)

    def test_core_lifecycle_and_restart(self):
        self.core.write_text('MENU')
        self.guard.poll()
        self.assertEqual(self.affinity.read_text().strip(), '3')
        self.core.write_text('PC98')
        self.guard.poll()
        self.assertEqual(self.affinity.read_text().strip(), '2')
        self.guard.poll()
        self.guard.restore()
        self.assertEqual(self.affinity.read_text().strip(), '3')
        self.guard.poll()
        self.core.write_text('ao486')
        self.guard.poll()
        self.assertEqual(self.affinity.read_text().strip(), '3')

    def test_preserves_admin_change(self):
        self.guard.poll()
        self.affinity.write_text('1\n')
        self.guard.restore()
        self.assertEqual(self.affinity.read_text().strip(), '1')

    def test_does_not_claim_existing_isolation(self):
        self.affinity.write_text('2\n')
        self.guard.poll()
        self.assertIsNone(self.guard.saved)
        self.core.unlink()
        self.guard.poll()
        self.assertEqual(self.affinity.read_text().strip(), '2')

    def test_refuses_ambiguous_or_single_cpu_layout(self):
        for text in (' CPU0\n50: 100 GIC ffb40000.usb\n',
                     ' CPU0 CPU1\n50: 100 0 GIC some_other_device\n',
                     ' CPU0 CPU1\n50: 1 0 GIC ffb40000.usb\n51: 2 0 GIC ffb40000.usb\n'):
            self.interrupts.write_text(text)
            self.guard.poll()
            self.assertEqual(self.affinity.read_text().strip(), '3')

    def test_restores_on_missing_core_name(self):
        self.guard.poll()
        self.core.unlink()
        self.guard.poll()
        self.assertEqual(self.affinity.read_text().strip(), '3')


class PriorityTest(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        for tid, name in ((100, 'midilink'), (200, 'fluidsynth'), (201, 'alsa-midi-seq')):
            folder = self.root / str(tid)
            folder.mkdir()
            (folder / 'comm').write_text(name)
            (folder / 'stat').write_text('%d (%s) S %s%d' % (tid, name, '0 '*18, tid))
        task = self.root / '200/task/201'
        task.mkdir(parents=True)
        (task / 'comm').write_text('alsa-midi-seq')
        self.policies = {100: (0, 0), 201: (1, 50)}
        self.affinities = {100: {0}, 201: {0}}
        self.scheduler = SimpleNamespace(
            SCHED_FIFO=1,
            sched_getaffinity=lambda tid: self.affinities[tid].copy(),
            sched_setaffinity=lambda tid, cpus: self.affinities.update({tid: set(cpus)}),
            sched_getscheduler=lambda tid: self.policies[tid][0],
            sched_getparam=lambda tid: SimpleNamespace(sched_priority=self.policies[tid][1]),
            sched_param=lambda priority: SimpleNamespace(sched_priority=priority),
            sched_setscheduler=lambda tid, policy, param: self.policies.update(
                {tid: (policy, param.sched_priority)}))
        self.guard = module.MidiPriorities(self.root, self.scheduler, lambda _: None)

    def test_restore_original_policies_after_repeated_polls(self):
        self.guard.poll(True)
        self.guard.poll(True)
        self.assertEqual(self.policies, {100: (1, 65), 201: (1, 70)})
        self.guard.poll(False)
        self.assertEqual(self.policies, {100: (0, 0), 201: (1, 50)})

    def test_preserves_reused_pid_and_admin_priority(self):
        self.guard.poll(True)
        (self.root / '100/stat').write_text('100 (other) S ' + '0 '*18 + '999')
        self.policies[201] = (1, 55)
        self.guard.restore()
        self.assertEqual(self.policies, {100: (1, 65), 201: (1, 55)})

    def test_already_configured_thread_is_not_owned(self):
        self.policies[100] = (1, 65)
        self.guard.poll(True)
        self.guard.restore()
        self.assertEqual(self.policies, {100: (1, 65), 201: (1, 50)})

    def test_process_disappearing_during_scan_does_not_stop_service(self):
        read_text = Path.read_text
        def racing_read(path, *args, **kwargs):
            if path == self.root / '100/comm':
                raise ProcessLookupError('process exited during proc read')
            return read_text(path, *args, **kwargs)
        with patch.object(Path, 'read_text', racing_read):
            self.guard.poll(True)
        self.assertEqual(self.policies, {100: (0, 0), 201: (1, 70)})
        self.guard.poll(True)
        self.assertEqual(self.policies, {100: (1, 65), 201: (1, 70)})

    def test_restore_midi_affinity_after_dual_cpu_launch(self):
        self.affinities[201] = {0, 1}
        self.policies[201] = (1, 70)
        self.guard.poll(True)
        self.assertEqual(self.affinities[201], {0})
        self.guard.restore()
        self.assertEqual(self.affinities[201], {0, 1})

    def test_preserve_admin_affinity_and_reused_pid(self):
        self.affinities = {100: {0, 1}, 201: {0, 1}}
        self.guard.poll(True)
        self.affinities[201] = {1}
        (self.root / '100/stat').write_text('100 (other) S ' + '0 '*18 + '999')
        self.guard.restore()
        self.assertEqual(self.affinities, {100: {0}, 201: {1}})

    def test_render_workers_separate_and_restore(self):
        for tid, name in ((202, 'alsa-audio'), (203, 'mixer0')):
            folder = self.root / str(tid)
            folder.mkdir()
            (folder / 'stat').write_text('%d (%s) S %s%d' % (tid, name, '0 '*18, tid))
            task = self.root / ('200/task/%d' % tid)
            task.mkdir()
            (task / 'comm').write_text(name)
            self.policies[tid] = (1, 60)
            self.affinities[tid] = {0, 1}
        self.guard.poll(True)
        self.assertEqual(self.affinities[202], {0})
        self.assertEqual(self.affinities[203], {1})
        self.guard.restore()
        self.assertEqual(self.affinities[202], {0, 1})
        self.assertEqual(self.affinities[203], {0, 1})


if __name__ == '__main__':
    unittest.main()
