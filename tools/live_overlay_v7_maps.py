"""Pinned u16 readers for V7. Only the listed call sites are redirected."""
import csv
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
SPECS = [
    ('ip_n_sp_is__tco', 'Idle speed', 0x7B674, 12, 0x4372E, 0xD022A, None),
    ('ip_isapwm__tco', 'Idle airflow', 0x7A2E0, 12, 0x436BE, 0xD022A, None),
    ('ip_acin_n_sp_is__tco', 'Idle speed', 0x7955E, 12, 0x4374E, 0xD022A, None),
    ('ip_n_vim_tia__tia', 'DISA', 0x7B680, 16, 0x2FEF0, 0xD022A, None),
    *[(f'ip_t_puc_deacc_{n}__n__maf_mmv', 'Overrun fuel cut', 0x7C400 + (n-1)*48, 48,
       site, 0xD049A, 0x4854 + (n-1)*12)
      for n, site in enumerate([0x2D89E, 0x2D84E, 0x2D862, 0x2D876, 0x2D88A], 1)],
    ('ip_tps_sp_pvs__pvs__n', 'Pedal / throttle', 0x7E4DC, 288, 0x1B12A, 0xD0168, None),
    ('ip_tps_sp_pvs_add_low_n__n_dif__', 'Pedal / throttle', 0x7E5FC, 32, 0x1B018, 0xD09A6, 0x4450),
]


def catalogue(image):
    definitions = {r['name']: r for r in csv.DictReader((ROOT/'calmaps_ms43x.csv').open(encoding='utf-8'))}
    rows = []
    for ident, (name, group, address, size, site, reader, descriptor) in enumerate(SPECS, 127):
        original = bytes([0xDA, reader >> 16, reader & 255, reader >> 8 & 255])
        assert image[site:site+4] == original, (name, 'reader changed')
        definition = definitions[name]
        assert int(definition['data'], 16) == address and definition['elem'] == 'u16'
        assert int(definition['rows'])*int(definition['cols'])*2 == size
        assert definition['sites'] == f'0x{site:X}', (name, 'consumer list changed')
        page, offset = divmod(address, 0x4000)
        if descriptor is None:
            assert image[site-8:site] == bytes([0xE6, 0xFC, offset & 255, offset >> 8, 0xE6, 0xFD, page, 0])
        else:
            physical = 0x6C000 + descriptor - 0x4000
            assert image[physical:physical+4] == offset.to_bytes(2,'little')+page.to_bytes(2,'little')
            assert bytes([0xE6,0xFC,descriptor & 255,descriptor >> 8]) in image[site-24:site]
            # The first six instructions only unpack the descriptor. Resume the unmodified reader after them.
            setup = bytes.fromhex('A8AC D42C0400 D43C0800 D45C0600 D4BC0A00 D4CC0200')
            assert image[(reader & 0x7FFFF):(reader & 0x7FFFF)+22] == setup
        rows.append(dict(id=ident, name=name, group=group, address=address, bytes=size,
                         rows=int(definition['rows']), columns=int(definition['cols']), bits=16,
                         flags=4, sites=[site], reader=reader, descriptor=descriptor, original=original.hex()))
    return rows


def stubs(rows):
    lines = ['; V7 u16 call-site adapters. The original interpolation and axis code stays in flash.']
    for r in rows:
        label = f"word_map{r['id']}"
        page, offset = divmod(r['address'], 0x4000)
        desc = r['descriptor']
        lines += [label+':', '        PUSH 0FF10h', '        MOV [-R0], R4',
                  '        EXTP #3, #1', '        MOV R4, W_MAGIC', '        CMP R4, #MAGIC',
                  f'        JMPR NZ, {label}_flash',
                  '        EXTP #3, #1', '        MOVBZ R4, W_DIR+35', '        CMP R4, #255',
                  f'        JMPR Z, {label}_find',
                  '        EXTP #3, #1', f"        MOVB RL4, W_BITMAP+{r['id']//8}",
                  f"        JNB R4.{r['id']%8}, {label}_flash", label+'_find:']
        if desc is not None:
            lines += [f'        CMP R12, #0{desc:04X}h', f'        JMPR NZ, {label}_flash', '        POP 0FF10h',
                      '        MOV R10, [R12]', '        MOV R2, [R12+4]', '        MOV R3, [R12+8]',
                      '        MOV R5, [R12+6]', '        MOV R11, [R12+10]', '        MOV R12, [R12+2]', '        PUSH 0FF10h']
        else:
            lines += [f'        CMP R12, #0{offset:04X}h', f'        JMPR NZ, {label}_flash',
                      f'        CMP R13, #0{page:02X}h', f'        JMPR NZ, {label}_flash']
        lines += [*[f'        MOV [-R0], R{i}' for i in (2,3,5)]]
        lines += [f"        MOV R2, #{r['id']}", '        CALLA UC, word_address',
                  f"        MOV R{10 if desc is not None else 12}, R3",
                  f"        MOV R{12 if desc is not None else 13}, R4",
                  *[f'        MOV R{i}, [R0+]' for i in (5,3,2,4)], '        POP 0FF10h',
                  f"        JMPS 0Dh, 0{(r['reader'] & 0xFFFF)+(22 if desc is not None else 0):04X}h"]
        lines += [label+'_flash:', '        MOV R4, [R0+]', '        POP 0FF10h',
                  f"        JMPS 0Dh, 0{r['reader'] & 0xFFFF:04X}h"]
    return '\n'.join(lines)+'\n'


