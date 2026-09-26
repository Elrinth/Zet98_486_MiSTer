; SPDX-License-Identifier: GPL-3.0-or-later
; Isolate the timed benchmark's upper-memory ALU and DOS-clock phases.
; Disposable DOS shell only; no memory managers. Never overwrites a result.
bits 16
cpu 8086
org 100h
start:
    cli
    mov ax,cs
    mov ss,ax
    mov sp,0fffeh
    mov ds,ax
    mov es,ax
    cld
    sti
    mov dx,critical_error
    mov ax,2524h
    int 21h
    mov dx,banner
    call puts
    mov ax,cs
    cmp ax,6000h
    ja failed
    cmp word [2],9100h
    jb failed
    mov ax,9000h
    mov es,ax
    mov si,upper_kernel
    xor di,di
    mov cx,upper_end-upper_kernel
    rep movsb
    push cs
    pop es

    mov byte [stage],'1'
    mov dx,phase1
    call puts
    mov word [blocks],8
    cli
.disabled:
    call 9000h:0
    or bx,bx
    jnz failed
    or si,si
    jnz failed
    dec word [blocks]
    jnz .disabled
    sti
    mov byte [stage],'2'
    mov dx,phase2
    call puts
    mov word [blocks],8
.enabled:
    call 9000h:0
    or bx,bx
    jnz failed
    or si,si
    jnz failed
    dec word [blocks]
    jnz .enabled

    mov byte [stage],'3'
    mov dx,phase3
    call puts
    mov word [blocks],16
.clock:
    mov ah,2ch
    int 21h
    cmp ch,24
    jae failed
    cmp cl,60
    jae failed
    cmp dh,60
    jae failed
    cmp dl,100
    jae failed
    dec word [blocks]
    jnz .clock
    mov byte [stage],'4'
    mov dx,phase4
    call puts
    mov ah,2ch
    int 21h
    mov [clock_cx],cx
    mov [clock_dx],dx
    mov byte [poll_groups],8
    mov word [poll_count],0
.tick:
    mov ah,2ch
    int 21h
    cmp ch,24
    jae failed
    cmp cl,60
    jae failed
    cmp dh,60
    jae failed
    cmp dl,100
    jae failed
    cmp cx,[clock_cx]
    jne .advanced
    cmp dx,[clock_dx]
    jne .advanced
    dec word [poll_count]
    jnz .tick
    dec byte [poll_groups]
    jnz .tick
    jmp failed
.advanced:
    mov word [status],'PA'
    mov word [status+2],'SS'
    jmp finish
failed:
    sti
finish:
    cld
    mov dx,report
    call puts
    mov dx,filename
    xor cx,cx
    mov ax,5b00h
    int 21h
    jc save_failed
    mov bx,ax
    mov dx,report
    mov cx,report_end-report
    mov ah,40h
    int 21h
    jc close_failed
    cmp ax,report_end-report
    jne close_failed
    mov ah,3eh
    int 21h
    jc save_failed
    mov ah,0dh
    int 21h
    jmp park
close_failed:
    mov ah,3eh
    int 21h
save_failed:
    mov dx,save_error
    call puts
park:
    sti
park_hlt:
    hlt
    jmp park
critical_error:
    mov al,3
    iret
puts:
    mov ah,9
    int 21h
    ret

upper_kernel:
    xor bx,bx
    xor si,si
    mov bp,32
.outer:
    mov cx,4096
.alu:
    add bx,3
    inc si
    dec cx
    jnz .alu
    dec bp
    jnz .outer
upper_return:
    retf
upper_end:

banner: db 13,10,'Z98 upper-memory / clock isolation probe',13,10,'$'
phase1: db '1: 90000h arithmetic, interrupts disabled',13,10,'$'
phase2: db '2: 90000h arithmetic, interrupts enabled',13,10,'$'
phase3: db '3: DOS clock calls',13,10,'$'
phase4: db '4: Bounded wait for DOS clock transition',13,10,'$'
report: db 'Z98 KERNEL: '
status: db 'FAIL stage='
stage: db '0',13,10
report_end: db '$'
filename: db 'A:\Z98KERN.TXT',0
save_error: db 'Result save failed.',13,10,'$'
blocks: dw 0
clock_cx: dw 0
clock_dx: dw 0
poll_count: dw 0
poll_groups: db 0
; Private test-harness offsets, no runtime use.
dw upper_kernel-$$,upper_return-upper_kernel,park_hlt-$$
