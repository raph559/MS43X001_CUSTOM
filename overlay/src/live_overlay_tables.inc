; off_due: R4 = 1 when everything must be off: the engine not running, or 300 ticks since the last 0x6D frame;
; else 0. Uses R4
off_due:
        CALLA   UC, running
        CMP     R4, #0
        JMPR    Z, od_yes
        MOV     R4, F_TICKS
        EXTP    #3, #1
        SUB     R4, W_SEEN
        CMP     R4, #SILENCE
        JMPR    UGE, od_yes
        MOV     R4, #0
        RET
od_yes:
        MOV     R4, #1
        RET

; all_off: every On table to Ready, its copy kept; uses R3, R4
all_off:
        CALLA   UC, watch_unalias
        MOV     [-R0], R5
        MOV     R5, #0
        MOV     R3, #W_DIR
ao_loop:
        EXTP    #3, #1
        MOVB    RL4, [R3]
        CMPB    RL4, #ST_ON
        JMPR    NZ, ao_next
        MOV     R5, #1
        MOV     R4, #ST_READY
        EXTP    #3, #1
        MOVB    [R3], RL4
ao_next:
        CALLA   UC, entry_next
        CMP     R3, #0
        JMPR    NZ, ao_loop
        EXTP    #10h, #1
        MOVBZ   R4, W_HARD+7
        JNB     R4.7, ao_epoch
        MOV     R5, #1
        AND     R4, #7Fh
        EXTP    #10h, #1
        MOVB    W_HARD+7, RL4
ao_epoch:
        CMP     R5, #0
        JMPR    Z, ao_done
        EXTP    #3, #1
        MOVBZ   R4, W_DIR+3
        ADD     R4, #1
        EXTP    #3, #1
        MOVB    W_DIR+3, RL4
        CMP     R4, #100h
        JMPR    NZ, ao_done
        EXTP    #3, #1
        MOVBZ   R4, W_DIR+11
        ADD     R4, #1
        EXTP    #3, #1
        MOVB    W_DIR+11, RL4
ao_done:
        MOV     R5, [R0+]
        RET

; Fixed control bytes survive Free. Overflow records are unlinked before reuse.
free_entry:
        CALLA   UC, bitmap_remove
        CMP     R3, #W_COPY
        JMPR    ULT, fe_clear
        MOV     [-R0], R5
        MOV     [-R0], R6
        MOV     R6, R3
        MOV     R3, #(W_DIR+32)
fe_find:
        MOV     R5, R3
        CALLA   UC, entry_next
        CMP     R3, #0
        JMPR    Z, fe_unlinked
        CMP     R3, R6
        JMPR    NZ, fe_find
        EXTP    #3, #1
        MOVB    RL4, [R3+3]
        EXTP    #3, #1
        MOVB    [R5+3], RL4
fe_unlinked:
        MOV     R3, R6
        MOV     R6, [R0+]
        MOV     R5, [R0+]
fe_clear:
        MOV     R4, #0
        EXTP    #3, #4
        MOV     [R3], R4
        MOVB    [R3+2], RL4
        MOV     [R3+4], R4
        MOV     [R3+6], R4
        RET

; Links increase within the 228-byte XRAM pool. Invalid links end the lookup.
entry_next:
        CMP     R3, #(W_DIR+32)
        JMPR    ULT, en_base
        EXTP    #3, #1
        MOVB    RL4, [R3+3]
        MOVBZ   R4, RL4
        CMP     R4, #50
        JMPR    UGT, en_end
        SHL     R4, #2
        ADD     R4, #W_COPY
        ADD     R3, #8
        CMP     R4, R3
        JMPR    ULT, en_end
        MOV     R3, R4
        RET
en_base:
        ADD     R3, #8
        RET
en_end:
        MOV     R3, #0
        RET

; Publish a complete extra record with one predecessor-link byte store.
link_entry:
        CMP     R3, #W_COPY
        JMPR    ULT, le_done
        MOV     R6, R3
        MOV     R3, #(W_DIR+32)
le_find:
        MOV     R5, R3
        CALLA   UC, entry_next
        CMP     R3, #0
        JMPR    Z, le_insert
        CMP     R3, R6
        JMPR    Z, le_restore
        JMPR    ULT, le_find
le_insert:
        MOV     R4, #255
        CMP     R3, #0
        JMPR    Z, le_tail
        MOV     R4, R3
        SUB     R4, #W_COPY
        SHR     R4, #2
