; Torque guard and downshift blip (docs/live-overlay-v10.md).
; Groups 140..142 use v10_setting; state is in live_overlay_v10_pops.inc; group 139 is reserved.

; R4: opening in 0.2 deg TPS steps. Returns R4 in 86A4 units, approximately 109.25 per step
; (16387 at 30.0 deg TPS). Preserves every other register; changes PSW.
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

; the torque guard, every 10 ms from housekeeping right after pops_tick. While a pops window or a blip runs,
; GUARD is set when the monitoring's torque estimate (8013) is more than 10 above the permitted torque (86AD): both
; bytes are 2 Nm, so 20 Nm short of the monitoring's fault threshold, ip_tqi_dif_max_mon = 40 Nm (0D:2534). The guard
; only ever lowers an addition: pops_throttle leaves out the blip's addition while it is set.
; Changes R3, R4 and PSW (housekeeping saves R3 and R4).
guard_tick:
        JB      0FDF8h.3, gt_watch
        JB      BLIP_ON, gt_watch
        BCLR    GUARD
        RET
gt_watch:
        MOVBZ   R3, 86ADh
        ADD     R3, #10
        MOVBZ   R4, 8013h
        CMP     R4, R3
        JMPR    UGT, gt_on
        BCLR    GUARD
        RET
gt_on:
        BSET    GUARD
        RET

; the downshift blip, every 10 ms from housekeeping after guard_tick. With the clutch in and
; the pedal released, a sign that this is a downshift starts a blip toward the next gear down's rpm at the road speed:
; both brake switches, or a pedal tap (the pedal up past the tap threshold after the clutch went in, and back down
; within the tap length). It rises with the blip opening, holds the target band with the hold opening, and ends at
; the clutch, the pedal, the time or any other stop. pops_throttle adds BLIP_ADD while BLIP_ON is set.

; R4 = a switch byte in pops' byte-0 encoding. Return R2 = 1 when it is on, else 0: 1 always on; 2 while the cruise
; control's main switch is on and no speed is held; 80h..9Fh its CAN bit. Changes R3 and PSW; preserves R4.
switch_on:
        MOV     R2, #0
        JB      R4.7, so_can
        CMP     R4, #1
        JMPR    Z, so_on
        CMP     R4, #2
        JMPR    NZ, so_done
        JNB     0FD18h.1, so_done       ; the cruise control's main switch is off
        JB      0FD18h.2, so_done       ; cruise control is holding a speed
so_on:
        MOV     R2, #1
so_done:
        RET
so_can:
        JMPA    UC, can_bit_matches     ; shared with pops and the LC/NLS/RAL triggers; it returns R2

; R5 = the gear just left (2..5). Return R4 = the next gear down's rpm at the road speed in 807F units (32 rpm),
; capped at the maximum rpm: 847F x (142 byte gear - 2, 0.5 rpm per km/h) / 64, multiplied by shifts (no MD
; register, as pops). Changes R2, R3 and PSW; preserves R5.
blip_target:
        MOV     R2, #142
        MOV     R3, R5
        SUB     R3, #2
        CALLA   UC, v10_setting
        MOVBZ   R3, 847Fh
        MOV     R2, #0
bg_mul:
        JNB     R3.0, bg_next
        ADD     R2, R4
bg_next:
        SHL     R4, #1
        SHR     R3, #1
        JMPR    NZ, bg_mul
        SHR     R2, #6
        MOV     [-R0], R2
        MOV     R2, #140
        MOV     R3, #3
        CALLA   UC, v10_setting         ; the maximum rpm, 807F units
        MOV     R2, [R0+]
        CMP     R2, R4
        JMPR    UGT, bg_capped
        MOV     R4, R2
bg_capped:
        RET

; while a blip rises: R5 = the engine speed now (807F units). Updates BLIP_RATE, the rise per 10 ms tick x 16,
; filtered (rate - rate/4 + 4 x the rise since the last tick, a fall counting as none, at most 255), and BLIP_PREV.
; Return R4 = the rise expected within the blip lead (141 byte 6, 10 ms): rate x lead / 16, in 807F units, 0 with no
; lead. Preserves R2, R3 and R5..R15; changes PSW.
blip_lead:
        MOV     [-R0], R2
        MOV     [-R0], R3
        MOVBZ   R4, BLIP_PREV
        MOVB    BLIP_PREV, RL5
        MOV     R3, R5
        SUB     R3, R4                  ; the rise since the last tick
        JMPR    UGE, bk_rise
        MOV     R3, #0                  ; a fall counts as none
