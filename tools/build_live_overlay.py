"""Build the live-tuning overlay (plan 6) from the car file.

    python -I tools/build_live_overlay.py [--car BIN] [--out BIN] [--fixture HEX]

Steps:
  1. Assemble patches/live_overlay.asm with AS in WSL (ms43_patch.assemble). Every assembler warning but "page might not
     be addressable" (AS gives it on each EXTP/EXTS access, with correct bytes) refuses the build.
  2. Refuse any record outside the write list: the hooks (the five tables' seven sites, the 0x6D slot, queue-1 task 09h's
     entry, the program CRC range's end; 4 bytes each) and the overlay's block from 0x4B544 up to the programming
     signature at 0x4FFE6. The boot block and the validity tags are never written.
  3. Apply the records to a copy of the car file (checked against its SHA-256), fix the five checksums, verify them.
  4. Write the bin (default build/CAR_43X001_SP95_STAGE1_LIVE_OVERLAY.bin, not committed) and the test fixture
     (sim/tests/Ms43Sim.Tests/fixtures/live_overlay.hex, the assembler's output with LF line endings).
  5. Print the hooks, the overlay's extent, the CRC range and the program identity (sim's ProgramIdentity.Of).

The input bin is only read. Nothing here flashes anything: the bin goes to the bench or the car only with the owner's
explicit go-ahead.
"""
import hashlib
import os
import struct
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import ms43_checksums  # noqa: E402
import ms43_patch  # noqa: E402

REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
CAR_NAME = "CAR_current_43X001_SP95_STAGE1.bin"
CAR_SHA256 = "8cfe31241aa90717195077f1d931ec3bd28e0e76b435a89472dc1fbdfe6c0717"
SOURCE = os.path.join(REPO, "patches", "live_overlay.asm")
DEFAULT_OUT = os.path.join(REPO, "build", "CAR_43X001_SP95_STAGE1_LIVE_OVERLAY.bin")
DEFAULT_FIXTURE = os.path.join(REPO, "sim", "tests", "Ms43Sim.Tests", "fixtures", "live_overlay.hex")

HOOKS = {
    0x2C650: "ip_iga_ron98_pl", 0x2C3A4: "ip_iga_ron98_is", 0x3D40A: "ip_af_target_ron98",
    0x33B48: "ip_cam_sp_ron98_in_pl (FD9C.3)", 0x33BA2: "ip_cam_sp_ron98_in_pl",
    0x33B74: "ip_cam_sp_ron98_ex_pl (FD9C.3)", 0x33BEA: "ip_cam_sp_ron98_ex_pl",
    0x1FC8A: "the DS2 0x6D slot", 0x6E3E2: "queue-1 task 09h", 0x6FE00: "the program CRC range 4's end",
}
BLOCK = (0x4B544, 0x4FFE6)
NEVER = [(0x00000, 0x08000), (0x4FFE6, 0x50000), (0x6FFF0, 0x70000), (0x7FFF0, 0x80000)]
ALLOWED_WARNING = "page might not be addressable"


def fail(message):
    sys.exit("build_live_overlay: " + message)


def find_car():
    here = os.path.abspath(os.getcwd())
    while True:
        path = os.path.join(here, "bins", CAR_NAME)
        if os.path.exists(path):
            return path
        parent = os.path.dirname(here)
        if parent == here:
            fail("no bins/%s in this folder or above it; give --car" % CAR_NAME)
        here = parent


def option(name, default):
    args = sys.argv[1:]
    if name in args:
        i = args.index(name)
        if i + 1 >= len(args):
            fail("%s needs a value" % name)
        return args[i + 1]
    return default


def check_warnings(listing):
    bad = []
    for line in open(listing, errors="replace"):
        if ": warning:" in line and ALLOWED_WARNING not in line:
            bad.append(line.strip())
        if ": error:" in line:
            bad.append(line.strip())
    if bad:
        fail("the assembler said more than '%s':\n  %s" % (ALLOWED_WARNING, "\n  ".join(bad)))


def check_record(offset, length):
    end = offset + length
    for start, stop in NEVER:
        if offset < stop and end > start:
            fail("a record writes file 0x%05X-0x%05X: the boot block, a tag or the signature" % (offset, end - 1))
    if any(offset >= site and end <= site + 4 for site in HOOKS):
        return
    if offset >= BLOCK[0] and end <= BLOCK[1]:
        return
    fail("a record writes file 0x%05X-0x%05X, outside the write list" % (offset, end - 1))


def identity(image):
    return hashlib.sha256(bytes(image[0x10000:0x4FFE6]) + bytes(image[0x50000:0x70000])).hexdigest()


def main():
    car_path = option("--car", None) or find_car()
    out = option("--out", DEFAULT_OUT)
    fixture = option("--fixture", DEFAULT_FIXTURE)
    car = open(car_path, "rb").read()
    if hashlib.sha256(car).hexdigest() != CAR_SHA256:
        fail("%s is not the car file (SHA-256 %s)" % (car_path, hashlib.sha256(car).hexdigest()))

    hexfile = ms43_patch.assemble(SOURCE)
    check_warnings(os.path.splitext(SOURCE)[0] + ".lst")
    records = [(addr & 0x7FFFF, bytes(data)) for addr, data in ms43_patch.read_ihex(hexfile)]
    image = bytearray(car)
    for offset, data in records:
        check_record(offset, len(data))
        image[offset:offset + len(data)] = data

    block_end = max(offset + len(data) for offset, data in records if BLOCK[0] <= offset < BLOCK[1])
    header = image[BLOCK[0]:BLOCK[0] + 16]
    if header[:4] != b"LTOV":
        fail("no LTOV header at 0x4B544")
    version, code_start, code_end, data_end = struct.unpack_from("<HHHH", header, 4)
    if 0x40000 + data_end != block_end:
        fail("the header's data end 0C:%04X is not the block's end 0x%05X" % (data_end, block_end))
    crc_end = struct.unpack_from("<I", image, 0x6FE00)[0]
    if crc_end != 0x0C0000 + data_end - 1:
        fail("the CRC range ends at %06X, not at the overlay's last byte" % crc_end)

    ms43_checksums.fix(image)
    print("checksums:")
    if not ms43_checksums.check(image):
        fail("the checksums do not verify")

    os.makedirs(os.path.dirname(out), exist_ok=True)
    open(out, "wb").write(image)
    text = open(hexfile).read().replace("\r\n", "\n")
    open(fixture, "w", newline="\n").write(text)

    print("hooks:")
    for site, what in sorted(HOOKS.items()):
        if site == 0x6E3E2:
            target = "0C:%04X" % (image[site] | image[site + 1] << 8)
        elif site == 0x6FE00:
            target = "range 4 = 0C:0000-%06X" % crc_end
        else:
            target = "CALLS 0Ch, %04Xh" % (image[site + 2] | image[site + 3] << 8)
        print("  0x%05X  %-34s %s" % (site, what, target))
    print("overlay 1.%d: code 0C:%04X-0C:%04X, data to 0C:%04X (%d bytes of %d free)"
          % (version, code_start, code_end, data_end, data_end - 0xB544, BLOCK[1] - BLOCK[0]))
    print("wrote %s" % out)
    print("wrote %s" % fixture)
    print("program identity %s" % identity(image))


if __name__ == "__main__":
    main()
