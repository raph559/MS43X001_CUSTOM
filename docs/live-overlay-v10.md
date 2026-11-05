# MS43X001 live overlay protocol 10: pops stabs and the downshift blip

V10 adds two things to [V9](live-overlay-v9.md). The **stabs**: a pops window first loads at the plain throttle
opening, then gives the throttle short stabs, so the bangs come as a series instead of a crackle. The **blip**: on a
downshift the ECU opens the throttle by itself, either while braking or after a short tap of the pedal, toward the
lower gear's rpm at the road speed. Everything else keeps V9's IDs, addresses, protocol rules and checks. The design
is the source contract, and the plan is
the source contract.

## Identification

- The header at `0C:B544` carries version 10 and a count of 143 (groups 139..142 added). The runtime magic is
  `C0DA`. `data_end` becomes `0CFFA8h`, still inside CRC range 4 (`0C:0000..0C:FFA7`).
- The builder is `tools/build_live_overlay_v10.py`. `tools/live_overlay_v10.py` generates
  `patches/live_overlay_v10.asm`, `live_overlay_v10_feature_helpers.inc` and `live_overlay_v10_pops.inc` from V9's
  sources by checked substitutions (each must match exactly once). The hand-written parts are
  `live_overlay_v10_groups.inc` (the four groups' limits, reads and validation) and `live_overlay_v10_blip.inc` (the
  stabs, the torque guard, the blip and the re-entry hook).
- The new code sits after V9's, from `0C:F754` to `0C:FBF2`, below pops' defaults at `0C:FF80`; the assembler guard
  still fails the build if it would reach them.
- Program identity `51d7ddd6…98fc` (the emulator's `ProgramIdentity.Ms43X001LiveOverlayV10`). A bin with edited
  flashed settings is recognised too: the identity is taken with V10's 40 default bytes at `0x4FF80` put back.

## RAM

V10's state takes the 12 bytes below the watch, logical 668..679 of pool A, CPU `041F9C..041FA7` (through DPP2,
`9F9Ch..9FA7h`). Pool A allocations may no longer reach logical 668, and the status reports 896 bytes free.

| CPU | Size | Name | Meaning |
|---|---|---|---|
| `9F9Ch` | word | `POPS_T` | 10 ms ticks since the pops window started, saturating |
| `9F9Eh` | word | `BLIP_ADD` | the blip's throttle addition now, in `86A4` units |
| `9FA0h` | word | `BLIP_LEFT` | 10 ms ticks left in the blip |
| `9FA2h` | byte | `POPS_PH` | 10 ms ticks left in the current stab or gap |
| `9FA3h` | byte | `BLIP_CL` | 10 ms ticks since the clutch went in, saturating at 255; 0 while it is released |
| `9FA4h` | byte | `BLIP_TGT` | the blip's target, in `807F` units (32 rpm) |
| `9FA5h` | byte | `BLIP_TAP` | 10 ms ticks since the pedal rose past the tap threshold |
| `9FA6h..9FA7h` | | | spare (V10.1: `BLIP_PREV`, `BLIP_RATE`, below) |
| `FDF8.7` | bit | `POPS_STAB` | a stab is on |
| `FDF8.8` | bit | `BLIP_ON` | a blip is running |
| `FDF8.9` | bit | `BLIP_USED` | this clutch press has had its blip, or the pedal is the driver's for it |
| `FDF8.10` | bit | `BLIP_ARMED` | the pedal has been below the tap threshold since the clutch went in |
| `FDF8.11` | bit | `BLIP_TAPPING` | the pedal rose past the threshold after the clutch went in |
| `FDF8.12` | bit | `BLIP_HOLD` | the blip has reached its target band |
| `FDF8.13` | bit | `GUARD` | the torque guard is acting |

## The groups

Every group is 8 bytes, as every V8 and V9 group is (RF-C1 of the plan): `feature_write_validate` takes one whole
group, `feature_address` maps a byte within an 8-byte span, and the app checks each group's address and size against
the ECU's table list. So the spec's "138 grows" and "an 18-byte 139" became four new groups, IDs 139..142, with bits
3..6 of `W_BITMAP` byte 17 and flash defaults at `33h:3F80h + 8·(ID − 138)`. A byte cannot hold 300, so the stab
size, the blip opening and the hold opening are in 0.2 °TPS steps, 0..150 (RF-C2). The tap threshold is in `E0FF`'s
own unit, 0.46875 °PVS, so the spec's 5..40 °PVS is 11..85; and as the app edits one byte per setting, the two signs
are one three-way byte and each downshift has its own Off/On byte. Every value read is clamped to
its limits (`v10_setting`); a copy with any byte outside them is refused on Write, Patch, On and AllOn with reason 4
(`v10_validate`, from `feature_validate` and `feature_write_validate`), and so is a blip copy whose hold opening is
above its blip opening.

