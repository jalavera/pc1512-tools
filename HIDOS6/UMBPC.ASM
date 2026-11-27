; =====================================================================
;  UMBPC.ASM - Controlador de blocs de memòria superior (UMB) per a
;              8086/8088 (Amstrad PC1512 i XT), per a l'MS-DOS 5/6.
;
;  CONFIG.SYS:
;      DEVICE=C:\DOS\UMBPC.SYS [inici-final]
;      DOS=UMB
;  i després DEVICEHIGH=... al CONFIG.SYS i LH ... a l'AUTOEXEC.BAT.
;
;  Busca RAM entre els segments C000h i EFFFh (o els que es diguin a la
;  línia, en hexadecimal, p. ex. D000-EFFF), en blocs de 2 KB, sense
;  destruir-ne el contingut i saltant les ROM (55AAh) fins al final de
;  la seva finestra de 16 KB (les targetes SCSI i de disc sovint hi tenen
;  RAM o registres després de la ROM, que no s'han de donar al DOS). La RAM trobada
;  s'ofereix al DOS com a UMB amb les funcions 10h/11h de l'XMS, que és
;  el que fa servir DOS=UMB. No hi ha HMA ni memòria estesa (un 8086 no
;  en té): DOS=HIGH no fa res.
;
;  Des de la 1.2, la part resident (el gestor de l'XMS i la taula de
;  blocs, uns 330 bytes) es copia al principi del primer bloc de memòria
;  superior; a la convencional només hi queda la capçalera del
;  controlador (48 bytes).
;
;  Des de la 1.3, se salta el tros on HIDOS6 /D ha posat les dades del DOS
;  (marca 'HIDOS6DD' i la mida en paràgrafs al principi del tros).
;
;  Construcció:  nasm -f bin UMBPC.ASM -o UMBPC.SYS
; =====================================================================

        cpu     8086
        org     0

MAXBLK  equ     8

e_      equ     0x8A
ee      equ     0x82
oo      equ     0xA2
a_      equ     0x85

; ---- capçalera del controlador -------------------------------------------
        dd      -1
        dw      0x8000                          ; de caràcters
        dw      strat
        dw      intr
        db      'UMBPC$$$'

reqp    dd      0

strat:  mov     [cs:reqp], bx
        mov     [cs:reqp+2], es
        retf

intr:   push    ax
        push    bx
        push    es
        les     bx, [cs:reqp]
        mov     word [es:bx+3], 0x0100          ; fet
        cmp     byte [es:bx+2], 0               ; INIT?
        jne     .fi
        call    init
.fi:    pop     es
        pop     bx
        pop     ax
        retf

        align   16, db 0
lowend:                                         ; fins aquí, a la convencional;
                                                ; d'aquí a resend, a dalt
old2f   dd      0
nblk    dw      0
blk     times MAXBLK*3 dw 0                     ; segment, paràgrafs, en ús

; ---- INT 2Fh: instal·lació de l'XMS ---------------------------------------
int2f:  cmp     ax, 0x4300
        jne     .n1
        mov     al, 0x80                        ; hi ha un XMS
        iret
.n1:    cmp     ax, 0x4310
        jne     .old
        push    cs
        pop     es
        mov     bx, xms
        iret
.old:   jmp     far [cs:old2f]

; ---- punt d'entrada de l'XMS (crida far) ------------------------------------
xms:    jmp     short .x                        ; capçalera estàndard
        nop
        nop
        nop
.x:     cmp     ah, 0x00
        je      .ver
        cmp     ah, 0x10
        je      .req
        cmp     ah, 0x11
        je      .rel
        cmp     ah, 0x08
        je      .free
        cmp     ah, 0x07
        je      .a20
        cmp     ah, 0x01
        je      .hma
        mov     bl, 0x80                        ; no implementada
.no:    xor     ax, ax
        retf
.ver:   mov     ax, 0x0200                      ; XMS 2.00
        mov     bx, 0x0100
        xor     dx, dx                          ; no hi ha HMA
        retf
.free:  xor     dx, dx                          ; memòria estesa: cap
        mov     bl, 0xA0
        jmp     short .no
.a20:   xor     bl, bl                          ; A20 desactivada
        jmp     short .no
.hma:   mov     bl, 0x90                        ; no hi ha HMA
        jmp     short .no

        ; ---- 10h: demana un UMB de DX paràgrafs ----
.req:   push    cx
        push    si
        push    di
        mov     si, blk
        mov     cx, [cs:nblk]
        xor     di, di                          ; el més gran lliure
.r1:    jcxz    .r3
        cmp     word [cs:si+4], 0
        jne     .r2
        mov     ax, [cs:si+2]
        cmp     ax, dx
        jae     .give
        cmp     ax, di
        jbe     .r2
        mov     di, ax
.r2:    add     si, 6
        dec     cx
        jmp     short .r1
.r3:    mov     dx, di
        mov     bl, 0xB1                        ; no n'hi ha cap
        or      di, di
        jz      .r4
        mov     bl, 0xB0                        ; n'hi ha de més petits
.r4:    pop     di
        pop     si
        pop     cx
        jmp     short .no
.give:  mov     word [cs:si+4], 1
        mov     bx, [cs:si]
        mov     dx, [cs:si+2]
        mov     ax, 1
        pop     di
        pop     si
        pop     cx
        retf

        ; ---- 11h: allibera l'UMB del segment DX ----
.rel:   push    cx
        push    si
        mov     si, blk
        mov     cx, [cs:nblk]
.l1:    jcxz    .l3
        cmp     [cs:si], dx
        jne     .l2
        cmp     word [cs:si+4], 0
        je      .l2
        mov     word [cs:si+4], 0
        mov     ax, 1
        pop     si
        pop     cx
        retf
.l2:    add     si, 6
        dec     cx
        jmp     short .l1
.l3:    pop     si
        pop     cx
        mov     bl, 0xB2
        jmp     .no

resend:                                         ; fi de la part resident
RESP    equ     (resend-lowend+15)/16           ; paràgrafs que ocupa a dalt

; =====================================================================
;  Inicialització (no queda resident)
; =====================================================================
init:   push    cx
        push    dx
        push    si
        push    di
        push    ds
        push    bp
        push    cs
        pop     ds
        mov     dx, m_banner
        call    print
        ; ---- paràmetres: [inici-final] ----
        push    es
        push    bx
        lds     si, [es:bx+0x12]
.sk1:   lodsb                                   ; salta el nom del fitxer
        cmp     al, ' '
        ja      .sk1
.sk2:   cmp     al, 0x0D
        je      .pdone
        cmp     al, 0x0A
        je      .pdone
        or      al, al
        je      .pdone
        cmp     al, ' '
        ja      .pnum
        lodsb
        jmp     short .sk2
.pnum:  dec     si
        call    hexnum
        jc      .pbad
        mov     bp, ax
        lodsb
        cmp     al, '-'
        jne     .pbad
        call    hexnum
        jc      .pbad
        cmp     ax, bp
        jb      .pbad
        cmp     bp, 0xA000
        jb      .pbad
        mov     [cs:sfrom], bp
        mov     [cs:sto], ax
        jmp     short .pdone
.pbad:  push    cs
        pop     ds
        mov     dx, m_par
        call    print
.pdone: pop     bx
        pop     es
        push    cs
        pop     ds
        ; ---- ja hi ha un XMS? ----
        mov     ax, 0x4300
        int     0x2F
        cmp     al, 0x80
        jne     .scan
        mov     dx, m_xms
        jmp     .quit
        ; ---- busca RAM ----
.scan:  mov     ax, [sfrom]
        and     ax, 0xFF80                      ; múltiple de 2 KB
.sc1:   cmp     ax, [sto]
        ja      .scdone
        mov     cx, ax
        call    isrom                           ; CX = paràgrafs de ROM
        jc      .notram
        call    isram
        jc      .notram
        ; RAM: allarga el darrer bloc o en comença un de nou
        mov     di, [nblk]
        or      di, di
        jz      .new
        mov     si, di
        dec     si
        mov     dx, si
        shl     si, 1
        add     si, dx
        shl     si, 1
        add     si, blk                         ; darrer bloc
        mov     dx, [si]
        add     dx, [si+2]
        cmp     dx, ax
        jne     .new
        add     word [si+2], 0x80
        jmp     short .next
.new:   cmp     di, MAXBLK
        jae     .next
        mov     si, di
        shl     si, 1
        add     si, di
        shl     si, 1
        add     si, blk
        mov     [si], ax
        mov     word [si+2], 0x80
        mov     word [si+4], 0
        inc     word [nblk]
.next:  add     ax, 0x80
        jnc     .sc1
        jmp     short .scdone
.notram:
        add     ax, cx                          ; salta la ROM (o 2 KB)
        jnc     .sc1
.scdone:
        cmp     word [nblk], 0
        jne     .found
        mov     dx, m_none
        jmp     .quit
        ; ---- informa i queda resident ----
.found: mov     si, blk
        mov     cx, [nblk]
.inf:   push    cx
        mov     ax, [si]
        mov     di, l_from
        call    hex4
        mov     ax, [si]
        add     ax, [si+2]
        dec     ax
        mov     di, l_to
        call    hex4
        mov     ax, [si+2]
        mov     cl, 6
        shr     ax, cl                          ; KB
        mov     di, l_kb
        call    dec3
        mov     dx, l_line
        call    print
        add     si, 6
        pop     cx
        loop    .inf
        mov     ax, 0x352F
        int     0x21
        mov     [old2f], bx
        mov     [old2f+2], es
        ; la part resident, al principi del primer bloc: HSEG:lowend
        mov     ax, [blk]
        add     word [blk], RESP                ; el bloc comença més amunt
        sub     word [blk+2], RESP
        sub     ax, (lowend-$$)/16
        mov     es, ax
        mov     si, lowend
        mov     di, si
        mov     cx, resend-lowend
        cld
        rep     movsb
        push    ds
        push    es
        pop     ds
        mov     ax, 0x252F
        mov     dx, int2f
        int     0x21
        pop     ds
        mov     ax, [blk]
        sub     ax, RESP
        mov     di, l_res
        call    hex4
        mov     dx, m_ok
        call    print
        les     bx, [reqp]
        mov     word [es:bx+0x0E], lowend
        mov     [es:bx+0x10], cs
        jmp     short .ret
.quit:  call    print                           ; no queda resident
        mov     dx, m_nores
        call    print
        les     bx, [reqp]
        mov     word [es:bx+0x0E], 0
        mov     [es:bx+0x10], cs
.ret:   pop     bp
        pop     ds
        pop     di
        pop     si
        pop     dx
        pop     cx
        ret

; ---- isrom: CF=1 si al segment AX hi ha una ROM; CX = paràgrafs a saltar
isrom:  push    es
        push    ax
        mov     es, ax
        cmp     word [es:0], 'HI'               ; les dades del DOS (HIDOS6 /D)
        jne     .rom
        cmp     word [es:2], 'DO'
        jne     .rom
        cmp     word [es:4], 'S6'
        jne     .rom
        cmp     word [es:6], 'DD'
        jne     .rom
        mov     cx, [es:8]                      ; paràgrafs a saltar
        pop     ax
        pop     es
        stc
        ret
.rom:   mov     cx, 0x80
        cmp     word [es:0], 0xAA55
        jne     .no
        mov     al, [es:2]                      ; mida en blocs de 512 bytes
        xor     ah, ah
        mov     cl, 5
        shl     ax, cl                          ; paràgrafs
        jnz     .ok
        mov     ax, 0x80
.ok:    ; Moltes targetes (SCSI, discs) tenen RAM o registres just
        ; després de la ROM, dins de la mateixa finestra de 16 KB: se
        ; salta fins al final de la finestra de 16 KB on acaba la ROM.
        pop     cx                              ; CX = segment de la ROM
        push    cx
        add     ax, cx                          ; segment final
        jc      .top
        add     ax, 0x3FF
        jc      .top
        and     ax, 0xFC00
        sub     ax, cx
        mov     cx, ax
        jmp     short .rr
.top:   mov     ax, cx
        neg     ax                              ; fins a FFFF:0
        mov     cx, ax
.rr:    pop     ax
        pop     es
        stc
        ret
.no:    pop     ax
        pop     es
        clc
        ret

; ---- isram: CF=0 si els 2 KB del segment AX són RAM (CX = 0x80) --------
isram:  push    es
        push    bx
        push    dx
        mov     es, ax
        xor     bx, bx
        call    .w
        jc      .r
        mov     bx, 0x400
        call    .w
        jc      .r
        mov     bx, 0x7FE
        call    .w
.r:     mov     cx, 0x80
        pop     dx
        pop     bx
        pop     es
        ret
.w:     mov     dx, [es:bx]                     ; prova no destructiva
        mov     word [es:bx], 0x55AA
        push    word [es:0x100]                 ; "neteja" el bus
        pop     word [es:0x100]
        cmp     word [es:bx], 0x55AA
        jne     .bad
        mov     word [es:bx], 0xAA55
        push    word [es:0x100]
        pop     word [es:0x100]
        cmp     word [es:bx], 0xAA55
        jne     .bad
        mov     [es:bx], dx
        clc
        ret
.bad:   mov     [es:bx], dx
        stc
        ret

; ---- hexnum: llegeix un número hexadecimal de DS:SI; AX, CF=1 si cap --
hexnum: xor     dx, dx
        xor     cx, cx
.h1:    lodsb
        cmp     al, '0'
        jb      .h9
        cmp     al, '9'
        jbe     .hd
        and     al, 0xDF
        cmp     al, 'A'
        jb      .h9
        cmp     al, 'F'
        ja      .h9
        sub     al, 7
.hd:    sub     al, '0'
        push    cx
        mov     cl, 4
        shl     dx, cl
        pop     cx
        or      dl, al
        inc     cx
        jmp     short .h1
.h9:    dec     si
        mov     ax, dx
        cmp     cx, 1
        ret                                     ; CF=1 si CX=0

; ---- hex4: AX en 4 xifres hexadecimals a DS:DI -------------------------
hex4:   mov     cx, 4
.x1:    push    cx
        mov     cl, 4
        rol     ax, cl
        pop     cx
        push    ax
        and     al, 0x0F
        add     al, '0'
        cmp     al, '9'
        jbe     .x2
        add     al, 7
.x2:    mov     [di], al
        inc     di
        pop     ax
        loop    .x1
        ret

; ---- dec3: AX (< 1000) en 3 xifres decimals a DS:DI ----------------------
dec3:   mov     bl, 100
        div     bl
        add     al, '0'
        mov     [di], al
        mov     al, ah
        xor     ah, ah
        mov     bl, 10
        div     bl
        add     ax, '00'
        mov     [di+1], ax
        cmp     byte [di], '0'
        jne     .r
        mov     byte [di], ' '
.r:     ret

print:  mov     ah, 9
        int     0x21
        ret

sfrom   dw      0xC000
sto     dw      0xEFFF

m_banner db     'UMBPC 1.3 - mem', oo, 'ria superior (UMB) per a 8086/8088', 13, 10, '$'
m_par   db      '  Par', a_, 'metre incorrecte (exemple: D000-EFFF). Faig servir C000-EFFF.', 13, 10, '$'
m_xms   db      '  Ja hi ha un controlador XMS (HIMEM?).', 13, 10, '$'
m_none  db      '  No hi ha RAM lliure a la zona de mem', oo, 'ria superior.', 13, 10, '$'
m_nores db      '  UMBPC no queda instal', 0xFA, 'lat.', 13, 10, '$'
m_ok    db      '  Instal', 0xFA, 'lat (resident a '
l_res   db      '0000). Posa DOS=UMB al CONFIG.SYS.', 13, 10, '$'
l_line  db      '  UMB '
l_from  db      '0000-'
l_to    db      '0000 ('
l_kb    db      '000 KB)', 13, 10, '$'
