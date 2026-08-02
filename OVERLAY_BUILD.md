# Live overlay — implementation spec

Everything another session needs to build the live-tuning overlay, with no re-derivation.
Companion documents: `LIVE_OVERLAY.md` (the design), `TUNE_ANALYSIS.md` (which tables and why),
`HANDOFF.md` (state), `REPORT.md` (toolchain and the emulator), `patches/README.md` (the built
patch and the assembler constraints).

Target: the car's own image, `bins/CAR_current_43X001_SP95_STAGE1.bin`. Work on copies only.
Nothing has been flashed. The program tag (0x6FFF0), the calibration tag (0x7FFF0) and the boot
block are never written.

**Status 2026-10-19: the patch is written and builds** (`patches/overlay.asm`, see
`patches/README.md`). Both the car's image and the stock 430069 image assemble, apply and verify
(all five checksums OK), with the boot block, the 0x8000 sector, the validity tags and the
calibration data untouched. **The emulator regression is the remaining gate** (§10) — nothing
goes near the flasher before it passes.

**Status 2026-10-20: do not flash the current build.** A review found that it would crash the
ECU (wrong call segment, code at odd addresses, overlapping stubs, a broken DS2 handler), and
that the stock 430069 build patches unrelated code. See `patches/README.md`.

The live set that is implemented (the owner agreed this set):

| Table | Address | Bytes | Reader | Call site |
|---|---|---|---|---|
| `ip_iga_ron98_pl__n__maf` | 0x77315 | 320 | 0D:029A | file 0x2C650 |
| `ip_af_target_ron98__maf__n` | 0x7D69C | 192 | 0D:029A | file 0x3D40A |
| `ip_iga_ron98_is__n__maf` | 0x775D4 | 36 | 0D:029A | file 0x2C3A4 |
| `ip_ti_fac_map__map` | 0x7D974 | 16 | 0D:0262 | file 0x4AB5A |
| `ip_ti_fac_ti__ti` | 0x7D984 | 16 | 0D:0262 | file 0x4AB80 |
| K (the fuelling denominator) | RAM 91B6 | 2 | — | written directly, no hook |

`ip_iga_puc__n__tco` was **dropped**: it is read through 0D:0C72, a *descriptor* helper that
always resolves the descriptor through DPP1 (the constants area), so a RAM descriptor is not
possible and the table cannot be shadowed the same way. It is a 24-byte warm-up ignition map,
not worth a second mechanism in the first build.

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
| 0x9D00–0x9FDF | 736 B | the whole shadow area: 680 B used, 56 B spare |

Recheck the budget: the live set is 580 B of tables and 100 B of directory, which exceeds the
736 B block only if the directory is counted twice. Exact layout (all in external RAM, page
0x10, so the offset within the page is address − 0x8000):

