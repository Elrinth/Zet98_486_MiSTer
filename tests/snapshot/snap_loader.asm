; Snapshot loader for z486_snap_tb: enters a protected-mode CPU state captured
; from NP2kai. Stage 1 runs at 0000:1000 in real mode, stage 2 at physical
; 2000000h (above the snapshot's RAM). snap_gen.py patches the STATE block and
; points the snapshot's PDE 8 at a page table that identity-maps stage 2; the
; testbench restores every patched byte when the snapshot EIP issues.
%ifndef STAGE2
STAGE2 equ 2000000h
%endif

%ifidn PART, hwcom
; Hardware: SNAPGO.COM, run at a plain DOS prompt (no EMM386) after the
; snapshot has been written into DDR from Linux (snap_hw.py).
        bits 16
        org 100h
        cli
        out 0f2h, al                    ; A20 on
        mov ax, cs
        movzx eax, ax
        shl eax, 4
        add eax, gdt1
        mov [gdtr1 + 2], eax
        lgdt [gdtr1]
        mov eax, cr0
        or al, 1
        mov cr0, eax
        jmp dword 08h:STAGE2
        align 8
gdt1:   dq 0
        dq 00CF9A000000FFFFh
        dq 00CF92000000FFFFh
gdtr1:  dw 23
        dd 0
%elifidn PART, stage1
        bits 16
        org 1000h
stage1:
        cli
        out 0f2h, al                    ; A20 on
        lgdt [cs:gdtr1]
        mov eax, cr0
        or al, 1
        mov cr0, eax
        jmp dword 08h:STAGE2
        align 8
gdt1:   dq 0
        dq 00CF9A000000FFFFh            ; 08h flat code
        dq 00CF92000000FFFFh            ; 10h flat data
gdtr1:  dw 23
        dd gdt1
%else
        bits 32
        org STAGE2
s2:
        mov ax, 10h
        mov ds, ax
        mov es, ax
        mov ss, ax
        mov esp, STAGE2 + 0ff0h
%ifdef HW
        lgdt [own_gdtr]                 ; the DOS-side GDT is about to be overwritten
        mov word [0a0000h], 'L'         ; text VRAM: loader alive
        mov esi, STAGE2 + 100000h       ; staged physical 0-10FFFFh (IVT..HMA)
        xor edi, edi
        mov ecx, 0a0000h / 4
        cld
        rep movsd
        mov esi, STAGE2 + 100000h + 100000h
        mov edi, 100000h
        mov ecx, 10000h / 4
        rep movsd
        mov al, 11h                     ; PICs as VPICD set them: vectors 50h/58h
        out 00h, al
        mov al, 50h
        out 02h, al
        mov al, 80h
        out 02h, al
        mov al, 1dh
        out 02h, al
        mov al, 11h
        out 08h, al
        mov al, 58h
        out 0ah, al
        mov al, 07h
        out 0ah, al
        mov al, 09h
        out 0ah, al
        mov al, 7ch                     ; NP2kai's masks under Windows: timer,
        out 02h, al                     ; keyboard and cascade open
        mov al, 51h
        out 0ah, al
%endif
        mov eax, [st_cr3]
        mov cr3, eax
        mov eax, [st_cr0]
        mov cr0, eax                    ; paging on: PDE 8 maps this page 1:1
        jmp short .paged
.paged:
        mov ecx, [st_warm]              ; optional cache warm-up: run the NOP
        jecxz .cold                     ; sled after this page, then read it
        call STAGE2 + 1000h
        mov esi, STAGE2 + 1000h
        cld
        rep lodsd
.cold:
        lgdt [st_gdtr]
        lidt [st_idtr]
        mov eax, [st_gdtr + 2]
        movzx ecx, word [st_tr]
        and cl, 0f8h
        and byte [eax + ecx + 5], 0fdh  ; TSS descriptor not busy, so LTR works
        ltr [st_tr]
        lldt [st_ldtr]
        mov ax, [st_sreg + 0]
        mov es, ax
        mov ax, [st_sreg + 6]
        mov ds, ax
        ; DS now holds the snapshot selector (Win16 code: a small 16-bit
        ; segment), so the loader reads its own state through CS (flat).
        mov ax, [cs:st_sreg + 8]
        mov fs, ax
        mov ax, [cs:st_sreg + 10]
        mov gs, ax
        test byte [cs:st_sreg + 2], 3
        jnz .outer
        mov ax, [cs:st_sreg + 4]
        mov ss, ax
        mov esp, [cs:st_esp]
        sub esp, 12
        mov eax, [cs:st_eip]
        mov [esp], eax
        movzx eax, word [cs:st_sreg + 2]
        mov [esp + 4], eax
        mov eax, [cs:st_eflags]
        mov [esp + 8], eax
        jmp .regs
.outer:                                 ; CPL 3 target: IRETD pops SS:ESP too, so
        mov eax, [cs:st_gdtr + 2]          ; build the frame on a ring-0 stack in this
        movzx ecx, word [cs:st_tr]         ; page, with the TSS's SS0 selector
        and cl, 0f8h
        add eax, ecx
        mov ecx, [cs:eax + 2]              ; TSS base 23..0 (+ access byte)
        and ecx, 0ffffffh
        movzx edx, byte [cs:eax + 7]
        shl edx, 24
        or ecx, edx
        mov ax, [cs:ecx + 8]               ; SS0
        mov ss, ax
        mov esp, STAGE2 + 0ff0h
        movzx eax, word [cs:st_sreg + 4]
        push eax
        push dword [cs:st_esp]
        push dword [cs:st_eflags]
        movzx eax, word [cs:st_sreg + 2]
        push eax
        push dword [cs:st_eip]
.regs:
        mov eax, [cs:st_eax]
        mov ecx, [cs:st_ecx]
        mov edx, [cs:st_edx]
        mov ebx, [cs:st_ebx]
        mov ebp, [cs:st_ebp]
        mov esi, [cs:st_esi]
        mov edi, [cs:st_edi]
        iretd

        align 16
; STATE block (patched by snap_gen.py; the order is fixed)
st_magic:  dd 534e4150h                 ; 'PANS'
st_eax:    dd 0
st_ecx:    dd 0
st_edx:    dd 0
st_ebx:    dd 0
st_esp:    dd 0
st_ebp:    dd 0
st_esi:    dd 0
st_edi:    dd 0
st_eip:    dd 0
st_eflags: dd 0
st_cr0:    dd 0
st_cr3:    dd 0
st_gdtr:   dw 0
           dd 0
st_idtr:   dw 0
           dd 0
st_ldtr:   dw 0
st_tr:     dw 0
st_sreg:   dw 0, 0, 0, 0, 0, 0          ; ES CS SS DS FS GS
st_warm:   dd 0                         ; sled size in dwords (0 = no warm-up)
%ifdef HW
        align 8
own_gdt:   dq 0
           dq 00CF9A000000FFFFh
           dq 00CF92000000FFFFh
own_gdtr:  dw 23
           dd own_gdt
%endif
%endif