| ID | Address | Title in the app | Bytes (limits, default) |
|---|---|---|---|
| 139 | `0C:FF88` | Pops stabs | load time 0.1 s (0..50, 20); stab size 0.2 °TPS (0..150, 75); stab length 10 ms (5..30, 15); gap 10 ms (10..100, 25); 4 reserved |
| 140 | `0C:FF90` | Downshift blip | switch as pops' byte 0 (0..2 or 80h..9Fh, 0); signs 1 braking, 2 a tap, 3 either (1..3, 3); minimum speed km/h (10..255, 30); maximum rpm 32·X (63..187, 187); maximum time 0.1 s (3..30, 15); blip opening 0.2 °TPS (0..150, 75); hold opening 0.2 °TPS (0..150 and at most the blip opening, 25); spark angle 0.375·X − 23.625 °BTDC (63..143, 90) |
| 141 | `0C:FF98` | Downshift blip: gears and tap | 5th → 4th, 4th → 3rd, 3rd → 2nd (0..1, 1); 2nd → 1st, on a tap only (0..1, 0); tap threshold in `E0FF` units, 0.46875 °PVS (11..85, 21); tap length 10 ms (10..60, 40); 2 reserved |
| 142 | `0C:FFA0` | Downshift blip: gear ratios | rpm per km/h of 1st, 2nd, 3rd, 4th in 0.5 steps (180..255, 226; 100..160, 134; 70..110, 89; 50..85, 67); 4 reserved |

Group 138's flashed defaults become `00 28 17 B8 32 9E 64 14`: a 4.0 s window and a 10.0 °TPS opening, so the defaults
give a load and then stabs. The flashed switches of 138 and 140 stay off.

## The stabs

- `stab_start` (from pops' gate, as a window starts) clears `POPS_T`, `POPS_PH` and `POPS_STAB`: the load begins.
- `stab_tick` (from `pops_tick` every 10 ms while the window runs and every condition holds) counts `POPS_T`. Until
  it passes 10 × the load time, and always with a stab size of 0, there is no stab. After that, each time `POPS_PH`
  runs out the phase changes: a stab lasts the stab length, a gap the gap.
- `pops_throttle` (the hook at `0x1B138`) adds the opening during the whole window, as V8.5 and V9 do, and during a
  stab the stab size on top, saturating, unless the torque guard is acting. With a stab size of 0 every store is V9's.
- The defaults give a 2.0 s load at 10.0 °TPS, then a +15.0 °TPS stab of 0.15 s every 0.40 s: five stabs in the
  4.0 s window.
- Below 4.0 °TPS the ECU closes the throttle slowly (0.2 °TPS per 10 ms under 7 °TPS), so the gaps blur; the app's
  hover for the opening says so.

## The brake and the lift

- Either brake switch (`FD2E.3`, `FD2E.4`) is a stop condition of the window (`pops_conditions`): pressing the brake
  ends it at once, and the stock fuel cut follows.
- A brake press in the overrun, or a blip, uses up the lift's pops (`FDF8.4`, V8's "lift used" bit): no window starts
  again until the pedal is pressed with the clutch up. `pops_tick` re-arms only with the clutch released, so a tap
  during a clutch-in does not re-arm it. After a braking downshift the pops never come back as the car turns in.

## The torque guard

`guard_tick` runs every 10 ms right after `pops_tick`. While a pops window or a blip runs, it sets `GUARD` when the
monitoring's torque estimate `8013` is more than 10 above the permitted torque `86AD` (both bytes in 2 Nm), that is
with less than 20 Nm of margin to the monitoring's threshold `ip_tqi_dif_max_mon` = 40 Nm (`0D:2534`). While it is
set, a stab's extra and the blip's addition drop to 0. It only ever lowers an addition, and clears as soon as the
margin is back. At pops' floor angle (−23.6°) it never acts in the drives: there the estimate stays low.

## The blip

`blip_tick` runs every 10 ms after `guard_tick`.

