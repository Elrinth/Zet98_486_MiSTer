; SPDX-License-Identifier: GPL-3.0-or-later
; Standalone Linux/i386 diagnostic, no libc and no bundled game/BIOS assets.
bits 32
global _start
section .text
_start:
    mov [oldesp],esp
    mov eax,192
    xor ebx,ebx
    mov ecx,8192
    mov edx,3
    mov esi,22h
    mov edi,-1
    xor ebp,ebp
    int 80h
    cmp eax,0fffff000h
    jae fail
    mov [base],eax
    mov dword [eax+4096],12345678h
    lea esp,[eax+1014h]
    mov [expected],esp
    mov ebp,0aabbccddh
    mov edi,12345678h
    mov esi,20h
    mov ebx,87654321h
    push dword 080a4120h
    call callee
    add esp,4
    cmp esp,[expected]
    jne fail
    cmp eax,080a4120h
    jne fail
    mov ecx,passed
    mov edx,passed_end-passed
    xor edi,edi
    jmp report
callee:
    push ebp
    push edi
    push esi
    push ebx
    sub esp,12
    mov ebp,[esp+20h]
    cmp ebp,080a4120h
    jne fail
    mov eax,ebp
    add esp,12
    pop ebx
    pop esi
    pop edi
    pop ebp
    ret
fail:
    mov ecx,failed
    mov edx,failed_end-failed
    mov edi,1
report:
    mov esp,[oldesp]
    mov eax,4
    mov ebx,1
    int 80h
    mov eax,1
    mov ebx,edi
    int 80h
section .data
passed db 'PASS Linux stack page-fault restart',10
passed_end:
failed db 'FAIL Linux stack page-fault restart',10
failed_end:
oldesp dd 0
base dd 0
expected dd 0
section .note.GNU-stack noalloc noexec nowrite progbits
