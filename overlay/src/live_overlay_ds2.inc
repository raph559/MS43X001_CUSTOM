; the DS2 0x6D handler: called by the dispatcher (09:FB76) with the request at F6CD
; It keeps R0 and saves R6-R9 and R15 on the user stack, as the firmware's handlers do; R1 is left alone. The serial-line task
; sends F74D.. once this returns.
handler:
        MOV     [-R0], R15
        MOV     [-R0], R9
        MOV     [-R0], R8
        MOV     [-R0], R7
        MOV     [-R0], R6
        EXTP    #3, #1
        MOV     R4, W_MAGIC
        CMP     R4, #MAGIC
        JMPR    Z, h_ready
        MOV     R5, #W_SEEN             ; the first frame since boot: zero E6B2-E6DF, then the magic
        MOV     R4, #0
h_zero:
        EXTP    #3, #1
        MOV     [R5], R4
        ADD     R5, #2
        CMP     R5, #W_COPY
        JMPR    ULT, h_zero
        MOVB    RL4, #0FFh
        EXTP    #3, #1
        MOVB    W_DIR+35, RL4
        CALLA   UC, hard_init
        MOV     R4, #MAGIC
        EXTP    #3, #1
        MOV     W_MAGIC, R4
        MOV     R4, #0
        EXTP    #3, #2
        MOV     W_REV, R4
        MOV     W_REV+2, R4
h_ready:
        CALLA   UC, off_due             ; a frame after a stop or a silence finds everything off first
        CMP     R4, #0
        JMPR    Z, h_stamp
        CALLA   UC, all_off
h_stamp:
        MOV     R4, F_TICKS             ; the keep-alive
        EXTP    #3, #1
        MOV     W_SEEN, R4
        MOVBZ   R4, REQ_LEN
        CMP     R4, #5
        JMPA    ULT, bad_len
        MOVBZ   R5, REQ_SUB
        CMP     R5, #0
        JMPR    NZ, h_open
        CMP     R4, #5
        JMPA    NZ, bad_len
        JMPA    UC, sub_status
h_open:
        CMP     R5, #10
        JMPR    NZ, h_patch
        CMP     R4, #9
        JMPA    NZ, bad_len
        JMPA    UC, sub_open
h_patch:
        CMP     R5, #9
        JMPR    NZ, h_watch
        CMP     R4, #29
        JMPA    NZ, bad_len
        JMPA    UC, sub_patch
h_watch:
        CMP     R5, #12
        JMPR    NZ, h_log
        CMP     R4, #8
        JMPA    NZ, bad_len
        JMPA    UC, sub_watch
h_log:
        CMP     R5, #11
        JMPR    NZ, h_auth
        CMP     R4, #5
        JMPA    NZ, bad_len
        JMPA    UC, sub_log
h_auth:
        CMP     R4, #13
        JMPA    ULT, bad_len
        CALLA   UC, authorize
        CMP     R4, #0
        JMPA    NZ, refuse_b1
        MOVBZ   R4, REQ_LEN
        SUB     R4, #8
        MOVBZ   R5, REQ_SUB
        CMP     R5, #1
        JMPR    NZ, h_write
        CMP     R4, #9
        JMPA    NZ, bad_len
        JMPA    UC, sub_load
h_write:
        CMP     R5, #2
        JMPR    NZ, h_on
        CMP     R4, #8
        JMPA    ULT, bad_len
        JMPA    UC, sub_write
h_on:
        CMP     R5, #3
        JMPR    NZ, h_off
        CMP     R4, #10
        JMPA    NZ, bad_len
        JMPA    UC, sub_on
h_off:
        CMP     R5, #4
        JMPR    NZ, h_allon
        CMP     R4, #6
        JMPA    NZ, bad_len
        JMPA    UC, sub_off
h_allon:
        CMP     R5, #5
        JMPR    NZ, h_alloff
        CMP     R4, #5
        JMPA    NZ, bad_len
        JMPA    UC, sub_allon
h_alloff:
        CMP     R5, #6
        JMPR    NZ, h_free
        CMP     R4, #5
        JMPA    NZ, bad_len
        CALLA   UC, all_off
        JMPA    UC, ack
