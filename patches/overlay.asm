; ---------------------------------------------------------------------------
; MS43X001 live-calibration overlay
;
; A RAM shadow of a few calibration tables. The ECU reads the tables from flash
; as usual; the stub below redirects the read to a RAM copy when the overlay is
; armed. The shadow lives in the external RAM at 9D00..9FDF - the only free
; block on this 8 KiB board, and wiped by the boot RAM test at every key-on,
; so the overlay is always off when the engine was last started.
;
; Control block (external RAM, page 0x10 -> logical 9D00):
;   +00  u16  magic          C0DE  (present only while the overlay is armed)
;   +02  u16  slot count
;   +04  slots, 16 bytes each, up to 6:
;          +00 u16 flash offset   (R12 at the patched call site)
;          +02 u16 flash page     (R13 at the patched call site)
;          +04 u16 RAM offset     (offset within the external RAM window)
;          +06 u16 RAM page       (10h = external RAM)
;          +08 u16 mode           (0 = inactive, 1 = active)
;
; Shadow: 9D64 = ip_iga_ron98_pl (320), 9EA4 = ip_af_target_ron98 (192),
;         9F64 = ip_iga_ron98_is (36), 9F88 = ip_ti_fac_map (16),
;         9F98 = ip_ti_fac_ti (16).  680 of the 736 bytes used.
;
; DS2 command 6D (the slot is dead in this firmware, it answers "unknown"):
;   request  F6D0 = sub, F6D1 = reserved, F6D2/3 = p1, F6D4/5 = p2,
;            F6D6/7 = p3, F6D8/9 = p4, F6DA.. = data
;     00 status   reply: F750 state, F751 count, F752/3 = K (91B6)
;     01 upload   p1 = offset in the shadow, p2 = length, data at F6DA
;     02 bind     p1 = flash offset, p2 = flash page, p3 = RAM offset,
;                 p4 = RAM page; arms the overlay
;     03 unbind   p1 = flash offset, p2 = flash page
;     04 revert   everything back to stock
;     05 write K  p1 = the new value of 91B6 (the fuelling denominator)
;   reply   F74E = frame length, F74F = status (A0 ok, B0 bad parameter,
;           B1 function error), payload from F750
; ---------------------------------------------------------------------------

        CPU     80C167
        ASSUME  DPP0:1Ch, DPP1:3Bh, DPP2:10h, DPP3:3

; ---------------------------------------------------------------------------
; stub A - replaces the call to 0D:029A (u8 map, two axes, bilinear)
;   R12 = flash offset, R13 = flash page on entry
;   R12 = RAM offset,  R13 = RAM page   on exit, if the table is shadowed
; Registers used: R2, R4, R10 - all three are clobbered by 0D:029A itself
; (R2, R3, R4, R5, R10, R15, MDH, MDL), so the caller cannot rely on them.
; ---------------------------------------------------------------------------
        ORG     0CB545h
stubA:
        MOV     R5, 0FE04h           ; save DPP2
        MOV     0FE04h, #010h        ; DPP2 = external RAM
        MOV     R2, #09D00h           ; control block (segment 2 -> DPP2)
        MOV     R10, [R2]             ; magic
        CMP     R10, #0C0DEh
        JMPR    NZ, Aoff
        MOV     R4, [R2+02h]          ; slot count
        ADD     R2, #0004h            ; -> directory
Aloop:
        CMP     R4, #0000h
        JMPR    Z, Aoff
        MOV     R10, [R2]             ; flash offset
        CMP     R10, R12
        JMPR    NZ, Anext
        MOV     R10, [R2+02h]         ; flash page
        CMP     R10, R13
        JMPR    NZ, Anext
        MOV     R10, [R2+08h]         ; mode
        CMP     R10, #0001h
        JMPR    NZ, Anext
        MOV     R12, [R2+04h]         ; RAM offset
        MOV     R13, [R2+06h]         ; RAM page
        JMP     Adone
Anext:
        ADD     R2, #0010h            ; next slot
        SUB     R4, #0001h
        JMPR    UC, Aloop
Aoff:
Adone:
        MOV     0FE04h, R5           ; restore DPP2
        CALLS   0Dh, 029Ah
        RETS

