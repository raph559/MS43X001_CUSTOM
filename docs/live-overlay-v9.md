# MS43X001 live overlay protocol 9: the watched map and the feature triggers

V9 adds two things to [V8](live-overlay-v8.md). The **watch**: the ECU records the exact cell it read
in one map, the one on the app's screen, and returns it with each logging reply. The **triggers**:
launch control, no-lift shift and rolling anti-lag can be made ready by the A/C button or another CAN
bit, as V8's pops switch can. Everything else keeps V8's IDs, addresses, protocol rules and checks.
The design is the source contract, and the plan is
the source contract.

## Identification

- The header at `0C:B544` carries version 9 and a count of 139 (no new group). The runtime magic is
  `C0D9`. `data_end` stays `0CFF88h`.
- The builder is `tools/build_live_overlay_v9.py`. `tools/live_overlay_v9_watch.py` generates
  `patches/live_overlay_v9.asm`, `live_overlay_v9_feature_helpers.inc`, `live_overlay_v9_feature_stubs.inc`
  and `live_overlay_v9_pops.inc` from V8's (and V6's) sources by checked substitutions. The hand-written
  parts are `live_overlay_v9_watch.inc` and `live_overlay_v9_triggers.inc`.
- The new code sits in the free flash after the CRC tables, from `0C:EB5E`, below pops' defaults at
  `0C:FF80`; an assembler guard fails the build if it would reach them. It is inside CRC range 4.
