# Zet98 Build & MiSTer Monitor

Run `build/monitor/Zet98Monitor.exe`. No installer or downloaded dependencies are needed on this workstation; it uses Windows .NET Framework. Keep it in that folder, or pass the absolute PC98_MiSTer project directory as its first argument after moving it.

Rebuild with `tools/BuildMonitor/build.ps1` (PowerShell 7). Source: `BuildMonitor.cs`.

The compact window shows the three newest project jobs, prioritizing running jobs. It discovers Docker containers named `zet98-quartus-*`, `zet98-simulation-*`, and `zet98-timequest-*` on the `desktop-linux` context. Other running containers are counted but are not presumed to be builds. It recovers older results from `build/*/result.json` and stores observed history in `build/monitor/history.json`.

- Build # is the ordinal of local Quartus build folders; the full timestamp/container name is also displayed. Removing old folders can change the ordinal.
- Three log lines per card; long lines are clipped to keep the window compact.
- Exit zero means the command finished successfully, not that hardware works. FPGA jobs display timing as unverified until an exported `timing-results.json` establishes a result. Timing results apply to that build's exported report; subsequent timing requalification is not inferred automatically.
- Typical total duration is the median of at least three successful jobs of the same category. It is an estimate across clock configurations, not a progress percentage or a deadline. Failed runs are excluded. FPGA runs that compile but fail timing remain compile-duration observations.
- Refresh every ten seconds, no overlapping polls, no `docker stats`, no continuous log streams. Each command has a six-second timeout. A Windows job object kills this monitor's child command processes on timeout, cancellation, or application exit. Docker failures cause a 30ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÂ¢Ã¢â€šÂ¬Ã…â€œ120 second backoff. Closing the window does not stop Docker containers or change MiSTer state.

## MiSTer / agent activity

`scripts/docker-command.ps1` automatically publishes safe labels for PuTTY SSH/SCP operations targeting the development MiSTer. It includes only the SSH script basename when available; passwords and command arguments are never written into the activity feed. A successful SSH operation does not assert that a game booted or rendered correctly.

For descriptive hardware tests or development milestones, publish explicit events:

```powershell
./scripts/write-monitor-activity.ps1 -Id rusty-test-75 -Title 'Loading Rusty on the 75 MHz test core' -Status Running
# Perform the actual operation and check its result.
./scripts/write-monitor-activity.ps1 -Id rusty-test-75 -Title 'Rusty test launch completed; awaiting graphics validation' -Status Completed
```

Reusing an ID preserves its start time. Status may be Running, Completed, Failed, or Info. Events live in `build/monitor-events/`. An explicit long-running event stays Running until its writer finishes it; the monitor cannot infer private agent reasoning or TV/game state. Build monitoring is read-only. The screenshot button explicitly requests a new MiSTer screenshot and deletes only that new file after a successful, image-validated download.

## Verification

`Zet98Monitor.exe --self-test` tests a real bounded Docker query, deliberate command timeout, cancellation, and child-process cleanup. It writes `self-test.txt` alongside the executable. Passing this does not certify a core build.

Pass `<project-path> --preview` to render a live twelve-second UI preview to `preview.png` and exit. The delivered executable was compiled, self-tested, and visually inspected against the live 75 MHz build. A read-only MiSTer uptime query verified the automatic activity feed.

Text selection: drag to select, Ctrl+C or right-click Copy. Ctrl+A selects an entire card or activity area, including clipped text. That text area holds its current snapshot during a drag or while text is selected so polling cannot interrupt copying. Clear the selection to resume its updates. Ordinary keyboard focus does not freeze updates. Other areas continue refreshing.

## Screenshot button

Click **New screenshot** to capture the current core output. The screenshot replaces the build cards inside the same window; **Show builds** returns to the live cards. Polling resumes after the capture operation. Local copies remain under `build/monitor/captures/<unique-id>/screenshot.png`.

Capture uses `scripts/capture-monitor-screenshot.ps1`, the already trusted PuTTY host entry for 192.168.0.161, and the existing development credential. The credential is stored with Windows DPAPI via Export-Clixml in ignored `build/monitor/mister-credential.xml`; it is readable only by the same Windows user on this computer. The PowerShell 7 executable location is in `build/monitor/powershell-path.txt`. No password is embedded in the EXE or committed source.

Only the uniquely named screenshot returned by this capture is eligible for deletion. The downloaded PNG is decoded before cleanup. Failed downloads leave the remote image untouched; cleanup failures display a warning while still showing the downloaded image. Other screenshots are not removed. A real capture/download/cleanup and the in-window capture handler were tested on the development MiSTer.

**Last screenshot** opens the most recent successfully saved local capture without contacting MiSTer. It also works after restarting the monitor; unreadable or missing images are skipped. **Show builds** returns to monitoring, and only **New screenshot** takes a fresh capture.

The screenshot view displays its recorded capture date and time in the Windows local time zone, including the UTC offset. Older images without a capture timestamp show their local file save time, explicitly labelled Saved.

## Automatic outcome and next step

Completed FPGA containers are now checked automatically: the monitor copies only their timing summary into the local build folder using one bounded `docker cp` and parses its setup/hold results. Exported local summaries work too. It writes `timing-results.json` so a removed container does not lose its outcome. Copy failures back off for two minutes and remain explicitly unverified. Passing summary checks still does not establish hardware correctness or constraint coverage.

The top status line states the running job category, or explicitly says that no project job is running and which review/fix/validation is next. The activity area is labelled event history; a past Completed message does not imply an agent is currently working. The monitor reports observed jobs and published events, not private agent reasoning, and does not itself start fixes or hardware tests.

When Docker cannot be reached, previously active jobs show **Status unknown · last seen Running** (or Paused), and their duration is labelled **Last elapsed**. Duration estimates are hidden until a successful poll restores live state. The top line explicitly says that live build state is unknown; saved history is retained for recovery.
