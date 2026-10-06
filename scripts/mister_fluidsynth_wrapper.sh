#!/bin/sh
# A runtime bind mount selects this launcher without changing linux.img.
# Keep the original executable's basename so MidiLink's killall still works.
if [ "$(cat /tmp/CORENAME 2>/dev/null)" = PC98 ]; then
    exec taskset 3 /run/pc98-midi/fluidsynth -r 48000 -z 256 -c 16 -o synth.cpu-cores=2 "$@"
fi
exec /run/pc98-midi/fluidsynth "$@"
