; V9: the watched map. See docs/live-overlay-v9.md.
; The record is the end of pool A, logical 680..699 (041FA8..041FBB), reached through DPP2 (page 10h).

W_WOFF          EQU     09FA8h          ; word: the watched map's flash offset (R12 form, < 4000h)
W_WPAGE         EQU     09FAAh          ; word: its flash page; 0FFFFh = no watch
W_AOFF          EQU     09FACh          ; word: its live copy's offset
W_APAGE         EQU     09FAEh          ; word: its live copy's page; 0FFFFh = none
W_KIND          EQU     09FB0h          ; byte: 0 none yet, 1 map indices, 2 curve index, 3 map inputs, 4 curve input
W_COUNT         EQU     09FB1h          ; byte: reads of the watched map, wraps at 256
W_ROW           EQU     09FB2h          ; word: FB6B (zero-extended) or R13
W_ROWF          EQU     09FB4h          ; word: E390, or 0 for inputs
W_COL           EQU     09FB6h          ; word: FB6C (zero-extended) or R14; 0 for curves
W_COLF          EQU     09FB8h          ; word: E392, or 0 for inputs and curves
W_COLS          EQU     09FBAh          ; byte: FB6D, or 0 for inputs and curves
W_ROWIX         EQU     09FBBh          ; byte: the watched map's catalogue row, 0FFh = not in the catalogue

; ---- sub 12: 6D 0C a2 a1 a0 sets the watch to the app address a2a1a0 (page * 4000h + offset); 0 clears it ----
; The reply echoes the address. An address of 80000h or more is refused with reason 4 and changes nothing.
sub_watch:
        MOVBZ   R6, REQ_SUB+1           ; a2
        MOVBZ   R7, REQ_SUB+2           ; a1
        MOVBZ   R8, REQ_SUB+3           ; a0
        CMP     R6, #8
        JMPA    UGE, bad_range
        MOVB    REP_DATA, RL6           ; the echo first: watch_set uses R6 and R7
        MOVB    REP_DATA+1, RL7
        MOV     R4, R8
        MOVB    REP_DATA+2, RL4
        MOV     R4, R6
        OR      R4, R7
        OR      R4, R8
        JMPR    NZ, sw_set
        CALLA   UC, watch_clear
        JMPR    UC, sw_reply
sw_set:
        MOV     R4, R6                  ; page = address >> 14
        SHL     R4, #2
        MOV     R5, R7
        SHR     R5, #6
        OR      R4, R5
        MOV     R5, R7                  ; offset = address & 3FFFh
        AND     R5, #3Fh
        SHL     R5, #8
        OR      R5, R8
        CALLA   UC, watch_set
sw_reply:
        MOVB    RL4, #0A0h
        MOVB    REP_STATUS, RL4
        MOVB    RL4, #7
        MOVB    REP_LEN, RL4
        JMPA    UC, h_exit

; ---- watch_set: R4 = page, R5 = offset. Clears the record and finds the map's catalogue row; uses R2, R3, R6, R7 ----
; The page is written last, so no hook matches a half-written address.
watch_set:
        MOV     R2, #0FFFFh
        MOV     W_WPAGE, R2
        MOV     W_APAGE, R2
        MOV     W_WOFF, R5
        MOV     R2, #0
        MOVB    W_KIND, RL2
        MOVB    W_COUNT, RL2
        MOV     R3, #(tables & 0FFFFh)
ws_find:
        EXTS    #0Ch, #2
        MOV     R6, [R3]
        MOV     R7, [R3+2]
        CMP     R6, R4
        JMPR    NZ, ws_next
        CMP     R7, R5
        JMPR    Z, ws_found
ws_next:
        ADD     R3, #8
        ADD     R2, #1
        CMP     R2, #N_TABLES
        JMPR    ULT, ws_find
        MOV     R2, #0FFh
ws_found:
        MOVB    W_ROWIX, RL2
        MOV     W_WPAGE, R4
        CALLA   UC, watch_alias
        RET

; ---- watch_clear: no watch, no live copy, an empty record; uses R4 ----
watch_clear:
        MOV     R4, #0FFFFh
        MOV     W_WPAGE, R4
        MOV     W_APAGE, R4
        MOV     R4, #0
        MOVB    W_KIND, RL4
        MOVB    W_COUNT, RL4
        RET

