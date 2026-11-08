"""V9: the V8 overlay plus the watched map. Generates the V9 assembly from V8's."""
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]

# The lookup library's readers: file offset of the entry, and the free register its first instruction loads.
READERS = [(0x5022A, 2), (0x50262, 2), (0x50454, 2), (0x5042E, 2), (0x50168, 3), (0x5029A, 3), (0x503D2, 3), (0x5043A, 3)]

# The sites V9 patches beyond V8, with the donor's instructions (file offset: name, bytes). Grows task by task.
PINNED = {site: (f"reader {n} entry", f"C2F{reg}6BFB") for n, (site, reg) in enumerate(READERS)}

# The descriptor lookups' MOV DPP0 sites (file offsets): the nine maps, then the seven curves. 0D:1092 moves R11, not R5.
DESCRIPTORS = [0x504B0, 0x505C8, 0x50776, 0x5089E, 0x509BC, 0x50B60, 0x50C88, 0x50EC2, 0x51092,
               0x506E4, 0x50AD6, 0x50DA4, 0x50E30, 0x50FE2, 0x51018, 0x51052]
PINNED.update({site: (f"descriptor {n} DPP0", "F6FB00FE" if site == 0x51092 else "F6F500FE")
               for n, site in enumerate(DESCRIPTORS)})

HOOKS = "".join(f"        ORG     0{0x80000 + site:X}h\n        JMPS    0Ch, watch_rd{n} & 0FFFFh\n"
                for n, (site, _) in enumerate(READERS))
HOOKS += "".join(f"        ORG     0{0x80000 + site:X}h\n        JMPS    0Ch, watch_ds{n} & 0FFFFh\n"
                 for n, site in enumerate(DESCRIPTORS))


def _replace(text, old, new, count=1):
    if text.count(old) != count:
        raise SystemExit(f"V9 generator: expected {count} of {old[:60]!r}, found {text.count(old)}")
    return text.replace(old, new)


