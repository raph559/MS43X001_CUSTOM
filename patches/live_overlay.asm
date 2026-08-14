; MS43X001 live-tuning overlay, protocol version 2.
;
; Built by tools/build_live_overlay.py from the car file bins/CAR_current_43X001_SP95_STAGE1.bin; the emulator's tests
; run its assembly (sim/tests/Ms43Sim.Tests/fixtures/live_overlay_v2.hex). The v2 contract is documented in
; docs/live-overlay-v2.md. Nothing built from this file is
; flashed without the owner's explicit go-ahead; patches/overlay.asm (2026-10-19) is a different, known-bad patch.
;
; The live set is five tables: the owner took the pedal map and the fuel constant K out (2026-10-22).
;
; AS is case-insensitive: a label must not repeat a constant's name (ST_FREE, st_free).
;
; Rules this source keeps (plan 6, Global Constraints): every routine at an even address; the overlay leaves only by RETS,
; RET to its own caller, or JMPS to 0D:029A or 0D:80DE; no write to a DPP, CP, SP, SYSCON or an interrupt control; the
; window reached only through EXTP #10h; writes only to the window, the DS2 reply buffer and the stacks; every hex
; literal starts with a digit.

        CPU     80C167
        ASSUME  DPP0:1Ch, DPP1:3Bh, DPP2:10h, DPP3:3

OVL_VERSION     EQU     2               ; (AS predefines VERSION)
RICHER_ONLY     EQU     1               ; 1: no lambda cell leaner than flashed (no wideband yet)
N_TABLES        EQU     5               ; the live tables (TABLES would be the label tables to AS)

; ---- the window: external RAM 9D00-9FDF (page 10h), reached only through EXTP #10h ----
W_MAGIC         EQU     9D00h           ; C0D2h once the handler has initialised the window
W_SEEN          EQU     9D02h           ; E2A6 at the last 0x6D frame
W_DIR           EQU     9D08h           ; 5 entries of 8 bytes: state, 0, offset, CRC32 low/high words
W_COPY          EQU     9D30h           ; 688 bytes, to 9FDF; directory ends at 9D2F
COPY_BYTES      EQU     688
MOST_WRITE      EQU     120             ; data bytes in one write: its request is then 128 bytes, inside the firmware's 129
MAGIC           EQU     0C0D2h
SILENCE         EQU     300             ; nominal 3 s of processed firmware ticks
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
REQ_ARG         EQU     0F6D1h
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

W_SESSION       EQU     0E6B4h
W_REV           EQU     0E7C4h

code_start:

; ---- the table stubs: one per table, called by its sites' CALLS with R12/R13 = the table's flash address ----
; A stub substitutes the table's copy only for its own table's address; anything else goes to the reader untouched.
e_ign98pl:
        CMP     R12, #3315h
        JMPR    NZ, to_reader
        CMP     R13, #001Dh
        JMPR    NZ, to_reader
        MOV     R2, #0
        JMPR    UC, subst
e_ign98is:
        CMP     R12, #35D4h
        JMPR    NZ, to_reader
        CMP     R13, #001Dh
        JMPR    NZ, to_reader
        MOV     R2, #1
        JMPR    UC, subst
e_af98:
        CMP     R12, #169Ch
        JMPR    NZ, to_reader
        CMP     R13, #001Fh
        JMPR    NZ, to_reader
        MOV     R2, #2
        JMPR    UC, subst
e_camin:
        CMP     R12, #2390h
        JMPR    NZ, to_reader
        CMP     R13, #001Dh
        JMPR    NZ, to_reader
        MOV     R2, #3
        JMPR    UC, subst
e_camex:
        CMP     R12, #229Ch
        JMPR    NZ, to_reader
        CMP     R13, #001Dh
        JMPR    NZ, to_reader
        MOV     R2, #4