- **The clutch.** With the clutch up (`FD2E.6` clear) a running blip ends and the press is over: `BLIP_CL`,
  `BLIP_USED`, `BLIP_ARMED` and `BLIP_TAPPING` clear. With it in, `BLIP_CL` counts up to 255.
- **The tap.** The pedal (`E0FF`) below the tap threshold arms the tap. A rise past it from there starts one
  (`BLIP_TAP` = 1 on the rise), and the pedal back below within the tap length completes it. Held longer, as at the
  end of an upshift, the pedal is the driver's for this press. A pedal already past the threshold when the clutch
  went in is never a tap.
- **The start**, with the pedal released, needs every one of: the switch on (pops' choices: off, always on, cruise
  armed, a CAN bit); coolant at 60 °C or more; the road speed at or above the minimum; the clutch in for at most
  2.0 s; no LC, NLS, RAL or pops window (`FDF8` bits 0..3); the gear just left (`81AE`) 2..5 with its downshift
  switched on (141 byte `5 − gear`); the target at least 192 rpm above the engine speed; and a sign: both brake
  switches (never into 1st), or a tap just completed. One blip per clutch press.
- **The target** is the road speed times the next gear down's ratio (142 byte `gear − 2`, 0.5 rpm per km/h) / 64, in
  `807F` units, capped at the maximum rpm (RF-C3). It is recomputed every tick, so it falls as the car slows. For
  example 4th at 60 km/h gives `60 × 89 / 64 = 83`, about 2,656 rpm.
- **Rise and hold.** The addition is the blip opening (re-read each tick, so a live edit applies at once) until the
  engine is within 192 rpm of the target. The hold then starts from the hold opening: none while the engine is more
  than 160 rpm above the target, the hold opening while it is below it, unchanged in between.
- **The stops**, each within 10 ms: the clutch up, the pedal past the tap threshold, the maximum time, the road speed
  under the minimum, the engine at the maximum rpm, the switch off, LC, NLS or RAL engaged. Releasing the brake does
  not end a blip. At the end the addition is 0 and the stock setpoint, fuel and spark apply.
- **Throttle.** `pops_throttle` adds `BLIP_ADD` to the stock setpoint while `BLIP_ON` is set (saturating), unless the
  guard acts.
