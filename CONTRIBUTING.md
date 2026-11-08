# Contributing

Thanks for helping. Reports from other cars, and help supporting more MS43X001 variants, are the most welcome.

## Reporting from a car

Open an issue with:

- the car, engine and gearbox, and the fuel;
- the MS43X001 release you started from, the SHA-256 of your bin before and after the build, and the program
  identity `build_overlay.py` printed;
- the MS43 Tuner version, what you did in the app, and what the car did;
- a CSV log from the Live tab if you have one.

**Never attach a bin or an XDF.** Bins carry someone's software and tune; the SHA-256 is enough.

## Supporting another MS43X001 variant

`build_overlay.py` refuses any program it does not know, because the overlay's hooks jump from fixed places in
MS43X001's code. Adding a variant means finding each hook site in that variant's program, checking that the code
there is the same, and adding its program identity to `SUPPORTED`. Open an issue first, with the variant's name
and program identity, so the work is not done twice.

## Changing the overlay

- The overlay is C167 assembly for AS, in [`overlay/src/`](overlay/src). Keep every write inside the free block
  and the hook sites in [`overlay/write_list.json`](overlay/write_list.json); the build refuses anything else.
- Test a change in [MS43_EMULATOR](https://github.com/raph559/MS43_EMULATOR) before any car: the standard drives
  and the overlay's drives must still pass.
- Never change calibration values in a code change. Tune values belong to each owner's bin.

By contributing you agree that your work is licensed under GPL-3.0-only, like MS43X001 and the rest of this
project. Only submit work you have the right to license that way.