; R2 = the table. Uses R3, R4 (the reader 0D:029A sets R2-R5 before it uses them).
; The copy is read only with the magic present, the table On, the engine running and a 0x6D frame in the last 3 s (D7).
subst:
        EXTP    #10h, #1
        MOV     R3, W_MAGIC
        CMP     R3, #MAGIC
        JMPR    NZ, to_reader
        MOV     R3, R2                  ; the entry: 9D08h + 8 x the table
        SHL     R3, #3
        ADD     R3, #W_DIR
        EXTP    #10h, #1
        MOVB    RL4, [R3]
        CMPB    RL4, #ST_ON
        JMPR    NZ, to_reader
        MOVB    RL4, F_STATE
        CMPB    RL4, #2
        JMPR    NZ, to_reader
        MOV     R4, F_MODE
        AND     R4, #1E00h
        JMPR    Z, to_reader
        MOV     R4, F_TICKS
        EXTP    #10h, #1
        SUB     R4, W_SEEN
        CMP     R4, #SILENCE
        JMPR    UGE, to_reader
        EXTP    #10h, #1
        MOV     R12, [R3+2]             ; the copy's offset in the area
        ADD     R12, #(W_COPY & 3FFFh)  ; its page offset in page 10h
        MOV     R13, #0010h
to_reader:
        JMPS    0Dh, 029Ah

; ---- housekeeping: queue-1 task 09h's entry, every 10 ms at every engine state (D1). With the magic present, when the
; engine is not running or the app has been silent for 3 s, every On table goes to Ready, and stays there until the app
; switches it on again (D7). Then the task itself, with R3 and R4 as the scheduler left them. ----
hk:
        MOV     [-R0], R3
        MOV     [-R0], R4
        EXTP    #10h, #1
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
        EXTP    #10h, #1
        MOV     R4, W_MAGIC
        CMP     R4, #MAGIC
        JMPR    Z, h_ready
        MOV     R5, #W_SEEN             ; the first frame since the boot: zero 9D02-9D2F, then the magic
        MOV     R4, #0
h_zero:
        EXTP    #10h, #1
        MOV     [R5], R4
        ADD     R5, #2
        CMP     R5, #W_COPY
        JMPR    ULT, h_zero
        MOV     R4, #MAGIC
        EXTP    #10h, #1
        MOV     W_MAGIC, R4
h_ready:
        CALLA   UC, off_due             ; a frame after a stop or a silence finds everything off first
        CMP     R4, #0
        JMPR    Z, h_stamp
        CALLA   UC, all_off
h_stamp:
        MOV     R4, F_TICKS             ; the keep-alive
        EXTP    #10h, #1
        MOV     W_SEEN, R4
        MOVB    RL4, REQ_LEN
        CMPB    RL4, #5
        JMPR    ULT, bad_len            ; no sub-command byte
        MOVB    RL5, REQ_SUB
        CMPB    RL5, #0
        JMPR    NZ, h_load
        CMPB    RL4, #5
        JMPR    NZ, bad_len
        JMPA    UC, sub_status
h_load:
        CMPB    RL5, #1
        JMPR    NZ, h_write
        CMPB    RL4, #8
        JMPR    NZ, bad_len
        JMPA    UC, sub_load
h_write:
        CMPB    RL5, #2
        JMPR    NZ, h_on
        CMPB    RL4, #8
        JMPR    ULT, bad_len            ; 8 carries no data: a range error, below
        JMPA    UC, sub_write
h_on:
        CMPB    RL5, #3
        JMPR    NZ, h_off
        CMPB    RL4, #10
        JMPR    NZ, bad_len
        JMPA    UC, sub_on
h_off:
        CMPB    RL5, #4
        JMPR    NZ, h_allon
        CMPB    RL4, #6
        JMPR    NZ, bad_len
        JMPA    UC, sub_off
h_allon:
        CMPB    RL5, #5
        JMPR    NZ, h_alloff
        CMPB    RL4, #5
        JMPR    NZ, bad_len
        JMPA    UC, sub_allon
h_alloff:
        CMPB    RL5, #6
        JMPR    NZ, h_free
        CMPB    RL4, #5
        JMPR    NZ, bad_len
        CALLA   UC, all_off
        JMPR    UC, ack