- **Fuel.** Pops' gate (`0x2A7BC`) takes the stock fuelled exit while a blip runs, so the overrun cut does not start.
  A blip that starts inside a cut that is already running needed one more hook (a ruling against the plan's "no new
  site", from the drive test): the in-cut handler `0A:A9EE` refuels only below the re-entry rpm. At `0x2AAA0`,
  `BCMP FD9Ah.11, FD48h.2` becomes `JMPS 0Ch, blip_reentry`: while `BLIP_ON` is set it jumps to the stock re-entry
  at `0A:AABA`; otherwise it runs the displaced instruction and returns to `0A:AAA4` with every register and flag as
  stock. The injections resume within 50 ms of the blip.
- **Spark.** Pops' spark hook (`0x2D424`) fires at the blip's fixed angle while a blip runs and `FD2C.11` is set,
  the flag pops' own fixed angle also requires: `E2B5` = the angle byte, `E2B4` = 0, then the stock spark call. No
  new ignition path.
- **Misfire** (RF-C4): while a blip runs, misfire detection stays suppressed (`E3B0` = 100, `FD2A.12`), as pops,
  LC and NLS do, so the cut-to-fuel switch with the clutch in counts no misfire.

## Verification (2026-11-05, in the emulator)

- **Direct CPU tests:** `OverlayV10Tests` (header, pool A, the defaults, every limit and one step past it on Write and
  Patch, the hold rule, reserved bytes, the clamp, the CAN switch, `v10_setting` keeps every other register),
  `PopsStabTests`, `PopsBrakeTests`, `TorqueGuardTests`, `BlipTests` (the signs, the tap, every start condition and
  every stop, the hold band, the target, misfire) and `BlipHookTests` (the throttle, the gate, the spark and the
  re-entry hook, each stock with the blip off). V9's gate, hook, trigger and watch tests also run on V10.
- **Whole drives** (`sim/drives/v10`, `V10DriveTests`; settings flashed, no RAM or device pokes):
  - **Stabs** (`pops-stabs`): one window with five stabs. The first comes 2.0 s in (± 20 ms), each lasts 0.15 s and
    each gap 0.25 s (± 10 ms). Every store adds +13,655 units (25.0 °TPS) during a stab and +5,462 (10.0 °TPS)
    otherwise, ± 4. With a stab size of 0 the stores are V9's, with no stab.
  - **The brake** (`pops-stabs-brake`): the window ends within 0.1 s of the brake, and none starts again.
  - **A braking downshift** (`blip-braking`, 4th at 60 km/h): the blip starts 0.0..0.1 s after the clutch and the
    brake, as the three switches pass their 4-pass debounce (66 ms measured), and ends within 0.1 s of the clutch
    coming up. The rise adds +8,193 (15.0 °TPS). Every main spark meanwhile fires at 10.125° ± 0.375°, no injection gap
    exceeds 0.2 s, and the addition is 0 after the end. With the blip off, nothing happens.
  - **A tap** (`blip-tap`, 5th at 90 km/h): the blip starts as the pedal comes back to 0.
  - **No blip** on an upshift with the foot back on before the clutch comes up (`blip-upshift`), or braking to a
    stop in 2nd (`blip-stop-in-2nd`, also with 2nd → 1st on).
  - **From a running cut** (`blip-from-cut`): the first injection comes within 50 ms of the blip, through the
    re-entry hook.
  - **The guard** never acts on `pops-stabs` at pops' floor angle (−23.6°).
  - **Tip-in fuel.** The stock code answers every stab: within 120 ms of its start comes a short intermediate
    injection (under 2 ms, about 1.1 ms), which never comes without stabs, and from 40 to 200 ms the main pulses are
    more than 1.1 × the last ones before it. The routine at `09:7D16` (the firmware reading's "wall film", outputs
    `8620`/`8622` and `85BE`/`85C0`) runs about twice a second and does not move during a stab; where the
    intermediate injection is triggered was not traced.
  - **Faults and checks**, on every V10 drive: the stored faults are the same drive's with V10's features off
    (`tam_can`, `tout_asr_3` and `t_es` come from the drives' surroundings and show on every run, V9's too); no
    throttle, brake-switch or torque-check fault (paths 111, 112, 113, 117, 118, 149); the verdict and every check
    pass.
- **Against V9, the new settings off** (`ms43sim compare`, `build/compare-v9-v10`; V9 `04210a45…`, V10 `708f767f…`):
  warm-start, cold-start, idle, key-cycle, overrun and part-load pass. Full-load fails the injector check on both bins
  (V9 100 %, V10 99 % of the engine cycle at 7,100 rpm, limit 98 %): the drift V9's record describes, from the tune's
  flame band at the limiter. No drive has a fault or power-cycle difference. The EEPROM differs on key-cycle and
  warm-start only in words that V8 to V9 already moved (`272h..3E0h`, the adaptations).
- **The emulator suite**, run in chunks: 1,883 tests, all passing except the two known failures of the first
  overlay (V1) on the quick key cycle (`OverlayDriveSetTests` and `OverlayAcceptanceTests`: P0339).
- **CPU cost** (`V10CostTests`, `sim/drives/v10/cost-full-load.drive`: a 20 s full-load hold in 3rd at 100 km/h with
  the logger polling sub 11 and a watch set; cycles at 24 MHz). With the new switches off a housekeeping pass takes 923
  cycles on V9 and 1,162 on V10 (+239, 0.1 % of the 10 ms period), and a throttle store 39.0 and 47.5 cycles. A pass
  takes 2,456 cycles during a stab window (1.0 % of the period) and 2,916 during a blip (1.2 %), against 548 outside a
  window on the same drive. On that full-load drive V9 and V10 alike overflow task queues 2 and 3 (`FD84 & 01C0h` =
  `0180h`) and store P1567 (`msw_tog`), V9's open question for the car: V10 adds no overflow and no fault.

## What the emulator cannot judge

The sound and the flames; the real throttle motor's answer to a 150 ms stab (the emulator's throttle body follows at
400 °/s); the free rev's real torque and the clutch's feel; combustion, exhaust temperature and knock at the blip's
+10.1°; the physical K-line and the real ECU's timing (P1567 and the queues above are V9's open questions too). Engine
safety and the stabs' and blip's settings remain to be shown on the car.

## V10.1 (2026-11-05, after the first car test)

The first car test of V10 (log `ms43-20261105-171338.csv`, 30 min) found the blips working but slow from low rpm and
overshooting by 350 to 700 rpm, and the pops "not working AT ALL" (owner): the window held the speed and the rpm with a
loud noise, a stab pushed the car, and V8's 160 rpm rise rule ended each window after one or two stabs, since on the
car a stab adds about 200 rpm. The owner's decisions: "put it by default plz" (the pops settings below), "do it by
default" (a 20.0 °TPS blip), "lets do it" (the blip's predictive end, and the faults in the log), "it needs way more
fuel i believe, and less pedal openning". The plan is the source contract.

