; SPDX-License-Identifier: GPL-3.0-or-later
; Windows 95 MSVFW32 DrawDibBegin (7D4B5FB1..7D4B600D, Magical Chase): three
; REP MOVSD copies of a BITMAPINFO, each followed by a reload of the header
; pointer from the stack frame. On the core the reload after the palette copy
; returned the copy's starting ESI (header + biSize), so the next copy used
; palette entry 8 (00C0DCC0h) as the colour count and ran off the heap.
; 32-bit protected mode with paging; every pass varies the colour count and
; the cache/TLB state. Port 7FE4h prints the registers (EBX = pass on a
; mismatch); 7FF0h gets 600Dh.
bits 16
cpu 486
org 1000h
HDR     equ 4b9b8h              ; BITMAPINFOHEADER, palette at +28h (same page)
OBJ     equ 76800h              ; DrawDib object
FRAME   equ 8f08h
cli
xor ax,ax
mov ds,ax
lgdt [gdtr]
mov eax,cr0
or al,1
mov cr0,eax
jmp dword 8:pm32
align 8
gdt:
dq 0
dq 00cf9a000000ffffh
dq 00cf92000000ffffh
gdtr:
dw $-gdt-1
dd gdt
bits 32
pm32:
mov ax,10h
mov ds,ax
mov es,ax
mov ss,ax
mov esp,8e00h
mov edi,20000h                  ; identity-map 0-4 MB
mov dword [edi],21000h | 3
mov edi,21000h
mov eax,3
.pte:
stosd
add eax,1000h
cmp edi,22000h
jne .pte
mov eax,20000h
mov cr3,eax
mov eax,cr0
or eax,80000000h
mov cr0,eax
jmp .paged
.paged:
mov edi,HDR + 28h               ; palette: entry i = i * 01010101h ^ 00C0DCC0h
xor eax,eax
.pal:
mov edx,eax
imul edx,edx,01010101h
xor edx,00c0dcc0h
mov [edi+eax*4],edx
inc eax
cmp eax,256
jne .pal
mov dword [HDR],28h
mov dword [HDR+4],0b4h
mov dword [HDR+8],6dh
mov word [HDR+0ch],1
mov word [HDR+0eh],8
mov dword [FRAME+18h],HDR
mov dword [OBJ+0d4h],OBJ + 800h
xor ebx,ebx                     ; pass number
pass:
mov eax,ebx
and eax,7
mov ecx,[counts+eax*4]
mov [HDR+20h],ecx               ; biClrUsed
test bl,8
jz .warm
wbinvd
.warm:
test bl,10h
jz .tlb
invlpg [HDR]
invlpg [OBJ]
invlpg [FRAME]
.tlb:
push ebx
mov ebp,FRAME
mov ebx,OBJ
mov eax,ebp                     ; scratch values the DLL had live
mov ecx,ebp
mov edx,ebp
; --- MSVFW32 7D4B5FB1 ---
lea edi,[ebx+0dch]
mov esi,[ebp+18h]
mov ecx,0ah
rep movsd
mov ecx,[ebx+0d4h]
mov edx,[ebp+18h]
mov dword [ecx+14h],0
mov dword [ebx+0f0h],0
cmp word [edx+0eh],8
ja near fail
mov ecx,[edx+20h]
mov esi,[edx]
shl ecx,2
lea edi,[ebx+104h]
shr ecx,2
add esi,edx
rep movsd
mov eax,[ebp+18h]
lea edi,[ebx+560h]
mov ecx,[eax+20h]
mov esi,[eax]
shl ecx,2
add esi,eax
shr ecx,2
; --- end of DLL sequence (the next instruction is the faulting copy) ---
pop ebx
cmp eax,HDR
jne fail
cmp ecx,[HDR+20h]
jne fail
cmp esi,HDR + 28h
jne fail
mov ecx,[HDR+20h]               ; first copy landed intact
mov esi,HDR + 28h
lea edi,[OBJ+104h]
repe cmpsd
jne fail
inc ebx
cmp ebx,64
jne pass
mov ax,600dh
jmp report
fail:
mov dx,7fe4h
out dx,ax
mov ax,0deadh
report:
mov dx,7ff0h
out dx,ax
hlt
jmp $
align 4
counts dd 256, 0, 2, 3, 0, 255, 1, 0