h_free:
        CMPB    RL5, #7
        JMPR    NZ, h_revert
        CMPB    RL4, #6
        JMPR    NZ, bad_len
        JMPA    UC, sub_free
h_revert:
        CMPB    RL5, #8
        JMPR    NZ, bad_sub
        CMPB    RL4, #5
        JMPR    NZ, bad_len
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
        MOVB    RL4, #0A0h
        MOVB    REP_STATUS, RL4
        MOVB    RL4, #4
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
        OR      R6, R4                  ; R6: the offset in the copy area
        CMP     R6, #COPY_BYTES
        JMPA    UGT, bad_range          ; first, so the end below cannot wrap past FFFFh
        CALLA   UC, table_info          ; R11 page, R12 flash offset, R10 bytes, R14 flags
        MOV     R7, R10                 ; R7: the bytes
        MOV     R8, R6
        ADD     R8, R7                  ; R8: the copy's end
        CMP     R8, #COPY_BYTES
        JMPA    UGT, bad_range
        MOV     R9, #0                  ; R9: every other table not Free must not overlap it
ld_overlap:
        CMP     R9, R2
        JMPR    Z, ld_next
        MOV     R3, R9
        SHL     R3, #3
        ADD     R3, #W_DIR
        EXTP    #10h, #1
        MOVB    RL4, [R3]
        CMPB    RL4, #ST_FREE
        JMPR    Z, ld_next
        EXTP    #10h, #1
        MOV     R4, [R3+2]              ; its offset
        CMP     R4, R8
        JMPR    UGE, ld_next            ; it starts at or after this copy's end
        MOV     R5, R9
        SHL     R5, #3
        ADD     R5, #(tables & 0FFFFh) + 4
        EXTS    #0Ch, #1
        MOV     R5, [R5]                ; its bytes
        ADD     R5, R4                  ; its end
        CMP     R6, R5
        JMPA    ULT, bad_overlap        ; this copy starts before its end
ld_next:
        ADD     R9, #1
        CMP     R9, #N_TABLES
        JMPR    ULT, ld_overlap
        CALLA   UC, entry_addr          ; R3: the table's entry
        EXTP    #10h, #1
        MOVB    RL4, [R3]
        CMPB    RL4, #ST_ON
        JMPA    Z, refuse_on
        MOV     R13, R6
        ADD     R13, #W_COPY
        MOV     R5, R7
ld_copy:
        EXTP    R11, #1
        MOVB    RL4, [R12]
        EXTP    #10h, #1
        MOVB    [R13], RL4
        ADD     R12, #1
        ADD     R13, #1
        SUB     R5, #1
        JMPR    NZ, ld_copy
        EXTP    #10h, #1
        MOV     [R3+2], R6
        MOV     R4, #0
        EXTP    #10h, #1
        MOV     [R3+4], R4
        EXTP    #10h, #1
        MOV     [R3+6], R4
        MOV     R4, #ST_LOADED          ; the state, written last
        EXTP    #10h, #1
        MOV     [R3], R4
        JMPA    UC, ack

; ---- write i, at, data: into a loaded or ready table's copy from its byte at; the table becomes Loaded ----
sub_write:
        MOVBZ   R2, REQ_ARG
        CMP     R2, #(N_TABLES - 1)
        JMPA    UGT, bad_table
        MOVBZ   R7, REQ_LEN
        SUB     R7, #8                  ; R7: the data bytes
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
        EXTP    #10h, #1
        MOVB    RL4, [R3]
        CMPB    RL4, #ST_FREE
        JMPA    Z, refuse_free
        CMPB    RL4, #ST_ON
        JMPA    Z, refuse_on            ; never into a copy the reader may be reading
        EXTP    #10h, #1
        MOV     R13, [R3+2]
        ADD     R13, #W_COPY
        ADD     R13, R6
        MOV     R12, #(REQ_ARG + 3)     ; the data: F6D4 on
wr_copy:
        MOVB    RL4, [R12]
        EXTP    #10h, #1
        MOVB    [R13], RL4
        ADD     R12, #1
        ADD     R13, #1
        SUB     R7, #1
        JMPR    NZ, wr_copy
        MOV     R4, #ST_LOADED          ; unconfirmed until its next on
        EXTP    #10h, #1
        MOV     [R3], R4
        JMPA    UC, ack

