; Self-authored real-mode CPU/PIC integration control. No private firmware.
bits 16
org 1000h
cli
xor ax,ax
mov ds,ax
mov es,ax
mov ss,ax
mov sp,8000h
cld
; All vectors have distinct handlers, so a late zero-vector read is visible.
%assign n 0
%rep 8
mov word [(8+n)*4],irq%+n
mov word [(8+n)*4+2],0
%assign n n+1
%endrep
%ifdef CASCADE
%assign n 0
%rep 8
mov word [(10h+n)*4],slave%+n
mov word [(10h+n)*4+2],0
%assign n n+1
%endrep
mov al,11h
out 0,al
mov al,08h
out 2,al
mov al,80h
out 2,al
%ifdef BIOSMODE
mov al,1dh
%else
mov al,0dh
%endif
out 2,al
mov al,11h
out 8,al
mov al,10h
out 0ah,al
mov al,07h
out 0ah,al
mov al,09h
out 0ah,al
xor al,al
out 0ah,al
%else
mov al,13h
out 0,al
mov al,08h
out 2,al
mov al,0dh
out 2,al
%endif
%ifdef BIOSMODE
; BIOS mode: master ICW4=1Dh, slave=09h; verify every mask value.
; This is a self-authored test, not copied private ROM code.
xor bx,bx
.mask:
mov ax,bx
out 2,al
in al,2
cmp al,bl
jne failed
mov ax,bx
out 0ah,al
in al,0ah
cmp al,bl
jne failed
inc bx
cmp bx,256
jb .mask
xor al,al
out 0ah,al
%endif
xor al,al
out 2,al
mov word [3000h],0
mov bx,0
.next:
mov word [3002h],0ffffh
mov dx,7fe0h
mov ax,bx
out dx,ax
sti
mov cx,0ffffh
.wait:
cmp word [3002h],0ffffh
jne .received
loop .wait
jmp failed
.received:
cli
cmp [3002h],bx
jne failed
inc bx
%ifdef CASCADE
cmp bx,7
jne .not_cascade_start
mov bx,10h
.not_cascade_start:
cmp bx,18h
%else
cmp bx,8
%endif
jb .next
%ifdef CASCADE
cmp word [3000h],15
%else
cmp word [3000h],8
%endif
jne failed
mov ax,600dh
mov dx,7ff0h
out dx,ax
hlt
failed:
mov ax,0deadh
mov dx,7ff0h
out dx,ax
hlt
%assign n 0
%rep 8
irq%+n:
push ax
mov word [3002h],n
inc word [3000h]
mov al,20h
out 0,al
pop ax
iret
%assign n n+1
%endrep
%ifdef CASCADE
%assign n 0
%rep 8
slave%+n:
push ax
mov word [3002h],10h+n
inc word [3000h]
mov al,20h
out 8,al
out 0,al
pop ax
iret
%assign n n+1
%endrep
%endif