h_free:
        CMP     R5, #7
        JMPR    NZ, h_revert
        CMP     R4, #6
        JMPA    NZ, bad_len
        JMPA    UC, sub_free
h_revert:
        CMP     R5, #8
        JMPA    NZ, bad_sub
        CMP     R4, #5
        JMPA    NZ, bad_len
        JMPA    UC, sub_revert

; the replies: refusals carry the reason in RL4; every path leaves through h_exit
bad_len:
        MOV     R4, #1
        JMPR    UC, refuse_b0
bad_sub:
        MOV     R4, #2
        JMPR    UC, refuse_b0
bad_table:
        MOV     R4, #3
        JMPR    UC, refuse_b0
bad_range:
        MOV     R4, #4
        JMPR    UC, refuse_b0
bad_overlap:
        MOV     R4, #5
refuse_b0:
        MOVB    RL5, #0B0h
        JMPR    UC, refuse
refuse_stopped:
        MOV     R4, #6
        JMPR    UC, refuse_b1
refuse_on:
        MOV     R4, #7
        JMPR    UC, refuse_b1
refuse_free:
        MOV     R4, #8
refuse_b1:
        MOVB    RL5, #0B1h
refuse:
        MOVB    REP_STATUS, RL5
        MOVB    REP_DATA, RL4
        MOVB    RL4, #5
        MOVB    REP_LEN, RL4
        JMPR    UC, h_exit
ack:
        CALLA   UC, advance_revision
ack_same:
        MOV     R12, #W_REV
        MOV     R13, #REP_DATA
        CALLA   UC, reply_dword
        MOVB    RL4, #0A0h
        MOVB    REP_STATUS, RL4
        MOVB    RL4, #8
        MOVB    REP_LEN, RL4
h_exit:
        MOV     R6, [R0+]
        MOV     R7, [R0+]
        MOV     R8, [R0+]
        MOV     R9, [R0+]
        MOV     R15, [R0+]
        RETS

; load i, off: the flashed table copied to the copy area at off; Loaded
sub_load:
        CALLA   UC, watch_unalias
        MOVBZ   R2, REQ_ARG
        CMP     R2, #(N_TABLES - 1)
        JMPA    UGT, bad_table
        MOVBZ   R6, REQ_ARG+1
        SHL     R6, #8
        MOVBZ   R4, REQ_ARG+2
        OR      R6, R4
        MOV     R4, R6
        AND     R4, #3
        JMPA    NZ, bad_range
        CALLA   UC, table_info
        CMP     R6, #COPY_BYTES
        JMPA    UGE, bad_range
        MOV     R7, R6
        ADD     R7, R10
        CMP     R7, #COPY_BYTES
        JMPA    UGT, bad_range
        CMP     R6, #704
        JMPR    UGE, ld_boundary_ok
        CMP     R7, #668
        JMPA    UGT, bad_range
ld_boundary_ok:
        CALLA   UC, entry_addr
        CMP     R3, #0
        JMPR    Z, ld_new
        EXTP    #3, #1
        MOVB    RL4, [R3]
        CMPB    RL4, #ST_ON
        JMPA    Z, refuse_on
        MOVBZ   R4, REQ_ARG+3
        CMP     R3, #W_COPY
        JMPR    UGE, ld_existing_extra
        CMP     R4, #255
        JMPA    NZ, bad_range
        JMPA    UC, ld_check_overlap
ld_existing_extra:
        CMP     R4, #50
        JMPA    UGT, bad_range
        SHL     R4, #2
        ADD     R4, #W_COPY
        CMP     R4, R3
        JMPA    NZ, bad_range
        JMPA    UC, ld_check_overlap
ld_new:
        MOVBZ   R4, REQ_ARG+3
        CMP     R4, #255
        JMPR    Z, ld_find_base
        CMP     R4, #50
        JMPA    UGT, bad_range
        SHL     R4, #2
        ADD     R4, #W_COPY
        MOV     R3, R4
        JMPA    UC, ld_check_overlap
ld_find_base:
        MOV     R3, #W_DIR
ld_base_loop:
        EXTP    #3, #1
        MOVB    RL4, [R3]
        CMPB    RL4, #ST_FREE
        JMPR    Z, ld_check_overlap
        ADD     R3, #8
        CMP     R3, #(W_DIR+8*BASE_SLOTS)
        JMPR    ULT, ld_base_loop
        JMPA    UC, bad_overlap
