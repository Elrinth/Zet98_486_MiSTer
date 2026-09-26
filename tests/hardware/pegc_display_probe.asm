; SPDX-License-Identifier: GPL-3.0-or-later
; Self-authored DOS/MiSTer packed-display probe. No game or firmware code.
; Fill/read back 256KB with index=(y XOR (x/8)), then display 640x400.
; R/G/B palette is index,255-index,index XOR55h. Explicit GDC pitch/SAD.
bits 16
cpu 386
org 100h
start:
    cli
    mov ax,cs
    mov ds,ax
    mov ss,ax
    mov sp,0fffeh
    sti
    cld
    add ax,1000h
    jc failed
    cmp [2],ax
    jb failed
    mov dx,start_text
    mov ah,9
    int 21h
    ; BIOS9821 deliberately leaves raster setup to the extended BIOS calls.
    ; Default build is the explicit-geometry control.
%ifdef BIOS9821
    mov ah,31h
    int 18h
    mov [saved_mode],al
    mov al,41h
    out 6ah,al
    mov dx,09a0h
    mov al,4
    out dx,al
    in al,dx
    xor ax,ax
    out 6ch,al
    mov es,ax
    mov cl,[es:054dh]
    mov al,[saved_mode]
    mov ah,30h
    mov bh,11h
    int 18h
    mov ah,4dh
    mov ch,1
    int 18h
    mov ah,0ch
    int 18h
    mov ah,40h
    int 18h
%else
    mov ax,4200h
    mov ch,0c0h
    int 18h
%endif
    xor al,al
    out 7ch,al
    out 0a4h,al
    mov al,7
    out 6ah,al
%ifndef BIOS9821
    mov al,4
    out 6ah,al
%endif
    mov al,21h
    out 6ah,al
%ifdef BIOS9821
    mov al,80h
    out 6ah,al
%endif
    mov al,69h
    out 6ah,al
%ifdef BIOS9821
    mov dx,043fh
    mov al,20h
    out dx,al
%else
    mov al,82h
    out 6ah,al
    mov al,84h
    out 6ah,al
%endif
    mov ax,0e000h
    mov es,ax
    mov byte [es:100h],0
    xor bx,bx
.palette:
    mov al,bl
    out 0a8h,al
    out 0ach,al
    not al
    out 0aah,al
    mov al,bl
    xor al,55h
    out 0aeh,al
    inc bx
    cmp bx,256
    jb .palette
    mov byte [bank],0
    mov word [x],0
    mov word [y],0
.write_bank:
    call select_bank
    xor di,di
    mov cx,8000h
.write_pixel:
    call expected_pixel
    stosb
    call advance_pixel
    loop .write_pixel
    inc byte [bank]
    cmp byte [bank],8
    jb .write_bank
    mov byte [bank],0
    mov word [x],0
    mov word [y],0
.read_bank:
    call select_bank
    xor di,di
    mov cx,8000h
.read_pixel:
    call expected_pixel
    cmp [es:di],al
    jne failed
    inc di
    call advance_pixel
    loop .read_pixel
    inc byte [bank]
    cmp byte [bank],8
    jb .read_bank
    ; Save and close evidence before hiding the text layer.
    mov dx,filename
    xor cx,cx
    mov ah,5bh
    int 21h
    jc failed
    mov bx,ax
    mov dx,passed_text
    mov cx,passed_end-passed_text
    mov ah,40h
    int 21h
    jc failed
    cmp ax,passed_end-passed_text
    jne failed
    mov ah,3eh
    int 21h
    jc failed
    mov ah,0dh
    int 21h
    mov dx,passed_text
    mov ah,9
    int 21h
%ifdef BIOS9821
    ; Capture the BIOS-only geometry first. No GDC overrides before this wait.