; ---- on i, crc32: finalize a loaded copy after full-content CRC and bounded-edit checks ----
sub_on:
        MOVBZ   R2, REQ_ARG
        CMP     R2, #(N_TABLES - 1)
        JMPA    UGT, bad_table
        CALLA   UC, running
        CMP     R4, #0
        JMPA    Z, refuse_stopped
        CALLA   UC, entry_addr
        EXTP    #10h, #1
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
        EXTP    #10h, #1
        MOV     [R3+4], R6
        EXTP    #10h, #1
        MOV     [R3+6], R7
        MOV     R4, #ST_ON              ; the state, written last
        EXTP    #10h, #1
        MOV     [R3], R4
        JMPA    UC, ack

; ---- off i: On becomes Ready, the copy stays ----
sub_off:
        MOVBZ   R2, REQ_ARG
        CMP     R2, #(N_TABLES - 1)
        JMPA    UGT, bad_table
        CALLA   UC, entry_addr
        EXTP    #10h, #1
        MOVB    RL4, [R3]
        CMPB    RL4, #ST_ON
        JMPA    NZ, ack
        MOV     R4, #ST_READY
        EXTP    #10h, #1
        MOV     [R3], R4
        JMPA    UC, ack

; ---- all on: every Ready table verified again with its stored CRC and the rules, then all of them On together; a Loaded
; table stays off. One that fails refuses the request, and nothing switches on ----
sub_allon:
        CALLA   UC, running
        CMP     R4, #0
        JMPA    Z, refuse_stopped
        MOV     R2, #0
an_check:
        CALLA   UC, entry_addr
        EXTP    #10h, #1
        MOVB    RL4, [R3]
        CMPB    RL4, #ST_READY
        JMPR    NZ, an_cnext
        EXTP    #10h, #1
        MOV     R6, [R3+4]              ; low CRC word from last on
        EXTP    #10h, #1
        MOV     R7, [R3+6]              ; high CRC word
        CALLA   UC, verify
        CMP     R4, #0
        JMPA    NZ, refuse_b1
an_cnext:
        ADD     R2, #1
        CMP     R2, #N_TABLES
        JMPR    ULT, an_check
        MOV     R2, #0
an_on:
        CALLA   UC, entry_addr
        EXTP    #10h, #1
        MOVB    RL4, [R3]
        CMPB    RL4, #ST_READY
        JMPR    NZ, an_onext
        MOV     R4, #ST_ON
        EXTP    #10h, #1
        MOV     [R3], R4
an_onext:
        ADD     R2, #1
        CMP     R2, #N_TABLES
        JMPR    ULT, an_on
        JMPA    UC, ack

; ---- free i: a table not On back to Free ----
sub_free:
        MOVBZ   R2, REQ_ARG
        CMP     R2, #(N_TABLES - 1)
        JMPA    UGT, bad_table
        CALLA   UC, entry_addr
        EXTP    #10h, #1
        MOVB    RL4, [R3]
        CMPB    RL4, #ST_ON
        JMPA    Z, refuse_on
        CALLA   UC, free_entry
        JMPA    UC, ack

; ---- revert: every table Free, On ones included ----
sub_revert:
        MOV     R2, #0
rv_loop:
        CALLA   UC, entry_addr
        CALLA   UC, free_entry
        ADD     R2, #1
        CMP     R2, #N_TABLES
        JMPR    ULT, rv_loop
        JMPA    UC, ack

