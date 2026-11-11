; the table stubs: one per table, called by its sites' CALLS with R12/R13 = the table's flash address
; A stub substitutes the table's copy only for its own table's address; anything else goes to the reader untouched.
e_map0:
        CMP     R12, #3315h
        JMPA    NZ, to_reader
        CMP     R13, #001Dh
        JMPA    NZ, to_reader
        MOV     R2, #0
        JMPA    UC, subst
e_map1:
        CMP     R12, #35D4h
        JMPA    NZ, to_reader
        CMP     R13, #001Dh
        JMPA    NZ, to_reader
        MOV     R2, #1
        JMPA    UC, subst
e_map2:
        CMP     R12, #169Ch
        JMPA    NZ, to_reader
        CMP     R13, #001Fh
        JMPA    NZ, to_reader
        MOV     R2, #2
        JMPA    UC, subst
e_map3:
        CMP     R12, #2390h
        JMPA    NZ, to_reader
        CMP     R13, #001Dh
        JMPA    NZ, to_reader
        MOV     R2, #3
        JMPA    UC, subst
e_map4:
        CMP     R12, #229Ch
        JMPA    NZ, to_reader
        CMP     R13, #001Dh
        JMPA    NZ, to_reader
        MOV     R2, #4
        JMPA    UC, subst
e_map5:
        CMP     R12, #1FD6h
        JMPA    NZ, to_reader
        CMP     R13, #001Dh
        JMPA    NZ, to_reader
        MOV     R2, #5
        JMPA    UC, subst
e_map6:
        CMP     R12, #1FF6h
        JMPA    NZ, to_reader
        CMP     R13, #001Dh
        JMPA    NZ, to_reader
        MOV     R2, #6
        JMPA    UC, subst
e_map7:
        CMP     R12, #2016h
        JMPA    NZ, to_reader
        CMP     R13, #001Dh
        JMPA    NZ, to_reader
        MOV     R2, #7
        JMPA    UC, subst
e_map8:
        CMP     R12, #2036h
        JMPA    NZ, to_reader
        CMP     R13, #001Dh
        JMPA    NZ, to_reader
        MOV     R2, #8
        JMPA    UC, subst
e_map9:
        CMP     R12, #2056h
        JMPA    NZ, to_reader
        CMP     R13, #001Dh
        JMPA    NZ, to_reader
        MOV     R2, #9
        JMPA    UC, subst
e_map10:
        CMP     R12, #2090h
        JMPA    NZ, to_reader
        CMP     R13, #001Dh
        JMPA    NZ, to_reader
        MOV     R2, #10
        JMPA    UC, subst
e_map11:
        CMP     R12, #20B4h
        JMPA    NZ, to_reader
        CMP     R13, #001Dh
        JMPA    NZ, to_reader
        MOV     R2, #11
        JMPA    UC, subst
e_map12:
        CMP     R12, #2184h
        JMPA    NZ, to_reader
        CMP     R13, #001Dh
        JMPA    NZ, to_reader
        MOV     R2, #12
        JMPA    UC, subst
e_map13:
        CMP     R12, #21A8h
        JMPA    NZ, to_reader
        CMP     R13, #001Dh
        JMPA    NZ, to_reader
        MOV     R2, #13
        JMPA    UC, subst
e_map14:
        CMP     R12, #2278h
        JMPA    NZ, to_reader
        CMP     R13, #001Dh
        JMPA    NZ, to_reader
        MOV     R2, #14
        JMPA    UC, subst
e_map15:
        CMP     R12, #236Ch
        JMPA    NZ, to_reader
        CMP     R13, #001Dh
        JMPA    NZ, to_reader
        MOV     R2, #15
        JMPA    UC, subst
e_map16:
        CMP     R12, #27AAh
        JMPA    NZ, to_reader
        CMP     R13, #001Dh
        JMPA    NZ, to_reader
        MOV     R2, #16
        JMPA    UC, subst
e_map17:
        CMP     R12, #27CEh
        JMPA    NZ, to_reader
        CMP     R13, #001Dh
        JMPA    NZ, to_reader
        MOV     R2, #17
        JMPA    UC, subst
e_map18:
        CMP     R12, #2812h
        JMPA    NZ, to_reader
        CMP     R13, #001Dh
        JMPA    NZ, to_reader
        MOV     R2, #18
        JMPA    UC, subst
