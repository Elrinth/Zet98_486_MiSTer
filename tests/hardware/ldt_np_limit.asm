; SPDX-License-Identifier: GPL-3.0-or-later
; A segment load past the LDT limit must raise #GP(selector & FFFCh) before
; any descriptor read. Windows 95's VMM returns to a protected-mode client
; with "mov ds,[esp+38h] / mov es,[esp+3Ch] / mov fs,[esp+40h] / mov gs,
; [esp+44h]" (C00013B7) and nulls a stale selector from its #GP handler. Its
; LDT is three pages (limit 2FFFh) inside a larger, not-present reservation:
; the core issued the descriptor read before the selector test redirected,
; took #PF on the page past the table, entered the page-fault path with the
; client frame half restored and later looped on #GP at C00013B7.
; Paging on, LDT at 203000h (limit 2FFFh, pages 3..15 not present), FS =
; CFFFh (descriptor at 20FFF8h). Each iteration moves the frame to another
; offset/page and mixes WBINVD/INVD so the frame reads miss differently.
; 7FF0h gets 600Dh; on failure EBP is 1 (#GP count), 2 (error code), 4 (FS
; not nulled) or BBh (another vector: EBX vector, ECX error code, EDI CR2).
bits 16
cpu 486
org 1000h
PD  equ 30000h
PT  equ 31000h
IDT equ 32000h
NITER equ 300
cli
xor ax,ax
mov ds,ax
lgdt [gdtr]
mov eax,cr0
or al,1
mov cr0,eax
jmp dword 8:pm32
align 16
gdt: dq 0
     dq 00cf9a000000ffffh
     dq 00cf92000000ffffh
     dw 2fffh, 3000h, 8220h, 0      ; 18h LDT at 203000h, limit 2FFFh, G=0
gdt_end:
gdtr: dw gdt_end-gdt-1
      dd gdt
idtr: dw 20h*8-1
      dd IDT
bits 32
pm32:
mov ax,10h
mov ds,ax
mov es,ax
mov ss,ax
mov esp,9000h
mov edi,PT                      ; identity map 0-4 MB
mov eax,3
mov ecx,1024
.pt: stosd
add eax,1000h
loop .pt
mov edi,PD
xor eax,eax
mov ecx,1024
rep stosd
mov dword [PD],PT|3
mov edi,PT+206h*4               ; LDT pages 3..15 not present
mov ecx,13
mov eax,40000h
rep stosd
mov edi,203000h
xor eax,eax
mov ecx,3000h/4
rep stosd
mov dword [203008h],0000ffffh   ; index 1 (0Fh): flat data, DPL 3
mov dword [20300ch],00cff200h
mov dword [203ff8h],0000ffffh   ; index 1FFh (0FFFh): flat data, DPL 3
mov dword [203ffch],00cff200h
mov edi,IDT                     ; all vectors -> stubs, 0Dh -> gp
xor ecx,ecx
.g: mov eax,ecx
shl eax,4
add eax,stubs
cmp ecx,0dh
jne .n
mov eax,gp
.n: mov edx,eax
and eax,0ffffh
or eax,80000h
and edx,0ffff0000h
or edx,8e00h
mov [edi+ecx*8],eax
mov [edi+ecx*8+4],edx
inc ecx
cmp ecx,20h
jne .g
lidt [idtr]
mov eax,PD
mov cr3,eax
mov eax,cr0
or eax,80000000h
mov cr0,eax
mov ax,18h
lldt ax
xor ebp,ebp
xor ebx,ebx
.it:
; frames at 340000h+: clear of the LDT even with A20 masked (bit 20 alias)
mov esi,ebx
imul esi,esi,0d4h
and esi,0ffffch
add esi,340000h
mov dword [esi+38h],0fh
mov dword [esi+3ch],0fffh
mov dword [esi+40h],0cfffh
mov dword [esi+44h],0fh
test bl,3
jnz .nf
wbinvd
.nf:
test bl,4
jz .ni
invd
.ni:
mov dword [gpc],0
mov [savesp],esp
mov esp,esi
mov ds,[esp+38h]
mov es,[esp+3ch]
mov fs,[esp+40h]
mov gs,[esp+44h]
mov esp,[ss:savesp]
mov ax,10h
mov ds,ax
mov es,ax
cmp dword [gpc],1
jne .bad1
cmp dword [gperr],0cffch
jne .bad2
mov ax,fs
test ax,ax
jnz .bad3
inc ebx
cmp ebx,NITER
jne .it
jmp done
.bad1: or ebp,1
jmp done
.bad2: or ebp,2
jmp done
.bad3: or ebp,4
done:
mov ax,10h
mov ds,ax
mov dx,7ff0h
mov ax,600dh
test ebp,ebp
jz .ok
mov ax,0deadh
.ok:
out dx,ax
hlt
; #GP: like VMM, null the faulting client selector in the frame and retry
gp:
push eax
mov eax,[ss:esp+4]
mov [ss:gperr],eax
inc dword [ss:gpc]
cmp dword [ss:gpc],5
jb .gpok
mov ebp,1
jmp done
.gpok:
mov dword [ss:esi+40h],0
pop eax
add esp,4
iretd
align 16
stubs:
%assign v 0
%rep 32
mov ebx,v
jmp near vec_common
times 6 nop
%assign v v+1
%endrep
vec_common:
mov ecx,[esp]
mov edi,cr2
mov ebp,0bbh
jmp done
align 4
gpc dd 0
gperr dd 0
savesp dd 0