; ---- status: the 48-byte payload of protocol 2 ----
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
        EXTP    #10h, #1
        MOV     R4, [R3]                ; the state, then 0
        MOV     [R5], R4
        EXTP    #10h, #1
        MOV     R4, [R3+2]              ; the copy offset
        ROL     R4, #8
        MOV     [R5+2], R4
        EXTP    #10h, #1
        MOV     R4, [R3+6]              ; high CRC word first on the wire
        ROL     R4, #8
        MOV     [R5+4], R4
        EXTP    #10h, #1
        MOV     R4, [R3+4]
        ROL     R4, #8
        MOV     [R5+6], R4
        ADD     R3, #8
        ADD     R5, #8
        CMP     R3, #(W_DIR + 8*N_TABLES)
        JMPR    ULT, st_entry
        MOV     R4, #COPY_BYTES         ; the free bytes: 688 less every table not Free
        MOV     R3, #W_DIR
        MOV     R5, #(tables & 0FFFFh) + 4
fr_loop:
        EXTP    #10h, #1
        MOV     R10, [R3]
        AND     R10, #00FFh
        JMPR    Z, fr_next
        EXTS    #0Ch, #1
        MOV     R11, [R5]
        SUB     R4, R11
fr_next:
        ADD     R3, #8
        ADD     R5, #8
        CMP     R3, #(W_DIR + 8*N_TABLES)
        JMPR    ULT, fr_loop
        ROL     R4, #8
        MOV     [R2+46], R4
        MOVB    RL4, #0A0h
        MOVB    REP_STATUS, RL4
        MOVB    RL4, #52
        MOVB    REP_LEN, RL4
        JMPA    UC, h_exit

; ---- verify: R2 table, R3 directory entry, R6/R7 expected CRC low/high. R4 = 0 or refusal reason.
; CRC-32/ISO-HDLC covers the full RAM copy, including unchanged cells. Every accepted cell is within eight raw
; counts of this image's flash baseline. AFR additionally cannot be leaner. These are bounded edits, not engine validation.
verify:
        MOV     [-R0], R6
        MOV     [-R0], R7
        CALLA   UC, table_info
        EXTP    #10h, #1
        MOV     R13, [R3+2]
        ADD     R13, #W_COPY
        CALLA   UC, content_crc
        MOV     R7, [R0+]
        MOV     R6, [R0+]
        CMP     R4, R6
        JMPA    NZ, vf_crc
        CMP     R5, R7
        JMPA    NZ, vf_crc
        MOV     R4, R15                 ; content CRC matched; report the first bounded-edit refusal, if any
        RET
vf_crc:
        MOV     R4, #9
        RET

; R11 flash page, R12 flash pointer, R13 RAM pointer, R10 length, R14 flags.
; Returns content CRC low/high in R4/R5, and first cell-policy refusal (or zero) in R15.
; One reflected byte-table update and one bounded-edit comparison per byte, in the same pass.
; R2/R3 are preserved. R6/R7 are scratch (verify saves the expected CRC on the user stack).
content_crc:
        MOV     R8, #0FFFFh
        MOV     R9, #0FFFFh
        MOV     R15, #0
crc_byte:
        EXTP    #10h, #1
        MOVB    RL4, [R13]
        MOVBZ   R4, RL4
        CMP     R15, #0
        JMPR    NZ, crc_update
        EXTP    R11, #1
        MOVB    RL5, [R12]
        MOVBZ   R5, RL5
        MOV     R6, R4
        SUB     R6, R5                  ; signed delta -255..255, never an eight-bit wrapped difference
        JNB     R14.0, crc_limit
        CMP     R6, #0
        JMPR    SLT, crc_leaner
crc_limit:
        CMP     R6, #8
        JMPR    SGT, crc_limit_bad
        CMP     R6, #0FFF8h
        JMPR    SLT, crc_limit_bad
        JMPR    UC, crc_update
crc_leaner:
        MOV     R15, #0Ah
        JMPR    UC, crc_update
crc_limit_bad:
        MOV     R15, #0Bh
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
        ADD     R12, #1
        ADD     R13, #1
        SUB     R10, #1
        JMPR    NZ, crc_byte
        MOV     R4, R8
        XOR     R4, #0FFFFh
        MOV     R5, R9
        XOR     R5, #0FFFFh
        RET