; ---- watch_quiet, from housekeeping: the watch ends after 3 s without a 0x6D frame, but not at engine-off, since
; watching changes nothing the engine reads. Before the app's first frame since boot there is no watch. Uses R4 ----
watch_quiet:
        MOV     R4, W_WPAGE
        CMP     R4, #0FFFFh
        JMPR    Z, wq_done
        EXTP    #3, #1
        MOV     R4, W_MAGIC
        CMP     R4, #MAGIC
        JMPR    NZ, wq_clear
        MOV     R4, F_TICKS
        EXTP    #3, #1
        SUB     R4, W_SEEN
        CMP     R4, #SILENCE
        JMPR    ULT, wq_done
wq_clear:
        CALLA   UC, watch_clear
wq_done:
        RET

; ---- the readers (Task 2): each JMPS 0Ch, watch_rdN replaces its entry's MOVBZ Rx, FB6Bh. Rx is free until that
; instruction, which runs last; no incoming flag is read (every flag test inside comes after a MOV or MULU). ----
watch_rd0:                             ; 0D:022A, curve
        CMP     R13, W_WPAGE
        JMPR    NZ, wr0_copy
        CMP     R12, W_WOFF
        JMPR    Z, wr0_hit
wr0_copy:
        CMP     R13, W_APAGE
        JMPR    NZ, wr0_stock
        CMP     R12, W_AOFF
        JMPR    NZ, wr0_stock
wr0_hit:
        PUSH    0FF10h                  ; PSW
        BCLR    0FF10h.11               ; IEN off for the record, as at 0C:A314
wr0_rec:
        MOVBZ   R2, 0FB6Bh
        MOV     W_ROW, R2
        MOV     R2, 0E390h
        MOV     W_ROWF, R2
        MOV     R2, #0
        MOV     W_COL, R2
        MOV     W_COLF, R2
        MOVB    W_COLS, RL2
        MOVB    RL2, #2
        MOVB    W_KIND, RL2
        MOVB    RL2, W_COUNT
        ADDB    RL2, #1
        MOVB    W_COUNT, RL2
wr0_end:
        POP     0FF10h                  ; PSW
wr0_stock:
        MOVBZ   R2, 0FB6Bh
        JMPS    0Dh, 022Eh

watch_rd1:                             ; 0D:0262, curve
        CMP     R13, W_WPAGE
        JMPR    NZ, wr1_copy
        CMP     R12, W_WOFF
        JMPR    Z, wr1_hit
wr1_copy:
        CMP     R13, W_APAGE
        JMPR    NZ, wr1_stock
        CMP     R12, W_AOFF
        JMPR    NZ, wr1_stock
wr1_hit:
        PUSH    0FF10h                  ; PSW
        BCLR    0FF10h.11               ; IEN off for the record, as at 0C:A314
wr1_rec:
        MOVBZ   R2, 0FB6Bh
        MOV     W_ROW, R2
        MOV     R2, 0E390h
        MOV     W_ROWF, R2
        MOV     R2, #0
        MOV     W_COL, R2
        MOV     W_COLF, R2
        MOVB    W_COLS, RL2
        MOVB    RL2, #2
        MOVB    W_KIND, RL2
        MOVB    RL2, W_COUNT
        ADDB    RL2, #1
        MOVB    W_COUNT, RL2
wr1_end:
        POP     0FF10h                  ; PSW
wr1_stock:
        MOVBZ   R2, 0FB6Bh
        JMPS    0Dh, 0266h

watch_rd2:                             ; 0D:0454, curve
        CMP     R13, W_WPAGE
        JMPR    NZ, wr2_copy
        CMP     R12, W_WOFF
        JMPR    Z, wr2_hit
wr2_copy:
        CMP     R13, W_APAGE
        JMPR    NZ, wr2_stock
        CMP     R12, W_AOFF
        JMPR    NZ, wr2_stock
wr2_hit:
        PUSH    0FF10h                  ; PSW
        BCLR    0FF10h.11               ; IEN off for the record, as at 0C:A314
wr2_rec:
        MOVBZ   R2, 0FB6Bh
        MOV     W_ROW, R2
        MOV     R2, 0E390h
        MOV     W_ROWF, R2
        MOV     R2, #0
        MOV     W_COL, R2
        MOV     W_COLF, R2
        MOVB    W_COLS, RL2
        MOVB    RL2, #2
        MOVB    W_KIND, RL2
        MOVB    RL2, W_COUNT
        ADDB    RL2, #1
        MOVB    W_COUNT, RL2
wr2_end:
        POP     0FF10h                  ; PSW
wr2_stock:
        MOVBZ   R2, 0FB6Bh
        JMPS    0Dh, 0458h

watch_rd3:                             ; 0D:042E, curve
        CMP     R13, W_WPAGE
        JMPR    NZ, wr3_copy
        CMP     R12, W_WOFF
        JMPR    Z, wr3_hit
