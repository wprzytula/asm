        default rel
        global  notec
        extern  debug

; Stack shall be organised in the following way: (lower line = lower address)
; return address - [rbp] [old rsp]
; rbp backup       [rbp - 8]
; r12 backup       [rbp - 16]
; r13 backup       [rbp - 24]
; <here number stack begins>
; numbers...       [rbp - 32]
; numbers...
; top number       [rsp]

        align 4
        section .bss
Pref:   resd    N                   ; array of preferences: if notec n want to perform
                                    ; an exchange with notec m, then in Pref[n] there is
                                    ; m + 1; 0 signifies no willingness to exchange
Bufex:  resq    N                   ; exchange buffer; notec n puts its data
                                    ; to be exchanged into Bufex[n].
        section .text

%macro  spin 2                      ; spin(location, until_what)
%%loop:
        mov     eax, %1
        cmp     eax, %2
        jne     %%loop
%endmacro

; Receives n in edi and calc in rsi.
; Performs actions resulting from read character.
; When NULL is reached, returns top of the stack in rax.
notec:
        mov     [rsp - 8], rbp      ; backup initial rbp value on stack
        mov     rbp, rsp
        mov     [rbp - 16], r12     ; backup initial r12 value on stack
        mov     [rbp - 24], r13     ; backup initial r13 value on stack
        sub     rsp, 24             ; update stack top
        mov     r12d, edi           ; store n in r12
        mov     r13, rsi            ; store current calc position in r13
        jmp     interpret

next_char:
        inc     r13
interpret:
        xor     eax, eax
        movzx   rdx, BYTE [r13]
        cmp     dl, 'f'
        ja      .above_f
        cmp     dl, 'a'
        jae     parse_int.parse_a_f
        cmp     dl, 'F'
        ja      .above_F
        cmp     dl, 'A'
        jae     parse_int.parse_A_F
        cmp     dl, '9'
        ja      next_char           ; '='
        cmp     dl, '0'
        jae     parse_int.parse_0_9
        cmp     dl, '+'
        ja      .neg                ; '-'
        je      .add                ; '+'
        cmp     dl, '&'
        ja      .mul                ; '*'
        je      .and                ; '&'
                                    ; else we must have read NULL byte
        mov     rax, [rsp]          ; so place top of the stack in rax
        mov     rsp, rbp            ; update stack top
        mov     r12, [rbp - 16]     ; restore initial r12 value from stack
        mov     r13, [rbp - 24]     ; restore initial r13
        mov     rbp, [rsp - 8]      ; restore initial rbp
        ret

.above_f:
        cmp     dl, 'n'
        jb      debug_call          ; 'g'
        je      .n                  ; 'n'
        cmp     dl, '~'
        je      .not                ; '~'
        jmp     .or                 ; '|'

.above_F:
        cmp     dl, 'W'
        jb      .N                  ; 'N'
        je      .W                  ; 'W'
        cmp     dl, 'Y'
        jb      .X                  ; 'X'
        je      .Y                  ; 'Y'
        cmp     dl, '^'
        je     .xor                 ; '^'
                                    ; else fall through to the only possible 'Z'
.Z:                                 ; erasure of the top number
        add     rsp, 8
        jmp     next_char
.Y:                                 ; duplication of the top number
        mov     rdx, [rsp]
        push    rdx
        jmp     next_char
.X:                                 ; exchange of two top numbers
        mov     rdx, [rsp + 8]
        xchg    QWORD [rsp], rdx
        mov     [rsp + 8], rdx
        jmp     next_char
.N:                                 ; append of number of all Notecie
        push    N
        jmp     next_char
.n:                                 ; append of this Notec number
        push    r12
        jmp     next_char
.not:                               ; bitwise negation of the top number
        not     QWORD [rsp]
        jmp     next_char
.neg:                               ; arithmetic negation of the top number
        neg     QWORD [rsp]
        jmp     next_char

; The following two-argument operations on two top numbers store their result
; in the former place of the operand stored deeper in the stack.
.and:                               ; bitwise AND
        pop     rdx
        and     [rsp], rdx
        jmp     next_char
.or:                                ; bitwise OR
        pop     rdx
        or      [rsp], rdx
        jmp     next_char
.xor:                               ; bitwise OR
        pop     rdx
        xor     [rsp], rdx
        jmp     next_char
.add:                               ; arithmetic addition
        pop     rdx
        add     [rsp], rdx
        jmp     next_char
.mul:                               ; arithmetic multiplication
        pop     rax
        xor     edx, edx
        mul     QWORD [rsp]
        mov     [rsp], rax
        jmp     next_char

.W:                                 ; concurrent exchange between two Notecie
        pop     r11                 ; number of Notec to exchange with (m)
        mov     rdx, [rsp]          ; item to exchange with Notec m

        lea     r10, [Bufex]         ; r10 points to Bufex

        lea     rdi, [Pref]          ; rdi points to Pref
        lea     rsi, [Pref]          ; rsi as well
        lea     rdi, [rdi + r11 * 4] ; rdi points to Pref[m]
        lea     rsi, [rsi + r12 * 4] ; rsi points to Pref[n]

        spin    [rsi], 0            ; spin locks until Pref[n] equals 0
                                    ; this is necessary to prevent races
        mov     [r10 + r12 * 8], rdx ; put item to exchange in Bufex[n]

        inc     r11d
        mov     [rsi], r11d         ; Pref[n] := m + 1
        dec     r11d                ; claiming willingness to exchange with m

        inc     r12d
        spin    [rdi], r12d         ; spin locks until Pref[m] equals n + 1
        dec     r12d

        mov     rdx, [r10 + r11 * 8] ; take item from Bufex[m]
        mov     [rsp], rdx          ; and put it on top of the stack

        mov     DWORD [rdi], 0      ; signal m that exchange has been finalized

        jmp     next_char           ; finish exchange protocol

; Ensures debug function call complies with ABI, wrapping the call with
; necessary preparations and post run cleaning
debug_call:
        mov     edi, r12d           ; n as first arg
        mov     rsi, rsp            ; stack pointer as second arg
        test    spl, 8              ; checks if stack is aligned properly
        jnz     .with_align
.no_align:
        call    debug
        jmp     .finish
.with_align:                        ; ensures ABI-compliant stack alignment
        sub     rsp, 8
        call    debug
        add     rsp, 8
.finish:
        sal     rax, 3              ; multiply by 8 in order to convert bytes
                                    ; to stack portions
        add     rsp, rax            ; adjust stack top according
                                    ; to value returned by debug
        jmp     next_char

; Receives current position of calc in rsi.
; Assumes rsi points at the first digit of the parsed number.
; Puts parsed int onto top of the Notec stack.
parse_int:
        movzx   rdx, BYTE [r13]
        cmp     dl, 'f'
        ja      .finish
        cmp     dl, 'a'
        jae     .parse_a_f
        cmp     dl, 'F'
        ja      .finish
        cmp     dl, 'A'
        jae     .parse_A_F
        cmp     dl, '9'
        ja      .finish
        cmp     dl, '0'
        jae     .parse_0_9
.finish:
        push    rax
        jmp     interpret

.parse_0_9:
        sub     dl, '0'
        jmp     .insert

.parse_A_F:
        sub     dl, 'A' - 10
        jmp     .insert

.parse_a_f:
        sub     dl, 'a' - 10
        jmp     .insert

.insert:
        shl     rax, 4          ; multiply number on top of the stack by 16
        add     rax, rdx        ; append next digit to currently inserted number
        inc     r13             ; advance to next character
        jmp     parse_int
