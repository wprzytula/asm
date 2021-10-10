global  _start

; Conventions:
; I do not comply to ABI norms.
; I do not use r8-r11 between functions - their use is local and temporary only.
; - rbp is set once at the beginning to give comfortable access to polynomial coefficients.
; - r13d stores current occupied length of input buffer.
; - r12d tells if we should load next char (< 0), read next portion (= 0) or move n > 0 bytes
;   to the beginning of the input buffer, meanwhile flushing both buffers.
; After we read the first portion of data from STDIN, then also:
; - edi stores current location in output buffer.
; - esi stores currently processed byte number in input buffer.


; syscalls constants
SYS_READ          equ 0
SYS_WRITE         equ 1
SYS_EXIT          equ 60
STDOUT            equ 1
STDIN             equ 0

BUFF_IN_LEN       equ 1024
BUFF_OUT_LEN      equ 2 * BUFF_IN_LEN ; will suffice to ensure that no output buffer overflow occur

; polynomial computation constants
POLY_CONST        equ 0x80
REMAINDER         equ 0x10FF80

; patterns to assess character length and check for correctness
UTF8_1B_MASK      equ 1000_0000b    ; it is actually MAX_1B + 1, so it is to be tested using jb
UTF8_2B_MASK      equ 1100_0000b
UTF8_3B_MASK      equ 1110_0000b
UTF8_4B_MASK      equ 1111_0000b
UTF8_5B_MASK      equ 11111_000b

UTF8_2B_FLOOR     equ 000000_10b
NEXT_BYTE_FLOOR   equ 1000_0000b
NEXT_BYTE_CEIL    equ 1011_1111b
NEXT_3BYTE_VALID  equ 00_100000b
NEXT_4BYTE_VALID  equ 00_010000b

; patterns for extracting bits from utf-8 to unicode
; they are designed to call 'and' on them with byte to extract
FIRST_OF_2_BYTES  equ 000_11111b
FIRST_OF_3_BYTES  equ 0000_1111b
FIRST_OF_4_BYTES  equ 00000_111b
NEXT_OF_X_BYTES   equ 00_111111b

; coding intervals, used in unicode -> utf-8 conversion
UNICODE_1B_FLOOR  equ 0x0
UNICODE_2B_FLOOR  equ 0x80
UNICODE_3B_FLOOR  equ 0x800
UNICODE_4B_FLOOR  equ 0x10000
UNICODE_4B_CEIL   equ 0x10FFFF

; patterns for coding utf-8 from unicode
NEXT_BYTE_MASK    equ 10_000000b

; patterns for extracting bits from unicode to utf-8
; ALIGN is used as an argument for shl/r
LAST_6_BITS       equ 111111b
NEXT_6_BITS       equ 111111_000000b
NEXT_6_ALIGN      equ 6
YET_NEXT_6_BITS   equ 111111_000000_000000b
YET_NEXT_6_ALIGN  equ 12
INITIAL_5_BITS    equ 11111_000000b
INITIAL_5_ALIGN   equ 6
INITIAL_4_BITS    equ 1111_000000_000000b
INITIAL_4_ALIGN   equ 12
INITIAL_3_BITS    equ 111_000000_000000_000000b
INITIAL_3_ALIGN   equ 18

section .bss
buff_in:        resb BUFF_IN_LEN
buff_out:       resb BUFF_OUT_LEN

section .text

%macro zero 1
    xor %1, %1
%endmacro

%macro is_zero 1
    test %1, %1
%endmacro

; Computes rax modulo REMAINDER.
; Changes: rax, rdx, r11
mod:
    mov     r11, REMAINDER
    zero    edx              ; required for proper div operation
    div     r11
    mov     rax, rdx         ; the remainder was stored in rdx
    ret

; Receives pointer to string in rsi, returns parsed int in rax.
; Changes: rax, rdx, r8, r10, r11, rsi
parse_int:
    zero    eax
    mov     r10d, 10
