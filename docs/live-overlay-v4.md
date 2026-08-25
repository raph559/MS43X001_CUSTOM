# Live overlay protocol 4

V4 adds a selectable catalogue to the V3 live overlay and an eight-byte manual-transmission limiter group. It is specific to the pinned `CAR_current_43X001_SP95_STAGE1.bin` donor, SHA-256 `8cfe31241aa90717195077f1d931ec3bd28e0e76b435a89472dc1fbdfe6c0717`. It updates RAM, not flash, while the engine runs. This is a software-tested candidate; real ECU operation and engine calibration safety remain unvalidated.

Build with `python tools/build_live_overlay_v4.py`. Sources are `patches/live_overlay_v4.asm` and `patches/live_overlay_v4_limiter.inc`. The builder checks the donor hash, every redirected instruction, the allowed write regions, the boot block and all five checksums. It writes a separate V4 BIN, simulator fixture and symbol file; V3 is retained.

## Selectable maps

`defs/live_overlay_v4_catalog.json` contains 124 named u8 bilinear tables, with 147 verified call sites. `tools/live_overlay_v4_catalog.py` derives it from `calmaps_ms43x.csv`. Every listed site must directly load the expected table offset/page into R12/R13 and call the original reader at 0D:029A. Each generated stub checks that address again at runtime before substituting a RAM pointer. The original reader still performs interpolation.

This is a supported catalogue, not support for arbitrary XDF items. Indirect/shared pointer sites, other element formats/readers, curves, axes and unrelated scalars are excluded. Matching XDF definitions are needed for display and editing; the app cannot make an unsupported item live by adding it to an XDF. A table has an effect only when the firmware actually selects it in the current operating conditions.

IDs 0–4 retain the original five maps: main ignition (320 bytes), idle ignition (36), AFR target (192), intake VANOS (192), exhaust VANOS (192). They still fit together with their full u8 precision. Other IDs follow address order. No ±8 or richer-only restriction is introduced.

## RAM layout

| Allocation | Physical addresses | Bytes |
| --- | --- | ---: |
| Map pool A | 041D00–041FBF | 704 |
| Private patch snapshot | 041FC0–041FD7 | 24 |
| Limiter group | 041FD8–041FDF | 8 |
| Control, session, five-entry directory | 00E6B0–00E6DF | 48 |
| Map pool B | 00E6E0–00E7C3 | 228 |
| Revision | 00E7C4–00E7C7 | 4 |

The total remains 1,016 bytes, including 932 map bytes. The limiter space comes from shortening the private request snapshot from 32 to 24 bytes. V4 introduces no additional RAM region.

Map offsets are logical: 0–703 refer to pool A; 704–931 refer to pool B. A table must be even-sized, start at an even offset, and remain wholly within one pool. Each of five directory entries contains state8, catalogue ID8, logical offset16 and confirmed CRC32. RAM multibyte values are little-endian.

The five slots are a separate limit from free bytes. Off keeps the allocation; Free releases it. The app places new maps in the smallest available hole that fits. It shows used/free bytes, occupied slots, largest free block and per-map fit. It does not move active allocations or silently replace another map.

The RAM ownership evidence and disabled service-monitor requirement are inherited from V3; see `docs/live-overlay-v3.md`. The donor's gate words at 00BFFC/00BFFE remain zero. This is not a general allocation guarantee for other firmware or service modes.

## Active map patches

V4 takes the expected old CRC from the confirmed directory entry, guarded by the session and expected revision. It recomputes the actual whole-table CRC and requires a match. It then calculates the exact prospective CRC using the verified before CRC, eight replacement bytes and unchanged suffix, as in V3.

The complete 24-byte packet is copied out of the receive buffer before validation. After validation, four new words are loaded into registers and committed with `EXTP R14,#4` followed by four aligned stores. The changed words are read back, the new CRC is stored and the revision advances. A readback failure disables that map and advances the revision. Unexpected RAM faults outside those checked words remain outside this guarantee.

The table stays active through a successful patch. Eight cells are the atomic update unit; a whole map or rectangle is progressive. Unchanged cells in each window retain their prior values. A retry for the immediately previous revision requires a matching current full-table CRC and identical replacement bytes, then acknowledges without committing twice.

The cooperative foreground task cannot suspend another foreground table reader. The extended-address sequence defers standard interrupts, PEC and class A traps across its stores; class B traps and reset are outside this guarantee. Compiled map-store and limiter-store sequences are tested with pending interrupts and PEC, including both map RAM pools. The C166 instruction reference and the prior mechanism are documented in `docs/live-overlay-v3.md`.

## Wire contract

Framing remains DS2 `12 length payload xor`; wire integers are big-endian.

