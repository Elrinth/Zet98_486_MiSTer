; SPDX-License-Identifier: GPL-3.0-or-later
; Linux BusyBox startup: four consecutive PUSHes cross a user stack page.
; A not-present stack page must retry the faulting PUSH without decrementing
; ESP twice. The next [ESP+20h] argument load must not read the return address.
bits 16
cpu 486
org 1000h
PD equ 20000h
PT equ 21000h
IDT equ 22000h
TSS equ 23000h
STACK_PAGE equ 30000h
%ifndef PUSH_BYTES
%define PUSH_BYTES 4
%endif
%ifndef FAULT_PUSH
%define FAULT_PUSH 4
%endif
%ifndef PRESENT
%define PRESENT 0
%endif
; FAULT_PUSH=-1 faults the argument PUSH; 0 faults CALL; 1..4 faults
; the corresponding saved-register PUSH in the callee.
%ifdef ENTER_FRAME
USER_ESP equ 31014h
FAULT_ADDR equ 30fe8h
FAULT_SAVED_ESP equ 3100ch
%else
FAULT_SAVED_ESP equ 31000h
%if FAULT_PUSH < 1
USER_ESP equ 31004h + FAULT_PUSH*4
FAULT_ADDR equ 30ffch
%else
USER_ESP equ 31008h + (FAULT_PUSH-1)*PUSH_BYTES
FAULT_ADDR equ 31000h-PUSH_BYTES
%endif
%endif
%ifdef ENTER_FRAME
FAULT_EIP equ four_pushes
%elif FAULT_PUSH = -1
FAULT_EIP equ push_arg
%elif FAULT_PUSH = 0
FAULT_EIP equ push_call
%elif FAULT_PUSH = 1
FAULT_EIP equ push_1
%elif FAULT_PUSH = 2
FAULT_EIP equ push_2
%elif FAULT_PUSH = 3
FAULT_EIP equ push_3
%else
FAULT_EIP equ push_4
%endif
cli
cld
xor ax,ax
mov ds,ax
lgdt [gdtr]
mov eax,cr0
or al,1
mov cr0,eax
jmp dword 8:pm32
align 8
gdt:
dq 0
dq 00cf9a000000ffffh
dq 00cf92000000ffffh
dq 00cffa000000ffffh
dq 00cff2000000ffffh
dq 0000890000000067h | (TSS << 16)
gdtr: dw $-gdt-1
dd gdt
idtr: dw 256*8-1
dd IDT
bits 32
pm32:
mov ax,10h
mov ds,ax
mov es,ax
mov ss,ax
mov esp,2f000h
mov edi,PD
xor eax,eax
mov ecx,4096
rep stosd
mov dword [PD],PT|7
mov edi,PT
mov eax,7
mov ecx,1024
.pte:
stosd
add eax,1000h
loop .pte
mov edi,IDT
mov ecx,256
.gate:
mov eax,bad_vector
mov edx,eax
and eax,0ffffh
or eax,80000h
and edx,0ffff0000h
or edx,8e00h
stosd
mov eax,edx
stosd
loop .gate
mov eax,pf_handler
mov edx,eax
and eax,0ffffh
or eax,80000h
and edx,0ffff0000h
or edx,8e00h
mov [IDT+14*8],eax
mov [IDT+14*8+4],edx
lidt [idtr]
mov dword [TSS+4],2f000h
mov word [TSS+8],10h
mov word [TSS+102],104
mov ax,28h
ltr ax
mov dword [PT+(STACK_PAGE>>12)*4],STACK_PAGE|4|PRESENT
mov eax,PD
mov cr3,eax
mov eax,cr0
or eax,80010000h
mov cr0,eax
jmp .paged
.paged:
mov ax,23h
mov ds,ax
mov es,ax
push dword 23h
push dword USER_ESP
push dword 3002h
push dword 1bh
push dword user
iretd
user:
mov ebp,0aabbccddh
mov edi,12345678h
mov esi,20h
mov ebx,87654321h
push_arg:
push dword 080a4120h
push_call:
call four_pushes
add esp,4
cmp esp,USER_ESP
jne fail
cmp eax,080a4120h
jne fail
cmp ebx,87654321h
jne fail
cmp edi,12345678h
jne fail
cmp esi,20h
jne fail
%if PUSH_BYTES = 4
cmp ebp,0aabbccddh
jne fail
%endif
cmp dword [faults],1
jne fail
mov ax,600dh
jmp report
four_pushes:
%ifdef ENTER_FRAME
; ENTER's final CW permission check follows its successful EBP push. The
; fault must retain the instruction's original ESP, not the partial frame.
enter 20h,0
mov eax,[ebp+8]
leave
ret
%else
%macro SAVE_REGISTER 3
push_%1:
    %if PUSH_BYTES = 4
    push %2
    %else
    push %3
    %endif
%endmacro
SAVE_REGISTER 1,ebp,bp
SAVE_REGISTER 2,edi,di
SAVE_REGISTER 3,esi,si
SAVE_REGISTER 4,ebx,bx
sub esp,0ch
mov ebp,[esp+10h+4*PUSH_BYTES]
cmp ebp,080a4120h
jne fail
mov eax,ebp
add esp,0ch
%if PUSH_BYTES = 4
pop ebx
pop esi
pop edi
pop ebp
%else
pop bx
pop si
pop di
pop bp
%endif
ret
%endif
pf_handler:
pushad
mov eax,cr2
mov ebx,[esp+32]
mov ecx,[esp+36]
mov esi,[esp+48]
cmp eax,FAULT_ADDR
jne fail
cmp ebx,6|PRESENT
jne fail
cmp ecx,FAULT_EIP
jne fail
cmp esi,FAULT_SAVED_ESP
jne fail
inc dword [faults]
mov dword [PT+(STACK_PAGE>>12)*4],STACK_PAGE|7
invlpg [STACK_PAGE]
popad
add esp,4
iretd
bad_vector:
mov ebp,0eeeeh
fail:
mov dx,7fe4h
out dx,ax
mov ax,0deadh
report:
mov dx,7ff0h
out dx,ax
hlt
jmp $
align 4
faults dd 0