.loop:
    mul     r10d             ; result stays in rax
    is_zero  edx
    jnz     error            ; too big coefficient - this should, however,
                             ; not happen anytime because of mod, so let's consider this an assert
    call    mod              ; modulo operation

    movzx   edx, BYTE [rsi ] ; fetching next byte
    sub     dl, '0'          ; changing ASCII digit code into corresponding number

    ; character sanity check - asserting it actually represents an ASCII digit
    jb      error            ; wrong character (not a digit)
    mov     r8b, 9
    cmp     r8b, dl
    jb      error            ; wrong character (not a digit)

    add     eax, edx         ; carry impossible due to former multiply by 10

    inc     rsi              ; step next
    cmp     BYTE [rsi], 0
    jnz     .loop
    call    mod              ; modulo operation
    ret

; Parses polynomial coefficients from ASCII form into numbers,
; leaving them in the same place on the stack.
; Changes: rax, rdx, r8, r9, r10, r11, rsi
parse_args:
    mov     eax, [rbp]
    cmp     eax, 1
    jbe     error

    lea     r9, [rbp + 8 + 8]  ; args[1] = first polynomial coefficient
.loop:
    mov     rsi, [r9]       ; address of the next argument
    is_zero  rsi
    jz      .end             ; NULL pointer has been read, no more arguments to parse.

    call    parse_int        ; Newly parsed int arrives in rax.
    mov     [r9], rax       ; The new int replaces string that represented it.

    add     r9, 8           ; Advance to the next argument.
    jmp     .loop
.end:
    ret

; Computes "diakrytynizujący" polynomial for argument given in eax and returns result in eax:
; accepts x in eax and returns w(x - 0x80) + 0x80.
; Changes: rax, rdx, r8, r9, r10, r11, rsi
polynomialize:
    push    rsi
    mov     ecx, [rbp]
    lea     rsi, [rbp + rcx * 8] ; args[n] = last polynomial coefficient (a_n)
    dec     ecx              ; ecx holds number of coefficients
    sub     eax, POLY_CONST
    mov     r10, rax         ; stores polynomial argument for computation
    zero    eax
.next_coefficient:
    mul     r10              ; multiplication by another x
    call    mod              ; we keep result modulo REMAINDER
    add     rax, [rsi]       ; another coefficient added to sum
    call    mod              ; we keep result modulo REMAINDER
    sub     rsi, 8           ; Advance to the next argument.
    loop    .next_coefficient
.end:
    add     eax, POLY_CONST
    pop     rsi
    ret

; Decides how long in bytes the character is and moves on to perform the merge into unicode.
; Assumes we are not at the end of buffer and no character has been started.
; Changes: rax, rdx, r8, r9, r10, r11, rsi
merge_into_unicode:
    zero    eax
    mov     dl, [buff_in + rsi]
    cmp     dl, UTF8_1B_MASK
    jb      merge_1B
    cmp     dl, UTF8_2B_MASK
    jb      error
    cmp     dl, UTF8_3B_MASK
    jb      merge_2B
    cmp     dl, UTF8_4B_MASK
    jb      merge_3B
    cmp     dl, UTF8_5B_MASK
    jb      merge_4B
    jmp     error            ; 5 bytes characters have been removed from utf-8

; Moves content of eax 6 bits to the left and puts 6 lower bits of byte from input buffer
; that is pointed by esi into a newly created place.
; Changes: rax, rdx, rsi
append_next_byte:
    inc     esi              ; advance to the next byte
    shl     eax, 6           ; higher bytes moved left to make place for lower bytes
    mov     dl, [buff_in + esi] ; fetch next byte from input buffer
    cmp     dl, NEXT_BYTE_FLOOR
    jb      error            ; invalid second byte
    cmp     dl, NEXT_BYTE_CEIL
    ja      error            ; invalid second byte
    and     dl, NEXT_OF_X_BYTES
    add     al, dl           ; append coding bits from next utf-8 byte to unicode
    ret

