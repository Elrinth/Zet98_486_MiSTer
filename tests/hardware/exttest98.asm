; SPDX-License-Identifier: GPL-3.0-or-later
; EXTTEST.COM: extended-RAM (1-15 MB) store/load/copy/execute check in flat
; protected mode, without XMS/VCPI (run from plain DOS, no EMM386).
; Prints per-test error counts and the first mismatch, then returns to DOS.
bits 16
cpu 486
org 100h

LO      equ 110000h             ; above the HMA (DOS=HIGH lives at 100000h)
HI      equ 0E00000h            ; page tables and stack live above this
PD      equ 0E80000h
PT0     equ 0E81000h
IDTB    equ 0E70000h
IRQSCR  equ 0E60000h

start:
    mov ax,cs
    movzx eax,ax
    shl eax,4
    mov [linbase],eax
    ; GDT descriptor bases: 08h code32, 18h code16 at the COM's base.
    mov [gdt+08h+2],ax
    mov [gdt+18h+2],ax
    mov [gdt+20h+2],ax
    shr eax,16
    mov [gdt+08h+4],al
    mov [gdt+18h+4],al
    mov [gdt+20h+4],al
    mov eax,[linbase]
    add eax,gdt
    mov [gdtr+2],eax
    mov [rmseg],cs
    push ds
    xor ax,ax
    mov ds,ax
    movzx eax,word [0594h]
    pop ds
    shl eax,20
    add eax,1000000h
    mov [hitop],eax
%ifdef DIAG
    call csum
    mov [csum0],eax
    mov di,blk0
    call blksum
    push ds                      ; snapshot 0000:0000-0FFF
    push ds
    pop es
    xor ax,ax
    mov ds,ax
    xor si,si
    mov di,snap
    mov cx,800h
    rep movsw
    pop ds
%endif
    mov [savesp],sp
    cli
    out 0f2h,al                 ; A20 on
    lgdt [gdtr]
    mov eax,cr0
    or al,1
    mov cr0,eax
    jmp dword 08h:pm32

back16:                          ; 16-bit protected mode, base = COM
    mov ax,20h
    mov ds,ax
    mov es,ax
    mov ss,ax
    mov eax,cr0
    and al,0feh
    mov cr0,eax
    jmp far [rmjmp]
rmback:
    mov ax,cs
    mov ds,ax
    mov es,ax
    mov ss,ax
    mov sp,[savesp]
%ifdef FLUSH
    wbinvd                      ; discard any stale CPU cache lines
%endif
%ifdef DIAG3
    ; Row 0: EFLAGS CR0 IDTR.base IDTR.limit GDTR.limit DS ES SS SP FS GS
    ; Row 1: INT 21h vector, first 8 bytes at it; then a DOS print test.
    pushfd
    pop eax
    mov [d3+0],eax
    mov eax,cr0
    mov [d3+4],eax
    sidt [d3+8]
    sgdt [d3+16]
    push es
    mov ax,0a000h
    mov es,ax
    mov di,0
    mov eax,[d3+0]
    call vhex
    add di,2
    mov eax,[d3+4]
    call vhex
    add di,2
    mov eax,[d3+10]
    call vhex
    add di,2
    movzx eax,word [d3+8]
    call vhex
    add di,2
    movzx eax,word [d3+16]
    call vhex
    add di,2
    mov ax,ds
    movzx eax,ax
    call vhex
    add di,2
    pop ax
    push ax
    movzx eax,ax
    call vhex
    add di,2
    mov ax,ss
    movzx eax,ax
    call vhex
    add di,2
    movzx eax,sp
    call vhex
    mov di,160
    push ds
    xor ax,ax
    mov ds,ax
    mov eax,[84h]
    pop ds
    call vhex
    add di,2
    push ds
    xor ax,ax
    mov ds,ax
    lds si,[84h]
    mov eax,[si]
    mov ebx,[si+4]
    pop ds
    call vhex
    mov eax,ebx
    call vhex
    pop es
    sti
    mov dx,s_probe
    mov ah,9
    int 21h
    mov dx,s_probe
    mov ah,9
    int 21h
    jmp $