ld_check_overlap:
        MOV     R15, #0FFFFh
        CMP     R3, #W_COPY
        JMPR    ULT, ld_other_start
        MOV     R15, R3
        SUB     R15, #(W_COPY-704)
        MOV     R8, R15
        ADD     R8, #8
        CMP     R6, R8
        JMPR    UGE, ld_other_start
        CMP     R7, R15
        JMPA    UGT, bad_overlap
ld_other_start:
        EXTP    #3, #1
        MOVBZ   R4, W_DIR+35
        CMP     R4, #255
        JMPR    NZ, ld_index_needed
        CMP     R3, #W_COPY
        JMPR    ULT, ld_index_ok
ld_index_needed:
        CMP     R7, #912
        JMPA    UGT, bad_overlap
ld_index_ok:
        MOV     R9, #W_DIR
ld_overlap_loop:
        EXTP    #3, #1
        MOVB    RL4, [R9]
        CMPB    RL4, #ST_FREE
        JMPR    Z, ld_overlap_next
        CMP     R9, R3
        JMPR    NZ, ld_other
        EXTP    #3, #1
        MOVB    RL4, [R9+1]
        MOVBZ   R4, RL4
        CMP     R4, R2
        JMPA    NZ, bad_overlap
        JMPR    UC, ld_overlap_next
ld_other:
        MOV     [-R0], R2
        EXTP    #3, #1
        MOVB    RL4, [R9+1]
        MOVBZ   R2, RL4
        CALLA   UC, table_info
        MOV     R2, [R0+]
        EXTP    #3, #1
        MOVB    RL4, [R9+2]
        MOVBZ   R8, RL4
        SHL     R8, #2
        MOV     R5, R8
        ADD     R5, R10
        CMP     R15, #0FFFFh
        JMPR    Z, ld_other_index_ok
        CMP     R5, #912
        JMPA    UGT, bad_overlap
ld_other_index_ok:
        CALLA   UC, load_range_conflict
        CMP     R4, #0
        JMPA    NZ, bad_overlap
        CMP     R9, #W_COPY
        JMPR    ULT, ld_overlap_next
        MOV     R8, R9
        SUB     R8, #(W_COPY-704)
        MOV     R5, R8
        ADD     R5, #8
        CALLA   UC, load_range_conflict
        CMP     R4, #0
        JMPA    NZ, bad_overlap
ld_overlap_next:
        MOV     [-R0], R3
        MOV     R3, R9
        CALLA   UC, entry_next
        MOV     R9, R3
        MOV     R3, [R0+]
        CMP     R9, #0
        JMPA    NZ, ld_overlap_loop
        MOV     R4, R6
        SHR     R4, #2
        EXTP    #3, #2
        MOVB    [R3+2], RL4
        MOVB    [R3+1], RL2
        CALLA   UC, ram_info
        CALLA   UC, table_info
ld_copy:
        EXTP    R11, #1
        MOVB    RL4, [R12]
        EXTP    R14, #1
        MOVB    [R13], RL4
        ADD     R12, #1
        ADD     R13, #1
        SUB     R10, #1
        JMPR    NZ, ld_copy
        MOV     R4, #0
        EXTP    #3, #2
        MOV     [R3+4], R4
        MOV     [R3+6], R4
        CALLA   UC, bitmap_include
        MOV     R4, #ST_LOADED
        EXTP    #3, #1
        MOVB    [R3], RL4
        CALLA   UC, link_entry
        JMPA    UC, ack

; Other allocation [R8,R5); requested data [R6,R7), optional record R15.
load_range_conflict:
        CMP     R7, R8
        JMPR    ULE, lrc_record
        CMP     R6, R5
        JMPR    ULT, lrc_bad
lrc_record:
        CMP     R15, #0FFFFh
        JMPR    Z, lrc_ok
        MOV     R4, R15
        ADD     R4, #8
        CMP     R4, R8
        JMPR    ULE, lrc_ok
        CMP     R15, R5
        JMPR    ULT, lrc_bad
lrc_ok:
        MOV     R4, #0
        RET
