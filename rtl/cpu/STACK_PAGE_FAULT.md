# Restarting a page-faulting stack write

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

The 24 cases pass with both pipeline-register settings 2 and 7. All three
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

The probe passes on the host CPU and fails on B241 (three hardware runs).
A separate 100-launch BusyBox hardware baseline on B241 recorded three
SIGSEGV stops and 97 normal exits. Local evidence is in `build/linux-ip/`.

Hardware validation of the fix is pending. B241 was released before this
CPU correction; it retains the known Linux startup failure.