wr3_copy:
        CMP     R13, W_APAGE
        JMPR    NZ, wr3_stock
        CMP     R12, W_AOFF
        JMPR    NZ, wr3_stock
wr3_hit:
        PUSH    0FF10h                  ; PSW
        BCLR    0FF10h.11               ; IEN off for the record, as at 0C:A314
wr3_rec:
        MOVBZ   R2, 0FB6Bh
        MOV     W_ROW, R2
        MOV     R2, 0E390h
        MOV     W_ROWF, R2
        MOV     R2, #0
        MOV     W_COL, R2
        MOV     W_COLF, R2
        MOVB    W_COLS, RL2
        MOVB    RL2, #2
        MOVB    W_KIND, RL2
        MOVB    RL2, W_COUNT
        ADDB    RL2, #1
        MOVB    W_COUNT, RL2
wr3_end:
        POP     0FF10h                  ; PSW
wr3_stock:
        MOVBZ   R2, 0FB6Bh
        JMPS    0Dh, 0432h

watch_rd4:                             ; 0D:0168, map
        CMP     R13, W_WPAGE
        JMPR    NZ, wr4_copy
        CMP     R12, W_WOFF
        JMPR    Z, wr4_hit
wr4_copy:
        CMP     R13, W_APAGE
        JMPR    NZ, wr4_stock
        CMP     R12, W_AOFF
        JMPR    NZ, wr4_stock
wr4_hit:
        PUSH    0FF10h                  ; PSW
        BCLR    0FF10h.11               ; IEN off for the record, as at 0C:A314
wr4_rec:
        MOVBZ   R3, 0FB6Bh
        MOV     W_ROW, R3
        MOV     R3, 0E390h
        MOV     W_ROWF, R3
        MOVBZ   R3, 0FB6Ch
        MOV     W_COL, R3
        MOV     R3, 0E392h
        MOV     W_COLF, R3
        MOVB    RL3, 0FB6Dh
        MOVB    W_COLS, RL3
        MOVB    RL3, #1
        MOVB    W_KIND, RL3
        MOVB    RL3, W_COUNT
        ADDB    RL3, #1
        MOVB    W_COUNT, RL3
wr4_end:
        POP     0FF10h                  ; PSW
wr4_stock:
        MOVBZ   R3, 0FB6Bh
        JMPS    0Dh, 016Ch

watch_rd5:                             ; 0D:029A, map
        CMP     R13, W_WPAGE
        JMPR    NZ, wr5_copy
        CMP     R12, W_WOFF
        JMPR    Z, wr5_hit
wr5_copy:
        CMP     R13, W_APAGE
        JMPR    NZ, wr5_stock
        CMP     R12, W_AOFF
        JMPR    NZ, wr5_stock
wr5_hit:
        PUSH    0FF10h                  ; PSW
        BCLR    0FF10h.11               ; IEN off for the record, as at 0C:A314
wr5_rec:
        MOVBZ   R3, 0FB6Bh
        MOV     W_ROW, R3
        MOV     R3, 0E390h
        MOV     W_ROWF, R3
        MOVBZ   R3, 0FB6Ch
        MOV     W_COL, R3
        MOV     R3, 0E392h
        MOV     W_COLF, R3
        MOVB    RL3, 0FB6Dh
        MOVB    W_COLS, RL3
        MOVB    RL3, #1
        MOVB    W_KIND, RL3
        MOVB    RL3, W_COUNT
        ADDB    RL3, #1
        MOVB    W_COUNT, RL3
wr5_end:
        POP     0FF10h                  ; PSW
wr5_stock:
        MOVBZ   R3, 0FB6Bh
        JMPS    0Dh, 029Eh

watch_rd6:                             ; 0D:03D2, map
        CMP     R13, W_WPAGE
        JMPR    NZ, wr6_copy
        CMP     R12, W_WOFF
        JMPR    Z, wr6_hit
wr6_copy:
        CMP     R13, W_APAGE
        JMPR    NZ, wr6_stock
        CMP     R12, W_AOFF
        JMPR    NZ, wr6_stock
wr6_hit:
        PUSH    0FF10h                  ; PSW
        BCLR    0FF10h.11               ; IEN off for the record, as at 0C:A314
wr6_rec:
        MOVBZ   R3, 0FB6Bh
        MOV     W_ROW, R3
        MOV     R3, 0E390h
        MOV     W_ROWF, R3
        MOVBZ   R3, 0FB6Ch
        MOV     W_COL, R3
        MOV     R3, 0E392h
        MOV     W_COLF, R3
        MOVB    RL3, 0FB6Dh
        MOVB    W_COLS, RL3
        MOVB    RL3, #1
        MOVB    W_KIND, RL3
        MOVB    RL3, W_COUNT
        ADDB    RL3, #1
        MOVB    W_COUNT, RL3