e_map19:
        CMP     R12, #281Eh
        JMPA    NZ, to_reader
        CMP     R13, #001Dh
        JMPA    NZ, to_reader
        MOV     R2, #19
        JMPA    UC, subst
e_map20:
        CMP     R12, #2842h
        JMPA    NZ, to_reader
        CMP     R13, #001Dh
        JMPA    NZ, to_reader
        MOV     R2, #20
        JMPA    UC, subst
e_map21:
        CMP     R12, #2866h
        JMPA    NZ, to_reader
        CMP     R13, #001Dh
        JMPA    NZ, to_reader
        MOV     R2, #21
        JMPA    UC, subst
e_map22:
        CMP     R12, #2A5Bh
        JMPA    NZ, to_reader
        CMP     R13, #001Dh
        JMPA    NZ, to_reader
        MOV     R2, #22
        JMPA    UC, subst
e_map23:
        CMP     R12, #2A98h
        JMPA    NZ, to_reader
        CMP     R13, #001Dh
        JMPA    NZ, to_reader
        MOV     R2, #23
        JMPA    UC, subst
e_map24:
        CMP     R12, #2ADCh
        JMPA    NZ, to_reader
        CMP     R13, #001Dh
        JMPA    NZ, to_reader
        MOV     R2, #24
        JMPA    UC, subst
e_map25:
        CMP     R12, #2BB5h
        JMPA    NZ, to_reader
        CMP     R13, #001Dh
        JMPA    NZ, to_reader
        MOV     R2, #25
        JMPA    UC, subst
e_map26:
        CMP     R12, #2BC5h
        JMPA    NZ, to_reader
        CMP     R13, #001Dh
        JMPA    NZ, to_reader
        MOV     R2, #26
        JMPA    UC, subst
e_map27:
        CMP     R12, #2C27h
        JMPA    NZ, to_reader
        CMP     R13, #001Dh
        JMPA    NZ, to_reader
        MOV     R2, #27
        JMPA    UC, subst
e_map28:
        CMP     R12, #2C4Bh
        JMPA    NZ, to_reader
        CMP     R13, #001Dh
        JMPA    NZ, to_reader
        MOV     R2, #28
        JMPA    UC, subst
e_map29:
        CMP     R12, #2C5Bh
        JMPA    NZ, to_reader
        CMP     R13, #001Dh
        JMPA    NZ, to_reader
        MOV     R2, #29
        JMPA    UC, subst
e_map30:
        CMP     R12, #2CDDh
        JMPA    NZ, to_reader
        CMP     R13, #001Dh
        JMPA    NZ, to_reader
        MOV     R2, #30
        JMPA    UC, subst
e_map31:
        CMP     R12, #2D0Dh
        JMPA    NZ, to_reader
        CMP     R13, #001Dh
        JMPA    NZ, to_reader
        MOV     R2, #31
        JMPA    UC, subst
e_map32:
        CMP     R12, #2D41h
        JMPA    NZ, to_reader
        CMP     R13, #001Dh
        JMPA    NZ, to_reader
        MOV     R2, #32
        JMPA    UC, subst
e_map33:
        CMP     R12, #2DC1h
        JMPA    NZ, to_reader
        CMP     R13, #001Dh
        JMPA    NZ, to_reader
        MOV     R2, #33
        JMPA    UC, subst
e_map34:
        CMP     R12, #2E41h
        JMPA    NZ, to_reader
        CMP     R13, #001Dh
        JMPA    NZ, to_reader
        MOV     R2, #34
        JMPA    UC, subst
e_map35:
        CMP     R12, #2E81h
        JMPA    NZ, to_reader
        CMP     R13, #001Dh
        JMPA    NZ, to_reader
        MOV     R2, #35
        JMPA    UC, subst
e_map36:
        CMP     R12, #2F11h
        JMPA    NZ, to_reader
        CMP     R13, #001Dh
        JMPA    NZ, to_reader
        MOV     R2, #36
        JMPA    UC, subst
e_map37:
        CMP     R12, #2F21h
        JMPA    NZ, to_reader
        CMP     R13, #001Dh
        JMPA    NZ, to_reader
        MOV     R2, #37
        JMPA    UC, subst
