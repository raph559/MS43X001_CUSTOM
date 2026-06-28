# Live overlay — implementation spec

Everything another session needs to build the live-tuning overlay, with no re-derivation.
Companion documents: `LIVE_OVERLAY.md` (the design), `TUNE_ANALYSIS.md` (which tables and why),
`HANDOFF.md` (state), `REPORT.md` (toolchain and the emulator).

Target: the car's own image, `bins/CAR_current_43X001_SP95_STAGE1.bin`. Work on copies only.
Nothing has been flashed. The program tag (0x6FFF0), the calibration tag (0x7FFF0) and the boot
block are never written.

---

## 0. The safety property that comes for free

The boot block's RAM test writes 0x55/0xAA patterns over **8000–9FFE** (8 KiB board) or
**8000–BFFE** (16 KiB attempt) at every key-on — file 0x2ED6 sets `ADDRSEL2 = 0x0402` and tests
8000–BFFE, the 8 KiB test is at 0x2FD0, and 0x2EF4 falls back to `ADDRSEL2 = 0x0401` when the
16 KiB probe fails [obs].

**The shadow area 9D00–9FDF is inside that range, so the whole overlay state is wiped at every
key-on.** No key-on hook is needed: the overlay is off whenever the engine was last started,
whatever happened in between. The app re-uploads after every key-on.

Consequence for the enable flag: it must live in 9D00–9FDF *and* must not be mistakable for
the RAM test's leftovers. Use a **16-bit magic (0xC0DE)** rather than a 0/1 byte — the test
leaves 0x55/0xAA/0xFF patterns behind.

---

## 1. RAM map (the car's board is 8 KiB — confirmed on the car)

| External RAM | Size | Contents |
|---|---|---|
| 0x9D00–0x9D1F | 32 B | overlay control block (see §2) |
| 0x9D20–0x9DFF | 224 B | shadow: `ip_iga_ron98_pl` (320 B) does **not** fit here — see below |

Recheck the budget: the live set is 606 B of tables and ~26 B of directory, which exceeds the
736 B block only if the directory is counted twice. Exact layout (all in external RAM, page
0x10, so the offset within the page is address − 0x8000):

| Address | Size | Contents |
|---|---|---|
| 0x9D00 | 2 | magic 0xC0DE (overlay enabled) |
| 0x9D02 | 1 | entry count |
| 0x9D04 | 6 × 8 | directory: u16 flash offset, u8 flash page, u16 RAM offset, u8 RAM page, u8 flags, u8 pad |
| 0x9D40 | 320 | `ip_iga_ron98_pl__n__maf` (0x77315) |
| 0x9D80 | 192 | `ip_af_target_ron98__maf__n` (0x7D69C) |
| 0x9E40 | 36 | `ip_iga_ron98_is__n__maf` (0x775D4) |
| 0x9E64 | 24 | `ip_iga_puc__n__tco` (0x7717D) + 12 B RAM descriptor |
| 0x9E80 | 16 | `ip_ti_fac_map__map` (0x7D974) |
| 0x9E90 | 16 | `ip_ti_fac_ti__ti` (0x7D984) |
| 0x9EA0 | 12 | RAM descriptor for `ip_iga_puc` (§4) |
| 0x9EAC | 4 | spare |
| **total** | **604 B** | of 736 B (0x9D00–0x9FDF) |

`c_inj_flow` is **not** shadowed — see §6.

---

## 2. The control block and the directory

```
0x9D00  u16  magic        = 0xC0DE     ; written by the app, cleared by the RAM test at key-on
0x9D02  u8   entry_count  = 0..6
0x9D04  entries[]  (8 bytes each):
          +0  u16  flash offset   (the R12 value at the patched call site)
          +2  u8   flash page     (the R13 value at the patched call site)
          +3  u16  RAM offset     (within page 0x10, i.e. address − 0x8000)
          +5  u8   RAM page       = 0x10
          +6  u8   flags          ; bit0 = active, bit1 = "descriptor form" (§4)
          +7  u8   pad
```

The stub matches on (flash offset, flash page) only — the RAM side is a straight substitution
of R12/R13.

---

## 3. The patch list