%ifdef STAGED
    mov dx,stage0
    call pause_stage
    mov al,47h
    call gdc_command
    mov al,40
    call gdc_parameter
    mov dx,stage1
    call pause_stage
    mov al,4bh
    call gdc_command
    xor al,al
    call gdc_parameter
    call gdc_parameter
    call gdc_parameter
    mov dx,stage2
    call pause_stage
    mov al,70h
    call gdc_command
    xor al,al
    call gdc_parameter
    call gdc_parameter
    call gdc_parameter
    mov al,19h
    call gdc_parameter
    xor al,al
    call gdc_parameter
    call gdc_parameter
    call gdc_parameter
    call gdc_parameter
    mov dx,stage3
    call pause_stage
    mov al,82h
    out 6ah,al
    mov al,84h
    out 6ah,al
    mov dx,stage4
    call pause_stage
    mov al,0dh
    call gdc_command
    mov dx,stage5
    call pause_stage
%endif
%ifdef PITCH_ONLY
    mov al,47h
    call gdc_command
    mov al,40
    call gdc_parameter
%endif
    sti
.bios_halt:
    hlt
    jmp .bios_halt
%endif
    ; 40 GDC words *16 bytes at2.5MHz =640 bytes per displayed row.
    mov al,47h
    call gdc_command
    mov al,40
    call gdc_parameter
    mov al,4bh
    call gdc_command
    xor al,al
    call gdc_parameter
    call gdc_parameter
    call gdc_parameter
    ; SAD0=0, length0=400 (19h<<4); second partition unused in this frame.
    mov al,70h
    call gdc_command
    xor al,al
    call gdc_parameter
    call gdc_parameter
    call gdc_parameter
    mov al,19h
    call gdc_parameter
    xor al,al
    call gdc_parameter
    call gdc_parameter
    call gdc_parameter
    call gdc_parameter
    mov al,0dh
    call gdc_command
    mov ah,0ch
    int 18h
    sti
.halt:
    hlt
    jmp .halt
expected_pixel:
    mov ax,[x]
    shr ax,3
    xor al,[y]
    ret
advance_pixel:
    inc word [x]
    cmp word [x],640
    jb .done
    mov word [x],0
    inc word [y]
.done:
    ret
select_bank:
    mov ax,0e000h
    mov es,ax
    mov al,[bank]
    mov [es:4],al
    mov ax,0a800h
    mov es,ax
    ret
gdc_command:
    push ax
.wait:
    in al,0a0h
    test al,2
    jnz .wait
    pop ax
    out 0a2h,al
    ret
gdc_parameter:
    push ax
.wait:
    in al,0a0h
    test al,2
    jnz .wait
    pop ax
    out 0a0h,al
    ret
%ifdef STAGED
pause_stage:
    mov ah,9
    int 21h
    in al,0a0h
    mov bl,al
    shr al,4
    call hex_nibble
    mov al,bl
    and al,15
    call hex_nibble
    mov dx,stage_end
    mov ah,9
    int 21h
    mov ah,8
    int 21h
    ret
hex_nibble:
    add al,'0'
    cmp al,'9'
    jbe .emit
    add al,7
.emit:
    mov dl,al
    mov ah,2
    int 21h
    ret
stage0: db 13,10,'S0 BIOS only; GDC status=$'
stage1: db 13,10,'S1 +pitch40; GDC status=$'
stage2: db 13,10,'S2 +repeat0; GDC status=$'
stage3: db 13,10,'S3 +SAD0/400lines; GDC status=$'
stage4: db 13,10,'S4 +slow clocks; GDC status=$'
stage5: db 13,10,'S5 +display enable; GDC status=$'
stage_end: db ' (key advances)',13,10,'$'
%endif
failed:
    mov dx,failed_text
    mov ah,9
    int 21h
    sti
.halt:
    hlt
    jmp .halt
bank: db 0
saved_mode: db 0
x: dw 0
y: dw 0
filename: db 'A:\Z98PGC.TXT',0
start_text: db 'PEGC framebuffer and explicit-raster test starting',13,10,'$'
passed_text: db 'PASS: all 262144 framebuffer bytes read back correctly.',13,10
%ifdef BIOS9821
%ifdef PITCH_ONLY
             db 'Extended BIOS plus pitch40: inspect independent reference.',13,10
%else
             db 'Extended BIOS geometry: inspect independent pixel reference.',13,10
%endif
%else
             db 'Explicit 640x400 raster: inspect independent pixel reference.',13,10
%endif
passed_end: db '$'
failed_text: db 'FAIL: PEGC framebuffer/readback or result-file operation.',13,10,'$'