; Merges 1-byte long utf-8 character into unicode.
merge_1B:    ; first byte already in dl
    mov     al, dl
    jmp     process_ascii

; Merges 2-byte long utf-8 character into unicode.
merge_2B:    ; first byte already in dl
    mov     eax, 1
    add     eax, esi
    cmp     eax, r13d        ; check if current character finishes by the end of input buffer
    jae     .flush_needed    ; if not, flush buffers with moving unended character to the beginning

    and     dl, FIRST_OF_2_BYTES
    cmp     dl, UTF8_2B_FLOOR
    jb      error            ; "shortest representation only" rule violation
    movzx   eax, dl

    call    append_next_byte

    jmp     process_char

; Action performed instead of merging when current character is not fully stored in input buffer.
.flush_needed:
    mov     r12d, 1          ; the only possible case to be moved
    call    flush_buffers
    call    next_portion
    ret

; Merges 3-byte long utf-8 character into unicode.
merge_3B:    ; first byte already in dl
    mov     eax, 2
    add     eax, esi
    cmp     eax, r13d        ; check if current character finishes by the end of input buffer
    jae     .flush_needed    ; if not, flush buffers with moving unended character to the beg

    ; "shortest representation only" rule validation
    ; r8b acts as boolean: 0 signifies no validation, 1 signifies validation.
    zero    r8b
    and     dl, FIRST_OF_3_BYTES
    is_zero dl
    jz      .possibly_invalid_1st_byte
    mov     r8b, 1           ; validate
.possibly_invalid_1st_byte:  ; label used only to omit validation
    movzx   eax, dl

    call    append_next_byte

    cmp     dl, NEXT_3BYTE_VALID
    jb      .possibly_invalid_2nd_byte
    mov     r8b, 1           ; validate
.possibly_invalid_2nd_byte:  ; label used only to omit validation
    test    r8b, r8b
    jz      error            ; "shortest representation only" rule violation

    call    append_next_byte

    jmp     process_char

; Action performed instead of merging when current character is not fully stored in input buffer.
.flush_needed:
    mov     r12d, r13d
    sub     r12d, esi        ; this results in amount of bytes to be moved
    call    flush_buffers
    call    next_portion
    ret

; Merges 4-byte long utf-8 character into unicode.
merge_4B:    ; proper byte already in dl
    mov     eax, 3
    add     eax, esi
    cmp     eax, r13d        ; check if current character finishes by the end of input buffer
    jae     .flush_needed    ; if not, flush buffers with moving unended character to the beg

    ; "shortest representation only" rule validation
    ; r8b acts as boolean: 0 signifies no validation, 1 signifies validation.
    zero    r8b
    and     dl, FIRST_OF_4_BYTES
    is_zero dl
    jz      .possibly_invalid_1st_byte
    mov     r8b, 1           ; validate
.possibly_invalid_1st_byte:
    movzx   eax, dl

    call    append_next_byte

    cmp     dl, NEXT_4BYTE_VALID
    jb      .possibly_invalid_2nd_byte
    mov     r8b, 1           ; validate
.possibly_invalid_2nd_byte:
    test    r8b, r8b
    jz      error            ; "shortest representation only" rule violation

    call    append_next_byte

    call    append_next_byte

    cmp     eax, UNICODE_4B_CEIL
    ja      error            ; character nonexistent in utf-8
    jmp     process_char

; Action performed instead of merging when current character is not fully stored in input buffer.
.flush_needed:
    mov     r12d, r13d
    sub     r12d, esi        ; this results in amount of bytes to be moved
    call    flush_buffers
    call    next_portion
    ret