wr6_end:
        POP     0FF10h                  ; PSW
wr6_stock:
        MOVBZ   R3, 0FB6Bh
        JMPS    0Dh, 03D6h

watch_rd7:                             ; 0D:043A, map
        CMP     R13, W_WPAGE
        JMPR    NZ, wr7_copy
        CMP     R12, W_WOFF
        JMPR    Z, wr7_hit
wr7_copy:
        CMP     R13, W_APAGE
        JMPR    NZ, wr7_stock
        CMP     R12, W_AOFF
        JMPR    NZ, wr7_stock
wr7_hit:
        PUSH    0FF10h                  ; PSW
        BCLR    0FF10h.11               ; IEN off for the record, as at 0C:A314
wr7_rec:
        MOVBZ   R3, 0FB6Bh
        MOV     W_ROW, R3
        MOV     R3, 0E390h
        MOV     W_ROWF, R3
        MOVBZ   R3, 0FB6Ch
        MOV     W_COL, R3
        MOV     R3, 0E392h
        MOV     W_COLF, R3
        MOVB    RL3, 0FB6Dh
        MOVB    W_COLS, RL3
        MOVB    RL3, #1
        MOVB    W_KIND, RL3
        MOVB    RL3, W_COUNT
        ADDB    RL3, #1
        MOVB    W_COUNT, RL3
wr7_end:
        POP     0FF10h                  ; PSW
wr7_stock:
        MOVBZ   R3, 0FB6Bh
        JMPS    0Dh, 043Eh

; ---- the descriptor lookups (Task 3): JMPS 0Ch, watch_dsN replaces the MOV DPP0 after the descriptor's unpacking. There
; R12 (page) : R10 (offset) is the data address, R13 the row input and R14 the column input. The displaced MOV DPP0 runs
; last; the next instructions set the flags before any test. ----
watch_ds0:                             ; 0D:04B0, map
        CMP     R12, W_WPAGE
        JMPR    NZ, wd0_copy
        CMP     R10, W_WOFF
        JMPR    Z, wd0_hit
wd0_copy:
        CMP     R12, W_APAGE
        JMPR    NZ, wd0_stock
        CMP     R10, W_AOFF
        JMPR    NZ, wd0_stock
wd0_hit:
        PUSH    0FF10h                  ; PSW
        BCLR    0FF10h.11               ; IEN off for the record, as at 0C:A314
wd0_rec:
        PUSH    R4
        MOV     W_ROW, R13
        MOV     R4, #0
        MOV     W_ROWF, R4
        MOV     W_COL, R14
        MOV     W_COLF, R4
        MOVB    W_COLS, RL4
        MOVB    RL4, #3
        MOVB    W_KIND, RL4
        MOVB    RL4, W_COUNT
        ADDB    RL4, #1
        MOVB    W_COUNT, RL4
        POP     R4
wd0_end:
        POP     0FF10h                  ; PSW
wd0_stock:
        MOV     0FE00h, R5              ; MOV DPP0, R5
        JMPS    0Dh, 04B4h

watch_ds1:                             ; 0D:05C8, map
        CMP     R12, W_WPAGE
        JMPR    NZ, wd1_copy
        CMP     R10, W_WOFF
        JMPR    Z, wd1_hit
wd1_copy:
        CMP     R12, W_APAGE
        JMPR    NZ, wd1_stock
        CMP     R10, W_AOFF
        JMPR    NZ, wd1_stock
wd1_hit:
        PUSH    0FF10h                  ; PSW
        BCLR    0FF10h.11               ; IEN off for the record, as at 0C:A314
wd1_rec:
        PUSH    R4
        MOV     W_ROW, R13
        MOV     R4, #0
        MOV     W_ROWF, R4
        MOV     W_COL, R14
        MOV     W_COLF, R4
        MOVB    W_COLS, RL4
        MOVB    RL4, #3
        MOVB    W_KIND, RL4
        MOVB    RL4, W_COUNT
        ADDB    RL4, #1
        MOVB    W_COUNT, RL4
        POP     R4
wd1_end:
        POP     0FF10h                  ; PSW
wd1_stock:
        MOV     0FE00h, R5              ; MOV DPP0, R5
        JMPS    0Dh, 05CCh

watch_ds2:                             ; 0D:0776, map
        CMP     R12, W_WPAGE
        JMPR    NZ, wd2_copy
        CMP     R10, W_WOFF
        JMPR    Z, wd2_hit
wd2_copy:
        CMP     R12, W_APAGE
        JMPR    NZ, wd2_stock
        CMP     R10, W_AOFF
        JMPR    NZ, wd2_stock
