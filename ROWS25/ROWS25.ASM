; =====================================================================
;  ROWS25.ASM - Posa a la zona de dades de la BIOS el nombre de files de
;               la pantalla (0040:0084 = 24) i l'al‡ada del car…cter
;               (0040:0085 = 8) si la BIOS els ha deixat a 0, com fan les
;               BIOS de l'Špoca del CGA (PC1512). Els fan servir, per
;               exemple, MEM /P i altres programes per parar a cada
;               pantalla. Amb EGA o VGA (valors ja posats) no toca res.
;  és: ROWS25 a l'AUTOEXEC.BAT.  No queda resident.
;  Construcci¢: nasm -f bin ROWS25.ASM -o ROWS25.COM
; =====================================================================
        cpu     8086
        org     0x100
        mov     ax, 0x40
        mov     es, ax
        cmp     byte [es:0x84], 0
        jne     .fi
        mov     byte [es:0x84], 24              ; files - 1
        cmp     word [es:0x85], 0
        jne     .fi
        mov     word [es:0x85], 8               ; punts per car…cter (CGA)
.fi:    mov     ax, 0x4C00
        int     0x21
