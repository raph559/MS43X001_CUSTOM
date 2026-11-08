"""V10.1: the V9 overlay plus pops' throttle stabs and the downshift blip. Generates the V10 assembly from V9's.

V10.1 (2026-11-05, after the first car test) is V10 with new defaults, the rise allowed once stabbing (139 byte 4),
the blip lead (141 byte 6), a pops AFR target down to 7.4 and three minors from V10's review. The header's version word
is 010Ah: the low byte stays 10, so every V10 rule holds, and the high byte is the minor (V8.5's way).

V10.3 (2026-11-08, the owner: "remove the stab logic from the pops") takes the stabs out: a pops window holds pops' own
opening (138 byte 6) for its whole time and ends at V8's 160 rpm rise, as V9's. Group 139 stays in the catalogue as a
reserved group, every byte limited to 0, so its ID and the groups after it keep their places; its flashed bytes are 0.
The stab count in the log (09FBFh) is gone. Everything else is V10.2's: the blip, its cap, the real AFRs."""
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]

# Groups 138..142 are 8 bytes each from 0C:FF80 (file 0x4FF80): pops, then V10's four (catalogue page 33h).
DEFAULTS_FILE = 0x4FF80
# V10.1's defaults (owner, 2026-11-05: "put it by default plz", "do it by default"): pops at -23.625 deg, AFR 9.99,
# 4,000 rpm and 3.0 deg TPS (V10.3: no stabs); a 30.0 deg TPS blip at +20.25 deg
# (2026-11-06: "Make it the default"), a 150 ms lead.
POPS_DEFAULTS = bytes([0x00, 0x28, 0x00, 0x46, 0x7D, 0x9E, 0x1E, 0x14])    # V10.2: byte 3 is the real AFR x 10, 7.0
STAB_DEFAULTS = bytes(8)                      # V10.3: group 139 is reserved
BLIP_DEFAULTS = bytes([0x00, 0x03, 0x1E, 0xBB, 0x0F, 0x96, 0x19, 0x75])
GEARS_DEFAULTS = bytes([0x01, 0x01, 0x01, 0x00, 0x15, 0x28, 0x0F, 0])
RATIO_DEFAULTS = bytes([0xE2, 0x86, 0x59, 0x43, 0, 0, 0, 0])
DEFAULTS = POPS_DEFAULTS + STAB_DEFAULTS + BLIP_DEFAULTS + GEARS_DEFAULTS + RATIO_DEFAULTS

GROUPS = [dict(id=139, name="reserved", address=0xCFF88, bytes=8, flags=2, fields=0),
          dict(id=140, name="blip", address=0xCFF90, bytes=8, flags=2, fields=8),
          dict(id=141, name="blip_gears", address=0xCFF98, bytes=8, flags=2, fields=7),
          dict(id=142, name="blip_ratios", address=0xCFFA0, bytes=8, flags=2, fields=4)]

# V10 reuses V8's gate, spark and throttle hooks and housekeeping, and adds one site (Task 7's finding): the in-cut handler
# (0A:A9EE) re-checks the engine speed at 0A:AAA0 and refuels only below the re-entry rpm, so a blip that starts during a
# running cut takes the stock re-entry at once (file offset: name, the donor's instruction).
PINNED = {0x2AAA0: ("in-cut re-entry check", "2A244D2B"),
          0x3D4D4: ("AFR display join (V10.2)", "C2FCB891"),
          0x70E14: ("injector flow, the X001 release's (V10.2)", "E100"),
          0x7DE64: ("start pre-injection, stock X001 again (V10.2)", "D0FB9DC11F854358763E7825C317D010")}

