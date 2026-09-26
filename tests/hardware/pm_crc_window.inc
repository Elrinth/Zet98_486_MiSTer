; Self-authored, 386 protected-mode CRC32 window. Caller owns a 64KB DOS
; segment. pm_address/pm_length (1..32768), pm_crc (uncomplemented) are inputs.
; DS/ES/FS/GS, stack, flags, CR0, GDTR/IDTR are restored. No BIOS/DOS in PM.
; IRQs disabled for only one bounded window; exceptions return pm_fault=1.
; Caller must enable A20 and keep the physical input allocation locked.
pm_initialize:
    mov ax,cs
    mov [pm_real_jump+3],ax
    movzx eax,ax
    shl eax,4
    mov ebx,eax
    mov si,pm_gdt+8
    mov cx,4
.base:
    mov [si+2],ax
    mov edx,eax
    shr edx,16
    mov [si+4],dl
    add si,8
    loop .base
    add eax,pm_gdt
    mov [pm_gdtr+2],eax
    add ebx,pm_idt
    mov [pm_idtr+2],ebx
    push es
    push cs
    pop es
    mov di,pm_idt
    mov cx,32
.gate:
    mov ax,pm_exception
    stosw
    mov ax,8
    stosw
    mov ax,8e00h
    stosw
    xor ax,ax
    stosw
    loop .gate
    pop es
    ret
pm_window:
    pushfd
    pushad
    push es
    push fs
    push gs
    mov [pm_ss],ss
    mov [pm_sp],sp
    mov byte [pm_fault],0
    cmp dword [pm_length],1
    jb pm_invalid
    cmp dword [pm_length],32768
    ja pm_invalid
    sgdt [pm_old_gdtr]
    sidt [pm_old_idtr]
    mov eax,cr0
    mov [pm_cr0],eax
    cli
    lgdt [pm_gdtr]
    lidt [pm_idtr]
    or al,1
    mov cr0,eax
    jmp 8:pm_code
pm_invalid:
    mov byte [pm_fault],1
    jmp pm_pop
bits 32
pm_code:
    mov ax,10h
    mov ds,ax
    mov es,ax
    mov ss,ax
    mov esp,0ff00h
    mov ax,28h
    mov fs,ax
    mov esi,[pm_address]
    mov ecx,[pm_length]
    mov eax,[pm_crc]
.byte:
    movzx ebx,byte [fs:esi]
    xor bl,al
    shr eax,8
    xor eax,[pm_table+ebx*4]
    inc esi
    dec ecx
    jnz .byte
    mov [pm_crc],eax
    jmp word 18h:pm_exit16
pm_exception:
    cli
    mov ax,10h
    mov ds,ax
    mov byte [pm_fault],1
    jmp word 18h:pm_exit16
bits 16
pm_exit16:
    mov ax,20h
    mov ds,ax
    mov es,ax
    mov ss,ax
    mov fs,ax
    mov gs,ax
    mov eax,[pm_cr0]
    mov cr0,eax
pm_real_jump:
    jmp 0:pm_real
pm_real:
    mov ax,cs
    mov ds,ax
    mov ss,[pm_ss]
    mov sp,[pm_sp]
    lgdt [pm_old_gdtr]
    lidt [pm_old_idtr]
pm_pop:
    pop gs
    pop fs
    pop es
    popad
    popfd
    ret
align 8
pm_gdt:
    dq 0
    dq 00409a000000ffffh
    dq 004092000000ffffh
    dq 00009a000000ffffh
    dq 000092000000ffffh
    dq 00cf92000000ffffh          ; Flat 4GB data, read at physical addresses
pm_gdtr: dw $-pm_gdt-1
    dd 0
pm_idtr: dw 32*8-1
    dd 0
pm_old_gdtr: times 6 db 0
pm_old_idtr: times 6 db 0
pm_cr0: dd 0
pm_ss: dw 0
pm_sp: dw 0
pm_address: dd 0
pm_length: dd 0
pm_crc: dd 0ffffffffh
pm_fault: db 0
pm_idt: times 32*8 db 0
pm_table equ 1000h
