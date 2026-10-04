; SPDX-License-Identifier: GPL-3.0-or-later
; Run the real Z98MEM map probe from ordinary DOS and upper extension-ROM RAM
; segments. It temporarily enters protected mode with nonzero segment bases.
bits 16
cpu 486
org 1000h
cli
mov ax,cs
mov ds,ax
mov es,ax
mov ax,2200h
mov ss,ax
mov sp,0fffeh
call detect_memory
cmp byte [detected],64
jne fail
; The map probe publishes both PC-98 memory counts and restores A20 off.
xor ax,ax
mov es,ax
cmp byte [es:401h],112
jne fail
cmp word [es:594h],48
jne fail
in al,0f2h
test al,1
jz fail
mov ax,600dh
report:
mov dx,7ff0h
out dx,ax
hang: jmp hang
fail:
mov ax,0deadh
jmp report
%include "z98mem_probe.inc"
