; MS43X001 live overlay protocol 10 (V10.4). Build it with ../build_overlay.py on your own MS43X001 bin.
; Code only: it writes the overlay's free flash block and its hook sites, never the calibration.
; Copyright (C) 2026 raph559. GPL-3.0, as a modification of MS43X001 (MS4X project, GPL-3.0).
; Control: 00E6B0..00E6DF; idle/intake: 00E6E0..00E7C3; revision: 00E7C4..00E7C7.
; Main/AFR/exhaust: 041D00..041FBF; private request: 041FC0..041FD7; limiter: 041FD8..041FDF.
; The disabled service monitor must remain disabled. No flash programming occurs at runtime.
;
; This file holds the equates, the header, the flashed settings and the order of the parts; the code is in the
; live_overlay_*.inc files it includes (../README.md lists them). Their order fixes every address, so
; moving an INCLUDE changes the bin.

        CPU     80C167
        ASSUME  DPP0:1Ch, DPP1:3Bh, DPP2:10h, DPP3:3

OVL_VERSION     EQU     10              ; (AS predefines VERSION)
RICHER_ONLY     EQU     0               ; preserves the full original u8 range
N_TABLES        EQU     143               ; the live tables (TABLES would be the label tables to AS)

; control in XRAM, reached through EXTP #3
W_MAGIC         EQU     0E6B0h           ; C0DAh once the handler has initialised the window
W_SEEN          EQU     0E6B2h           ; E2A6 at the last 0x6D frame
W_DIR           EQU     0E6B8h           ; base records: state, ID, offset/4, control/link, CRC32
W_COPY          EQU     0E6E0h           ; control end, followed by idle ignition and intake cam
W_BITMAP        EQU     0E7B0h           ; 20-byte allocation presence index, only with overflow records
COPY_BYTES      EQU     932
MOST_WRITE      EQU     112             ; data bytes in one write: its request is then 128 bytes, inside the firmware's 129
MAGIC           EQU     0C0DAh
SILENCE         EQU     300             ; nominal 3 s of processed firmware ticks
W_SESSION       EQU     0E6B4h
W_REV           EQU     0E7C4h
W_PATCH         EQU     09FC0h
REQ_SESSION     EQU     0F6D1h
REQ_REV         EQU     0F6D5h
BASE_SLOTS      EQU     5
W_HARD          EQU     09FD8h
ST_FREE         EQU     0
ST_LOADED       EQU     1
ST_READY        EQU     2
ST_ON           EQU     3

; Firmware RAM addresses.
F_STATE         EQU     0F900h          ; byte: 2 = synchronised
F_MODE          EQU     0FD2Ch          ; bits 9-12: idle, part load, overrun, fuel cut
F_TICKS         EQU     0E2A6h          ; +1 every 10 ms in the main loop
REQ_LEN         EQU     0F6CEh          ; the request: 12h at F6CD, the length, the command, then F6D0 on
REQ_SUB         EQU     0F6D0h
REQ_ARG         EQU     0F6D9h
REP_LEN         EQU     0F74Eh          ; the reply: 12h at F74D, the length, the status, then the payload
REP_STATUS      EQU     0F74Fh
REP_DATA        EQU     0F750h

        ORG     0CB544h

header: DB      "LTOV"                  ; the signature the app reads with DS2 command 06 at 0C:B544
        DW      OVL_VERSION + 0400h     ; the high byte is the minor
        DW      code_start & 0FFFFh
        DW      code_end & 0FFFFh
        DW      data_end & 0FFFFh
        DW      N_TABLES
        DW      MAGIC

code_start:

        INCLUDE "live_overlay_map_stubs.inc"

        INCLUDE "live_overlay_housekeeping.inc"

        INCLUDE "live_overlay_ds2.inc"

        INCLUDE "live_overlay_tables.inc"

        INCLUDE "live_overlay_patch_crc.inc"

; Everything up to code_end is code: the header gives the app that boundary.
        INCLUDE "live_overlay_limiter.inc"

        INCLUDE "live_overlay_feature_helpers.inc"
        INCLUDE "live_overlay_feature_stubs.inc"

        INCLUDE "live_overlay_word_stubs.inc"

        INCLUDE "live_overlay_pops.inc"

code_end:

        INCLUDE "live_overlay_catalogue.inc"

        INCLUDE "live_overlay_crc_zero_powers.inc"

        INCLUDE "live_overlay_watch.inc"
        INCLUDE "live_overlay_triggers.inc"
        INCLUDE "live_overlay_blip_groups.inc"
        INCLUDE "live_overlay_blip.inc"
        IF      $ > 0CFF80h
        ERROR   "the code overruns the flashed settings at 0C:FF80"
        ENDIF

; The flashed pops settings: off, 4.0 s, -23.625 deg, a real AFR of 7.0 (70), 4,000 rpm, 70.5 deg C, 3.0 deg TPS, 20 km/h.
        ORG     0CFF80h
pops_defaults:
        DB      000h, 028h, 000h, 046h, 07Dh, 09Eh, 01Eh, 014h
; 139 reserved.
stab_defaults:
        DB      000h, 000h, 000h, 000h, 000h, 000h, 000h, 000h
; 140 downshift blip: off, braking or tap, 30 km/h, 5,984 rpm, 1.5 s, 30.0 and 5.0 deg TPS, +20.25 deg.
blip_defaults:
        DB      000h, 003h, 01Eh, 0BBh, 00Fh, 096h, 019h, 075h
; 141 its gears and tap: 5th-4th, 4th-3rd, 3rd-2nd on, 2nd-1st off; 9.8 deg PVS within 0.4 s; a 150 ms lead.
gears_defaults:
        DB      001h, 001h, 001h, 000h, 015h, 028h, 00Fh, 000h
; 142 its ratios, 0.5 rpm per km/h: 1st 113.0, 2nd 67.0, 3rd 44.5, 4th 33.5.
ratio_defaults:
        DB      0E2h, 086h, 059h, 043h, 000h, 000h, 000h, 000h

data_end:

        INCLUDE "live_overlay_feature_hooks.inc"

        INCLUDE "live_overlay_hooks.inc"
