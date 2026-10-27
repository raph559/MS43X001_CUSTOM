# Live overlay protocol 2

Protocol 2 uses a full-copy CRC-32 and a bounded raw-edit policy. It is a test candidate and has not been validated on an ECU. These bounds do not establish safe combustion or validate the flashed baseline.

The versioned output is `build/CAR_43X001_SP95_STAGE1_LIVE_OVERLAY_V2.bin`. The original v1 image is retained. Build with `python -I tools/build_live_overlay.py --car <original car bin>`; its donor SHA-256 is pinned in the builder. Tests use `sim/tests/Ms43Sim.Tests/fixtures/live_overlay_v2.hex`.

Requests are `12 LEN 6D sub args... xor`. Arguments are big-endian. Unchanged subcommands: 00 status (LEN5), 01 load i offset16 (LEN8), 02 write i at16 data (LEN9-128; 1-120 data bytes), 04 off i (LEN6), 05 all on (LEN5), 06 all off (LEN5), 07 free i (LEN6), 08 revert (LEN5).

**03 on** is now LEN10: `12 0A 6D 03 i CRC32_BE xor`. The CRC covers every byte of the complete RAM table, including unchanged cells. It is CRC-32/ISO-HDLC: reflected polynomial EDB88320, initial FFFFFFFF, final XOR FFFFFFFF; `123456789` gives CBF43926. Legacy LEN8 on requests are refused as B0 reason01. A host must detect version2 before uploading or activating.

Load starts a fresh copy from the flashed table and clears its stored CRC. Writes to active slots remain refused; an accepted write leaves the slot Loaded/unconfirmed. On recomputes the complete CRC, applies cell limits, and writes On state last. All on revalidates all Ready slots before activating any. A CRC is accidental-error detection, not cryptographic authorization; the host also reads back and compares its complete intended copy before activation.

Limits compare each unsigned raw cell with this image's flashed cell using signed mathematical subtraction. Ignition and both VANOS maps permit -8 through +8 raw counts. AFR permits 0 through +8; negative changes retain reason0A (Leaner). A larger absolute change is B1 reason0B (EditLimit). B1 reason09 now means Integrity/CRC mismatch. Other refusal reasons retain their v1 values.

RAM remains within physical041D00-041FDF. Magic is C0D2 at page10:1D00; seen counter at1D02. Directory starts1D08, five8-byte records: state,pad,offsetLE16,CRC_low_LE16,CRC_high_LE16. Copy starts1D30 (physical041D30), capacity688bytes. The five fixed table descriptors remain main ignition320, idle ignition36, AFR192, intakeVANOS192, exhaustVANOS192. They total932bytes and cannot all fit concurrently. The greatest complete subset is612bytes (idle ignition, AFR and both VANOS tables).

Status is `12 34 A0 payload48 xor`: LTOV4, version2, flags (bit0 running, bit1 richer-only), five8-byte records (state,pad,offsetBE16,CRC32BE), freeBE16. The LTOV header remains16bytes with version2, code start/end, total data end, tablecount5. The first40bytes after code end are the five table descriptors; additional CRC lookup constants follow before data end. Program CRC covers all of them.

Fallback conditions are retained: initialized directory, slot On, firmware running gate, and fewer than300 processed E2A6 ticks since any handled6D frame. Nominally this is3seconds; E2A6 advances in the main scheduler, so it is not an independent wall-clock deadline under all workloads. Housekeeping changes expired/stopped On slots toReady. A reset, A/B-off, free, revert and inactivity retain their established semantics.