wd2_hit:
        PUSH    0FF10h                  ; PSW
        BCLR    0FF10h.11               ; IEN off for the record, as at 0C:A314
wd2_rec:
        PUSH    R4
        MOV     W_ROW, R13
        MOV     R4, #0
        MOV     W_ROWF, R4
        MOV     W_COL, R14
        MOV     W_COLF, R4
        MOVB    W_COLS, RL4
        MOVB    RL4, #3
        MOVB    W_KIND, RL4
        MOVB    RL4, W_COUNT
        ADDB    RL4, #1
        MOVB    W_COUNT, RL4
        POP     R4
wd2_end:
        POP     0FF10h                  ; PSW
wd2_stock:
        MOV     0FE00h, R5              ; MOV DPP0, R5
        JMPS    0Dh, 077Ah

watch_ds3:                             ; 0D:089E, map
        CMP     R12, W_WPAGE
        JMPR    NZ, wd3_copy
        CMP     R10, W_WOFF
        JMPR    Z, wd3_hit
wd3_copy:
        CMP     R12, W_APAGE
        JMPR    NZ, wd3_stock
        CMP     R10, W_AOFF
        JMPR    NZ, wd3_stock
wd3_hit:
        PUSH    0FF10h                  ; PSW
        BCLR    0FF10h.11               ; IEN off for the record, as at 0C:A314
wd3_rec:
        PUSH    R4
        MOV     W_ROW, R13
        MOV     R4, #0
        MOV     W_ROWF, R4
        MOV     W_COL, R14
        MOV     W_COLF, R4
        MOVB    W_COLS, RL4
        MOVB    RL4, #3
        MOVB    W_KIND, RL4
        MOVB    RL4, W_COUNT
        ADDB    RL4, #1
        MOVB    W_COUNT, RL4
        POP     R4
wd3_end:
        POP     0FF10h                  ; PSW
wd3_stock:
        MOV     0FE00h, R5              ; MOV DPP0, R5
        JMPS    0Dh, 08A2h

watch_ds4:                             ; 0D:09BC, map
        CMP     R12, W_WPAGE
        JMPR    NZ, wd4_copy
        CMP     R10, W_WOFF
        JMPR    Z, wd4_hit
wd4_copy:
        CMP     R12, W_APAGE
        JMPR    NZ, wd4_stock
        CMP     R10, W_AOFF
        JMPR    NZ, wd4_stock
wd4_hit:
        PUSH    0FF10h                  ; PSW
        BCLR    0FF10h.11               ; IEN off for the record, as at 0C:A314
wd4_rec:
        PUSH    R4
        MOV     W_ROW, R13
        MOV     R4, #0
        MOV     W_ROWF, R4
        MOV     W_COL, R14
        MOV     W_COLF, R4
        MOVB    W_COLS, RL4
        MOVB    RL4, #3
        MOVB    W_KIND, RL4
        MOVB    RL4, W_COUNT
        ADDB    RL4, #1
        MOVB    W_COUNT, RL4
        POP     R4
wd4_end:
        POP     0FF10h                  ; PSW
wd4_stock:
        MOV     0FE00h, R5              ; MOV DPP0, R5
        JMPS    0Dh, 09C0h

watch_ds5:                             ; 0D:0B60, map
        CMP     R12, W_WPAGE
        JMPR    NZ, wd5_copy
        CMP     R10, W_WOFF
        JMPR    Z, wd5_hit
wd5_copy:
        CMP     R12, W_APAGE
        JMPR    NZ, wd5_stock
        CMP     R10, W_AOFF
        JMPR    NZ, wd5_stock
wd5_hit:
        PUSH    0FF10h                  ; PSW
        BCLR    0FF10h.11               ; IEN off for the record, as at 0C:A314
wd5_rec:
        PUSH    R4
        MOV     W_ROW, R13
        MOV     R4, #0
        MOV     W_ROWF, R4
        MOV     W_COL, R14
        MOV     W_COLF, R4
        MOVB    W_COLS, RL4
        MOVB    RL4, #3
        MOVB    W_KIND, RL4
        MOVB    RL4, W_COUNT
        ADDB    RL4, #1
        MOVB    W_COUNT, RL4
        POP     R4
wd5_end:
        POP     0FF10h                  ; PSW
wd5_stock:
        MOV     0FE00h, R5              ; MOV DPP0, R5
        JMPS    0Dh, 0B64h

watch_ds6:                             ; 0D:0C88, map
        CMP     R12, W_WPAGE
        JMPR    NZ, wd6_copy
        CMP     R10, W_WOFF
        JMPR    Z, wd6_hit