ADDRESS = '''; Caller checked runtime magic and, when present, the allocation bitmap.
; R2 is a catalogue ID. Return data offset R3 and page R4; preserve R2.
word_address:
        CALLA UC, entry_addr
        CMP R3, #0
        JMPR Z, wa_flash
        EXTP #3, #1
        MOVB RL4, [R3]
        CMPB RL4, #ST_ON
        JMPR NZ, wa_flash
        CALLA UC, off_due
        CMP R4, #0
        JMPR NZ, wa_flash
        EXTP #3, #1
        MOVB RL4, [R3+2]
        MOVBZ R3, RL4
        SHL R3, #2
        CMP R3, #704
        JMPR ULT, wa_external
        ADD R3, #(26E0h-704)
        MOV R4, #3
        RET
wa_external:
        ADD R3, #1D00h
        MOV R4, #10h
        RET
wa_flash:
        MOV R3, R2
        SHL R3, #3
        ADD R3, #(tables & 0FFFFh)
        EXTS #0Ch, #2
        MOV R4, [R3]
        MOV R3, [R3+2]
        RET
'''


def prepare(image):
    rows = catalogue(image)
    source = (ROOT/'patches/live_overlay_v6.asm').read_text()
    source = source.replace('protocol 6', 'protocol 7').replace('docs/live-overlay-v6.md', 'docs/live-overlay-v7.md')
    source = source.replace('OVL_VERSION     EQU     6', 'OVL_VERSION     EQU     7')
    source = source.replace('N_TABLES        EQU     127', f'N_TABLES        EQU     {127+len(rows)}')
    source = source.replace('C0D6', 'C0D7').replace('0E7B4h', '0E7B0h')
    source = source.replace('16-byte allocation presence', '20-byte allocation presence')
    source = source.replace('CMP     R4, #51', 'CMP     R4, #50')
    source = source.replace('#916', '#912').replace('#(W_BITMAP+16)', '#(W_BITMAP+20)')
    source = source.replace('SUB     R9, #16', 'SUB     R9, #20')
    source = source.replace('final 16 pool-B bytes', 'final 20 pool-B bytes')
    source = source.replace('live_overlay_v6_feature_helpers.inc', 'live_overlay_v7_feature_helpers.inc')
    source = source.replace('code_end:', '        INCLUDE "live_overlay_v7_word_stubs.inc"\n\ncode_end:')
    entries = '\n'.join(f"        DW      0{r['address']//0x4000:03X}h, 0{r['address']%0x4000:04X}h, {r['bytes']}, 4 ; {r['id']} {r['name']}" for r in rows)
    source = source.replace('crc_table:', entries+'\n\ncrc_table:')
    source += '\n'+ '\n'.join(f"        ORG 0{site|0x80000:05X}h\n        CALLS 0Ch, word_map{r['id']} & 0FFFFh" for r in rows for site in r['sites'])+'\n'
    helpers = (ROOT/'patches/live_overlay_v6_feature_helpers.inc').read_text()
    helpers = helpers.replace('        CMP     R2, #124\n        JMPR    ULT, fv_ok',
        '        CMP     R2, #126\n        JMPR    UGT, fv_ok\n        CMP     R2, #124\n        JMPR    ULT, fv_ok')
    (ROOT/'patches/live_overlay_v7.asm').write_text(source)
    (ROOT/'patches/live_overlay_v7_feature_helpers.inc').write_text(helpers)
    (ROOT/'patches/live_overlay_v7_word_stubs.inc').write_text(stubs(rows)+'\n'+ADDRESS)
    (ROOT/'defs/live_overlay_v7_new_maps.json').write_text(json.dumps(rows,indent=2)+'\n')
    return rows