lrc_bad:
        MOV     R4, #1
        RET

; write i, at, data: into a loaded or ready table's copy from its byte at; the table becomes Loaded
sub_write:
        MOVBZ   R2, REQ_ARG
        CMP     R2, #(N_TABLES - 1)
        JMPA    UGT, bad_table
        MOVBZ   R7, REQ_LEN
        SUB     R7, #16                 ; excludes the session and revision
        JMPA    Z, bad_range
        CMP     R7, #MOST_WRITE
        JMPA    UGT, bad_range
        MOVBZ   R6, REQ_ARG+1
        SHL     R6, #8
        MOVBZ   R4, REQ_ARG+2
        OR      R6, R4                  ; R6: at
        CALLA   UC, table_info          ; R10: the table's bytes
        CMP     R6, R10
        JMPA    UGT, bad_range          ; first, so the end below cannot wrap
        MOV     R8, R6
        ADD     R8, R7
        CMP     R8, R10
        JMPA    UGT, bad_range          ; the write runs past the table
        CALLA   UC, entry_addr
        CMP     R3, #0
        JMPA    Z, refuse_free
        EXTP    #3, #1
        MOVB    RL4, [R3]
        CMPB    RL4, #ST_FREE
        JMPA    Z, refuse_free
        CMPB    RL4, #ST_ON
        JMPA    Z, refuse_on            ; never into a copy the reader may be reading
        CALLA   UC, feature_write_validate
        CMP     R4, #0
        JMPA    NZ, refuse_b1
        CALLA   UC, ram_info
        ADD     R13, R6
        MOV     R12, #(REQ_ARG + 3)     ; the data: F6DC on
wr_copy:
        MOVB    RL4, [R12]
        EXTP    R14, #1
        MOVB    [R13], RL4
        ADD     R12, #1
        ADD     R13, #1
        SUB     R7, #1
        JMPR    NZ, wr_copy
        MOV     R4, #ST_LOADED          ; unconfirmed until its next on
        EXTP    #3, #1
        MOVB    [R3], RL4
        JMPA    UC, ack

; on i, crc32: finalize a loaded copy after full-content CRC verification
sub_on:
        MOVBZ   R2, REQ_ARG
        CMP     R2, #(N_TABLES - 1)
        JMPA    UGT, bad_table
        CALLA   UC, running
        CMP     R4, #0
        JMPA    Z, refuse_stopped
        CALLA   UC, entry_addr
        CMP     R3, #0
        JMPA    Z, refuse_free
        EXTP    #3, #1
        MOVB    RL4, [R3]
        CMPB    RL4, #ST_FREE
        JMPA    Z, refuse_free
        MOVBZ   R7, REQ_ARG+1
        SHL     R7, #8
        MOVBZ   R4, REQ_ARG+2
        OR      R7, R4                  ; high CRC word, wire big-endian
        MOVBZ   R6, REQ_ARG+3
        SHL     R6, #8
        MOVBZ   R4, REQ_ARG+4
        OR      R6, R4                  ; low CRC word
        CALLA   UC, verify
        CMP     R4, #0
        JMPA    NZ, refuse_b1
        EXTP    #3, #1
        MOV     [R3+4], R6
        EXTP    #3, #1
        MOV     [R3+6], R7
        MOV     R4, #ST_ON              ; the state, written last
        EXTP    #3, #1
        MOVB    [R3], RL4
        JMPA    UC, ack

; off i: On becomes Ready, the copy stays
sub_off:
        MOVBZ   R2, REQ_ARG
        CMP     R2, #(N_TABLES - 1)
        JMPA    UGT, bad_table
        CALLA   UC, entry_addr
        CMP     R3, #0
        JMPA    Z, refuse_free
        EXTP    #3, #1
        MOVB    RL4, [R3]
        CMPB    RL4, #ST_ON
        JMPA    NZ, ack
        MOV     R4, #ST_READY
        EXTP    #3, #1
        MOVB    [R3], RL4
        JMPA    UC, ack

; all on: every Ready table verified again with its stored CRC, then all of them On together; a Loaded
; table stays off. One that fails refuses the request, and nothing switches on
sub_allon:
        CALLA   UC, running
        CMP     R4, #0
        JMPA    Z, refuse_stopped
        MOV     R3, #W_DIR
