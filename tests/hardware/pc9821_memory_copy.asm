; Self-authored ROM: isolate low-RAM copies from any NEC/DOS code.
; Debug UART RecorderDivide: OUT80=A55A pass, E101 copy failure,
; E102 RAM execution failure. Failure also emits SI, DI and iteration.
bits 16
section bios start=0 vstart=0
    times 0x18000 db 0xff
section itf start=0x18000 vstart=0
entry:
    cli
    cld
    xor ax,ax
    mov ss,ax
    mov sp,0x7c00
    mov ds,ax
    mov word [0],terminal
    mov word [2],0xf800
    mov bp,64
.again:
    mov ax,0x2000
    mov es,ax
    xor di,di
    mov cx,32768
    mov ax,bp
.fill:
    stosw
    add ax,0x9e37
    loop .fill
    mov ax,0x2000
    mov ds,ax
    mov ax,0x3000
    mov es,ax
    xor si,si
    xor di,di
    mov cx,32768
    rep movsw
    xor si,si
    xor di,di
    mov cx,32768
    repe cmpsw
    mov bx,0xe101
    jne fail
    ; Rewrite a tiny RAM function each iteration, then execute it.
    mov word [0],0x00b8
    mov word [1],bp
    mov word [3],0xcb90
    call 0x2000:0
    cmp ax,bp
    mov bx,0xe102
    jne fail
    dec bp
    jnz .again
    mov bx,0xa55a
fail:
    mov ax,si
    out 80h,ax
    mov ax,di
    out 80h,ax
    mov ax,bp
    out 80h,ax
    mov ax,bx
    out 80h,ax
    int 0
terminal:
    cli
    hlt
    jmp terminal
    times 0x7ff0-($-$$) db 0xff
    jmp 0xf800:entry
    times 0x8000-($-$$) db 0xff
section tail start=0x20000 vstart=0
    times 0x66800 db 0
