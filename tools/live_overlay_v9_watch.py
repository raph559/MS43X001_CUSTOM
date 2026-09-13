"""V9: the V8 overlay plus the watched map. Generates the V9 assembly from V8's."""
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]

# The sites V9 patches beyond V8, with the donor's instructions (file offset: name, bytes). Grows task by task.
PINNED = {}

HOOKS = ""


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
    # Sub 12 sets the watch. It needs no session: it changes nothing the engine reads.
    source = _replace(source, "h_patch:\n        CMP     R5, #9\n        JMPR    NZ, h_auth\n"
                              "        CMP     R4, #29\n        JMPA    NZ, bad_len\n        JMPA    UC, sub_patch\n",
                      "h_patch:\n        CMP     R5, #9\n        JMPR    NZ, h_watch\n"
                      "        CMP     R4, #29\n        JMPA    NZ, bad_len\n        JMPA    UC, sub_patch\n"
                      "h_watch:\n        CMP     R5, #12\n        JMPR    NZ, h_auth\n"
                      "        CMP     R4, #8\n        JMPA    NZ, bad_len\n        JMPA    UC, sub_watch\n")
    source = _replace(source, "        CALLA   UC, pops_tick\n", "        CALLA   UC, pops_tick\n        CALLA   UC, watch_quiet\n")
    # The V9 code goes in the free flash after the CRC tables, below pops' flashed defaults.
    source = _replace(source, "\n; The flashed pops settings",
                      '\n        INCLUDE "live_overlay_v9_watch.inc"\n'
                      '        IF      $ > 0CFF80h\n        ERROR   "the V9 code overruns the pops defaults"\n        ENDIF\n'
                      "\n; The flashed pops settings")
    source += HOOKS

    helpers = (ROOT / "patches/live_overlay_v8_feature_helpers.inc").read_text()
    (ROOT / "patches/live_overlay_v9.asm").write_text(source)
    (ROOT / "patches/live_overlay_v9_feature_helpers.inc").write_text(helpers)