| Address | Size | Ends at | Contents |
|---|---|---|---|
| 0x9D00 | 2 | 0x9D02 | magic 0xC0DE (overlay enabled) |
| 0x9D02 | 2 | 0x9D04 | slot count |
| 0x9D04 | 96 | 0x9D64 | directory: 6 slots × 16 bytes (see §2) |
| 0x9D64 | 320 | 0x9EA4 | `ip_iga_ron98_pl__n__maf` (0x77315) |
| 0x9EA4 | 192 | 0x9F64 | `ip_af_target_ron98__maf__n` (0x7D69C) |
| 0x9F64 | 36 | 0x9F88 | `ip_iga_ron98_is__n__maf` (0x775D4) |
| 0x9F88 | 16 | 0x9F98 | `ip_ti_fac_map__map` (0x7D974) |
| 0x9F98 | 16 | 0x9FA8 | `ip_ti_fac_ti__ti` (0x7D984) |
| 0x9FA8 | 56 | 0x9FDF | spare |
| | **680 B** | | of 736 B

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
| `ip_iga_ron98_pl__n__maf` | 0x77315 | 0D:029A | 0x2C650 / 0xAC650 | `da 0d 9a 02` | `da 0d 45 b5` → stub A |
| `ip_af_target_ron98__maf__n` | 0x7D69C | 0D:029A | 0x3D40A / 0xBD40A | `da 0d 9a 02` | `da 0d 45 b5` → stub A |
| `ip_iga_ron98_is__n__maf` | 0x775D4 | 0D:029A | 0x2C3A4 / 0xAC3A4 | `da 0d 9a 02` | `da 0d 45 b5` → stub A |
| `ip_ti_fac_map__map` | 0x7D974 | 0D:0262 | 0x4AB5A / 0xCAB5A | `da 0d 62 02` | `da 0d 85 b5` → stub B |
| `ip_ti_fac_ti__ti` | 0x7D984 | 0D:0262 | 0x4AB80 / 0xCAB80 | `da 0d 62 02` | `da 0d 85 b5` → stub B |
| DS2 command 0x6D | — | — | 0x1FC8A / 0x81FC8A | `da 09 b6 ff` | `da 0c d5 b5` → the handler |

(The 0x6D slot is dead in this firmware: the dispatcher sends both 0x6C and 0x6D to 09:FFB6, the
"unknown" reply [obs].)

**Note the three call sites of 0D:0C72** at 0x2C8F8/0x2C90E/0x2C924 (descriptors 0x4848, 0x483C,
0x4830) — the warm-up ignition map is one of three variants chosen by condition. That table is
not in the live set (see the header).

---

## 4. The stubs

One stub per reader, because the stub has to jump to the right reader at the end. The stub
*replaces* the reader's `CALLS`, so it is entered with R12 = the flash offset and R13 = the
flash page, and it leaves R12/R13 pointing at the RAM copy when the table is shadowed.

**Both stubs are written** (`patches/overlay.asm`, stub A at CPU 0xCB545, stub B at 0xCB585) —
the design below is what they implement.

**Register rules.** The stub may use only the registers the reader it replaces already
modifies. For 0D:029A that is **R2, R3, R4, R5, R10, R15, MDH, MDL** — read from the whole
reader body (0x5029A–0x5033C): it sets R2, R3, R5 itself, uses R4 as the high half of the
multiply, R10 and R15 for the interpolation fractions, and R12/R13 as the parameters. It
touches nothing else. For 0D:0262 it is **R2, R4, R10, MDH, MDL**. Both stubs use only
**R2, R4, R10**, and both readers re-initialise all three before using them.

Everything else — R0, R1, R6, R7, R8, R9, R11, R14 — must come out of the stub unchanged, and
R12/R13 may change only by the intended substitution.

**The emulator run is the proof** that the stub's register use is safe (see §10).

**The addressing.** The C167 forms the physical address as
`(DPP[segment] << 14) + (offset & 0x3FFF)`, with the segment in bits 15:14 of the 16-bit
address. The shadow at 0x9D00-0x9FDF is therefore segment 2 → **DPP2** (0x10, the external RAM
window), and the stub reaches it with a register pointer holding 0x9Dxx. The substitution it
makes is R12 = the offset inside the 8 KiB window (0x1D00…) and R13 = 0x10, which is exactly
what the reader expects after its own `EXTP R13`. The stub never has to touch DPP0 or DPP1.

**stub_A — replaces 0D:029A (u8 2-axis map, bilinear)**

```
stubA:
        MOV   0FE04h, #010h        ; DPP2 = external RAM
        MOV   R2, #09D00h           ; the control block
        MOV   R10, [R2]             ; the magic
        CMP   R10, #0C0DEh
        JMPR  NZ, Aoff
        MOV   R4, [R2+02h]          ; the slot count
        ADD   R2, #0004h            ; -> the directory
Aloop:  ...                       ; compare (R12, R13) against each slot
        MOV   R12, [R2+04h]         ; the RAM offset
        MOV   R13, [R2+06h]         ; the RAM page
Aoff:
Adone:  CALLS 0Dh, 029Ah           ; then the real reader
        RETS
```

