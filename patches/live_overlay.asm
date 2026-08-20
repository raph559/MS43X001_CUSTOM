; MS43X001 live overlay protocol 4. See docs/live-overlay-v4.md.
; Built from the pinned car donor; V1/V2 binaries and calibration are preserved.
; Control: 00E6B0..00E6DF; idle/intake: 00E6E0..00E7C3; revision: 00E7C4..00E7C7.
; Main/AFR/exhaust: 041D00..041FBF; private request: 041FC0..041FD7; limiter: 041FD8..041FDF.
; The disabled service monitor must remain disabled. No flash programming occurs at runtime.

        CPU     80C167
        ASSUME  DPP0:1Ch, DPP1:3Bh, DPP2:10h, DPP3:3

OVL_VERSION     EQU     4               ; (AS predefines VERSION)
RICHER_ONLY     EQU     0               ; protocol 4 preserves the full original u8 range
N_TABLES        EQU     5               ; the live tables (TABLES would be the label tables to AS)

; ---- control in XRAM, reached through EXTP #3 ----
W_MAGIC         EQU     0E6B0h           ; C0D3h once the handler has initialised the window
W_SEEN          EQU     0E6B2h           ; E2A6 at the last 0x6D frame
W_DIR           EQU     0E6B8h           ; 5 entries of 8 bytes: state, map ID, logical offset, CRC32
W_COPY          EQU     0E6E0h           ; control end, followed by idle ignition and intake cam
COPY_BYTES      EQU     932
MOST_WRITE      EQU     112             ; data bytes in one write: its request is then 128 bytes, inside the firmware's 129
MAGIC           EQU     0C0D4h
SILENCE         EQU     300             ; nominal 3 s of processed firmware ticks
W_SESSION       EQU     0E6B4h
W_REV           EQU     0E7C4h
W_PATCH         EQU     09FC0h
REQ_SESSION     EQU     0F6D1h
REQ_REV         EQU     0F6D5h
MAX_SLOTS       EQU     5
W_HARD          EQU     09FD8h
ST_FREE         EQU     0
ST_LOADED       EQU     1
ST_READY        EQU     2
ST_ON           EQU     3

; ---- the firmware's RAM (R4-R7 of the plan) ----
F_STATE         EQU     0F900h          ; byte: 2 = synchronised
F_MODE          EQU     0FD2Ch          ; bits 9-12: idle, part load, overrun, fuel cut
F_TICKS         EQU     0E2A6h          ; +1 every 10 ms in the main loop
REQ_LEN         EQU     0F6CEh          ; the request: 12h at F6CD, the length, the command, then F6D0 on
REQ_SUB         EQU     0F6D0h
REQ_ARG         EQU     0F6D9h
REP_LEN         EQU     0F74Eh          ; the reply: 12h at F74D, the length, the status, then the payload
REP_STATUS      EQU     0F74Fh
REP_DATA        EQU     0F750h

; ======================================================================================================================
        ORG     0CB544h

header: DB      "LTOV"                  ; the signature the app reads with DS2 command 06 at 0C:B544
        DW      OVL_VERSION
        DW      code_start & 0FFFFh
        DW      code_end & 0FFFFh
        DW      data_end & 0FFFFh
        DW      N_TABLES
        DW      0

code_start:

; ---- the table stubs: one per table, called by its sites' CALLS with R12/R13 = the table's flash address ----
; A stub substitutes the table's copy only for its own table's address; anything else goes to the reader untouched.
e_map0:
        CMP     R12, #3315h
        JMPA    NZ, to_reader
        CMP     R13, #001Dh
        JMPA    NZ, to_reader
        MOV     R2, #0
        JMPA    UC, subst
e_map1:
        CMP     R12, #35D4h
        JMPA    NZ, to_reader
        CMP     R13, #001Dh
        JMPA    NZ, to_reader
        MOV     R2, #1
        JMPA    UC, subst
e_map2:
        CMP     R12, #169Ch
        JMPA    NZ, to_reader
        CMP     R13, #001Fh
        JMPA    NZ, to_reader
        MOV     R2, #2
        JMPA    UC, subst
e_map3:
        CMP     R12, #2390h
        JMPA    NZ, to_reader
        CMP     R13, #001Dh
        JMPA    NZ, to_reader
        MOV     R2, #3
        JMPA    UC, subst
e_map4:
        CMP     R12, #229Ch
        JMPA    NZ, to_reader
        CMP     R13, #001Dh
        JMPA    NZ, to_reader
        MOV     R2, #4
        JMPA    UC, subst

