; SPDX-License-Identifier: GPL-3.0-or-later
; Expand-down stack segments in protected mode (Viper CTR's SGS sound mixer):
; a 32-bit expand-down SS with limit 0 (valid 1..FFFFFFFFh) and a 16-bit one
; with limit 0FFFh (valid 1000h..FFFFh). PUSH/POP, CALL/RET and a software
; interrupt through a 32-bit interrupt gate must work on both; before the fix
; every push faulted (#SS -> #DF -> triple fault).
bits 16
cpu 386
org 1000h
cli
cld
xor ax,ax
mov ds,ax
mov ss,ax
mov sp,9000h
lgdt [gdtr]
lidt [idtr]
mov eax,cr0
or al,1
mov cr0,eax
jmp dword 08h:protected
bits 32
protected:
mov ax,10h
mov ds,ax
mov es,ax
; ---- 32-bit expand-down stack, limit 0, B=1
mov ax,18h
mov ss,ax
mov esp,90000h
push dword 12345678h
cmp dword [ss:esp],12345678h
jne fail
pop eax
cmp eax,12345678h
jne fail
call probe_call
ret_here:
cmp esp,90000h
jne fail
int 40h
cmp dword [ints],1
jne fail
cmp esp,90000h
jne fail
; ---- 16-bit expand-down stack at 80000h, limit 0FFFh, B=0
mov ax,20h
mov ss,ax
mov esp,8000h
push word 0beefh
pop bx
cmp bx,0beefh
jne fail
push dword 0cafef00dh
pop ebx
cmp ebx,0cafef00dh
jne fail
int 40h
cmp dword [ints],2
jne fail
cmp sp,8000h
jne fail
mov ax,600dh
jmp report
probe_call:
push ebp
mov ebp,esp
mov eax,[ss:ebp+4]
cmp eax,ret_here
pop ebp
jne fail
ret
int_handler:
inc dword [ints]
iretd
fail:
mov ax,0deadh
report:
mov dx,7ff0h
out dx,ax
hlt
jmp $
align 8
gdt:
dq 0
dq 00cf9a000000ffffh            ; 08: code 32, flat
dq 00cf92000000ffffh            ; 10: data 32, flat
dq 0040960000000000h            ; 18: data, expand-down, B=1, base 0, limit 0
dq 0000960800000fffh            ; 20: data, expand-down, B=0, base 80000h, limit 0FFFh
gdtr: dw 39
dd gdt
align 8
idt:
times 40h dq 0
dw int_handler                  ; 40h: 32-bit interrupt gate, selector 08
dw 08h
db 0,8eh
dw 0
idtr: dw 41h*8-1
dd idt
ints: dd 0