; Splits polynomialized unicode into valid utf-8 bytes and puts them into output buffer.
; The length of output buffer prevents the possibility of buffer overflow.
; Changes: rax, rdx, rsi, rdi, r8, r9, r10, r11, r12.
split_into_utf:
    mov     r10d, eax             ; full new unicode stored in r10d
    mov     r9d, r10d             ; r9d serves as temporary storage for certain bits of unicode
    cmp     r10d, UNICODE_2B_FLOOR
    jb     .split_into_1B
    cmp     r10d, UNICODE_3B_FLOOR
    jb      .split_into_2B
    cmp     r10d, UNICODE_4B_FLOOR
    jb      .split_into_3B
    cmp     r10d, UNICODE_4B_CEIL
    jbe     .split_into_4B
    jmp     error                 ; character outside utf-8 coding scope

.split_into_1B:
    mov     [buff_out + edi], al  ; we put ASCII code, which is valid UTF-8 code, into proper place
    inc     edi
    ret

.split_into_2B:
    mov     al, UTF8_2B_MASK      ; first byte code mask put in al
    and     r9d, INITIAL_5_BITS
    shr     r9d, INITIAL_5_ALIGN
    add     al, r9b               ; al contains 1st byte of new char, so we put it into output buff
    mov     [buff_out + edi], al
    inc     edi
    jmp     .2B_cont

.split_into_3B:
    mov     al, UTF8_3B_MASK      ; first byte code mask put in al
    and     r9d, INITIAL_4_BITS
    shr     r9d, INITIAL_4_ALIGN
    add     al, r9b               ; al contains 1st byte of new char, so we put it into output buff
    mov     [buff_out + edi], al
    inc     edi
    jmp     .3B_cont

.split_into_4B:
    mov     al, UTF8_4B_MASK      ; first byte code mask put in al
    and     r9d, INITIAL_3_BITS
    shr     r9d, INITIAL_3_ALIGN
    add     al, r9b               ; al contains 1st byte of new char, so we put it into output buff
    mov     [buff_out + edi], al
    inc     edi
                                  ; falling through
.4B_cont:
    mov     al, NEXT_BYTE_MASK    ; next byte code mask put in al
    mov     r9d, r10d             ; r9d acts as temporary storage for certain bits of unicode
    and     r9d, YET_NEXT_6_BITS
    shr     r9d, YET_NEXT_6_ALIGN
    add     al, r9b               ; al contains next byte of new char, so we put it into output buff
    mov     [buff_out + edi], al
    inc     edi
.3B_cont:
    mov     al, NEXT_BYTE_MASK    ; next byte code mask put in al
    mov     r9d, r10d             ; r9d acts as temporary storage for certain bits of unicode
    and     r9d, NEXT_6_BITS
    shr     r9d, NEXT_6_ALIGN
    add     al, r9b               ; al contains next byte of new char, so we put it into output buff
    mov     [buff_out + edi], al
    inc     edi
.2B_cont:
    mov     al, NEXT_BYTE_MASK   ; last byte code mask put in al
    mov     r9d, r10d            ; r9d acts as temporary storage for certain bits of unicode
    and     r9d, LAST_6_BITS
    add     al, r9b              ; al contains last byte of new char, so we put it into output buff
    mov     [buff_out + edi], al
    inc     edi
    ret

; Performs alternation on unicode already loaded into eax and goes on to split it back into utf-8.
; Changes: rax, rdx, rsi, rdi, r8, r9, r10, r11, r12.
process_char:
    call    polynomialize
    cmp     eax, UNICODE_4B_CEIL
    ja      error            ; character nonexistent in utf-8
process_ascii:               ; entry point for 1-byte long characters that are not to be altered
    call    split_into_utf

    zero    r12d
    inc     esi              ; advance to the next character in input buffer

    cmp     esi, r13d        ; did we finish processing the input buffer?
    jz      .finish          ; yes, we did
.put_negative:
    mov     r12d, -1         ; no, then continue
.finish:
    ret