an_check:
        EXTP    #3, #1
        MOVB    RL4, [R3]
        CMPB    RL4, #ST_READY
        JMPR    NZ, an_cnext
        EXTP    #3, #1
        MOVB    RL4, [R3+1]
        MOVBZ   R2, RL4
        EXTP    #3, #2
        MOV     R6, [R3+4]
        MOV     R7, [R3+6]
        CALLA   UC, verify
        CMP     R4, #0
        JMPA    NZ, refuse_b1
an_cnext:
        CALLA   UC, entry_next
        CMP     R3, #0
        JMPR    NZ, an_check
        MOV     R3, #W_DIR
an_on:
        EXTP    #3, #1
        MOVB    RL4, [R3]
        CMPB    RL4, #ST_READY
        JMPR    NZ, an_onext
        MOVB    RL4, #ST_ON
        EXTP    #3, #1
        MOVB    [R3], RL4
an_onext:
        CALLA   UC, entry_next
        CMP     R3, #0
        JMPR    NZ, an_on
        EXTP    #10h, #1
        MOVBZ   R4, W_HARD+7
        JNB     R4.5, an_done
        OR      R4, #80h
        EXTP    #10h, #1
        MOVB    W_HARD+7, RL4
an_done:
        JMPA    UC, ack

; free i: a table not On back to Free
sub_free:
        CALLA   UC, watch_unalias
        MOVBZ   R2, REQ_ARG
        CMP     R2, #(N_TABLES - 1)
        JMPA    UGT, bad_table
        CALLA   UC, entry_addr
        CMP     R3, #0
        JMPA    Z, refuse_free
        EXTP    #3, #1
        MOVB    RL4, [R3]
        CMPB    RL4, #ST_ON
        JMPA    Z, refuse_on
        CALLA   UC, free_entry
        JMPA    UC, ack

; revert: every table Free, On ones included
sub_revert:
        CALLA   UC, watch_unalias
        MOV     R3, #W_DIR
rv_loop:
        CALLA   UC, free_entry
        ADD     R3, #8
        CMP     R3, #(W_DIR+8*BASE_SLOTS)
        JMPR    ULT, rv_loop
rv_extra:
        MOV     R3, #(W_DIR+32)
        CALLA   UC, entry_next
        CMP     R3, #0
        JMPR    Z, rv_limiter
        CALLA   UC, free_entry
        JMPR    UC, rv_extra
rv_limiter:
        EXTP    #10h, #1
        MOVBZ   R4, W_HARD+7
        AND     R4, #41h
        EXTP    #10h, #1
        MOVB    W_HARD+7, RL4
        JMPA    UC, ack

; status: 64 payload bytes, including the session, revision and limiter
sub_status:
        CALLA   UC, running
        MOV     R13, R4                 ; 1 while the engine runs
        MOV     R2, #REP_DATA
        MOV     R4, #544Ch              ; "LT"
        MOV     [R2], R4
        MOV     R4, #564Fh              ; "OV"
        MOV     [R2+2], R4
        MOV     R4, R13
        OR      R4, #(RICHER_ONLY*2)
        SHL     R4, #8
        OR      R4, #OVL_VERSION
        MOV     [R2+4], R4              ; the version, then the flags
        MOV     R3, #W_DIR
        MOV     R5, #(REP_DATA + 6)
st_entry:
        EXTP    #3, #1
        MOV     R4, [R3]                ; state, then catalogue ID
        MOV     [R5], R4
        EXTP    #3, #1
        MOV     R4, [R3+2]              ; packed offset/4 and control/link
        MOV     [R5+2], R4
        EXTP    #3, #1
        MOV     R4, [R3+6]              ; high CRC word first on the wire
        ROL     R4, #8
        MOV     [R5+4], R4
        EXTP    #3, #1
        MOV     R4, [R3+4]
        ROL     R4, #8
        MOV     [R5+6], R4
        ADD     R3, #8
        ADD     R5, #8
        CMP     R3, #(W_DIR + 8*BASE_SLOTS)
        JMPR    ULT, st_entry
        MOV     R9, #(COPY_BYTES-36)
        EXTP    #3, #1
        MOVBZ   R4, W_DIR+35
        CMP     R4, #255
        JMPR    Z, fr_no_index
        SUB     R9, #20