; ---------------------------------------------------------------------------
; stub B - replaces the call to 0D:0262 (u8 curve, one axis, interpolating)
;   Registers used: R2, R4, R10 - 0D:0262 clobbers R2, R4, R10, MDH, MDL.
; ---------------------------------------------------------------------------
        ORG     0CB585h
stubB:
        MOV     R5, 0FE04h           ; save DPP2
        MOV     0FE04h, #010h        ; DPP2 = external RAM
        MOV     R2, #09D00h
        MOV     R10, [R2]             ; magic
        CMP     R10, #0C0DEh
        JMPR    NZ, Boff
        MOV     R4, [R2+02h]
        ADD     R2, #0004h
Bloop:
        CMP     R4, #0000h
        JMPR    Z, Boff
        MOV     R10, [R2]
        CMP     R10, R12
        JMPR    NZ, Bnext
        MOV     R10, [R2+02h]
        CMP     R10, R13
        JMPR    NZ, Bnext
        MOV     R10, [R2+08h]
        CMP     R10, #0001h
        JMPR    NZ, Bnext
        MOV     R12, [R2+04h]
        MOV     R13, [R2+06h]
        JMP     Bdone
Bnext:
        ADD     R2, #0010h
        SUB     R4, #0001h
        JMPR    UC, Bloop
Boff:
Bdone:
        MOV     0FE04h, R5           ; restore DPP2
        CALLS   0Dh, 0262h
        RETS

; ---------------------------------------------------------------------------
; DS2 command 6D handler
; ---------------------------------------------------------------------------
        ORG     0CB5D5h
handler:
        MOV     [-R0], R9
        MOV     [-R0], R8
        MOV     [-R0], R7
        MOV     [-R0], R6
        MOVB    RL3, 0F6D0h           ; sub-command
        CMPB    RL3, #00h
        JMPR    Z, Hstat
        CMPB    RL3, #01h
        JMPR    Z, Hupl
        CMPB    RL3, #02h
        JMP     Hbind
        CMPB    RL3, #03h
        JMP     Hunbind
        CMPB    RL3, #04h
        JMP     Hrevert
        CMPB    RL3, #05h
        JMP     HsetK
        JMP     HerrB0

; --- 00 status -------------------------------------------------------------
Hstat:
        MOV     R2, #09D00h
        MOV     R10, [R2]             ; magic
        CMP     R10, #0C0DEh
        JMPR    NZ, Hst0
        MOVB    RL3, #01h
        MOVB    0F750h, RL3           ; state
        JMP     Hst1
Hst0:
        MOVB    RL3, #00h
        MOVB    0F750h, RL3           ; state
Hst1:
        MOV     R4, [R2+02h]           ; slot count
        MOVB    RL3, RL4
        MOVB    0F751h, RL3
        MOV     R10, 0FB6Bh           ; K
        MOV     0F752h, R10
        MOVB    RL3, #08h
        MOVB    0F74Eh, RL3           ; frame length
        JMP     Hok

; --- 01 upload -------------------------------------------------------------
Hupl:
        MOV     R10, 0F6D2h           ; p1 = offset in the shadow
        MOV     R3, R10
        CMP     R10, #02DFh
        JMPR    UGT, HerrB0
        MOV     R4, 0F6D4h            ; p2 = length
        CMP     R4, #0000h
        JMPR    Z, HerrB0
        CMP     R4, #007Bh
        JMPR    UGT, HerrB0
        ADD     R10, R4
        CMP     R10, #02E0h
        JMPR    UGT, HerrB0
        MOV     R2, #09D00h
        ADD     R2, R3               ; destination
        MOV     R5, 0F6DAh           ; source
Hup_loop:
        MOVB    RL3, [R5]
        MOVB    [R2], RL3
        ADD     R2, #0001h
        ADD     R5, #0001h
        SUB     R4, #0001h
        CMP     R4, #0000h
        JMPR    NZ, Hup_loop
        JMP     Hok