e_map38:
        CMP     R12, #2F61h
        JMPA    NZ, to_reader
        CMP     R13, #001Dh
        JMPA    NZ, to_reader
        MOV     R2, #38
        JMPA    UC, subst
e_map39:
        CMP     R12, #2FE5h
        JMPA    NZ, to_reader
        CMP     R13, #001Dh
        JMPA    NZ, to_reader
        MOV     R2, #39
        JMPA    UC, subst
e_map40:
        CMP     R12, #30A5h
        JMPA    NZ, to_reader
        CMP     R13, #001Dh
        JMPA    NZ, to_reader
        MOV     R2, #40
        JMPA    UC, subst
e_map41:
        CMP     R12, #3195h
        JMPA    NZ, to_reader
        CMP     R13, #001Dh
        JMPA    NZ, to_reader
        MOV     R2, #41
        JMPA    UC, subst
e_map42:
        CMP     R12, #31D5h
        JMPA    NZ, to_reader
        CMP     R13, #001Dh
        JMPA    NZ, to_reader
        MOV     R2, #42
        JMPA    UC, subst
e_map43:
        CMP     R12, #3470h
        JMPA    NZ, to_reader
        CMP     R13, #001Dh
        JMPA    NZ, to_reader
        MOV     R2, #43
        JMPA    UC, subst
e_map44:
        CMP     R12, #3494h
        JMPA    NZ, to_reader
        CMP     R13, #001Dh
        JMPA    NZ, to_reader
        MOV     R2, #44
        JMPA    UC, subst
e_map45:
        CMP     R12, #35F8h
        JMPA    NZ, to_reader
        CMP     R13, #001Dh
        JMPA    NZ, to_reader
        MOV     R2, #45
        JMPA    UC, subst
e_map46:
        CMP     R12, #3638h
        JMPA    NZ, to_reader
        CMP     R13, #001Dh
        JMPA    NZ, to_reader
        MOV     R2, #46
        JMPA    UC, subst
e_map47:
        CMP     R12, #3678h
        JMPA    NZ, to_reader
        CMP     R13, #001Dh
        JMPA    NZ, to_reader
        MOV     R2, #47
        JMPA    UC, subst
e_map48:
        CMP     R12, #3858h
        JMPA    NZ, to_reader
        CMP     R13, #001Dh
        JMPA    NZ, to_reader
        MOV     R2, #48
        JMPA    UC, subst
e_map49:
        CMP     R12, #3870h
        JMPA    NZ, to_reader
        CMP     R13, #001Dh
        JMPA    NZ, to_reader
        MOV     R2, #49
        JMPA    UC, subst
e_map50:
        CMP     R12, #38B0h
        JMPA    NZ, to_reader
        CMP     R13, #001Dh
        JMPA    NZ, to_reader
        MOV     R2, #50
        JMPA    UC, subst
e_map51:
        CMP     R12, #38F8h
        JMPA    NZ, to_reader
        CMP     R13, #001Dh
        JMPA    NZ, to_reader
        MOV     R2, #51
        JMPA    UC, subst
e_map52:
        CMP     R12, #393Ch
        JMPA    NZ, to_reader
        CMP     R13, #001Dh
        JMPA    NZ, to_reader
        MOV     R2, #52
        JMPA    UC, subst
e_map53:
        CMP     R12, #3A10h
        JMPA    NZ, to_reader
        CMP     R13, #001Dh
        JMPA    NZ, to_reader
        MOV     R2, #53
        JMPA    UC, subst
e_map54:
        CMP     R12, #3A4Ch
        JMPA    NZ, to_reader
        CMP     R13, #001Dh
        JMPA    NZ, to_reader
        MOV     R2, #54
        JMPA    UC, subst
e_map55:
        CMP     R12, #3AA0h
        JMPA    NZ, to_reader
        CMP     R13, #001Dh
        JMPA    NZ, to_reader
        MOV     R2, #55
        JMPA    UC, subst
e_map56:
        CMP     R12, #3AC0h
        JMPA    NZ, to_reader
        CMP     R13, #001Dh
        JMPA    NZ, to_reader
        MOV     R2, #56
        JMPA    UC, subst
e_map57:
        CMP     R12, #3AFAh
        JMPA    NZ, to_reader
        CMP     R13, #001Dh
        JMPA    NZ, to_reader
        MOV     R2, #57
        JMPA    UC, subst
