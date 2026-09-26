; SPDX-License-Identifier: GPL-3.0-or-later
; Self-authored PC-98 DOS XMS benchmark. Run only on a disposable fixture.
; BIOS INT 1Ch/AH=00 reads the hardware RTC, which keeps running while XMS
; disables interrupts. DOS/PIT tick counts are deliberately not used as time.
; Whole RTC seconds have roughly +/-1 second endpoint uncertainty. Zero means
; below this resolution, not zero cost. Progress output is included in timing.
; Counts are bounded; RTC budgets are checked BETWEEN calls. A stuck XMS/BIOS
; call cannot be interrupted safely by this program and needs host supervision.
bits 16
cpu 386
org 100h

%define GROW_STEPS 64
%define FINAL_KB (19 + 16*GROW_STEPS)
%define COPY_PASSES 8
%define CHUNK 16384
%define PHASE_LIMIT 120

start:
    push cs
    pop ds
    push cs
    pop es
    cld
    mov word [log_pos],log_buffer
    mov dx,critical_error
    mov ax,2524h
    int 21h
    ; Create-new: never truncate an earlier measurement.
    mov dx,log_name
    xor cx,cx
    mov ah,5bh
    int 21h
    jc cannot_create
    mov [log_handle],ax
    mov si,title
    call puts
    mov ax,4300h
    int 2fh
    cmp al,80h
    jne no_xms
    mov ax,4310h
    int 2fh
    mov [entry],bx
    mov [entry+2],es

    ; Require a valid, advancing RTC before reporting any timing.
    call read_rtc
    mov [clock_first],eax
    mov dword [polls],131072
.clock_poll:
    call read_rtc
    cmp eax,[clock_first]
    jne .clock_ready
    dec dword [polls]
    jnz .clock_poll
    jmp bad_clock
.clock_ready:
    mov si,rtc_ready
    call puts
    call decimal
    call newline

    mov si,phase_alloc_small
    call puts
    call timer_start
    mov dx,FINAL_KB
    mov ah,9
    call xms_checked
    mov [handle1],dx
    call timer_report
    call free1

    mov si,phase_alloc_large
    call puts
    call timer_start
    mov dx,8192
    mov ah,9
    call xms_checked
    mov [handle1],dx
    call timer_report
    call free1

    ; Seed a distinct 16KB pattern before growth and check it after growth.
    mov dx,19
    mov ah,9
    call xms_checked
    mov [handle1],dx
    mov word [chunk_index],0
    call make_pattern
    call upload_chunk
    mov si,phase_grow
    call puts
    mov word [wanted],35
    mov word [completed],0
    call timer_start
.grow:
    mov dx,[handle1]
    mov bx,[wanted]
    mov ah,0fh
    call xms_checked
    inc word [completed]
    call progress_and_budget
    add word [wanted],16
    cmp word [completed],GROW_STEPS
    jb .grow
    call timer_report
    ; Verification is outside the measured growth interval.
    mov ax,[handle1]
    mov [read_handle],ax
    call verify_chunk
    call free1

    mov si,copy_prepare
    call puts
    mov dx,1024
    mov ah,9
    call xms_checked
    mov [handle1],dx
    mov dx,1024
    mov ah,9
    call xms_checked
    mov [handle2],dx
    mov word [chunk_index],0
    call timer_start
.fill:
    call make_pattern
    call upload_chunk
    call budget
    inc word [chunk_index]
    cmp word [chunk_index],64
    jb .fill
    mov si,phase_copy
    call puts
    mov dword [transfer],1048576
    mov ax,[handle1]
    mov [transfer+4],ax
    mov dword [transfer+6],0
    mov ax,[handle2]
    mov [transfer+10],ax
    mov dword [transfer+12],0
    mov word [completed],0
    call timer_start
.copy:
    mov si,transfer
    mov ah,0bh
    call xms_checked
    inc word [completed]
    call progress_and_budget
    cmp word [completed],COPY_PASSES
    jb .copy
    call timer_report

    ; Read and compare EVERY byte of the final 1MB destination, with different
    ; patterns in each 16KB chunk. This is not part of throughput timing.
    mov si,verify_text
    call puts
    mov ax,[handle2]
    mov [read_handle],ax
    mov word [chunk_index],0
    call timer_start
