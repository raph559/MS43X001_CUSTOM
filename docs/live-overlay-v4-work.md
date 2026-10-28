# V4 implementation record

Requested: choose live maps in the app, show remaining capacity, retain all five original full-precision maps, and add the eight-byte limiter group. No ECU flashing is part of this work.

The catalogue is restricted to named u8 bilinear tables whose listed call sites in the pinned donor directly load the table's exact page and offset and call 0D:029A. Other tables, scalars and axes are not automatically supported by an XDF. Each enabled site receives a guarded stub. Existing map IDs 0-4 remain stable.

Planned RAM layout: five eight-byte allocation entries (state, map ID, logical offset, CRC32); 932 map bytes in the existing 704-byte external and 228-byte internal pools; 24-byte private update snapshot; eight-byte limiter data; existing session, timestamp and revision. Total remains 1,016 bytes. Five map allocations maximum, plus the separately reserved limiter group. Tables cannot span the two pools. Off retains an allocation; Free releases it.

Protocol 4 active patch: session32, revision32, map8, reserved8, offset16, replacement8, packet CRC32 (24 bytes). The expected old CRC comes from the confirmed directory entry, protected by the expected revision. The firmware checks actual contents against that CRC, computes the prospective CRC, commits four protected words, reads them back, then stores the new CRC and advances the revision. A retry requires the immediately preceding revision, confirmed whole-table CRC, and matching replacement bytes. Protocol 3 is retained unchanged.

Limiter payload: six manual-gear RPM bytes, ignition-cut hysteresis byte, mode/flags byte. One raw RPM step is 32 rpm. Requested mode and enabled state are distinct from the mode currently used by the limiter. A mode transition must wait until the limiter's cached thresholds have refreshed and its cut flags are clear. Launch control, NLS, ETC safety fallback and the separate hard fuel-cut table retain their original logic.

Required validation before delivery: original-reader equivalence for every catalogue entry, allocation bounds and overlaps, all-five-map operation, packet/session/revision failures, partial updates and retries, limiter mode transitions and fallback, client integration, regression tests, rendered app controls, checksum and artifact verification. Simulator evidence is not hardware acceptance.

Completed 2026-10-26. The final catalogue contains 124 tables and 147 verified call sites. The matching app provides selection/search, allocation/slot indicators, limiter controls and confirmed-only Copy to Tune. Final firmware SHA-256: b76a4a8fc4ca5b430fc90bdb29435c59df4067845853a79a1b2f17b00956dd4b. Program identity: f5541e1edf954aa24fa1934db230b161dde7ab9ae005003b9892bf72b28f0d57.

Firmware V3/V4 regression: 29 passed (14 V4 cases), including 1,176 original-reader comparisons and 3,890 full-CRC comparisons. Logger core: 469 passed. Desktop: 655 passed. Production-client integration completed at 9,600/125,000 baud idle and 125,000 baud at 6,500 rpm with telemetry. The UART investigation found stock ASC0 receive overrun before activation dispatch; the V4 client now reconciles session/revision/result before retrying an uncertain mutation. Final runs retain natural timeout counts and high-RPM scheduler coverage gaps. No physical ECU operation is claimed.

See docs/live-overlay-v4.md for the final protocol and the logger checkout's artifacts/live-overlay-v4/README.md for deliverables, hashes, timings, failures and final evidence. The V3 BIN and executable were retained and reverified. No ECU was flashed.
