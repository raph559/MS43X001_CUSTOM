"""V10.1: the V9 overlay plus pops' throttle stabs and the downshift blip. Generates the V10 assembly from V9's.

V10.1 (2026-11-05, after the first car test) is V10 with new defaults, the rise allowed once stabbing (139 byte 4),
the blip lead (141 byte 6), a pops AFR target down to 7.4 and three minors from V10's review. The header's version word
is 010Ah: the low byte stays 10, so every V10 rule holds, and the high byte is the minor (V8.5's way)."""
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]

# Groups 138..142 are 8 bytes each from 0C:FF80 (file 0x4FF80): pops, then V10's four (catalogue page 33h).
DEFAULTS_FILE = 0x4FF80
# V10.1's defaults (owner, 2026-11-05: "put it by default plz", "do it by default"): pops at -23.625 deg, AFR 9.99,
# 4,000 rpm and 3.0 deg TPS with 5.0 deg TPS stabs and a 480 rpm rise once stabbing; a 30.0 deg TPS blip at +20.25 deg
# (2026-11-06: "Make it the default"), a 150 ms lead.
POPS_DEFAULTS = bytes([0x00, 0x28, 0x00, 0xD2, 0x7D, 0x9E, 0x1E, 0x14])
STAB_DEFAULTS = bytes([0x14, 0x19, 0x0F, 0x19, 0x0F, 0, 0, 0])
BLIP_DEFAULTS = bytes([0x00, 0x03, 0x1E, 0xBB, 0x0F, 0x96, 0x19, 0x75])
GEARS_DEFAULTS = bytes([0x01, 0x01, 0x01, 0x00, 0x15, 0x28, 0x0F, 0])
RATIO_DEFAULTS = bytes([0xE2, 0x86, 0x59, 0x43, 0, 0, 0, 0])
DEFAULTS = POPS_DEFAULTS + STAB_DEFAULTS + BLIP_DEFAULTS + GEARS_DEFAULTS + RATIO_DEFAULTS

GROUPS = [dict(id=139, name="pops_stabs", address=0xCFF88, bytes=8, flags=2, fields=5),
          dict(id=140, name="blip", address=0xCFF90, bytes=8, flags=2, fields=8),
          dict(id=141, name="blip_gears", address=0xCFF98, bytes=8, flags=2, fields=7),
          dict(id=142, name="blip_ratios", address=0xCFFA0, bytes=8, flags=2, fields=4)]

# V10 reuses V8's gate, spark and throttle hooks and housekeeping, and adds one site (Task 7's finding): the in-cut handler
# (0A:A9EE) re-checks the engine speed at 0A:AAA0 and refuels only below the re-entry rpm, so a blip that starts during a
# running cut takes the stock re-entry at once (file offset: name, the donor's instruction).
PINNED = {0x2AAA0: ("in-cut re-entry check", "2A244D2B")}

HOOKS = """
        ORG     0AAAA0h
        JMPS    0Ch, blip_reentry & 0FFFFh
"""

