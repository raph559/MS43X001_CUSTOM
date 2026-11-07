# Live-tuning overlay V10.4

The source is [`overlay/src`](../overlay/src) and the build is [`overlay/build_overlay.py`](../overlay/build_overlay.py).

## Identification

The overlay starts at `0C:B544` (file `0x4B544`) with the header `LTOV`, then the version word `040Ah`: the low byte
is the protocol (10), the high byte the minor (4). MS43 Tuner reads the header with the read-only DS2 command 06
before it sends anything, and works only with V10.4.

## What it does

- **Live maps.** 135 maps and curves can be copied into RAM. At each place the firmware reads one of them, a hook
  jumps to the overlay, which returns the live copy when it is switched on and the flashed one otherwise.
- **Settings groups.** Groups 138 to 142 are 8-byte settings blocks with flashed defaults at `0C:FF80`: 138 pops,
  139 reserved, 140 the downshift blip, 141 its gears and tap, 142 its gear ratios. Every byte has limits in the
  overlay; a write outside them is refused.
- **Protocol.** One DS2 command, `6D`, with sub-commands to open a session, load, write, switch on and off, revert
  and read the status. Every write carries the session and a revision, and a map is switched on only with the
  CRC-32 of its whole copy. When the app goes quiet for 3 s, the ECU goes back to the flashed values. Nothing in
  RAM survives a key-off.
- **Pops & bangs.** On lift-off in gear, the overrun fuel cut is held off for the set time with a fixed spark angle
  (−23.6 to +30.0 °BTDC), a set AFR (5.0 to 14.7, as a real mixture) and a little throttle. A brake press, the
  clutch, the pedal, or a 160 rpm rise ends the window.
- **Downshift blip.** With the clutch in and the brake on (or a short pedal tap), the throttle opens toward the lower
  gear's rpm. Above the target the spark is capped, and the stock angle comes back in steps afterwards so no coil
  loses its charge. A blip needs the engine at 800 rpm or more.
- **Triggers.** Pops, the blip, launch control, no-lift shift and rolling anti-lag can follow cruise control armed,
  ASC off or A/C on.
- **Map watch.** The ECU reports the cell it last read in the map the app shows, for the live cursor.

## Changes in V10.4

- The pops spark angle is limited to +30.0 °BTDC, as the blip's; V10.3 accepted up to +72.
- A blip never starts on a stalled engine (under 800 rpm).
- A pops window's time is in place before its flag, so the 10 ms task cannot end a window as it opens.

## How it was checked

Every version runs in [MS43 Emulator](https://github.com/raph559/MS43_EMULATOR), which executes the real MS43X001
code with an engine and a car around it: starts, idle, full load, overrun, pops windows, braking and tap blips, key
cycles and a silent app. The checks there cover the hooks' register and flag handling, every setting's limits, the
spark angles and coil charge times, and that no fault is stored.

V10.4 has also run in one E46 M54B25. Wider vehicle validation is still pending.
