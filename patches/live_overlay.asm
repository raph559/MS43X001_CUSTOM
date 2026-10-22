; MS43X001 live-tuning overlay, version 1 (plan 6).
;
; Built by tools/build_live_overlay.py from the car file bins/CAR_current_43X001_SP95_STAGE1.bin; the emulator's tests
; run its assembly (sim/tests/Ms43Sim.Tests/fixtures/live_overlay.hex). The contract it implements is "The K-line
; contract" in docs/superpowers/plans/2026-10-22-ms43-emulator-plan6-overlay-bin.md. Nothing built from this file is
; flashed without the owner's explicit go-ahead; patches/overlay.asm (2026-10-19) is a different, known-bad patch.
;
; AS is case-insensitive: a label must not repeat a constant's name (ST_FREE, st_free).
;
; Rules this source keeps (plan 6, Global Constraints): every routine at an even address; the overlay leaves only by RETS,
; RET to its own caller, or JMPS to 0D:029A, 0D:0168 or 0D:80DE; no write to a DPP, CP, SP, SYSCON or an interrupt
; control; the window reached only through EXTP #10h; writes only to the window, the DS2 reply buffer and the stacks;
; every hex literal starts with a digit.

        CPU     80C167
        ASSUME  DPP0:1Ch, DPP1:3Bh, DPP2:10h, DPP3:3

OVL_VERSION     EQU     1               ; (AS predefines VERSION)
RICHER_ONLY     EQU     1               ; 1: no lambda cell leaner than flashed, K within 90-100 % of K0 (no wideband yet)
PEDAL_LIVE      EQU     1               ; 1: the pedal map is live, inside the tune's own envelope

; ---- the window: external RAM 9D00-9FDF (page 10h), reached only through EXTP #10h ----
W_MAGIC         EQU     9D00h           ; C0DEh once the handler has initialised the window
W_SEEN          EQU     9D02h           ; E2A6 at the last 0x6D frame
W_KEDIT         EQU     9D04h           ; the edited K
W_KSTATE        EQU     9D06h           ; byte: 0 no edit, 1 stored (off), 2 on; 9D07 stays 0
W_DIR           EQU     9D08h           ; 6 entries of 6 bytes: state, 0, copy offset (word), edit sum (word)
W_COPY          EQU     9D2Ch           ; the copy area: 692 bytes, to 9FDF
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
F_K             EQU     91B6h           ; K, written once at start-up
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
        DW      6                       ; live tables
        DW      0

code_start:

; ---- the table stubs: one per table, called by its sites' CALLS with R12/R13 = the table's flash address ----
e_ign98pl:
        JMPS    0Dh, 029Ah
e_ign98is:
        JMPS    0Dh, 029Ah
e_af98:
        JMPS    0Dh, 029Ah
e_camin:
        JMPS    0Dh, 029Ah
e_camex:
        JMPS    0Dh, 029Ah
e_pedal:
        JMPS    0Dh, 0168h

; ---- the K stub: replaces MOV R14, 91B6h at 0C:AB28 ----
kstub:
        MOV     R14, F_K
        RETS

; ---- housekeeping: queue-1 task 09h's entry, every 10 ms ----
hk:
        JMPS    0Dh, 080DEh

; ---- the DS2 0x6D handler: called by the dispatcher (09:FB76) with the request at F6CD ----
; R2-R5 and R10-R15 are free; R0 and R6-R9 are kept. The serial-line task sends F74D.. once this returns.
handler:
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
        JMPR    NZ, bad_sub
        CMPB    RL4, #5
        JMPR    NZ, bad_len
        JMPA    UC, sub_status

bad_len:
        MOVB    RL3, #1
        JMPR    UC, refuse_b0
bad_sub:
        MOVB    RL3, #2
refuse_b0:
        MOVB    RL4, #0B0h
        MOVB    REP_STATUS, RL4
        MOVB    REP_DATA, RL3
        MOVB    RL4, #5
        MOVB    REP_LEN, RL4
        RETS

