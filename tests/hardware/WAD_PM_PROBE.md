The self-authored WADPM.COM diagnostic reads A:\DOOM1\DOOM.WAD through DOS,
copies it into one XMS allocation, locks that allocation, then computes a CRC32
over every byte through a flat 32-bit protected-mode data selector. Each 32KB
window returns to real mode and restores the original stack, descriptor tables,
segment registers and flags. A20 has a local XMS reference while reading.
The file and allocation are bounded to 32MB; an independent 300-second host
watchdog is required because a stalled DOS/XMS call cannot be preempted safely.

WADPM.BIN is create-new, never truncated. Its 64-byte header has magic Z98PMRD1,
then six little-endian dwords: status, file size, loaded bytes, locked physical
base, protected bytes read, checkpoint count. Remaining header bytes are zero.
Every 32KB contributes the complemented running CRC32. The host verifier must
compare every checkpoint against the original WAD; guest completion is not PASS.
Errors release acquired XMS/A20 resources and return a failure status. The
probe refuses an already-protected execution environment (including EMM386).

Validation includes independent DOS/XMS Unicorn hooks executing the actual
protected-mode kernel, odd file lengths, corruption detection and failure
cleanup. The actual CPU/bridge simulation uses independently generated known
payload bytes, unaligned addresses, the 2MB boundary, above 16MB and near 64MB;
it tests chained checksums, real-mode return and a non-present descriptor #NP.
The separate PM_LIMIT_CONTROL assembly variant retains a failing segment-limit
regression: the descriptor limit loads correctly, but the fast read path's
checker is disabled. Do not report that control as passing or infer that it
causes Doom's failure. The probe uses valid allocated addresses and explicit
counts; it does not rely on segment-limit enforcement for its bounds.

This isolates the DOS -> XMS -> protected-addressing path. It does not execute
the Doom extender, inspect Doom's live tables, prove all CPU behavior or measure
startup performance. Never upload private patched game executables with it.