; R2 identifies a catalogue entry. The original reader overwrites R2-R5 before use.
subst:
        EXTP    #3, #1
        MOV     R3, W_MAGIC
        CMP     R3, #MAGIC
        JMPR    NZ, to_reader
        MOV     R4, R2
        SHL     R4, #8
        OR      R4, #ST_ON
        MOV     R3, #W_DIR
        EXTP    #3, #1
        CMP     R4, [R3]
        JMPR    Z, rd_found
        ADD     R3, #8
        EXTP    #3, #1
        CMP     R4, [R3]
        JMPR    Z, rd_found
        ADD     R3, #8
        EXTP    #3, #1
        CMP     R4, [R3]
        JMPR    Z, rd_found
        ADD     R3, #8
        EXTP    #3, #1
        CMP     R4, [R3]
        JMPR    Z, rd_found
        ADD     R3, #8
        EXTP    #3, #1
        CMP     R4, [R3]
        JMPR    NZ, to_reader
rd_found:
        CALLA   UC, off_due
        CMP     R4, #0
        JMPR    NZ, to_reader
        EXTP    #3, #1
        MOV     R4, [R3+2]
        MOV     R13, #10h
        CMP     R4, #704
        JMPR    ULT, rd_external
        SUB     R4, #704
        ADD     R4, #26E0h
        MOV     R12, R4
        MOV     R13, #3
        JMPR    UC, to_reader
rd_external:
        ADD     R4, #1D00h
        MOV     R12, R4
to_reader:
        JMPS    0Dh, 029Ah

; ---- housekeeping: queue-1 task 09h's entry, every 10 ms at every engine state (D1). With the magic present, when the
; engine is not running or the app has been silent for 3 s, every On table goes to Ready, and stays there until the app
; switches it on again (D7). Then the task itself, with R3 and R4 as the scheduler left them. ----
hk:
        MOV     [-R0], R3
        MOV     [-R0], R4
        EXTP    #3, #1
        MOV     R4, W_MAGIC
        CMP     R4, #MAGIC
        JMPR    NZ, hk_task
        CALLA   UC, off_due
        CMP     R4, #0
        JMPR    Z, hk_task
        CALLA   UC, all_off
hk_task:
        MOV     R4, [R0+]
        MOV     R3, [R0+]
        JMPS    0Dh, 080DEh

; ---- the DS2 0x6D handler: called by the dispatcher (09:FB76) with the request at F6CD ----
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
        JMPR    NZ, h_auth
        CMP     R4, #29
        JMPA    NZ, bad_len
        JMPA    UC, sub_patch
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
        CMP     R4, #8
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

; ---- the replies: refusals carry the reason in RL4; every path leaves through h_exit ----
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

; ---- load i, off: the flashed table copied to the copy area at off; Loaded ----
sub_load:
        MOVBZ   R2, REQ_ARG
        CMP     R2, #(N_TABLES - 1)
        JMPA    UGT, bad_table
        MOVBZ   R6, REQ_ARG+1
        SHL     R6, #8
        MOVBZ   R4, REQ_ARG+2
        OR      R6, R4
        JB      R6.0, ld_bad_range
        CALLA   UC, table_info
        MOV     R7, R6
        ADD     R7, R10
        CMP     R6, #COPY_BYTES
        JMPA    UGE, bad_range
        CMP     R7, #COPY_BYTES
        JMPA    UGT, bad_range
        CMP     R6, #704
        JMPR    UGE, ld_boundary_ok
        CMP     R7, #704
        JMPA    UGT, bad_range
ld_boundary_ok:
        CALLA   UC, entry_addr
        CMP     R3, #0
        JMPR    Z, ld_find_free
        EXTP    #3, #1
        MOVB    RL4, [R3]
        CMPB    RL4, #ST_ON
        JMPA    Z, refuse_on
        JMPR    UC, ld_check_overlap
ld_find_free:
        MOV     R3, #W_DIR
ld_free_loop:
        EXTP    #3, #1
        MOVB    RL4, [R3]
        CMPB    RL4, #ST_FREE
        JMPR    Z, ld_check_overlap
        ADD     R3, #8
        CMP     R3, #(W_DIR+8*MAX_SLOTS)
        JMPR    ULT, ld_free_loop
        JMPA    UC, bad_overlap
ld_bad_range:
        JMPA    UC, bad_range
ld_check_overlap:
        MOV     R9, #W_DIR
ld_overlap_loop:
        CMP     R9, R3
        JMPR    Z, ld_overlap_next
        EXTP    #3, #1
        MOVB    RL4, [R9]
        CMPB    RL4, #ST_FREE
        JMPR    Z, ld_overlap_next
        EXTP    #3, #1
        MOV     R8, [R9+2]
        CMP     R7, R8
        JMPR    ULE, ld_overlap_next
        MOV     [-R0], R2
        EXTP    #3, #1
        MOVB    RL4, [R9+1]
        MOVBZ   R2, RL4
        CALLA   UC, table_info
        MOV     R2, [R0+]
        ADD     R8, R10
        CMP     R6, R8
        JMPA    ULT, bad_overlap