; ---- status: the 52-byte payload of the contract ----
sub_status:
        CALLA   UC, running
        MOV     R13, R4                 ; 1 while the engine runs
        MOV     R2, #REP_DATA
        MOV     R4, #544Ch              ; "LT"
        MOV     [R2], R4
        MOV     R4, #564Fh              ; "OV"
        MOV     [R2+2], R4
        MOV     R4, R13
        OR      R4, #(RICHER_ONLY*2 + PEDAL_LIVE*4)
        SHL     R4, #8
        OR      R4, #OVL_VERSION
        MOV     [R2+4], R4             ; the version, then the flags
        MOV     R10, F_K                ; K0
        EXTP    #10h, #1
        MOV     R11, W_KEDIT
        MOV     R12, R10                ; K now: the edit while K is on and the engine runs, else K0
        EXTP    #10h, #1
        MOVB    RL4, W_KSTATE
        CMPB    RL4, #2
        JMPR    NZ, st_know
        CMP     R13, #0
        JMPR    Z, st_know
        MOV     R12, R11
st_know:
        MOV     R4, R12
        ROL     R4, #8                  ; big-endian
        MOV     [R2+6], R4
        MOV     R4, R11
        ROL     R4, #8
        MOV     [R2+8], R4
        MOV     R4, R10
        ROL     R4, #8
        MOV     [R2+10], R4
        EXTP    #10h, #1
        MOV     R4, W_KSTATE            ; the K state, then 0
        MOV     [R2+12], R4
        MOV     R3, #W_DIR
        MOV     R5, #(REP_DATA + 14)
st_entry:
        EXTP    #10h, #1
        MOV     R4, [R3]                ; the state, then 0
        MOV     [R5], R4
        EXTP    #10h, #1
        MOV     R4, [R3+2]             ; the copy offset
        ROL     R4, #8
        MOV     [R5+2], R4
        EXTP    #10h, #1
        MOV     R4, [R3+4]             ; the edit sum
        ROL     R4, #8
        MOV     [R5+4], R4
        ADD     R3, #6
        ADD     R5, #6
        CMP     R3, #(W_DIR + 36)
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
        CMP     R3, #(W_DIR + 36)
        JMPR    ULT, fr_loop
        ROL     R4, #8
        MOV     [R2+50], R4
        MOVB    RL4, #0A0h
        MOVB    REP_STATUS, RL4
        MOVB    RL4, #56
        MOVB    REP_LEN, RL4
        RETS

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

; ---- the live tables: page, page offset, bytes, flags (bit 0 words, bit 1 the lambda rule, bit 2 the pedal envelope) ----
tables:
        DW      001Dh, 3315h, 320, 0    ; 0 ip_iga_ron98_pl__n__maf   0x77315
        DW      001Dh, 35D4h, 36, 0     ; 1 ip_iga_ron98_is__n__maf   0x775D4
        DW      001Fh, 169Ch, 192, 2    ; 2 ip_af_target_ron98__maf__n 0x7D69C
        DW      001Dh, 2390h, 192, 0    ; 3 ip_cam_sp_ron98_in_pl     0x76390
        DW      001Dh, 229Ch, 192, 0    ; 4 ip_cam_sp_ron98_ex_pl     0x7629C
        DW      001Fh, 24DCh, 288, 5    ; 5 ip_tps_sp_pvs__pvs__n     0x7E4DC

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
        ORG     09B12Ah                 ; file 0x1B12A: ip_tps_sp_pvs's read
        CALLS   0Ch, e_pedal & 0FFFFh
        ORG     0CAB28h                 ; file 0x4AB28: MOV R14, 91B6h, the one read of K
        CALLS   0Ch, kstub & 0FFFFh
        ORG     09FC8Ah                 ; file 0x1FC8A: the dispatcher's slot for command 6Dh
        CALLS   0Ch, handler & 0FFFFh
        ORG     0EE3E2h                 ; file 0x6E3E2: queue-1 task 09h (0D:80DE)
        DW      hk & 0FFFFh, 000Ch
        ORG     0EFE00h                 ; file 0x6FE00: the end of the program CRC's range 4
        DW      (data_end - 1) & 0FFFFh, 000Ch
