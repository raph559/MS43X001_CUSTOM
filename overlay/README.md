# The live-tuning overlay (V10.4)

A small add-on to **MS43X001**, the MS4X project's custom firmware for the Siemens MS43. It lives in
MS43X001's free flash space and lets MS43 Tuner change maps and settings in the ECU's RAM over DS2 on
the K-line, with no reflash. Nothing you send survives a power cycle until you copy it into the bin
and flash it.

> [!WARNING]
> This is experimental firmware. V10.4 has run on scripted drives in MS43 Emulator, which executes the
> real MS43X001 code, and has also run in one E46 M54B25. Wider vehicle validation is still pending.
> Keep your original bin, flash the overlay bin only if you can flash back, and use the Fun features
> only on a closed road or a track.

## What it adds

- **Live maps:** the ECU reads chosen maps (ignition, AFR target, VANOS and more) from RAM, where the
  app writes them, and can switch between them and the flashed ones at once.
- **Live settings:** the rev limiter, and MS43X001's own launch control, no-lift shift and rolling
  anti-lag settings.
- **Pops & bangs** on lift-off, with a real AFR target and the throttle held at its set opening.
- **A downshift blip:** an automatic rev-match on braking downshifts, with a spark cap above the target
  engine speed.
- **Switch triggers:** pops and the blip can follow cruise control armed, ASC off or A/C on.
- **A map watch:** the app's live cursor can show which map the firmware read last.

Every feature is off until you turn it on in the app.

## What the build changes

[`build_overlay.py`](build_overlay.py) takes **your own MS43X001 bin** and writes a patched copy next to
it. It writes code only:

- the overlay itself, into MS43X001's erased flash block at `0x4B544`..`0x4FFE6`;
- a jump to it at each of the 216 hook sites in [`write_list.json`](write_list.json), each checked
  against MS43X001's original bytes first;
- the five checksums, fixed and verified.

Your calibration (`0x70000` onwards: maps, injector flow, limiter, every tune value) comes out byte for
byte as it went in, apart from its two checksum words; the build checks this and refuses otherwise. It
also refuses a bin whose program is not MS43X001's, a bin already patched, and any write outside the
block and the hook sites. The boot block and the validity tags are never written.

Supported program: MS43X001 (Oct 2025 release, M54B25). Other MS43X001 variants are refused until their
program is checked.

## Build

You need Python 3.10 or later, and AS, Alfred Arnold's Macro Assembler
([asl and p2hex](http://john.ccac.rwth-aachen.de:8000/as/)), for the C167.

```bash
python -I build_overlay.py YOUR.bin
```

- With `asl` on PATH it runs natively. Otherwise give its folder with `--asl-dir`; on Windows without a
  native AS, the build runs it in WSL (`--wsl`, default `Ubuntu-24.04`), and `--asl-dir` is a WSL path.
- `--out OUT.bin` names the result; the default is `YOUR-live-overlay-v10_4.bin`.
- The build prints the result's program identity (SHA-256 of the program code, excluding calibration).
  Use the identity from your current build when reporting a problem; an older overlay's digest does
  not identify V10.4.

Flash the result with MS4X Flasher, as any bin. Then open it in MS43 Tuner: the Live tuning and Fun tabs
find the overlay on the ECU and in the bin.

## The source

[`src/live_overlay.asm`](src/live_overlay.asm) is the only file the assembler is given. It holds the equates, the
header, the flashed settings and the order of the parts, and includes the section files next to it. It is C167
assembly for AS, written with physical addresses and the firmware's DPP assumptions. The order of the `INCLUDE`
lines fixes every address, so moving one changes the bin.

| File | What it holds |
|---|---|
| [`live_overlay_map_stubs.inc`](src/live_overlay_map_stubs.inc) | One stub per byte map, and the substitution of its live copy |
| [`live_overlay_housekeeping.inc`](src/live_overlay_housekeeping.inc) | The 10 ms task: the ticks of pops, the guard, the blip and the watch, and the switch-off |
| [`live_overlay_ds2.inc`](src/live_overlay_ds2.inc) | The DS2 `0x6D` handler and its commands (load, write, on, off, free, revert, status, patch) |
| [`live_overlay_tables.inc`](src/live_overlay_tables.inc) | The tables' state: the switch-off, the directory and its overflow records |
| [`live_overlay_patch_crc.inc`](src/live_overlay_patch_crc.inc) | The CRC a patch will give, from the CRC before it |
| [`live_overlay_limiter.inc`](src/live_overlay_limiter.inc) | The rev limiter per gear |
| [`live_overlay_feature_helpers.inc`](src/live_overlay_feature_helpers.inc) | The settings groups' addresses and validation |
| [`live_overlay_feature_stubs.inc`](src/live_overlay_feature_stubs.inc) | Launch control, no-lift shift and rolling anti-lag reads (generated) |
| [`live_overlay_word_stubs.inc`](src/live_overlay_word_stubs.inc) | The 16-bit maps' stubs (generated) |
| [`live_overlay_pops.inc`](src/live_overlay_pops.inc) | Pops on lift-off, the real AFR targets, and the spark and throttle hooks the blip shares |
| [`live_overlay_catalogue.inc`](src/live_overlay_catalogue.inc) | The catalogue: each table's flash page, offset, size and flags |
| [`live_overlay_crc_zero_powers.inc`](src/live_overlay_crc_zero_powers.inc) | CRC advance matrices (generated) |
| [`live_overlay_watch.inc`](src/live_overlay_watch.inc) | The watched map |
| [`live_overlay_triggers.inc`](src/live_overlay_triggers.inc) | Switch triggers for launch control, no-lift shift and anti-lag |
| [`live_overlay_blip_groups.inc`](src/live_overlay_blip_groups.inc) | Groups 139 to 142: limits, reads and validation |
| [`live_overlay_blip.inc`](src/live_overlay_blip.inc) | The torque guard and the downshift blip |
| [`live_overlay_feature_hooks.inc`](src/live_overlay_feature_hooks.inc) | The patched sites of the LC, NLS and RAL reads (generated) |
| [`live_overlay_hooks.inc`](src/live_overlay_hooks.inc) | Every other patched site in the firmware |

The files marked generated come from scripts in the author's lab; the rest is edited by hand.

## License

GPL-3.0, as a modification of MS43X001 (MS4X project,
[MS43X-Custom-Firmware](https://github.com/ms4x-net/MS43X-Custom-Firmware), GPL-3.0). MS43X001 is
built on Siemens's MS430069 software, which is not part of this repository. No bin is published. See [LICENSE](../LICENSE).