ld_overlap_next:
        ADD     R9, #8
        CMP     R9, #(W_DIR+8*MAX_SLOTS)
        JMPR    ULT, ld_overlap_loop
        EXTP    #3, #2
        MOV     [R3+2], R6
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
        MOV     R4, #ST_LOADED
        EXTP    #3, #1
        MOVB    [R3], RL4
        JMPA    UC, ack

; ---- write i, at, data: into a loaded or ready table's copy from its byte at; the table becomes Loaded ----
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

; ---- on i, crc32: finalize a loaded copy after full-content CRC verification ----
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

; ---- off i: On becomes Ready, the copy stays ----
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

; ---- all on: every Ready table verified again with its stored CRC, then all of them On together; a Loaded
; table stays off. One that fails refuses the request, and nothing switches on ----
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
        ADD     R3, #8
        CMP     R3, #(W_DIR+8*MAX_SLOTS)
        JMPR    ULT, an_check
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
        ADD     R3, #8
        CMP     R3, #(W_DIR+8*MAX_SLOTS)
        JMPR    ULT, an_on
        EXTP    #10h, #1
        MOVBZ   R4, W_HARD+7
        JNB     R4.5, an_done
        OR      R4, #80h
        EXTP    #10h, #1
        MOVB    W_HARD+7, RL4
an_done:
        JMPA    UC, ack

; ---- free i: a table not On back to Free ----
sub_free:
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

; ---- revert: every table Free, On ones included ----
sub_revert:
        MOV     R3, #W_DIR
rv_loop:
        CALLA   UC, free_entry
        ADD     R3, #8
        CMP     R3, #(W_DIR+8*MAX_SLOTS)
        JMPR    ULT, rv_loop
        EXTP    #10h, #1
        MOVBZ   R4, W_HARD+7
        AND     R4, #41h
        EXTP    #10h, #1
        MOVB    W_HARD+7, RL4
        JMPA    UC, ack

; ---- status: 56 payload bytes, including the session and revision ----
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
        MOV     R4, [R3]                ; the state, then 0
        MOV     [R5], R4
        EXTP    #3, #1
        MOV     R4, [R3+2]              ; the copy offset
        ROL     R4, #8
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
        CMP     R3, #(W_DIR + 8*MAX_SLOTS)
        JMPR    ULT, st_entry
        MOV     R9, #COPY_BYTES
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
        ADD     R3, #8
        CMP     R3, #(W_DIR + 8*MAX_SLOTS)
        JMPR    ULT, fr_loop
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
        MOV     R13, [R3+2]
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

; ---- off_due: R4 = 1 when everything must be off: the engine not running, or 300 ticks since the last 0x6D frame;
; else 0. Uses R4 ----
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

; ---- all_off: every On table to Ready, its copy kept; uses R3, R4 ----
all_off:
        MOV     R3, #W_DIR
ao_loop:
        EXTP    #3, #1
        MOVB    RL4, [R3]
        CMPB    RL4, #ST_ON
        JMPR    NZ, ao_next
        MOV     R4, #ST_READY
        EXTP    #3, #1
        MOVB    [R3], RL4
ao_next:
        ADD     R3, #8
        CMP     R3, #(W_DIR + 8*MAX_SLOTS)
        JMPR    ULT, ao_loop
        EXTP    #10h, #1
        MOVBZ   R4, W_HARD+7
        AND     R4, #7Fh
        EXTP    #10h, #1
        MOVB    W_HARD+7, RL4
        RET

; ---- free_entry: the entry at R3 to Free, its offset and CRC 0; the state first, so no stub substitutes after it. Uses R4 ----
free_entry:
        MOV     R4, #0
        EXTP    #3, #4
        MOV     [R3], R4
        MOV     [R3+2], R4
        MOV     [R3+4], R4
        MOV     [R3+6], R4
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
        ADD     R3, #8
        CMP     R3, #(W_DIR+8*MAX_SLOTS)
        JMPR    ULT, ea_loop
        MOV     R3, #0
ea_done:
        RET

; ---- table_info: table R2's flash page (R11), page offset (R12), bytes (R10); uses R5 ----
table_info:
        MOV     R5, R2
        SHL     R5, #3
        ADD     R5, #(tables & 0FFFFh)
        EXTS    #0Ch, #3
        MOV     R11, [R5]
        MOV     R12, [R5+2]
        MOV     R10, [R5+4]
        RET

; ---- running: R4 = 1 while the engine runs (F900 = 2 and FD2C bits 9-12), else 0; uses R4 ----
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

; V4 limiter helpers are included here, before the header's catalogue pointer.
        INCLUDE "live_overlay_v4_limiter.inc"

code_end:

