"""Assemble a C166 patch with AS (asl, in WSL) and apply it to a copy of an MS43 image.

    python -I ms43_patch.py BASE.bin PATCH.asm OUT.bin [--allow-overwrite]

Steps:
  1. asl + p2hex (WSL, ~/src/asl_dl/asl-current) -> Intel HEX of every ORG block.
  2. Apply the records to a copy of BASE (file offset = address & 0x7FFFF).
     By default a record may only land on erased flash (0xFF); patching
     existing code/data needs --allow-overwrite, and every overwritten range
     is listed.
  3. Disassemble each written range with the project decoder for review.
  4. Recompute the five checksums (ms43_checksums.fix) and verify them.
     Note: bytes outside the checksum ranges are not protected by the ECU.

Write the patch with physical addresses and the firmware DPP assumptions:
    CPU 80C167
    ASSUME DPP0:1Ch, DPP1:3Bh, DPP2:10h, DPP3:3
Conditions are AS-style (Z, NZ, UC, C, ...). Use #> to force a long
immediate. Avoid absolute ESFR operands inside an EXTR window (AS remaps
them; see REPORT.md).
"""
import os
import subprocess
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import ms43_checksums  # noqa: E402
from c167dis import decode  # noqa: E402

ASL_DIR = "~/src/asl_dl/asl-current"


def wsl_path(p):
    p = os.path.abspath(p).replace("\\", "/")
    return "/mnt/%s%s" % (p[0].lower(), p[2:])


def assemble(asm):
    base = os.path.splitext(asm)[0]
    cmd = ("set -e; cd \"$(dirname '{a}')\"; {d}/asl -q -L -olist '{b}.lst' '{a}'; "
           "{d}/p2hex -q -F Intel32 -l 32 '{b}.p' '{b}.hex'").format(a=wsl_path(asm), b=wsl_path(base), d=ASL_DIR)
    r = subprocess.run(["wsl.exe", "-d", "Ubuntu-24.04", "--exec", "bash", "-lc", cmd],
                       capture_output=True, text=True)
    if r.returncode != 0:
        lst = base + ".lst"
        errs = [l for l in open(lst, errors="replace")] if os.path.exists(lst) else []
        sys.exit("assembly failed:\n" + r.stdout + r.stderr + "".join(l for l in errs if "error" in l))
    return base + ".hex"


def read_ihex(path):
    """Yield (address, bytes) from Intel HEX with extended linear/segment records."""
    upper = 0
    for line in open(path):
        line = line.strip()
        if not line.startswith(":"):
            continue
        raw = bytes.fromhex(line[1:])
        n, addr, typ, data = raw[0], (raw[1] << 8) | raw[2], raw[3], raw[4:4 + raw[0]]
        if typ == 0:
            yield upper + addr, data
        elif typ == 2:
            upper = ((data[0] << 8) | data[1]) << 4
        elif typ == 4:
            upper = ((data[0] << 8) | data[1]) << 16


def main():
    args = [a for a in sys.argv[1:] if not a.startswith("--")]
    allow = "--allow-overwrite" in sys.argv
    base_bin, asm, out = args
    img = bytearray(open(base_bin, "rb").read())
    orig = bytes(img)
    hexfile = assemble(asm)
    written = []
    for addr, data in read_ihex(hexfile):
        off = addr & 0x7FFFF
        old = img[off:off + len(data)]
        if any(b != 0xFF for b in old) and old != data and not allow:
            sys.exit("refusing to overwrite non-erased bytes at file 0x%05X (addr 0x%06X); "
                     "use --allow-overwrite" % (off, addr))
        img[off:off + len(data)] = data
        written.append((addr, off, len(data)))
    # merge contiguous records for the review listing
    merged = []
    for addr, off, n in sorted(written, key=lambda t: t[1]):
        if merged and merged[-1][1] + merged[-1][2] == off:
            merged[-1] = (merged[-1][0], merged[-1][1], merged[-1][2] + n)
        else:
            merged.append((addr, off, n))
    for addr, off, n in merged:
        was = "erased" if all(b == 0xFF for b in orig[off:off + n]) else "OVERWRITTEN"
        print("== %d bytes at file 0x%05X (CPU 0x%06X), previously %s" % (n, off, addr, was))
        p = off
        while p < off + n:
            i = decode(img, p, addr - off + p)
            print("   %06X  %-12s %s" % (addr - off + p, img[p:p + (i.size if i else 2)].hex(), i or "db ?"))
            p += i.size if i else 2
    ms43_checksums.fix(img)
    open(out, "wb").write(img)
    print("wrote %s; checksums:" % out)
    ok = ms43_checksums.check(img)
    sys.exit(0 if ok else 1)


if __name__ == "__main__":
    main()
