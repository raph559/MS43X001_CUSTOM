; V10's pops stabs, torque guard and downshift blip (docs/live-overlay-v10.md). The state is at the top of the pops
; include; the settings are groups 139..142, read through v10_setting.

; ---- the pops stabs: after the load, the throttle addition alternates a stab (the opening plus the stab size) and a
; gap (the opening), on the 10 ms tick. pops_throttle adds the stab's extra while POPS_STAB is set. ----

; R4 = an opening in 0.2 deg TPS steps. Return R4 = its 86A4 units: 54.625 (2X) by V8.5's shifts, 16387 at 30.0 deg
; TPS. Preserves every other register; changes PSW.
opening_units:
        MOV     [-R0], R5
        MOV     R5, R4
        SHL     R5, #6
        MOV     R4, R5                  ; 32 (2X)
        SHR     R5, #1
        ADD     R4, R5                  ; + 16 (2X)
        SHR     R5, #2
        ADD     R4, R5                  ; + 4 (2X)
        SHR     R5, #1
        ADD     R4, R5                  ; + 2 (2X)
        SHR     R5, #2
        ADD     R4, R5                  ; + (2X) / 2
        SHR     R5, #2
        ADD     R4, R5                  ; + (2X) / 8
        MOV     R5, [R0+]
        RET

; From pops_gate when a window starts: the load begins. Preserves every register; changes PSW.
stab_start:
        MOV     [-R0], R4
        MOV     R4, #0
        MOV     POPS_T, R4
        MOVB    POPS_PH, RL4
        BCLR    POPS_STAB
        MOV     R4, [R0+]
        RET

; From pops_tick every 10 ms while a window runs and every condition holds. After 10 x the load time (0.1 s), each
; phase lasts its own setting: a stab the stab length, a gap the gap. A stab size of 0 means no stab. Changes R2..R5
; and PSW (pops_tick saves R2 and R5, housekeeping R3 and R4).
stab_tick:
        MOV     R4, POPS_T
        CMP     R4, #0FFFFh
        JMPR    Z, st_counted
        ADD     R4, #1
        MOV     POPS_T, R4
st_counted:
        MOV     R2, #139
        MOV     R3, #1
        CALLA   UC, v10_setting         ; the stab size
        CMP     R4, #0
        JMPR    Z, st_off
        MOV     R3, #0
        CALLA   UC, v10_setting         ; the load time
        MOV     R5, R4
        SHL     R5, #3
        ADD     R5, R4
        ADD     R5, R4                  ; 10 X ticks
        MOV     R4, POPS_T
        CMP     R4, R5
        JMPR    ULE, st_off             ; still loading
        MOVB    RL4, POPS_PH
        JMPR    NZ, st_count
        MOV     R3, #2                  ; a stab follows the load or a gap
        JNB     POPS_STAB, st_toggle
        MOV     R3, #3                  ; a gap follows a stab
st_toggle:
        BMOVN   POPS_STAB, POPS_STAB
        CALLA   UC, v10_setting         ; the new phase's length, 10 ms
        MOVB    POPS_PH, RL4
st_count:
        MOVB    RL4, POPS_PH
        SUBB    RL4, #1
        MOVB    POPS_PH, RL4
        RET
st_off:
        BCLR    POPS_STAB
        RET
