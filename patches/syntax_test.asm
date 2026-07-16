        CPU     80C167
        ASSUME  DPP0:1Ch, DPP1:3Bh, DPP2:10h, DPP3:3
        ORG     0CB545h
M01:    MOVB    RL4, [R2+00h]
M02:    MOVB    RL4, [R2+02h]
M03:    MOVB    RL4, [R2+04h]
M04:    MOVB    RL4, [R2+06h]
M05:    MOVB    RL4, [R2+08h]
M06:    MOVB    R4L, [R2+02h]
M07:    MOVB    R4L, [R2+00h]
M08:    MOVB    R10L, [R2+00h]
M09:    MOVB    R13L, [R2+00h]
M10:    MOVB    RL4, [R2+0006h]
M11:    MOVB    RL13, [R2+00h]
M12:    MOVB    R13L, [R2+00h]
M13:    MOV     R4, [R2+06h]
M14:    MOVB    RL4, [R2+6h]
M15:    MOVB    RL4, [R2+6]
