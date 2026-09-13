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