- `6D 00`: 68-byte framed status. After A0 comes a 64-byte payload: LTOV, version4, running flags8, five eight-byte directory entries, freeBytes16, session32, revision32, limiter8. Free entries have zero offset/CRC. Status is a keep-alive and does not advance revision.
- `6D 0A session32`: open a nonzero session. A new token resets revision, retaining confirmed maps. Reopening the same token is idempotent.
- `6D sub session32 expectedRevision32 args`: operations 1–8 remain Load, Write, On, Off, AllOn, AllOff, Free, Revert. IDs are catalogue IDs; Load takes a logical offset. A map is inactive while initially loading/writing/verifying. Inactive Write accepts at most 112 data bytes. On and AllOn verify whole-map CRCs.
- `6D 09`: followed by the 24-byte patch below, giving a 29-byte complete frame.

| Patch offset | Content |
| ---: | --- |
| 0 | Session32 |
| 4 | Expected revision32 |
| 8 | Catalogue ID8, or 255 for the limiter |
| 9 | Reserved8 = 0 |
| 10 | Even table offset16; zero for limiter |
| 12 | Eight replacement bytes |
| 20 | CRC32 of bytes 0–19 |

CRCs use CRC-32/ISO-HDLC. Successful mutations reply A0 revision32 (eight framed bytes). Refusals retain B0/B1 plus reason; Session=12, Revision=13, Integrity=9. Revision never wraps. Session tokens and CRCs protect against stale/corrupt traffic, not a hostile diagnostic client.

## Limiter group

Bytes 0–5 are the six entries of the manual gear limit table (neutral/gear 0, gears 1–5). Byte 6 is return hysteresis. All seven are RPM/32. Each gear threshold must exceed hysteresis. Byte 7 contains:

| Bit | Meaning | Writer |
| ---: | --- | --- |
| 0 | Requested ignition cut (1) or fuel cut (0) | Client |
| 5 | Confirmed live limiter copy | Firmware |
| 6 | Currently applied cut mode | Firmware |
| 7 | Live limiter enabled | Client / firmware fallback |

The client sends only bits 0 and 7. The firmware validates the packet/range/session/revision, preserves the currently applied mode, commits all eight bytes using one protected four-store sequence, verifies readback and advances revision. A failed readback clears confirmation/enabling. Retry compares the normalized requested data, ignoring firmware-owned flags.

The original manual gear reader and hysteresis load use RAM only when enabled, the engine is running and the overlay is fresh. The mode is latched only after the original threshold-refresh task and when all relevant cut flags are clear. Changing modes while a cut is latched waits for release. After disable/silence, the flashed mode is restored at that same safe transition. This is tested at the compiled hook level; combustion behavior is not modeled.

The original ETC fault branch still forces fuel cut. Launch-control/NLS branches and the separate hard fuel-cut table retain their original logic. The donor's soft manual limits are 7,008 rpm, hysteresis 64 rpm and mode ignition cut; the separate hard fuel-cut limits remain 7,104 rpm. Raising a live soft limit does not remove those other constraints. No donor limiter values were changed in the delivered BIN.

## Client recovery and fallback

The matching client sends the first active group immediately and waits at least 100 ms after each patch response or timeout before another patch, including retries. It leaves the serial request lock available during the wait. Firmware does not enforce pacing against arbitrary clients.

A patch whose reply is lost is retried identically once. For Load/Write/On/Off/AllOn/AllOff/Free/Revert, a missing or malformed reply first triggers a fresh status. If session/revision prove the command was not applied, the identical command can retry once. If revision advanced exactly once, its expected state/content must be verified before success is accepted. Other outcomes stop recovery. This prevents an uncertain successful mutation from being blindly repeated.

At sustained 6,500 rpm and 125,000 baud, the initial integration run exposed ASC0 receive overrun before a map activation reached the overlay handler. A bounded receive trace captured S0CON=84F7 and the stock error handler discarding the frame. Recovery was added to the production client and verified with both request-loss and reply-loss tests. This recovers a transport failure; it does not prove high-RPM scheduling on hardware.

Stall or 300 processed ticks of silence disables maps and limiter overrides. A key cycle clears RAM. The session reads back/adopts existing confirmed settings and restores previously sent intent after recovery when the engine runs. Revert clears that intent. Draft edits are not automatically sent. The app's Copy to Tune actions save confirmed values into the open calibration document; flashing remains separate.

## Validation

Run `dotnet test sim/tests/Ms43Sim.Tests --filter 'FullyQualifiedName~OverlayV4|FullyQualifiedName~OverlayV3'`. V4 coverage includes every catalogue site's reader equivalence, all even eight-byte CRC windows with arbitrary bytes, all-five-map operation, allocation boundaries, corrupt/stale requests, private snapshot isolation, failed readback, all six gear lookups/hysteresis, mode gating/fallback, and interrupt/PEC deferral for compiled stores. The logger repository holds core/UI tests, production-client integration, rendered screens and the delivery manifest.

The simulator excludes periodic-task deadlines and scheduler overload flags at or above 2,000 rpm because the donor already exceeds those checks in its timing model. Watchdog, crank-task and applicable output checks remain active. A Pass is limited to those checks. Actual RAM ownership in every physical ECU mode, cable timing, all desktop scheduling interleavings and engine safety remain unvalidated. No ECU was flashed.