e_map58:
        CMP     R12, #3D27h
        JMPA    NZ, to_reader
        CMP     R13, #001Dh
        JMPA    NZ, to_reader
        MOV     R2, #58
        JMPA    UC, subst
e_map59:
        CMP     R12, #3D87h
        JMPA    NZ, to_reader
        CMP     R13, #001Dh
        JMPA    NZ, to_reader
        MOV     R2, #59
        JMPA    UC, subst
e_map60:
        CMP     R12, #0055h
        JMPA    NZ, to_reader
        CMP     R13, #001Eh
        JMPA    NZ, to_reader
        MOV     R2, #60
        JMPA    UC, subst
e_map61:
        CMP     R12, #0079h
        JMPA    NZ, to_reader
        CMP     R13, #001Eh
        JMPA    NZ, to_reader
        MOV     R2, #61
        JMPA    UC, subst
e_map62:
        CMP     R12, #00C9h
        JMPA    NZ, to_reader
        CMP     R13, #001Eh
        JMPA    NZ, to_reader
        MOV     R2, #62
        JMPA    UC, subst
e_map63:
        CMP     R12, #00EDh
        JMPA    NZ, to_reader
        CMP     R13, #001Eh
        JMPA    NZ, to_reader
        MOV     R2, #63
        JMPA    UC, subst
e_map64:
        CMP     R12, #0371h
        JMPA    NZ, to_reader
        CMP     R13, #001Eh
        JMPA    NZ, to_reader
        MOV     R2, #64
        JMPA    UC, subst
e_map65:
        CMP     R12, #03B1h
        JMPA    NZ, to_reader
        CMP     R13, #001Eh
        JMPA    NZ, to_reader
        MOV     R2, #65
        JMPA    UC, subst
e_map66:
        CMP     R12, #03F1h
        JMPA    NZ, to_reader
        CMP     R13, #001Eh
        JMPA    NZ, to_reader
        MOV     R2, #66
        JMPA    UC, subst
e_map67:
        CMP     R12, #0431h
        JMPA    NZ, to_reader
        CMP     R13, #001Eh
        JMPA    NZ, to_reader
        MOV     R2, #67
        JMPA    UC, subst
e_map68:
        CMP     R12, #0499h
        JMPA    NZ, to_reader
        CMP     R13, #001Eh
        JMPA    NZ, to_reader
        MOV     R2, #68
        JMPA    UC, subst
e_map69:
        CMP     R12, #04C9h
        JMPA    NZ, to_reader
        CMP     R13, #001Eh
        JMPA    NZ, to_reader
        MOV     R2, #69
        JMPA    UC, subst
e_map70:
        CMP     R12, #0551h
        JMPA    NZ, to_reader
        CMP     R13, #001Eh
        JMPA    NZ, to_reader
        MOV     R2, #70
        JMPA    UC, subst
e_map71:
        CMP     R12, #0581h
        JMPA    NZ, to_reader
        CMP     R13, #001Eh
        JMPA    NZ, to_reader
        MOV     R2, #71
        JMPA    UC, subst
e_map72:
        CMP     R12, #05B1h
        JMPA    NZ, to_reader
        CMP     R13, #001Eh
        JMPA    NZ, to_reader
        MOV     R2, #72
        JMPA    UC, subst
e_map73:
        CMP     R12, #05F1h
        JMPA    NZ, to_reader
        CMP     R13, #001Eh
        JMPA    NZ, to_reader
        MOV     R2, #73
        JMPA    UC, subst
e_map74:
        CMP     R12, #0639h
        JMPA    NZ, to_reader
        CMP     R13, #001Eh
        JMPA    NZ, to_reader
        MOV     R2, #74
        JMPA    UC, subst
e_map75:
        CMP     R12, #0703h
        JMPA    NZ, to_reader
        CMP     R13, #001Eh
        JMPA    NZ, to_reader
        MOV     R2, #75
        JMPA    UC, subst
e_map76:
        CMP     R12, #075Bh
        JMPA    NZ, to_reader
        CMP     R13, #001Eh
        JMPA    NZ, to_reader
        MOV     R2, #76
        JMPA    UC, subst
