; MS43X001 live-tuning overlay, version 1 (plan 6).
;
; Built by tools/build_live_overlay.py from the car file bins/CAR_current_43X001_SP95_STAGE1.bin; the emulator's tests
; run its assembly (sim/tests/Ms43Sim.Tests/fixtures/live_overlay.hex). The contract it implements is "The K-line
; contract" in docs/superpowers/plans/2026-10-22-ms43-emulator-plan6-overlay-bin.md. Nothing built from this file is
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

OVL_VERSION     EQU     1               ; (AS predefines VERSION)
RICHER_ONLY     EQU     1               ; 1: no lambda cell leaner than flashed (no wideband yet)
N_TABLES        EQU     5               ; the live tables (TABLES would be the label tables to AS)

; ---- the window: external RAM 9D00-9FDF (page 10h), reached only through EXTP #10h ----
W_MAGIC         EQU     9D00h           ; C0DEh once the handler has initialised the window
W_SEEN          EQU     9D02h           ; E2A6 at the last 0x6D frame
W_DIR           EQU     9D08h           ; 5 entries of 6 bytes: state, 0, copy offset (word), edit sum (word)
W_COPY          EQU     9D2Ch           ; the copy area: 692 bytes, to 9FDF (9D04-9D07 and 9D26-9D2B stay zero)
COPY_BYTES      EQU     692
MAGIC           EQU     0C0DEh
SILENCE         EQU     300             ; 3 s of 10 ms ticks
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
        MOV     R3, R2                  ; the entry: 9D08h + 6 x the table
        SHL     R3, #1
        ADD     R3, R2
        SHL     R3, #1
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

; ---- housekeeping: queue-1 task 09h's entry, every 10 ms ----
hk:
        JMPS    0Dh, 080DEh

; ---- the DS2 0x6D handler: called by the dispatcher (09:FB76) with the request at F6CD ----
; It keeps R0 and saves R6-R9 on the user stack, as the firmware's handlers do; R1 is left alone. The serial-line task
; sends F74D.. once this returns.
handler:
        MOV     [-R0], R9
        MOV     [-R0], R8
        MOV     [-R0], R7
        MOV     [-R0], R6
        EXTP    #10h, #1
        MOV     R4, W_MAGIC
        CMP     R4, #MAGIC
        JMPR    Z, h_ready
        MOV     R5, #W_SEEN             ; the first frame since the boot: zero 9D02-9D2B, then the magic
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
        JMPR    NZ, h_on
        CMPB    RL4, #8
        JMPR    NZ, bad_len
        JMPA    UC, sub_load
h_on:
        CMPB    RL5, #3
        JMPR    NZ, h_off
        CMPB    RL4, #8
        JMPR    NZ, bad_len
        JMPA    UC, sub_on
h_off:
        CMPB    RL5, #4
        JMPR    NZ, bad_sub
        CMPB    RL4, #6
        JMPR    NZ, bad_len
        JMPA    UC, sub_off

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
        SHL     R3, #1
        ADD     R3, R9
        SHL     R3, #1
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
        MOV     R4, #ST_LOADED          ; the state, written last
        EXTP    #10h, #1
        MOV     [R3], R4
        JMPA    UC, ack

; ---- on i, sum: a loaded table whose copy has this edit sum (and keeps the rules) switches on ----
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
        MOVBZ   R6, REQ_ARG+1
        SHL     R6, #8
        MOVBZ   R4, REQ_ARG+2
        OR      R6, R4                  ; R6: the edit sum
        CALLA   UC, verify
        CMP     R4, #0
        JMPA    NZ, refuse_b1
        EXTP    #10h, #1
        MOV     [R3+4], R6
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

; ---- status: the 38-byte payload of the contract ----
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
        MOV     R4, [R3+4]              ; the edit sum
        ROL     R4, #8
        MOV     [R5+4], R4
        ADD     R3, #6
        ADD     R5, #6
        CMP     R3, #(W_DIR + 6*N_TABLES)
        JMPR    ULT, st_entry
        MOV     R4, #COPY_BYTES         ; the free bytes: 692 less every table not Free
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
        ADD     R3, #6
        ADD     R5, #8
        CMP     R3, #(W_DIR + 6*N_TABLES)
        JMPR    ULT, fr_loop
        ROL     R4, #8
        MOV     [R2+36], R4
        MOVB    RL4, #0A0h
        MOVB    REP_STATUS, RL4
        MOVB    RL4, #42
        MOVB    REP_LEN, RL4
        JMPA    UC, h_exit

; ---- verify: R2 = the table, R3 = its entry, R6 = the edit sum it must have. R4 = 0, or the B1 reason. Uses R5,
; R7, R10-R14. The edit sum is the copy's bytes less the flashed table's, modulo 2^16 (D9). ----
verify:
        CALLA   UC, table_info
        EXTP    #10h, #1
        MOV     R13, [R3+2]
        ADD     R13, #W_COPY
        MOV     R4, #0
        MOV     R5, R10
vf_loop:
        EXTP    #10h, #1
        MOVB    RL7, [R13]
        MOVBZ   R7, RL7
        ADD     R4, R7
        EXTP    R11, #1
        MOVB    RL7, [R12]
        MOVBZ   R7, RL7
        SUB     R4, R7
        ADD     R12, #1
        ADD     R13, #1
        SUB     R5, #1
        JMPR    NZ, vf_loop
        CMP     R4, R6
        JMPR    NZ, vf_sum
        MOV     R4, #0
        RET
vf_sum:
        MOV     R4, #9
        RET

; ---- entry_addr: R3 = the entry of table R2 (9D08h + 6 x R2); uses R3 ----
entry_addr:
        MOV     R3, R2
        SHL     R3, #1
        ADD     R3, R2
        SHL     R3, #1
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

code_end:

; ---- the live tables: page, page offset, bytes, flags (bit 0: the lambda rule) ----
tables:
        DW      001Dh, 3315h, 320, 0    ; 0 ip_iga_ron98_pl__n__maf   0x77315
        DW      001Dh, 35D4h, 36, 0     ; 1 ip_iga_ron98_is__n__maf   0x775D4
        DW      001Fh, 169Ch, 192, 1    ; 2 ip_af_target_ron98__maf__n 0x7D69C
        DW      001Dh, 2390h, 192, 0    ; 3 ip_cam_sp_ron98_in_pl     0x76390
        DW      001Dh, 229Ch, 192, 0    ; 4 ip_cam_sp_ron98_ex_pl     0x7629C

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
