; SPDX-License-Identifier: GPL-3.0-or-later
; Self-authored regression: a 16-bit protected-mode word read from a
; one-byte ES segment must raise #GP(0), preserving AX and the fault IP.
; The unguarded direct-load path silently read memory instead.
bits 16
org 1000h
cli
xor ax,ax
mov ds,ax
mov ss,ax
mov sp,0f00h
lgdt [gdtr]
lidt [idtr]
mov eax,cr0
or eax,1
mov cr0,eax
jmp 8:protected
protected:
mov ax,10h
mov ds,ax
mov ss,ax
mov sp,0f00h
mov ax,18h
mov es,ax
xor bx,bx
mov ax,1234h
faulting:
mov ax,[es:bx]
after:
cmp word [fault_count],1
jne fail
cmp ax,1234h
jne fail
mov dx,7ff0h
mov ax,600dh
out dx,ax
hlt
fail:
mov dx,7fe4h
out dx,al
mov dx,7ff0h
mov ax,0badh
out dx,ax
hlt
gp:
push bp
mov bp,sp
cmp word [ss:bp+2],0
jne fail
cmp word [ss:bp+4],faulting
jne fail
mov word [ss:bp+4],after
inc word [fault_count]
pop bp
add sp,2
iret
align 8
gdt:
dq 0
dw 0ffffh,0
db 0,09ah,0,0
dw 0ffffh,0
db 0,092h,0,0
dw 0,0
db 1,093h,0,0
gdt_end:
gdtr: dw gdt_end-gdt-1
dd gdt
idtr: dw idt_end-idt-1
dd idt
align 8
idt: times 13 dq 0
dw gp,8
db 0,086h
dw 0
idt_end:
fault_count: dw 0