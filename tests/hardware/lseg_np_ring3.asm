; SPDX-License-Identifier: GPL-3.0-or-later
; LFS/LGS/LES of a not-present selector from 16-bit ring 3, as Windows 95
; USER does on a discarded segment ("lfs si,es:[5Ah]"): the load must raise
; #NP (vector 11) with error code = selector index/TI, the saved IP must be
; the faulting instruction, and the destination offset register and segment
; register must be unchanged. The ring-0 handler marks the descriptor present
; and returns; the retried load must then complete. On the core the ring-0
; stack overflowed right after such a #NP and Windows hung at USER's
; "Display Resources" step.
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
%define NPSEL     2Fh
%define NPDESC    28h
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
        mov     si, ldt+NPDESC
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
        mov     word [idt+11*8], np     ; #NP handler
%ifdef GATE386
        mov     word [idt+11*8+4], 8E00h ; 386 interrupt gate (Windows' VMM)
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
        mov     es, ax
        mov     fs, ax
        mov     gs, ax
        mov     cx, 50
.round:
%macro LOADCASE 4                       ; stage, insn, offset reg, segment reg
        mov     ebp, %1
        mov     byte [np_seen], 0
        mov     si, 5555h
        mov     di, 5555h
        mov     bx, 5555h
        mov     word [expect_ip], %%insn
        mov     word [expect_reg], 5555h
%%insn: %2      %3, [es:fptr]
        cmp     byte [np_seen], 1
        jne     fail
        cmp     %3, 1234h
        jne     fail
        mov     ax, %4
        cmp     ax, NPSEL
        jne     fail
        mov     ax, LDT_ALIAS           ; not present again
        mov     %4, ax
        and     byte [%4:NPDESC+5], 7Fh
        mov     ax, R3_DATA
        mov     %4, ax
%endmacro
        LOADCASE 1, lfs, si, fs
        LOADCASE 2, lgs, di, gs
        LOADCASE 3, lfs, bx, fs
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

; #NP handler (ring 0, vector 11, 286 gate): error code = NPSEL index/TI,
; IP = the faulting load, offset register and segment register unchanged.
%ifdef GATE386
; 386 gate: 32-bit frame on the flat TSS stack: err, EIP, CS, EFLAGS, ESP, SS.
np:     mov     ebp, esp
        mov     eax, [tss+4]
        sub     eax, 6*4
        cmp     ebp, eax                ; the frame must sit right below ESP0
        jne     .bad
        mov     ax, [ss:ebp]
        cmp     ax, NPSEL & 0FFFCh
        jne     .bad
        mov     ax, R3_DATA
        mov     ds, ax
        mov     ax, [ss:ebp+4]
        cmp     ax, [expect_ip]
        jne     .bad
        cmp     si, 1234h
        je      .bad
        cmp     di, 1234h
        je      .bad
        cmp     bx, 1234h
        je      .bad
        mov     ax, fs
        cmp     ax, NPSEL
        je      .bad
        mov     ax, gs
        cmp     ax, NPSEL
        je      .bad
        mov     byte [np_seen], 1
        mov     ax, LDT_ALIAS
        mov     es, ax
        or      byte [es:NPDESC+5], 80h ; present
        mov     ax, R3_DATA
        mov     es, ax
        add     esp, 4                  ; error code
        iretd
.bad:   mov     bx, [ss:ebp]
        mov     ebp, 10Bh
        jmp     exc_out
%else
np:     push    bp
        mov     bp, sp
        push    ds
        push    ax
        mov     ax, R3_DATA
        mov     ds, ax
        mov     ax, [ss:bp+2]
        cmp     ax, NPSEL & 0FFFCh
        jne     .bad
        mov     ax, [ss:bp+4]
        cmp     ax, [expect_ip]
        jne     .bad
        cmp     si, 1234h               ; offset must not be loaded yet
        je      .bad
        cmp     di, 1234h
        je      .bad
        cmp     bx, 1234h
        je      .bad
        mov     ax, fs
        cmp     ax, NPSEL
        je      .bad
        mov     ax, gs
        cmp     ax, NPSEL
        je      .bad
        mov     byte [np_seen], 1
        push    es
        mov     ax, LDT_ALIAS
        mov     es, ax
        or      byte [es:NPDESC+5], 80h ; present
        pop     es
        pop     ax
        pop     ds
        pop     bp
        add     sp, 2                   ; error code
        iret
.bad:   mov     bx, [ss:bp+2]
        mov     ebp, 10Bh
        jmp     exc_out

%endif
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
        dw      0FFFFh, 0, 7200h, 0     ; 2C data16 DPL3, not present
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
np_seen: db     0
align 2
expect_ip: dw   0
expect_reg: dw  0
fptr:   dw      1234h, NPSEL
align 8
idt:    times   42h*8 db 0