- Program identity `5906167b…69c1` (the emulator's `ProgramIdentity.Ms43X001LiveOverlayV9`).

## RAM

The watch takes the 20 bytes at the end of pool A below pops' four, logical 680..699, CPU `041FA8..041FBB`
(through DPP2, `9FA8h..9FBBh`). Pool A allocations may no longer reach logical 680, and the status reports
908 bytes.

| CPU | Size | Name | Meaning |
|---|---|---|---|
| `9FA8h` | word | `W_WOFF` | the watched flash offset |
| `9FAAh` | word | `W_WPAGE` | the watched flash page; `0FFFFh` = no watch |
| `9FACh` | word | `W_AOFF` | the live copy's offset |
| `9FAEh` | word | `W_APAGE` | the live copy's page; `0FFFFh` = none |
| `9FB0h` | byte | `W_KIND` | 0 none yet, 1 map indices, 2 curve index, 3 map inputs, 4 curve input |
| `9FB1h` | byte | `W_COUNT` | reads of the watched map, wraps at 256 |
| `9FB2h`..`9FBAh` | | `W_ROW`, `W_ROWF`, `W_COL`, `W_COLF`, `W_COLS` | indices and fractions, or the inputs |
| `9FBBh` | byte | `W_ROWIX` | the watched map's catalogue row, `0FFh` = not in the catalogue |
| `FDF8.5` | bit | `W_ON` | a watch is set and armed: the hooks compare only while it is |
| `FDF8.6` | bit | `W_CP` | the watch has a live copy: the hooks compare `W_AOFF`/`W_APAGE` only then |

`FDF8` bits 5 and 6 are free (V8's note: no code in the car file or in V7 uses bits 3 to 13; V8 uses 3 and 4).
Fast on-chip storage for the offset was tried and dropped: CC26 looked free on one drive, but the car file
switches it on (CCM6 = 0655h) on another, so V9 writes no SFR.

## The watch's hooks

- **The 8 readers** (`0D:0168`, `029A`, `03D2`, `043A` maps; `022A`, `0262`, `0454`, `042E` curves):
  `JMPS 0Ch, watch_rdN` replaces the entry's `MOVBZ Rx, FB6Bh`. With no watch the stub tests `W_ON` and runs the
  displaced instruction. With one it compares R12 with `W_WOFF` (another map's read falls through), tests `W_CP`,
  and compares the page, or the live copy's offset and page, only after a match. On a match it records
  `FB6B`/`E390`/`FB6C`/`E392`/`FB6D` (curves: no column fields) and counts the read.
- **The 16 descriptor lookups**: the hook is the `MOV DPP0` after the descriptor's unpacking, not the helper's
  entry, as the plan's reading corrected: there R12:R10 is the data address, R13 the row input and R14 the
  column input, and V7's live word maps (which enter at `0D:04B0`/`09BC` with their RAM copy's address)
  pass through it too. `0D:1092` moves R11, not R5.
- **Cost** (emulator, full load in 3rd at 100 km/h, cycles per pass through a hooked site; stock 6.0):
  70.6 before the fast path above, 35.6 now with no watch (3.3 % of the CPU there) and 62.6 watching the
  part-load ignition map (5.5 %). Each instruction fetched from segment 0C costs about 7 cycles.
- **Open: P1567 at sustained full load.** On the cross-check drive's full-load hold (3rd, 100 km/h, pedal 95,
  after two minutes of driving) with the logger polling sub 11 at full speed, V9 stores P1567 (`msw_tog`, the
  steering-wheel toggle), with or without a watch; V8 polling `0B B0` does not. Without the logger it no longer
  does (it did before the fast path). There the car file's own lowest queue already waits seconds at the ISM's
  minimum timing (the scheduler check's declared gap), and the toggle check gives 1.7 s. Whether the real ECU is
  that loaded is unknown: a car check decides it.
- **The emulator runs short of CPU time where the car does not.** A full-throttle pull in 2nd from 30 to
  88 km/h (past 5,000 rpm) overflows task queues 2 and 3 (`FD84` = `0185h`) on the stock car bin, V8.5 and
  V9 alike. On the car (2026-11-04, V8.5, several such pulls in one key-on) the fault memory read
  "no overflow". So the emulator's load is too high for stock too, and V9's P1567 there may be the same
  shortfall; only a V9 drive on the car settles it.
- Every record write runs with `IEN` held off (`PUSH PSW`, `BCLR IEN`, `POP PSW`, as stock does at
  `0C:A314`), and the displaced instruction runs last, so every register and flag the original code reads
  is as it left it.
- **The live copy.** `watch_alias` (from housekeeping every 10 ms, and from `watch_set`) points
  `W_APAGE:W_AOFF` at the watched map's RAM copy while its catalogue row holds an allocation. `sub_load`,
  `sub_free`, `sub_revert` and `all_off` (AllOff, the frame after a stop or a silence, housekeeping's own
  switch-off) clear it before they change anything, so a freed copy's RAM given to another table is never
  recorded as the watched map.
- **Limit:** `hard_gears` reads its uncatalogued table `W_HARD` through `0D:042E`; watching the gears' flash
  table shows "not read" while the hard cut is on.

## The two sub-commands

- **Sub 12, `6D 0C a2 a1 a0`:** sets the watch to the app address (page × 4000h + offset). Reply
  `12 07 A0 a2 a1 a0 cs`. Address 0 clears it; `80000h` or more is refused with `B0` reason 4. It needs no
  session. Any set clears the record and the count and finds the map's catalogue row.
- **Sub 11, `6D 0B`:** logs. It calls the stock `0B B0` handler (`CALLS 0Ch, 467Eh`), sets the length to
  `58h` and copies the record big-endian to `F799..F7A3` with `IEN` held off. The reply is 88 bytes:
  `12 58 A0`, the stock payload unchanged, `KIND COUNT ROWh ROWl ROWFh ROWFl COLh COLl COLFh COLFl COLS`,
  the checksum. It needs no session and stamps the keep-alive.
  So logging alone keeps live settings on. When the app's live-tuning session stops on an error, the app
  logs with `0B B0` until a new session starts (`WatchingPayloadSource.Quiet`), and the overlay puts its live
  settings back to flash 3 s later, as on V8.
- `0B B0` stays byte for byte as it was.
- **DPP2.** The hooks reach `W_*` through DPP2, not `EXTP #10h`, to keep the watching path short. That holds
  while DPP2 is 10h at every hooked lookup. The stock code changes it only in its flash-to-RAM copy at
  `0E:2FAE` (behind the `FD52`/`FD6E` request flags), which never ran on the drives. `WatchDppTests` checks
  DPP2 = 10h at every pass through the 24 sites on six drives, cold start to full load, with and without a
  watch (about 3.9 million passes). If that copy ran with a watch set, the worst case is a missed or wrong
  record.

**The watch ends** after 3 s without a `0x6D` frame (`watch_quiet`, in housekeeping), but not at engine-off,
unlike V8's `off_due`: watching changes nothing the engine reads, and reads at key-on must stay visible.
Before the app's first frame since boot there is no watch.

## The triggers

- Each feature's activation byte (`c_conf_lc` 0x7132C, `c_conf_nls` 0x71334, `c_conf_ral` 0x7133C) may hold
  a trigger in pops' encoding: 80h..9Fh, bit 4 the frame (0 the ASC's 153h, `EF47`; 1 the A/C's 615h,
  `EF37`), bit 3 the polarity, bits 0..2 the bit of byte 0. A/C on is `97h` (the owner's car check,
  2026-10-29: byte 0 reads `0000 0000` off, `1000 0000` on).
- V6's activation-byte read stubs call `trigger_effective`: below 80h the byte passes through (LC/NLS 0..2,
  RAL 0..1, as stock); 80h..9Fh reads as 1 while the feature's `FDF8` bit is set (engaged) and as its CAN
  bit's state otherwise; A0h and above read as 0. So the trigger only makes the feature ready, gates
  engagement only, and an engaged feature ends the stock way (the clutch, the pedal, the speed gates).
