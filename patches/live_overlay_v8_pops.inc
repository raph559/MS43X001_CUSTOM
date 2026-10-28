; Pops on lift-off (docs/live-overlay-v8.md): settings group 138, its limits and the routines that use it.

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
