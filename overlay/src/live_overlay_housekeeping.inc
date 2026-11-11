; housekeeping: queue-1 task 09h's entry, every 10 ms at every engine state. With the magic present, when the
; engine is not running or the app has been silent for 3 s, every On table goes to Ready, and stays there until the app
; switches it on again. Then the task itself, with R3 and R4 as the scheduler left them.
hk:
        MOV     [-R0], R3
        MOV     [-R0], R4
        CALLA   UC, pops_tick
        CALLA   UC, guard_tick
        CALLA   UC, blip_tick
        CALLA   UC, watch_quiet
        CALLA   UC, watch_alias
        EXTP    #3, #1
        MOV     R4, W_MAGIC
        CMP     R4, #MAGIC
        JMPR    NZ, hk_task
        CALLA   UC, off_due
        CMP     R4, #0
        JMPR    Z, hk_task
        CALLA   UC, all_off
hk_task:
        MOV     R4, [R0+]
        MOV     R3, [R0+]
        JMPS    0Dh, 080DEh
