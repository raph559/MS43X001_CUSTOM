"""V8: the V7 overlay plus pops on lift-off (settings group 138). Generates the V8 assembly from V7's."""
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]

DEFAULTS_FILE = 0x4FF80          # CPU 0C:FF80, app address 0xCFF80, catalogue page 33h offset 3F80h
DEFAULTS = bytes([0x00, 0x14, 0x17, 0x73, 0x32, 0x9E, 0x00, 0x14])
GROUP = dict(id=138, name="pops", address=0xCFF80, bytes=8, flags=2, fields=8)

# The sites V8 patches beyond V7, with the donor's instructions (file offset: name, bytes).
PINNED = {}


def _replace(text, old, new, count=1):
    if text.count(old) != count:
        raise SystemExit(f"V8 generator: expected {count} of {old[:60]!r}, found {text.count(old)}")
    return text.replace(old, new)


def prepare(image):
    """Write patches/live_overlay_v8.asm and its helpers from the V7 sources; return group 138's catalogue row."""
    if image[DEFAULTS_FILE:DEFAULTS_FILE + 8] != b"\xFF" * 8:
        raise SystemExit("V8 generator: the defaults' location is not free in the donor")
    source = (ROOT / "patches/live_overlay_v7.asm").read_text()
    source = source.replace("protocol 7", "protocol 8").replace("docs/live-overlay-v7.md", "docs/live-overlay-v8.md")
    source = _replace(source, "OVL_VERSION     EQU     7", "OVL_VERSION     EQU     8")
    source = _replace(source, "N_TABLES        EQU     138", "N_TABLES        EQU     139")
    source = source.replace("C0D7", "C0D8")
    # Pool A keeps its last four bytes (041FBC..041FBF) for the pops state: no allocation may reach them,
    # and the free space reported to the app is 928 bytes.
    source = _replace(source, "        CMP     R7, #704\n        JMPA    UGT, bad_range\nld_boundary_ok:",
                      "        CMP     R7, #700\n        JMPA    UGT, bad_range\nld_boundary_ok:")
    source = _replace(source, "        MOV     R9, #COPY_BYTES\n", "        MOV     R9, #(COPY_BYTES-4)\n")
    source = _replace(source, "live_overlay_v7_feature_helpers.inc", "live_overlay_v8_feature_helpers.inc")
    source = _replace(source, "\ncode_end:", '\n        INCLUDE "live_overlay_v8_pops.inc"\n\ncode_end:')
    source = _replace(source, "\ncrc_table:", "        DW      0033h, 03F80h, 8, 2 ; 138 pops\n\ncrc_table:")
    data = ", ".join(f"{b:02X}h" for b in DEFAULTS)
    source = _replace(source, "\ndata_end:",
                      f"\n; The flashed pops settings: off, 2.0 s, -15.0 deg, 11.5 AFR, 1,600 rpm, 70.5 deg C, no throttle, 20 km/h.\n"
                      f"        ORG     0CFF80h\npops_defaults:\n        DB      {data}\n\ndata_end:")

    helpers = (ROOT / "patches/live_overlay_v7_feature_helpers.inc").read_text()
    helpers = _replace(helpers, "        ; IDs 124..126 share bitmap byte 15. Avoid a full chain scan when absent.\n",
                       "        CMP     R2, #138\n        JMPR    Z, fa_bitmap_pops\n"
                       "        ; IDs 124..126 share bitmap byte 15. Avoid a full chain scan when absent.\n")
    helpers = _replace(helpers, "fa_find:\n",
                       "        JMPR    UC, fa_find\n"
                       "fa_bitmap_pops:\n        EXTP    #3, #1\n        MOVBZ   R4, W_BITMAP+17\n"
                       "        JNB     R4.2, fa_flash\nfa_find:\n")
    helpers = _replace(helpers, "fa_flash:\n        MOV     R3, R2\n",
                       "fa_flash:\n        CMP     R2, #138\n        JMPR    NZ, fa_flash_x001\n"
                       "        MOV     R3, #3F80h\n        ADD     R3, R5\n        MOV     R4, #33h\n        RET\n"
                       "fa_flash_x001:\n        MOV     R3, R2\n")
    helpers = _replace(helpers, "feature_validate:\n        CMP     R2, #126\n",
                       "feature_validate:\n        CMP     R2, #138\n        JMPA    Z, pops_validate\n        CMP     R2, #126\n")
    helpers = _replace(helpers, "feature_write_validate:\n        CMP     R2, #126\n        JMPR    UGT, fv_ok\n"
                                "        CMP     R2, #124\n        JMPR    ULT, fv_ok\n",
                       "feature_write_validate:\n        CMP     R2, #138\n        JMPR    Z, fwv_group\n"
                       "        CMP     R2, #126\n        JMPR    UGT, fv_ok\n        CMP     R2, #124\n        JMPR    ULT, fv_ok\n"
                       "fwv_group:\n")
    (ROOT / "patches/live_overlay_v8.asm").write_text(source)
    (ROOT / "patches/live_overlay_v8_feature_helpers.inc").write_text(helpers)
    return GROUP