def prepare(image):
    """Write patches/live_overlay_v9.asm and its helpers from the V8 sources."""
    source = (ROOT / "patches/live_overlay_v8.asm").read_text()
    source = source.replace("protocol 8", "protocol 9").replace("docs/live-overlay-v8.md", "docs/live-overlay-v9.md")
    source = _replace(source, "OVL_VERSION     EQU     8", "OVL_VERSION     EQU     9")
    source = source.replace("C0D8", "C0D9")
    # Pool A keeps its last 24 bytes: the watch record (041FA8..041FBB) and pops' state (041FBC..041FBF). No allocation
    # may reach logical offset 680, and the free space reported to the app is 908 bytes.
    source = _replace(source, "        CMP     R7, #700\n        JMPA    UGT, bad_range\nld_boundary_ok:",
                      "        CMP     R7, #680\n        JMPA    UGT, bad_range\nld_boundary_ok:")
    source = _replace(source, "        MOV     R9, #(COPY_BYTES-4)\n", "        MOV     R9, #(COPY_BYTES-24)\n")
    source = _replace(source, "live_overlay_v8_feature_helpers.inc", "live_overlay_v9_feature_helpers.inc")
    # Sub 12 sets the watch and sub 11 logs with the record. They need no session: they change nothing the engine reads.
    source = _replace(source, "h_patch:\n        CMP     R5, #9\n        JMPR    NZ, h_auth\n"
                              "        CMP     R4, #29\n        JMPA    NZ, bad_len\n        JMPA    UC, sub_patch\n",
                      "h_patch:\n        CMP     R5, #9\n        JMPR    NZ, h_watch\n"
                      "        CMP     R4, #29\n        JMPA    NZ, bad_len\n        JMPA    UC, sub_patch\n"
                      "h_watch:\n        CMP     R5, #12\n        JMPR    NZ, h_log\n"
                      "        CMP     R4, #8\n        JMPA    NZ, bad_len\n        JMPA    UC, sub_watch\n"
                      "h_log:\n        CMP     R5, #11\n        JMPR    NZ, h_auth\n"
                      "        CMP     R4, #5\n        JMPA    NZ, bad_len\n        JMPA    UC, sub_log\n")
    source = _replace(source, "        CALLA   UC, pops_tick\n", "        CALLA   UC, pops_tick\n        CALLA   UC, watch_quiet\n        CALLA   UC, watch_alias\n")
    # The V9 code goes in the free flash after the CRC tables, below pops' flashed defaults.
    source = _replace(source, "\n; The flashed pops settings",
                      '\n        INCLUDE "live_overlay_v9_watch.inc"\n'
                      '        IF      $ > 0CFF80h\n        ERROR   "the V9 code overruns the pops defaults"\n        ENDIF\n'
                      "\n; The flashed pops settings")
    # The watch drops the live copy before any allocation changes hands (RF1): Load, Free, Revert and every switch-off
    # (AllOff, the frame after a stop or a silence, and housekeeping's own), which all run all_off.
    for routine in ("sub_load", "sub_free", "sub_revert", "all_off"):
        source = _replace(source, f"\n{routine}:\n", f"\n{routine}:\n        CALLA   UC, watch_unalias\n")
    source += HOOKS

    # Triggers (Task 5b): each feature's activation-byte read turns a stored trigger into the byte the stock code expects.
    source = _replace(source, '        INCLUDE "live_overlay_v9_watch.inc"\n',
                      '        INCLUDE "live_overlay_v9_watch.inc"\n        INCLUDE "live_overlay_v9_triggers.inc"\n')
    source = _replace(source, '"live_overlay_v6_feature_stubs.inc"', '"live_overlay_v9_feature_stubs.inc"')
    source = _replace(source, '"live_overlay_v8_pops.inc"', '"live_overlay_v9_pops.inc"')
    stubs = (ROOT / "patches/live_overlay_v6_feature_stubs.inc").read_text()
    for n, feature in enumerate(("lc", "nls", "ral")):
        read = f"feature_{feature}_config_read:\n        EXTP    R4, #1\n        MOVB    RL2, [R3]\n"
        stubs = _replace(stubs, read, read + f"        MOV     R3, #{n}\n        CALLA   UC, trigger_effective\n")
    stubs = stubs.replace("; Generated by tools/live_overlay_v6_features.py",
                          "; Generated by tools/live_overlay_v9_watch.py from V6's stubs, with the triggers")
    pops = (ROOT / "patches/live_overlay_v8_pops.inc").read_text()
    pops = _replace(pops, "pc_can:\n        MOV     R3, #0EF47h\n        JNB     R4.4, pc_can_read\n        MOV     R3, #0EF37h\n"
                          "pc_can_read:\n        MOVB    RL2, [R3]\n        MOVBZ   R2, RL2\n        MOV     R3, R4\n"
                          "        AND     R3, #7\n        SHR     R2, R3\n        AND     R2, #1\n        JNB     R4.3, pc_can_level\n"
                          "        XOR     R2, #1\npc_can_level:\n        CMP     R2, #0\n",
                    "pc_can:\n        CALLA   UC, can_bit_matches     ; shared with the LC/NLS/RAL triggers\n        CMP     R2, #0\n")
    # The pops throttle opening goes up to 20.0 deg TPS (owner, 2026-10-29: "oui 20"; V8's 5.0 gave only crackle). The
    # validators and pops_setting read the limit from pops_limits. The 86A4 units are computed, X * 54.625 by shifts
    # (X * 2731 / 50 within 2 units), since a 201-word table does not fit; no MD register is used (V8 Task 3).
    pops = _replace(pops, "        DB      0, 50           ; 6 throttle opening, 0.1 deg TPS\n",
                          "        DB      0, 200          ; 6 throttle opening, 0.1 deg TPS (V9: up to 20.0)\n")
    pops = _replace(pops, "        SHL     R4, #1\n        ADD     R4, #(pops_throttle_add & 0FFFFh)\n        EXTS    #0Ch, #1\n"
                          "        MOV     R4, [R4]\n",
                    "        MOV     [-R0], R5\n        MOV     R5, R4\n        SHL     R5, #5\n        MOV     R4, R5               ; 32 X\n"
                    "        SHR     R5, #1\n        ADD     R4, R5               ; + 16 X\n        SHR     R5, #2\n"
                    "        ADD     R4, R5               ; + 4 X\n        SHR     R5, #1\n        ADD     R4, R5               ; + 2 X\n"
                    "        SHR     R5, #2\n        ADD     R4, R5               ; + X / 2\n        SHR     R5, #2\n"
                    "        ADD     R4, R5               ; + X / 8: 54.625 X, 10925 at 20.0 deg TPS\n        MOV     R5, [R0+]\n")
    start = pops.index("; 86A4 units added for each 0.1 deg TPS of opening")
    end = pops.index("\n", pops.index("pops_throttle_add:\n        DW") + len("pops_throttle_add:\n")) + 1
    pops = pops[:start] + pops[end:]

    helpers = (ROOT / "patches/live_overlay_v8_feature_helpers.inc").read_text()
    # A trigger (80h..9Fh) is a valid activation byte for LC, NLS and RAL; RAL keeps 0..1 for the rest, and its neighbour rule.
    helpers = _replace(helpers, "        MOVB    RL4, [R13]\n        CMPB    RL4, #2\n        JMPR    UGT, fv_range\n"
                                "        CMP     R2, #126\n        JMPR    NZ, fv_ok\n        CMPB    RL4, #1\n        JMPR    UGT, fv_range\n",
                       "        MOVB    RL4, [R13]\n        MOVB    RH4, RL4\n        ANDB    RH4, #0E0h\n        CMPB    RH4, #80h\n"
                       "        JMPR    Z, fv_trigger\n        CMPB    RL4, #2\n        JMPR    UGT, fv_range\n"
                       "        CMP     R2, #126\n        JMPR    NZ, fv_ok\n        CMPB    RL4, #1\n        JMPR    UGT, fv_range\n"
                       "fv_trigger:\n        CMP     R2, #126\n        JMPR    NZ, fv_ok\n")
    (ROOT / "patches/live_overlay_v9.asm").write_text(source)
    (ROOT / "patches/live_overlay_v9_feature_helpers.inc").write_text(helpers)
    (ROOT / "patches/live_overlay_v9_feature_stubs.inc").write_text(stubs)
    (ROOT / "patches/live_overlay_v9_pops.inc").write_text(pops)
