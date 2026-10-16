; SPDX-License-Identifier: GPL-3.0-or-later
; Ring-3 version of rep_movs_load.asm with a periodic IRQ0 (PIT_PM_TEST) whose
; ring-0 handler PUSHADs onto a stack placed so the saved ESI shares a page
; offset with the reloaded frame slot [EBP+18h] (Windows 95 VMM entry while
; MSVFW32 DrawDibBegin copies a palette, Magical Chase). INT 30h ends the run,
; INT 31h reports a mismatch (EBX = pass, EAX = reloaded pointer).
bits 16
cpu 486
org 1000h
HDR     equ 24b9b8h            ; all data in extended memory (DDR), as under Win95
OBJ     equ 276800h
FRAME   equ 205908h             ; [EBP+18h] = 205920h
STACK0  equ 207950h             ; PUSHAD saves ESI at 207920h
STACK3  equ 20e000h
UCODE   equ 280000h             ; ring-3 loop runs from DDR too
IDT     equ 22000h
PASSES  equ 400
cli
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
dq 00cf9a000000ffffh            ; 08h ring-0 code
dq 00cf92000000ffffh            ; 10h ring-0 data
dq 00cffa000000ffffh            ; 18h ring-3 code
dq 00cff2000000ffffh            ; 20h ring-3 data
tss_desc:
dw 103, tss, 8900h, 0           ; 28h TSS (base < 64 KB)
gdtr:
dw $-gdt-1
dd gdt
idtr:
dw 64*8-1
dd IDT
align 4
tss:
dd 0, STACK0, 10h
times 23 dd 0
bits 32
%macro GATE 3                   ; vector, handler, type
mov eax,%2
mov edx,eax
and eax,0ffffh
or eax,80000h
and edx,0ffff0000h
or edx,%3
mov [IDT+%1*8],eax
mov [IDT+%1*8+4],edx
%endmacro
pm32:
mov ax,10h
mov ds,ax
mov es,ax
mov ss,ax
mov esp,8e00h
mov ecx,64
.gates:
GATE 0, bad_vector, 8e00h
mov eax,[IDT]
mov edx,[IDT+4]
mov [IDT+ecx*8-8],eax
mov [IDT+ecx*8-4],edx
loop .gates
GATE 08h, irq0, 8e00h
GATE 30h, done, 0ee00h
GATE 31h, mismatch, 0ee00h
lidt [idtr]
mov ax,28h
ltr ax
mov edi,20000h                  ; identity-map 0-4 MB, user pages
mov dword [edi],21000h | 7
mov edi,21000h
mov eax,7
.pte:
stosd
add eax,1000h
cmp edi,22000h
jne .pte
mov eax,20000h
mov cr3,eax
mov eax,cr0
or eax,80000000h
mov cr0,eax
jmp .paged
.paged:
mov edi,HDR + 28h
xor eax,eax
.pal:
mov edx,eax
imul edx,edx,01010101h
xor edx,00c0dcc0h
mov [edi+eax*4],edx
inc eax
cmp eax,256
jne .pal
mov dword [HDR],28h
mov dword [HDR+4],0b4h
mov dword [HDR+8],6dh
mov word [HDR+0ch],1
mov word [HDR+0eh],8
mov dword [HDR+20h],256
mov dword [FRAME+18h],HDR
mov dword [OBJ+0d4h],OBJ + 800h
mov al,0feh                     ; unmask IRQ0
out 2,al
push dword 23h
push dword STACK3
push dword 202h
push dword 1bh
mov esi,user
mov edi,UCODE
mov ecx,user_end-user
rep movsb
push dword UCODE
iretd

user:
mov ax,23h
mov ds,ax
mov es,ax
xor ebx,ebx
.pass:
mov eax,ebx
and eax,7
mov ecx,[counts+eax*4]
mov [HDR+20h],ecx
push ebx
mov ebp,FRAME
mov ebx,OBJ
mov eax,ebp
mov ecx,ebp
mov edx,ebp
lea edi,[ebx+0dch]
mov esi,[ebp+18h]
mov ecx,0ah
rep movsd
mov ecx,[ebx+0d4h]
mov edx,[ebp+18h]
mov dword [ecx+14h],0
mov dword [ebx+0f0h],0
cmp word [edx+0eh],8
ja .bad
mov ecx,[edx+20h]
mov esi,[edx]
shl ecx,2
lea edi,[ebx+104h]
shr ecx,2
add esi,edx
rep movsd
mov eax,[ebp+18h]
lea edi,[ebx+560h]
mov ecx,[eax+20h]
mov esi,[eax]
shl ecx,2
add esi,eax
shr ecx,2
pop ebx
cmp eax,HDR
jne .bad
cmp ecx,[HDR+20h]
jne .bad
cmp esi,HDR + 28h
jne .bad
mov ecx,[HDR+20h]
mov esi,HDR + 28h
lea edi,[OBJ+104h]
repe cmpsd
jne .bad
inc ebx
cmp ebx,PASSES
jne .pass
int 30h
.bad:
int 31h
user_end:

irq0:
pushad
mov ebp,esp
push ds
push es
mov ax,10h
mov ds,ax
mov es,ax
mov eax,[ebp+1ch]               ; the saved EAX..EDI must read back
mov esi,[ebp+4]
mov ecx,8
mov edi,207800h
rep movsd
mov al,20h
out 0,al
pop es
pop ds
popad
iretd

done:
mov al,0ffh
out 2,al
mov ax,600dh
jmp report
mismatch:
mov ebp,0bad1h
jmp fail
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
counts dd 256, 0, 2, 3, 0, 255, 1, 0