; Flushes output buffer.
; Changes: rax, rcx, rdx, r11, rdi
flush_buff_out:
    push    rsi
    mov     eax, SYS_WRITE
    mov     edx, edi
    mov     edi, STDOUT
    mov     rsi, buff_out
    syscall
    cmp     rax, 0
    jl      error           ; error in write
    pop     rsi
    zero    edi             ; as output buffer was flushed, we return to its beginning
    ret

; Flushes both input and output buffers.
; Changes: rax, rcx, rdx, r8, r9, r11, rdi
flush_buffers:  ; will store initial bytes of the possible unended character in r8 and r9
    call    flush_buff_out
    ; If some character is splitted between this and next portion in input buffer, then we
    ; move it in order to preserve it as a whole for the next input buffer iteration.
    cmp     r12d, 3
    je      .move_3B
    cmp     r12d, 2
    je      .move_2B
    cmp     r12d, 1
    je      .move_1B
    ret                         ; no move

; Moves 1B from the end to the beginning of input buffer.
.move_1B:
    mov     r8b, [buff_in + rsi]
    mov     BYTE [buff_in], r8b
    ret

; Moves 2B from the end to the beginning of input buffer.
.move_2B:
    mov     r8w, [buff_in + rsi]
    mov     WORD [buff_in], r8w
    ret

; Moves 3B from the end to the beginning of input buffer.
.move_3B:
    mov     r8w, [buff_in + rsi]
    mov     r9b, [buff_in + rsi + 2]
    mov     WORD [buff_in], r8w
    mov     BYTE [buff_in + 2], r9b
    ret

; Reads at most [BUFF_IN_LEN - MOVED_LEN] into input buffer, leaving first MOVED_LEN cells untouched.
; MOVED_LEN is initially stored in r12d, and it must be hold that r12d >= 0.
; Conventions here:
; - r13d stores current occupied length of input buffer,
; - r12d tells if we should load next char (< 0), read next portion (= 0) or move n > 0 bytes
;   to the beginning of the input buffer, meanwhile flushing both buffers,
; - edi stores current location in output buffer,
; - esi stores currently processed byte number in input buffer.
; Possibly leads to program end.
; Changes: rax, rcx, rdx, r11, r12, r13, rsi, rdi
next_portion:
    mov     r13d, r12d      ; backup number of already stored elements in r13d
    mov     eax, SYS_READ
    mov     edi, STDIN
    lea     rsi, [buff_in + r13d]
    mov     edx, BUFF_IN_LEN
    sub     edx, r12d
    syscall                 ; new portion of data arrives in buffer
                            ; and amount of bytes read is in rax
    cmp     rax, 0
    jl      error           ; error in read
    jz      finished_read

    add     r13d, eax       ; saving read data length into r13d
    mov     r12d, -1        ;
    zero    esi
    zero    edi             ; we start from the beginning of both buffers
    ret

; We jump here after all read bytes had been processed and EOF was encountered.
finished_read:
    is_zero r12d            ; if there are any unended characters, we consider it an error
    jnz     error
    jmp     success

_start:
    mov     rbp, rsp        ; since now, rbp points at argc
    call    parse_args

    zero    esi
    zero    r12d
    call    next_portion
                            ; falling through

; Main loop of the program, used to fetch one character from the input buffer, process it
; and put back into output buffer (flushing both if necessary).
; Here we encounter an endless loop - it is only possible to end program execution
; using SYS_EXIT from within.
character_loop:
    call    merge_into_unicode   ; processes one character
    cmp     r12d, 0              ; what to do next?
    jl      character_loop       ; if we didn't reach end of buffer, continue parsing characters
    call    flush_buffers        ; else flush buffers
    call    next_portion         ; and read next portion to input buffer
    jmp     character_loop       ; and then try to process another character

; Ending phase
success:
    call    flush_buff_out  ; print characters remaining in output buffer
    zero    edi
    jmp     exit
error:
    call    flush_buff_out  ; print characters remaining in output buffer
    mov     edi, 1
exit:
    mov     eax, SYS_EXIT
    syscall