bk_rise:
        SHL     R3, #2
        MOVBZ   R2, BLIP_RATE
        MOV     R4, R2
        SHR     R4, #2
        SUB     R2, R4
        ADD     R2, R3                  ; rate - rate/4 + 4 x the rise
        CMP     R2, #255
        JMPR    ULE, bk_store
        MOV     R2, #255
bk_store:
        MOVB    BLIP_RATE, RL2
        MOV     R2, #141
        MOV     R3, #6
        CALLA   UC, v10_setting         ; the lead, 10 ms (0..30)
        MOVBZ   R2, BLIP_RATE
        MOV     R3, #0
bk_mul:
        JNB     R4.0, bk_next           ; rate x lead by shifts (no MD register, as pops)
        ADD     R3, R2
bk_next:
        SHL     R2, #1
        SHR     R4, #1
        JMPR    NZ, bk_mul
        SHR     R3, #4
        MOV     R4, R3
        MOV     R3, [R0+]
        MOV     R2, [R0+]
        RET

; Ends a running blip: the next throttle store has no blip addition. Changes R4.
blip_end:
        BCLR    BLIP_ON
        BCLR    BLIP_HOLD
        MOV     R4, #0
        MOV     BLIP_ADD, R4
        RET

; Preserves R2, R5 and R6; changes R3, R4 and PSW (housekeeping saves R3 and R4).
blip_tick:
        MOV     [-R0], R2
        MOV     [-R0], R5
        MOV     [-R0], R6
        JB      0FD2Eh.6, bt_clutch
        CALLA   UC, blip_end            ; 1. the clutch is up: no blip, and this press is over
        MOVB    BLIP_CL, RL4            ; R4 = 0
        BCLR    BLIP_USED
        BCLR    BLIP_ARMED
        BCLR    BLIP_TAPPING
        JMPA    UC, bt_done
bt_clutch:
        MOVB    RL4, BLIP_CL            ; 2. the clutch is in: count it, up to 255
        CMPB    RL4, #255
        JMPA    Z, bt_counted
        ADDB    RL4, #1
        MOVB    BLIP_CL, RL4
bt_counted:
        JNB     BLIP_ON, bt_idle
        JMPA    UC, bt_running
bt_idle:
        JNB     BLIP_USED, bt_free
        JMPA    UC, bt_done
bt_free:
        MOV     R6, #0                  ; 4. the tap; R6 = 1 when one completes this tick
        MOV     R2, #141
        MOV     R3, #4
        CALLA   UC, v10_setting         ; the tap threshold, E0FF units
        MOVBZ   R5, 0E0FFh              ; the pedal
        CMP     R5, R4
        JMPA    UGE, bt_up
        BSET    BLIP_ARMED              ; below it: a rise from here is a tap
        JNB     BLIP_TAPPING, bt_start
        BCLR    BLIP_TAPPING            ; back down within the tap length: a completed tap
        MOV     R6, #1
        JMPA    UC, bt_start
bt_up:
        JB      BLIP_TAPPING, bt_tapping
        JB      BLIP_ARMED, bt_rise
        JMPA    UC, bt_done             ; up since before the clutch went in: not a tap
bt_rise:
        BSET    BLIP_TAPPING
        MOV     R4, #1                  ; the rise counts as the tap's first tick
        MOVB    BLIP_TAP, RL4
        JMPA    UC, bt_done
bt_tapping:
        MOVB    RL4, BLIP_TAP
        ADDB    RL4, #1
        MOVB    BLIP_TAP, RL4
        MOV     R3, #5
        CALLA   UC, v10_setting         ; the tap length, 10 ms (R2 = 141)
        MOVBZ   R5, BLIP_TAP
        CMP     R5, R4
        JMPA    ULE, bt_done            ; still a tap
        BSET    BLIP_USED               ; held longer than a tap: the pedal is the driver's for this press
        BCLR    BLIP_TAPPING
        JMPA    UC, bt_done
