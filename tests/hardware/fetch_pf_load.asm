; SPDX-License-Identifier: GPL-3.0-or-later
; An instruction-fetch #PF must not drop an older load's register write
; (Windows 95 MSVFW32 DrawDibBegin, Magical Chase): "mov eax,[ebp+18h] /
; lea edi,[ebx+560h]" ends a code page, the next code page is not present,
; the VMM pages it in and returns to its first byte. On the core EAX kept its
; old value. 32-bit paging, code and data in DDR; each pass varies the
; instructions between the load and the page end and the cache state.
; Port 7FE4h prints the registers (EBX = pass); 7FF0h gets 600Dh.
bits 16
cpu 486
org 1000h
CODE    equ 300000h             ; snippet ends at CODE+1000h, CODE+1000h not present
PTE_B   equ 21000h + ((CODE + 1000h) >> 12) * 4
FRAME   equ 205908h
GOOD    equ 24b9b8h
STALE   equ 24b9e0h
IDT     equ 22000h
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
idtr:
dw 32*8-1
dd IDT
bits 32
pm32:
mov ax,10h
mov ds,ax
mov es,ax
mov ss,ax
mov esp,9000h
mov edi,IDT
xor ecx,ecx
.gate:
mov eax,bad_vector
cmp ecx,14
jne .g
mov eax,pf_handler
.g:
mov edx,eax
and eax,0ffffh
or eax,80000h
and edx,0ffff0000h
or edx,8e00h
mov [edi+ecx*8],eax
mov [edi+ecx*8+4],edx
inc ecx
cmp ecx,32
jne .gate
lidt [idtr]
mov edi,20000h
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
mov dword [FRAME+18h],GOOD
mov dword [276800h+0d4h],276800h + 800h
mov dword [GOOD],28h            ; BITMAPINFOHEADER: biSize, 8 bpp, 256 colours
mov word [GOOD+0eh],8
mov dword [GOOD+20h],256
mov byte [CODE+1000h],0c3h      ; page B: ret
xor ebx,ebx
pass:
mov eax,ebx                     ; snippet = variant (pass & 3) placed to end at the boundary
and eax,3
mov esi,[snip_start+eax*4]
mov ecx,[snip_end+eax*4]
sub ecx,esi
mov edi,CODE + 1000h
sub edi,ecx
mov [entry],edi
rep movsb
mov eax,cr0                     ; passes 64-127: cache disabled
and eax,~60000000h
test bl,40h
jz .cd
or eax,40000000h
.cd:
mov cr0,eax
test bl,4
jz .warm
wbinvd
.warm:
test bl,8
jz .tlb
invlpg [FRAME]
.tlb:
and dword [PTE_B],~1            ; page B not present
invlpg [CODE+1000h]
mov dword [faults],0
push ebx
mov ebp,FRAME
mov ebx,276800h
mov eax,STALE
mov ecx,[esp]
shr ecx,4
and ecx,3
mov ecx,[copy_counts+ecx*4]
mov esi,24b9e0h
lea edi,[ebx+104h]
call [entry]
pop ebx
cmp eax,GOOD
jne fail
cmp dword [faults],1
jne fail
inc ebx
cmp ebx,128
jne pass
mov ax,600dh
jmp report

snip0:                          ; MSVFW32 7D4B5FF5
rep movsd
mov eax,[ebp+18h]
lea edi,[ebx+560h]
snip1:
mov eax,[ebp+18h]
lea edi,[ebx+560h]
snip2:
rep movsd
mov eax,[ebp+18h]
snip3:                          ; MSVFW32 7D4B5FB1..7D4B5FFF (4Fh bytes, same alignment)
lea edi,[ebx+0dch]
mov esi,[ebp+18h]
mov ecx,0ah
rep movsd
mov ecx,[ebx+0d4h]
mov edx,[ebp+18h]
mov dword [ecx+14h],0
mov dword [ebx+0f0h],0
cmp word [edx+0eh],8
ja short $+2
mov ecx,[edx+20h]
mov esi,[edx]
shl ecx,2
lea edi,[ebx+104h]
shr ecx,2
add esi,edx
rep movsd
mov eax,[ebp+18h]
lea edi,[ebx+560h]
snip4:
snip_start dd snip0, snip1, snip2, snip3
snip_end dd snip1, snip2, snip3, snip4
%if snip4 - snip3 != 4fh
%error DLL block length
%endif

pf_handler:
push eax
mov eax,cr2
cmp eax,CODE+1000h
jne fail
cmp dword [esp+4],0             ; supervisor fetch, not present
jne fail
inc dword [faults]
or dword [PTE_B],1
invlpg [CODE+1000h]
mov eax,[9000h-400h]            ; VMM work: unrelated loads/stores
mov [9000h-404h],eax
pop eax
add esp,4
iretd
bad_vector:
mov ebp,0eeeeh
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
entry dd 0
copy_counts dd 256, 10, 1, 0
faults dd 0
