#!/bin/sh
# A runtime bind mount selects this launcher without changing linux.img.
# Keep the original executable's basename so MidiLink's killall still works.
# MGL launchers report their setname (PC98_OPT1, ...) as the core name, so
# match every name that starts with PC98 or Zet98.
case "$(cat /tmp/CORENAME 2>/dev/null)" in
    PC98*|pc98*|Zet98*|ZET98*|zet98*)
        exec taskset 3 /run/pc98-midi/fluidsynth -r 48000 -z 256 -c 16 -o synth.cpu-cores=2 "$@";;
esac
exec /run/pc98-midi/fluidsynth "$@"