bt_start:                               ; 5. the pedal is released: every condition, then a sign
        MOV     R2, #140
        MOV     R3, #0
        CALLA   UC, v10_setting
        CALLA   UC, switch_on
        CMP     R2, #0
        JMPA    Z, bt_done              ; the blip's switch is off
        MOVBZ   R4, 807Fh
        CMP     R4, #25
        JMPA    ULT, bt_done            ; under 800 rpm, a stalled engine is never blipped
        MOVBZ   R4, 8433h
        CMP     R4, #144
        JMPA    ULT, bt_done            ; the engine is under 60 deg C
        MOV     R2, #140
        MOV     R3, #2
        CALLA   UC, v10_setting
        MOVBZ   R3, 847Fh
        CMP     R3, R4
        JMPA    ULT, bt_done            ; below the minimum speed
        MOVBZ   R4, BLIP_CL
        CMP     R4, #200
        JMPA    UGT, bt_done            ; the clutch went in more than 2.0 s ago
        MOV     R4, 0FDF8h
        AND     R4, #0Fh
        JMPA    NZ, bt_done             ; LC, NLS, RAL or a pops window
        MOVBZ   R5, 81AEh               ; the gear just left
        CMP     R5, #2
        JMPA    ULT, bt_done
        CMP     R5, #5
        JMPA    UGT, bt_done
        MOV     R2, #141
        MOV     R3, #5
        SUB     R3, R5
        CALLA   UC, v10_setting         ; its downshift's switch, 141 byte 5 - gear
        CMP     R4, #0
        JMPA    Z, bt_done
        CALLA   UC, blip_target
        MOVB    BLIP_TGT, RL4
        MOVBZ   R3, 807Fh
        ADD     R3, #6
        CMP     R4, R3
        JMPA    ULT, bt_done            ; the target is within 192 rpm: nothing to blip
        MOV     R2, #140
        MOV     R3, #1
        CALLA   UC, v10_setting         ; the signs: bit 0 braking, bit 1 a tap
        JNB     R4.0, bt_tap_sign
        CMP     R5, #3
        JMPA    ULT, bt_tap_sign        ; braking never blips into 1st
        JNB     0FD2Eh.3, bt_tap_sign
        JB      0FD2Eh.4, bt_go         ; braking: both switches, so one stuck switch cannot start blips
bt_tap_sign:
        JB      R4.1, bt_tap_ok
        JMPA    UC, bt_done
bt_tap_ok:
        CMP     R6, #0
        JMPA    Z, bt_done
bt_go:
        BCLR    BLIP_HOLD
        MOV     R3, #4
        CALLA   UC, v10_setting         ; the maximum time, 0.1 s (R2 = 140)
        MOV     R5, R4
        SHL     R5, #3
        ADD     R5, R4
        ADD     R5, R4
        MOV     BLIP_LEFT, R5
        MOV     R3, #5
        CALLA   UC, v10_setting         ; the blip opening
        CALLA   UC, opening_units
        MOV     BLIP_ADD, R4
        MOVB    RL4, 807Fh              ; the rise rate starts from here
        MOVB    BLIP_PREV, RL4
        MOV     R4, #0
        MOVB    BLIP_RATE, RL4
        MOVB    RL4, #0FFh              ; the blip's first angle is whole, for a sharp blip;
        MOVB    BLIP_SPK, RL4           ; only a return from the cap ramps (psk_blip)
        BSET    BLIP_USED
        BSET    0FDF8h.4                ; a blip uses up this lift's pops
        BSET    BLIP_ON                 ; last: the throttle store sees a blip only with its values in place
        JMPA    UC, bt_done
