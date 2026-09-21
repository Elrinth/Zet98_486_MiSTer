bits 16
cpu 386
org 1000h
%define BIOS_HEADS 8
%define BIOS_SECTORS 17
%define BIOS_CYLINDERS 8162
%define BIOS_POLL_LIMIT 256
%define BIOS_TOTAL (BIOS_HEADS * BIOS_SECTORS * BIOS_CYLINDERS)
start:
    cli
    xor ax,ax
    mov ss,ax
    mov sp,9000h
    mov ds,ax
    mov es,ax
    cld
    mov word [1bh*4],bios_int1b
    mov word [1bh*4+2],0
    mov word [055ch],0023h
    mov ax,0380h
    int 1bh
    jc failed
    cmp word [055ch],0123h
    jne failed
    mov ebx,12340000h
    mov ecx,56780000h
    mov edx,9abc0000h
    mov ax,8480h
    int 1bh
    jc failed
    cmp ah,0fh
    jne failed
    cmp ebx,12340200h
    jne failed
    cmp ecx,56780000h+BIOS_CYLINDERS
    jne failed
    cmp edx,9abc0811h
    jne failed
    ; A read across the last head/sector into the next cylinder, also crossing
    ; the caller's 64K offset. Upper register halves and DF must survive.
    mov ax,1000h
    mov es,ax
    mov ebp,1122fff0h
    mov ebx,33440600h
    mov ecx,55660003h
    mov edx,77880710h
    mov esi,99aabbcch
    mov edi,0ddeeff00h
    mov eax,0aa550680h
    std
    int 1bh
    jc failed
    cmp eax,0aa550080h
    jne failed
    pushf
    pop ax
    test ax,400h
    jz failed
    cld
    cmp ebp,1122fff0h
    jne failed
    cmp ebx,33440600h
    jne failed
    cmp ecx,55660003h
    jne failed
    cmp edx,77880710h
    jne failed
    cmp esi,99aabbcch
    jne failed
    cmp edi,0ddeeff00h
    jne failed
    mov edi,1fff0h
    mov esi,543
    mov bx,3
    call check_sectors
    ; Linear addressing and a partial final sector preserve the next byte.
    mov ax,2000h
    mov es,ax
    mov bp,10h
    mov word [es:bp+512],7777h
    mov ax,0600h
    mov bx,513
    mov cx,0123h
    mov dx,1
    int 1bh
    jc failed
    cmp word [es:bp],0a55ah ^ 0123h
    jne failed
    cmp word [es:bp+512],07700h | ((0a55ah ^ 0124h) & 255)
    jne failed
%ifndef BIOS_SHORT_TEST
    ; BX=0 really transfers 64K. Compare all 128 sectors independently.
    mov ax,3000h
    mov es,ax
    xor bp,bp
    xor bx,bx
    mov cx,17
    xor dx,dx
    mov ax,0600h
    int 1bh
    jc failed
    mov edi,30000h
    mov esi,17
    mov bx,128
    call check_sectors
%endif
    ; VERIFY reads data without modifying the caller's buffer.
    mov ax,2000h
    mov es,ax
    xor bp,bp
    mov word [es:bp],1234h
    mov bx,512
    xor cx,cx
    xor dx,dx
    mov ax,0180h
    int 1bh
    jc failed
    cmp word [es:bp],1234h
    jne failed
    mov cx,BIOS_CYLINDERS
    mov ax,0680h
    int 1bh
    call expect_range
    xor cx,cx
    mov dx,0800h
    mov ax,0680h
    int 1bh
    call expect_range
    mov dx,17
    mov ax,0680h
    int 1bh
    call expect_range
    mov bx,1024
    mov cx,(BIOS_TOTAL-1) & 0ffffh
    mov dx,(BIOS_TOTAL-1) >> 16
    mov ax,0600h
    int 1bh
    call expect_range
    mov ax,0580h
    int 1bh
    jnc failed
    cmp ah,70h
    jne failed
    mov ax,0d80h
    int 1bh
    jnc failed
    cmp ah,40h
    jne failed
    ; Another device must reach the original INT handler unchanged.
    mov ax,0690h
    int 1bh
    cmp ax,5a90h
    jne failed
    ; Inject missing media, stuck BSY and ATA command error.
    mov si,1
.error_case:
    mov dx,7ff2h
    mov ax,si
    out dx,ax
    mov ax,8480h
    int 1bh
    cmp si,3
    je .try_read
    jnc failed
    cmp ah,60h
    jne failed
.try_read:
    mov bx,512
    xor cx,cx
    xor dx,dx
    mov ax,0680h
    int 1bh
    jnc failed
    cmp ah,60h
    jne failed
    inc si
    cmp si,4
    jb .error_case
    mov dx,7ff0h
    mov ax,600dh
    out dx,ax
    hlt

expect_range:
    jnc failed
    cmp ah,0d0h
    jne failed
    ret
check_sectors:
    ; Test model emits word = 0xA55A XOR LBA XOR word index.
    mov eax,edi
    shr eax,4
    mov es,ax
    and di,15
    xor cx,cx
.word:
    mov ax,si
    xor ax,cx
    xor ax,0a55ah
    scasw
    jne failed
    inc cx
    cmp cx,256
    jb .word
    ; Normalize the address after each sector, avoiding 16-bit wrap.
    mov ax,es
    movzx eax,ax
    shl eax,4
    movzx edx,di
    add eax,edx
    mov edi,eax
    inc esi
    dec bx
    jnz check_sectors
    ret
previous_handler:
    mov ah,5ah
    iret
bios_previous_vector: dw previous_handler,0
failed:
    mov dx,7ff0h
    mov ax,0deadh
    out dx,ax
    hlt
%include "software/pc98_ide_read_bios.inc"
