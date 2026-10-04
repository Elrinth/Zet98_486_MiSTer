; SPDX-License-Identifier: GPL-3.0-or-later
; Self-authored PC-98 protected-mode IRQ0 test. Fresh disposable DOS boot only.
; Own GDT/IDT, 32-bit code and interrupt gate; finite five-million-iteration
; loop. No DOS/BIOS calls while protected. This does not emulate DX386/DMX.
; Restore real mode, original descriptor tables/stack, PIC mask and BIOS PIT.
bits 16
cpu 386
org 100h
%ifdef LDT_TEST
%ifndef CPU_TEST
    %error LDT variant is a CPU simulation control, not a qualified DOS program
%endif
%define CODE_SEL 0ch
%define DATA_SEL 14h
%else
%define CODE_SEL 08h
%define DATA_SEL 10h
%endif
start:
    push cs
    pop ds
    cld
    mov eax,cr0
    test al,1
    jnz refuse
    mov [old_cr0],eax
    sgdt [old_gdtr]
    sidt [old_idtr]
    mov [old_ss],ss
    mov [old_sp],sp
    mov ax,cs
    mov [real_jump+3],ax
    movzx eax,ax
    shl eax,4
    mov ebx,eax
    mov si,gdt+8
    mov cx,4
.descriptor:
    mov [si+2],ax
    mov edx,eax
    shr edx,16
    mov [si+4],dl
    add si,8
    loop .descriptor
%ifdef LDT_TEST
    mov si,ldt+8
    mov cx,2
.ldt_descriptor:
    mov [si+2],ax
    mov edx,eax
    shr edx,16
    mov [si+4],dl
    add si,8
    loop .ldt_descriptor
    mov edx,eax
    add edx,ldt
    mov [gdt+42],dx
    shr edx,16
    mov [gdt+44],dl
%endif
    add eax,gdt
    mov [gdtr+2],eax
    mov eax,ebx
    add eax,idt
    mov [idtr+2],eax
    push ds
    pop es
    mov di,idt
    mov cx,256
.gate:
    mov word [di],fault_handler
    mov word [di+2],CODE_SEL
    mov word [di+4],8e00h
    mov word [di+6],0
    add di,8
    loop .gate
    mov word [idt+8*8],irq_handler
    cli
    in al,2
    mov [old_mask],al
    mov al,0feh
    out 2,al
    mov al,36h
    out 77h,al
    mov ax,17554
    out 71h,al
    mov al,ah
    out 71h,al
    lgdt [gdtr]
    lidt [idtr]
    mov eax,[old_cr0]
    or al,1
    mov cr0,eax
%ifdef LDT_TEST
    mov ax,28h
    lldt ax
%endif
    jmp CODE_SEL:protected32
bits 32
protected32:
    mov ax,DATA_SEL
    mov ds,ax
    mov es,ax
    mov ss,ax
    mov esp,0ff00h
%ifdef CPU_TEST
    ; Bound a missing-IRQ failure, but finish based on delivered interrupts.
    ; A fixed 5000-iteration delay can end before the third timer tick when
    ; the CPU pipeline is faster, despite correct interrupt delivery.
    mov ecx,100000
%else
    mov ecx,5000000
%endif
    sti
.wait:
%ifdef CPU_TEST
    cmp word [irq_count],3
    jae .irq_ready
%endif
    dec ecx
    jnz .wait
%ifdef CPU_TEST
.irq_ready:
%endif
    cli
    mov byte [completed],1
    jmp word 18h:protected16_exit
irq_handler:
    push eax
    inc word [irq_count]         ; DS is writable; CS is a read-only code segment
    mov al,20h
    out 0,al
    pop eax
    iretd
fault_handler:
    cli
    mov ax,DATA_SEL
    mov ds,ax
    mov byte [faulted],1
    jmp word 18h:protected16_exit
bits 16
protected16_exit:
    mov ax,20h
    mov ds,ax
    mov es,ax
    mov ss,ax
    mov eax,[old_cr0]
    mov cr0,eax
real_jump:
    jmp 0:real_mode
real_mode:
    mov ax,cs
    mov ds,ax
    mov es,ax
    mov ax,[old_ss]
    mov ss,ax
    mov sp,[old_sp]
    lgdt [old_gdtr]
    lidt [old_idtr]
    mov al,0ffh
    out 2,al
    mov al,36h
    out 77h,al
    xor al,al
    out 71h,al
    mov al,60h
    out 71h,al
    mov al,20h
    out 0,al
    mov al,[old_mask]
    out 2,al
%ifdef CPU_TEST
    cmp word [completed],1
    jne cpu_fail
    cmp word [irq_count],3
    jb cpu_fail
    mov ax,600dh
    jmp cpu_report
cpu_fail:
    mov ax,0deadh
cpu_report:
    mov dx,7ff0h
    out dx,ax
    hlt
    jmp $
%endif
    sti
    mov dx,title
    mov ah,9
    int 21h
    mov ax,[irq_count]
    call hex16
    mov dx,status_text
    mov ah,9
    int 21h
    mov ax,[completed]            ; low completed, high faulted
    call hex16
    mov dx,newline
    mov ah,9
    int 21h
    mov ax,4c01h
    cmp word [completed],1
    jne .exit
    cmp word [irq_count],3
    jb .exit
    xor al,al
.exit:
    int 21h
refuse:
    mov dx,refusal
    mov ah,9
    int 21h
    mov ax,4c02h
    int 21h
hex16:
    mov bx,ax
    mov cx,4
.digit:
    rol bx,4
    mov dl,bl
    and dl,15
    add dl,'0'
    cmp dl,'9'
    jbe .emit
    add dl,7
.emit:
    mov ah,2
    int 21h
    loop .digit
    ret
align 8
gdt:
    dq 0
    dq 00409a000000ffffh          ; 08: 32-bit code, base patched
    dq 004092000000ffffh          ; 10: 32-bit stack/data
    dq 00009a000000ffffh          ; 18: 16-bit exit code
    dq 000092000000ffffh          ; 20: 16-bit stack/data
%ifdef LDT_TEST
    dq 0000820000000017h          ; 28: LDT descriptor, base patched
%endif
gdt_end:
gdtr: dw gdt_end-gdt-1
    dd 0
%ifdef LDT_TEST
ldt:
    dq 0
    dq 00409a000000ffffh          ; 0c: LDT 32-bit code
    dq 004092000000ffffh          ; 14: LDT 32-bit stack/data
%endif
idtr: dw 2047
    dd 0
old_gdtr: times 6 db 0
old_idtr: times 6 db 0
old_cr0: dd 0
old_ss: dw 0
old_sp: dw 0
old_mask: db 0
completed: db 0
faulted: db 0
irq_count: dw 0
idt: times 2048 db 0
title: db 'PC-98 protected32 PIT IRQ0 count (hex): $'
status_text: db ' / status (0001=completed, no fault): $'
newline: db 13,10,'Restored real mode, descriptor tables, stack and PIC; BIOS PIT rate.',13,10,'$'
refusal: db 'Refused: existing protected/V86 host. No state changed.',13,10,'$'