; --- 02 bind ---------------------------------------------------------------
Hbind:
        MOV     R10, 0F6D2h           ; p1 = the flash offset
        MOV     R11, 0F6D4h           ; p2 = the flash page
        MOV     R12, 0F6D6h           ; p3 = the RAM offset
        MOV     R13, 0F6D8h           ; p4 = the RAM page
        MOV     R2, #09D00h
        MOV     R4, [R2+02h]          ; slot count
        CMP     R4, #0006h            ; at most 6 slots
        JMPR    UGT, HerrB0
        MOV     R5, R4
        SHL     R5, #4                ; count * 16
        ADD     R5, #0004h            ; + the directory offset
        ADD     R2, R5               ; the slot address
        MOV     [R2], R10             ; the flash offset
        MOV     [R2+02h], R11         ; the flash page
        MOV     [R2+04h], R12         ; the RAM offset
        MOV     [R2+06h], R13         ; the RAM page
        MOV     R10, #0001h
        MOV     [R2+08h], R10         ; mode = active
        ADD     R4, #0001h
        SUB     R2, #0002h            ; the slot count
        MOV     [R2], R4
        SUB     R2, #0002h            ; the magic
        MOV     R10, #0C0DEh
        MOV     [R2], R10             ; arm the overlay
        JMP     Hok

; --- 03 unbind -------------------------------------------------------------
Hunbind:
        MOV     R10, 0F6D2h           ; p1 = the flash offset
        MOV     R11, 0F6D4h           ; p2 = the flash page
        MOV     R2, #09D00h
        MOV     R4, [R2+02h]
        ADD     R2, #0004h
Hun_loop:
        CMP     R4, #0000h
        JMPR    Z, HerrB1
        MOV     R14, [R2]             ; the flash offset
        CMP     R14, R10
        JMPR    NZ, Hun_next
        MOV     R14, [R2+02h]         ; the flash page
        CMP     R14, R11
        JMPR    NZ, Hun_next
        MOV     R14, #0000h
        MOV     [R2+08h], R14         ; mode = inactive
        JMP     Hok
Hun_next:
        ADD     R2, #0010h
        SUB     R4, #0001h
        JMPR    UC, Hun_loop
        JMP     HerrB1

; --- 04 revert -------------------------------------------------------------
Hrevert:
        MOV     R2, #09D00h
        MOV     R10, #0000h
        MOV     [R2], R10             ; the magic
        MOV     [R2+02h], R10         ; the slot count
        JMP     Hok

; --- 05 write K ------------------------------------------------------------
HsetK:
        MOV     R10, 0F6D2h           ; p1 = the new K
        MOV     0FB6Bh, R10           ; 91B6
        JMP     Hok

; --- replies ---------------------------------------------------------------
Hok:
        MOVB    RL3, #0A0h
        MOVB    0F74Fh, RL3
        JMP     Hexit
HerrB0:
        MOVB    RL3, #0B0h
        MOVB    0F74Fh, RL3
        MOVB    RL3, #04h
        MOVB    0F74Eh, RL3
        JMP     Hexit
HerrB1:
        MOVB    RL3, #0B1h
        MOVB    0F74Fh, RL3
        MOVB    RL3, #04h
        MOVB    0F74Eh, RL3
Hexit:
        MOV     R6, [R0+]
        MOV     R7, [R0+]
        MOV     R8, [R0+]
        MOV     R9, [R0+]
        RETS

; ---------------------------------------------------------------------------
; the patched call sites: a CALLS to the stub instead of to the reader
; ---------------------------------------------------------------------------
        ORG     0AC650h               ; ip_iga_ron98_pl__n__maf
        CALLS   0Dh, 0B545h
        ORG     0AC3A4h               ; ip_iga_ron98_is__n__maf
        CALLS   0Dh, 0B545h
        ORG     0BD40Ah               ; ip_af_target_ron98__maf__n
        CALLS   0Dh, 0B545h
        ORG     0CAB5Ah               ; ip_ti_fac_map__map
        CALLS   0Dh, 0B585h
        ORG     0CAB80h               ; ip_ti_fac_ti__ti
        CALLS   0Dh, 0B585h
        ORG     081FC8Ah               ; the DS2 dispatcher slot for command 6D
        CALLS   0Ch, 0B5D5h
        ORG     0EFE00h               ; program CRC range 4 end: 0C0000-0CFFFF
        DB      0FFh, 0FFh, 0Ch, 00h

