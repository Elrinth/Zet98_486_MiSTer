; Shift flags across a chained stack instruction (z486 SHIFT2 deferred flags).
; A stack instruction issued in the SHIFT2 cycle used to overwrite SIGMA with
; its new SP before the deferred Z/S/P retirement read it. Windows 95 VMM's
; semaphore wait (SHR AH,7 / RET, then JNE in the caller after an indirect
; CALL) then never saw its I/O completion. Writes 600Dh to 7FF0h if every
; case is right, else reports registers at 7FE4h (EBP = case) and 0BADh.
        bits 16
        org 1000h
        cli
        xor ax, ax
        mov ds, ax
        mov ss, ax
        mov sp, 0f00h
        mov word [500h], 1
        mov si, 500h
%macro FAIL_UNLESS 2                    ; condition jump that means OK, case
        %1 %%ok
        mov bp, %2
        jmp fail
%%ok:
%endmacro
        ; 1: indirect call, callee SHR AH,7 / RET, ZF=1 expected
        push word f_shr_ah
        mov bx, sp
        mov eax, 0c0fc0000h
        call word [bx]
        FAIL_UNLESS jz, 1
        jpe .c1p
        mov bp, 101
        jmp fail
.c1p:   add sp, 2
        ; 2: memory form as in VMM: MOV AX,[SI] / DEC EAX / SHR AH,7 / RET
        push word f_vmm
        mov bx, sp
        mov eax, 0c0fce300h
        call word [bx]
        FAIL_UNLESS jz, 2
        add sp, 2
        ; 3: SAR AH,1 with AH=80h -> C0h: SF=1 ZF=0, then PUSH
        mov ah, 80h
        sar ah, 1
        push ax
        FAIL_UNLESS js, 3
        FAIL_UNLESS jnz, 4
        pop ax
        ; 5: SHL BX,1 (8000h -> 0, ZF=1) then POP
        push word 1234h
        mov bx, 8000h
        shl bx, 1
        pop cx
        FAIL_UNLESS jz, 5
        ; 6: SHR EDX,31 (7FFFFFFFh -> 0, ZF=1) then CALL
        mov edx, 7fffffffh
        shr edx, 31
        call f_check_zf
        cmp al, 1
        FAIL_UNLESS je, 6
        ; 7: SHR AL,1 (1 -> 0) then RET from a near call
        call f_shr_al
        FAIL_UNLESS jz, 7
        ; 8: nonzero result must clear ZF: SHR AH,1 (AH=2 -> 1) then RET
        push word f_shr_ah1
        mov bx, sp
        mov eax, 0200h
        call word [bx]
        FAIL_UNLESS jnz, 8
        add sp, 2
        mov dx, 7ff0h
        mov ax, 600dh
        out dx, ax
        hlt
fail:
        mov dx, 7fe4h                   ; register report: EBP = failing case
        out dx, al
        mov dx, 7ff0h
        mov ax, 0badh
        out dx, ax
        hlt
f_shr_ah:
        shr ah, 7
        ret
f_vmm:
        mov ax, [si]
        dec eax
        shr ah, 7
        ret
f_check_zf:                             ; AL = 1 if ZF was set on entry
        setz al
        ret
f_shr_al:
        mov al, 1
        shr al, 1
        ret
f_shr_ah1:
        shr ah, 1
        ret