wd6_copy:
        CMP     R12, W_APAGE
        JMPR    NZ, wd6_stock
        CMP     R10, W_AOFF
        JMPR    NZ, wd6_stock
wd6_hit:
        PUSH    0FF10h                  ; PSW
        BCLR    0FF10h.11               ; IEN off for the record, as at 0C:A314
wd6_rec:
        PUSH    R4
        MOV     W_ROW, R13
        MOV     R4, #0
        MOV     W_ROWF, R4
        MOV     W_COL, R14
        MOV     W_COLF, R4
        MOVB    W_COLS, RL4
        MOVB    RL4, #3
        MOVB    W_KIND, RL4
        MOVB    RL4, W_COUNT
        ADDB    RL4, #1
        MOVB    W_COUNT, RL4
        POP     R4
wd6_end:
        POP     0FF10h                  ; PSW
wd6_stock:
        MOV     0FE00h, R5              ; MOV DPP0, R5
        JMPS    0Dh, 0C8Ch

watch_ds7:                             ; 0D:0EC2, map
        CMP     R12, W_WPAGE
        JMPR    NZ, wd7_copy
        CMP     R10, W_WOFF
        JMPR    Z, wd7_hit
wd7_copy:
        CMP     R12, W_APAGE
        JMPR    NZ, wd7_stock
        CMP     R10, W_AOFF
        JMPR    NZ, wd7_stock
wd7_hit:
        PUSH    0FF10h                  ; PSW
        BCLR    0FF10h.11               ; IEN off for the record, as at 0C:A314
wd7_rec:
        PUSH    R4
        MOV     W_ROW, R13
        MOV     R4, #0
        MOV     W_ROWF, R4
        MOV     W_COL, R14
        MOV     W_COLF, R4
        MOVB    W_COLS, RL4
        MOVB    RL4, #3
        MOVB    W_KIND, RL4
        MOVB    RL4, W_COUNT
        ADDB    RL4, #1
        MOVB    W_COUNT, RL4
        POP     R4
wd7_end:
        POP     0FF10h                  ; PSW
wd7_stock:
        MOV     0FE00h, R5              ; MOV DPP0, R5
        JMPS    0Dh, 0EC6h

watch_ds8:                             ; 0D:1092, map
        CMP     R12, W_WPAGE
        JMPR    NZ, wd8_copy
        CMP     R10, W_WOFF
        JMPR    Z, wd8_hit
wd8_copy:
        CMP     R12, W_APAGE
        JMPR    NZ, wd8_stock
        CMP     R10, W_AOFF
        JMPR    NZ, wd8_stock
wd8_hit:
        PUSH    0FF10h                  ; PSW
        BCLR    0FF10h.11               ; IEN off for the record, as at 0C:A314
wd8_rec:
        PUSH    R4
        MOV     W_ROW, R13
        MOV     R4, #0
        MOV     W_ROWF, R4
        MOV     W_COL, R14
        MOV     W_COLF, R4
        MOVB    W_COLS, RL4
        MOVB    RL4, #3
        MOVB    W_KIND, RL4
        MOVB    RL4, W_COUNT
        ADDB    RL4, #1
        MOVB    W_COUNT, RL4
        POP     R4
wd8_end:
        POP     0FF10h                  ; PSW
wd8_stock:
        MOV     0FE00h, R11             ; MOV DPP0, R11
        JMPS    0Dh, 1096h

watch_ds9:                             ; 0D:06E4, curve
        CMP     R12, W_WPAGE
        JMPR    NZ, wd9_copy
        CMP     R10, W_WOFF
        JMPR    Z, wd9_hit
wd9_copy:
        CMP     R12, W_APAGE
        JMPR    NZ, wd9_stock
        CMP     R10, W_AOFF
        JMPR    NZ, wd9_stock
wd9_hit:
        PUSH    0FF10h                  ; PSW
        BCLR    0FF10h.11               ; IEN off for the record, as at 0C:A314
wd9_rec:
        PUSH    R4
        MOV     W_ROW, R13
        MOV     R4, #0
        MOV     W_ROWF, R4
        MOV     W_COL, R4
        MOV     W_COLF, R4
        MOVB    W_COLS, RL4
        MOVB    RL4, #4
        MOVB    W_KIND, RL4
        MOVB    RL4, W_COUNT
        ADDB    RL4, #1
        MOVB    W_COUNT, RL4
        POP     R4
wd9_end:
        POP     0FF10h                  ; PSW
wd9_stock:
        MOV     0FE00h, R5              ; MOV DPP0, R5
        JMPS    0Dh, 06E8h