; The catalogue: flash page, page offset, bytes, flags.
tables:
        DW      001Dh, 3315h, 320, 0 ; 0 ip_iga_ron98_pl__n__maf
        DW      001Dh, 35D4h, 36, 0 ; 1 ip_iga_ron98_is__n__maf
        DW      001Fh, 169Ch, 192, 0 ; 2 ip_af_target_ron98__maf__n
        DW      001Dh, 2390h, 192, 0 ; 3 ip_cam_sp_ron98_in_pl__n__maf_ivvt
        DW      001Dh, 229Ch, 192, 0 ; 4 ip_cam_sp_ron98_ex_pl__n__maf_ivvt

crc_table:
        DW      00000h, 00000h
        DW      03096h, 07707h
        DW      0612Ch, 0EE0Eh
        DW      051BAh, 09909h
        DW      0C419h, 0076Dh
        DW      0F48Fh, 0706Ah
        DW      0A535h, 0E963h
        DW      095A3h, 09E64h
        DW      08832h, 00EDBh
        DW      0B8A4h, 079DCh
        DW      0E91Eh, 0E0D5h
        DW      0D988h, 097D2h
        DW      04C2Bh, 009B6h
        DW      07CBDh, 07EB1h
        DW      02D07h, 0E7B8h
        DW      01D91h, 090BFh
        DW      01064h, 01DB7h
        DW      020F2h, 06AB0h
        DW      07148h, 0F3B9h
        DW      041DEh, 084BEh
        DW      0D47Dh, 01ADAh
        DW      0E4EBh, 06DDDh
        DW      0B551h, 0F4D4h
        DW      085C7h, 083D3h
        DW      09856h, 0136Ch
        DW      0A8C0h, 0646Bh
        DW      0F97Ah, 0FD62h
        DW      0C9ECh, 08A65h
        DW      05C4Fh, 01401h
        DW      06CD9h, 06306h
        DW      03D63h, 0FA0Fh
        DW      00DF5h, 08D08h
        DW      020C8h, 03B6Eh
        DW      0105Eh, 04C69h
        DW      041E4h, 0D560h
        DW      07172h, 0A267h
        DW      0E4D1h, 03C03h
        DW      0D447h, 04B04h
        DW      085FDh, 0D20Dh
        DW      0B56Bh, 0A50Ah
        DW      0A8FAh, 035B5h
        DW      0986Ch, 042B2h
        DW      0C9D6h, 0DBBBh
        DW      0F940h, 0ACBCh
        DW      06CE3h, 032D8h
        DW      05C75h, 045DFh
        DW      00DCFh, 0DCD6h
        DW      03D59h, 0ABD1h
        DW      030ACh, 026D9h
        DW      0003Ah, 051DEh
        DW      05180h, 0C8D7h
        DW      06116h, 0BFD0h
        DW      0F4B5h, 021B4h
        DW      0C423h, 056B3h
        DW      09599h, 0CFBAh
        DW      0A50Fh, 0B8BDh
        DW      0B89Eh, 02802h
        DW      08808h, 05F05h
        DW      0D9B2h, 0C60Ch
        DW      0E924h, 0B10Bh
        DW      07C87h, 02F6Fh
        DW      04C11h, 05868h
        DW      01DABh, 0C161h
        DW      02D3Dh, 0B666h
        DW      04190h, 076DCh
        DW      07106h, 001DBh
        DW      020BCh, 098D2h
        DW      0102Ah, 0EFD5h
        DW      08589h, 071B1h
        DW      0B51Fh, 006B6h
        DW      0E4A5h, 09FBFh
        DW      0D433h, 0E8B8h
        DW      0C9A2h, 07807h
        DW      0F934h, 00F00h
        DW      0A88Eh, 09609h
        DW      09818h, 0E10Eh
        DW      00DBBh, 07F6Ah
        DW      03D2Dh, 0086Dh
        DW      06C97h, 09164h
        DW      05C01h, 0E663h
        DW      051F4h, 06B6Bh
        DW      06162h, 01C6Ch
        DW      030D8h, 08565h
        DW      0004Eh, 0F262h
        DW      095EDh, 06C06h
        DW      0A57Bh, 01B01h
        DW      0F4C1h, 08208h
        DW      0C457h, 0F50Fh
        DW      0D9C6h, 065B0h
        DW      0E950h, 012B7h
        DW      0B8EAh, 08BBEh
        DW      0887Ch, 0FCB9h
        DW      01DDFh, 062DDh
        DW      02D49h, 015DAh
        DW      07CF3h, 08CD3h
        DW      04C65h, 0FBD4h
        DW      06158h, 04DB2h
        DW      051CEh, 03AB5h
        DW      00074h, 0A3BCh
        DW      030E2h, 0D4BBh
        DW      0A541h, 04ADFh
        DW      095D7h, 03DD8h
        DW      0C46Dh, 0A4D1h
        DW      0F4FBh, 0D3D6h
        DW      0E96Ah, 04369h
        DW      0D9FCh, 0346Eh
        DW      08846h, 0AD67h
        DW      0B8D0h, 0DA60h
        DW      02D73h, 04404h
        DW      01DE5h, 03303h
        DW      04C5Fh, 0AA0Ah
        DW      07CC9h, 0DD0Dh
        DW      0713Ch, 05005h
        DW      041AAh, 02702h
        DW      01010h, 0BE0Bh
        DW      02086h, 0C90Ch
        DW      0B525h, 05768h
        DW      085B3h, 0206Fh
        DW      0D409h, 0B966h
        DW      0E49Fh, 0CE61h
        DW      0F90Eh, 05EDEh
        DW      0C998h, 029D9h
        DW      09822h, 0B0D0h
        DW      0A8B4h, 0C7D7h
        DW      03D17h, 059B3h
        DW      00D81h, 02EB4h
        DW      05C3Bh, 0B7BDh
        DW      06CADh, 0C0BAh
        DW      08320h, 0EDB8h
        DW      0B3B6h, 09ABFh
        DW      0E20Ch, 003B6h
        DW      0D29Ah, 074B1h
        DW      04739h, 0EAD5h
        DW      077AFh, 09DD2h
        DW      02615h, 004DBh
        DW      01683h, 073DCh
        DW      00B12h, 0E363h
        DW      03B84h, 09464h
        DW      06A3Eh, 00D6Dh
        DW      05AA8h, 07A6Ah
        DW      0CF0Bh, 0E40Eh
        DW      0FF9Dh, 09309h
        DW      0AE27h, 00A00h
        DW      09EB1h, 07D07h
        DW      09344h, 0F00Fh
        DW      0A3D2h, 08708h
        DW      0F268h, 01E01h
        DW      0C2FEh, 06906h
        DW      0575Dh, 0F762h
        DW      067CBh, 08065h
        DW      03671h, 0196Ch
        DW      006E7h, 06E6Bh
        DW      01B76h, 0FED4h
        DW      02BE0h, 089D3h
        DW      07A5Ah, 010DAh
        DW      04ACCh, 067DDh
        DW      0DF6Fh, 0F9B9h
        DW      0EFF9h, 08EBEh
        DW      0BE43h, 017B7h
        DW      08ED5h, 060B0h
        DW      0A3E8h, 0D6D6h
        DW      0937Eh, 0A1D1h
        DW      0C2C4h, 038D8h
        DW      0F252h, 04FDFh
        DW      067F1h, 0D1BBh
        DW      05767h, 0A6BCh
        DW      006DDh, 03FB5h
        DW      0364Bh, 048B2h
        DW      02BDAh, 0D80Dh
        DW      01B4Ch, 0AF0Ah
        DW      04AF6h, 03603h
        DW      07A60h, 04104h
        DW      0EFC3h, 0DF60h
        DW      0DF55h, 0A867h
        DW      08EEFh, 0316Eh
        DW      0BE79h, 04669h
        DW      0B38Ch, 0CB61h
        DW      0831Ah, 0BC66h
        DW      0D2A0h, 0256Fh
        DW      0E236h, 05268h
        DW      07795h, 0CC0Ch
        DW      04703h, 0BB0Bh
        DW      016B9h, 02202h
        DW      0262Fh, 05505h
        DW      03BBEh, 0C5BAh
        DW      00B28h, 0B2BDh
        DW      05A92h, 02BB4h
        DW      06A04h, 05CB3h
        DW      0FFA7h, 0C2D7h
        DW      0CF31h, 0B5D0h
        DW      09E8Bh, 02CD9h
        DW      0AE1Dh, 05BDEh
        DW      0C2B0h, 09B64h
        DW      0F226h, 0EC63h
        DW      0A39Ch, 0756Ah
        DW      0930Ah, 0026Dh
        DW      006A9h, 09C09h
        DW      0363Fh, 0EB0Eh
        DW      06785h, 07207h
        DW      05713h, 00500h
        DW      04A82h, 095BFh
        DW      07A14h, 0E2B8h
        DW      02BAEh, 07BB1h
        DW      01B38h, 00CB6h
        DW      08E9Bh, 092D2h
        DW      0BE0Dh, 0E5D5h
        DW      0EFB7h, 07CDCh
        DW      0DF21h, 00BDBh
        DW      0D2D4h, 086D3h
        DW      0E242h, 0F1D4h
        DW      0B3F8h, 068DDh
        DW      0836Eh, 01FDAh
        DW      016CDh, 081BEh
        DW      0265Bh, 0F6B9h
        DW      077E1h, 06FB0h
        DW      04777h, 018B7h
        DW      05AE6h, 08808h
        DW      06A70h, 0FF0Fh
        DW      03BCAh, 06606h
        DW      00B5Ch, 01101h
        DW      09EFFh, 08F65h
        DW      0AE69h, 0F862h
        DW      0FFD3h, 0616Bh
        DW      0CF45h, 0166Ch
        DW      0E278h, 0A00Ah
        DW      0D2EEh, 0D70Dh
        DW      08354h, 04E04h
        DW      0B3C2h, 03903h
        DW      02661h, 0A767h
        DW      016F7h, 0D060h
        DW      0474Dh, 04969h
        DW      077DBh, 03E6Eh
        DW      06A4Ah, 0AED1h
        DW      05ADCh, 0D9D6h
        DW      00B66h, 040DFh
        DW      03BF0h, 037D8h
        DW      0AE53h, 0A9BCh
        DW      09EC5h, 0DEBBh
        DW      0CF7Fh, 047B2h
        DW      0FFE9h, 030B5h
        DW      0F21Ch, 0BDBDh
        DW      0C28Ah, 0CABAh
        DW      09330h, 053B3h
        DW      0A3A6h, 024B4h
        DW      03605h, 0BAD0h
        DW      00693h, 0CDD7h
        DW      05729h, 054DEh
        DW      067BFh, 023D9h
        DW      07A2Eh, 0B366h
        DW      04AB8h, 0C461h
        DW      01B02h, 05D68h
        DW      02B94h, 02A6Fh
        DW      0BE37h, 0B40Bh
        DW      08EA1h, 0C30Ch
        DW      0DF1Bh, 05A05h
        DW      0EF8Dh, 02D02h

