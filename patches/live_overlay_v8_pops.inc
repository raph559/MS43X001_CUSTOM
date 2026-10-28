; Pops on lift-off (docs/live-overlay-v8.md): settings group 138, its limits and the routines that use it.
; State: FDF8.3 a window is running, FDF8.4 this lift has had its window; the last four bytes of pool A hold
; the 10 ms ticks left and the lowest RPM byte (807F) seen in the window.

POPS_LEFT       EQU     09FBCh          ; word: 10 ms ticks left in the window
POPS_MIN        EQU     09FBEh          ; byte: the lowest 807F in the window (09FBFh reserved)

; ---- the limits of group 138: lowest and highest value of each byte; a switch above its highest reads as 0 ----
pops_limits:
        DB      0, 2            ; 0 switch: 0 off, 1 always on, 2 cruise control ready
        DB      1, 50           ; 1 duration, 0.1 s
        DB      0, 255          ; 2 ignition angle, 0.375 X - 23.625 deg BTDC
        DB      100, 147        ; 3 AFR target, 0.1 X
        DB      50, 219         ; 4 minimum RPM, 32 X
        DB      144, 255        ; 5 minimum coolant, 0.75 X - 48 deg C
        DB      0, 50           ; 6 throttle opening, 0.1 deg TPS
        DB      0, 255          ; 7 minimum speed, km/h

; R3 = byte of group 138. Return R4 = the live or flashed setting, clamped to its limits.
; Preserves R2, R3 and R5..R15; changes PSW.
pops_setting:
        MOV     [-R0], R2
        MOV     [-R0], R3
        MOV     [-R0], R5
        MOV     R2, #138
        CALLA   UC, feature_address
        EXTP    R4, #1
        MOVB    RL2, [R3]
        MOV     R3, [R0+2]
        SHL     R3, #1
        ADD     R3, #(pops_limits & 0FFFFh)
        EXTS    #0Ch, #1
        MOV     R4, [R3]
        CMPB    RL2, RL4
        JMPR    UGE, ps_low_ok
        MOVB    RL2, RL4
ps_low_ok:
        CMPB    RL2, RH4
        JMPR    ULE, ps_done
        MOVB    RL2, RH4
        MOV     R3, [R0+2]
        CMP     R3, #0
        JMPR    NZ, ps_done
        MOVB    RL2, #0
ps_done:
        MOVBZ   R4, RL2
        MOV     R5, [R0+]
        MOV     R3, [R0+]
        MOV     R2, [R0+]
        RET

; R13 data pointer, R14 page of an 8-byte copy of group 138. R4 = 4 when any byte is outside its limits, else 0.
; Preserves R2, R3 and R6..R15; R5 is scratch, as for feature_validate.
pops_validate:
        MOV     [-R0], R6
        MOV     [-R0], R7
        MOV     R5, #0
pv_loop:
        MOV     R6, R13
        ADD     R6, R5
        EXTP    R14, #1
        MOVB    RL7, [R6]
        MOV     R6, R5
        SHL     R6, #1
        ADD     R6, #(pops_limits & 0FFFFh)
        EXTS    #0Ch, #1
        MOV     R4, [R6]
        CMPB    RL7, RL4
        JMPR    ULT, pv_bad
        CMPB    RL7, RH4
        JMPR    UGT, pv_bad
        ADD     R5, #1
        CMP     R5, #8
        JMPR    ULT, pv_loop
        MOV     R4, #0
        JMPR    UC, pv_done
pv_bad:
        MOV     R4, #4
pv_done:
        MOV     R7, [R0+]
        MOV     R6, [R0+]
        RET

; R5 = 1 when every condition for a window holds, else 0. Changes R2..R4 and PSW.
pops_conditions:
        MOV     R5, #0
        MOV     R3, #0
        CALLA   UC, pops_setting
        CMP     R4, #1
        JMPR    Z, pc_switched_on
        CMP     R4, #2
        JMPR    NZ, pc_done
        JNB     0FD18h.1, pc_done       ; cruise control main switch off
        JB      0FD18h.2, pc_done       ; cruise control holding a speed
pc_switched_on:
        MOV     R3, #4
        CALLA   UC, pops_setting
        MOVBZ   R2, 807Fh
        CMP     R2, R4
        JMPR    ULT, pc_done
        MOV     R3, #7
        CALLA   UC, pops_setting
        MOVBZ   R2, 847Fh
        CMP     R2, R4
        JMPR    ULT, pc_done
        MOV     R3, #5
        CALLA   UC, pops_setting
        MOVBZ   R2, 8433h
        CMP     R2, R4
        JMPR    ULT, pc_done
        JB      0FD2Eh.6, pc_done       ; clutch pressed: the clutch belongs to NLS
        MOV     R2, 0FDF8h
        AND     R2, #7
        JMPR    NZ, pc_done             ; LC, NLS or RAL active
        MOV     R5, #1
pc_done:
        RET

; ---- the overrun-cut gate (0A:A7BC). The stock cut comes when FD2E.13 or FD30.2 is set; a pops window holds it off
; and stays in fuelled overrun. Exits are the stock ones, with every register and PSW as they came. ----
pops_gate:
        JB      0FD2Eh.13, pg_request
        JB      0FD30h.2, pg_request
        JMPS    0Ah, 0B0F2h
pg_request:
        PUSH    0FF10h                  ; PSW
        MOV     [-R0], R2
        MOV     [-R0], R3
        MOV     [-R0], R4
        MOV     [-R0], R5
        CALLA   UC, pops_conditions
        JB      0FDF8h.3, pg_running
        JB      0FDF8h.4, pg_cut
        CMP     R5, #0
        JMPR    Z, pg_cut
        BSET    0FDF8h.3
        BSET    0FDF8h.4
        MOV     R3, #1
        CALLA   UC, pops_setting
        MOV     R3, R4
        SHL     R4, #3
        ADD     R4, R3
        ADD     R4, R3
        MOV     POPS_LEFT, R4
        MOVB    RL4, 807Fh
        MOVB    POPS_MIN, RL4
        JMPR    UC, pg_stay
