# MS43X001 live overlay protocol 6

V6 extends [V5](live-overlay-v5.md) with three optional 8-byte scalar groups.
All V5 RAM addresses, allocation rules, CRCs, session/revision handling,
snapshot epochs, patch pacing and hardcut behavior are retained.

## Identification and catalogue

The header remains 16 bytes at CPU `0C:B544` (file `04B544`). Version is 6,
catalogue count is 127, and the previously reserved last word contains `C0D6`.
The runtime initialization magic is also `C0D6`.

Catalogue entries 0..123 retain the V4/V5 tables, sizes and flags. New entries:

| ID | Meaning | Flash address | Bytes | Flags |
| ---: | --- | --- | ---: | ---: |
| 124 | Launch control | 07132C | 8 | 2 |
| 125 | No-lift shift | 071334 | 8 | 2 |
| 126 | Rolling anti-lag | 07133C | 8 | 2 |

Flags 2 identifies a scalar group, not a bilinear table. RAL owns only its first
7 bytes; its last byte at `071343` is the overboost setting `c_ob_thr_e85`.
The 16-byte allocation index already covers all 127 IDs. No RAM region is added.

## Mutation validation

For these IDs, inactive Write must supply all 8 bytes starting at offset zero.
The ordinary active Patch is already exactly 8 bytes and is therefore one whole
group. Both paths reject configuration bytes above 2 for LC/NLS or above 1 for
RAL. RAL's last byte must equal the current flashed byte at `071343`.
On and AllOn repeat content validation in addition to CRC verification, so a
matching CRC cannot authorize an invalid mode or altered neighbor.

The original allocation, packet CRC, whole-copy CRC, revision, idempotent retry,
protected four-word commit and readback checks remain in effect. A validation
failure returns range reason 4 without changing the allocation or its revision.

## Executable hooks

The pinned donor SHA-256 is
`8cfe31241aa90717195077f1d931ec3bd28e0e76b435a89472dc1fbdfe6c0717`.
`tools/live_overlay_v6_features.py` records exact original instructions, their
file offsets and scalar ownership. The builder refuses any differing donor read.
It also retains the full-image donor pin and explicit write ranges.

There are 26 verified scalar reads, covered by 20 hook blocks: 14 individual
4-byte MOVB/MOVBZ/CMPB instructions and 6 adjacent MOVBZ pairs of 8 bytes. A pair
is replaced by CALLS plus two NOPs. Its hook resolves the copy once and reads
both adjacent bytes within one EXTP range, deferring interrupts and PEC between
the loads. Odd-address pairs use byte loads, not unaligned word reads.

`feature_address` uses the normal allocation state, running/silence gates and
presence index. It returns a pointer/page into the allocated RAM group, or the
corresponding flash span. Original downstream interpolation and control logic
are retained.

The stubs preserve R2..R5 on the firmware's R0 stack and save/restore PSW on the
system stack. PUSH and POP change arithmetic flags: the final register restore
is enclosed by PUSH/POP PSW after replaying the original operation. MOVB retains
the destination high byte and incoming C/V; MOVBZ retains C/V and zero-extends;
CMPB retains its operands and original comparison flags. The implementation
does not change DPP registers or interrupt enable state.

When an effective configuration byte is zero, its hook clears only FDF8 bit
0 (LC), 1 (NLS), or 2 (RAL), before the original zero-return branch. This matches
the complete normal release path. It does not clear the cached RPM at `80BE`,
shared activity timer `E3B0`, or `FD2A.12`. The original active path writes decimal
100 to E3B0 (`E6 F6 64 00`), not hexadecimal 100.

NLS/RAL RPM offsets are captured at engagement, including the original saturation
to the raw RPM byte range. LC's RPM value still goes through the stock refresh
and hysteresis path. Original feature activation priorities are retained.

## Build and validation

Build with `python tools/build_live_overlay_v6.py`. It emits a separate V6 BIN,
compiled HEX fixture, catalogue, read manifest and symbol file. Retained V5
source and binaries are not overwritten. Code occupies `0C:B554..D63F` and the
catalogue/CRC tables end at `0C:E2B8`, inside the original overlay code area.

Focused simulator tests compare all new hook blocks with the actual original
instructions across both RAM pools, directory kinds, fallback conditions,
boundary values and incoming C/V flags. They check complete register/PSW/DPP/CP/SP
equivalence, pair interrupt exclusion, feature entry/release/caching, and compiled
protocol mutation validation. Real-client integration and image verification
results are retained in the logger's `artifacts/live-overlay-v6/` delivery folder.

The direct tests model CPU and memory behavior; they do not model combustion.
The reviewed read sites and bounded static scan are not an exhaustive proof
against all possible indirect accesses. Simulator timing and output observations
do not establish physical ECU operation or engine safety.

The verified program identity is registered in `ProgramIdentity.cs` so checks
that read stock MS43X001 RAM execute for this exact build. The new overlay does
not relocate the stock RAM those checks monitor. The high-RPM integration still
inherits the simulator's documented limitation: periodic-task deadline/overload
checks R2/R4 are not judged above 2,000 RPM because the minimum instruction timing
model also stretches the donor's tasks there. Crank-task, trap, reset and physical
output observers remain enabled. A Pass verdict is bounded by that coverage.
