# MS43X001 live overlay protocol 8: pops on lift-off

V8 adds one settings group to [V7](live-overlay-v7.md), group 138, "Pops & bangs". After a lift-off
in gear, the group holds off the overrun fuel cut for a set time. During that time the engine runs
rich, the spark is fixed and very late, and the throttle may open a little. Everything else keeps
V7's IDs, addresses, protocol rules and checks. The design is
the source contract, and the plan is
the source contract.

## Identification and the group

- The header at `0C:B544` carries version 8 and a count of 139. The runtime magic is `C0D8`.
- Catalogue entry 138 is `DW 0033h, 3F80h, 8, 2`: an 8-byte scalar group whose flashed defaults sit
  in the overlay's own flash at file `0x4FF80` (CPU `0C:FF80`, app address `0xCFF80`). That location
  is inside CRC range 4, which now ends at `0x0CFF87`.
- The builder is `tools/build_live_overlay_v8.py`. It generates `patches/live_overlay_v8.asm` and
  `patches/live_overlay_v8_feature_helpers.inc` from the V7 sources (`tools/live_overlay_v8_pops.py`)
  and assembles them with `patches/live_overlay_v8_pops.inc`.
- Unlike V7's builder, which wrote V7's symbols from V6's listing, it writes
  `defs/live_overlay_v8_symbols.json` from V8's own listing.

| Byte | Setting | Encoding | Limits | Default |
|---:|---|---|---|---|
| 0 | Switch | 0 off, 1 always on, 2 cruise control ready; 80h..9Fh one bit of byte 0 of the ASC (153h, `EF47`) or A/C (615h, `EF37`) frame: bit 4 the frame (1 = A/C), bit 3 the polarity (1 = on while the bit is 0), bits 0..2 the bit | 0..2, 80h..9Fh | 0 |
| 1 | Duration | 0.1 s | 1..50 | 20 (2.0 s) |
| 2 | Spark angle, fixed | 0.375·X − 23.625 °BTDC | 0..255 | 23 (−15.0°) |
| 3 | AFR target | the firmware's: λ = 1.5 − X/256 (128 = 14.7, 184 = 11.5) | 128..210 | 184 (11.5) |
| 4 | Minimum engine speed | 32·X rpm | 50..219 | 50 (1,600 rpm) |
| 5 | Minimum coolant | 0.75·X − 48 °C | 144..255 | 158 (70.5 °C) |
| 6 | Throttle opening | 0.1 °TPS | 0..50 | 0 |
| 7 | Minimum road speed | km/h (`847F`) | 0..255 | 20 |

The validators reject any byte outside its limits on Write, Patch, On and AllOn, with reason 4.
Every read through `pops_setting` also clamps the value into its limits; a switch value above 2
reads as 0.

## RAM

- `FDF8.3` means a window is running, and `FDF8.4` means this lift has had its window. No code in the
  car file or in V7 uses `FDF8` bits 3 to 13.
- The window's 10 ms countdown is the word at `041FBC`, and the lowest `807F` seen in the window is
  the byte at `041FBE`.
- These are the last four bytes of pool A. An allocation may no longer reach logical offset 700, and
  the status reports 928 bytes.
- **Cost:** the five original tables no longer fit together. Four of them, plus any smaller maps,
  still do. No RAM outside the pool is proven free; the census gaps would need a dynamic proof first.

## Hooks

| Site | Original | V8 |
|---|---|---|
| `0x2A7BC` overrun-cut gate | `JB FD2E.13` / `JB FD30.2` → cut at `0A:A7C8` | `JMPS pops_gate`. It stays fuelled (`0A:B0F2`) while a window holds, and every exit keeps all registers and PSW |
| `0x2D424` spark call | `CALLS 0Bh, 5C84h` | `CALLS pops_spark`: during a window `E2B5` is the set angle, then `JMPS 0Bh, 5C84h`. Knock retard does not act in overrun |
| `0x3D434` AFR branch | `JB FDF8.2, 3D44E` | `JMPS pops_afr`. RAL keeps priority. During a window R12 = R13 = the set AFR, through the shared path, which takes the richer target and switches the lambda loop off from 1,600 rpm |
| `0x1B138` throttle store | `MOV 86A4h, R4` | `CALLS pops_throttle`: during a window the opening is added to the pedal-map setpoint, saturating. The flags come out as the stock store leaves them |
| `0x3D3B2` pedal-released skip | `JNB FD44.3, 3D3BA` / `JMPA 3D476` | `JMPS pops_target`. During a window the target and full-load enrichment path runs even with the pedal released; otherwise it is stock |
| housekeeping (10 ms) | — | `pops_tick`. It counts the window down and ends it at time-up or on any failed condition or the RPM rise, whether or not the gate runs. While the window runs, it keeps misfire detection suppressed (`E3B0 = 100`, `FD2A.12`). When `FD2C.11` and `FD2C.12` are both clear, it clears both flags |

A window starts at the stock cut decision when every condition below holds:
- the switch is on;
- `807F`, `847F` and `8433` are at or above their minimums;
- the clutch (`FD2E.6`) is not pressed;
- LC, NLS and RAL are inactive.

The window ends within 10 ms (the tick), or at the next gate pass, in any of these cases:
- a condition fails;
- the time is up;
- `807F` reaches the lowest value seen plus 5, a rise of 160 rpm.

Pressing the pedal leaves overrun the stock way.

## Verification (2026-10-28, in the emulator)

- **Direct CPU tests:**
  - `OverlayV8Tests`, `PopsGateTests` and `PopsHookTests` cover the group's mutations and limits,
    the gate (every condition, stop and latch), the tick, and each hook against the donor's original
    instructions with pops inactive;
  - V6's feature-hook and V7's word-reader equivalence tests also run on V8.
- **Whole drives** (`sim/drives/pops`, `PopsDriveTests`; pops-on runs use the V8 image with other
  flashed settings):
  - a lift holds the fuel for 2.0 s after the stock cut, with every spark at −15° and the throttle
    setpoint +3.0°;
  - the pedal, the clutch, a falling engine speed, a falling road speed and a rising engine speed
    each end the window within 100 ms;
  - a cold engine never starts one;
  - each lift has one window;
  - the fault memory and the verdicts equal the pops-off runs.
- **Pops off against V7** (`ms43sim compare`, the seven standard drives, `build/compare-v7-v8`):
  - every drive passes;
  - there is no fault or power-cycle difference;
  - the EEPROM differs in the same words as V6 against V7 on the warm start (`0x272..0x3E1`, timing
    drift).

The emulator does not model combustion, exhaust temperature or sound. Its lambda sensors read as
absent, its engine follows the drive's speed, and the monitoring module's reaction is not modelled.
For those, the disassembly is the evidence: misfire is suppressed during the window, the lambda loop
is switched off by the stock path from 1,600 rpm, and the throttle addition goes in before the
setpoint checks. Physical ECU operation and engine safety remain to be shown on the car.