pg_running:
        CMP     R5, #0
        JMPR    Z, pg_end
        MOV     R4, POPS_LEFT
        CMP     R4, #0
        JMPR    Z, pg_end
        MOVBZ   R4, POPS_MIN
        MOVBZ   R3, 807Fh
        MOV     R2, R4
        ADD     R2, #5
        CMP     R3, R2
        JMPR    UGE, pg_end             ; the engine is pushing, or the car is speeding up
        CMP     R3, R4
        JMPR    UGE, pg_stay
        MOVB    POPS_MIN, RL3
        JMPR    UC, pg_stay
pg_end:
        BCLR    0FDF8h.3
pg_cut:
        MOV     R5, [R0+]
        MOV     R4, [R0+]
        MOV     R3, [R0+]
        MOV     R2, [R0+]
        POP     0FF10h                  ; PSW
        JMPS    0Ah, 0A7C8h
pg_stay:
        MOV     R5, [R0+]
        MOV     R4, [R0+]
        MOV     R3, [R0+]
        MOV     R2, [R0+]
        POP     0FF10h                  ; PSW
        JMPS    0Ah, 0B0F2h

; ---- every 10 ms, from housekeeping (R4 is saved there): the lift is over when the engine leaves overrun; during
; a window, count it down and keep misfire detection suppressed, as LC, NLS and RAL do. ----
pops_tick:
        JB      0FD2Ch.11, pt_overrun
        JB      0FD2Ch.12, pt_overrun
        BCLR    0FDF8h.3
        BCLR    0FDF8h.4
        RET
pt_overrun:
        JNB     0FDF8h.3, pt_done
        MOV     R4, POPS_LEFT
        CMP     R4, #0
        JMPR    Z, pt_misfire
        SUB     R4, #1
        MOV     POPS_LEFT, R4
pt_misfire:
        MOV     R4, #100
        MOV     0E3B0h, R4
        BSET    0FD2Ah.12
pt_done:
        RET

; ---- the spark call (0A:D424, CALLS 0Bh, 5C84h): during a window the angle is the setting, written where the
; per-cylinder angles are taken from (E2B5, the encoding of ip_iga_puc). Knock retard is not applied in overrun. ----
pops_spark:
        JNB     0FDF8h.3, psk_stock
        JNB     0FD2Ch.11, psk_stock
        PUSH    0FF10h                  ; PSW
        MOV     [-R0], R3
        MOV     [-R0], R4
        MOV     R3, #2
        CALLA   UC, pops_setting
        MOVB    0E2B5h, RL4
        MOV     R4, #0
        MOVB    0E2B4h, RL4
        MOV     R4, [R0+]
        MOV     R3, [R0+]
        POP     0FF10h                  ; PSW
psk_stock:
        JMPS    0Bh, 05C84h

; ---- the AFR branch (0B:D434, JB FDF8.2): RAL first, as stock; during a window the rich target goes through the
; shared feature path, which takes the richer of it and the stock target and switches the lambda loop off. ----
pops_afr:
        JB      0FDF8h.2, pa_ral
        JNB     0FDF8h.3, pa_none
        JNB     0FD2Ch.11, pa_none
        PUSH    0FF10h                  ; PSW
        MOV     [-R0], R3
        MOV     [-R0], R4
        MOV     R3, #3
        CALLA   UC, pops_setting
        MOV     R12, R4                 ; the same value for both fuels, so the blend returns it
        MOV     R13, R4
        MOV     R4, [R0+]
        MOV     R3, [R0+]
        POP     0FF10h                  ; PSW
        JMPS    0Bh, 0D456h
pa_ral:
        JMPS    0Bh, 0D44Eh
pa_none:
        JMPS    0Bh, 0D464h

; ---- the throttle store (09:B138, MOV 86A4h, R4): during a window the opening is added to the pedal-map setpoint,
; saturating; the store then sets E, Z and N as the stock one does, with C and V as they came. ----
pops_throttle:
        JNB     0FDF8h.3, pth_store
        JNB     0FD2Ch.11, pth_store
        PUSH    0FF10h                  ; PSW
        MOV     [-R0], R2
        MOV     [-R0], R3
        MOV     R2, R4
        MOV     R3, #6
        CALLA   UC, pops_setting
        SHL     R4, #1
        ADD     R4, #(pops_throttle_add & 0FFFFh)
        EXTS    #0Ch, #1
        MOV     R4, [R4]
        ADD     R4, R2
        JMPR    NC, pth_sum
        MOV     R4, #0FFFFh
pth_sum:
        MOV     R3, [R0+]
        MOV     R2, [R0+]
        POP     0FF10h                  ; PSW
pth_store:
        MOV     86A4h, R4
        RETS

; 86A4 units added for each 0.1 deg TPS of opening: X * 2731 / 50 (2731 = 5.0 deg TPS as the logger shows it).
pops_throttle_add:
        DW      0, 54, 109, 163, 218, 273, 327, 382, 436, 491, 546, 600, 655, 710, 764, 819, 873, 928, 983, 1037, 1092, 1147, 1201, 1256, 1310, 1365, 1420, 1474, 1529, 1583, 1638, 1693, 1747, 1802, 1857, 1911, 1966, 2020, 2075, 2130, 2184, 2239, 2294, 2348, 2403, 2457, 2512, 2567, 2621, 2676, 2731
