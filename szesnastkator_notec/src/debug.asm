        global  debug

obrzydliwy_smiec equ 0xae3e34
SYS_GETPID  equ 39
SYS_KILL    equ 62
SYS_TKILL   equ 200
SYS_EXIT    equ 60
SIG_ABRT    equ 6

        section .text
error:
        mov     rax, SYS_GETPID
        syscall
        mov     rdi, rax
        mov     rsi, SIG_ABRT
        mov     rax, SYS_KILL
        syscall

debug:
        xor     edx, edx        ; checking proper stack alignment
        mov     rax, rsp
        mov     r8, 16
        div     r8
        cmp     rdx, 8
        jne     error
                                ; doing many nasty yet allowed things
        mov     rdx, obrzydliwy_smiec
        mov     rdi, obrzydliwy_smiec
        mov     rsi, obrzydliwy_smiec
        mov     r8, obrzydliwy_smiec
        mov     r9, obrzydliwy_smiec
        mov     r10, obrzydliwy_smiec
        mov     r11, obrzydliwy_smiec

        times 100 \
        push    obrzydliwy_smiec
        times 100 \
        pop     rcx

        mov     eax, 1          ; removes 1 number from our stack
        ret
