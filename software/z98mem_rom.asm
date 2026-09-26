; SPDX-License-Identifier: GPL-3.0-or-later
; Z98MEM's memory-map probe as a blob for the core's disk extension ROM.
; The ROM copies it to RAM and calls offset 0 during BIOS initialization, so
; stock PC-98 HIMEM.SYS works without a CONFIG.SYS driver: the legacy BIOS
; sets the V30 flag unconditionally and never counts memory above 1 MB.
bits 16
cpu 486
org 0
entry:
    push ds
    push cs
    pop ds
    call detect_memory
    pop ds
    retf
%include "z98mem_probe.inc"
