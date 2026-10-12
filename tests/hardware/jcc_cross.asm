; SPDX-License-Identifier: GPL-3.0-or-later
; Branches whose displacement lies on the next page. Windows 95 KERNEL32 has
; "je rel8" (74 EE) at BFF94FFF with BFF95000 paged out: a 486 raises #PF
; (CR2 = the next page), Windows pages it in and retries. The core stopped
; at that EIP for good (no fault, no interrupts) and the desktop never came
; up. Each case places the branch opcode on the last byte of a page, with
; the next page cached, out of the TLB or not present; the target returns
; AL=2, the fall-through AL=1. Port 7FE4h prints the registers (EBP = case
; number); 7FF0h gets 600Dh.
bits 16
cpu 486
org 1000h
%ifdef HIGH
X       equ 300fffh             ; extended memory (DDR path)
N       equ 301000h
%else
X       equ 30fffh              ; branch opcode at the last byte of a page
N       equ 31000h              ; next page
%endif
XPTE    equ 21000h + (N >> 12) * 4
IDT     equ 22000h
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
dq 00cf9a000000ffffh            ; 08h flat code
dq 00cf92000000ffffh            ; 10h flat data
tssd: dw 67h, tss, 8900h, 0     ; 18h TSS
dq 00cffa000000ffffh            ; 20h flat code, DPL 3 (23h)
dq 00cff2000000ffffh            ; 28h flat data, DPL 3 (2Bh)
gdtr:
dw $-gdt-1
dd gdt
idtr:
dw 20h*8-1
dd IDT
align 4
tss: times 68h db 0
bits 32
pm32:
mov ax,10h
mov ds,ax
mov es,ax
mov ss,ax
mov esp,9000h
mov edi,IDT
xor ecx,ecx
.gate:
mov eax,bad_vector
cmp ecx,14
jne .not_pf
mov eax,pf_handler
.not_pf:
mov edx,8e00h
cmp ecx,1fh
jne .not_1f
mov eax,r3gate
mov edx,0ee00h                  ; DPL 3
.not_1f:
mov ebx,eax
and eax,0ffffh
or eax,80000h
and ebx,0ffff0000h
or edx,ebx
mov [edi+ecx*8],eax
mov [edi+ecx*8+4],edx
inc ecx
cmp ecx,20h
jne .gate
lidt [idtr]
mov dword [tss+4],9000h
mov dword [tss+8],10h
mov word [tss+66h],68h
mov ax,18h
ltr ax
mov edi,20000h                  ; identity-map 0-4 MB
mov dword [edi],21000h | 7
mov edi,21000h
mov eax,7                       ; user pages
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
xor ebp,ebp

; short form: OP at X, rel8 = 3 at N, fall-through N+1: mov al,1/ret,
; target N+4: mov al,2/ret
%macro SHORT 1
    mov byte [X],%1
    mov dword [N],0c301b003h
    mov dword [N+4],0c302b0h
%endmacro
; near form: 0F at X, 8x rel32 = 3 at N, fall-through N+5, target N+8
%macro NEAR 1
    mov byte [X],0fh
    mov dword [N],03h << 8 | %1
    mov dword [N+4],0c301b000h  ; N+4: 00, N+5: mov al,1 / ret
    mov dword [N+8],0c302b0h    ; N+8: mov al,2 / ret
%endmacro
; mode 0: warm, 1: next page out of the TLB, 2: next page not present
%macro CASE 5                   ; flags-setup, expected AL, mode, expected faults, ecx
    inc ebp
    mov dword [faults],0
%if %3 >= 1
    invlpg [N]
%endif
%if %3 == 2
    and dword [XPTE],0fffffffeh
    invlpg [N]
%endif
    mov ecx,%5
    mov al,0
    %1
    call X
    cmp al,%2
    jne fail
    cmp dword [faults],%4
    jne fail
%endmacro
%macro ZF1 0
    cmp eax,eax
