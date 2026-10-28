# Live overlay protocol 5

V5 replaces V4's fixed 5-record directory with 5 reserved records plus additional
records allocated from the existing map RAM. It retains the 124-map catalogue,
147 verified call sites, full u8 values, 8-byte active patches and separate
limiter group. See [V4](live-overlay-v4.md) for unchanged patch, limiter,
fallback and donor constraints.

The pinned donor is `CAR_current_43X001_SP95_STAGE1.bin`, SHA-256
`8cfe31241aa90717195077f1d931ec3bd28e0e76b435a89472dc1fbdfe6c0717`.
Build with `python tools/build_live_overlay_v5.py`. The builder checks the donor,
all redirected instructions, allowed write regions, boot block and 5 checksums.
It requires all catalogue table sizes to be divisible by 4. V4 files are retained.

## Memory

| Allocation | Physical addresses | Bytes |
| --- | --- | ---: |
| Map pool A | 041D00–041FBF | 704 |
| Private patch snapshot | 041FC0–041FD7 | 24 |
| Limiter | 041FD8–041FDF | 8 |
| Magic, last-seen tick, session | 00E6B0–00E6B7 | 8 |
| Base directory | 00E6B8–00E6DF | 40 |
| Map pool B, extra directory records and optional index | 00E6E0–00E7C3 | 228 |
| Revision | 00E7C4–00E7C7 | 4 |

Total allocated RAM remains 1,016 bytes. The map/extra-record budget is 932 bytes.
No new RAM region is claimed. Existing ownership evidence and the disabled
service-monitor gate requirement remain applicable; the donor gate words at
00BFFC/00BFFE are zero. Initialization magic is C0D5.

Logical offsets 0–703 refer to pool A; 704–931 refer to pool B. Map data must
start on a 4-byte boundary and remain wholly within one pool. Active patch
offsets are still even, with 8 bytes per group.

## Records and links

Each record is 8 bytes: state8, catalogue ID8, logical offset/4 u8, control/link8,
CRC32 little-endian. A free base record has zero state, ID, offset and CRC;
its control byte survives Free.

Base records 0 and 1 use their control bytes for the low/high bytes of a 16-bit
disable epoch. Base records 2 and 3 reserve theirs as zero. Base record 4 stores
the overflow-chain head. Each extra record's control byte points to the next one.

Links encode `(physical address - E6E0) / 4`; 0–51 are possible record starts,
FF is the end marker. Records are in increasing physical-address order, with at
least 8 bytes between consecutive starts. A link outside the pool, backward or
overlapping terminates the firmware lookup. The client rejects such a chain.
This bounds traversal even if a link is corrupted. It is not a general guarantee
against arbitrary RAM corruption.

The allocator checks requested data and tracking ranges against every existing
data/record range before writing. A new record is published with one predecessor
link-byte store after its map copy and fields are complete. Free unlinks an extra
record and returns its 8 bytes to the pool. Existing active map data is never
relocated. Reloading an inactive allocation retains its record.

The first 5 records have no charge against the 932-byte budget. Each extra record
costs 8 bytes from pool B. While any extra record exists, a 16-byte presence index
occupies E7B4–E7C3 (logical offsets 916–931). Bit `id % 8` of byte `id / 8` marks
an allocated map, regardless of whether it is on. The first extra allocation
initializes the complete index before publishing the chain head. Later Load/Free
operations set/clear one bit; removing the last extra record releases the index
implicitly because the head becomes FF. The host checks every index bit against
the parsed directory. Data/records cannot overlap this index.

A free base record may coexist with extra records after removal; records are not
automatically moved. Tracking therefore costs `8 * extra records + 16` while any
extra record exists, otherwise zero. It is not determined by loaded count alone.

## Wire changes from V4

DS2 framing, session/revision guards, refusal reasons and operations remain as
in V4 except for the following:

- Header and status version are 5. Header catalogue metadata remains unchanged.
- Load arguments are `catalogueID8 logicalOffset16BE descriptor8`. FF selects
  a free base record, or reuses this map's existing base record. An index 0–51
  specifies an extra record at E6E0 + index*4; an existing extra allocation must
  specify its own record. The complete framed request is 17 bytes.
- Status is still 68 framed bytes. Following A0 is a 64-byte payload: LTOV,
  version8, running flags8, 5 packed records, freeBytes16BE, session32BE,
  revision32BE, limiter8. Record offset/control bytes are copied as individual
  packed bytes; record CRCs are big-endian on the status wire. Extra records read
  directly from RAM retain little-endian CRCs.

If the head is FF, the status contains the complete directory. Otherwise the
client reads all 228 bytes of pool B through read-only DS2 command 06 and requests
status again. It accepts the snapshot only when both complete status frames
match, retrying the snapshot at most 3 times. It then validates record links,
states, IDs, map ranges, all overlaps and the reported free-byte total.

Ordinary mutations change revision; a new session changes the session token.
Automatic `all_off` increments the disable epoch once if it changed any map or
limiter enable state. This makes automatic fallback visible in the bracketed
snapshot even when the changed maps are all in overflow records. Limiter mode
changes are visible in the status's limiter payload. A timed-out command-06 chunk
gets up to 2 retries separated by 20 ms; refusals and malformed responses are not
retried by that reader. No mutation uses this read-only retry path.

## Runtime and verification

When overflow records exist, the runtime reader first checks the presence bit
and immediately uses flash for an unallocated map. Otherwise it compares the
5 base entries directly, then follows increasing overflow links without a helper
call per record. It checks the same table
address, state, running condition and freshness as V4 before substituting a RAM
pointer. The original interpolation routine is unchanged.

The initial helper-based search passed functional checks but the 29-map A/B
integration exceeded a periodic-task interval bound at idle (45.4 ms versus
45 ms). Direct traversal passed that check, but the larger high-RPM selection
produced injector-pulse duty findings while still using unchanged baseline
values. The presence index was added to avoid repeatedly scanning the full
directory for unallocated maps. Initial failed evidence is retained separately
in the logger's V5 artifacts; final results are in its delivery notes.

Compiled tests cover 12 real allocations with edit/free/reuse/A-B/revert,
tracking/data overlap refusals, fallback and the snapshot epoch, every catalogue
reader in base and extra records, prospective CRCs, patch isolation/readback and
protected stores. A synthetic directory fills all 31 physically possible record
positions to test traversal bounds and invalid links independently of usable
map-data capacity; it does not claim that 31 catalogue maps fit.

Production-client integration fills the original 5-map set and a selection of
smaller maps through the simulated UART, editing and reading back each,
reclaiming/reusing an extra record and exercising A/B/revert. The logger repository
contains the final evidence, app, manifest and usage guide.

Periodic-task deadline/overload checks remain excluded at or above 2,000 rpm in
the simulator because its timing model already stretches donor tasks. Applicable
output, watchdog and crank-task checks still run. Physical ECU RAM ownership in
all operating modes, cable timing and engine safety remain unvalidated. No ECU
was flashed.
