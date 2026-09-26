# BIOS read/verify cost control

This self-authored COM program issues only PC-98 INT 1Bh READ (06h) and
VERIFY (01h) against linear LBA 136 through 16519 on a disposable raw disk.
Each pass covers 8 MiB using 256 calls of 32 KiB. The order is READ, VERIFY,
VERIFY, READ. No disk-write BIOS operation is issued. DOS writes only a new,
exclusively created `A:\BIOSCOST.BIN` result.

The current production BIOS performs the same per-sector ATA reads for both
commands, including the transfer to its stack bounce buffer. READ additionally
copies bytes into the caller's buffer. VERIFY leaves that buffer untouched.
This experiment can reveal the cost of that copy and command-dependent work;
it cannot attribute all remaining time to the HPS, disk, controller or CPU.

The destination is filled with A55Ah before every pass. VERIFY checks the
entire buffer afterward. READ retains the final 32 KiB for host comparison.
Checksums and canary checks occur **outside** each timed interval. The RTC
clock is validated, initially checked for liveness and handled across midnight.
Each phase has a 60-second between-call deadline; the launcher provides a
separate 300-second host recovery deadline. A stuck BIOS call cannot be
interrupted by the guest budget.

The 128-byte little-endian result contains `Z98BIO1\0`, start LBA at offset8,
bytes per pass at12, chunk size at16 and phase count at20. Four 16-byte records
begin at32: command, whole RTC seconds, final-buffer CRC32, success marker1.
Offsets24–31 and96–127 remain zero. A failed probe must not be accepted even
if a partial output exists.

Protocol tests check the full 1024-call sequence, address progression,
read-only commands, DF, clock validation/rollover, existing result refusal,
BIOS failures, VERIFY buffer corruption and wrong READ data. A reduced
64 KiB-per-pass build additionally executes the unmodified production option
ROM and resident BIOS in Unicorn, including all 512 actual ATA sector reads.
The emulator is a functional check, not a hardware performance model.

Whole-second results include endpoint quantization and firmware polling.
The ordering reduces, but does not eliminate, cache effects. This is neither
a Doom startup benchmark nor proof of Doom's protected-mode runtime state.