- **Identification.** V10's sources are edited in place. The header's version word is `010Ah`: the low byte stays 10,
  so every V10 rule and the magic `C0DA` hold, and the high byte is the minor (V8.5's way); the status reply still
  says 10. The build writes `build/CAR_43X001_SP95_STAGE1_LIVE_OVERLAY_V10_1.bin` (SHA-256 `765bac9d…a8ff`), program
  identity `dccf68a2…b055` (`ProgramIdentity.Ms43X001LiveOverlayV101`, known whatever its flashed settings). The sent
  V10 (`708f767f…`) keeps its own name. V10's code now runs from `0C:F758` to `0C:FCB2`.
- **Defaults** (the switches still off):

  | Group | Bytes | Meaning |
  |---|---|---|
  | 138 pops | `00 28 00 D2 7D 9E 1E 14` | 4.0 s, −23.625°, AFR 9.99, 4,000 rpm, 70.5 °C, 3.0 °TPS, 20 km/h |
  | 139 stabs | `14 19 0F 19 0F 00 00 00` | a 2.0 s load, +5.0 °TPS stabs of 150 ms every 400 ms, a 480 rpm rise once stabbing |
  | 140 blip | `00 03 1E BB 0F 64 19 5A` | as V10, with a 20.0 °TPS blip opening |
  | 141 gears and tap | `01 01 01 00 15 28 0F 00` | as V10, with a 150 ms lead |
  | 142 ratios | `E2 86 59 43 00 00 00 00` | as V10 |

- **The AFR target** (138 byte 3) takes 128..255, down to AFR 7.4 (λ 0.504); V10 stopped at 210 (AFR 9.99). The value
  goes through the same shared rich path (`0x3D456`), a byte throughout: the blend, then the richer of it and the stock
  target.
- **The rise once stabbing** (139 byte 4, "Rise allowed during stabs", 32 rpm units, 5..31, 160..992 rpm).
  `rise_allowance` replaces V8's `+ 5` in both rise checks, `pops_tick`'s every 10 ms and the overrun-cut gate's
  (`pops_gate`, at every request of the stock cut; the V10.1 review found it still at 160 rpm, which would have ended
  every stabbing window as on V10): during the load a window still ends when the rpm rises 160 rpm above its lowest;
  once the stabs have begun (`POPS_T` past 10 × the load time, with a stab size above 0) it ends at this byte's rise.
  A V10 bin's 0 reads as 5, V10's rule. No `FDF8` bit is used for the phase: `FDF8.14` and `FDF8.15` belong to the car
  file.
- **The blip lead** (141 byte 6, "Blip lead", 10 ms units, 0..30). While the blip rises, `blip_lead` keeps `BLIP_PREV`
  (`9FA6h`, `807F` one tick ago) and `BLIP_RATE` (`9FA7h`, the rise a tick × 16, filtered: `rate − rate/4 + 4 × rise`,
  a fall counting as none, at most 255), and returns `rate × lead / 16` in `807F` units. The rise ends when the rpm plus
  192 rpm plus that reaches the target. At one unit (32 rpm) a tick the rate settles at 16 within 8 ticks, so a 150 ms
  lead ends the rise 480 rpm earlier. The lead only ever ends the rise sooner; 0 is V10's rule. The hold is V10's.
- **V10's review minors, fixed:** `blip_reentry`'s blip path runs the stock `BCMP FD9Ah.11, FD48h.2` and
  `BMOV FD9Ah.11, PSW.2` (the same bytes as `0x2AAA0..0x2AAA7`) before `JMPS 0Ah, 0AABAh`, so `FD9A.11` and the flags
  are a stock pass's; `bt_go` sets `BLIP_ON` after `BLIP_LEFT`, `BLIP_ADD`, `BLIP_HOLD` and the rate; a running blip
  stops if `81AE` leaves 2..5, which would index past group 142.
- **The app.** The header's minor picks the catalogue and the rules (`OverlayV10.MapsFor(minor)`,
  `ValidateCopy(…, minor)`): on a V10.1 ECU or bin, "Pops stabs" shows "Rise allowed during stabs" and "Downshift blip:
  gears and tap" shows "Blip lead", and the pops AFR target goes down to 7.4. A V10 ECU keeps V10's fields and limits,
  and a V10.1 value is refused there before anything is sent.