# V10's state, ahead of the pops include that is the first to use it: pool A logical 668..679 (through DPP2), below the
# watch record, and FDF8 bits 7..13, which no code in the car file or in V9 uses.
V10_STATE = """; V10's state (docs/live-overlay-v10.md): pool A logical 668..679, through DPP2, and FDF8 bits 7..13; FDF8.14 and
; FDF8.15 belong to the car file.
POPS_T          EQU     09F9Ch          ; word: 10 ms ticks since the pops window started, saturating
BLIP_ADD        EQU     09F9Eh          ; word: the blip's throttle addition now, 86A4 units
BLIP_LEFT       EQU     09FA0h          ; word: 10 ms ticks left in the blip
POPS_PH         EQU     09FA2h          ; byte: 10 ms ticks left in the current stab or gap
BLIP_CL         EQU     09FA3h          ; byte: 10 ms ticks since the clutch went in, saturating; 0 while it is released
BLIP_TGT        EQU     09FA4h          ; byte: the blip's target, 807F units (32 rpm)
BLIP_TAP        EQU     09FA5h          ; byte: 10 ms ticks since the pedal rose past the tap threshold
BLIP_PREV       EQU     09FA6h          ; byte: 807F one tick ago, while a blip rises (V10.1)
BLIP_RATE       EQU     09FA7h          ; byte: the rise per 10 ms tick x 16, filtered, while a blip rises (V10.1)
POPS_STABS      EQU     09FBFh          ; byte: the stabs begun in this pops window, up to 255, for the log (V10.1)
POPS_STAB       BIT     0FDF8h.7        ; a stab is on
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
    source = _replace(source, "        DW      OVL_VERSION\n", "        DW      OVL_VERSION + 0100h     ; V10.1: the high byte is the minor\n")
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
                      "        DW      0033h, 03F88h, 8, 2 ; 139 pops stabs\n"
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
                      "; The flashed pops settings: off, 4.0 s, -23.625 deg, 9.99 AFR (210), 4,000 rpm, 70.5 deg C, "
                      "3.0 deg TPS, 20 km/h.\n")
    source = _replace(source, "pops_defaults:\n        DB      000h, 014h, 017h, 0B8h, 032h, 09Eh, 000h, 014h\n",
                      "pops_defaults:\n" + _db(POPS_DEFAULTS)
                      + "; 139 pops stabs: a 2.0 s load, +5.0 deg TPS stabs of 150 ms, 250 ms gaps, a 480 rpm rise once stabbing.\n"
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
    # Task 2, the stabs: a window's start resets the phases; the tick runs them while every condition holds; every way a
    # window ends clears POPS_STAB; the throttle store adds the stab's extra while POPS_STAB is set and GUARD is clear.
    source = _replace(source, '        INCLUDE "live_overlay_v10_groups.inc"\n',
                      '        INCLUDE "live_overlay_v10_groups.inc"\n        INCLUDE "live_overlay_v10_blip.inc"\n')
    # V10.1: the pops AFR target reaches 255 (lambda 0.504, AFR 7.4) through the same shared rich path, a byte throughout.
    pops = _replace(pops, "        DB      128, 210        ; 3 AFR target, the firmware's: lambda = 1.5 - X/256 (128 = 14.7, "
                          "184 = 11.5, 210 = 10.0)\n",
                    "        DB      128, 255        ; 3 AFR target, the firmware's: lambda = 1.5 - X/256 (128 = 14.7, "
                    "184 = 11.5, 255 = 7.4)\n")
    # V10.1, the rise once stabbing: a stab adds about 200 rpm on the car (2026-11-05), so V8's 160 rpm rule ended each
    # window after one or two stabs. rise_allowance keeps 160 rpm during the load and uses 139 byte 4 once stabbing.
    pops = _replace(pops, "        MOV     R5, R4\n        ADD     R5, #5\n        CMP     R3, R5\n",
                    "        MOV     R5, R4\n        CALLA   UC, rise_allowance      ; + 160 rpm, or 139 byte 4 once stabbing\n"
                    "        CMP     R3, R5\n")
    # The overrun-cut gate checks the rise too, on every request of the stock cut (the V10.1 review): it ended every
    # stabbing window at 160 rpm until it used the same allowance. R5 is free there once the conditions are checked.
    pops = _replace(pops, "        MOV     R2, R4\n        ADD     R2, #5\n        CMP     R3, R2\n        JMPR    UGE, pg_end",
                    "        MOV     R5, R4\n        CALLA   UC, rise_allowance      ; + 160 rpm, or 139 byte 4 once stabbing\n"
                    "        CMP     R3, R5\n        JMPR    UGE, pg_end")
    # V10.1, the log: pops' spare byte after POPS_MIN counts the stabs begun in the window (stab_start, stab_tick).
    pops = _replace(pops, "(09FBFh reserved)", "(09FBFh: POPS_STABS, V10.1)")
    pops = _replace(pops, "        MOV     POPS_LEFT, R4\n        MOVB    RL4, 807Fh\n",
                    "        MOV     POPS_LEFT, R4\n        CALLA   UC, stab_start\n        MOVB    RL4, 807Fh\n")
    pops = _replace(pops, "pg_end:\n        BCLR    0FDF8h.3\n", "pg_end:\n        BCLR    0FDF8h.3\n        BCLR    POPS_STAB\n")
    pops = _replace(pops, "pops_tick:\n        JB      0FD2Ch.11, pt_overrun\n        JB      0FD2Ch.12, pt_overrun\n"
                          "        BCLR    0FDF8h.3\n",
                    "pops_tick:\n        JB      0FD2Ch.11, pt_overrun\n        JB      0FD2Ch.12, pt_overrun\n"
                    "        BCLR    0FDF8h.3\n        BCLR    POPS_STAB\n")
    pops = _replace(pops, "pt_kept:\n        CMP     R2, #0\n        JMPR    Z, pt_stop\n",
                    "pt_kept:\n        CMP     R2, #0\n        JMPR    Z, pt_stop\n        CALLA   UC, stab_tick\n")
    pops = _replace(pops, "pt_end:\n        BCLR    0FDF8h.3\n        RET\n",
                    "pt_end:\n        BCLR    0FDF8h.3\n        BCLR    POPS_STAB\n        RET\n")
    pops = _replace(pops, "pth_sum:\n        MOV     R3, [R0+]\n        MOV     R2, [R0+]\n",
                    "pth_sum:\n        JNB     POPS_STAB, pth_done\n        JB      GUARD, pth_done\n"
                    "        MOV     [-R0], R4               ; the stock setpoint plus the opening\n"
                    "        MOV     R2, #139\n        MOV     R3, #1\n        CALLA   UC, v10_setting         ; the stab size\n"
                    "        CALLA   UC, opening_units\n        MOV     R2, R4\n        MOV     R4, [R0+]\n        ADD     R4, R2\n"
                    "        JMPR    NC, pth_done\n        MOV     R4, #0FFFFh\n"
                    "pth_done:\n        MOV     R3, [R0+]\n        MOV     R2, [R0+]\n")
    # Task 3, the brake: either switch (FD2E.3 the brake light switch, FD2E.4 the brake test switch) blocks a window and
    # ends a running one, and braking in overrun uses up the lift (FDF8.4). Out of overrun the lift is re-armed only with
    # the clutch released, so a tap with the clutch in does not bring the pops back (owner, 2026-11-05).
    pops = _replace(pops, "        JB      0FD2Eh.6, pc_done       ; clutch pressed: the clutch belongs to NLS\n",
                    "        JB      0FD2Eh.6, pc_done       ; clutch pressed: the clutch belongs to NLS\n"
                    "        JB      0FD2Eh.3, pc_done       ; braking: either brake switch\n"
                    "        JB      0FD2Eh.4, pc_done\n")
    pops = _replace(pops, "        BCLR    0FDF8h.3\n        BCLR    POPS_STAB\n        BCLR    0FDF8h.4\n        RET\n"
                          "pt_overrun:\n        JNB     0FDF8h.3, pt_done\n",
                    "        BCLR    0FDF8h.3\n        BCLR    POPS_STAB\n"
                    "        JB      0FD2Eh.6, pt_rearm_done ; the clutch in: not a press that re-arms the pops\n"
                    "        BCLR    0FDF8h.4\npt_rearm_done:\n        RET\n"
                    "pt_overrun:\n        JB      0FD2Eh.3, pt_brake\n        JNB     0FD2Eh.4, pt_no_brake\n"
                    "pt_brake:\n        BSET    0FDF8h.4                ; braking uses up this lift's pops\n"
                    "        BCLR    0FDF8h.3\n        BCLR    POPS_STAB\n        RET\n"
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
    pops = _replace(pops, "psk_stock:\n        JMPS    0Bh, 05C84h\n",
                    "psk_stock:\n        JMPS    0Bh, 05C84h\n"
                    "psk_blip:\n        JNB     0FD2Ch.11, psk_stock\n        PUSH    0FF10h                  ; PSW\n"
                    "        MOV     [-R0], R2\n        MOV     [-R0], R3\n        MOV     [-R0], R4\n"
                    "        MOV     R2, #140\n        MOV     R3, #7\n        CALLA   UC, v10_setting         ; the blip's own spark angle\n"
                    "        MOVB    0E2B5h, RL4\n        MOV     R4, #0\n        MOVB    0E2B4h, RL4\n"
                    "        MOV     R4, [R0+]\n        MOV     R3, [R0+]\n        MOV     R2, [R0+]\n        POP     0FF10h                  ; PSW\n"
                    "        JMPS    0Bh, 05C84h\n")

    (ROOT / "patches/live_overlay_v10.asm").write_text(source)
    (ROOT / "patches/live_overlay_v10_feature_helpers.inc").write_text(helpers)
    (ROOT / "patches/live_overlay_v10_pops.inc").write_text(pops)