%endif
%ifdef DIAG
    ; Before any DOS call: show the code checksum and counters in text VRAM
    ; (row 0) and stop, so DOS output cannot hide them.
    call csum
    mov [csum1],eax
    mov ax,0a000h
    mov es,ax
    xor di,di
    mov eax,[csum0]
    call vhex
    add di,2
    mov eax,[csum1]
    call vhex
    add di,2
    mov eax,[total]
    call vhex
    add di,2
    mov eax,[irqcnt]
    call vhex
    add di,2
    mov eax,[unexp]
    call vhex
    add di,2
    movzx eax,word [rmseg]
    call vhex
    ; 4 KB block map of conventional memory: '.' same, 'X' changed, 'o' ours
    mov di,blk1
    push es
    push ds
    pop es
    call blksum
    pop es
    mov di,160                  ; row 1
    xor bx,bx
.bm: mov eax,[blk0+bx]
    mov dl,'.'
    cmp eax,[blk1+bx]
    je .bs
    mov dl,'X'
.bs: mov ax,bx
    shr ax,2                    ; block number
    shl ax,8                    ; paragraph of block
    mov cx,cs
    sub ax,cx
    cmp ax,0F000h               ; our 64 KB segment: block starts within it
    ja .bw
    cmp ax,1000h
    jae .bw
    mov dl,'o'
.bw: mov al,dl
    xor ah,ah
    stosw
    add bx,4
    cmp bx,160*4
    jb .bm
    ; rows 3+: first 40 changed bytes of 0000:0000-0FFF as offset:old>new
    push ds
    xor ax,ax
    mov fs,ax
    pop ds
    mov di,160*3
    xor si,si
    xor bp,bp
.df: mov al,[fs:si]
    cmp al,[snap+si]
    je .dn
    push ax
    movzx eax,si
    shl eax,16
    mov cx,4
    call vhexn
    mov ax,':'
    stosw
    movzx eax,byte [snap+si]
    shl eax,24
    mov cx,2
    call vhexn
    mov ax,'>'
    stosw
    pop ax
    movzx eax,al
    shl eax,24
    mov cx,2
    call vhexn
    add di,2
    inc bp
    cmp bp,40
    jae .dd
.dn: inc si
    cmp si,1000h
    jb .df
.dd:
    sti
    jmp $
%endif
    mov al,3                    ; A20 off again (F6h command 03h)
    out 0f6h,al
    sti
    ; ---- report ----
    mov si,names
    mov bx,errs
    mov cx,NTEST
.rep:
    push cx
    cmp dword [bx],0             ; print failing tests only
    je .skip
    mov dx,si
    call puts0
    mov eax,[bx]
    call hex32
    mov dx,s_first
    call puts
    mov eax,[bx+4]
    call hex32
    mov dx,s_exp
    call puts
    mov eax,[bx+8]
    call hex32
    mov dx,s_got
    call puts
    mov eax,[bx+12]
    call hex32
    mov dx,s_crlf
    call puts
.skip:
    lodsb
    test al,al
    jnz .skip
    add bx,16
    pop cx
    loop .rep
    mov dx,s_irq
    call puts
    mov eax,[irqcnt]
    call hex32
    mov dx,s_unexp
    call puts
    mov eax,[unexp]
    call hex32
    mov dx,s_crlf
    call puts
    mov dx,s_total
    call puts
    mov eax,[total]
    call hex32
    mov dx,s_crlf
    call puts
    mov ax,4c00h
    int 21h

%ifdef DIAG
csum:                            ; EAX = sum of the code bytes 100h..gdt
    mov si,100h
    xor eax,eax
    xor ebx,ebx
.c: mov bl,[si]
    add eax,ebx
    rol eax,1
    inc si
    cmp si,gdt
    jb .c
    ret
blksum:                          ; DS:DI <- 160 sums of 4 KB blocks of 0-9FFFFh
    push ds
    mov dx,0
.b: mov ds,dx
    xor si,si
    xor eax,eax
    xor ebx,ebx
.s: mov bl,[si]
    add eax,ebx
    rol eax,1
    inc si
    cmp si,1000h
    jb .s
    pop ds
    mov [di],eax
    push ds
    add di,4
    add dx,100h
    cmp dx,0A000h
    jb .b
    pop ds
    ret
vhex:                            ; EAX as 8 hex chars at ES:DI (text VRAM)
    mov cx,8
vhexn:                           ; EAX top CX nibbles
.v: rol eax,4
    push eax
    and al,0fh
    add al,'0'
    cmp al,'9'
    jbe .w
    add al,7
.w: xor ah,ah
    stosw
    pop eax
    loop .v
    ret
%endif
puts:                            ; DS:DX '$'-terminated
    mov ah,9
    int 21h
    ret