e_map77:
        CMP     R12, #07B3h
        JMPA    NZ, to_reader
        CMP     R13, #001Eh
        JMPA    NZ, to_reader
        MOV     R2, #77
        JMPA    UC, subst
e_map78:
        CMP     R12, #0803h
        JMPA    NZ, to_reader
        CMP     R13, #001Eh
        JMPA    NZ, to_reader
        MOV     R2, #78
        JMPA    UC, subst
e_map79:
        CMP     R12, #0853h
        JMPA    NZ, to_reader
        CMP     R13, #001Eh
        JMPA    NZ, to_reader
        MOV     R2, #79
        JMPA    UC, subst
e_map80:
        CMP     R12, #08A3h
        JMPA    NZ, to_reader
        CMP     R13, #001Eh
        JMPA    NZ, to_reader
        MOV     R2, #80
        JMPA    UC, subst
e_map81:
        CMP     R12, #08F3h
        JMPA    NZ, to_reader
        CMP     R13, #001Eh
        JMPA    NZ, to_reader
        MOV     R2, #81
        JMPA    UC, subst
e_map82:
        CMP     R12, #0943h
        JMPA    NZ, to_reader
        CMP     R13, #001Eh
        JMPA    NZ, to_reader
        MOV     R2, #82
        JMPA    UC, subst
e_map83:
        CMP     R12, #0993h
        JMPA    NZ, to_reader
        CMP     R13, #001Eh
        JMPA    NZ, to_reader
        MOV     R2, #83
        JMPA    UC, subst
e_map84:
        CMP     R12, #09E3h
        JMPA    NZ, to_reader
        CMP     R13, #001Eh
        JMPA    NZ, to_reader
        MOV     R2, #84
        JMPA    UC, subst
e_map85:
        CMP     R12, #0A33h
        JMPA    NZ, to_reader
        CMP     R13, #001Eh
        JMPA    NZ, to_reader
        MOV     R2, #85
        JMPA    UC, subst
e_map86:
        CMP     R12, #0A83h
        JMPA    NZ, to_reader
        CMP     R13, #001Eh
        JMPA    NZ, to_reader
        MOV     R2, #86
        JMPA    UC, subst
e_map87:
        CMP     R12, #0AD3h
        JMPA    NZ, to_reader
        CMP     R13, #001Eh
        JMPA    NZ, to_reader
        MOV     R2, #87
        JMPA    UC, subst
e_map88:
        CMP     R12, #0B03h
        JMPA    NZ, to_reader
        CMP     R13, #001Eh
        JMPA    NZ, to_reader
        MOV     R2, #88
        JMPA    UC, subst
e_map89:
        CMP     R12, #0B39h
        JMPA    NZ, to_reader
        CMP     R13, #001Eh
        JMPA    NZ, to_reader
        MOV     R2, #89
        JMPA    UC, subst
e_map90:
        CMP     R12, #0BB9h
        JMPA    NZ, to_reader
        CMP     R13, #001Eh
        JMPA    NZ, to_reader
        MOV     R2, #90
        JMPA    UC, subst
e_map91:
        CMP     R12, #0BF9h
        JMPA    NZ, to_reader
        CMP     R13, #001Eh
        JMPA    NZ, to_reader
        MOV     R2, #91
        JMPA    UC, subst
e_map92:
        CMP     R12, #0C39h
        JMPA    NZ, to_reader
        CMP     R13, #001Eh
        JMPA    NZ, to_reader
        MOV     R2, #92
        JMPA    UC, subst
e_map93:
        CMP     R12, #0D9Eh
        JMPA    NZ, to_reader
        CMP     R13, #001Eh
        JMPA    NZ, to_reader
        MOV     R2, #93
        JMPA    UC, subst
e_map94:
        CMP     R12, #0DDEh
        JMPA    NZ, to_reader
        CMP     R13, #001Eh
        JMPA    NZ, to_reader
        MOV     R2, #94
        JMPA    UC, subst
e_map95:
        CMP     R12, #0E1Eh
        JMPA    NZ, to_reader
        CMP     R13, #001Eh
        JMPA    NZ, to_reader
        MOV     R2, #95
        JMPA    UC, subst
e_map96:
        CMP     R12, #0E5Eh
        JMPA    NZ, to_reader
        CMP     R13, #001Eh
        JMPA    NZ, to_reader
        MOV     R2, #96
        JMPA    UC, subst