- `can_bit_matches` is shared with pops' switch. Validation (live writes and Patch) accepts 0..2 or
  80h..9Fh for LC/NLS and 0..1 or 80h..9Fh for RAL; RAL keeps its neighbour rule. RAL has no cruise-light
  trigger: stock RAL is blocked while the cruise main switch is on (owner, 2026-10-29: dropped).
- ASC off waits for the owner to read the ASC button's bit; the firmware already accepts any 80h..9Fh.

## Verification (2026-10-29, in the emulator)

- **Direct CPU tests:** `OverlayV9Tests` (header, pool A, the watch sub, the quiet expiry, `0B B0` unchanged),
  `WatchReaderTests` (each reader stock when not watched, records indices, the live copy, IEN off),
  `WatchDescriptorTests` (the same for the 16 lookups, and V7's live word map through its RAM copy),
  `WatchAliasTests` (the alias follows a load and is cleared before Free, Revert, AllOff and the switch-off),
  `WatchLogTests` (the reply, IEN off, and an interrupt raised inside the copy never tears the record),
  `TriggerTests` (each feature engages only with its trigger and its own action, stays engaged when the
  trigger goes, polarity and frame, validation, a flashed trigger without the app). V6's LC/NLS/RAL tests
  and the pops tests also run on V9.
- **Whole drives** (`sim/drives/watch`, `WatchDriveTests`, with `kline poll 6D 0B` and `kline watch`):
  every log reply on the part-load drive carries the last read an independent oracle saw, with the right
  count; the idle ignition map counts at idle and stops within 1 s of the blip; the overrun-cut ignition
  map `ip_iga_puc__n__tco` is read in the overrun. Watching a map against watching an address no table has
  changes no fault, power cycle, verdict or check.
- **Logging rate:** on the K-line pause drive, V9 logging with the watch on gets 21.73/s and V8 polling
  `0B B0` 20.99/s, with the scheduler check passing. The spec's 22.5/s floor was set from the car file's
  23.4/s; V9 is not slower than V8.
- **Against V8, nothing loaded** (`ms43sim compare`, `build/compare-v8-v9`): warm-start, cold-start, idle,
  key-cycle, overrun and part-load pass, and no drive has a fault or power-cycle difference. Full-load fails
  V9's injector check (99 % of the engine cycle at 7,100 rpm, limit 98 %). That is drift: the same drive
  fails the check on V8 (100 %) and V7 (98 %) in the test harness, and passes on V7 with K-line polling. The
  tune's flame band at the limiter holds injector duty on that line whatever the overlay.
- **What the emulator cannot judge:** combustion, exhaust temperature, the physical K-line and the real
  ECU's timing. The first request after the connect's speed switch was lost in the emulator; the app must
  resend the watch until it is acknowledged. Physical ECU operation and engine safety remain to be shown
  on the car.