fr_no_index:
        MOV     R3, #W_DIR
fr_loop:
        EXTP    #3, #1
        MOVB    RL4, [R3]
        CMPB    RL4, #ST_FREE
        JMPR    Z, fr_next
        EXTP    #3, #1
        MOVB    RL4, [R3+1]
        MOVBZ   R2, RL4
        CALLA   UC, table_info
        SUB     R9, R10
fr_next:
        CMP     R3, #W_COPY
        JMPR    ULT, fr_step
        SUB     R9, #8
fr_step:
        CALLA   UC, entry_next
        CMP     R3, #0
        JMPR    NZ, fr_loop
        ROL     R9, #8
        MOV     REP_DATA+46, R9
        MOVB    RL4, #0A0h
        MOVB    REP_STATUS, RL4
        MOV     R12, #W_SESSION
        MOV     R13, #(REP_DATA+48)
        CALLA   UC, reply_dword
        MOV     R12, #W_REV
        MOV     R13, #(REP_DATA+52)
        CALLA   UC, reply_dword
        MOV     R12, #W_HARD
        MOV     R13, #(REP_DATA+56)
        MOV     R10, #8
st_hard:
        EXTP    #10h, #1
        MOVB    RL4, [R12]
        MOVB    [R13], RL4
        ADD     R12, #1
        ADD     R13, #1
        SUB     R10, #1
        JMPR    NZ, st_hard
        MOVB    RL4, #68
        MOVB    REP_LEN, RL4
        JMPA    UC, h_exit

; R6/R7 expected full-table CRC. No change-magnitude policy is applied in protocol 4.
verify:
        MOV     [-R0], R6
        MOV     [-R0], R7
        CALLA   UC, table_info
        CALLA   UC, ram_info
        CALLA   UC, feature_validate
        CMP     R4, #0
        JMPR    Z, vf_content
        MOV     R7, [R0+]
        MOV     R6, [R0+]
        RET
vf_content:
        MOV     R15, #0
        CALLA   UC, content_crc
        MOV     R7, [R0+]
        MOV     R6, [R0+]
        CMP     R4, R6
        JMPR    NZ, vf_crc
        CMP     R5, R7
        JMPR    NZ, vf_crc
        MOV     R4, #0
        RET
vf_crc:
        MOV     R4, #9
        RET

; R14 page, R13 pointer, R10 bytes. R2/R3 are preserved; result R4/R5 low/high.
content_crc:
        MOV     R8, #0FFFFh
        MOV     R9, #0FFFFh
crc_byte:
        EXTP    R14, #1
        MOVB    RL4, [R13]
        MOVBZ   R4, RL4
crc_update:
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
        ADD     R13, #1
        SUB     R10, #1
        JMPR    NZ, crc_byte
        MOV     R4, R8
        XOR     R4, #0FFFFh
        MOV     R5, R9
        XOR     R5, #0FFFFh
        RET

; A complete request is copied out of the receive buffer before CRC validation.
; Private snapshot: session, revision, table/reserved/start, before CRC, after CRC, eight bytes, packet CRC.
sub_patch:
        MOV     R12, #REQ_SESSION
        MOV     R13, #W_PATCH
        MOV     R10, #24