watch_ds10:                             ; 0D:0AD6, curve
        CMP     R12, W_WPAGE
        JMPR    NZ, wd10_copy
        CMP     R10, W_WOFF
        JMPR    Z, wd10_hit
wd10_copy:
        CMP     R12, W_APAGE
        JMPR    NZ, wd10_stock
        CMP     R10, W_AOFF
        JMPR    NZ, wd10_stock
wd10_hit:
        PUSH    0FF10h                  ; PSW
        BCLR    0FF10h.11               ; IEN off for the record, as at 0C:A314
wd10_rec:
        PUSH    R4
        MOV     W_ROW, R13
        MOV     R4, #0
        MOV     W_ROWF, R4
        MOV     W_COL, R4
        MOV     W_COLF, R4
        MOVB    W_COLS, RL4
        MOVB    RL4, #4
        MOVB    W_KIND, RL4
        MOVB    RL4, W_COUNT
        ADDB    RL4, #1
        MOVB    W_COUNT, RL4
        POP     R4
wd10_end:
        POP     0FF10h                  ; PSW
wd10_stock:
        MOV     0FE00h, R5              ; MOV DPP0, R5
        JMPS    0Dh, 0ADAh

watch_ds11:                             ; 0D:0DA4, curve
        CMP     R12, W_WPAGE
        JMPR    NZ, wd11_copy
        CMP     R10, W_WOFF
        JMPR    Z, wd11_hit
wd11_copy:
        CMP     R12, W_APAGE
        JMPR    NZ, wd11_stock
        CMP     R10, W_AOFF
        JMPR    NZ, wd11_stock
wd11_hit:
        PUSH    0FF10h                  ; PSW
        BCLR    0FF10h.11               ; IEN off for the record, as at 0C:A314
wd11_rec:
        PUSH    R4
        MOV     W_ROW, R13
        MOV     R4, #0
        MOV     W_ROWF, R4
        MOV     W_COL, R4
        MOV     W_COLF, R4
        MOVB    W_COLS, RL4
        MOVB    RL4, #4
        MOVB    W_KIND, RL4
        MOVB    RL4, W_COUNT
        ADDB    RL4, #1
        MOVB    W_COUNT, RL4
        POP     R4
wd11_end:
        POP     0FF10h                  ; PSW
wd11_stock:
        MOV     0FE00h, R5              ; MOV DPP0, R5
        JMPS    0Dh, 0DA8h

watch_ds12:                             ; 0D:0E30, curve
        CMP     R12, W_WPAGE
        JMPR    NZ, wd12_copy
        CMP     R10, W_WOFF
        JMPR    Z, wd12_hit
wd12_copy:
        CMP     R12, W_APAGE
        JMPR    NZ, wd12_stock
        CMP     R10, W_AOFF
        JMPR    NZ, wd12_stock
wd12_hit:
        PUSH    0FF10h                  ; PSW
        BCLR    0FF10h.11               ; IEN off for the record, as at 0C:A314
wd12_rec:
        PUSH    R4
        MOV     W_ROW, R13
        MOV     R4, #0
        MOV     W_ROWF, R4
        MOV     W_COL, R4
        MOV     W_COLF, R4
        MOVB    W_COLS, RL4
        MOVB    RL4, #4
        MOVB    W_KIND, RL4
        MOVB    RL4, W_COUNT
        ADDB    RL4, #1
        MOVB    W_COUNT, RL4
        POP     R4
wd12_end:
        POP     0FF10h                  ; PSW
wd12_stock:
        MOV     0FE00h, R5              ; MOV DPP0, R5
        JMPS    0Dh, 0E34h

watch_ds13:                             ; 0D:0FE2, curve
        CMP     R12, W_WPAGE
        JMPR    NZ, wd13_copy
        CMP     R10, W_WOFF
        JMPR    Z, wd13_hit
wd13_copy:
        CMP     R12, W_APAGE
        JMPR    NZ, wd13_stock
        CMP     R10, W_AOFF
        JMPR    NZ, wd13_stock
wd13_hit:
        PUSH    0FF10h                  ; PSW
        BCLR    0FF10h.11               ; IEN off for the record, as at 0C:A314
wd13_rec:
        PUSH    R4
        MOV     W_ROW, R13
        MOV     R4, #0
        MOV     W_ROWF, R4
        MOV     W_COL, R4
        MOV     W_COLF, R4
        MOVB    W_COLS, RL4
        MOVB    RL4, #4
        MOVB    W_KIND, RL4
        MOVB    RL4, W_COUNT
        ADDB    RL4, #1
        MOVB    W_COUNT, RL4
        POP     R4
wd13_end:
        POP     0FF10h                  ; PSW