%endmacro
%macro ZF0 0
    or esp,esp
%endmacro

%assign m 0
%rep 3
%assign f (m == 2)
    SHORT 74h                   ; je
    CASE ZF1, 2, m, f, 5
    CASE ZF0, 1, m, f, 5
    SHORT 75h                   ; jne
    CASE ZF0, 2, m, f, 5
    SHORT 0ebh                  ; jmp short
    CASE ZF1, 2, m, f, 5
    SHORT 0e2h                  ; loop
    CASE ZF1, 2, m, f, 5
    CASE ZF1, 1, m, f, 1
    SHORT 0e3h                  ; jecxz
    CASE ZF1, 2, m, f, 0
    NEAR 84h                    ; je near
    CASE ZF1, 2, m, f, 5
    CASE ZF0, 1, m, f, 5
%assign m m+1
%endrep

; Windows' shape: a call returns to "test eax,eax / je rel8" whose 74 is the
; last byte of the page (KERNEL32 BFF94FFD). X-2: 85 C0, X: 74, N: rel8 3.
%macro RETCASE 3                ; eax, expected AL, mode
    inc ebp
    mov dword [faults],0
    SHORT 74h
    mov word [X-2],0c085h
%if %3 >= 1
    invlpg [N]
%endif
%if %3 == 2
    and dword [XPTE],0fffffffeh
    invlpg [N]
%endif
    push dword .back%[ebpc]
    push dword X-2
    mov eax,%1
    ret
.back%[ebpc]:
    cmp al,%2
    jne fail
    cmp dword [faults],(%3 == 2)
    jne fail
%assign ebpc ebpc+1
%endmacro
%assign ebpc 0
%ifndef NORET
RETCASE 0, 2, 0
RETCASE 1, 1, 0
RETCASE 0, 2, 1
RETCASE 0, 2, 2
RETCASE 1, 1, 2
%endif


; Any instruction split at the page end, behind a short predecessor on the
; same page (Explorer 00407FFD: push 43h / xor esi,esi with 00408000 paged
; out). Each pattern runs warm and with the next page not present; after it
; N+k holds "pop eax / ret" (eax = 43h pushed by the predecessor or a
; marker). PUTB writes bytes from address %1.
%macro PUTB 2-*
    %assign a %1
    %rotate 1
    %rep %0-1
        mov byte [a],%1
        %assign a a+1
        %rotate 1
    %endrep
%endmacro
; SPLIT case-label, mode, predecessor bytes count, then the full byte list
; starting at X-count; ESI/EAX/EBX results checked by the caller
%macro SPLITRUN 1               ; mode
    inc ebp
    mov dword [faults],0
%if %1 >= 1
    invlpg [N]
%endif
%if %1 == 2
    and dword [XPTE],0fffffffeh
    invlpg [N]
%endif
    mov esi,-1
    mov ebx,-1
    mov dword [scratch],12345678h
    push ebp
    mov ebp,scratch+4
    call [split_entry]
    pop ebp
    cmp dword [faults],(%1 == 2)
    jne fail
%endmacro
%macro CHECK 2
    cmp %1,%2
    jne fail
%endmacro

