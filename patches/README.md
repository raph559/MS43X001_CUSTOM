# MS43X001 live-calibration overlay - the built patch

`patches/overlay.asm` is the source, `build/` holds the assembled images.

> **Do not flash any image built from this source.** A byte-level review on 2026-10-20 found
> defects that would crash the ECU at the first redirected table read, with the validity tags
> still valid (the dangerous failure in REPORT.md §9.4):
>
> - the five call sites call segment 0Dh (`CALLS 0Dh, B545h`), but the stubs are in segment 0Ch
> - the stubs and the handler start at odd addresses (0x4B545, 0x4B585, 0x4B5D5), and the C167
>   traps on a branch to an odd address. Free flash starts at 0x4B544
> - the stubs overlap: stub A runs into stub B, and the handler overwrites stub B's `RETS`
> - the DS2 handler fails on every sub-command: status reads K as a word at the odd address
>   FB6B (K is at 91B6), upload copies from the wrong source, and every sub-command from 02 up
>   runs bind, so revert does not revert
>
> The source has to be rewritten and tested before anything built from it is flashed.

## What the patch does

| Where | Change |
|---|---|
| file 0x4B545 (CPU 0xCB545) | stub A: redirects a table read to the RAM shadow (for the u8 map reader 0D:029A) |
| file 0x4B585 (CPU 0xCB585) | stub B: the same for the u8 curve reader 0D:0262 |
| file 0x4B5D5 (CPU 0xCB5D5) | the DS2 command 6D handler (upload / bind / unbind / revert / write K) |
| file 0x2C650 | `CALLS 0Dh, 029Ah` → `CALLS 0Dh, B545h` (ip_iga_ron98_pl) |
| file 0x2C3A4 | → stub A (ip_iga_ron98_is) |
| file 0x3D40A | → stub A (ip_af_target_ron98) |
| file 0x4AB5A, 0x4AB80 | → stub B (ip_ti_fac_map, ip_ti_fac_ti) |
| file 0x1FC8A | the DS2 dispatcher slot for command 6D → the handler |
| file 0x6FE00 | the program CRC range 4 end: 0x0CB543 → 0x0CFFFF, so the new code is covered |

Everything else is untouched: the boot block, the 0x8000 service sector, the validity tags, the
ASCII programming signature at 0x4FFE6 and all calibration data except the two CRC bytes.

## Build

```bash
# in WSL
cd ~/src/asl_dl/asl-current
./asl -q -L -olist overlay.lst overlay.asm
./p2hex -q -F Intel32 -l 32 overlay.p overlay.hex
```

or, from the project root (this also applies the patch, disassembles every written range and
recomputes the five checksums):

```bash
python -I tools/ms43_patch.py bins/CAR_current_43X001_SP95_STAGE1.bin \
    patches/overlay.asm build/CAR_43X001_SP95_STAGE1_OVERLAY.bin --allow-overwrite
```

`--allow-overwrite` is required: the five call sites, the dispatcher slot and the CRC range end
are existing code. The tool lists every overwritten range for review.

Applying this source to the **stock 430069 image** does not give a valid test image: stock does
not have these call sites. At those offsets it has other instructions or erased flash, and
0x1FC8A is a real handler call (`CALLS 0Ah, 9278h`), so the patch overwrites unrelated code
there.

## Assembler notes (AS / Macroassembler asl, target 80C167)

Things that cost time and are worth keeping:

- **Hex literals need a leading digit**: `0A0h`, not `A0h`. `A0h` is read as a symbol.
- **Far call targets are 16-bit offsets inside the segment**: `CALLS 0Dh, 0B545h`, not
  `CALLS 0Dh, 0CB545h` (that is a range overflow).
- **JMPR is a short relative jump** (about ±128 bytes). Use `JMP label` (JMPA, 4 bytes) for
  anything further. `JNE`/`JE` do not exist: use `JMPR NZ, label` / `JMPR Z, label`.
- **Byte registers are RL0..RL7 and RH0..RH7** (the bytes of R0..R7). `R4L` style is accepted
  by the assembler but assembles to a different encoding - use `RL4`.
- **`MOVB <mem>, #imm` is not allowed.** Load the immediate into a byte register first:
  `MOVB RL3, #01h` then `MOVB 0F750h, RL3`.
- **`DEC` / `DECB` do not exist.** Use `SUB Rn, #0001h`.
- **SFRs must be written numerically** (`0FE00h` = DPP0, `0FE04h` = DPP2) so the assembler
  picks the SFR instruction form. Writing `DPP0` produces a data move instead.
- The conditions are `Z, NZ, UC, C, NC, SGT, SLE, SLT, SGE, UGT, ULE` - there is no plain
  `GE` or `GT`.
- `DW` holds 16 bits only; a 32-bit value has to go in as `DB` bytes.

## Addressing notes (why the stub is shaped the way it is)

The C167 forms the physical address as **(DPP[segment] << 14) + (offset & 0x3FFF)**, where the
segment is bits 15:14 of the 16-bit address:

| Address | Segment | Page | Used for |
|---|---|---|---|
| 0x9D00-0x9FDF | 2 | DPP2 = 0x10 | the external RAM (0x40000 window) - the shadow |
| 0xF6D0, 0xF74E, 0xFB6B | 3 | DPP3 = 0x03 | the internal RAM - the DS2 request, the reply, K |
| 0x3315 | 0 | DPP0 = 0x1D | a calibration table (the reader does `EXTP R13` itself) |

So the stub never has to change DPP0 or DPP1: it only sets DPP2 (already 0x10) and reads the
shadow through a register pointer holding 0x9Dxx. The substitution it makes is R12 = the offset
inside the 8 KiB window (0x1D00..) and R13 = 0x10, which is exactly what the reader expects
after its own `EXTP R13`.

## Registers the stubs may touch

The stub replaces the reader, so it may only clobber what the reader clobbers:

- 0D:029A: R2, R3, R4, R5, R10, R15, MDH, MDL
- 0D:0262: R2, R4, R10, MDH, MDL

Both stubs use only **R2, R4, R10**, and both readers re-initialise all three before using them.