wd13_stock:
        MOV     0FE00h, R5              ; MOV DPP0, R5
        JMPS    0Dh, 0FE6h

watch_ds14:                             ; 0D:1018, curve
        CMP     R12, W_WPAGE
        JMPR    NZ, wd14_copy
        CMP     R10, W_WOFF
        JMPR    Z, wd14_hit
wd14_copy:
        CMP     R12, W_APAGE
        JMPR    NZ, wd14_stock
        CMP     R10, W_AOFF
        JMPR    NZ, wd14_stock
wd14_hit:
        PUSH    0FF10h                  ; PSW
        BCLR    0FF10h.11               ; IEN off for the record, as at 0C:A314
wd14_rec:
        PUSH    R4
        MOV     W_ROW, R13
        MOV     R4, #0
        MOV     W_ROWF, R4
        MOV     W_COL, R4
        MOV     W_COLF, R4
        MOVB    W_COLS, RL4
        MOVB    RL4, #4
        MOVB    W_KIND, RL4
        MOVB    RL4, W_COUNT
        ADDB    RL4, #1
        MOVB    W_COUNT, RL4
        POP     R4
wd14_end:
        POP     0FF10h                  ; PSW
wd14_stock:
        MOV     0FE00h, R5              ; MOV DPP0, R5
        JMPS    0Dh, 101Ch

watch_ds15:                             ; 0D:1052, curve
        CMP     R12, W_WPAGE
        JMPR    NZ, wd15_copy
        CMP     R10, W_WOFF
        JMPR    Z, wd15_hit
wd15_copy:
        CMP     R12, W_APAGE
        JMPR    NZ, wd15_stock
        CMP     R10, W_AOFF
        JMPR    NZ, wd15_stock
wd15_hit:
        PUSH    0FF10h                  ; PSW
        BCLR    0FF10h.11               ; IEN off for the record, as at 0C:A314
wd15_rec:
        PUSH    R4
        MOV     W_ROW, R13
        MOV     R4, #0
        MOV     W_ROWF, R4
        MOV     W_COL, R4
        MOV     W_COLF, R4
        MOVB    W_COLS, RL4
        MOVB    RL4, #4
        MOVB    W_KIND, RL4
        MOVB    RL4, W_COUNT
        ADDB    RL4, #1
        MOVB    W_COUNT, RL4
        POP     R4
wd15_end:
        POP     0FF10h                  ; PSW
wd15_stock:
        MOV     0FE00h, R5              ; MOV DPP0, R5
        JMPS    0Dh, 1056h

; ---- watch_alias (Task 4): W_APAGE:W_AOFF is the watched map's live copy, in the readers' form, while its catalogue row
; holds an allocation; else W_APAGE = 0FFFFh. From housekeeping every 10 ms and from watch_set. Uses R3, R4 ----
watch_alias:
        MOV     [-R0], R2
        MOV     [-R0], R5
        MOV     R5, #0FFFFh             ; the page: none
        MOV     R2, W_WPAGE
        CMP     R2, #0FFFFh
        JMPR    Z, wa_store
        EXTP    #3, #1
        MOV     R2, W_MAGIC
        CMP     R2, #MAGIC
        JMPR    NZ, wa_store
        MOVBZ   R2, W_ROWIX
        CMP     R2, #0FFh
        JMPR    Z, wa_store
        CALLA   UC, entry_addr          ; R3 = its directory record, or 0
        CMP     R3, #0
        JMPR    Z, wa_store
        EXTP    #3, #1
        MOVB    RL4, [R3+2]             ; the logical offset / 4
        MOVBZ   R4, RL4
        SHL     R4, #2
        MOV     R5, #10h
        CMP     R4, #704
        JMPR    ULT, wa_pool_a
        SUB     R4, #704
        ADD     R4, #26E0h
        MOV     R5, #3
        JMPR    UC, wa_store
wa_pool_a:
        ADD     R4, #1D00h
wa_store:
        PUSH    0FF10h                  ; PSW
        BCLR    0FF10h.11               ; IEN off: no hook sees a page with another map's offset
        MOV     R2, #0FFFFh
        MOV     W_APAGE, R2
        MOV     W_AOFF, R4
        MOV     W_APAGE, R5
        POP     0FF10h
        MOV     R5, [R0+]
        MOV     R2, [R0+]
        RET

; ---- watch_unalias (Task 4): no live copy for the watch, at once. Load, Free, Revert and every switch-off call it before
; they change an allocation (RF1); housekeeping finds the copy again within 10 ms. Preserves every register ----
watch_unalias:
        MOV     [-R0], R4
        MOV     R4, #0FFFFh
        MOV     W_APAGE, R4
        MOV     R4, [R0+]
        RET
