#!/usr/bin/env bash
# Run a Quartus command line with a stall watchdog.
#
# B162 and the first B163 attempt never finished: quartus_fit kept ~1.7 CPUs
# busy for over an hour after placement. Their last log line was an SDC
# message, but Quartus writes fitter output in chunks (docker timestamps show
# minutes of work arriving in one burst), so that line only marks where the
# last chunk ended; the unfinished phase was routing. B161 routed in 10
# minutes. stdbuf makes the output line-buffered so this log, the watchdog
# and Zet98Monitor see the real current phase.
#
# If no line is written for STALL_MINUTES, or the whole run exceeds
# MAX_MINUTES, save per-thread diagnostics, print a Z98_WATCHDOG line, stop
# every Quartus process and exit 125 (stall) or 124 (time limit). The
# Zet98Monitor recognizes both exit codes and the Z98_WATCHDOG line.
#
# Usage: quartus-watchdog.sh "<command line>"   (from Zet98/v17)
set -u
STALL_MINUTES=${STALL_MINUTES:-25}
MAX_MINUTES=${MAX_MINUTES:-150}
POLL_SECONDS=${POLL_SECONDS:-30}
dir=/project/Zet98/v17/watchdog
mkdir -p "$dir"
log="$dir/progress.log"
: > "$log"

status() {
    printf '{"state":"%s","silentSeconds":%s,"elapsedSeconds":%s,"stallMinutes":%s,"maxMinutes":%s}\n' \
        "$1" "$2" "$3" "$STALL_MINUTES" "$MAX_MINUTES" > "$dir/status.json"
}

diagnostics() {
    {
        echo "== $(date -u +%FT%TZ) reason: $1"
        echo "== last output lines"
        tail -n 40 "$log"
        echo "== processes"
        ps -eo pid,ppid,etime,time,pcpu,rss,args
        for pid in $(pgrep -x 'quartus_(fit|sta|map|asm|cdb|sh)'); do
            echo "== threads of $pid ($(tr '\0' ' ' < /proc/$pid/cmdline 2>/dev/null | cut -c1-120))"
            for task in /proc/$pid/task/*; do
                tid=${task##*/}
                # utime/stime in clock ticks: fields 14/15 of stat.
                read -r -a stat < "$task/stat" 2>/dev/null || continue
                printf '%s state=%s utime=%s stime=%s wchan=%s comm=%s\n' "$tid" "${stat[2]}" \
                    "${stat[13]}" "${stat[14]}" "$(cat "$task/wchan" 2>/dev/null)" "$(cat "$task/comm" 2>/dev/null)"
            done
        done
    } >> "$dir/diagnostics.txt" 2>&1
}

stop_quartus() {
    pkill -TERM -x 'quartus_(fit|sta|map|asm|cdb|sh)' 2>/dev/null
    sleep 15
    pkill -KILL -x 'quartus_(fit|sta|map|asm|cdb|sh)' 2>/dev/null
}

stdbuf -oL -eL bash -c "$1" > >(tee -a "$log") 2>&1 &
child=$!
start=$(date +%s)
status running 0 0
while kill -0 "$child" 2>/dev/null; do
    sleep "$POLL_SECONDS"
    kill -0 "$child" 2>/dev/null || break
    now=$(date +%s)
    silent=$(( now - $(stat -c %Y "$log") ))
    elapsed=$(( now - start ))
    status running "$silent" "$elapsed"
    # A thread snapshot every ten silent minutes helps separate a busy router
    # from a stuck constraint script without stopping a legitimate run.
    if [ "$silent" -ge 600 ] && [ $(( silent % 600 )) -lt "$POLL_SECONDS" ]; then
        diagnostics "silent for ${silent}s (still running)"
    fi
    reason=""; code=0
    if [ "$silent" -ge $(( STALL_MINUTES * 60 )) ]; then
        reason="STALL: no Quartus output for $(( silent / 60 )) min"; code=125
    elif [ "$elapsed" -ge $(( MAX_MINUTES * 60 )) ]; then
        reason="TIME LIMIT: build exceeded ${MAX_MINUTES} min"; code=124
    fi
    if [ -n "$reason" ]; then
        diagnostics "$reason"
        last=$(grep -v '^Z98_WATCHDOG' "$log" | tail -n 1)
        echo "Z98_WATCHDOG $reason; last output: $last"
        echo "Z98_WATCHDOG diagnostics: $dir/diagnostics.txt (exported with the Quartus database)"
        status "$( [ $code = 125 ] && echo stalled || echo time-limit )" "$silent" "$elapsed"
        stop_quartus
        wait "$child" 2>/dev/null
        exit "$code"
    fi
done
wait "$child"
code=$?
status "$( [ $code = 0 ] && echo completed || echo failed )" 0 $(( $(date +%s) - start ))
exit "$code"