HOOKS = """
        ORG     0AAAA0h
        JMPS    0Ch, blip_reentry & 0FFFFh
        ORG     0BD4D4h
        JMPS    0Ch, pops_fuel & 0FFFFh
; V10.2, the owner's choice (2026-11-08): the start's pre-injection, ip_tipr_cst__tco (8 cells over coolant, 0.00533 ms),
; back to stock X001; the car file has it x 1.6 at every temperature (23.0 ms at 90 deg C, stock 14.4).
        ORG     0FDE64h
        DB      062h, 09Dh, 002h, 079h, 033h, 053h, 02Ah, 037h, 00Ah, 027h, 06Bh, 017h, 0DAh, 00Eh, 082h, 00Ah
; V10.2, the owner's choice (2026-11-08, the injectors stock): c_inj_flow, 16 bits little-endian, cm3/min, back to the
; X001 release's 237; the car file's 225 came with an E85 edit and adds 5.3 % fuel everywhere on petrol.
        ORG     0F0E14h
        DB      0EDh, 000h
"""

# V10.2, real AFRs: at the shared rich path's join, during a window that pops_afr forced (91A0 = 2032), the enrichment
# becomes the real pops AFR's, or the car file's own made real when richer, and the logged target the real mixture;
# every other pass with a rich target makes that target real (every AFR real, spec 6b), its logged number as stock.
POPS_FUEL = """
; ---- V10.2, the AFR display join (0B:D4D4, MOVBZ R12, 91B8h): both branches of the shared rich path meet here, 91A0
; set (0B:D4BC, L = (X - 128) x 16, with FD9A.10) or cleared. When pops_afr forced the rich path in this pass (a window,
; the pops AFR below 14.7, so 91A0 holds the forced 2032), the enrichment becomes the real AFR's, (147 - A) x 4096 / A,
; or the car file's own made real when that is richer, and 91B9, the logged target, the real mixture: 91B8 x 4096 /
; (4096 + 91A0). Every other pass with a rich target makes it real (every AFR real): 91B9 first, from L, as the stock
; display, so its numbers stay as today, then 91A0 = afr_real(L). MULU and DIVLU as the stock 0D:194C uses them at
; 0B:D4E0 in the same pass; R4, R5, R12, R13 and MD are scratch there, and R5 and R12 are left as the stock code leaves
; them. Without a rich target the displaced instruction runs. ----
pops_fuel:
        JNB     0FD9Ah.10, pf_plain     ; no rich target in this pass
        JNB     0FDF8h.3, pf_every
        JNB     0FD2Ch.11, pf_every
        JB      0FDF8h.2, pf_every
        MOV     R12, 091A0h
        CMP     R12, #2032
        JMPR    NZ, pf_every            ; not forced by pops_afr in this pass
        MOV     [-R0], R3
        MOV     R3, #3
        CALLA   UC, pops_setting        ; A, the real AFR x 10, 50..147
        MOV     R3, [R0+]
        CMP     R4, #147
        JMPR    UGE, pf_every
        MOV     R12, #147
        SUB     R12, R4
        MOV     R13, #4096
        MULU    R12, R13                ; MD = (147 - A) x 4096
        DIVLU   R4                      ; / A: at most 7,946 at 5.0
        MOV     R12, 0FE0Eh             ; MDL
        MOVBZ   R13, POPS_XSTOCK
        CMP     R13, #128
        JMPR    ULE, pf_store           ; the car file's byte at lambda 1 or leaner adds nothing
        SUB     R13, #128
        SHL     R13, #4                 ; (X - 128) x 16, as the shared path stores it
        CALLA   UC, afr_real            ; made real, as every target
        CMP     R13, R12
        JMPR    ULE, pf_store
        MOV     R12, R13                ; the car file's own target is the richer
pf_store:
        MOV     091A0h, R12
        MOVBZ   R13, 091B8h
        MOV     R4, #4096
        MULU    R13, R4                 ; MD = 91B8 x 4096
        ADD     R12, #4096
        DIVLU   R12                     ; / (4096 + 91A0): the real mixture
        MOV     R4, 0FE0Eh              ; MDL
        CMP     R4, #255
        JMPR    ULE, pf_shown
        MOV     R4, #255
pf_shown:
        MOVB    091B9h, RL4
pf_done:
        MOV     R5, #1000h
        MOVBZ   R12, 091B8h
        JMPS    0Bh, 0D4E8h
pf_every:                               ; every AFR real
        MOVBZ   R12, 091B8h
        MOV     R13, #1000h
        SUB     R13, 091A0h
        CALLS   0Dh, 0194Ch             ; the stock display from L (0B:D4D8..D4E0)
        MOVB    091B9h, RL4
        MOV     R13, 091A0h
        CALLA   UC, afr_real
        MOV     091A0h, R13
        JMPR    UC, pf_done
pf_plain:
        MOVBZ   R12, 091B8h
        JMPS    0Bh, 0D4D8h

; V10.2: R13 = L, an enrichment as the shared rich path stores it ((X - 128) x 16, -2048..2032). Return R13 = the real
; AFR's, L x 4096 / (4096 - L), signed and truncated toward zero: the byte the XDF shows as AFR 14.7 x (384 - X) / 256
; then gives that AFR. Changes R4, MD and PSW.
afr_real:
        MOV     R4, R13
        JB      R13.15, ar_lean
        MOV     R13, #4096
        MULU    R4, R13                 ; MD = L x 4096
        SUB     R13, R4                 ; 4096 - L, 2064..4096
        DIVLU   R13
        MOV     R13, 0FE0Eh             ; MDL, at most 4,032
        RET
ar_lean:
        NEG     R4                      ; -L
        MOV     R13, #4096
        MULU    R4, R13                 ; MD = -L x 4096
        ADD     R13, R4                 ; 4096 - L, 4112..6144
        DIVLU   R13
        MOV     R13, 0FE0Eh             ; MDL, at most 1,365
        NEG     R13
        RET
"""