; Generated by tools/generate_crc_zero_powers.py; 9 x 32 columns.
crc_zero_powers:
; Advance a remainder by 1 zero bytes.
        DW      03096h, 07707h
        DW      0612Ch, 0EE0Eh
        DW      0C419h, 0076Dh
        DW      08832h, 00EDBh
        DW      01064h, 01DB7h
        DW      020C8h, 03B6Eh
        DW      04190h, 076DCh
        DW      08320h, 0EDB8h
        DW      00001h, 00000h
        DW      00002h, 00000h
        DW      00004h, 00000h
        DW      00008h, 00000h
        DW      00010h, 00000h
        DW      00020h, 00000h
        DW      00040h, 00000h
        DW      00080h, 00000h
        DW      00100h, 00000h
        DW      00200h, 00000h
        DW      00400h, 00000h
        DW      00800h, 00000h
        DW      01000h, 00000h
        DW      02000h, 00000h
        DW      04000h, 00000h
        DW      08000h, 00000h
        DW      00000h, 00001h
        DW      00000h, 00002h
        DW      00000h, 00004h
        DW      00000h, 00008h
        DW      00000h, 00010h
        DW      00000h, 00020h
        DW      00000h, 00040h
        DW      00000h, 00080h
; Advance a remainder by 2 zero bytes.
        DW      03141h, 0191Bh
        DW      06282h, 03236h
        DW      0C504h, 0646Ch
        DW      08A08h, 0C8D9h
        DW      01251h, 04AC2h
        DW      024A2h, 09584h
        DW      04F05h, 0F079h
        DW      0984Bh, 03B83h
        DW      03096h, 07707h
        DW      0612Ch, 0EE0Eh
        DW      0C419h, 0076Dh
        DW      08832h, 00EDBh
        DW      01064h, 01DB7h
        DW      020C8h, 03B6Eh
        DW      04190h, 076DCh
        DW      08320h, 0EDB8h
        DW      00001h, 00000h
        DW      00002h, 00000h
        DW      00004h, 00000h
        DW      00008h, 00000h
        DW      00010h, 00000h
        DW      00020h, 00000h
        DW      00040h, 00000h
        DW      00080h, 00000h
        DW      00100h, 00000h
        DW      00200h, 00000h
        DW      00400h, 00000h
        DW      00800h, 00000h
        DW      01000h, 00000h
        DW      02000h, 00000h
        DW      04000h, 00000h
        DW      08000h, 00000h
