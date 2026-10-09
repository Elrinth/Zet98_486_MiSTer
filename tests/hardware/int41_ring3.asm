; SPDX-License-Identifier: GPL-3.0-or-later
; INT 41h from 16-bit ring 3, as Windows 95 KERNEL's debugger check
; ("mov ax,4Fh / int 41h"). With a DPL-0 gate the INT must raise #GP (vector
; 13) with error code 41h*8+2 = 20Ah; with a DPL-3 gate it reaches its
; handler. On the core the DPL-0 case read IDT entry 0 (#DE): Windows then
; looped in its #DE handler and hung at USER's "Display Resources" step.
; Loaded at 1000:0100 by z486_xms_resident_tb. Reports 600Dh to port 7FF0h;
; on failure EBP = stage (exceptions: 100h+vector, EBX = error code) and
; 0BADh goes to port 7FE4h.
        cpu     486
        org     100h
bits 16
%define R0_CODE   08h
%define R0_DATA   10h
%define TSS_SEL   18h
%define LDT_SEL   20h
%define R3_CODE   07h
%define R3_DATA   0Fh
%define LDT_ALIAS 17h
%define TARGET    1Ch
%define FLAT_DATA 28h
%define SS0_SEL   FLAT_DATA

start:  cli
        cld
        mov     ax, cs
        mov     ds, ax
        movzx   eax, ax
        shl     eax, 4
        mov     [base], eax
        mov     si, gdt+8
        call    setbase
        mov     si, gdt+16
        call    setbase
        mov     si, gdt+TSS_SEL
        mov     edx, tss
        call    setbase_off
        mov     si, gdt+LDT_SEL
        mov     edx, ldt
        call    setbase_off
        mov     si, ldt
        call    setbase
        mov     si, ldt+8
        call    setbase
        mov     si, ldt+16
        mov     edx, ldt
        call    setbase_off
        mov     si, ldt+24
        call    setbase
        mov     eax, [base]
        add     eax, 0F000h
        mov     [tss+4], eax            ; flat ESP0 = linear address
%ifndef FLAT_SS0
        mov     dword [tss+4], 0F000h
%endif
        mov     eax, [base]
        add     eax, gdt
        mov     [gdtr+2], eax
        mov     eax, [base]
        add     eax, idt
        mov     [idtr+2], eax
        mov     si, idt                 ; 32 286 interrupt gates to the stubs
        mov     di, stubs
        mov     cx, 42h
.id:    mov     [si], di
        mov     word [si+2], R0_CODE
        mov     word [si+4], 8600h
        mov     word [si+6], 0
        add     si, 8
        add     di, stub_size
        loop    .id
        mov     word [idt+13*8], gp     ; #GP handler
        mov     word [idt+41h*8], int41  ; INT 41h
%ifdef DPL3
        mov     word [idt+41h*8+4], 0E600h
%endif
        lgdt    [gdtr]
        lidt    [idtr]
        mov     eax, cr0
        or      al, 1
        mov     cr0, eax
        jmp     R0_CODE:pm
pm:     mov     ax, R0_DATA
        mov     ds, ax
        mov     es, ax
        mov     ss, ax
        mov     sp, 0F000h
        mov     ax, LDT_SEL
        lldt    ax
        mov     ax, TSS_SEL
        ltr     ax
        pushf                           ; IOPL 3 for the report ports
        pop     ax
        or      ah, 30h
        push    ax
        popf
        push    word R3_DATA            ; to ring 3
        push    word 0E000h
        push    word R3_CODE
        push    word ring3
        retf

ring3:  mov     ax, R3_DATA
        mov     ds, ax
        mov     cx, 50
.round: mov     ebp, 1
        mov     byte [gp_seen], 0
        mov     ax, 4Fh
        int     41h
%ifdef DPL3
        mov     ebp, 2                  ; DPL-3 gate: the handler answered
        cmp     ax, 0F386h
        jne     fail
%else
        mov     ebp, 3                  ; DPL-0 gate: #GP(20Ah) skipped the INT
        cmp     byte [gp_seen], 1
        jne     fail
%endif
        dec     cx
        jnz     .round
        mov     dx, 7FF0h
        mov     ax, 600Dh
        out     dx, ax
        hlt
        jmp     short $

fail:   mov     dx, 7FE4h
        mov     ax, 0BADh
        out     dx, ax
        hlt
        jmp     short $

; IDT 41h handler (ring 0): debugger "present" answer.
int41:  mov     ax, 0F386h
        iret

; #GP handler (ring 0, vector 13): must see error code 41h*8+2 from INT 41h.
gp:     push    bp
        mov     bp, sp
        cmp     word [ss:bp+2], 41h*8+2
        jne     .bad
        push    ds
        push    ax
        mov     ax, R3_DATA
        mov     ds, ax
        mov     byte [gp_seen], 1
        pop     ax
        pop     ds
        add     word [ss:bp+4], 2       ; skip the INT 41h (CD 41)
        pop     bp
        add     sp, 2                   ; error code
        iret
.bad:   mov     bx, [ss:bp+2]
        mov     ebp, 10Dh
        jmp     exc_out

; Exception stubs (ring 0): EBP = 100h + vector, EBX = error code if any.
stubs:
%assign v 0
%rep 42h
        mov     ebp, 100h+v
        jmp     near exc
%assign v v+1
%endrep
stub_size equ 9
exc:    xor     ebx, ebx
        cmp     bp, 108h
        jb      exc_out
        cmp     bp, 10Eh
        ja      exc_out
        cmp     bp, 109h
        je      exc_out
        pop     bx
exc_out: mov     dx, 7FE4h
        mov     ax, 0BADh
        out     dx, ax
        hlt
        jmp     short exc_out

setbase:                                ; descriptor base = program base
        mov     edx, 0
setbase_off:                            ; descriptor base = program base + edx
        mov     eax, [base]
        add     eax, edx
        mov     [si+2], ax
        shr     eax, 16
        mov     [si+4], al
        mov     [si+7], ah
        ret

align 8
gdt:    dq      0
        dw      0FFFFh, 0, 9A00h, 0     ; 08 code16 DPL0
        dw      0FFFFh, 0, 9200h, 0     ; 10 data16 DPL0
        dw      67h, 0, 8900h, 0        ; 18 386 TSS
        dw      ldt_end-ldt-1, 0, 8200h, 0 ; 20 LDT
        dw      0FFFFh, 0, 9200h, 00CFh ; 28 flat 32-bit data, 4 GB
gdt_end:
ldt:    dw      0FFFFh, 0, 0FA00h, 0    ; 04 code16 DPL3
        dw      0FFFFh, 0, 0F200h, 0    ; 0C data16 DPL3
        dw      ldt_end-ldt-1, 0, 0F200h, 0 ; 14 LDT alias DPL3
        dw      0FFFFh, 0, 0FA00h, 0    ; 1C code16, DPL rewritten
        dq      0                       ; 24 call gate
ldt_end:
align 4
tss:    dd      0
        dd      0F000h                  ; ESP0
        dd      SS0_SEL                 ; SS0
        times   23 dd 0
        dw      0, 68h
gdtr:   dw      gdt_end-gdt-1
        dd      0
idtr:   dw      42h*8-1
        dd      0
base:   dd      0
r3sp:   dw      0
gp_seen: db     0
align 8
idt:    times   42h*8 db 0
