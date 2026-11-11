; Exact prospective CRC from the verified before CRC and the eight-byte XOR difference.
; CRC(old) XOR CRC(new) = CRC(init=0, no final xor, old XOR new).
; Leading zero bytes leave the zero remainder unchanged; trailing zeros use precomputed
; GF(2) matrices, one for each power-of-two byte count. R2/R3 are preserved.
patch_result_crc:
        CALLA   UC, table_info
        CALLA   UC, ram_info
        EXTP    #10h, #1
        MOV     R4, W_PATCH+10
        ROL     R4, #8
        ADD     R13, R4
        SUB     R10, R4
        SUB     R10, #8
        MOV     R15, R10              ; unchanged suffix length
        MOV     R12, #(W_PATCH+12)
        MOV     R10, #8
        MOV     R8, #0
        MOV     R9, #0
delta_byte:
        EXTP    R14, #1
        MOVB    RL4, [R13]
        MOVBZ   R4, RL4
        EXTP    #10h, #1
        MOVB    RL5, [R12]
        MOVBZ   R5, RL5
        XOR     R4, R5
        XOR     R8, R4
        MOV     R5, R8
        AND     R5, #0FFh
        SHL     R5, #2
        ADD     R5, #(crc_table & 0FFFFh)
        MOV     R6, R8
        SHR     R6, #8
        MOV     R7, R9
        SHL     R7, #8
        OR      R6, R7
        SHR     R9, #8
        MOV     R8, R6
        EXTS    #0Ch, #2
        MOV     R4, [R5]
        MOV     R7, [R5+2]
        XOR     R8, R4
        XOR     R9, R7
        ADD     R12, #1
        ADD     R13, #1
        SUB     R10, #1
        JMPR    NZ, delta_byte
        MOV     R12, #(crc_zero_powers & 0FFFFh)
delta_power:
        CMP     R15, #0
        JMPR    Z, delta_done
        JNB     R15.0, delta_next
        MOV     R6, #0
        MOV     R7, #0
        MOV     R11, R12
        MOV     R10, #32
delta_bit:
        JNB     R8.0, delta_shift
        EXTS    #0Ch, #2
        MOV     R4, [R11]
        MOV     R5, [R11+2]
        XOR     R6, R4
        XOR     R7, R5
delta_shift:
        SHR     R8, #1
        MOV     R4, R9
        SHL     R4, #15
        OR      R8, R4
        SHR     R9, #1
        ADD     R11, #4
        SUB     R10, #1
        JMPR    NZ, delta_bit
        MOV     R8, R6
        MOV     R9, R7
delta_next:
        SHR     R15, #1
        ADD     R12, #128
        JMPR    UC, delta_power
delta_done:
        EXTP    #3, #2
        MOV     R6, [R3+4]
        MOV     R7, [R3+6]
        MOV     R4, R8
        MOV     R5, R9
        XOR     R4, R6
        XOR     R5, R7
        RET

compare_entry_crc:
        EXTP    #3, #2
        MOV     R6, [R3+4]
        MOV     R7, [R3+6]
        CMP     R4, R6
        JMPA    NZ, pc_bad
        CMP     R5, R7
        JMPA    NZ, pc_bad
        MOV     R4, #0
        RET

patch_matches:
        CALLA   UC, ram_info
        EXTP    #10h, #1
        MOV     R4, W_PATCH+10
        ROL     R4, #8
        ADD     R13, R4
        MOV     R12, #(W_PATCH+12)
        MOV     R10, #4
pm_loop:
        EXTP    R14, #1
        MOV     R4, [R13]
        EXTP    #10h, #1
        MOV     R5, [R12]
        CMP     R4, R5
        JMPA    NZ, pc_bad
        ADD     R12, #2
        ADD     R13, #2
        SUB     R10, #1
        JMPR    NZ, pm_loop
        MOV     R4, #0
        RET