**stub_B — replaces 0D:0262 (u8 1-axis curve, interpolating)**: the same, ending
`CALLS 0Dh, 0262h`.

**The descriptor case is gone.** `ip_iga_puc` was dropped from the live set (see the header),
so no stub for 0D:0C72 is needed.

---

## 5. The new DS2 command

Frame format is the one the existing handlers use (see 09:FF96): `12 <len> <status> <data...>
<xor>`. Status bytes: A0 ack, A1 busy, A2 rejected, B0 parameter error, B1 function error,
FF unknown. The request side follows the read command: `12 <len> 6D <sub> <args...> <xor>`.

The handler reads its request from **F6D0** and builds the reply in **F74E** (length),
**F74F** (status) and **F750** (payload) — the same convention as the read handler at 0A:6A38.
The words in the request are kept 16-bit aligned so they can be read directly:

| Offset | Meaning |
|---|---|
| F6D0 | the sub-command (byte) |
| F6D1 | reserved |
| F6D2/F6D3 | p1 (word) |
| F6D4/F6D5 | p2 (word) |
| F6D6/F6D7 | p3 (word) |
| F6D8/F6D9 | p4 (word) |
| F6DA.. | data |

| Sub | Direction | Function |
|---|---|---|
| 00 | reply | status: F750 = armed (0/1), F751 = the slot count, F752/3 = K (91B6) |
| 01 | request | upload: p1 = the offset in the shadow, p2 = the length (1..123), the data at F6DA |
| 02 | request | bind: p1 = the flash offset, p2 = the flash page, p3 = the RAM offset, p4 = the RAM page; **arms the overlay** |
| 03 | request | unbind: p1 = the flash offset, p2 = the flash page |
| 04 | request | revert: everything back to stock (the magic is cleared) |
| 05 | request | write K: p1 = the new value of 91B6 |

**K-line budget:** at 9600 baud a 320-byte ignition map is about 0.4 s; the whole 580-byte
shadow about 0.8 s. At the 125000 baud logger rate it is negligible. Upload only the table
that changed.

**The order matters:** upload first, then bind (which arms the overlay), because the magic is
what makes the stubs redirect. The boot RAM test wipes the magic at every key-on, so the app has
to re-upload and re-bind after every start.

---

## 6. The global fuelling trim (`c_inj_flow` → RAM 91B6)

The ECU does not read `c_inj_flow` per cycle. At 0xC:AB28 it uses the RAM value **91B6**
(= c_inj_flow × fuel density, with the AFR in 91B8) in the pulse-width calculation
`load × 477 / K`; 91B6 is computed at 0xC:AB4x from the flash constant and stored at 0x4B470
[obs].

So a live trim needs **no shadow and no hook**: the app writes 91B6 directly (2 bytes) through
sub-command 05. Beware of the sign: pulse width ∝ 1/91B6, so a *smaller* 91B6 = more fuel.
The flash constant 0x70E14 is 225 in the car (237 in the release) = +5.3 % fuel.

**Verified that a live write sticks** [ver]: 91B6 and 91B8 are written in exactly one place
(0x4B444 and 0x4B470), and the routine that does it (0xC:41EC) is called from exactly two
places — 0xB:0086, which is the start-up task, and 0xC:367A, which is **unreachable**: the
instruction before it at 0xC:3676 is an unconditional `JMPA 0xC3CBC`, and nothing in the image
jumps or calls to 0xC:367A (MS43X001 left the old call site behind when it refactored the
fuel model). So K is computed **at start-up only**, and a live write to 91B6 survives until the
next key-on.