.verify:
    call make_pattern
    call verify_chunk
    call budget
    inc word [chunk_index]
    cmp word [chunk_index],64
    jb .verify
    call free1
    mov dx,[handle2]
    mov ah,0ah
    call xms_checked
    mov word [handle2],0
    mov si,passed
    call puts
    jmp finish

timer_start:
    call read_rtc
    mov [phase_start],eax
    ret
elapsed:
    call read_rtc
    sub eax,[phase_start]
    jnc .done
    add eax,86400                 ; midnight rollover, not signed wrap
.done:
    ret
budget:
    call elapsed
    cmp eax,PHASE_LIMIT
    jae too_slow
    ret
progress_and_budget:
    call budget
    test word [completed],15
    jnz .done
    mov al,'.'
    call putchar
.done:
    ret
timer_report:
    call elapsed
    cmp eax,PHASE_LIMIT
    jae too_slow
    push eax
    mov si,seconds_text
    call puts
    pop eax
    call decimal
    call newline
    ret

; EAX = seconds since midnight, from the latched hardware RTC calendar.
; Preserve all other general registers and caller segment registers.
read_rtc:
    push ebx
    push ecx
    push edx
    push esi
    push edi
    push ebp
    push ds
    push es
    push cs
    pop es
    mov bx,rtc_buffer
    xor ah,ah
    int 1ch
    pop es
    pop ds
    mov al,[rtc_buffer+3]
    call bcd
    cmp eax,23
    ja bad_clock
    imul eax,eax,3600
    mov ebx,eax
    mov al,[rtc_buffer+4]
    call bcd
    cmp eax,59
    ja bad_clock
    imul eax,eax,60
    add ebx,eax
    mov al,[rtc_buffer+5]
    call bcd
    cmp eax,59
    ja bad_clock
    add eax,ebx
    pop ebp
    pop edi
    pop esi
    pop edx
    pop ecx
    pop ebx
    ret
bcd:
    movzx eax,al
    mov edx,eax
    and eax,15
    cmp eax,9
    ja bad_clock
    shr edx,4
    cmp edx,9
    ja bad_clock
    imul edx,edx,10
    add eax,edx
    ret

make_pattern:
    pushad
    push es
    push cs
    pop es
    cld
    mov di,source
    mov bx,[chunk_index]
    shl bx,9
    xor cx,cx
.word:
    mov ax,cx
    xor ax,bx
    xor ax,55aah
    stosw
    inc cx
    cmp cx,CHUNK/2
    jb .word
    pop es
    popad
    ret
upload_chunk:
    mov dword [transfer],CHUNK
    mov word [transfer+4],0
    mov word [transfer+6],source
    mov ax,cs
    mov [transfer+8],ax
    mov ax,[handle1]
    mov [transfer+10],ax
    movzx eax,word [chunk_index]
    shl eax,14
    mov [transfer+12],eax
    mov si,transfer
    mov ah,0bh
    call xms_checked
    ret
verify_chunk:
    mov dword [transfer],CHUNK
    mov ax,[read_handle]
    mov [transfer+4],ax
    movzx eax,word [chunk_index]
    shl eax,14
    mov [transfer+6],eax
    mov word [transfer+10],0
    mov word [transfer+12],destination
    mov ax,cs
    mov [transfer+14],ax
    mov si,transfer
    mov ah,0bh
    call xms_checked
    push cs
    pop es
    cld
    mov si,source
    mov di,destination
    mov cx,CHUNK/2
    repe cmpsw
    jne data_failed
    ret

free1:
    mov dx,[handle1]
    mov ah,0ah
    call xms_checked
    mov word [handle1],0
    ret
xms_checked:
    call xms
    cmp ax,1
    jne xms_failed
    ret
xms:
    mov [last_function],ah
    pushfd
    cli
    call far [cs:entry]
    popfd
    ret

no_xms:
    mov si,no_xms_text
    jmp fail
bad_clock:
    mov si,bad_clock_text
    jmp fail
too_slow:
    mov si,timeout_text
    jmp fail
data_failed:
    mov si,data_text
    jmp fail
xms_failed:
    mov [error_ax],ax
    mov [error_bl],bl
    mov si,xms_text
    call puts
    movzx eax,byte [last_function]
    call decimal
    mov si,ax_text
    call puts
    movzx eax,word [error_ax]
    call decimal
    mov si,bl_text
    call puts
    movzx eax,byte [error_bl]
    call decimal
    mov si,empty