puts0:                           ; DS:DX zero-terminated
    push si
    mov si,dx
.l: lodsb
    test al,al
    jz .d
    mov dl,al
    mov ah,2
    int 21h
    jmp .l
.d: pop si
    ret
hex32:
    mov cx,8
.h: rol eax,4
    push eax
    and al,0fh
    add al,'0'
    cmp al,'9'
    jbe .p
    add al,7
.p: mov dl,al
    mov ah,2
    int 21h
    pop eax
    loop .h
    ret

; ---------------------------------------------------------------- 32-bit
bits 32
pm32:
    mov ax,10h
    mov ds,ax
    mov es,ax
    mov ss,ax
    mov ebp,[cs:linbase]         ; flat address of this program
    mov esp,0F00000h - 16        ; stack in extended RAM (exercised too)
    mov dword [ebp+tbase],0
    call runall
    ; Second pass with paging: identity map 0-64 MB, tables in extended RAM.
    mov edi,PD
    mov ecx,1024
    xor eax,eax
    rep stosd
    mov edi,PD
    mov eax,PT0+7
    mov ecx,16                  ; identity map 0-64 MB
.pde: stosd
    add eax,1000h
    loop .pde
    mov edi,PT0
    mov eax,7
    mov ecx,16384
.pte: stosd
    add eax,1000h
    loop .pte
    mov eax,PD
    mov cr3,eax
    mov eax,cr0
    or eax,80000000h
    mov cr0,eax
    jmp .pg
.pg:
    mov dword [ebp+tbase],9
    call runall
    ; Third pass: paging + interrupts. IDT in extended RAM, PIT channel 0 at
    ; about 600 Hz; IRQ handlers store to extended and conventional memory.
    mov edi,IDTB
    xor ecx,ecx
.idt: mov eax,irq_other          ; gate offsets are COM-relative (CS base)
    cmp ecx,8
    jne .g1
    mov eax,irq_timer
.g1: cmp ecx,9
    jb .g2
    cmp ecx,0Fh
    ja .g2
    cmp ecx,8
    je .g2
    mov eax,irq_master
.g2: mov [edi],ax
    mov word [edi+2],08h
    mov word [edi+4],8E00h
    shr eax,16
    mov [edi+6],ax
    add edi,8
    inc ecx
    cmp ecx,256
    jb .idt
    lidt [ebp+idtr]
    mov al,34h                  ; PIT ch0, lo/hi, mode 2
    out 77h,al
    mov al,00h
    out 71h,al
    mov al,10h
    out 71h,al
    in al,02h
    mov [ebp+picmask],al
    and al,0FEh                 ; unmask IRQ0
    out 02h,al
    mov dword [ebp+tbase],18
    sti
    call runall
    cli
    mov al,[ebp+picmask]
    out 02h,al
    mov al,30h                  ; PIT ch0 back to a quiet one-shot (mode 0)
    out 77h,al
    mov al,0FFh
    out 71h,al
    out 71h,al
    lidt [ebp+rmidtr]
    mov eax,cr0
    and eax,7fffffffh
    mov cr0,eax
    jmp .npg
.npg:
    xor eax,eax
    mov cr3,eax
    jmp 18h:back16

runall:
    ; T0: address pattern dwords
    mov edi,LO
.t0w: mov eax,edi
    xor eax,5A5A3C3Ch
    rol eax,7
    mov [edi],eax
    add edi,4
    cmp edi,HI
    jb .t0w
    mov esi,LO
    mov ebx,0
.t0r: mov eax,esi
    xor eax,5A5A3C3Ch
    rol eax,7
    mov edx,[esi]
    cmp edx,eax
    je .t0n
    call fail
.t0n: add esi,4
    cmp esi,HI
    jb .t0r
    ; T1: byte stores over 2 MB, dword verify
    mov edi,200000h
.t1w: mov eax,edi
    imul eax,eax,9Dh
    shr eax,3
    mov [edi],al
    inc edi
    cmp edi,400000h
    jb .t1w
    mov esi,200000h
    mov ebx,1
.t1r: mov eax,esi
    imul eax,eax,9Dh
    shr eax,3
    movzx eax,al
    movzx edx,byte [esi]
    cmp edx,eax
    je .t1n
    call fail
.t1n: inc esi
    cmp esi,400000h
    jb .t1r
    ; T2: unaligned words then unaligned dwords (stride 3 / 5)
    mov edi,400001h
