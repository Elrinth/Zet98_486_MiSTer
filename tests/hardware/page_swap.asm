; SPDX-License-Identifier: GPL-3.0-or-later
; Windows 95 VMM page exchange (VMM C0222000): with interrupts off, swap the
; contents of two linear pages with an XCHG loop, swap their PTEs through the
; page-table self-map at FF800000h with another XCHG loop, then reload CR3.
; Each page keeps its linear contents but moves to the other physical page.
; Afterwards the linear pages must read their own patterns (no stale
; translation) and identity aliases of the physical pages the swapped ones.
; Port 7FE4h prints the registers (EBP = case/step); 7FF0h gets 600Dh.
bits 16
cpu 486
org 1000h
PD      equ 20000h
PT      equ 21000h
A       equ 300000h             ; linear pages exchanged by the routine
B       equ 301000h
PA      equ 300000h             ; their physical pages at the start
PB      equ 301000h
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
dq 00cf9a000000ffffh            ; 08h flat code
dq 00cf92000000ffffh            ; 10h flat data
gdtr:
dw $-gdt-1
dd gdt
bits 32
pm32:
mov ax,10h
mov ds,ax
mov es,ax
mov ss,ax
mov esp,9000h
mov edi,PD                      ; PDE 0: identity 0-4 MB; PDE 3FEh: self-map
xor eax,eax
mov ecx,1024
rep stosd
mov dword [PD],PT | 3
mov dword [PD+3feh*4],PD | 3
mov edi,PT
mov eax,3
.pte:
stosd
add eax,1000h
cmp edi,PT+1000h
jne .pte
mov eax,PD
mov cr3,eax
mov eax,cr0
or eax,80000000h
mov cr0,eax
jmp .paged
.paged:
mov ebp,1
.round:
mov edi,A                       ; patterns, then touch both pages (TLB, cache)
mov ecx,1024
mov eax,0aaaa0000h
.fa:
stosd
inc eax
loop .fa
mov edi,B
mov ecx,1024
mov eax,0bbbb0000h
.fb:
stosd
inc eax
loop .fb
mov esi,A
mov ecx,2048
.touch:
lodsd
loop .touch
push dword 1                    ; one page
push dword B
push dword A
call vmm_swap
inc ebp
; linear contents unchanged
mov esi,A
mov ecx,1024
mov edx,0aaaa0000h
.ca:
lodsd
cmp eax,edx
jne fail
inc edx
loop .ca
mov esi,B
mov ecx,1024
mov edx,0bbbb0000h
.cb:
lodsd
cmp eax,edx
jne fail
inc edx
loop .cb
inc ebp
; PTEs exchanged
mov eax,[PT+(A>>12)*4]
and eax,0fffff000h
cmp eax,PB
jne fail
mov eax,[PT+(B>>12)*4]
and eax,0fffff000h
cmp eax,PA
jne fail
inc ebp
; physical pages exchanged: map an alias at 302000h onto PA, then PB
mov dword [PT+302h*4],PA | 3
invlpg [302000h]
mov eax,[302000h]
cmp eax,0bbbb0000h
jne fail
mov eax,[302ffch]
cmp eax,0bbbb03ffh
jne fail
mov dword [PT+302h*4],PB | 3
invlpg [302000h]
mov eax,[302000h]
cmp eax,0aaaa0000h
jne fail
; restore identity for the next round
mov dword [PT+(A>>12)*4],PA | 3
mov dword [PT+(B>>12)*4],PB | 3
mov eax,cr3
mov cr3,eax
add ebp,10h
and ebp,0fff0h
inc ebp
cmp ebp,41h                     ; four rounds
jb .round
mov ax,600dh
jmp report

; VMM C0222000, as in Windows 95 (args: linear A, linear B, page count)
vmm_swap:
pushfd
push ebp
push esi
push edi
cli
mov eax,cr3
mov esi,[esp+14h]
mov edi,[esp+18h]
mov ecx,[esp+1ch]
mov ebp,ecx
shl ecx,0ah
.data:
mov edx,[esi]
xchg [edi],edx
mov [esi],edx
add esi,4
add edi,4
loop .data
mov ecx,ebp
shr esi,0ch
shr edi,0ch
sub esi,ecx
sub edi,ecx
lea esi,[esi*4-800000h]
lea edi,[edi*4-800000h]
.ptes:
mov edx,[esi]
xchg [edi],edx
mov [esi],edx
add esi,4
add edi,4
loop .ptes
mov cr3,eax
pop edi
pop esi
pop ebp
popfd
ret 0ch

fail:
mov dx,7fe4h
out dx,ax
mov ax,0deadh
report:
mov dx,7ff0h
out dx,ax
hlt
jmp $
