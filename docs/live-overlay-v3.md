# Live overlay protocol 3

This candidate keeps all five original u8 tables in RAM and updates an active table in checked groups of eight cells. It does not program flash at runtime. It is specific to the pinned `CAR_current_43X001_SP95_STAGE1.bin` donor, SHA-256 `8cfe31241aa90717195077f1d931ec3bd28e0e76b435a89472dc1fbdfe6c0717`.

Build with `python tools/build_live_overlay_v3.py`. The new output is `build/CAR_43X001_SP95_STAGE1_LIVE_OVERLAY_V3.bin`; the V1 and V2 artifacts are retained. Assembly lives in `patches/live_overlay_v3.asm`, and the committed simulator fixture is `sim/tests/Ms43Sim.Tests/fixtures/live_overlay_v3.hex`. The builder retains the donor hash, write allowlist and five checksum checks of the V2 builder.

## Memory ownership

| Use | Physical address | Bytes |
| --- | --- | ---: |
| Main ignition | `041D00–041E3F` | 320 |
| AFR target | `041E40–041EFF` | 192 |
| Exhaust cam | `041F00–041FBF` | 192 |
| Private patch request | `041FC0–041FDF` | 32 |
| Control, session, directory | `00E6B0–00E6DF` | 48 |
| Idle ignition | `00E6E0–00E703` | 36 |
| Intake cam | `00E704–00E7C3` | 192 |
| Revision counter | `00E7C4–00E7C7` | 4 |

The map payload totals 932 bytes; the entire allocation totals 1,016 bytes. There is no unallocated space inside these two windows. All locations are fixed, so freeing one map does not allow another to move into it.

The internal window was identified as a disabled service monitor's storage. The ordinary boot entry requires words `A55A` and `C956` at `00BFFC` and `00BFFE`; the pinned donor contains zero at both. The boot RAM test clears the window before application handover. The prior RAM investigation covered static accesses, ten baseline runs, three canary runs and original-reader equivalence. That evidence supports this particular donor; it is not a general allocation guarantee for other firmware or service modes. The service monitor must remain disabled.

## Active update

The DS2 handler runs in the cooperative application task. Original foreground table readers cannot be suspended by it. The update sequence is:

1. Copy the complete 32-byte patch payload out of the receive buffer into private RAM.
2. Check packet CRC, session, revision, table, state and aligned bounds.
3. Calculate the current complete table's CRC and require the supplied before CRC.
4. Calculate the exact prospective complete table CRC from the verified before CRC and the eight-byte XOR difference, advanced over the unchanged suffix with GF(2) matrices. Require the supplied after CRC. No active byte changes during this calculation.
5. Load four new words into registers, then execute `EXTP R14,#4` and four aligned word stores.
6. Read back those four words and compare with the private snapshot, store the already checked after CRC, advance the revision and acknowledge.

