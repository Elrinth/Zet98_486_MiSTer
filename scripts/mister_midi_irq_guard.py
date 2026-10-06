#!/usr/bin/env python3
"""Schedule local MIDI and synthesis threads while PC98 is active.

Keep MidiLink, MIDI input and the audio thread on CPU0; the second synthesis
worker runs on CPU1. Route the Cyclone V HPS USB interrupt to CPU1 for PC98
only, restoring its previous affinity on core exit or service shutdown.
Use FIFO priorities 65/70 for MIDI delivery and 60 for rendering. Restore
prior policies and CPU affinities afterward, checking thread identity.
No soundfonts or MIDI bytes are changed.
"""
import os
from pathlib import Path
import signal
import time


class Guard:
    def __init__(self, proc=Path('/proc'), core=Path('/tmp/CORENAME'), log=print):
        self.proc, self.core, self.log = Path(proc), Path(core), log
        self.saved = None

    def usb_irq(self):
        lines = (self.proc / 'interrupts').read_text().splitlines()
        if not lines or 'CPU1' not in lines[0].split():
            return None
        matches = []
        for line in lines[1:]:
            fields = line.split()
            if fields and 'ffb40000.usb' in [x.rstrip(',') for x in fields]:
                irq = fields[0].rstrip(':')
                if irq.isdigit():
                    matches.append(irq)
        return matches[0] if len(matches) == 1 else None

    def restore(self):
        if self.saved is None:
            return
        irq, original = self.saved
        path = self.proc / 'irq' / irq / 'smp_affinity'
        # Do not overwrite a later administrator change or a reused IRQ.
        if self.usb_irq() == irq and int(path.read_text().strip(), 16) == 2:
            path.write_text(original + '\n')
            self.log('Restored USB IRQ %s affinity to %s' % (irq, original))
        self.saved = None

    def active(self):
        try:
            return self.core.read_text().strip().upper() == 'PC98'
        except FileNotFoundError:
            return False

    def poll(self):
        if not self.active():
            self.restore()
            return
        if self.saved is not None:
            return
        irq = self.usb_irq()
        if irq is None:
            return
        path = self.proc / 'irq' / irq / 'smp_affinity'
        original = path.read_text().strip()
        # Already isolated by another service: leave ownership with it.
        if int(original, 16) == 2:
            return
        self.saved = (irq, original)
        path.write_text('2\n')
        if int(path.read_text().strip(), 16) != 2:
            raise RuntimeError('USB IRQ affinity did not apply')
        self.log('PC98: USB IRQ %s moved to CPU1 (previous affinity %s)' % (irq, original))


class MidiPriorities:
    """Restore only threads we changed, checking identity against PID reuse."""
    def __init__(self, proc=Path('/proc'), scheduler=os, log=print):
        self.proc, self.scheduler, self.log = Path(proc), scheduler, log
        self.saved = {}

    def identity(self, tid):
        return (self.proc / str(tid) / 'stat').read_text().rsplit(')', 1)[1].split()[19]

    def restore(self):
        for tid, (identity, policy, priority, applied, affinity, target) in list(self.saved.items()):
            try:
                if self.identity(tid) == identity:
                    if (self.scheduler.sched_getscheduler(tid) == self.scheduler.SCHED_FIFO and
                        self.scheduler.sched_getparam(tid).sched_priority == applied):
                        self.scheduler.sched_setscheduler(tid, policy, self.scheduler.sched_param(priority))
                    if self.scheduler.sched_getaffinity(tid) == target:
                        self.scheduler.sched_setaffinity(tid, affinity)
            except (FileNotFoundError, ProcessLookupError):
                pass
            del self.saved[tid]

    def poll(self, active):
        if not active:
            self.restore()
            return
        candidates = []
        for path in self.proc.glob('[0-9]*/comm'):
            try:
                name = path.read_text().strip()
                if name == 'midilink':
                    candidates.append((int(path.parent.name), 65, {0}))
                elif name == 'fluidsynth':
                    for thread in (path.parent / 'task').glob('*/comm'):
                        role = thread.read_text().strip()
                        settings = {'alsa-midi-seq': (70, {0}),
                                    'alsa-audio': (60, {0}), 'mixer0': (60, {1})}
                        if role in settings:
                            priority, target = settings[role]
                            candidates.append((int(thread.parent.name), priority, target))
            except (FileNotFoundError, ProcessLookupError):
                continue
        for tid, applied, target in candidates:
            try:
                identity = self.identity(tid)
                if tid in self.saved and self.saved[tid][0] == identity:
                    continue
                policy = self.scheduler.sched_getscheduler(tid)
                priority = self.scheduler.sched_getparam(tid).sched_priority
                affinity = self.scheduler.sched_getaffinity(tid)
                if policy == self.scheduler.SCHED_FIFO and priority == applied and affinity == target:
                    continue
                self.saved[tid] = (identity, policy, priority, applied, affinity, target)
                self.scheduler.sched_setscheduler(tid, self.scheduler.SCHED_FIFO,
                                                  self.scheduler.sched_param(applied))
                self.scheduler.sched_setaffinity(tid, target)
                self.log('PC98: audio/MIDI thread %d uses FIFO priority %d on CPU%d' % (tid, applied, min(target)))
            except (FileNotFoundError, ProcessLookupError):
                continue


def main():
    import fcntl
    with open('/tmp/pc98-midi-irq-guard.lock', 'a+') as lock:
        try:
            fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
        except BlockingIOError:
            return
        lock.seek(0)
        lock.truncate()
        lock.write(str(os.getpid()) + '\n')
        lock.flush()
        running = True

        def stop(*unused):
            nonlocal running
            running = False

        signal.signal(signal.SIGTERM, stop)
        signal.signal(signal.SIGINT, stop)
        guard = Guard(log=lambda text: print(text, flush=True))
        priorities = MidiPriorities(log=lambda text: print(text, flush=True))
        try:
            while running:
                guard.poll()
                priorities.poll(guard.active())
                time.sleep(1)
        finally:
            try:
                priorities.restore()
            finally:
                guard.restore()


if __name__ == '__main__':
    main()