Each live table is read with the address in R12 and the page in R13 **immediately before the
call**, so the call target alone is redirected. One 4-byte `CALLS` instruction is replaced by
another 4-byte `CALLS` — same size, no code moves.

| Table | Data | Reader | Call site (file / CPU) | Bytes now | Bytes after |
|---|---|---|---|---|---|
| `ip_iga_ron98_pl__n__maf` | 0x77315 | 0D:029A | 0x2C650 / 0xAC650 | `da 0d 9a 02` | `da 0d xx xx` → stub_A |
| `ip_af_target_ron98__maf__n` | 0x7D69C | 0D:029A | 0x3D40A / 0xBD40A | `da 0d 9a 02` | `da 0d xx xx` → stub_A |
| `ip_iga_ron98_is__n__maf` | 0x775D4 | 0D:029A | 0x2C3A4 / 0xAC3A4 | `da 0d 9a 02` | `da 0d xx xx` → stub_A |
| `ip_ti_fac_map__map` | 0x7D974 | 0D:0262 | 0x4AB5A / 0xCAB5A | `da 0d 62 02` | `da 0d xx xx` → stub_B |
| `ip_ti_fac_ti__ti` | 0x7D984 | 0D:0262 | 0x4AB80 / 0xCAB80 | `da 0d 62 02` | `da 0d xx xx` → stub_B |
| `ip_iga_puc__n__tco` | 0x7717D | 0D:0C72 | 0x2C904 / 0xAC904 | `da 0d 72 0c` | `da 0d xx xx` → stub_C |
| DS2 command 0x6D | — | — | 0x1FC8A / 0x81FC8A | `da 09 b6 ff` | `da 0c xx xx` → handler |

The 0x6D slot is dead in this firmware: the dispatcher sends both 0x6C and 0x6D to 09:FFB6, the
"unknown" reply [obs].

**Note the three call sites of 0D:0C72** at 0x2C8F8/0x2C90E/0x2C924 (descriptors 0x4848, 0x483C,
0x4830) — the warm-up ignition map is one of three variants chosen by condition. Only
0x2C904 (descriptor 0x4848 → table 0x7717D) is in the live set.

---

## 4. The three stubs

One stub per reader, because the stub has to jump to the right reader at the end.

**Register rules.** The stub may use only the registers the reader it replaces already
modifies. For 0D:029A that is **R2, R3, R4, R5, R10, R15, MDH, MDL** (the reader sets R2, R3, R5
itself and uses R4/R10/R15/MDH/MDL). Everything else — R0, R1, R6, R7, R8, R9, R11, R14 — must
come out unchanged, and R12/R13 may change only by the intended substitution. Check the
register use of 0D:0262 and 0D:0C72 the same way before writing their stubs.

**stub_A — replaces 0D:029A (u8 2-axis map, bilinear)**

```
stub_A:
        ; entry: R12 = flash offset, R13 = flash page
        ; 1. if the overlay is off -> jump to real_reader
        ; 2. scan the directory for (R12, R13) with the active flag set
        ; 3. if found: R12 = RAM offset, R13 = 0x10
        ; 4. fall through to real_reader
real_reader:
        JMPA  0Dh, 029Ah
```

**stub_B — replaces 0D:0262 (u8 1-axis curve, interpolating)**: identical logic, ending
`JMPA 0Dh, 0262h`.

**stub_C — replaces 0D:0C72 (descriptor helper)** [the awkward one]

0D:0C72 is not a direct reader: R12 points at a **descriptor** in the constants area, and the
descriptor holds {data_off, data_page, ax1_off, ax1_page, ax2_off, ax2_page}. For
`ip_iga_puc` the descriptor is at file 0x6C848 (CPU 0xC:C848, page 0x3B offset 0xC848).

```
stub_C:
        ; entry: R12 = descriptor pointer (0xC848), R13/R14 = the two axis inputs
        ; 1. if the overlay is off -> JMPA 0Dh, 0C72h
        ; 2. if R12 == 0xC848 (the descriptor of ip_iga_puc) and the entry is active:
        ;       R12 = 0x9EA0  (the RAM descriptor)
        ; 3. JMPA 0Dh, 0C72h
```

The RAM descriptor at 0x9EA0 is a copy of the flash descriptor with the data fields replaced
by the RAM copy of the table (data_off = 0x1E64, data_page = 0x10); the axis fields stay as
they are (they still point into flash, which is correct — the axes are not being edited).

