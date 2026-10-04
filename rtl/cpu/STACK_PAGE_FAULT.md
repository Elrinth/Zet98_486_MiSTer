# Restarting a page-faulting stack write

This correction is included in B242, using the hardware-qualified bitstream
and build profile recorded below.

The PC-98 Linux BusyBox i486 image intermittently segfaulted during libc
initialization, including when starting `ip`. This reproduced on B241 with
OpenBIOS 2026-10-04.1. The same extracted executable runs on the host CPU.

A ptrace launcher captured the fault without single-stepping the child.
At `08062216` (`mov [ebp],eax`), EBP was the return address `08062322`, not
the expected argument `080A4120`. ESP was `BFBB6FEC`; the return address and
argument appeared at ESP+20h and ESP+24h, four bytes below their expected
stack positions. Four register PUSHes in the callee crossed a stack page.
Linux demand-mapped that page, but retrying the PUSH decremented ESP again.

Two CPU issues contributed:

- A delayed store fault restored the issuing instruction's saved EIP while
  using a newer instruction's ESP snapshot. Store ownership now includes
  both snapshots. CALL can submit its stack write on the first microcode
  cycle, so that cycle captures ESP directly before TMPeSP updates.
- The paging unit returns to idle when it reports a fault. A younger chained
  PUSH could issue in that same cycle and overwrite the fault address and
  restart state. Demand submissions are now suppressed during the page-fault
  pulse so exception delivery retains the older fault.

`tests/hardware/push_page_fault_probe.asm` reproduces the failure without
Linux binaries. It enters CPL 3, crosses into a missing or read-only stack
page, demand-maps it from a separate ring-0 stack, and checks saved ESP,
fault address/error, the callee argument and return-stack integrity.
`tests/run-z486-push-page-fault.sh` checks argument PUSH, CALL,
and each of four word/DWORD callee register PUSH positions. Negative controls remove
the stack rollback, CALL first-cycle selection, and fault-request gate.

The 26 cases, including ENTER's final permission check, pass with both
pipeline-register settings 2 and 7. All three
negative controls fail with setting 2. Existing store/Jcc page-fault,
CMPXCHG/XADD fault, stack allocation, native memory and four V86/EMM386
variants pass. The framebuffer workload remains 1,132,151 cycles with
72,000 DDR commands in the B241 configuration.

`tests/hardware/linux_stack_page_fault.asm` is a standalone Linux/i386 ELF
probe with no libc dependency. It lazily maps two anonymous pages, places
the stack at their boundary, and verifies the same callee argument and
return stack after Linux resolves the fault. Build it with:

```
nasm -f elf32 tests/hardware/linux_stack_page_fault.asm -o linux-stack-pf.o
ld -m elf_i386 -o linux-stack-pf linux-stack-pf.o
```

The probe passes on the host CPU and fails on B241 (three hardware runs)
and B240 (two hardware runs). The relevant CPU RTL is identical in B240 and
B241; this fault predates the framebuffer optimization.
A separate 100-launch BusyBox hardware baseline on B241 recorded three
SIGSEGV stops and 97 normal exits. Local evidence is in `build/linux-ip/`.

The corrected 90 MHz/64 MB core was checked on the MiSTer with the same
OpenBIOS 2026-10-04.1. The deterministic probe passed four times, and the
100-launch ptrace batch recorded 100 normal exits and no SIGSEGV. A fresh
copy of the original image then completed 100 direct `ip` launches: all
returned the expected no-argument status 1, with no crash in the kernel
log. The original compressed image and BIOS were not modified.

The supplied kernel still reports `ip: socket: Function not implemented`
for `ip addr`, `ip link`, and `ip route`, as on the baseline. This is separate
from the corrected userspace startup fault.

Quartus build `quartus-20261004-223923-218d4d` fits at 41,286/41,910 ALMs,
539/553 M10Ks and 50 DSPs. Worst reported slack is -7.303 ns, with 10
negative timing checks; timing is not closed. This is within the user's
accepted 12 ns threshold for a hardware-qualified build. Pixel-clock and
FEC routing audits pass. The RBF SHA-256 is
`769a69589ae2dfe7cf6fe3e4f320e7533dd499eabfa2cbe677e38fc0c4124104`.

DOS QUALIFY passes on the same RBF: long-line output, all four DIVTEST
rounds, all 4,008 STRTEST cases, and MEMTEST with 531 KB conventional memory
and 16,384 KB XMS report no failures. B241 was released before this CPU
correction; it retains the known Linux startup failure.