; Advance a remainder by 4 zero bytes.
        DW      06765h, 0B8BCh
        DW      0C88Bh, 0AA09h
        DW      09757h, 08F62h
        DW      028EFh, 0C5B4h
        DW      0579Fh, 05019h
        DW      0AF3Eh, 0A032h
        DW      0583Dh, 09B14h
        DW      0B63Bh, 0ED59h
        DW      06A37h, 001C2h
        DW      0D46Eh, 00384h
        DW      0A8DCh, 00709h
        DW      051B8h, 00E13h
        DW      0A370h, 01C26h
        DW      046E0h, 0384Dh
        DW      08DC0h, 0709Ah
        DW      01B80h, 0E135h
        DW      03141h, 0191Bh
        DW      06282h, 03236h
        DW      0C504h, 0646Ch
        DW      08A08h, 0C8D9h
        DW      01251h, 04AC2h
        DW      024A2h, 09584h
        DW      04F05h, 0F079h
        DW      0984Bh, 03B83h
        DW      03096h, 07707h
        DW      0612Ch, 0EE0Eh
        DW      0C419h, 0076Dh
        DW      08832h, 00EDBh
        DW      01064h, 01DB7h
        DW      020C8h, 03B6Eh
        DW      04190h, 076DCh
        DW      08320h, 0EDB8h
