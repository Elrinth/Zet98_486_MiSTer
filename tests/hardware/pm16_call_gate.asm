; SPDX-License-Identifier: GPL-3.0-or-later
; Ring-3 to ring-0 call through a 286 call gate with six parameter words,
; as Windows 95 Setup's SYSDETMG.DLL builds for port I/O under enhanced
; mode: ring 3 rewrites an LDT code descriptor's DPL to 0 through an LDT
; data alias, builds a DPL-3 call gate to it in the LDT, pushes six words and
; calls it; the ring-0 code returns with RETF 12. Each round toggles the
; descriptor's DPL again so a stale descriptor would be used.
; Loaded at 1000:0100 by z486_xms_resident_tb. Reports 600Dh to port 7FF0h;
; on failure EBP holds the stage (exceptions: 100h+vector, EBX = error code)
; and 0BADh goes to port 7FE4h.
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
%define GATE      27h
%define TDESC     18h
%define GDESC     20h
%define ROUNDS    100
%define FLAT_DATA 28h
%ifdef FLAT_SS0
%define SS0_SEL   FLAT_DATA         ; VMM-style flat 32-bit ring-0 stack
%else
%define SS0_SEL   R0_DATA
%endif

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
        mov     cx, 32
.id:    mov     [si], di
        mov     word [si+2], R0_CODE
        mov     word [si+4], 8600h
        mov     word [si+6], 0
        add     si, 8
        add     di, stub_size
        loop    .id
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
%ifdef ESP_HIGH
        ; Windows leaves ESP[31:16] nonzero with a 16-bit ring-3 SS (Win95
        ; Setup: ESP 8001B2DA). Only SP addresses the stack; the gate must
        ; copy its parameter words from SS:SP.
        mov     eax, esp
        and     eax, 0FFFFh
        or      eax, 80010000h
        mov     esp, eax
%endif
        mov     ax, LDT_ALIAS
        mov     es, ax
        mov     ebp, 1
        mov     ax, cs
        and     ax, 3
        cmp     ax, 3
        jne     fail
        mov     cx, ROUNDS
.round: ; Descriptor back to DPL 3, then DPL 0 exactly as SYSDETMG does it.
        or      byte [es:TDESC+5], 60h
        and     byte [es:TDESC+5], 9Fh
        ; Gate: offset, selector, then count/type/access like SYSDETMG.
        mov     word [es:GDESC], gate_target
%ifdef TARGET_RPL3
        ; Windows stores AllocSelector's RPL-3 selector in the gate (2367h);
        ; a call gate ignores its target selector's RPL.
        mov     word [es:GDESC+2], TARGET | 3
%else
        mov     word [es:GDESC+2], TARGET
%endif
        mov     al, [es:GDESC+4]
        xor     al, 6
        and     ax, 0Fh
        xor     [es:GDESC+4], ax
        and     byte [es:GDESC+4], 0Fh
        mov     ax, [es:GDESC+4]
        and     ah, 0F4h
        or      ah, 4
        mov     [es:GDESC+4], ax
        and     byte [es:GDESC+5], 0EFh
        or      byte [es:GDESC+5], 0E0h
        mov     word [es:GDESC+6], 0
        mov     [r3sp], sp
        pushf
        push    word 1111h
        push    word 2222h
        push    word 3333h
        push    word 4444h
        push    word 5555h
        push    cx                      ; varies per round
        call    GATE:0
        popf
        mov     ebp, 2
        cmp     sp, [r3sp]
        jne     fail
        mov     ebp, 3
        mov     bx, cx
        add     bx, 1111h+2222h+3333h+4444h+5555h
        cmp     ax, bx
        jne     fail
        mov     ebp, 4
        cmp     dx, 0C0DEh              ; ring-0 checks passed
        jne     fail
        mov     ebp, 5
        mov     bx, ds
        cmp     bx, R3_DATA
        jne     fail
        mov     bx, cs
        cmp     bx, R3_CODE
        jne     fail
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

; Ring 0 through the gate: CS = TARGET (DPL 0), stack from TSS SS0:SP0.
gate_target:
        push    bp
        mov     ebp, esp                ; ESP for a flat SS0, SP otherwise
%ifndef FLAT_SS0
        movzx   ebp, bp
%endif
        mov     dx, 0BAD0h
        mov     ax, cs
        and     ax, 3
        jnz     .ret                    ; must run at CPL 0
        mov     ax, ss
        cmp     ax, SS0_SEL
        jne     .ret
        cmp     word [ss:ebp+4], R3_CODE ; caller CS
        jne     .ret
        cmp     word [ss:ebp+20], R3_DATA ; caller SS after the six words
        jne     .ret
        mov     ax, [ss:ebp+6]          ; copied words, last pushed first
        add     ax, [ss:ebp+8]
        add     ax, [ss:ebp+10]
        add     ax, [ss:ebp+12]
        add     ax, [ss:ebp+14]
        add     ax, [ss:ebp+16]
        mov     dx, 0C0DEh
.ret:   pop     bp
        retf    12

; Exception stubs (ring 0): EBP = 100h + vector, EBX = error code if any.
stubs:
%assign v 0
%rep 32
        mov     ebp, 100h+v
        jmp     near exc
%assign v v+1
%endrep
stub_size equ 9
exc:    xor     ebx, ebx
        cmp     bp, 108h
        jb      .noerr
        cmp     bp, 10Eh
        ja      .noerr
        cmp     bp, 109h
        je      .noerr
        pop     bx
.noerr: mov     dx, 7FE4h
        mov     ax, 0BADh
        out     dx, ax
        hlt
        jmp     short exc

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
idtr:   dw      32*8-1
        dd      0
base:   dd      0
r3sp:   dw      0
align 8
idt:    times   32*8 db 0