# V10's state, ahead of the pops include that is the first to use it: pool A logical 668..679 (through DPP2), below the
# watch record, and FDF8 bits 7..13, which no code in the car file or in V9 uses.
V10_STATE = """; V10's state (docs/live-overlay-v10.md): pool A logical 668..679, through DPP2, and FDF8 bits 7..13; FDF8.14 and
; FDF8.15 belong to the car file.
                                        ; 09F9Ch: free (V10.2's stab clock)
BLIP_ADD        EQU     09F9Eh          ; word: the blip's throttle addition now, 86A4 units
BLIP_LEFT       EQU     09FA0h          ; word: 10 ms ticks left in the blip
BLIP_SPK        EQU     09FA2h          ; byte: while a blip runs, the spark angle it wrote last, E2B5's encoding, FFh
                                        ; until its first (V10.2)
BLIP_CL        EQU     09FA3h          ; byte: 10 ms ticks since the clutch went in, saturating; 0 while it is released
BLIP_TGT        EQU     09FA4h          ; byte: the blip's target, 807F units (32 rpm)
BLIP_TAP        EQU     09FA5h          ; byte: 10 ms ticks since the pedal rose past the tap threshold
BLIP_PREV       EQU     09FA6h          ; byte: 807F one tick ago, while a blip rises (V10.1)
BLIP_RATE       EQU     09FA7h          ; byte: the rise per 10 ms tick x 16, filtered, while a blip rises (V10.1)
POPS_XSTOCK     EQU     09FA7h          ; byte: in a pops window, the car file's own target byte (V10.2); shares BLIP_RATE,
                                        ; as no blip runs in a window and every blip's start resets the rate
                                        ; 09FBFh: free (V10.2's stab count)
SPK_RAMP        BIT     0FDF8h.7        ; V10.3: the spark comes back from the blip's last angle, ramped (V10.2's stab bit)
BLIP_ON         BIT     0FDF8h.8        ; a blip is running
BLIP_USED       BIT     0FDF8h.9        ; this clutch press has had its blip, or the pedal is the driver's for it
BLIP_ARMED      BIT     0FDF8h.10       ; the pedal has been below the tap threshold since the clutch went in
BLIP_TAPPING    BIT     0FDF8h.11       ; the pedal rose past the threshold after the clutch went in
BLIP_HOLD       BIT     0FDF8h.12       ; the blip has reached its target band (the hold phase)
GUARD           BIT     0FDF8h.13       ; the torque guard is acting

"""


