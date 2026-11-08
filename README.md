# MS43X001_CUSTOM

A custom build of **MS43X001**, the [MS4X project](https://github.com/ms4x-net/MS43X-Custom-Firmware)'s
custom firmware for the Siemens MS43: MS43X001 plus the **live-tuning overlay**, which lets
[MS43 Tuner](https://github.com/raph559/MS43_TUNER) change maps and settings in the ECU's RAM over
the K-line, and adds pops & bangs on lift-off and an automatic downshift blip.

> [!WARNING]
> Experimental firmware. It has been tested in [MS43_EMULATOR](https://github.com/raph559/MS43_EMULATOR),
> which runs the real MS43X001 code, and in one car (E46 M54B25). Keep your original bin, flash a
> build only if you can flash back, and use the Fun features only on a closed road or a track.

## Build it

[`overlay/`](overlay/) holds the current version (V10.2) and `build_overlay.py`, which adds the
overlay's code to **your own** MS43X001 bin and leaves every calibration value as it is. See
[overlay/README.md](overlay/README.md).

## What else is here

This repository keeps the overlay's full development history, taken from the author's lab:

| Path | What |
| --- | --- |
| `overlay/` | The current overlay and its code-only build, for any MS43X001 (B25) bin |
| `patches/` | Every overlay version's assembly, V1 to V10.2, as it was developed |
| `tools/` | The lab's generators and builders for each version (`build_live_overlay*.py`) |
| `docs/`, `LIVE_OVERLAY.md`, `OVERLAY_BUILD.md` | Each version's design, protocol and test records |

The lab builders in `tools/` read the author's own bins (`bins/…`), which are not published; use
`overlay/build_overlay.py` instead. `patches/overlay.asm`, the first patch, is a known-bad record:
never build or flash it.

No bin and no part of Siemens's 430069 software is included.

## License

GPL-3.0 ([LICENSE](LICENSE)), as a modification of MS43X001 (MS4X project, GPL-3.0).
