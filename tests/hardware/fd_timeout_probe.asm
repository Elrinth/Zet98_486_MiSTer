; SPDX-License-Identifier: GPL-3.0-or-later
; FDTIME.COM - how long does the NEC BIOS wait for the FDC, and how long do
; Xanadu's boot reads take? Put the disk to test in the first 1 MB floppy
; drive (DA/UA 90h) and run from another drive (HDD).
;
; 1. Times the INT 1Bh completion wait (FD80:2184..2192: 28h x 65536 of
;    TEST [0:055E],AX / LOOP) run from RAM with the never-set mask AX=0.
; 2. Times INT 1Bh calls the BIOS boot and Xanadu's IPL make:
;    AH=2Ah READ ID (FM), AH=16h READ DATA FM 128-byte sectors from R=1:
;    512 bytes (BIOS boot) and 3328 bytes (Xanadu IPL, whole FM track).
;    AH=90h in a result means the BIOS gave up waiting (timeout).
; Time is counted in VSYNC interrupts (IRQ2, ~56.4 Hz on 24 kHz modes).
; nasm -f bin fd_timeout_probe.asm -o FDTIME.COM
bits 16
org 100h

start:
    cld
    mov si, title
    call puts
    ; DMA buffer on a 64 KB boundary inside our memory
    mov ax, cs
    add ax, 1000h
    and ax, 0F000h
    add ax, 1000h
    mov [bufseg], ax
    ; hook VSYNC (INT 0Ah)
    xor ax, ax
    mov es, ax
    cli
    mov ax, [es:0Ah*4]
    mov [old0a], ax
    mov ax, [es:0Ah*4+2]
    mov [old0a+2], ax
    mov word [es:0Ah*4], vsync
    mov [es:0Ah*4+2], cs
    in al, 02h
    mov [oldmask], al
    and al, 0FBh
    out 02h, al
    out 64h, al
    sti

    ; 1. the BIOS wait loop, from RAM
    mov si, t_loop
    call puts
    call tstart
    push ds
    xor ax, ax
    mov ds, ax
    mov dh, 28h
    xor cx, cx
.w: test [055Eh], ax
    jnz .x
    loop .w
    dec dh
    jnz .w
.x: pop ds
    call tstop

    ; 2. BIOS calls
    mov si, t_rid
    call puts
    mov ax, 2A90h               ; READ ID, FM, 1 MB drive 0
    xor cx, cx
    xor dx, dx
    call bios
    mov si, t_r512
    call puts
    mov ax, 1690h               ; READ DATA FM with seek, like the boot
    mov bx, 0200h
    xor cx, cx                  ; C=0, N=0
    mov dx, 0001h               ; H=0, R=1
    call bios
    mov si, t_r3328
    call puts
    mov ax, 1690h               ; Xanadu IPL
    mov bx, 0D00h
    xor cx, cx
    mov dx, 0001h
    call bios
    mov si, t_r3328
    call puts
    mov ax, 1690h
    mov bx, 0D00h
    xor cx, cx
    mov dx, 0001h
    call bios
    mov si, t_rid
    call puts
    mov ax, 6A90h               ; READ ID, MFM (fails on an FM track)
    xor cx, cx
    xor dx, dx
    call bios

    ; unhook
    cli
    mov al, [oldmask]
    out 02h, al
    xor ax, ax
    mov es, ax
    mov ax, [old0a]
    mov [es:0Ah*4], ax
    mov ax, [old0a+2]
    mov [es:0Ah*4+2], ax
    sti
    mov ax, 4C00h
    int 21h

; INT 1Bh with AX/BX/CX/DX set, ES:BP = buffer; prints AH/CX/DX and frames
bios:
    push ax
    call tstart
    pop ax
    mov es, [bufseg]
    xor bp, bp
    int 1Bh
    push cs
    pop es
    push dx
    push cx
    push ax
    mov si, t_ah
    call puts
    pop ax
    mov al, ah
    call hexbyte
    mov si, t_cx
    call puts
    pop ax
    call hexword
    mov si, t_dx
    call puts
    pop ax
    call hexword
    ; fall through
tstop:
    mov ax, [frames]
    sub ax, [t0]
    push ax
    mov si, t_frames
    call puts
    pop ax
    push ax
    call dec16
    mov si, t_ms
    call puts
    pop ax                      ; ms = frames * 1000 / 56.42 ~ frames * 709 / 40
    mov bx, 709
    mul bx
    mov bx, 40
    div bx
    call dec16
    mov si, t_msend
    call puts
    ret

tstart:
    mov ax, [frames]
    mov [t0], ax
    ret

vsync:
    push ax
    inc word [cs:frames]
    out 64h, al                 ; re-arm the CRT interrupt
    mov al, 20h
    out 00h, al
    pop ax
    iret

puts:
    lodsb
    test al, al
    jz .d
    mov dl, al
    mov ah, 02h
    int 21h
    jmp puts
.d: ret

hexword:
    push ax
    mov al, ah
    call hexbyte
    pop ax
hexbyte:
    push ax
    shr al, 4
    call .n
    pop ax
.n: and al, 0Fh
    add al, '0'
    cmp al, '9'
    jbe .o
    add al, 7
.o: mov dl, al
    mov ah, 02h
    int 21h
    ret

dec16:
    xor cx, cx
    mov bx, 10
.a: xor dx, dx
    div bx
    push dx
    inc cx
    test ax, ax
    jnz .a
.b: pop dx
    add dl, '0'
    mov ah, 02h
    int 21h
    loop .b
    ret

title   db 'FDTIME: NEC BIOS FDC wait vs FM reads (drive 90h)', 13, 10, 0
t_loop  db 'BIOS wait loop (timeout)       ', 0
t_rid   db 'INT1B READ ID                  ', 0
t_r512  db 'INT1B 16h FM 512 bytes (boot)  ', 0
t_r3328 db 'INT1B 16h FM 3328 bytes (IPL)  ', 0
t_ah    db 'AH=', 0
t_cx    db ' CX=', 0
t_dx    db ' DX=', 0
t_frames db ' frames=', 0
t_ms    db ' ~', 0
t_msend db ' ms', 13, 10, 0
frames  dw 0
t0      dw 0
bufseg  dw 0
old0a   dd 0
oldmask db 0