%assign m 0
%rep 3
    ; push 43h / xor esi,esi (33 F6) / pop eax / ret
    PUTB X-2, 6ah,43h,33h,0f6h,58h,0c3h
    mov dword [split_entry],X-2
    SPLITRUN m
    CHECK eax,43h
    CHECK esi,0
    ; test eax,eax / xor esi,esi / push 43h / pop eax / ret
    PUTB X-2, 85h,0c0h,33h,0f6h,6ah,43h,58h,0c3h
    SPLITRUN m
    CHECK esi,0
    CHECK eax,43h
    ; nop / mov ebx,[ebp-4] (8B 5D FC) / push 43h / pop eax / ret
    PUTB X-1, 90h,8bh,5dh,0fch,6ah,43h,58h,0c3h
    mov dword [split_entry],X-1
    SPLITRUN m
    CHECK ebx,12345678h
    ; push esi / mov eax,43h (B8 imm32) / pop esi / ret   (the push/pop pair)
    PUTB X-1, 56h,0b8h,43h,0,0,0,5eh,0c3h
    SPLITRUN m
    CHECK eax,43h
    ; nop / movzx esi,al (0F B6 F0), 0F at the page end / ret
    PUTB X-1, 90h,0fh,0b6h,0f0h,0c3h
    mov eax,1234h
    SPLITRUN m
    CHECK esi,34h
    ; Explorer 00407FF6 verbatim: push ebp / mov ebp,esp / sub esp,8 /
    ; push esi / push 43h / xor esi,esi | pop eax / pop esi / leave / ret
    PUTB X-9, 55h,8bh,0ech,83h,0ech,08h,56h,6ah,43h,33h,0f6h,58h,5eh,0c9h,0c3h
    mov dword [split_entry],X-9
    SPLITRUN m
    CHECK eax,43h
    CHECK esi,-1
    mov dword [split_entry],X-1
    ; nop / bswap-free 0F 8x: setz bl (0F 94 C3) / ret
    PUTB X-1, 90h,0fh,94h,0c3h,0c3h
    SPLITRUN m
%assign m m+1
%endrep

%ifndef NORING3
; the same from ring 3 (#PF switches to the ring-0 stack)
mov dword [r3case],0
%assign r 0
%rep 3
    inc ebp
    mov dword [faults],0
    SHORT 74h
    mov word [X-2],0c085h
%if r >= 1
    invlpg [N]
%endif
%if r == 2
    and dword [XPTE],0fffffffeh
    invlpg [N]
%endif
    mov [r0esp],esp
    mov dword [r3cont],.r3back%[r]
    push dword 2bh
    push dword 7000h
    push dword 3002h            ; IOPL 3
    push dword 23h
    push dword r3entry
    iretd
.r3back%[r]:
    mov esp,[r0esp]
    cmp byte [r3al],2
    jne fail
    cmp dword [faults],(r == 2)
    jne fail
%assign r r+1
%endrep
; Explorer's split prologue from ring 3
PUTB X-9, 55h,8bh,0ech,83h,0ech,08h,56h,6ah,43h,33h,0f6h,58h,5eh,0c9h,0c3h
mov dword [split_entry],X-9
%assign r 0
%rep 3
    inc ebp
    mov dword [faults],0
%if r >= 1
    invlpg [N]
%endif
%if r == 2
    and dword [XPTE],0fffffffeh
    invlpg [N]
%endif
    mov [r0esp],esp
    mov dword [r3cont],.r3xback%[r]
    push dword 2bh
    push dword 7000h
    push dword 3002h
    push dword 23h
    push dword r3split
    iretd
.r3xback%[r]:
    mov esp,[r0esp]
    cmp dword [r3al],43h
    jne fail
    cmp dword [faults],(r == 2)
    jne fail
%assign r r+1
%endrep
%endif
mov ax,600dh
jmp report

r3entry:
mov ax,2bh
mov ds,ax
mov es,ax
push dword r3done
push dword X-2
xor eax,eax
ret
r3done:
mov [r3al],al
int 1fh
r3split:
mov ax,2bh
mov ds,ax
mov es,ax
mov esi,-1
call [split_entry]
mov [r3al],eax
int 1fh                         ; back to ring 0 (gate DPL 3)
r3gate:
mov ax,10h
mov ds,ax
mov es,ax
mov esp,[r0esp]
jmp [r3cont]


pf_handler:
inc dword [faults]
push eax
mov eax,cr2
cmp eax,N
pop eax
jne fail
or dword [XPTE],1               ; present again
invlpg [N]
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
split_entry dd 0
scratch dd 0
r0esp dd 0
r3cont dd 0
r3al dd 0
r3case dd 0
