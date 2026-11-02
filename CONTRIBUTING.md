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

## Pull requests

Keep each pull request focused on one change, and describe what you checked in the emulator or on a car.
State which checks you ran and any vehicle testing still needed.

Use `type(scope): summary` for commit subjects and pull request titles, for example
`docs(overlay): clarify build requirements`. Choose the type that fits the change: `feat`, `fix`, `refactor`,
`perf`, `test`, `docs`, `build`, `ci`, `chore` or `revert`.

### Commit subjects and PR titles

The scope names the affected subsystem, such as `overlay`, `protocol`, `allocator`, `pops`, `blip` or `watch`.
Use `deps` for package updates and `actions` for workflow dependencies. Other scopes are fine when they describe
the change. Use lowercase letters and digits, with hyphens between words.

For example:

- `feat(overlay): add a map reader hook`
- `fix(protocol): reject a stale revision`
- `test(blip): cover cancellation during fuel cut`
- `docs(overlay): clarify build requirements`

The summary must be nonempty, on one line, without leading or trailing whitespace. Use `!` after the scope
only for a breaking change, such as `feat(protocol)!: require a new session format`.
The [PR title check](.github/workflows/pr-title.yml) validates the format when a PR opens, reopens, changes title
or receives commits. Match the final commit subject to the PR title when squashing.

### Commit bodies

Use a body when the subject leaves useful context out. Describe the problem, the resulting behavior and why
the change is needed. For protocol or firmware changes, name the affected version and the byte, address or
register contract when it helps explain the change.

State which checks ran for this change and their limits: missing fixtures, a partial suite, emulator checks
or remaining vehicle validation. Keep results tied to the source version they tested. Record later car results
in the current documentation or release notes.

An import or snapshot should say what it brings in. Preserve credits and validation limits, and leave copied
chat requests and private planning links out of the message. A small, focused change can have an empty body.

## License of contributions

By contributing you agree that your work is licensed under GPL-3.0-only, like MS43X001 and the rest of this
project. Only submit work you have the right to license that way.
