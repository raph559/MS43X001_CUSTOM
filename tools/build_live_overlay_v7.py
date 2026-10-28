"""Build the separate V7 image with pinned word-table and inherited scalar hooks."""
import json
import re
import subprocess
from pathlib import Path
import build_live_overlay as build
from live_overlay_v4_catalog import catalogue
from live_overlay_v7_maps import prepare
from live_overlay_v6_features import GROUPS, READS, stubs, hooks

ROOT = Path(build.REPO)
build.SOURCE = str(ROOT / "patches/live_overlay_v7.asm")
build.DEFAULT_OUT = str(ROOT / "build/CAR_43X001_SP95_STAGE1_LIVE_OVERLAY_V7.bin")
build.DEFAULT_FIXTURE = str(ROOT / "sim/tests/Ms43Sim.Tests/fixtures/live_overlay_v7.hex")


def assemble_gently(asm):
    base = str(Path(asm).with_suffix(""))
    wsl = build.ms43_patch.wsl_path
    # WSL server workers are outside the Windows job; throttle the Linux tools too.
    command = ("set -e; cd \"$(dirname '{a}')\"; "
               "timeout --kill-after=2s 120s bash '{g}' {d}/asl -q -L -olist '{b}.lst' '{a}'; "
               "timeout --kill-after=2s 120s bash '{g}' {d}/p2hex -q -F Intel32 -l 32 '{b}.p' '{b}.hex'")
    result = subprocess.run(["wsl.exe", "-d", "Ubuntu-24.04", "--exec", "bash", "-lc",
                             command.format(a=wsl(asm), b=wsl(base), d=build.ms43_patch.ASL_DIR,
                                            g=wsl(str(ROOT / "tools/run_gently.sh")))],
                            capture_output=True, text=True)
    if result.returncode:
        listing = Path(base + ".lst")
        errors = [line for line in listing.read_text(errors="replace").splitlines() if "error" in line] if listing.exists() else []
        build.fail("assembly failed:\n" + result.stdout + result.stderr + "\n".join(errors))
    return base + ".hex"


def main():
    donor = Path(build.option("--car", None) or build.find_car()).read_bytes()
    maps = catalogue(donor)
    if maps != json.loads((ROOT / "defs/live_overlay_v4_catalog.json").read_text()):
        build.fail("The checked V4 catalogue does not match the donor")
    if (ROOT / "patches/live_overlay_v6_feature_stubs.inc").read_text() != stubs():
        build.fail("Regenerate the scalar stubs from live_overlay_v6_features.py")
    if (ROOT / "patches/live_overlay_v6_feature_hooks.inc").read_text() != hooks():
        build.fail("Regenerate the scalar hooks from live_overlay_v6_features.py")
    maps += prepare(donor)
    if any(row["bytes"] % 4 for row in maps):
        build.fail("Packed directory offsets require four-byte map sizes")
    build.HOOKS = {site: row["name"] for row in maps for site in row["sites"]}
    sizes = {site: 4 for site in build.HOOKS}
    extra = {0x2A3AC: ("cut mode", "F3F81E13"), 0x58C88: ("manual gear limits", "DA0D2E04"),
             0x58CFC: ("cut hysteresis", "C2FDFF0B"), 0x58D18: ("mode refresh", "F3FCAC81"),
             0x1FC8A: ("DS2 6D", "DA09B6FF"), 0x6E3E2: ("housekeeping", "DE800D00")}
    extra.update({site: (name, expected) for name, _, _, _, _, site, expected in READS})
    for site, (name, expected) in extra.items():
        original = bytes.fromhex(expected)
        if donor[site:site+len(original)] != original:
            build.fail(f"Unexpected original {name} instruction at {site:06X}")
        build.HOOKS[site] = name
        sizes[site] = len(original)
    build.HOOKS[0x6FE00] = "program checksum range"
    sizes[0x6FE00] = 4

    def check_record(offset, length):
        end = offset + length
        if any(offset < stop and end > start for start, stop in build.NEVER):
            build.fail(f"Forbidden record {offset:06X}..{end:06X}")
        if any(offset >= site and end <= site+size for site, size in sizes.items()):
            return
        if build.BLOCK[0] <= offset and end <= build.BLOCK[1]:
            return
        build.fail(f"Record outside V7 write list: {offset:06X}..{end:06X}")

    build.check_record = check_record
    build.ms43_patch.assemble = assemble_gently
    build.main()
    listing = (ROOT / "patches/live_overlay_v6.lst").read_text(errors="replace")
    symbols = {name: int(address, 16) for address, name in re.findall(r"\b([0-9A-F]{5,6})\s+:\s+([a-z_]\w*):", listing)}
    (ROOT / "defs/live_overlay_v7_symbols.json").write_text(json.dumps(symbols, indent=2) + "\n")
    (ROOT / "defs/live_overlay_v7_catalog.json").write_text(json.dumps(sorted(maps + GROUPS, key=lambda r: r["id"]), indent=2) + "\n")
    reads = [dict(name=n, group=g, offset=o, operation=k, register=r, site=s, original=b)
             for n, g, o, k, r, s, b in READS]
    (ROOT / "defs/live_overlay_v7_reads.json").write_text(json.dumps(reads, indent=2) + "\n")


if __name__ == "__main__":
    main()
