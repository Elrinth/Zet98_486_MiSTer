#!/bin/sh
# Optional: extracting this bundle never activates MIDI tuning.
base=/media/fat/Scripts/pc98-midi-timing
echo 'PC98 optional FluidSynth MIDI timing'
echo 'More buffering may reduce crackling and note clumping.'
echo 'About 85 ms buffering: roughly 64 ms more than the previous setup.'
echo 'Requires existing MidiLink/FluidSynth, Python3, taskset and mountpoint.'
echo '1) Enable/update tuning   2) Undo tuning   Enter) Leave unchanged'
printf 'Choice: '
read -r choice
case "$choice" in
1|2)
    for tool in python3 taskset mountpoint; do
        command -v "$tool" >/dev/null 2>&1 || { echo "Missing $tool"; exit 1; }
    done
    if [ "$choice" = 1 ]; then
        python3 "$base/mister_midi_install.py"
    else
        python3 "$base/mister_midi_install.py" --uninstall
    fi
    result=$?
    if [ "$result" = 0 ]; then
        echo 'Done. Reboot MiSTer when convenient; this script does not reboot it.'
    else
        echo 'Setup failed. Read the error above before retrying.'
    fi
    printf 'Press Enter to return. '; read -r unused
    exit "$result"
    ;;
*) echo 'No changes made.' ;;
esac