pt_snapshot:
        MOVB    RL4, [R12]
        EXTP    #10h, #1
        MOVB    [R13], RL4
        ADD     R12, #1
        ADD     R13, #1
        SUB     R10, #1
        JMPR    NZ, pt_snapshot
        MOV     R13, #W_PATCH
        MOV     R14, #10h
        MOV     R10, #20
        MOV     R15, #0
        CALLA   UC, content_crc
        MOV     R12, #(W_PATCH+20)
        CALLA   UC, patch_compare_crc
        CMP     R4, #0
        JMPA    NZ, refuse_b1
        MOV     R12, #W_PATCH
        CALLA   UC, patch_dword
        CALLA   UC, check_session
        CMP     R4, #0
        JMPA    NZ, refuse_b1
        EXTP    #10h, #2
        MOVBZ   R2, W_PATCH+8
        MOVBZ   R4, W_PATCH+9
        CMP     R2, #255
        JMPA    Z, sub_hard
        CMP     R2, #(N_TABLES-1)
        JMPA    UGT, bad_table
        CMP     R4, #0
        JMPA    NZ, bad_range
        MOV     R13, #(W_PATCH+12)
        MOV     R14, #10h
        CALLA   UC, feature_validate
        CMP     R4, #0
        JMPA    NZ, refuse_b1
        CALLA   UC, table_info
        EXTP    #10h, #1
        MOV     R6, W_PATCH+10
        ROL     R6, #8
        JB      R6.0, pt_range
        SUB     R10, #8
        CMP     R6, R10
        JMPA    UGT, bad_range
        CALLA   UC, entry_addr
        CMP     R3, #0
        JMPA    Z, refuse_free
        EXTP    #3, #1
        MOVB    RL4, [R3]
        MOVBZ   R4, RL4
        CMP     R4, #ST_ON
        JMPA    NZ, refuse_free
        CALLA   UC, running
        CMP     R4, #0
        JMPA    Z, refuse_stopped
        MOV     R12, #(W_PATCH+4)
        CALLA   UC, patch_dword
        MOV     R4, R6
        AND     R4, R7
        CMP     R4, #0FFFFh
        JMPR    NZ, pt_revision
        MOV     R4, #13
        JMPA    UC, refuse_b1
pt_revision:
        CALLA   UC, check_revision
        CMP     R4, #0
        JMPR    Z, pt_before
        ; Only a retry of the immediately preceding revision may be acknowledged without a write.
        ADD     R6, #1
        ADDC    R7, #0
        CALLA   UC, check_revision
        CMP     R4, #0
        JMPA    NZ, refuse_b1
        CALLA   UC, patch_actual_crc
        CALLA   UC, compare_entry_crc
        CMP     R4, #0
        JMPA    NZ, refuse_b1
        CALLA   UC, patch_matches
        CMP     R4, #0
        JMPA    NZ, refuse_b1
        JMPA    UC, ack_same
pt_range:
        JMPA    UC, bad_range
pt_before:
        CALLA   UC, revision_available
        CMP     R4, #0
        JMPA    NZ, refuse_b1
        CALLA   UC, patch_actual_crc
        CALLA   UC, compare_entry_crc
        CMP     R4, #0
        JMPA    NZ, refuse_b1
        CALLA   UC, patch_result_crc
        EXTP    #10h, #2
        MOV     W_PATCH+20, R4
        MOV     W_PATCH+22, R5
        CALLA   UC, ram_info
        EXTP    #10h, #1
        MOV     R4, W_PATCH+10
        ROL     R4, #8
        ADD     R13, R4
        EXTP    #10h, #4
        MOV     R4, W_PATCH+12
        MOV     R5, W_PATCH+14
        MOV     R6, W_PATCH+16
        MOV     R7, W_PATCH+18
        ; EXTP protects these four aligned stores from interrupts and PEC. No PSW/IEN change.
patch_commit:
        EXTP    R14, #4
        MOV     [R13], R4
        MOV     [R13+2], R5
        MOV     [R13+4], R6
        MOV     [R13+6], R7
patch_committed:
        ; Full current CRC and exact prospective CRC were checked before the commit.
        ; Read back the only four words changed, avoiding another full-table scan.
        MOV     R12, #(W_PATCH+12)
        MOV     R10, #4
pt_readback:
        EXTP    R14, #1
        MOV     R4, [R13]
        EXTP    #10h, #1
        MOV     R5, [R12]
        CMP     R4, R5
        JMPR    NZ, pt_write_failed
        ADD     R12, #2
        ADD     R13, #2
        SUB     R10, #1
        JMPR    NZ, pt_readback
        JMPR    UC, pt_verified
pt_write_failed:
        MOV     R4, #ST_READY
        EXTP    #3, #1
        MOVB    [R3], RL4
        CALLA   UC, advance_revision
        MOV     R4, #9
        JMPA    UC, refuse_b1
pt_verified:
        EXTP    #10h, #2
        MOV     R6, W_PATCH+20
        MOV     R7, W_PATCH+22
        EXTP    #3, #2
        MOV     [R3+4], R6
        MOV     [R3+6], R7
        JMPA    UC, ack

