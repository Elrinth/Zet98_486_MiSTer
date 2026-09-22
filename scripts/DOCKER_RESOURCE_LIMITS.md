# Bounded build clients

Use PowerShell 7 for `build.ps1`. Its default FPGA job is one container with
3 CPUs, 8 GiB RAM, no extra swap and no network. Sources and Quartus databases
live in the container's Linux filesystem. Windows bind mounts are not used.

`docker-command.ps1` runs short Docker commands with explicit argument arrays,
no shell expansion, concurrent stdout/stderr draining, and a 15-second default
deadline. Large copies may use up to 60 seconds. The still-running client
and its child processes are killed on timeout/cancellation; no Docker Desktop
backend, WSL VM or unrelated container is killed by that cleanup.

Builds start detached. The default workflow checks the same container every
10 seconds without keeping a client attached to its log stream. `-StartOnly`
returns after starting it and records the container name/ID in the build
directory. A client timeout does **not** prove the container stopped: inspect
that recorded container, preserve/export its results, and never start a
replacement merely because observation timed out. Failed observations throw
instead of retrying in a loop. Paused/unexpected container states also stop
the build watcher.

`Export-DockerDirectory` streams binary tar output directly to disk through
the same bounded runner. The Python extractor verifies member paths/types
and does not apply Linux timestamps that can fail on Windows. The completed
container is removed only after successful result export. A failed export
retains the container and archive for recovery.

`tests/docker-command.ps1` needs Python but does not use Docker. It verifies
literal argument fidelity, error propagation, large simultaneous output
pipes, binary output and bounded termination of a client **and its child**.
The test passes on the development host. The actual binary export was also
used successfully for generated GHDL proof inputs.

Do not use `docker stats` or reopen Docker Desktop's dashboard for polling.
That dashboard previously accumulated hung stats clients on this machine.
Use bounded `inspect`, `logs` and, when necessary, `top` on a known container.
`test.ps1` and `report-timing.ps1` use this runner too. Tests default to one
CPU/2 GiB and TimeQuest to one CPU/4 GiB, both without extra swap or Windows
binds. The scripts refuse competing simulation/timing/FPGA workloads. Test
images are installed once, then selected by immutable image ID for each run;
tests no longer launch an image rebuild on every invocation. Per-run source,
toolchain identity, commands, resource limits, logs and results stay under
`build/simulation-*`. CPU tests obtain Intel models from a never-started
Quartus container and save model hashes before removing that container.

All three scripts accept `-StartOnly`; inspect the recorded container name
and export its results before removing a detached job. `test.ps1 -PrepareOnly`
copies the exact source inputs without invoking Docker. `-TestScript` accepts
one or more existing `tests/run*.sh` files for focused regressions.
