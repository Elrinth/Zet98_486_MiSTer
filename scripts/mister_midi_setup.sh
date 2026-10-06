#!/bin/sh
# PC98 host MIDI setup. Runtime mounts disappear on reboot; linux.img stays read-only.
set -eu
base=/media/fat/Scripts/PC98_MIDI
run=/run/pc98-midi
original=/usr/sbin/fluidsynth
case "${1:-start}" in
start)
    test -x "$original"
    test -f "$base/fluidsynth-wrapper.sh"
    test -f "$base/timing.py"
    command -v python3 >/dev/null
    command -v taskset >/dev/null
    mkdir -p "$run"
    if ! mountpoint -q "$run/fluidsynth"; then
        # Refuse to capture our wrapper as the original after partial setup.
        if mountpoint -q "$original"; then
            echo "FluidSynth already has a mount override; inspect before installing." >&2
            exit 1
        fi
        touch "$run/fluidsynth"
        mount --bind "$original" "$run/fluidsynth"
    fi
    if ! mountpoint -q "$original"; then
        # /run permits executable scripts even if the SD card is mounted noexec.
        cp "$base/fluidsynth-wrapper.sh" "$run/launcher"
        chmod 755 "$run/launcher"
        if ! mount --bind "$run/launcher" "$original"; then
            umount "$run/fluidsynth"
            exit 1
        fi
    else
        cmp -s "$original" "$run/launcher" || { echo "Unrecognized FluidSynth override" >&2; exit 1; }
    fi
    nohup python3 "$base/timing.py" >/tmp/pc98-midi-timing.log 2>&1 </dev/null &
    ;;
stop)
    # Validate the service identity before sending a signal.
    python3 - "$base/timing.py" <<'PY'
import os, signal, sys, time
from pathlib import Path
lock = Path('/tmp/pc98-midi-irq-guard.lock')
if lock.exists():
    pid = int(lock.read_text().strip())
    proc = Path('/proc/%d/cmdline' % pid)
    if proc.exists() and sys.argv[1].encode() in proc.read_bytes().split(b'\0'):
        os.kill(pid, signal.SIGTERM)
        for _ in range(60):
            if not proc.exists():
                break
            time.sleep(.05)
        else:
            raise RuntimeError('Timing service did not stop')
PY
    if mountpoint -q "$original"; then
        cmp -s "$original" "$run/launcher" || { echo "Unrecognized FluidSynth override" >&2; exit 1; }
        umount "$original"
    fi
    # A running synth holds the original executable open. Detach this private
    # bind mount; the process keeps its inode until exit and is not interrupted.
    if mountpoint -q "$run/fluidsynth"; then umount -l "$run/fluidsynth"; fi
    ;;
*) echo "Usage: $0 start|stop" >&2; exit 2 ;;
esac