patch_actual_crc:
        CALLA   UC, table_info
        CALLA   UC, ram_info
        MOV     R15, #0
        JMPA    UC, content_crc

; Compare computed R4/R5 with the big-endian dword at patch pointer R12.
patch_compare_crc:
        CALLA   UC, patch_dword
        CMP     R4, R6
        JMPA    NZ, pc_bad
        CMP     R5, R7
        JMPA    NZ, pc_bad
        MOV     R4, #0
        RET
pc_bad:
        MOV     R4, #9
        RET

patch_dword:
        EXTP    #10h, #2
        MOV     R7, [R12]
        MOV     R6, [R12+2]
        ROL     R7, #8
        ROL     R6, #8
        RET

; RAM page/offset are immutable, independent of directory contents.
ram_info:
        EXTP    #3, #1
        MOVB    RL4, [R3+2]
        MOVBZ   R13, RL4
        SHL     R13, #2
        MOV     R14, #10h
        CMP     R13, #704
        JMPR    ULT, ri_external
        SUB     R13, #704
        ADD     R13, #26E0h
        MOV     R14, #3
        RET
ri_external:
        ADD     R13, #1D00h
        RET

sub_open:
        MOV     R12, #REQ_SESSION
        CALLA   UC, request_dword
        MOV     R4, R6
        OR      R4, R7
        JMPA    Z, bad_range
        CALLA   UC, check_session
        CMP     R4, #0
        JMPA    Z, ack_same
        EXTP    #3, #2
        MOV     W_SESSION, R6
        MOV     W_SESSION+2, R7
        MOV     R4, #0
        EXTP    #3, #2
        MOV     W_REV, R4
        MOV     W_REV+2, R4
        JMPA    UC, ack_same

authorize:
        MOV     R12, #REQ_SESSION
        CALLA   UC, request_dword
        CALLA   UC, check_session
        CMP     R4, #0
        JMPR    NZ, auth_done
        MOV     R12, #REQ_REV
        CALLA   UC, request_dword
        CALLA   UC, check_revision
        CMP     R4, #0
        JMPR    NZ, auth_done
        CALLA   UC, revision_available
auth_done:
        RET

request_dword:
        MOVB    RL7, [R12]
        MOVBZ   R7, RL7
        SHL     R7, #8
        MOVB    RL4, [R12+1]
        MOVBZ   R4, RL4
        OR      R7, R4
        MOVB    RL6, [R12+2]
        MOVBZ   R6, RL6
        SHL     R6, #8
        MOVB    RL4, [R12+3]
        MOVBZ   R4, RL4
        OR      R6, R4
        RET

check_session:
        MOV     R4, R6
        OR      R4, R7
        JMPR    Z, session_bad
        EXTP    #3, #1
        CMP     R6, W_SESSION
        JMPR    NZ, session_bad
        EXTP    #3, #1
        CMP     R7, W_SESSION+2
        JMPR    NZ, session_bad
        MOV     R4, #0
        RET
session_bad:
        MOV     R4, #12
        RET

check_revision:
        EXTP    #3, #1
        CMP     R6, W_REV
        JMPR    NZ, revision_bad
        EXTP    #3, #1
        CMP     R7, W_REV+2
        JMPR    NZ, revision_bad
        MOV     R4, #0
        RET
revision_bad:
        MOV     R4, #13
        RET

revision_available:
        EXTP    #3, #2
        MOV     R4, W_REV
        AND     R4, W_REV+2
        CMP     R4, #0FFFFh
        JMPR    Z, revision_bad
        MOV     R4, #0
        RET

advance_revision:
        MOV     R4, #1
        EXTP    #3, #1
        ADD     W_REV, R4
        MOV     R4, #0
        EXTP    #3, #1
        ADDC    W_REV+2, R4
        RET

; Internal little-endian dword R12 to reply big-endian R13. R2/R3 unchanged.
reply_dword:
        EXTP    #3, #2
        MOV     R4, [R12+2]
        MOV     R5, [R12]
        ROL     R4, #8
        ROL     R5, #8
        MOV     [R13], R4
        MOV     [R13+2], R5
        RET