; ---- off_due: R4 = 1 when everything must be off: the engine not running, or 300 ticks since the last 0x6D frame;
; else 0. Uses R4 ----
off_due:
        CALLA   UC, running
        CMP     R4, #0
        JMPR    Z, od_yes
        MOV     R4, F_TICKS
        EXTP    #10h, #1
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
        EXTP    #10h, #1
        MOVB    RL4, [R3]
        CMPB    RL4, #ST_ON
        JMPR    NZ, ao_next
        MOV     R4, #ST_READY
        EXTP    #10h, #1
        MOV     [R3], R4
ao_next:
        ADD     R3, #8
        CMP     R3, #(W_DIR + 8*N_TABLES)
        JMPR    ULT, ao_loop
        RET

; ---- free_entry: the entry at R3 to Free, its offset and CRC 0; the state first, so no stub substitutes after it. Uses R4 ----
free_entry:
        MOV     R4, #0
        EXTP    #10h, #4
        MOV     [R3], R4
        MOV     [R3+2], R4
        MOV     [R3+4], R4
        MOV     [R3+6], R4
        RET

; ---- entry_addr: R3 = the entry of table R2 (9D08h + 8 x R2); uses R3 ----
entry_addr:
        MOV     R3, R2
        SHL     R3, #3
        ADD     R3, #W_DIR
        RET

; ---- table_info: table R2's page (R11), page offset (R12), bytes (R10) and flags (R14) from the list; uses R5 ----
table_info:
        MOV     R5, R2
        SHL     R5, #3
        ADD     R5, #(tables & 0FFFFh)
        EXTS    #0Ch, #4
        MOV     R11, [R5]
        MOV     R12, [R5+2]
        MOV     R10, [R5+4]
        MOV     R14, [R5+6]
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

code_end:

; ---- the live tables: page, page offset, bytes, flags (bit 0: the lambda rule) ----
tables:
        DW      001Dh, 3315h, 320, 0    ; 0 ip_iga_ron98_pl__n__maf   0x77315
        DW      001Dh, 35D4h, 36, 0     ; 1 ip_iga_ron98_is__n__maf   0x775D4
        DW      001Fh, 169Ch, 192, 1    ; 2 ip_af_target_ron98__maf__n 0x7D69C
        DW      001Dh, 2390h, 192, 0    ; 3 ip_cam_sp_ron98_in_pl     0x76390
        DW      001Dh, 229Ch, 192, 0    ; 4 ip_cam_sp_ron98_ex_pl     0x7629C

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

; ======================================================================================================================
; The hooks: each replaces a 4-byte instruction with a 4-byte CALLS into segment 0Ch.

        ORG     0AC650h                 ; file 0x2C650: ip_iga_ron98_pl's read
        CALLS   0Ch, e_ign98pl & 0FFFFh
        ORG     0AC3A4h                 ; file 0x2C3A4: ip_iga_ron98_is's read
        CALLS   0Ch, e_ign98is & 0FFFFh
        ORG     0BD40Ah                 ; file 0x3D40A: ip_af_target_ron98's read
        CALLS   0Ch, e_af98 & 0FFFFh
        ORG     0B3B48h                 ; file 0x33B48: ip_cam_sp_ron98_in_pl's read (FD9C.3 set)
        CALLS   0Ch, e_camin & 0FFFFh
        ORG     0B3BA2h                 ; file 0x33BA2: its read otherwise
        CALLS   0Ch, e_camin & 0FFFFh
        ORG     0B3B74h                 ; file 0x33B74: ip_cam_sp_ron98_ex_pl's read (FD9C.3 set)
        CALLS   0Ch, e_camex & 0FFFFh
        ORG     0B3BEAh                 ; file 0x33BEA: its read otherwise
        CALLS   0Ch, e_camex & 0FFFFh
        ORG     09FC8Ah                 ; file 0x1FC8A: the dispatcher's slot for command 6Dh
        CALLS   0Ch, handler & 0FFFFh
        ORG     0EE3E2h                 ; file 0x6E3E2: queue-1 task 09h (0D:80DE)
        DW      hk & 0FFFFh, 000Ch
        ORG     0EFE00h                 ; file 0x6FE00: the end of the program CRC's range 4
        DW      (data_end - 1) & 0FFFFh, 000Ch
