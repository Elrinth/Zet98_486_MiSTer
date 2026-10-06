#!/usr/bin/env python3
"""Install/uninstall the PC98 MIDI bundle on MiSTer; run as root."""
import os
from pathlib import Path
import shutil
import signal
import subprocess
import sys
import time

BASE = Path('/media/fat/Scripts/PC98_MIDI')
STARTUP = Path('/media/fat/linux/user-startup.sh')
BEGIN = '# BEGIN PC98 MIDI timing\n'
END = '# END PC98 MIDI timing\n'
OLD = ('# PC98 local MIDI: isolate USB IRQs and prioritize MIDI delivery.\n'
       'nohup python3 /media/fat/Scripts/PC98_MIDI_Timing.py '
       '>/tmp/pc98-midi-timing.log 2>&1 </dev/null &\n')


def startup_text(text, install):
    if BEGIN in text:
        before, rest = text.split(BEGIN, 1)
        _, after = rest.split(END, 1)
        text = before + after
    text = text.replace(OLD, '')
    if install:
        block = (BEGIN + 'if [ "${1:-start}" != stop ]; then\n'
                 '    sh /media/fat/Scripts/PC98_MIDI/setup.sh start\nfi\n' + END)
        # Preserve an existing final exit statement and all unrelated commands.
        lines = text.splitlines(keepends=True)
        nonempty = [i for i, line in enumerate(lines) if line.strip()]
        if nonempty and lines[nonempty[-1]].strip() in ('exit', 'exit 0'):
            lines.insert(nonempty[-1], block)
            return ''.join(lines)
        text = text.rstrip('\n') + '\n\n' + block
    return text


def stop_old_guard():
    lock = Path('/tmp/pc98-midi-irq-guard.lock')
    if not lock.exists():
        return
    pid = int(lock.read_text().strip())
    proc = Path('/proc/%d/cmdline' % pid)
    if proc.exists() and b'/media/fat/Scripts/PC98_MIDI_Timing.py' in proc.read_bytes().split(b'\0'):
        os.kill(pid, signal.SIGTERM)
        for _ in range(60):
            if not proc.exists():
                return
            time.sleep(.05)
        raise RuntimeError('Old timing helper did not stop')


def main():
    if os.geteuid() != 0:
        raise SystemExit('Run as root on MiSTer')
    uninstall = sys.argv[1:] == ['--uninstall']
    if sys.argv[1:] and not uninstall:
        raise SystemExit('Usage: python3 mister_midi_install.py [--uninstall]')
    source = Path(__file__).resolve().parent
    files = {'mister_midi_irq_guard.py': 'timing.py',
             'mister_midi_setup.sh': 'setup.sh',
             'mister_fluidsynth_wrapper.sh': 'fluidsynth-wrapper.sh',
             'mister_midi_install.py': 'mister_midi_install.py'}
    if not uninstall:
        for filename in files:
            if not (source / filename).is_file():
                raise RuntimeError('Missing bundle file: ' + filename)
        if not Path('/usr/sbin/fluidsynth').is_file():
            raise RuntimeError('Expected MiSTer FluidSynth at /usr/sbin/fluidsynth')
        if shutil.which('mountpoint') is None:
            raise RuntimeError('mountpoint utility required')
    old = STARTUP.read_text() if STARTUP.exists() else '#!/bin/sh\n'
    new = startup_text(old, not uninstall)
    backup = STARTUP.with_name(STARTUP.name + '.before-midi-' + time.strftime('%Y%m%d-%H%M%S'))
    if new != old:
        backup.write_text(old)
        print('Startup backup:', backup)
    stop_old_guard()
    if (BASE / 'setup.sh').exists():
        # Use the new stop implementation during upgrades, including fixes
        # for detaching the executable bind mount while FluidSynth is running.
        stop_script = BASE / 'setup.sh' if uninstall else source / 'mister_midi_setup.sh'
        subprocess.run(['sh', str(stop_script), 'stop'], check=True)
    if not uninstall:
        BASE.mkdir(parents=True, exist_ok=True)
        for filename, target in files.items():
            shutil.copyfile(source / filename, BASE / target)
        subprocess.run(['sh', str(BASE / 'setup.sh'), 'start'], check=True)
    stage = STARTUP.with_name(STARTUP.name + '.pc98-midi-new')
    stage.write_text(new)
    stage.chmod(0o755)
    stage.replace(STARTUP)
    print('Removed startup hook.' if uninstall else 'Installed startup hook and started timing helper.')
    print('Restart MiSTer to apply the launch settings to a fresh music session.')


if __name__ == '__main__':
    main()
