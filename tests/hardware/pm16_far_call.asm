; SPDX-License-Identifier: GPL-3.0-or-later
; Protected m16:16 calls through a four-byte ES segment, including both gate
; widths and RETF argument cleanup. m16:32 must fault on that same short ES.
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
push word 6
push word 5
push word 4
push word 3
push word 2
push word 1
call far [es:0]
cmp sp,0f00h
jne fail
mov word [pointer],0
mov word [pointer+2],20h
push word 6
push word 5
push word 4
push word 3
push word 2
push word 1
call far [es:0]
cmp sp,0f00h
jne fail
mov word [pointer+2],28h
push word 6
push word 5
push word 4
push word 3
push word 2
push word 1
call far [es:0]
cmp sp,0f00h
jne fail
cmp word [calls],3
jne fail
mov word [pointer],callee16
mov word [pointer+2],0
mov word [pointer+4],8
faulting:
o32 call far [es:0]
after:
cmp word [faults],1
jne fail
cmp sp,0f00h
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
callee16:
inc word [calls]
retf 12
callee286:
inc word [calls]
retf 12
callee386:
inc word [calls]
o32 retf 12
gp:
push bp
mov bp,sp
cmp word [ss:bp+2],0
jne fail
cmp word [ss:bp+4],faulting
jne fail
mov word [ss:bp+4],after
inc word [faults]
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
dw 3,pointer
db 0,092h,0,0
dw callee286,8
db 6,084h
dw 0
dw callee386,8
db 6,08ch
dw 0
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
pointer: dw callee16,8,0
calls: dw 0
faults: dw 0