def _replace(text, old, new, count=1):
    if text.count(old) != count:
        raise SystemExit(f"V10 generator: expected {count} of {old[:60]!r}, found {text.count(old)}")
    return text.replace(old, new)


def _db(data):
    return "        DB      " + ", ".join(f"0{b:02X}h" for b in data) + "\n"


def prepare(image):
    """Write patches/live_overlay_v10.asm and its helpers from the V9 sources (run V9's generator first)."""
    if image[DEFAULTS_FILE + 8:DEFAULTS_FILE + 40] != b"\xFF" * 32:
        raise SystemExit("V10 generator: the new groups' defaults are not free in the donor")
    source = (ROOT / "patches/live_overlay_v9.asm").read_text()
    source = source.replace("protocol 9", "protocol 10").replace("docs/live-overlay-v9.md", "docs/live-overlay-v10.md")
    source = _replace(source, "OVL_VERSION     EQU     9 ", "OVL_VERSION     EQU     10")
    source = _replace(source, "N_TABLES        EQU     139", "N_TABLES        EQU     143")
    source = _replace(source, "        DW      OVL_VERSION\n", "        DW      OVL_VERSION + 0300h     ; V10.3: the high byte is the minor\n")
    source = source.replace("C0D9", "C0DA")
    # Pool A keeps its last 36 bytes: V10's state (041F9C..041FA7), the watch record and pops' state. No allocation may
    # reach logical offset 668, and the free space reported to the app is 896 bytes.
    source = _replace(source, "        CMP     R7, #680\n        JMPA    UGT, bad_range\nld_boundary_ok:",
                      "        CMP     R7, #668\n        JMPA    UGT, bad_range\nld_boundary_ok:")
    source = _replace(source, "        MOV     R9, #(COPY_BYTES-24)\n", "        MOV     R9, #(COPY_BYTES-36)\n")
    source = _replace(source, "live_overlay_v9_feature_helpers.inc", "live_overlay_v10_feature_helpers.inc")
    source = _replace(source, '"live_overlay_v9_pops.inc"', '"live_overlay_v10_pops.inc"')
    source = _replace(source, "        DW      0033h, 03F80h, 8, 2 ; 138 pops\n",
                      "        DW      0033h, 03F80h, 8, 2 ; 138 pops\n"
                      "        DW      0033h, 03F88h, 8, 2 ; 139 reserved (V10.3: no stabs)\n"
                      "        DW      0033h, 03F90h, 8, 2 ; 140 downshift blip\n"
                      "        DW      0033h, 03F98h, 8, 2 ; 141 downshift blip: gears and tap\n"
                      "        DW      0033h, 03FA0h, 8, 2 ; 142 downshift blip: gear ratios\n")
    # V10's code goes after V9's, in the free flash below the defaults.
    source = _replace(source, '        INCLUDE "live_overlay_v9_triggers.inc"\n        IF      $ > 0CFF80h\n'
                              '        ERROR   "the V9 code overruns the pops defaults"\n',
                      '        INCLUDE "live_overlay_v9_triggers.inc"\n        INCLUDE "live_overlay_v10_groups.inc"\n'
                      '        IF      $ > 0CFF80h\n        ERROR   "the V10 code overruns the pops defaults"\n')
    source = _replace(source, "; The flashed pops settings: off, 2.0 s, -15.0 deg, 11.5 AFR (184), 1,600 rpm, 70.5 deg C, "
                              "no throttle, 20 km/h.\n",
                      "; The flashed pops settings: off, 4.0 s, -23.625 deg, a real AFR of 7.0 (70), 4,000 rpm, 70.5 deg C, "
                      "3.0 deg TPS, 20 km/h.\n")
    source = _replace(source, "pops_defaults:\n        DB      000h, 014h, 017h, 0B8h, 032h, 09Eh, 000h, 014h\n",
                      "pops_defaults:\n" + _db(POPS_DEFAULTS)
                      + "; 139 reserved (V10.3: the stabs are gone).\n"
                      + "stab_defaults:\n" + _db(STAB_DEFAULTS)
                      + "; 140 downshift blip: off, braking or tap, 30 km/h, 5,984 rpm, 1.5 s, 30.0 and 5.0 deg TPS, +20.25 deg.\n"
                      + "blip_defaults:\n" + _db(BLIP_DEFAULTS)
                      + "; 141 its gears and tap: 5th-4th, 4th-3rd, 3rd-2nd on, 2nd-1st off; 9.8 deg PVS within 0.4 s; a 150 ms lead.\n"
                      + "gears_defaults:\n" + _db(GEARS_DEFAULTS)
                      + "; 142 its ratios, 0.5 rpm per km/h: 1st 113.0, 2nd 67.0, 3rd 44.5, 4th 33.5.\n"
                      + "ratio_defaults:\n" + _db(RATIO_DEFAULTS))

    helpers = (ROOT / "patches/live_overlay_v9_feature_helpers.inc").read_text()
    # Groups 138..142: byte 17 of the allocation index, bit (ID - 136); their flash defaults are 8 bytes apart from 3F80h.
    helpers = _replace(helpers, "        CMP     R2, #138\n        JMPR    Z, fa_bitmap_pops\n",
                       "        CMP     R2, #138\n        JMPR    UGE, fa_bitmap_pops\n")
    helpers = _replace(helpers, "fa_bitmap_pops:\n        EXTP    #3, #1\n        MOVBZ   R4, W_BITMAP+17\n        JNB     R4.2, fa_flash\n",
                       "fa_bitmap_pops:\n        EXTP    #3, #1\n        MOVBZ   R4, W_BITMAP+17\n        MOV     R3, R2\n"
                       "        SUB     R3, #136\n        SHR     R4, R3\n        JNB     R4.0, fa_flash\n")
    helpers = _replace(helpers, "fa_flash:\n        CMP     R2, #138\n        JMPR    NZ, fa_flash_x001\n        MOV     R3, #3F80h\n",
                       "fa_flash:\n        CMP     R2, #138\n        JMPR    ULT, fa_flash_x001\n        MOV     R3, R2\n"
                       "        SUB     R3, #138\n        SHL     R3, #3\n        ADD     R3, #3F80h\n")
    helpers = _replace(helpers, "feature_validate:\n        CMP     R2, #138\n        JMPA    Z, pops_validate\n",
                       "feature_validate:\n        CMP     R2, #138\n        JMPA    Z, pops_validate\n"
                       "        JMPA    UGT, v10_validate\n")
    helpers = _replace(helpers, "feature_write_validate:\n        CMP     R2, #138\n        JMPR    Z, fwv_group\n",
                       "feature_write_validate:\n        CMP     R2, #138\n        JMPR    UGE, fwv_group\n")
    helpers = helpers.replace("; R2 = group ID, R3 = byte within its 8-byte span.",
                              "; R2 = group ID (124..126, 138..142), R3 = byte within its 8-byte span.")

    source += HOOKS
    pops = V10_STATE + (ROOT / "patches/live_overlay_v9_pops.inc").read_text()
    # Task 4, the torque guard: housekeeping runs it right after pops_tick, every 10 ms.
    source = _replace(source, "        CALLA   UC, pops_tick\n        CALLA   UC, watch_quiet\n",
                      "        CALLA   UC, pops_tick\n        CALLA   UC, guard_tick\n        CALLA   UC, watch_quiet\n")
    # Task 5, the blip: housekeeping runs it right after the guard, every 10 ms.
    source = _replace(source, "        CALLA   UC, guard_tick\n", "        CALLA   UC, guard_tick\n        CALLA   UC, blip_tick\n")
    # The blip's code and the torque guard (V10.3: the stabs are gone from it).
    source = _replace(source, '        INCLUDE "live_overlay_v10_groups.inc"\n',
                      '        INCLUDE "live_overlay_v10_groups.inc"\n        INCLUDE "live_overlay_v10_blip.inc"\n')
    # V10.2: the pops AFR target is the real AFR x 10, 5.0..14.7 in petrol AFR (a lambda, A/147, on either fuel). pops_afr
    # keeps the car file's byte and forces the shared rich path; pops_fuel writes the real enrichment at the path's join.
    pops = _replace(pops, "        DB      128, 210        ; 3 AFR target, the firmware's: lambda = 1.5 - X/256 (128 = 14.7, "
                          "184 = 11.5, 210 = 10.0)\n",
                    "        DB      50, 147         ; 3 AFR target, the real AFR x 10 in petrol AFR (V10.2): 50 = 5.0, "
                    "147 = 14.7\n")
    pops = _replace(pops, "        MOV     R12, R4                 ; the same value for both fuels, so the blend returns it\n"
                          "        MOV     R13, R4\n",
                    "        MOV     R12, R6                 ; V10.2: at 14.7 the car file's own target, as stock\n"
                    "        CMP     R4, #147\n        JMPR    UGE, pa_pass\n"
                    "        MOVB    POPS_XSTOCK, RL6        ; the car file's byte, for pops_fuel's richer-of rule\n"
                    "        MOV     R12, #255               ; forces the shared rich path: the lambda loop off, 91A0 = 2032\n"
                    "pa_pass:\n        MOV     R13, R12                ; the same value for both fuels, so the blend returns it\n")
    pops += POPS_FUEL
    # V10.3: no stabs. The window keeps V9's rise rule (160 rpm) in the tick and the gate, its own opening throughout,
    # and 09FBFh stays reserved.
    # Task 3, the brake: either switch (FD2E.3 the brake light switch, FD2E.4 the brake test switch) blocks a window and
    # ends a running one, and braking in overrun uses up the lift (FDF8.4). Out of overrun the lift is re-armed only with
    # the clutch released, so a tap with the clutch in does not bring the pops back (owner, 2026-11-05).
    pops = _replace(pops, "        JB      0FD2Eh.6, pc_done       ; clutch pressed: the clutch belongs to NLS\n",
                    "        JB      0FD2Eh.6, pc_done       ; clutch pressed: the clutch belongs to NLS\n"
                    "        JB      0FD2Eh.3, pc_done       ; braking: either brake switch\n"
                    "        JB      0FD2Eh.4, pc_done\n")
    pops = _replace(pops, "        BCLR    0FDF8h.3\n        BCLR    0FDF8h.4\n        RET\n"
                          "pt_overrun:\n        JNB     0FDF8h.3, pt_done\n",
                    "        BCLR    0FDF8h.3\n"
                    "        JB      0FD2Eh.6, pt_rearm_done ; the clutch in: not a press that re-arms the pops\n"
                    "        BCLR    0FDF8h.4\npt_rearm_done:\n        RET\n"
                    "pt_overrun:\n        JB      0FD2Eh.3, pt_brake\n        JNB     0FD2Eh.4, pt_no_brake\n"
                    "pt_brake:\n        BSET    0FDF8h.4                ; braking uses up this lift's pops\n"
                    "        BCLR    0FDF8h.3\n        RET\n"
                    "pt_no_brake:\n        JNB     0FDF8h.3, pt_done\n")
    # Task 6, the blip's outputs. A pops window and a blip never overlap (the blip needs FDF8.3 clear, and the clutch
    # ends a window), so each hook checks the blip first. The throttle store adds BLIP_ADD while GUARD is clear; the gate
    # holds the overrun cut off, with every register as it came; the spark call fires at 140's angle in fuelled overrun.
    pops = _replace(pops, "pops_throttle:\n        JNB     0FDF8h.3, pth_store\n",
                    "pops_throttle:\n        JB      BLIP_ON, pth_blip\n        JNB     0FDF8h.3, pth_store\n")
    pops = _replace(pops, "pth_store:\n        MOV     86A4h, R4\n        RETS\n",
                    "pth_store:\n        MOV     86A4h, R4\n        RETS\n"
                    "pth_blip:\n        JB      GUARD, pth_store\n        PUSH    0FF10h                  ; PSW\n"
                    "        ADD     R4, BLIP_ADD\n        JMPR    NC, pth_blip_sum\n        MOV     R4, #0FFFFh\n"
                    "pth_blip_sum:\n        POP     0FF10h                  ; PSW\n        MOV     86A4h, R4\n        RETS\n")
    pops = _replace(pops, "pg_request:\n        PUSH    0FF10h                  ; PSW\n",
                    "pg_request:\n        JNB     BLIP_ON, pg_pops\n        JMPS    0Ah, 0B0F2h             ; a blip holds the overrun cut off\n"
                    "pg_pops:\n        PUSH    0FF10h                  ; PSW\n")
    pops = _replace(pops, "pops_spark:\n        JNB     0FDF8h.3, psk_stock\n",
                    "pops_spark:\n        JB      BLIP_ON, psk_blip\n        JNB     0FDF8h.3, psk_stock\n")
    # V10.2, the cap: above the blip's target the spark is 141 byte 7's angle (flashed -23.625 deg), so the air already
    # in the intake stops the climb instead of driving the rpm past the target (2026-11-07 log: +650 rpm at the peak).
    # The spark call arms each coil's charge for the angle before it, so an advance written while a coil charges cuts that
    # charge by the advance's time (the cap's 44 deg release at 2,624 rpm left cylinder 4 0.21 ms of 2.35, igcfb_5
    # detected): after the cap, an advance rises at most 807F / 4 steps of 0.375 deg a spark from the last angle the blip
    # wrote, under 0.5 ms of a charge at any speed, as the stock overrun ramp (0A:D3DE) does 2.5 deg a spark; a retard, the
    # cap, is whole at once. A blip's start is whole (bt_go leaves FFh): the owner wants it "very sharp" (2026-11-08), as
    # V10.1's, so its first firing may lose its charge (one cylinder, 0.04 ms from the car file's -12.75 deg). Above the
    # target the angle is the lower of the cap and the blip angle (the review, 2026-11-08): a cap set above the blip
    # angle would otherwise add advance where it should take it away; at or above the blip angle the cap is off.
    pops = _replace(pops, "psk_stock:\n        JMPS    0Bh, 05C84h\n",
                    "psk_stock:\n        JMPS    0Bh, 05C84h\n"
                    "psk_blip:\n        JNB     0FD2Ch.11, psk_stock\n        PUSH    0FF10h                  ; PSW\n"
                    "        MOV     [-R0], R2\n        MOV     [-R0], R3\n        MOV     [-R0], R4\n        MOV     [-R0], R5\n"
                    "        MOV     R2, #140\n        MOV     R3, #7                  ; the blip's own spark angle\n"
                    "        CALLA   UC, v10_setting\n"
                    "        MOVB    RL5, 807Fh\n        CMPB    RL5, BLIP_TGT\n"
                    "        JMPR    ULE, psk_angle          ; at or below the target\n"
                    "        MOV     R5, R4\n"
                    "        MOV     R2, #141                ; V10.2: above it, the cap angle (141 byte 7)\n"
                    "        CALLA   UC, v10_setting\n"
                    "        CMP     R4, R5\n        JMPR    ULE, psk_angle\n"
                    "        MOV     R4, R5                  ; a cap above the blip angle is off (V10.2's review)\n"
                    "psk_angle:\n"
                    "        MOVBZ   R3, 807Fh               ; V10.2: the most advance now, the last angle + 807F / 4\n"
                    "        SHR     R3, #2\n        MOVBZ   R5, BLIP_SPK\n        ADD     R3, R5\n"
                    "        CMP     R4, R3\n        JMPR    ULE, psk_write\n        MOV     R4, R3\n"
                    "psk_write:\n        MOVB    BLIP_SPK, RL4\n        MOVB    0E2B5h, RL4\n"
                    "psk_written:\n        MOV     R4, #0\n        MOVB    0E2B4h, RL4\n"
                    "        MOV     R5, [R0+]\n        MOV     R4, [R0+]\n        MOV     R3, [R0+]\n        MOV     R2, [R0+]\n"
                    "        POP     0FF10h                  ; PSW\n"
                    "        JMPS    0Bh, 05C84h\n")

    # V10.3, the hand-over (the V10.2 review's pedal case, found again on 2026-11-08 at another phase): when the stock code
    # takes the spark back from the blip, the pedal pressed (out of overrun) or the blip over, its angle could jump 9 deg
    # at once from the cap's, and an advance written while a coil charges cuts that charge (1.78 ms of 2.34). Each blip
    # write sets SPK_RAMP; after the blip, the stock angle rises at most 807F / 4 steps a spark from the last angle
    # written, as the cap's return does, until it reaches the stock one; a retard is whole at once. Below 25 x 32 rpm the
    # ramp ends (a stray bit at power-up cannot hold a start's advance back). A pops window fires its own angle.
    pops = _replace(pops, "pops_spark:\n        JB      BLIP_ON, psk_blip\n        JNB     0FDF8h.3, psk_stock\n"
                          "        JNB     0FD2Ch.11, psk_stock\n        PUSH    0FF10h                  ; PSW\n",
                    "pops_spark:\n        JB      BLIP_ON, psk_blip\n        JNB     0FDF8h.3, psk_ramp\n"
                    "        JNB     0FD2Ch.11, psk_ramp\n        BCLR    SPK_RAMP                ; V10.3: a pops window fires its own angle\n"
                    "        PUSH    0FF10h                  ; PSW\n")
    pops = _replace(pops, "psk_blip:\n        JNB     0FD2Ch.11, psk_stock\n",
                    "psk_blip:\n        JNB     0FD2Ch.11, psk_ramp     ; V10.3: out of overrun the stock angle comes back ramped\n")
    pops = _replace(pops, "psk_write:\n        MOVB    BLIP_SPK, RL4\n",
                    "psk_write:\n        BSET    SPK_RAMP                ; V10.3: the stock angle will come back from this one\n"
                    "        MOVB    BLIP_SPK, RL4\n")
    pops = _replace(pops, "\n; ---- the AFR branch (0B:D434",
                    "psk_ramp:                               ; V10.3: the hand-over from the blip to the stock angle\n"
                    "        JNB     SPK_RAMP, psk_stock\n        PUSH    0FF10h                  ; PSW\n"
                    "        MOV     [-R0], R3\n        MOV     [-R0], R4\n        MOV     [-R0], R5\n"
                    "        MOVBZ   R3, 807Fh\n        CMP     R3, #25\n        JMPR    ULT, pr_end            ; under 800 rpm\n"
                    "        SHR     R3, #2\n        MOVBZ   R5, BLIP_SPK\n        ADD     R3, R5                  ; the most advance now\n"
                    "        MOVBZ   R4, 0E2B5h              ; the stock angle\n        CMP     R4, R3\n"
                    "        JMPR    ULE, pr_end             ; reached: the stock angle from here\n"
                    "        MOVB    BLIP_SPK, RL3\n        MOVB    0E2B5h, RL3\n        MOV     R4, #0\n        MOVB    0E2B4h, RL4\n"
                    "        JMPR    UC, pr_out\npr_end:\n        BCLR    SPK_RAMP\npr_out:\n"
                    "        MOV     R5, [R0+]\n        MOV     R4, [R0+]\n        MOV     R3, [R0+]\n"
                    "        POP     0FF10h                  ; PSW\n        JMPS    0Bh, 05C84h\n"
                    "\n; ---- the AFR branch (0B:D434")

    (ROOT / "patches/live_overlay_v10.asm").write_text(source)
    (ROOT / "patches/live_overlay_v10_feature_helpers.inc").write_text(helpers)
    (ROOT / "patches/live_overlay_v10_pops.inc").write_text(pops)