fail:
    call puts
    call newline
    mov byte [exit_status],1
    ; Best effort cleanup, without recursive error handling.
    mov dx,[handle1]
    test dx,dx
    jz .second
    mov ah,0ah
    call xms
.second:
    mov dx,[handle2]
    test dx,dx
    jz finish
    mov ah,0ah
    call xms
finish:
    mov bx,[log_handle]
    mov dx,log_buffer
    mov cx,[log_pos]
    sub cx,dx
    mov [write_length],cx
    mov ah,40h
    int 21h
    jc save_failed
    cmp ax,[write_length]
    jne save_failed
    mov bx,[log_handle]
    mov ah,3eh
    int 21h
    jc save_failed
    mov si,saved_text
    call puts
.exit:
    mov al,[exit_status]
    mov ah,4ch
    int 21h
cannot_create:
    mov si,create_text
    call puts
    mov ax,4c02h
    int 21h
save_failed:
    mov bx,[log_handle]
    mov ah,3eh
    int 21h
    mov si,save_text
    call puts
    mov ax,4c02h
    int 21h
critical_error:
    mov al,3
    iret
newline:
    mov si,newline_text
    jmp puts
decimal:
    pushad
    xor cx,cx
    mov ebx,10
.digit:
    xor edx,edx
    div ebx
    push dx
    inc cx
    test eax,eax
    jnz .digit
.print:
    pop ax
    add al,'0'
    call putchar
    loop .print
    popad
    ret
puts:
    pushad
    cld
.next:
    lodsb
    test al,al
    jz .done
    call putchar
    jmp .next
.done:
    popad
    ret
putchar:
    pushad
    mov di,[log_pos]
    cmp di,log_buffer+2048
    jae .screen
    mov [di],al
    inc word [log_pos]
.screen:
    mov dl,al
    mov ah,2
    int 21h
    popad
    ret

title: db 'Zet98 XMS benchmark R1; XMS caller IF=0',13,10
    db 'RTC whole seconds; 0 is below resolution, NOT zero cost.',13,10
    db '120s budget checked BETWEEN calls. Progress output included.',13,10,0
rtc_ready: db 'RTC advances; start seconds-of-day=',0
phase_alloc_small: db 'ALLOC single 1043KB / 1 request',0
phase_alloc_large: db 'ALLOC single 8192KB / 1 request',0
phase_grow: db 'GROW 19->1043KB / 64 resizes of 16KB',0
copy_prepare: db 'Prepare two 1MB blocks, fill source outside timed copy.',13,10,0
phase_copy: db 'COPY XMS->XMS / 8 x 1048576 bytes',0
verify_text: db 'Verify all 1048576 destination bytes (outside timing).',13,10,0
seconds_text: db ' RTC_SECONDS=',0
passed: db 'PASS: growth data and complete 1MB copied data match.',13,10,0
no_xms_text: db 'FAIL: XMS driver absent.',0
bad_clock_text: db 'FAIL: invalid or non-advancing RTC; timings unusable.',0
timeout_text: db 'FAIL: phase exceeded 120 RTC seconds; stopped between calls.',0
data_text: db 'FAIL: XMS data differs.',0
xms_text: db 'FAIL: XMS function=',0
ax_text: db ' AX=',0
bl_text: db ' BL=',0
saved_text: db 'Saved new XMSBENCH.TXT; benchmark complete.',13,10,0
create_text: db 'ERROR: cannot create NEW XMSBENCH.TXT; no tests run.',13,10,0
save_text: db 'ERROR saving XMSBENCH.TXT; use console result.',13,10,0
newline_text: db 13,10,0
empty: db 0
log_name: db 'XMSBENCH.TXT',0
entry: dd 0
handle1: dw 0
handle2: dw 0
read_handle: dw 0
log_handle: dw 0
log_pos: dw 0
write_length: dw 0
exit_status: db 0
last_function: db 0
error_ax: dw 0
error_bl: db 0
phase_start: dd 0
clock_first: dd 0
polls: dd 0
wanted: dw 0
completed: dw 0
chunk_index: dw 0
rtc_buffer: times 6 db 0ffh
transfer: times 16 db 0
log_buffer: times 2048 db 0
source: times CHUNK db 0
destination: times CHUNK db 0
; Leave at least 8KB of the COM segment for the DOS stack/BIOS/XMS driver.
times 0 * (1 / (($ - $$) < 56000)) db 0