**Alternative:** drop `ip_iga_puc` from the first build. It is 24 bytes of warm-up ignition for
a cold engine and needs a different mechanism. The set still fits without it (580 B).

---

## 5. The new DS2 command

Frame format is the one the existing handlers use (see 09:FF96): `12 <len> <status> <data...>
<xor>`. Status bytes: A0 ack, A1 busy, A2 rejected, B0 parameter error, B1 function error,
FF unknown. The request side follows the read command: `12 <len> 6D <sub> <args...> <xor>`.

| Sub | Direction | Function |
|---|---|---|
| 00 | reply | status: magic present?, entry count, free bytes, overlay enabled |
| 01 | request | upload N bytes into the shadow area at a given offset |
| 02 | request | bind: (flash offset, flash page, RAM offset, size) → create a directory entry |
| 03 | request | unbind one entry |
| 04 | request | revert everything: zero the magic and all the entries |
| 05 | request | write the global fuelling trim (RAM 91B6) |

The handler lives in the free code area (§8) and is entered from the patched dispatcher slot.
Reply with the same status convention; use B0 for a bad length or address.

**Framing detail:** the DS2 payload after the command byte starts at F6D0 in the existing
handlers, with F6D0 = the first payload byte, F6D1.. the rest, and the length in F6D4 for the
read command. The new handler should follow the same convention so the existing receive path
works unchanged.

**K-line budget:** at 9600 baud a 320-byte ignition map is about 0.4 s; the whole 604-byte
shadow about 0.8 s. At the 125000 baud logger rate it is negligible. Upload only the table
that changed.

---

## 6. The global fuelling trim (`c_inj_flow` → RAM 91B6)

The ECU does not read `c_inj_flow` per cycle. At 0xC:AB28 it uses the RAM value **91B6**
(= c_inj_flow × fuel density, with the AFR in 91B8) in the pulse-width calculation
`load × 477 / K`; 91B6 is computed at 0xC:AB4x from the flash constant and stored at 0x4B470
[obs].

So a live trim needs **no shadow and no hook**: the app writes 91B6 directly (2 bytes) through
sub-command 05. Beware of the sign: pulse width ∝ 1/91B6, so a *smaller* 91B6 = more fuel.
The flash constant 0x70E14 is 225 in the car (237 in the release) = +5.3 % fuel.

**In closed-loop areas the lambda trims absorb this** and the driver feels nothing; it shows
up in the open-loop areas (full load, enrichments) and in the trim values.

---

## 7. The program CRC must be extended

The new code sits outside the program CRC range, so the range descriptor has to be extended —
exactly what MS43X001 did for its own code (the car's range 3 ends at 0x0B:FDD1 and range 4
at 0x0C:CB543, while stock 430069 ended at 0x0B:FCB9 and 0x0C:A8CB).

| Item | Value |
|---|---|
| program CRC descriptor | file 0x6FDE0: u16 CRC, u8 count, then count × (u32 start, u32 end) |
| the 4th range | file 0x6FDFC: start 0x0C0000, end **0x0CB543** (u32 at file 0x6FE00) |
| change | the u32 at file **0x6FE00** → the end of the new code, e.g. 0x0CFFFF |
| program SUM32 | covers 0D:0000–0D:3BF8 and 0E:E876–0E:E878 only — unaffected by code at 0C:B545 |
| calibration | untouched by this feature; its CRC/SUM stay as they are |

`tools/ms43_checksums.py` recomputes all five.

---

## 8. Where the new code goes

| Item | File offset | CPU |
|---|---|---|
| free code area | 0x4B545–0x4FFE5 (19,105 B) | 0xC:B545–0xC:FFE5 |
| the only non-erased bytes in 0x4B545–0x4FFFF | 0x4FFE6–0x4FFFF (26 B ASCII programming signature) | — |

**Do not overwrite 0x4FFE6–0x4FFFF.** It is the programming signature, not code, but it is
what the flasher may look for.

Layout suggestion: stub_A, stub_B, stub_C, the DS2 handler, and the directory/control
constants, from 0x4B545 up.

---

## 9. Build order

