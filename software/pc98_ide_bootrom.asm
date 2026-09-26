; SPDX-License-Identifier: GPL-3.0-or-later
; PC-98 extension-ROM entry table at D0000h, not an IBM-PC option ROM.
bits 16
cpu 386
org 0
    retf
    times 3-($-$$) db 90h
    retf
    times 6-($-$$) db 90h
    retf
    times 9-($-$$) db 90h
    db 55h,0aah,10h
    jmp near claim
    jmp near initialize
    retf
    times 15h-($-$$) db 90h
    jmp near boot
    times 30h-($-$$) db 0cbh
claim:
    mov byte [bx],0d9h
    retf
initialize:
    pushf
    cli
    pushad
    push ds
    push es
    cld
    push cs
    pop ds
    ; Publish the core's extended RAM and clear the legacy BIOS's V30 flag
    ; (Z98MEM's probe). It patches itself, so run it from the reserved RAM
    ; before the resident service is copied below it.
    mov ax,0da00h
    mov es,ax
    xor di,di
    mov si,memfix
    mov cx,memfix_end-memfix
    rep movsb
    call 0da00h:0
    ; The core has an EGC. The PC-9801VM BIOS never reports one, so set
    ; 054Dh bit 6 as an EGC-equipped BIOS does (NP2kai bios.c: grcg.chip>=3).
    ; Games such as Rusty select their EGC graphics driver from this bit.
    xor ax,ax
    mov es,ax
    or byte [es:054dh],40h
    mov ax,0d800h
    mov es,ax
    xor di,di
    mov si,resident
    mov cx,resident_end-resident
    rep movsb
    call 0d800h:0
    pop es
    pop ds
    popad
    popf
    retf
boot:
    jmp 0d800h:3
resident:
    incbin RESIDENT_BINARY
resident_end:
memfix:
    incbin MEMFIX_BINARY
memfix_end:
    times 8192-($-$$) db 0ffh