The table remains On throughout a successful patch. The foreground task is occupied during validation, but normal interrupts remain enabled except for the short extended-address instruction sequences. `EXTP` protects its four following instructions from standard interrupts, PEC and class A traps. Class B traps and resets are outside that guarantee. See the [Infineon instruction set manual, page 39](https://www.keil.com/dd/docs/datashts/infineon/c166ism.pdf).

Post-write validation checks only the changed words: the full current-table CRC pass and exact CRC difference calculation already proved the before contents and prospective result, and no other supported application writer owns the remaining bytes. This avoids repeated full-table scans in the cooperative task. For equal-length messages, `CRC(old) XOR CRC(new)` equals a zero-initialized, non-finalized CRC of their XOR difference; leading zero bytes leave the zero remainder unchanged. The eight changed bytes and unchanged suffix therefore determine that difference exactly. `tools/generate_crc_zero_powers.py` generates the nine zero-byte advance matrices. The compiled firmware calculation is checked against an independent complete-table CRC for every even window in all five table sizes, using arbitrary byte values (451 cases).

Unexpected RAM faults outside the changed words after validation are outside this guarantee. A changed-word readback failure advances the revision, switches the table to Ready and refuses the command with Integrity.

The atomic unit is eight consecutive byte cells, with an even starting offset. It is not an entire selected rectangle or table. Unchanged cells in a group retain their prior values. A large edit is a sequence of complete groups, and intermediate tables contain completed new groups plus remaining old groups. Transfer failure leaves completed groups in place. The client reads back that state before further edits; it does not silently roll back the completed groups.

## Wire contract

DS2 framing remains `12 length payload xor`. All integers on the wire are big-endian. RAM words/dwords are little-endian. Offsets below exclude framing unless stated otherwise.

- `6D 00`: 60-byte framed status. The 56-byte payload starts with `LTOV`, version 3, flags (bit 0 running), five eight-byte entries, free map bytes, session32 and revision32. Each entry is state8, reserved8=0, page-offset16, full-table CRC32. Free entries have zero offset/CRC. Status remains a keep-alive and does not advance the revision.
- `6D 0A session32`: open a nonzero session. A new token resets revision to zero and keeps maps active. Repeating the current token is idempotent.
- `6D sub session32 expectedRevision32 args`: existing operations 1–8 (Load, Write, On, Off, AllOn, AllOff, Free, Revert). They require the current session/revision. A successful operation advances revision once. Load requires the table's exact fixed page offset. Inactive Write carries at most 112 data bytes and refuses an On table. On/AllOn verify full-table CRCs.
- `6D 09` followed by the 32-byte patch below. Complete framed length is 37 bytes.

| Patch offset | Content |
| ---: | --- |
| 0 | Session32 |
| 4 | Expected revision32 |
| 8 | Table8 |
| 9 | Reserved8 = 0 |
| 10 | Even start offset16 within the table; eight bytes must fit |
| 12 | Before-table CRC32 |
| 16 | After-table CRC32 |
| 20 | Eight replacement bytes |
| 28 | CRC32 of patch bytes 0–27 |

All CRCs use CRC-32/ISO-HDLC. A success is framed `A0 revision32` (eight bytes). Refusals retain the five-byte B0/B1 format; reasons 12 and 13 mean Session and Revision. Packet/contents mismatches use Integrity (9).

A patch for the immediately preceding revision may be acknowledged again without a write only if its requested after CRC matches the current entire table. Other old revisions and other sessions are refused. The counter never wraps; at `FFFFFFFF` a new session is required. The token and CRCs guard against stale/corrupt traffic, not a hostile diagnostic client.

## Client and operating limits

The logger detects protocol 2 and 3 separately. V2 keeps its old allocation and edit bounds. V3 retains the original table encoding and permits the full representable u8 range, including leaner AFR targets; representability is not an engine-safety limit.

Initial load uses the flashed map, writes differences while inactive, reads the entire result back, and activates it with its CRC. Subsequent active edits use only patch messages. A lost patch acknowledgement causes one identical retry; the client does not invent a new revision. Following an uncertain partial transfer it reconciles the actual map on its next successful status/readback. A key cycle clears RAM and requires a fresh session and reupload; a stall or silence disables overlays. The silence deadline remains 300 processed firmware ticks, nominally three seconds, not an independent hardware timer.

The matching logger sends the first active patch immediately, then leaves at least 100 ms after each patch response or timeout before another patch. This includes an identical retry. An edit made after that interval has already elapsed needs no added wait. The worker waits outside the serial request lock, allowing telemetry polls to continue. The firmware does not enforce this spacing against arbitrary clients. Unpaced sustained updates produced simulator injector timing findings even when writing unchanged values; the optimized CRC calculation and paced production client are the candidate configuration.

Run the firmware checks with:

```powershell
dotnet test sim/tests/Ms43Sim.Tests --filter FullyQualifiedName~OverlayV3
```

Tests exercise the compiled protected stores, pending interrupts/PEC, full firmware K-line updates at idle and high RPM, all five RAM reader destinations, snapshot corruption resistance, stale requests, revision carry/overflow, lost-ack replay, failed readback and silence fallback. Logger tests and the production-client-to-emulated-firmware integration harness are in the logger checkout.

The simulator excludes periodic-task deadlines and overload flags at or above 2,000 rpm from its verdict because the donor already exceeds those checks in its timing model. Watchdog and crank-task checks still run at high RPM. A Pass is limited to applicable software checks. Cable timing, hardware RAM ownership under all real modes and engine calibration safety require bench/vehicle evidence; no ECU was flashed as part of this implementation.
