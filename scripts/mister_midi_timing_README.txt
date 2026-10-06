PC98 local FluidSynth MIDI timing workaround - 2026-10-06

Guide: https://pc98.thefirstboss.com/guides/midi-timing/

Extract this bundle to /media/fat/Scripts/pc98-midi-timing on MiSTer.
Run from SSH or the Linux terminal as root:
  python3 /media/fat/Scripts/pc98-midi-timing/mister_midi_install.py
Then reboot, load PC98 and start your game with local FluidSynth MIDI.

Tested: PC98 B244, MidiLink 3.3 BB7, FluidSynth 2.1.6, GeneralUser-GS,
USB Wi-Fi. Python3, taskset and mountpoint are required.

This revision uses BOTH ARM CPUs for FluidSynth, with the main audio
thread on CPU0 and the synthesis worker on CPU1. MIDI delivery uses
CPU0 at FIFO65/70. The HPS USB interrupt remains on CPU1.
New PC98 synths start at 48 kHz, period256, periods16, cpu-cores2.
The host buffer is approximately 85 ms, about 64 ms more than the
previous 21 ms configuration. Reverb, chorus, 256 voices and normal
interpolation are preserved. The soundfont selection is unchanged.

Three captured-jingle replays with SD-card upload load passed with
zero observed underruns or audio-stream restarts. Earlier single-CPU
settings repeatedly failed this test. Actual startup verification is
recorded in the online guide. This is tested on one hardware/software
combination; do not assume every soundfont or setup needs the same tuning.

The helper also fixes a /proc process-disappearance race. The installer
handles upgrades while the original synth executable is still running.
Earlier users should extract the new bundle and rerun its installer.
Thread/IRQ settings restore when PC98 exits. Synth launch settings remain
until that process exits. No game or MIDI data is distributed.

The installer preserves unrelated startup commands and writes a dated
backup beside /media/fat/linux/user-startup.sh. linux.img stays read-only.
The runtime executable bind mount is recreated by the startup hook.

Undo, then reboot to reset an already-running synth:
  python3 /media/fat/Scripts/PC98_MIDI/mister_midi_install.py --uninstall

Diagnostics:
  cat /tmp/pc98-midi-timing.log
  ps -ef | grep '[f]luidsynth'
  cat /proc/asound/card0/pcm0p/sub0/hw_params

Public source is included in this bundle. Please report residual timing
issues with core/synth versions, soundfont, network type and activity.
