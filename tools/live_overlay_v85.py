"""V8.5: V8 with the pops throttle opening up to 20.0 deg TPS and nothing else. Generates its assembly from V8's.

The header's version word is 0508h: the low byte stays 8, so every V8 rule holds, and the high byte is the minor. V8's status
reply still reports 8. The 86A4 units are computed as in V9, since a 201-word table does not fit below the defaults.
"""
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]


def _replace(text, old, new):
    if text.count(old) != 1:
        raise SystemExit(f"V8.5 generator: expected one {old!r}, found {text.count(old)}")
    return text.replace(old, new)


def prepare():
    """Write patches/live_overlay_v85.asm and its pops include from V8's, which the V8 generator has just written."""
    source = (ROOT / "patches/live_overlay_v8.asm").read_text()
    source = _replace(source, "        DW      OVL_VERSION\n", "        DW      OVL_VERSION + 0500h     ; V8.5: the high byte is the minor\n")
    source = _replace(source, '"live_overlay_v8_pops.inc"', '"live_overlay_v85_pops.inc"')
    pops = (ROOT / "patches/live_overlay_v8_pops.inc").read_text()
    pops = _replace(pops, "        DB      0, 50           ; 6 throttle opening, 0.1 deg TPS\n",
                          "        DB      0, 200          ; 6 throttle opening, 0.1 deg TPS (V8.5: up to 20.0)\n")
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
    (ROOT / "patches/live_overlay_v85.asm").write_text(source)
    (ROOT / "patches/live_overlay_v85_pops.inc").write_text(pops)