le_tail:
        EXTP    #3, #1
        MOVB    [R6+3], RL4
        MOV     R4, R6
        SUB     R4, #W_COPY
        SHR     R4, #2
        EXTP    #3, #1
        MOVB    [R5+3], RL4
le_restore:
        MOV     R3, R6
le_done:
        RET

; Find a loaded map by catalogue ID; zero when it has no allocation.
entry_addr:
        MOV     R3, #W_DIR
ea_loop:
        EXTP    #3, #1
        MOVB    RL4, [R3]
        CMPB    RL4, #ST_FREE
        JMPR    Z, ea_next
        EXTP    #3, #1
        MOVB    RL4, [R3+1]
        MOVBZ   R4, RL4
        CMP     R4, R2
        JMPR    Z, ea_done
ea_next:
        CALLA   UC, entry_next
        CMP     R3, #0
        JMPR    NZ, ea_loop
        MOV     R3, #0
ea_done:
        RET

; The first extra record reserves the final 20 pool-B bytes. Publish its head only
; after the complete index exists. Later updates change one allocation bit.
bitmap_include:
        EXTP    #3, #1
        MOVBZ   R4, W_DIR+35
        CMP     R4, #255
        JMPR    NZ, bi_set
        CMP     R3, #W_COPY
        JMPR    ULT, bi_done
        MOV     [-R0], R2
        MOV     [-R0], R3
        MOV     R4, #W_BITMAP
        MOV     R5, #0
bi_clear:
        EXTP    #3, #1
        MOV     [R4], R5
        ADD     R4, #2
        CMP     R4, #(W_BITMAP+20)
        JMPR    ULT, bi_clear
        MOV     R3, #W_DIR
bi_base:
        EXTP    #3, #1
        MOVB    RL4, [R3]
        CMPB    RL4, #ST_FREE
        JMPR    Z, bi_next
        EXTP    #3, #1
        MOVB    RL4, [R3+1]
        MOVBZ   R2, RL4
        CALLA   UC, bitmap_set
bi_next:
        ADD     R3, #8
        CMP     R3, #(W_DIR+40)
        JMPR    ULT, bi_base
        MOV     R3, [R0+]
        MOV     R2, [R0+]
bi_set:
        CALLA   UC, bitmap_set
bi_done:
        RET

; R2 is the allocated ID. R3 is preserved; R4-R6 are scratch.
bitmap_set:
        CALLA   UC, bitmap_bit
        EXTP    #3, #1
        MOVB    RL5, [R4]
        ORB     RL5, RL6
        EXTP    #3, #1
        MOVB    [R4], RL5
        RET

bitmap_bit:
        MOV     R4, R2
        SHR     R4, #3
        ADD     R4, #W_BITMAP
        MOV     R5, R2
        AND     R5, #7
        MOV     R6, #1
        SHL     R6, R5
        RET

bitmap_remove:
        EXTP    #3, #1
        MOVBZ   R4, W_DIR+35
        CMP     R4, #255
        JMPR    Z, br_done
        MOV     [-R0], R2
        MOV     [-R0], R5
        MOV     [-R0], R6
        EXTP    #3, #1
        MOVB    RL4, [R3+1]
        MOVBZ   R2, RL4
        CALLA   UC, bitmap_bit
        EXTP    #3, #1
        MOVB    RL5, [R4]
        XOR     R6, #0FFFFh
        ANDB    RL5, RL6
        EXTP    #3, #1
        MOVB    [R4], RL5
        MOV     R6, [R0+]
        MOV     R5, [R0+]
        MOV     R2, [R0+]
br_done:
        RET

; table_info: table R2's flash page (R11), page offset (R12), bytes (R10); uses R5
table_info:
        MOV     R5, R2
        SHL     R5, #3
        ADD     R5, #(tables & 0FFFFh)
        EXTS    #0Ch, #3
        MOV     R11, [R5]
        MOV     R12, [R5+2]
        MOV     R10, [R5+4]
        RET

; running: R4 = 1 while the engine runs (F900 = 2 and FD2C bits 9-12), else 0; uses R4
running:
        MOVB    RL4, F_STATE
        CMPB    RL4, #2
        JMPR    NZ, r_stopped
        MOV     R4, F_MODE
        AND     R4, #1E00h
        JMPR    Z, r_stopped
        MOV     R4, #1
        RET
r_stopped:
        MOV     R4, #0
        RET
