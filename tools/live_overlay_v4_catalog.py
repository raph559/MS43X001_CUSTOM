"""Identify V4's bounded catalogue from direct u8 bilinear reads in the pinned donor."""
import csv
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
FIRST = [0x77315, 0x775D4, 0x7D69C, 0x76390, 0x7629C]


def catalogue(image):
    found = {}
    for row in csv.DictReader((ROOT / "calmaps_ms43x.csv").open(encoding="utf-8")):
        size = int(row["rows"]) * int(row["cols"])
        if (row["kind"], row["elem"], row["interp"]) != ("map", "u8", "1"):
            continue
        if size < 8 or size > 704 or size % 2 or not row["sites"] or not row["name"]:
            continue
        address = int(row["data"], 16)
        page, offset = divmod(address, 0x4000)
        sites = [int(site, 16) for site in row["sites"].split()]
        pointer = bytes([0xE6, 0xFC, offset & 255, offset >> 8, 0xE6, 0xFD, page, 0])
        if not all(image[site - 8:site] == pointer and image[site:site + 4] == bytes.fromhex("DA0D9A02") for site in sites):
            continue
        if not 0x74000 <= address < address + size <= 0x7FFE0:
            raise ValueError(f"Calibration range: {row['name']}")
        found[address] = dict(address=address, bytes=size, name=row["name"], rows=int(row["rows"]),
                              columns=int(row["cols"]), sites=sites, reader=0xD029A)
    if any(address not in found for address in FIRST):
        raise ValueError("The original five maps must remain available")
    ordered = [found[address] for address in FIRST + sorted(found.keys() - set(FIRST))]
    if len(ordered) > 254:
        raise ValueError("Map IDs reserve 255 for the limiter")
    sites = set()
    for index, row in enumerate(ordered):
        row["id"] = index
        for site in row["sites"]:
            if site in sites:
                raise ValueError(f"Ambiguous call site {site:06X}")
            sites.add(site)
    return ordered


def write_catalogue(image, output):
    rows = catalogue(image)
    Path(output).write_text(json.dumps(rows, indent=2) + "\n", encoding="utf-8")
    return rows