1. **Write the AS source** for the three stubs and the DS2 handler, in a new file
   `patches/overlay.asm`. Assembler: the Macroassembler AS built in WSL (REPORT.md §9.2),
   target `CPU 80C167`, with `ASSUME DPP0:1Ch, DPP1:3Bh, DPP2:10h, DPP3:3`.
   Note the AS quirk: an absolute ESFR operand inside an EXTR window gets remapped — avoid
   that pattern.
2. **Assemble and disassemble for review** — `tools/to_asl.py` converts the program's disassembly
   to AS and back; `tools/dis.py BIN START COUNT` lists a range.
3. **Apply to a copy** with `tools/ms43_patch.py BASE.bin overlay.asm OUT.bin`. It refuses to
   overwrite anything that is not erased flash, disassembles every written range, and fixes
   the five checksums.
4. **Extend the program CRC range** (file 0x6FE00) as part of the same patch, then re-run
   `tools/ms43_checksums.py OUT.bin` — all five must be OK.
5. **Verify the invariants**: program tag 0x6FFF0, calibration tag 0x7FFF0 and the boot block
   0x0000–0x3FFF byte-identical to the car's file; the program area changed only where
   intended; `git diff` the byte list.
6. **Emulator test** (below) before anything goes near the flasher.
7. **Flash** — only with the owner's explicit go-ahead, and as a separate step from the
   cam-map candidate.

---

## 10. Emulator test plan

The bench is described in REPORT.md §9.1: Ghidra 12.1.4 in WSL with the C166 module v1.2.0
(`XDG_CONFIG_HOME=$HOME/ghidra_emu_cfg`), the NXT-Tronic ms43-c166-emulator, project
`~/ghidra_projects/MS43EMU2`, program `MS43_430069.bin`, and the script
`EmuVirtualPlantPhase4Full.java` (18,000 teeth, 14 subsystems, zero divergence).

What the overlay test must add:

1. **Regression first:** run the existing closed-loop script on the *unmodified* car image and
   on the patched image, and compare the traces. Any divergence in a subsystem that does not
   read a shadowed table means the stub broke something.
2. **Shadow substitution:** preload the shadow area with a recognisable pattern (e.g. the
   ignition map shifted by +1 raw unit), run the closed loop, and confirm the ignition output
   moves by exactly the expected amount in the regions that read 0x77315 — and does **not**
   move in the regions that read the flash copy.
3. **Default-off:** with the magic cleared, the output must be bit-identical to the stock run.
4. **K-line path:** drive the new DS2 command through the emulator's serial model if the
   emulator provides one; otherwise test the handler by calling it directly with a crafted
   frame and check the reply bytes and the RAM contents.

Note the emulator's limits (REPORT.md §9.1): it drives 14 subsystems by direct calls, it does
not run natural start-up, diagnostics sessions or EEPROM writes, and zero divergence is not
proof of correctness.

---

## 11. The app side (`MS43_LOGGER`)

The app already reads TunerPro XDFs, so the MS43X001 definition gives it named, scaled,
car-accurate maps (verified: `show --bin CAR…bin --xdf … ip_iga_ron98_pl__n__maf`).

To add:

- a **Live** panel listing the six live items and nothing else, grouped as Timing / Fuelling;
- upload of a changed table over the new DS2 command, with the λ target shown in λ and AFR
  and the 6990 rpm column marked (that column is deliberately rich and retarded on this car);
- the e85 tables shown as *inactive (E85 setup)* — **live edits must never be mirrored into
  them**;
- a single, always-available **revert** (sub-command 04);
- re-upload after every key-on, because the shadow is wiped by the boot RAM test (§0).

---

## 12. Open risks

| Risk | Mitigation |
|---|---|
| the stub clobbers a register the reader needs | only the reader's own registers may be used; the emulator run is the proof |
| the program CRC range is not extended | §7; `ms43_checksums.py` must show all five OK |
| the app dies with the overlay on | the overlay is wiped at every key-on; the trim revert is one command |
| the K-line is slow at 9600 baud | upload only the changed table; the logger's 125000 baud session is much faster |
| the 8 KiB RAM assumption is wrong on another car | check the RAM-size class byte 8494 at runtime and pick the block; 16 KiB would give A906–BFFF |
