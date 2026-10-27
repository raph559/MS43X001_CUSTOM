"""Build V4 beside retained V2/V3 images; validate every newly redirected instruction."""
import json
import re
from pathlib import Path
import build_live_overlay as build
from live_overlay_v4_catalog import catalogue

ROOT = Path(build.REPO)
build.SOURCE = str(ROOT / "patches/live_overlay_v4.asm")
build.DEFAULT_OUT = str(ROOT / "build/CAR_43X001_SP95_STAGE1_LIVE_OVERLAY_V4.bin")
build.DEFAULT_FIXTURE = str(ROOT / "sim/tests/Ms43Sim.Tests/fixtures/live_overlay_v4.hex")


def main():
    donor = Path(build.option("--car", None) or build.find_car()).read_bytes()
    maps = catalogue(donor)
    if maps != json.loads((ROOT / "defs/live_overlay_v4_catalog.json").read_text()):
        build.fail("The checked catalogue does not match the donor")
    build.HOOKS = {site: row["name"] for row in maps for site in row["sites"]}
    extra = {0x2A3AC: ("cut mode", "F3F81E13"), 0x58C88: ("manual gear limits", "DA0D2E04"),
             0x58CFC: ("cut hysteresis", "C2FDFF0B"), 0x58D18: ("mode refresh", "F3FCAC81"),
             0x1FC8A: ("DS2 6D", "DA09B6FF"), 0x6E3E2: ("housekeeping", "DE800D00")}
    for site, (name, expected) in extra.items():
        if donor[site:site+4] != bytes.fromhex(expected):
            build.fail(f"Unexpected original {name} instruction at {site:06X}: {donor[site:site+4].hex()}")
        build.HOOKS[site] = name
    build.HOOKS[0x6FE00] = "program checksum range"
    build.main()
    listing = (ROOT / "patches/live_overlay_v4.lst").read_text(errors="replace")
    symbols = {name: int(address, 16) for address, name in re.findall(r"\b([0-9A-F]{5,6})\s+:\s+([a-z_]\w*):", listing)}
    (ROOT / "defs/live_overlay_v4_symbols.json").write_text(json.dumps(symbols, indent=2) + "\n")


if __name__ == "__main__":
    main()