; Advance a remainder by 8 zero bytes.
        DW      0009Eh, 0CCAAh
        DW      0077Dh, 04225h
        DW      00EFAh, 0844Ah
        DW      01BB5h, 0D3E5h
        DW      0312Bh, 07CBBh
        DW      06256h, 0F976h
        DW      0C2EDh, 0299Dh
        DW      085DAh, 0533Bh
        DW      00BB4h, 0A677h
        DW      01129h, 0979Fh
        DW      02413h, 0F44Fh
        DW      04E67h, 033EFh
        DW      09CCEh, 067DEh
        DW      0399Ch, 0CFBDh
        DW      07579h, 0440Bh
        DW      0EAF2h, 08816h
        DW      0D3A5h, 0CB5Ch
        DW      0A10Bh, 04DC8h
        DW      04216h, 09B91h
        DW      0826Dh, 0EC53h
        DW      0029Bh, 003D6h
        DW      00536h, 007ACh
        DW      00A6Ch, 00F58h
        DW      014D8h, 01EB0h
        DW      029B0h, 03D60h
        DW      05360h, 07AC0h
        DW      0A6C0h, 0F580h
        DW      04BC1h, 03070h
        DW      09782h, 060E0h
        DW      02F04h, 0C1C1h
        DW      05849h, 058F3h
        DW      0B092h, 0B1E6h
; Advance a remainder by 16 zero bytes.
        DW      09191h, 0AE68h
        DW      02563h, 087A0h
        DW      04C87h, 0D431h
        DW      09F4Fh, 07313h
        DW      03E9Eh, 0E627h
        DW      07B7Dh, 0173Fh
        DW      0F6FAh, 02E7Eh
        DW      0EDF4h, 05CFDh
        DW      0DBE8h, 0B9FBh
        DW      0B191h, 0A886h
        DW      06563h, 08A7Ch
        DW      0CC87h, 0CF89h
        DW      09F4Fh, 04462h
        DW      03E9Eh, 088C5h
        DW      07B7Dh, 0CAFBh
        DW      0F0BBh, 04E87h
        DW      0E176h, 09D0Fh
        DW      0C4ADh, 0E16Eh
        DW      08F1Bh, 019ACh
        DW      01E36h, 03359h
        DW      03C6Ch, 066B2h
        DW      078D8h, 0CD64h
        DW      0F7F1h, 041B9h
        DW      0EFE2h, 08373h
        DW      0D985h, 0DD96h
        DW      0B54Bh, 0605Ch
        DW      06A96h, 0C0B9h
        DW      0D36Dh, 05A03h
        DW      0A6DAh, 0B407h
        DW      04BF5h, 0B37Eh
        DW      091ABh, 0BD8Dh
        DW      02517h, 0A06Ah
; Advance a remainder by 32 zero bytes.
        DW      005AAh, 0F1DAh
        DW      00D15h, 038C5h
        DW      01A2Ah, 0718Ah
        DW      03454h, 0E314h
        DW      06EE9h, 01D59h
        DW      0DDD2h, 03AB2h
        DW      0BBA4h, 07565h
        DW      07748h, 0EACBh
        DW      0E8D1h, 00EE7h
        DW      0D1A2h, 01DCFh
        DW      0A344h, 03B9Fh
        DW      04688h, 0773Fh
        DW      08D10h, 0EE7Eh
        DW      01C61h, 0078Ch
        DW      038C2h, 00F18h
        DW      07184h, 01E30h
        DW      0E308h, 03C60h
        DW      0C610h, 078C1h
        DW      08C20h, 0F183h
        DW      01E01h, 03876h
        DW      03C02h, 070ECh
        DW      07804h, 0E1D8h
        DW      0F649h, 018C1h
        DW      0EC92h, 03183h
        DW      0D924h, 06307h
        DW      0B248h, 0C60Fh
        DW      062D1h, 0576Eh
        DW      0C5A2h, 0AEDCh
        DW      08D05h, 086C8h
        DW      01C4Bh, 0D6E0h
        DW      03ED7h, 076B1h
        DW      07DAEh, 0ED62h
