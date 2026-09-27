; SPDX-License-Identifier: GPL-3.0-or-later
; Self-authored virtual-8086 monitor test, modelled on what EMM386/VEM486 do:
; paging with an EMS-style remapped page and supervisor-only monitor pages, a TSS with an I/O permission bitmap,
; an IDT with a ring-0 monitor, IRETD into V86 mode, then sensitive
; instructions trapped (#GP) or executed natively depending on IOPL, a page
; fault resolved by mapping the page, and a software interrupt reflected into
; the V86 interrupt vector table. Loaded at 1000:0100. Reports 600Dh to port
; 7FF0h on success; on failure EBP holds the failure code (CPU REPORT 7FE4h).
; A CPU reset (for example a triple fault) is detected and reported as 0B0Fh.
        cpu     486
        org     100h
LIN     equ     10000h                  ; linear base of this segment
PD      equ     20000h
PT      equ     21000h
%ifdef EMM_SEQ
%define EXT_PT
%endif
%ifdef EXT_PT
; Page tables in extended memory, written through the data cache from
; protected mode just before paging is enabled (as EMM386 does with XMS).
PD_ACT  equ     200000h
PT_ACT  equ     201000h
%else
PD_ACT  equ     PD
PT_ACT  equ     PT
%endif
TSS     equ     22000h
TSS_LIM equ     104 + 8192 + 1 - 1
TRAPPED equ     3Fh                     ; port marked in the I/O bitmap
ALLOWED equ     7FE6h                   ; port left open (reads FFFFh)

bits 16
start:  cli
        cld
        mov     ax, cs
        mov     ds, ax
        mov     ss, ax
        mov     sp, 0FFF0h
        xor     ax, ax
        mov     fs, ax
        cmp     word [fs:500h], 0B007h  ; second pass: the CPU was reset
        jne     .first
        mov     ebp, 0B0Fh
        jmp     rm_fail
.first: mov     word [fs:500h], 0B007h
        xor     al, al                  ; PC-98: enable A20 (extended memory at 1MB+)
        out     0F2h, al
        ; page directory: one table, user/rw
        mov     ax, PD >> 4
        mov     es, ax
        xor     di, di
        mov     eax, PT | 7
        stosd
        xor     eax, eax
        mov     cx, 1023
        rep     stosd
        ; page table: identity map 0-4MB
        mov     ax, PT >> 4
        mov     es, ax
        xor     di, di
        mov     eax, 7
        mov     cx, 1024
.pt:    stosd
        add     eax, 1000h
        loop    .pt
        mov     dword [es:30h * 4], 110000h | 7   ; "EMS" page -> extended RAM
        mov     dword [es:31h * 4], 0             ; not present until #PF
        mov     dword [es:2Eh * 4], 2E000h | 3    ; ring-0 stack: supervisor only
        mov     dword [es:22h * 4], 22000h | 3    ; TSS
        mov     dword [es:23h * 4], 23000h | 3
        mov     dword [es:24h * 4], 24000h | 3
        ; TSS: ring-0 stack and an I/O bitmap trapping one port
        mov     ax, TSS >> 4
        mov     es, ax
        xor     di, di
        xor     al, al
        mov     cx, TSS_LIM + 1
        rep     stosb
        mov     dword [es:4], 2F000h
        mov     word [es:8], 10h
        mov     word [es:102], 104
        or      byte [es:104 + TRAPPED / 8], 1 << (TRAPPED % 8)
        mov     byte [es:104 + 8192], 0FFh
        ; V86 interrupt vector 22h
        mov     word [fs:22h * 4], v86_isr22
        mov     word [fs:22h * 4 + 2], cs
        ; IDT: 32 exception stubs, everything else "unexpected"
        push    cs
        pop     es
        mov     di, idt
        xor     bx, bx
.gate:  mov     eax, LIN + unexpected_int
        cmp     bx, 32
        jae     .set
        mov     eax, ebx
        shl     eax, 3
        add     eax, LIN + exc_stubs
.set:   mov     dx, 8E00h
        call    set_gate
        inc     bx
        cmp     bx, 256
        jb      .gate
        mov     bx, 13
        mov     eax, LIN + gp_handler
        mov     dx, 8E00h
        call    set_gate
        mov     bx, 14
        mov     eax, LIN + pf_handler
        call    set_gate
        mov     bx, 22h
        mov     eax, LIN + int22_handler
        mov     dx, 0EE00h              ; DPL 3: reachable by INT from V86 at IOPL 3
        call    set_gate
        mov     bx, 23h
        mov     eax, LIN + done_handler
        call    set_gate
%ifdef IRQ_TEST
        mov     bx, 08h                 ; timer IRQ (testbench PIT mode)
        mov     eax, LIN + irq_handler
        mov     dx, 8E00h
        call    set_gate
%endif
%ifdef EMM_SEQ
        ; EMM386's switch: tables and GDT are copied to extended memory in a
        ; short protected-mode trip (HIMEM-style), then real mode loads CR3
        ; and GDTR and sets PE and PG in one MOV CR0, then far-jumps to 0B8h.
        lgdt    [gdtr]
        mov     eax, cr0
        or      al, 1
        mov     cr0, eax
        jmp     dword 8:(LIN + copy32)
bits 32
copy32: mov     ax, 10h
        mov     ds, ax
        mov     es, ax
        cld
%ifdef UNREAL
        jmp     word 20h:back16         ; HIMEM style: only load 4 GB limits here
%endif
        mov     esi, PD
        mov     edi, PD_ACT
        mov     ecx, 2 * 1024
        rep     movsd
        mov     dword [PD_ACT], PT_ACT | 7
        mov     dword [PT_ACT + 12h * 4], 0     ; switch page (emm_stub, 12000h) unmapped
        mov     dword [PT_ACT + 312h * 4], 12000h | 3   ; ...but reachable at 312000h
        mov     esi, LIN + gdt
        mov     edi, GDT_EXT
        mov     ecx, (gdt_end - gdt) / 4
        rep     movsd
        jmp     word 20h:back16
bits 16
back16: mov     ax, 28h
%ifndef UNREAL
        mov     ds, ax
        mov     es, ax
%endif
        mov     ss, ax
        mov     eax, cr0
        and     al, 0FEh
        mov     cr0, eax
        jmp     1000h:rm_again
rm_again:
        mov     ax, cs
        mov     ds, ax
        mov     es, ax
        mov     ss, ax
        mov     sp, 0FFF0h
%ifdef UNREAL
        ; unreal mode (DS/ES keep 4 GB limits): copy to extended memory from real mode
        xor     ax, ax
        mov     ds, ax
        mov     es, ax
        cld
        mov     esi, PD
        mov     edi, PD_ACT
        mov     ecx, 2 * 1024
        a32 rep movsd
        mov     dword [es:dword PD_ACT], PT_ACT | 7
        mov     dword [es:dword PT_ACT + 12h * 4], 0
        mov     dword [es:dword PT_ACT + 312h * 4], 12000h | 3
        mov     esi, LIN + gdt
        mov     edi, GDT_EXT
        mov     ecx, (gdt_end - gdt) / 4
        a32 rep movsd
        mov     ax, cs
        mov     ds, ax
        mov     es, ax
%endif
        jmp     1000h:emm_stub          ; on its own page, not mapped by the new tables
%endif
        ; protected mode with paging
        lgdt    [gdtr]
        lidt    [idtr]
        mov     eax, PD
        mov     cr3, eax
        mov     eax, cr0
%ifdef EXT_PT
        or      eax, 1                  ; paging is enabled in pm32
%else
        or      eax, 80000001h
%endif
        mov     cr0, eax
        jmp     dword 8:(LIN + pm32)
set_gate:                               ; bx vector, eax offset, dx attributes
        push    di
        mov     di, bx
        shl     di, 3
        add     di, idt
        mov     [di], ax
        mov     word [di + 2], 8
        mov     [di + 4], dx
        push    eax
        shr     eax, 16
        mov     [di + 6], ax
        pop     eax
        pop     di
        ret
rm_fail:
        mov     dx, 7FE4h
        out     dx, ax
        mov     ax, 0DEADh
        mov     dx, 7FF0h
        out     dx, ax
        hlt
        jmp     $

bits 32
pm32:   mov     ax, 10h
        mov     ds, ax
        mov     es, ax
        mov     fs, ax
        mov     gs, ax
        mov     ss, ax
        mov     esp, 2F000h
%ifdef EXT_PT
%ifndef EMM_SEQ
        mov     esi, PD                 ; copy the tables to extended memory
        mov     edi, PD_ACT
        mov     ecx, 2 * 1024
        cld
        rep     movsd
        mov     dword [PD_ACT], PT_ACT | 7
        mov     eax, PD_ACT
        mov     cr3, eax
        mov     eax, cr0
        or      eax, 80000000h
        mov     cr0, eax
        jmp     short .paged
.paged:
%endif
        mov     ebp, 60                 ; first paged accesses through the new tables
        cmp     word [30000h], 0        ; EMS page (fresh extended RAM reads as 0... or any)
        mov     eax, [PT_ACT + 30h * 4]
        and     eax, ~60h                       ; the walk sets Accessed (and Dirty)
        cmp     eax, 110000h | 7
        jne     fail
%endif
        mov     ax, 18h
        ltr     ax
pm32_ltr_done:
        mov     ax, 10h
        mov     ds, ax
        mov     es, ax
        mov     fs, ax
        mov     gs, ax
        ; enter V86 at 1000:v86_entry, IOPL 0, interrupts off
        push    dword 1000h             ; GS
        push    dword 1000h             ; FS
        push    dword 1000h             ; DS
        push    dword 1000h             ; ES
        push    dword 1000h             ; SS
        push    dword 0FF00h            ; ESP
        push    dword 20002h            ; EFLAGS: VM
        push    dword 1000h             ; CS
        push    dword v86_entry         ; EIP
        iretd

; #GP from V86 at IOPL 0: count the instruction and skip it. HLT also
; raises IOPL to 3 for the rest of the test.
gp_handler:
        push    eax
        push    ebx
        push    ds
        mov     ax, 10h
        mov     ds, ax
        mov     ebp, 10
        test    dword [esp + 24], 20000h        ; frame: err+12, EIP+16, CS+20, EFLAGS+24
        jz      fail
        mov     ebp, 11
        cmp     dword [esp + 12], 0
        jne     fail
        movzx   ebx, word [esp + 20]
        shl     ebx, 4
        add     ebx, [esp + 16]
        mov     al, [ebx]
        mov     ebx, 1
        cmp     al, 0FAh
        jne     .n1
        inc     byte [LIN + cnt_cli]
        jmp     .skip
.n1:    cmp     al, 9Ch
        jne     .n2
        inc     byte [LIN + cnt_pushf]
        jmp     .skip
.n2:    cmp     al, 9Dh
        jne     .n3
        inc     byte [LIN + cnt_popf]
        jmp     .skip
.n3:    cmp     al, 0F4h
        jne     .n4
        inc     byte [LIN + cnt_hlt]
        or      dword [esp + 24], 3000h         ; IOPL 3 from now on
        jmp     .skip
.n4:    mov     ebx, 2
        cmp     al, 0CDh
        jne     .n5
        inc     byte [LIN + cnt_int21]
        jmp     .skip
.n5:    cmp     al, 0E4h
        jne     .bad
        inc     byte [LIN + cnt_in]
        jmp     .skip
.bad:   mov     ebp, 12
        jmp     fail
.skip:  add     [esp + 16], ebx
        pop     ds
        pop     ebx
        pop     eax
        add     esp, 4
        iretd

; #PF from V86 writing the not-present page: map it and retry.
pf_handler:
        push    eax
        push    ds
        mov     ax, 10h
        mov     ds, ax
        mov     ebp, 20
        mov     ebx, cr2                        ; reported on failure
        mov     eax, [esp + 8]
        cmp     eax, 6                          ; user, write, not present
        jne     fail
        mov     ebp, 21
        cmp     ebx, 31000h
        jne     fail
        mov     dword [PT_ACT + 31h * 4], 111000h | 7
        mov     eax, cr3
        mov     cr3, eax
        inc     byte [LIN + cnt_pf]
        pop     ds
        pop     eax
        add     esp, 4
        iretd

; INT 22h from V86 at IOPL 3: reflect it to the V86 IVT like a monitor does.
int22_handler:
        push    eax
        push    ebx
        push    ds
        mov     ax, 10h
        mov     ds, ax
        mov     ebp, 30                         ; frame: EIP+12 CS+16 EFLAGS+20 ESP+24 SS+28 ES+32 DS+36
        test    dword [esp + 20], 20000h
        jz      fail
        mov     ebp, 31
        cmp     dword [esp + 36], 1000h
        jne     fail
        mov     ebp, 32
        cmp     dword [esp + 32], 3000h
        jne     fail
        mov     ebp, 33
        mov     eax, [esp + 20]
        and     eax, 3000h
        cmp     eax, 3000h
        jne     fail
        ; push FLAGS, CS, IP on the V86 stack
        movzx   ebx, word [esp + 28]
        shl     ebx, 4
        movzx   eax, word [esp + 24]
        sub     ax, 6
        mov     [esp + 24], eax
        add     ebx, eax
        mov     ax, [esp + 12]
        mov     [ebx], ax
        mov     ax, [esp + 16]
        mov     [ebx + 2], ax
        mov     ax, [esp + 20]
        mov     [ebx + 4], ax
        movzx   eax, word [22h * 4]
        mov     [esp + 12], eax
        movzx   eax, word [22h * 4 + 2]
        mov     [esp + 16], eax
        and     dword [esp + 20], ~300h         ; IF, TF off as a real INT does
        inc     byte [LIN + cnt_int22]
        pop     ds
        pop     ebx
        pop     eax
        iretd

; INT 23h: the V86 part is over; check everything.
done_handler:
        mov     ax, 10h
        mov     ds, ax
        mov     ebp, 40
        test    dword [esp + 8], 20000h
        jz      fail
        mov     ebp, 41
        movzx   eax, byte [LIN + v_stage]       ; which V86 check failed
        movzx   ebx, word [LIN + v_val]
        movzx   ecx, word [110000h]             ; physical page behind 30000h
        movzx   esi, word [30000h]              ; linear, from ring 0
        cmp     byte [LIN + v_fail], 0
        jne     fail
        mov     ebp, 42
        cmp     dword [LIN + cnt_cli], 01010101h        ; cli pushf popf hlt
        jne     fail
        mov     ebp, 43
        cmp     dword [LIN + cnt_int21], 01010101h      ; int21 in pf int22
        jne     fail
        mov     ebp, 44
        cmp     word [110000h], 5A5Ah
        jne     fail
        cmp     word [110FFEh], 0A55Ah
        jne     fail
        mov     ebp, 45
        cmp     word [111000h], 7777h
        jne     fail
        mov     ebp, 46
        cmp     word [30000h], 5A5Ah            ; still mapped through the page table
        jne     fail
        mov     ax, 600Dh
        mov     dx, 7FF0h
        out     dx, ax
        hlt
        jmp     $

%ifdef IRQ_TEST
irq_handler:
        push    eax
        push    ds
        mov     ax, 10h
        mov     ds, ax
        mov     ebp, 50
        test    dword [esp + 16], 20000h        ; frame: EIP+8 CS+12 EFLAGS+16
        jz      fail
        inc     word [LIN + irq_count]
        mov     al, 20h                         ; EOI
        out     00h, al
        pop     ds
        pop     eax
        iretd
%endif
unexpected_int:
        push    dword 0FFh
exc_common:
        mov     ax, 10h
        mov     ds, ax
        pop     ebp
        add     ebp, 1000                       ; 1000 + vector
        mov     eax, [esp]
        mov     ebx, [esp + 4]
        mov     ecx, [esp + 8]
fail:   mov     dx, 7FE4h
        out     dx, ax
        mov     ax, 0DEADh
        mov     dx, 7FF0h
        out     dx, ax
        hlt
        jmp     $
align 8
exc_stubs:
%assign v 0
%rep 32
        push    dword v
        jmp     exc_common
        align   8
%assign v v + 1
%endrep

bits 16
v86_entry:
        mov     ax, 1234h
        mov     [v_scratch], ax
        mov     byte [v_stage], 1
        cmp     word [v_scratch], 1234h
        jne     v86_fail
        ; IOPL 0: each of these traps to the monitor, which skips it
        cli
        pushf
        popf
        int     21h
        hlt                             ; monitor raises IOPL to 3
        ; I/O: the bitmap decides, whatever the IOPL
        mov     dx, ALLOWED
        in      ax, dx
        mov     byte [v_stage], 2
        cmp     ax, 0FFFFh
        jne     v86_fail
        in      al, TRAPPED
        ; EMS-style page and a demand-mapped page
        mov     ax, 3000h
        mov     es, ax
        mov     word [es:0], 5A5Ah
        mov     word [es:0FFEh], 0A55Ah
        mov     word [es:1000h], 7777h
        mov     byte [v_stage], 3
        cmp     word [es:1000h], 7777h
        jne     v86_fail
        mov     byte [v_stage], 4
        mov     ax, [es:0]
        mov     [v_val], ax
        cmp     ax, 5A5Ah
        jne     v86_fail
        ; IOPL 3: CLI/STI/PUSHF run natively
        sti
        pushf
        pop     ax
        mov     byte [v_stage], 41
        test    ax, 200h
        jz      v86_fail
        cli
        pushf
        pop     ax
        mov     byte [v_stage], 42
        test    ax, 200h
        jnz     v86_fail
        ; Known z486 deviation: PUSHFD in V86 stores VM=1 (a real CPU stores 0).
        ; The flags image is shared with the #GP frame of a faulting PUSHF, so
        ; it is not masked; POPF(D) in V86 ignores VM, so DOS code is unaffected.
        ; software interrupt reflected through the V86 IVT
        xor     bx, bx
        mov     sp, 0FF00h
        int     22h
        mov     byte [v_stage], 5
        cmp     bx, 0BEEFh
        jne     v86_fail
        mov     byte [v_stage], 6
        cmp     sp, 0FF00h
        jne     v86_fail
%ifdef IRQ_TEST
        ; Timer IRQs taken from V86 while a store loop runs (IOPL 3: STI/CLI
        ; and OUT to the unmasked PIC port are native).
        mov     ax, 3080h               ; EMS page, offset 800h
        mov     es, ax
        xor     cx, cx
        xor     di, di
        mov     al, 0FEh
        out     02h, al
        sti
.work:  mov     [es:di], cx
        add     di, 2
        and     di, 1FFh
        inc     cx
        cmp     word [irq_count], 5
        jb      .work
        cli
        mov     al, 0FFh
        out     02h, al
        mov     byte [v_stage], 7
        cmp     cx, 256
        jb      v86_fail
        xor     di, di                  ; entry k holds a value v with v mod 256 = k,
        xor     bx, bx                  ; written within the last 256 iterations
.chk:   mov     ax, [es:di]
        mov     byte [v_stage], 8
        cmp     al, bl
        jne     v86_fail
        mov     dx, cx
        sub     dx, ax
        mov     byte [v_stage], 9
        cmp     dx, 256
        ja      v86_fail
        add     di, 2
        inc     bx
        cmp     bx, 256
        jb      .chk
%endif
        int     23h
v86_fail:
        mov     byte [v_fail], 1
        int     23h
v86_isr22:
        mov     bx, 0BEEFh
        iret

align 8
gdt:    dq      0
        dq      00CF9A000000FFFFh       ; 08h code, flat, ring 0
        dq      00CF92000000FFFFh       ; 10h data, flat
        dq      0000890000000000h | (TSS_LIM & 0FFFFh) | ((TSS & 0FFFFFFh) << 16)
        dq      00009A010000FFFFh       ; 20h code16, base 10000h (EMM_SEQ return)
        dq      000092010000FFFFh       ; 28h data16, base 10000h
        times   (0B8h - ($ - gdt)) / 8 dq 0
%ifdef EMM_SEQ
        dq      00009A310000FFFFh       ; 0B8h code16, base 310000h: the stub page seen through
                                        ; an alias mapping (312000h -> 12000h), like EMM386's
        dq      0000921358180000h | (gdt_end - gdt - 1)   ; 0C0h data alias of the GDT at GDT_EXT
        dq      0                       ; 0C8h stack, written through the alias
%else
        dq      00CF9A000000FFFFh       ; 0B8h code, flat, ring 0 (EMM386's selector)
%endif
gdt_end:
GDT_EXT equ     135818h                 ; EMM386's GDT address (unaligned, in XMS)
gdtr_ext: dw    gdt_end - gdt - 1
        dd      GDT_EXT
gdtr:   dw      gdt_end - gdt - 1
        dd      LIN + gdt
idtr:   dw      256 * 8 - 1
        dd      LIN + idt
v_scratch dw    0
v_fail  db      0
v_stage db      0
v_val   dw      0
irq_count dw    0
align 4
cnt_cli   db    0
cnt_pushf db    0
cnt_popf  db    0
cnt_hlt   db    0
cnt_int21 db    0
cnt_in    db    0
cnt_pf    db    0
cnt_int22 db    0
align 8
idt:    times 256 * 8 db 0
%ifdef EMM_SEQ
; EMM386 runs its switch from a page its new tables do not map: the far JMP
; after MOV CR0 comes from the 486 prefetch queue, untranslated.
        times   (2000h - 100h) - ($ - $$) db 0
bits 16
emm_stub:
        mov     eax, PD_ACT
        mov     cr3, eax
        lgdt    [gdtr_ext]
        lidt    [idtr]
        mov     eax, cr0
        or      eax, 80000001h
        mov     cr0, eax
        jmp     0B8h:emm_pm16
; EMM386's first protected-mode steps (16-bit code, selector 0B8h)
emm_pm16:
        mov     ax, 18h
        ltr     ax
        xor     ax, ax
        lldt    ax
        xor     ecx, ecx
        mov     cr2, ecx
        mov     ax, 0C0h                ; write the 0C8h stack descriptor through the alias
        mov     ds, ax
        mov     word [0C8h], 0FFFFh     ; limit 64K
        mov     word [0CAh], 0E000h     ; base 02E000h (ring-0 stack page)
        mov     byte [0CCh], 02h
        mov     byte [0CDh], 92h        ; present data, writable
        mov     byte [0CEh], 0
        mov     byte [0CFh], 0
        mov     ax, 0C8h
        mov     ss, ax
        mov     sp, 0FF0h
        push    word 1234h              ; stack at 2E000h + 0FEEh through the new SS
        pop     ax
        cmp     ax, 1234h
        jne     .bad
        mov     ax, 10h
        mov     ds, ax
        cmp     word [dword 2EFEEh], 1234h
        jne     .bad
        mov     ax, 10h
        mov     ss, ax
        mov     esp, 2F000h
        jmp     dword 8:(LIN + pm32_ltr_done)
.bad:   mov     ax, 10h
        mov     ds, ax
        mov     ebp, 70
        jmp     dword 8:(LIN + fail)
%endif
