; SPDX-License-Identifier: GPL-3.0-or-later
; Protected-mode extended-RAM traffic with frequent IRQ0 (z486_xms_resident_tb
; PIT_PM_TEST): IDT and stack in extended RAM, the handler stores to both
; extended and conventional memory. Checks dword/byte stores, copies through
; conventional memory and deep CALL/PUSH recursion. Mismatch: port 7FE4h
; (registers) then 7FF0h <- DEADh; success: 7FF0h <- 600Dh.
bits 16
cpu 486
org 100h
ROUNDS  equ 24
EXT     equ 180000h             ; test buffers
STK     equ 1A0000h             ; stack top
IDTB    equ 1B0000h
IRQSCR  equ 1C0000h
PDIR    equ 1D0000h
PTAB    equ 1D1000h
LOWA    equ 4000h               ; conventional buffers, CS-relative
LOWB    equ 6000h
    cli
    cld
    mov ax,cs
    mov ds,ax
    xor al,al
    out 0f2h,al
    lgdt [gdtr]
    mov eax,cr0
    or al,1
    mov cr0,eax
    jmp dword 8:pm32
align 8
gdt:
    dq 0
    dq 00cf9a010000ffffh        ; 08h code, base 10000h
    dq 00cf92000000ffffh        ; 10h flat data
gdtr:
    dw $-gdt-1
    dd 10000h+gdt
bits 32
pm32:
    mov ax,10h
    mov ds,ax
    mov es,ax
    mov ss,ax
    mov esp,STK
    mov ebp,10000h
    ; IDT: vector 08h = timer, everything else = stray
    mov edi,IDTB
    xor ecx,ecx
.idt: mov eax,stray
    cmp ecx,8
    jne .g
    mov eax,timer
.g: mov [edi],ax
    mov word [edi+2],08h
    mov word [edi+4],8E00h
    shr eax,16
    mov [edi+6],ax
    add edi,8
    inc ecx
    cmp ecx,30h
    jb .idt
    lidt [ebp+idtr]
%ifdef PAGING
    ; identity map 0-4 MB, tables in extended RAM
    mov edi,PDIR
    mov ecx,1024
    xor eax,eax
    rep stosd
    mov dword [PDIR],PTAB+7
    mov edi,PTAB
    mov eax,7
    mov ecx,1024
.pt: stosd
    add eax,1000h
    loop .pt
    mov eax,PDIR
    mov cr3,eax
    mov eax,cr0
    or eax,80000000h
    mov cr0,eax
    jmp .pg
.pg:
%endif
    ; conventional source pattern
    lea edi,[ebp+LOWA]
    mov ecx,1000h/4
    mov eax,13579BDFh
.lp: stosd
    rol eax,3
    add eax,ecx
    loop .lp
    mov al,0FEh
    out 02h,al                  ; unmask IRQ0
    sti
    xor ebx,ebx                 ; round
round:
    ; T0: dword pattern 8 KB
    mov edi,EXT
.t0w: lea eax,[edi+ebx]
    xor eax,5A3CC3A5h
    mov [edi],eax
    add edi,4
    cmp edi,EXT+2000h
    jb .t0w
    mov esi,EXT
.t0r: lea eax,[esi+ebx]
    xor eax,5A3CC3A5h
    cmp [esi],eax
    jne fail0
    add esi,4
    cmp esi,EXT+2000h
    jb .t0r
    ; T1: bytes 4 KB
    mov edi,EXT+2000h
.t1w: lea eax,[edi+ebx*2]
    mov [edi],al
    inc edi
    cmp edi,EXT+3000h
    jb .t1w
    mov esi,EXT+2000h
.t1r: lea eax,[esi+ebx*2]
    cmp [esi],al
    jne fail1
    inc esi
    cmp esi,EXT+3000h
    jb .t1r
    ; T2: conventional -> extended (unaligned) -> conventional
    lea esi,[ebp+LOWA]
    lea edi,[EXT+3003h+ebx]
    mov ecx,1000h/4
    rep movsd
    lea esi,[EXT+3003h+ebx]
    lea edi,[ebp+LOWB]
    mov ecx,1000h
    rep movsb
    lea esi,[ebp+LOWA]
    lea edi,[ebp+LOWB]
    mov ecx,1000h/4
    repe cmpsd
    jne fail2
    ; T3: recursion depth 200 with pushes (stack in extended RAM)
    mov ecx,200
    mov eax,ebx
    call rec
    ; expected: ebx + sum(1..200) + 200*7
    lea edx,[ebx+20100+1400]
    cmp eax,edx
    jne fail3
    inc ebx
    cmp ebx,ROUNDS
    jb round
    cli
    mov al,0FFh
    out 02h,al
    mov dx,7ff0h
    mov ax,600dh
    out dx,ax
    hlt
    jmp $

rec:                            ; eax += ecx + 7, recursing ecx times
    push ecx
    push esi
    push edi
    mov esi,ecx
    lea edi,[esi+7]
    add eax,edi
    dec ecx
    jz .done
    call rec
.done:
    pop edi
    pop esi
    pop ecx
    ret

fail0: mov ebp,0
    jmp report
fail1: mov ebp,1
    jmp report
fail2: mov ebp,2
    jmp report
fail3: mov ebp,3
report:
    cli
    mov dx,7fe4h
    out dx,ax
    mov dx,7ff0h
    mov ax,0deadh
    out dx,ax
    hlt
    jmp $

timer:
    push eax
    push edx
    mov edx,10000h
    mov eax,[edx+irqcnt]
    inc eax
    mov [edx+irqcnt],eax         ; conventional RMW
    and eax,3Fh
    add [IRQSCR+eax*4],eax       ; extended RMW
    mov [IRQSCR+100h+eax*2],al   ; extended byte store
    mov al,20h
    out 00h,al
    pop edx
    pop eax
    iretd
stray:
    cli
    mov ebp,99
    jmp report

bits 16
idtr    dw 30h*8-1
        dd IDTB
irqcnt  dd 0