e_map97:
        CMP     R12, #0E9Eh
        JMPA    NZ, to_reader
        CMP     R13, #001Eh
        JMPA    NZ, to_reader
        MOV     R2, #97
        JMPA    UC, subst
e_map98:
        CMP     R12, #0EBEh
        JMPA    NZ, to_reader
        CMP     R13, #001Eh
        JMPA    NZ, to_reader
        MOV     R2, #98
        JMPA    UC, subst
e_map99:
        CMP     R12, #0EDEh
        JMPA    NZ, to_reader
        CMP     R13, #001Eh
        JMPA    NZ, to_reader
        MOV     R2, #99
        JMPA    UC, subst
e_map100:
        CMP     R12, #0EF6h
        JMPA    NZ, to_reader
        CMP     R13, #001Eh
        JMPA    NZ, to_reader
        MOV     R2, #100
        JMPA    UC, subst
e_map101:
        CMP     R12, #0F2Eh
        JMPA    NZ, to_reader
        CMP     R13, #001Eh
        JMPA    NZ, to_reader
        MOV     R2, #101
        JMPA    UC, subst
e_map102:
        CMP     R12, #0F6Eh
        JMPA    NZ, to_reader
        CMP     R13, #001Eh
        JMPA    NZ, to_reader
        MOV     R2, #102
        JMPA    UC, subst
e_map103:
        CMP     R12, #0FC6h
        JMPA    NZ, to_reader
        CMP     R13, #001Eh
        JMPA    NZ, to_reader
        MOV     R2, #103
        JMPA    UC, subst
e_map104:
        CMP     R12, #1061h
        JMPA    NZ, to_reader
        CMP     R13, #001Eh
        JMPA    NZ, to_reader
        MOV     R2, #104
        JMPA    UC, subst
e_map105:
        CMP     R12, #10A1h
        JMPA    NZ, to_reader
        CMP     R13, #001Eh
        JMPA    NZ, to_reader
        MOV     R2, #105
        JMPA    UC, subst
e_map106:
        CMP     R12, #10E1h
        JMPA    NZ, to_reader
        CMP     R13, #001Eh
        JMPA    NZ, to_reader
        MOV     R2, #106
        JMPA    UC, subst
e_map107:
        CMP     R12, #1121h
        JMPA    NZ, to_reader
        CMP     R13, #001Eh
        JMPA    NZ, to_reader
        MOV     R2, #107
        JMPA    UC, subst
e_map108:
        CMP     R12, #11A9h
        JMPA    NZ, to_reader
        CMP     R13, #001Eh
        JMPA    NZ, to_reader
        MOV     R2, #108
        JMPA    UC, subst
e_map109:
        CMP     R12, #175Ch
        JMPA    NZ, to_reader
        CMP     R13, #001Fh
        JMPA    NZ, to_reader
        MOV     R2, #109
        JMPA    UC, subst
e_map110:
        CMP     R12, #181Ch
        JMPA    NZ, to_reader
        CMP     R13, #001Fh
        JMPA    NZ, to_reader
        MOV     R2, #110
        JMPA    UC, subst
e_map111:
        CMP     R12, #183Ch
        JMPA    NZ, to_reader
        CMP     R13, #001Fh
        JMPA    NZ, to_reader
        MOV     R2, #111
        JMPA    UC, subst
e_map112:
        CMP     R12, #186Ch
        JMPA    NZ, to_reader
        CMP     R13, #001Fh
        JMPA    NZ, to_reader
        MOV     R2, #112
        JMPA    UC, subst
e_map113:
        CMP     R12, #18ECh
        JMPA    NZ, to_reader
        CMP     R13, #001Fh
        JMPA    NZ, to_reader
        MOV     R2, #113
        JMPA    UC, subst
e_map114:
        CMP     R12, #192Ch
        JMPA    NZ, to_reader
        CMP     R13, #001Fh
        JMPA    NZ, to_reader
        MOV     R2, #114
        JMPA    UC, subst
e_map115:
        CMP     R12, #1944h
        JMPA    NZ, to_reader
        CMP     R13, #001Fh
        JMPA    NZ, to_reader
        MOV     R2, #115
        JMPA    UC, subst
