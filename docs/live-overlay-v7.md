# MS43X001 live overlay protocol 7

V7 adds 11 unsigned 16-bit curves and tables to V6. The existing 124 byte tables,
three feature groups and separately reserved hardcut settings retain their IDs
and behavior. This is support for choosing live data, not a new calibration.
Axis data remains in flash.

## Added tables

| ID | XDF name | Data address | Cells | Bytes |
| ---: | --- | --- | ---: | ---: |
| 127 | `ip_n_sp_is__tco` | `07B674` | 6 | 12 |
| 128 | `ip_isapwm__tco` | `07A2E0` | 6 | 12 |
| 129 | `ip_acin_n_sp_is__tco` | `07955E` | 6 | 12 |
| 130 | `ip_n_vim_tia__tia` | `07B680` | 8 | 16 |
| 131 | `ip_t_puc_deacc_1__n__maf_mmv` | `07C400` | 24 | 48 |
| 132 | `ip_t_puc_deacc_2__n__maf_mmv` | `07C430` | 24 | 48 |
| 133 | `ip_t_puc_deacc_3__n__maf_mmv` | `07C460` | 24 | 48 |
| 134 | `ip_t_puc_deacc_4__n__maf_mmv` | `07C490` | 24 | 48 |
| 135 | `ip_t_puc_deacc_5__n__maf_mmv` | `07C4C0` | 24 | 48 |
| 136 | `ip_tps_sp_pvs__pvs__n` | `07E4DC` | 144 | 288 |
| 137 | `ip_tps_sp_pvs_add_low_n__n_dif__` | `07E5FC` | 16 | 32 |

The idle entries are base RPM, base idle-valve PWM and A/C RPM. The DISA entry
is the temperature-dependent RPM correction, including its original XDF offset;
its companion scalar thresholds and hysteresis remain flashed. The pedal entries
are the main pedal/RPM throttle target and the low-RPM additive table. The
overrun entries are the five gear-dependent fuel-cut delay tables. This does not
add every idle correction, DISA scalar, torque model or throttle-monitoring map.
Stock limits, monitoring, blending and state transitions still apply.

## Identification and allocation

The 16-byte header remains at `0C:B544`: version 7, count 138, final word `C0D7`.
Runtime magic is `C0D7`. Catalogue flags 4 mean unsigned little-endian 16-bit
cells; flags 0 and 2 retain their byte-table and scalar-group meanings.
The app checks address, size, flags and the XDF cell encoding before editing.

The same 932-byte allocation budget is used. No speculative RAM range is added.
The first five records still occupy their separate 40-byte reservation. With
overflow records, the presence index expands from 16 to 20 bytes and occupies
`00E7B0..00E7C3`, logical offsets 912..931. Extra records remain eight bytes,
four-byte aligned, with start indices 0..50 in pool B. Their links must increase.
The index supports IDs 0..159; V7 only accepts IDs 0..137.

The original five tables still fill 932 bytes without any index allocation.
All 11 new tables together use 612 data bytes and 68 tracking bytes (six extra
records plus the index), leaving 252 bytes. Actual combinations also depend on
the two pools' free contiguous blocks and allocation order. The app shows the
complete cost and rejects overlaps with either map data or the index.

## Reader hooks

`tools/live_overlay_v7_maps.py` pins the donor's call instructions, data pointers,
descriptor layout and recovered consumers. The four curves use stock reader
`0D:022A`; the main throttle table uses `0D:0168`. Their adapters preserve scratch
registers and flags while choosing the original or live data pointer.

The overrun and additive-throttle readers use descriptors. Their adapters execute
the same first six descriptor-unpacking instructions, substitute only the data
pointer and page, then jump back into the original helper at `0D:04B0` or
`0D:09BC`. Axes, interpolation, limits and the remaining instructions are unchanged.
Unexpected incoming pointers take the original path. Only 11 known call sites
are replaced; no shared interpolation-library entry is globally patched.

Each adapter checks initialization and its fixed bitmap bit before saving the
remaining scratch registers or searching the directory. An unselected map uses
the original reader immediately when the overflow index is present. This bounds
the extra work for frequent readers whose tables are not loaded.

The inherited feature validators are explicitly restricted to IDs 124..126 so
they cannot misinterpret a word table's first byte as an activation setting.
All existing V6 source includes and binaries remain separate.

## Updates and verification boundary

Active updates retain the session/revision protocol, packet/content CRCs,
idempotent retries and protected four-word commit. Each eight-byte patch contains
four complete 16-bit cells. Larger edits remain progressive groups with 100 ms
spacing; a whole 144-cell table is not switched atomically. The live map stays
selected during upload. A/B still selects flashed or edited data.

The stock firmware determines when each value is used. A curve can be refreshed
on its normal task cycle; a timer already calculated from an overrun table need
not be restarted when that table changes. Compatibility does not bypass these
firmware behaviors or establish that a particular calibration is safe.

The pinned build preserves the donor calibration except its checksum word,
boot block and validity tags. Validation uses compiled C167 reader comparisons,
compiled mutation handlers, the app editor and the production DS2 client against
the simulator. Delivery-specific hashes, results and remaining simulation gaps
are recorded with the matching app in the logger's `artifacts/live-overlay-v7/`.
No physical ECU or engine validation is implied.