**In closed-loop areas the lambda trims absorb this** and the driver feels nothing; it shows
up in the open-loop areas (full load, enrichments) and in the trim values. **On this car both
O2 sensors are unplugged**, so there is no closed loop at all and the +5.3 % applies across the
whole map (CAR_TUNE.md, "Lambda").

### 6a. The "application system" values — a possible existing write path

The firmware keeps a set of **runtime-adjustable application-system values in RAM**, copied
from the calibration at start-up by the routine at file 0x1DC06 (CPU 0x9DC06):

| Flash calibration (file offset) | RAM | Value |
|---|---|---|
| 0x700A3–0x700A8 | 80EF–80F4 | `t_ti_as_0..5` — per-cylinder injection time multipliers (128 = 1.0) |
| 0x70092 / 0x70093 | 80DE / 80DF | `t_cam_sp_as_ex` / `_in` — exhaust and intake cam target offsets |
| 0x7009B–0x7009F, 0x70094–0x70096 | 80E0–80EB | `t_lshpwm_as_*` — lambda sensor heater duty offsets (pointless with the sensors unplugged) |

(0x70092 and 0x700A3 are the *file* offsets; the code reads them as calibration-page offsets
0x0092 and 0x00A3 with DPP0 = 0x1C.)

Only the start-up routine writes them in the program area; everything else only reads them
[obs]. So they are *designed* to be changed at runtime — by BMW's "application system" write,
for which we have not found a DS2 command (the adaptation-write blocks at 0x8221, 0x8321, …
are elsewhere and hold learned values).

**One detail that matters:** the copy at 0x9DC06 is skipped entirely when **FD1C.0** is set
(`JB FD1Ch.0, 0x9DC2h` at file 0x1DC06) — i.e. once something has written those values at
runtime, the start-up routine will not overwrite them with the flash defaults. That is
consistent with the application system being designed for runtime writes.

**Worth one question to an expert:** if there is a K-line command that writes the
application-system values, the overlay could use it instead of a new command, and the cam
offset would become a live knob for free. Until that is answered, the plan stays as written
above. The RAM addresses 80DE–80F4 are inside 8000–9FFE, so the boot RAM test wipes them at
every key-on as well.

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

## 10. Emulator test plan — **BLOCKED on the bench, not on the patch**

The gate before anything goes near the flasher. The bench cannot currently run it: the
closed-loop script `EmuVirtualPlantPhase4Full` aborts with "Remainder by 0" **on the unmodified
stock image** (REPORT.md §9.1), and a focused probe shows the calibration read does not come
back and the script-side memory writes are byte-swapped.

What is ready:

| Probe | What it does |
|---|---|
| `emu/ProbeOverlayReader.java` | the reader 0D:029A on its own, and the stub with the overlay armed - the same bytes and one step up |
| `emu/ProbeOverlayDiag.java` | diagnostics: where the reader actually read from, the flags, the bytes at candidate addresses |
| `emu/ProbeOverlayRam.java` | the same test entirely inside the external RAM, so it does not depend on the calibration read at all |

Run them with `~/emu_runs/run_emu.sh <image.bin> <script.java> <log>` (it clears the Ghidra
project lock before and after, which a crashed run leaves behind).

The pass condition, once the bench is fixed:

1. **Control** (unmodified stock): the reader returns the calibration byte; the stub cases are
   the control's own values, because there is no stub.
2. **Patched**: the reader alone = the calibration byte; the stub with an identical copy in RAM
   = the same byte (the stub must be transparent); the stub with every byte one step up = one
   more.
3. **Regression**: the patched image with the overlay disarmed must behave exactly like the
   unmodified image in the closed-loop run.
4. **The DS2 handler** has not been exercised at all: its frame parsing, the upload copy loop
   and the bind/unbind/revert logic are only desk-checked so far.

**Until 1–3 pass, the image must not be flashed.** The current build
(`build/CAR_43X001_SP95_STAGE1_OVERLAY.bin`) is a work in progress, not a candidate to flash.

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
