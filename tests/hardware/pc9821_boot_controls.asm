; Self-authored boot.rom for the debug-UART core; contains no NEC code/data.
; nasm -f bin pc9821_boot_controls.asm -o boot.rom
; Trace terminal OUT 80h: A55Ah=PASS, E001..E007=failed assertion.
; The following INT 0 freezes a RecorderDivide trace (CPU then halts).
bits 16

section bios start=0 vstart=0
    times 0x18000/2 dw 0x55aa

section itf start=0x18000 vstart=0
entry:
    cli
    xor ax, ax
    mov ss, ax
    mov sp, 0x7c00
    mov ds, ax
    mov word [0], terminal
    mov word [2], 0xf800
    cld

    mov dx, 0x439
    in al, dx
    test al, al
    mov bx, 0xe001
    jnz fail
    mov al, 0xb4
    out dx, al
    in al, dx
    cmp al, 0xb4
    mov bx, 0xe002
    jne fail
    xor al, al
    out dx, al
    in al, dx
    test al, al
    mov bx, 0xe003
    jnz fail
    in al, 0xf0
    test al, al
    mov bx, 0xe004
    jnz fail

    ; Execute a ROM-bank switch from RAM so the next instruction is stable.
    xor ax, ax
    mov es, ax
    push cs
    pop ds
    mov si, trampoline
    mov di, 0x600
    mov cx, trampoline_end-trampoline
    rep movsb
    jmp 0:0x600
trampoline:
    mov dx, 0x43d
    mov al, 2
    out dx, al
    mov ax, 0xf800
    mov es, ax
    cmp word [es:0], 0x55aa
    mov bx, 0xe005
    mov al, 0
    out dx, al                 ; OUT and MOV preserve comparison flags
    jne .failed
    jmp 0xf800:after_bank
.failed:
    jmp 0xf800:fail
trampoline_end:

after_bank:
    ; The NEC POST pattern: read ROM directly, write its RAM shadow via bank E.
    mov dx, 0x461
    mov al, 0x0e
    out dx, al
    mov ax, 0xe800
    mov ds, ax
    mov ax, 0x8800
    mov es, ax
    xor si, si
    xor di, di
    mov cx, 256
    ; Invert the copied data so ignored RAM-select writes cannot falsely pass.
.copy:
    lodsw
    not ax
    stosw
    loop .copy
    cmp word [0], 0x55aa
    mov bx, 0xe007
    jne fail                  ; copying must preserve the original ROM
    mov dx, 0x53d
    mov al, 2
    out dx, al
    mov ax, 0xe800
    mov es, ax
    xor di, di
    mov ax, 0xaa55
    mov cx, 256
    repe scasw
    mov bx, 0xe006
    jne fail
    mov bx, 0xa55a
fail:
    mov ax, bx
    out 0x80, ax
    int 0
terminal:
    cli
    hlt
    jmp terminal
    times 0x7ff0-($-$$) db 0xff
    jmp 0xf800:entry
    times 0x8000-($-$$) db 0xff

section tail start=0x20000 vstart=0
    ; Same loader length as the standard combined ROM, blank font/sound areas.
    times 0x66800 db 0