.t2w: mov eax,edi
    rol eax,11
    mov [edi],ax
    add edi,3
    cmp edi,500000h
    jb .t2w
    mov esi,400001h
    mov ebx,2
.t2r: mov eax,esi
    rol eax,11
    movzx eax,ax
    movzx edx,word [esi]
    cmp edx,eax
    je .t2n
    call fail
.t2n: add esi,3
    cmp esi,500000h-3
    jb .t2r
    mov edi,500003h
.t3w: mov eax,edi
    xor eax,0C3A50F69h
    mov [edi],eax
    add edi,5
    cmp edi,600000h
    jb .t3w
    mov esi,500003h
    mov ebx,3
.t3r: mov eax,esi
    xor eax,0C3A50F69h
    mov edx,[esi]
    cmp edx,eax
    je .t3n
    call fail
.t3n: add esi,5
    cmp esi,600000h-5
    jb .t3r
    ; T4: read-modify-write and store->load chains
    mov edi,600000h
.t4w: mov dword [edi],12345678h
    add dword [edi],edi
    xor [edi],edi
    mov eax,[edi]
    mov [edi+4],eax
    inc dword [edi+4]
    add edi,8
    cmp edi,700000h
    jb .t4w
    mov esi,600000h
    mov ebx,4
.t4r: mov eax,12345678h
    add eax,esi
    xor eax,esi
    mov edx,[esi]
    cmp edx,eax
    je .t4a
    call fail
.t4a: inc eax
    mov edx,[esi+4]
    cmp edx,eax
    je .t4n
    push esi
    add esi,4
    call fail
    pop esi
.t4n: add esi,8
    cmp esi,700000h
    jb .t4r
%ifdef IRQ_NO_REP
    cmp dword [ebp+tbase],18     ; interrupt pass: skip the long REP copies
    je .t7s