- **The log.** Every CSV row carries 13 more columns after the channels.
  - Five come from the stock payload itself, on every row and at no cost, under the ADX's names: `PUSTATE` (overrun),
    `PUCSTATE` (its fuel cut), `BTSSTATE` (the brake light test switch), `BLSSTATE` (the brake light switch) and
    `CSSTATE` (the clutch switch).
  - `faults` (the stored P-codes, oldest first, or `none`) and `queues` (the overflowed task queues, or `none`) are read
    when logging starts and every 20 s; on a V10 ECU, `fdf8` (hex) with `pops_window`, `pops_stab`, `pops_used`, `blip`
    (0 off, 1 rising, 2 holding) and `guard`, every 0.5 s. `pops_stab` is `FDF8.7` at the moment of each read, so it
    catches about one stab in five.
  - At most one DS2 06 exchange goes out between two polls, never retried: the fault round is spread over polls (the
    queue flags, the layout check once a session, the count, the list, a record each). Nothing more goes out while no
    CSV is open or a Performance run waits or records, so its samples keep the poll's own timing. On another fault
    layout both `faults` and `queues` say `unsupported`.
  - A failed read keeps the last value and the poll goes on; three state reads in a row with no answer wait 20 s, and
    the state cells stay empty once the last good read is a second old. While the overlay is quiet, nothing but these
    stock reads reaches it. Columns not read stay empty, so every row is as wide as the header.
  - In the emulator at 125,000 baud the log keeps 14.85 rows a second against sub 11's 16.67 alone on the same drive,
    with no gap between rows over 120 ms (the first V10.1 build read FD2C and FD2E as well, two reads a half-second and
    the fault memory in one go: 12.89 a second, with a 380 ms hole every 20 s).

### V10.1's verification (2026-11-05, in the emulator)

- **Direct CPU tests:** `OverlayV10Tests` (the header word, V10.1's defaults, the new limits and their clamps, the AFR
  to 255, V10.1 known beside the sent V10), `PopsStabTests` (the rise once stabbing at the tick and at the real gate,
  160 rpm during the load and with no stab size), `BlipTests` (the lead against 0 and 5, the filtered rate with every
  register kept, a gear outside 2..5, `BLIP_ON` seen only with its values in place, 20 °TPS) and `BlipHookTests` (the
  blip's re-entry path leaves `FD9A`, every register and the PSW as a stock pass does). V10's earlier tests run V10.1's
  code with V10's settings pinned (`V10Fixture.Classic`) and keep their numbers.
- **Drives** (`V10DriveTests`): V10's drives as before; V10.1's own pops (`pops-v101`: 3rd at 120 km/h, one 4.0 s
  window, five 5.0 °TPS stabs on 3.0, the spark decided at −23.625°); a slope (`pops-downhill-v101`: about 270 rpm of
  rise once stabbing keeps a 4.0 s window, and ends it with 139/4 = 5); a braking blip at 20.0 °TPS; no new fault on
  any of them.
- **Against the sent V10, the switches off** (`build/compare-v10-v101`): no behaviour difference on any of the seven
  drives; full-load fails the injector check on both bins, as V9 to V10.
- **CPU cost** (`V10CostTests`): a housekeeping pass takes 3,218 cycles in a stab window (V10: 2,456) and 3,039 during a
  blip; a gate pass inside a window 2,352 cycles, about 100 a second, 0.98 % of the CPU; at full load with the switches
  off V10.1 is V10 (1,162 cycles a pass) and overflows the same queues as V9.
- **The app against the firmware** (`app/tools/OverlayV10Integration`, the production client at 125,000 baud): stabs,
  blip, fallback, rate and queues as on V10, at V10.1's settings; `log` puts the app's diagnostic columns through the
  stabs lift (the window and the stabs show in `pops_window` and `pops_stab`, the faults column is the emulator's list);
  `log-plain` and `log-plain-off` show that this lift with sub 11 logging overflows queues 2 and 3 (`FD84` = `0185h`)
  with or without the columns and with pops off: V9's open question, not V10.1's.
- **Suites:** the emulator 1,932 of 1,934 before the gate fix (the two V1 quick-key-cycle failures, as always), and
  after it every chunk that runs the V10 image (overlay 349, pops 318, watch 136, v10 166); the app Core 737/737 and
  UI 764/764, in chunks.