e_map116:
        CMP     R12, #195Ch
        JMPA    NZ, to_reader
        CMP     R13, #001Fh
        JMPA    NZ, to_reader
        MOV     R2, #116
        JMPA    UC, subst
e_map117:
        CMP     R12, #2C72h
        JMPA    NZ, to_reader
        CMP     R13, #001Fh
        JMPA    NZ, to_reader
        MOV     R2, #117
        JMPA    UC, subst
e_map118:
        CMP     R12, #2CB4h
        JMPA    NZ, to_reader
        CMP     R13, #001Fh
        JMPA    NZ, to_reader
        MOV     R2, #118
        JMPA    UC, subst
e_map119:
        CMP     R12, #2CF4h
        JMPA    NZ, to_reader
        CMP     R13, #001Fh
        JMPA    NZ, to_reader
        MOV     R2, #119
        JMPA    UC, subst
e_map120:
        CMP     R12, #2D3Ah
        JMPA    NZ, to_reader
        CMP     R13, #001Fh
        JMPA    NZ, to_reader
        MOV     R2, #120
        JMPA    UC, subst
e_map121:
        CMP     R12, #2D7Ah
        JMPA    NZ, to_reader
        CMP     R13, #001Fh
        JMPA    NZ, to_reader
        MOV     R2, #121
        JMPA    UC, subst
e_map122:
        CMP     R12, #2DBAh
        JMPA    NZ, to_reader
        CMP     R13, #001Fh
        JMPA    NZ, to_reader
        MOV     R2, #122
        JMPA    UC, subst
e_map123:
        CMP     R12, #2DCAh
        JMPA    NZ, to_reader
        CMP     R13, #001Fh
        JMPA    NZ, to_reader
        MOV     R2, #123
        JMPA    UC, subst

; R2 identifies a catalogue entry. The original reader overwrites R2-R5 before use.
subst:
        EXTP    #3, #1
        MOV     R3, W_MAGIC
        CMP     R3, #MAGIC
        JMPR    NZ, to_reader
        MOV     R5, R2
        SHL     R5, #8
        OR      R5, #ST_ON
        EXTP    #3, #1
        MOVBZ   R4, W_DIR+35
        CMP     R4, #255
        JMPR    Z, rd_base
        MOV     R3, R2
        SHR     R3, #3
        ADD     R3, #W_BITMAP
        EXTP    #3, #1
        MOVB    RL4, [R3]
        MOVBZ   R4, RL4
        AND     R2, #7
        SHR     R4, R2
        JNB     R4.0, to_reader
rd_base:
        MOV     R3, #W_DIR
rd_loop:
        EXTP    #3, #1
        CMP     R5, [R3]
        JMPR    Z, rd_found
        ADD     R3, #8
        EXTP    #3, #1
        CMP     R5, [R3]
        JMPR    Z, rd_found
        ADD     R3, #8
        EXTP    #3, #1
        CMP     R5, [R3]
        JMPR    Z, rd_found
        ADD     R3, #8
        EXTP    #3, #1
        CMP     R5, [R3]
        JMPR    Z, rd_found
        ADD     R3, #8
        EXTP    #3, #1
        CMP     R5, [R3]
        JMPR    Z, rd_found
rd_link:
        EXTP    #3, #1
        MOV     R4, [R3+2]
        SHR     R4, #8
        CMP     R4, #50
        JMPR    UGT, to_reader
        SHL     R4, #2
        ADD     R4, #W_COPY
        ADD     R3, #8
        CMP     R4, R3
        JMPR    ULT, to_reader
        MOV     R3, R4
        EXTP    #3, #1
        CMP     R5, [R3]
        JMPR    NZ, rd_link
rd_found:
        CALLA   UC, off_due
        CMP     R4, #0
        JMPR    NZ, to_reader
        EXTP    #3, #1
        MOVB    RL4, [R3+2]
        MOVBZ   R4, RL4
        SHL     R4, #2
        MOV     R13, #10h
        CMP     R4, #704
        JMPR    ULT, rd_external
        SUB     R4, #704
        ADD     R4, #26E0h
        MOV     R12, R4
        MOV     R13, #3
        JMPR    UC, to_reader
rd_external:
        ADD     R4, #1D00h
        MOV     R12, R4

to_reader:
        JMPS    0Dh, 029Ah