bt_running:                             ; 3. a blip runs: the stops first
        MOV     R2, #141
        MOV     R3, #4
        CALLA   UC, v10_setting
        MOVBZ   R5, 0E0FFh
        CMP     R5, R4
        JMPA    UGE, bt_stop            ; the pedal: the driver has it
        MOV     R4, BLIP_LEFT
        CMP     R4, #0
        JMPA    Z, bt_stop              ; the time is up
        SUB     R4, #1
        MOV     BLIP_LEFT, R4
        MOV     R2, #140
        MOV     R3, #2
        CALLA   UC, v10_setting
        MOVBZ   R5, 847Fh
        CMP     R5, R4
        JMPA    ULT, bt_stop            ; below the minimum speed
        MOV     R3, #3
        CALLA   UC, v10_setting
        MOVBZ   R5, 807Fh
        CMP     R5, R4
        JMPA    UGE, bt_stop            ; at the maximum rpm
        MOV     R3, #0
        CALLA   UC, v10_setting
        CALLA   UC, switch_on
        CMP     R2, #0
        JMPA    Z, bt_stop              ; the switch is off
        MOV     R4, 0FDF8h
        AND     R4, #7
        JMPA    NZ, bt_stop             ; LC, NLS or RAL engaged
        MOVBZ   R5, 81AEh               ; the gear just left indexes 142: outside 2..5 the blip stops
        CMP     R5, #2
        JMPA    ULT, bt_stop
        CMP     R5, #5
        JMPA    UGT, bt_stop
        CALLA   UC, blip_target         ; the target follows the road speed
        MOVB    BLIP_TGT, RL4
        MOV     R6, R4                  ; R6 = the target, R5 = the engine speed (807F units)
        MOVBZ   R5, 807Fh
        JB      BLIP_HOLD, bt_hold
        CALLA   UC, blip_lead           ; R4 = the rise expected within the lead
        MOV     R3, R5
        ADD     R3, #6
        ADD     R3, R4
        CMP     R3, R6
        JMPA    UGE, bt_hold_begins     ; within 192 rpm of the target by the end of the lead
        MOV     R2, #140                ; the rise: the blip opening, read each tick so a live edit applies
        MOV     R3, #5
        CALLA   UC, v10_setting
        CALLA   UC, opening_units
        MOV     BLIP_ADD, R4
        JMPA    UC, bt_misfire
bt_hold_begins:
        BSET    BLIP_HOLD               ; within 192 rpm of the target: the hold starts from the hold opening
        MOV     R2, #140
        MOV     R3, #6
        CALLA   UC, v10_setting
        CALLA   UC, opening_units
        MOV     BLIP_ADD, R4
bt_hold:
        MOV     R3, R6
        ADD     R3, #5
        CMP     R5, R3
        JMPA    ULE, bt_hold_low
        MOV     R4, #0                  ; above the target plus 160 rpm: no addition
        MOV     BLIP_ADD, R4
        JMPA    UC, bt_misfire
bt_hold_low:
        CMP     R5, R6
        JMPA    UGE, bt_misfire         ; in the band: unchanged
        MOV     R2, #140
        MOV     R3, #6
        CALLA   UC, v10_setting         ; below the target: the hold opening
        CALLA   UC, opening_units
        MOV     BLIP_ADD, R4
bt_misfire:
        MOV     R4, #100                ; misfire detection stays suppressed, as for pops, LC and NLS
        MOV     0E3B0h, R4
        BSET    0FD2Ah.12
        JMPA    UC, bt_done
bt_stop:
        CALLA   UC, blip_end
bt_done:
        MOV     R6, [R0+]
        MOV     R5, [R0+]
        MOV     R2, [R0+]
        RET

; the in-cut re-entry check (0A:AAA0, BCMP FD9Ah.11, FD48h.2): in a running overrun cut with the pedal released, the
; stock handler refuels only below the re-entry rpm (81AB). A blip needs the fuel now, so while one runs this check
; takes the stock re-entry at 0A:AABA (fuelled overrun, or idle below 88E0), after the stock BCMP and BMOV, so
; FD9A.11 and the flags are what a stock pass leaves at 0A:AAA8. Otherwise the displaced instruction runs and the stock
; code continues with its flags. Every register is as it came.
blip_reentry:
        JNB     BLIP_ON, br_stock
        BCMP    0FD9Ah.11, 0FD48h.2
        BMOV    0FD9Ah.11, 0FF10h.2     ; PSW.2, as the stock code at 0A:AAA4
        JMPS    0Ah, 0AABAh
br_stock:
        BCMP    0FD9Ah.11, 0FD48h.2
        JMPS    0Ah, 0AAA4h
