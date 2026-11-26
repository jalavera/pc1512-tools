; CMDTR.ASM - diu on te la part transitoria el COMMAND.COM que l'ha
; engegat (MS-DOS 3.20).  nasm -f bin -o CMDTR.COM CMDTR.ASM
        org     100h
        mov     ax, [16h]               ; el pare: el COMMAND.COM
        mov     di, h_psp
        call    hex
        mov     es, ax
        mov     ax, [es:2]
        mov     di, h_p2
        call    hex
        mov     ax, [es:0C21h]          ; (3.20) segment de la transitoria
        mov     di, h_tr
        call    hex
        mov     ax, [es:0C27h]          ; (3.20) final del bloc on es
        mov     di, h_top
        call    hex
        mov     bx, 0FFFFh              ; el bloc lliure mes gran
        mov     ah, 48h
        int     21h
        mov     ax, bx
        mov     di, h_lg
        call    hex
        mov     dx, txt
        mov     ah, 9
        int     21h
        mov     ax, 4C00h
        int     21h
hex:    push    ax
        mov     cx, 4
.l:     push    cx
        mov     cl, 4
        rol     ax, cl
        pop     cx
        push    ax
        and     al, 0Fh
        add     al, '0'
        cmp     al, '9'
        jbe     .d
        add     al, 7
.d:     mov     [di], al
        inc     di
        pop     ax
        loop    .l
        pop     ax
        ret
txt     db      'COMMAND PSP '
h_psp   db      '0000   PSP:2 '
h_p2    db      '0000', 13, 10
        db      'transitoria a '
h_tr    db      '0000   final '
h_top   db      '0000', 13, 10
        db      'bloc lliure mes gran: '
h_lg    db      '0000 paragrafs', 13, 10, '$'