%endif
    ; T5: rep movsd 960 KB (T0 pattern, below T1's 2 MB) to 0A00000h,
    ; then rep movsb unaligned 64 KB
    mov esi,LO
    mov edi,0A00000h
    mov ecx,0F0000h/4
    cld
    rep movsd
    mov esi,0A00000h
    mov ebx,5
.t5r: mov eax,esi
    sub eax,0A00000h-LO
    xor eax,5A5A3C3Ch
    rol eax,7
    mov edx,[esi]
    cmp edx,eax
    je .t5n
    call fail
.t5n: add esi,4
    cmp esi,0AF0000h
    jb .t5r
    mov esi,LO+1
    mov edi,0B00003h
    mov ecx,10000h
    rep movsb
    mov esi,LO+1
    mov edi,0B00003h
    mov ecx,10000h
    mov ebx,6
.t6r: mov al,[esi]
    cmp al,[edi]
    je .t6n
    push esi
    mov esi,edi
    call fail
    pop esi
.t6n: inc esi
    inc edi
    dec ecx
    jnz .t6r
    ; T7: execute code copied to extended RAM at 16 alignments
.t7s:
    xor edx,edx
.t7c: mov edi,0C00000h
    add edi,edx
    lea esi,[ebp+fn_start]
    mov ecx,fn_end-fn_start
    rep movsb
    mov eax,0C00000h
    add eax,edx
    sub eax,ebp                  ; offset in the COM-based code segment
    push edx
    mov ecx,1000
    call eax
    pop edx
    push eax
    mov ecx,1000
    call fn_start
    mov ecx,eax
    pop eax
    cmp eax,ecx
    je .t7n
    mov ebx,7
    lea esi,[edx+0C00000h]
    push edx
    mov edx,eax
    mov eax,ecx
    call fail
    pop edx
.t7n: inc edx
    cmp edx,16
    jb .t7c
    ; T8: dword pattern above 16 MB (up to the BIOS-reported top)
    mov edi,1000000h
    mov ecx,[ebp+hitop]
    cmp edi,ecx
    jae .t8d
.t8w: mov eax,edi
    xor eax,0A5C3965Ah
    ror eax,5
    mov [edi],eax
    add edi,4
    cmp edi,ecx
    jb .t8w
    mov esi,1000000h
    mov ebx,8
.t8r: mov eax,esi
    xor eax,0A5C3965Ah
    ror eax,5
    mov edx,[esi]
    cmp edx,eax
    je .t8n
    push ecx
    call fail
    pop ecx
.t8n: add esi,4
    cmp esi,ecx
    jb .t8r
.t8d:
    ret

; fail: EBX=test, ESI=address, EAX=expected, EDX=actual
fail:
    push edi
    lea edi,[ebp+errs]
    add ebx,[ebp+tbase]
    shl ebx,4
    add edi,ebx
    shr ebx,4
    sub ebx,[ebp+tbase]
    cmp dword [edi],0
    jne .f1
    mov [edi+4],esi
    mov [edi+8],eax
    mov [edi+12],edx
.f1: inc dword [edi]
    inc dword [ebp+total]
    pop edi
    ret

irq_timer:
%ifdef IRQ_EOI_ONLY
    push eax
    mov al,20h
    out 00h,al
    pop eax
    iretd
%endif
    push eax
    push edx
    mov edx,[cs:linbase]
    mov eax,[edx+irqcnt]
    inc eax
    mov [edx+irqcnt],eax
    and eax,0FFh
    add dword [IRQSCR+eax*4],eax  ; extended-RAM read-modify-write
    mov edx,eax
    imul edx,edx,3
    mov [IRQSCR+400h+edx],dl      ; unaligned byte store
    mov al,20h                     ; EOI master
    out 00h,al
    pop edx
    pop eax
    iretd
irq_master:
    push eax
    mov al,20h
    out 00h,al
    pop eax
    iretd
irq_other:
    push eax
    mov eax,[cs:linbase]
    inc dword [eax+unexp]
    pop eax
    iretd

; Position-independent mixed loop: ECX iterations, result in EAX.
fn_start:
    mov eax,1
    xor edx,edx
.l: imul eax,eax,41C64E6Dh
    add eax,3039h
    add edx,eax
    test eax,40000h
    jz .s
    xor edx,ecx
.s: dec ecx
    jnz .l
    add eax,edx
    ret
fn_end:

; ---------------------------------------------------------------- data
bits 16
align 8
gdt:
    dq 0
    dq 00cf9a000000ffffh         ; 08h code32, base patched
    dq 00cf92000000ffffh         ; 10h flat data
    dq 00009a000000ffffh         ; 18h code16, base patched
    dq 000092000000ffffh         ; 20h data16, base patched (64 KB)
gdtr:
    dw 5*8-1
    dd 0
linbase dd 0
savesp  dw 0
rmjmp   dw rmback
rmseg   dw 0
total   dd 0
tbase   dd 0
csum0   dd 0
d3      times 8 dd 0
s_probe db 'DOS PRINT OK',13,10,'$'
csum1   dd 0
blk0    times 160 dd 0
blk1    times 160 dd 0
snap    times 1000h db 0
irqcnt  dd 0
unexp   dd 0
picmask db 0
idtr    dw 256*8-1
        dd IDTB
rmidtr  dw 3FFh
        dd 0
hitop   dd 0
NTEST   equ 27
errs    times NTEST*4 dd 0
names   db 'T0 dword pattern    ',0
        db 'T1 byte stores      ',0
        db 'T2 unaligned words  ',0
        db 'T3 unaligned dwords ',0
        db 'T4 RMW/store-load   ',0
        db 'T5 rep movsd copy   ',0
        db 'T6 rep movsb unalig ',0
        db 'T7 code in ext RAM  ',0
        db 'T8 dwords >16 MB    ',0
        db 'PT0 dword pattern   ',0
        db 'PT1 byte stores     ',0
        db 'PT2 unaligned words ',0
        db 'PT3 unaligned dwords',0
        db 'PT4 RMW/store-load  ',0
        db 'PT5 rep movsd copy  ',0
        db 'PT6 rep movsb unalig',0
        db 'PT7 code in ext RAM ',0
        db 'PT8 dwords >16 MB   ',0
        db 'IT0 dword pattern   ',0
        db 'IT1 byte stores     ',0
        db 'IT2 unaligned words ',0
        db 'IT3 unaligned dwords',0
        db 'IT4 RMW/store-load  ',0
        db 'IT5 rep movsd copy  ',0
        db 'IT6 rep movsb unalig',0
        db 'IT7 code in ext RAM ',0
        db 'IT8 dwords >16 MB   ',0
s_first db ' first $'
s_exp   db ' exp $'
s_got   db ' got $'
s_crlf  db 13,10,'$'
s_irq   db 'IRQs $'
s_unexp db ' unexpected $'
s_total db 'EXTTEST total errors $'
