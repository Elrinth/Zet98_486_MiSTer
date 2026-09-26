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
    times 8192-($-$$) db 0ffh