; Advance a remainder by 64 zero bytes.
        DW      02D95h, 08F35h
        DW      05D6Bh, 0C51Bh
        DW      0BC97h, 05147h
        DW      0792Eh, 0A28Fh
        DW      0F41Dh, 09E6Fh
        DW      0EE7Bh, 0E7AEh
        DW      0DAB7h, 0142Ch
        DW      0B56Eh, 02859h
        DW      06ADCh, 050B3h
        DW      0D5B8h, 0A166h
        DW      0AD31h, 099BCh
        DW      05C23h, 0E808h
        DW      0BE07h, 00B61h
        DW      07C0Eh, 016C3h
        DW      0F81Ch, 02D86h
        DW      0F038h, 05B0Dh
        DW      0E070h, 0B61Bh
        DW      0C6A1h, 0B746h
        DW      08B03h, 0B5FCh
        DW      01047h, 0B088h
        DW      026CFh, 0BA61h
        DW      04BDFh, 0AFB3h
        DW      091FFh, 08417h
        DW      025BFh, 0D35Eh
        DW      04D3Fh, 07DCDh
        DW      09A7Eh, 0FB9Ah
        DW      032BDh, 02C44h
        DW      0657Ah, 05888h
        DW      0CAF4h, 0B110h
        DW      093A9h, 0B950h
        DW      02113h, 0A9D0h
        DW      04467h, 088D1h
; Advance a remainder by 128 zero bytes.
        DW      0F533h, 033FFh
        DW      0EA66h, 067FFh
        DW      0D4CCh, 0CFFFh
        DW      0AFD9h, 0448Eh
        DW      05FB2h, 0891Dh
        DW      0B925h, 0C94Bh
        DW      0740Bh, 049E6h
        DW      0E816h, 093CCh
        DW      0D66Dh, 0FCE8h
        DW      0AA9Bh, 022A0h
        DW      05536h, 04541h
        DW      0AA6Ch, 08A82h
        DW      05299h, 0CE74h
        DW      0A373h, 04799h
        DW      046E6h, 08F33h
        DW      08B8Dh, 0C517h
        DW      0115Bh, 0515Eh
        DW      022B6h, 0A2BCh
        DW      0432Dh, 09E09h
        DW      0801Bh, 0E763h
        DW      00677h, 015B6h
        DW      00CEEh, 02B6Ch
        DW      019DCh, 056D8h
        DW      033B8h, 0ADB0h
        DW      06131h, 08011h
        DW      0C423h, 0DB53h
        DW      08E07h, 06DD6h
        DW      01C0Eh, 0DBADh
        DW      03E5Dh, 06C2Bh
        DW      07CBAh, 0D856h
        DW      0FF35h, 06BDDh
        DW      0FE6Ah, 0D7BBh
; Advance a remainder by 256 zero bytes.
        DW      071CBh, 0CE33h
        DW      0E5D7h, 04717h
        DW      0CBAEh, 08E2Fh
        DW      0911Dh, 0C72Eh
        DW      0247Bh, 0552Ch
        DW      048F6h, 0AA58h
        DW      097ADh, 08FC1h
        DW      0291Bh, 0C4F2h
        DW      05477h, 05295h
        DW      0A8EEh, 0A52Ah
        DW      0579Dh, 09124h
        DW      0A97Bh, 0F939h
        DW      054B7h, 02902h
        DW      0A96Eh, 05204h
        DW      052DCh, 0A409h
        DW      0A3F9h, 09363h
        DW      041B3h, 0FDB6h
        DW      08527h, 0201Dh
        DW      00A4Eh, 0403Bh
        DW      0149Ch, 08076h
        DW      02F79h, 0DB9Dh
        DW      058B3h, 06C4Bh
        DW      0B166h, 0D896h
        DW      0648Dh, 06A5Ch
        DW      0C91Ah, 0D4B8h
        DW      09475h, 07200h
        DW      028EAh, 0E401h
        DW      05795h, 01373h
        DW      0AF2Ah, 026E6h
        DW      05E54h, 04DCDh
        DW      0BCA8h, 09B9Ah
        DW      07F11h, 0EC44h

data_end:

        ORG     0AC650h
        CALLS   0Ch, e_map0 & 0FFFFh
        ORG     0AC3A4h
        CALLS   0Ch, e_map1 & 0FFFFh
        ORG     0BD40Ah
        CALLS   0Ch, e_map2 & 0FFFFh
        ORG     0B3B48h
        CALLS   0Ch, e_map3 & 0FFFFh
        ORG     0B3BA2h
        CALLS   0Ch, e_map3 & 0FFFFh
        ORG     0B3B74h
        CALLS   0Ch, e_map4 & 0FFFFh
        ORG     0B3BEAh
        CALLS   0Ch, e_map4 & 0FFFFh
        ORG     0AA3ACh
        CALLS   0Ch, hard_mode & 0FFFFh
        ORG     0D8C88h
        CALLS   0Ch, hard_gears & 0FFFFh
        ORG     0D8CFCh
        CALLS   0Ch, hard_hysteresis & 0FFFFh
        ORG     0D8D18h
        CALLS   0Ch, hard_refresh & 0FFFFh
        ORG     09FC8Ah
        CALLS   0Ch, handler & 0FFFFh
        ORG     0EE3E2h
        DW      hk & 0FFFFh, 000Ch
        ORG     0EFE00h
        DW      (data_end - 1) & 0FFFFh, 000Ch
