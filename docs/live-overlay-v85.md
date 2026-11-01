# MS43X001 live overlay 8.5: V8 with a wider pops throttle opening

V8.5 is [V8](live-overlay-v8.md) with one change: the pops throttle opening (group 138, byte 6) goes up to 20.0 °TPS
instead of 5.0. It has none of V9's watch hooks or triggers. The owner asked for it on 2026-10-30, after V8's pops gave
only crackle: a window at 5 °TPS gets about 15 air per rev at 3,500 to 5,000 rpm, the old map-based recipe that banged got
21 to 28, and each °TPS adds about 1.

## What changes

- **Limit.** `pops_limits` byte 6 is 0..200. The validators and `pops_setting` read it from there, so a value of 201 or more
  is refused with reason 4 on Write, Patch, On and AllOn, and a flashed one is clamped.
- **The add.** The 86A4 units are computed, 54.625 X by shifts (10925 at 200), since a 201-word table does not fit below the
  defaults. V8's X x 2731 / 50 and this differ by at most 2 units. No MD register is used, as in V8.
- **Identification.** The header's version word is `0508h`. The low byte stays 8, so every V8 rule applies, and the status
  reply still reports 8; the high byte is the minor. Exes older than this one refuse the overlay ("unsupported version").
- **Unchanged:** the magic `C0D8`, the catalogue, the flashed pops settings (switch 0: off), the +160 rpm stop, and every byte
  outside the overlay block except one checksum word at `6FDE0h`. The source diff is those lines.

The builder is `tools/build_live_overlay_v85.py`, and `tools/live_overlay_v85.py` generates `patches/live_overlay_v85.asm`
and `live_overlay_v85_pops.inc` from V8's by checked substitutions. Program identity `9765fe8b…4da9`.

## Checks (emulator; no ECU was flashed)

- `OverlayV85Tests`, `PopsGateTestsOnV85`, `PopsHookTestsOnV85`: V8's gate and hook behaviour, the limit, the clamp, the add.
- `PopsV9DriveTests` on V8.5: the lift drive with 20.0 °TPS flashed adds +20.0 °TPS in the window, every check passes,
  nothing is stored. The drive scripts the shaft's speed, so **whether the extra air makes the car pull on lift-off is not
  modelled**. The +160 rpm stop is the safety net there; start low on the road.
- The full-load drive where V9 stores P1567 (3rd, 100 km/h, logger polling): V8.5 passes and stores nothing.
