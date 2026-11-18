; =====================================================================
;  DRAW.INC - Dibuix del men£ d'arrencada (compartit per IOX i IOCONFIG,
;             perquŠ la vista prŠvia sigui idŠntica al men£ real)
;
;  Variables que ha de definir el programa que inclou aquest fitxer:
;     CFGBLK   bloc de configuraci¢ (DS:CFGBLK)
;     m_lbl    5 dw: punters (DS) als noms de les opcions
;     m_n      db: nombre d'opcions (1..5)
;     m_sel    db: opci¢ seleccionada (0..m_n-1)
;     m_secs   db: segons que queden (T_INF = no es mostra)
;     d_cols   dw, d_left db, d_top db, d_row0 db, d_w db: de treball
;
;  Dues disposicions (C_LAYOUT):
;   0 centrada: t¡tol a dalt en una barra, opcions, ajuda i compte enrere
;   1 cl…ssica (com les primeres versions): a dalt a l'esquerra,
;     "F1 = nom" en barres de CLW columnes, i a sota "T¡tol: 5" amb el
;     compte enrere al costat; sense l¡nia d'ajuda
;  Escriu directament a la mem•ria de v¡deo de text (B800h).
;
;  drawall  dibuixa tot el men£ (nom‚s cal fer-ho una vegada)
;  d_item   repinta una sola opci¢ (CL = ¡ndex)
;  d_count  repinta nom‚s la l¡nia del compte enrere
; =====================================================================

; ---- d_setup: calcula columnes, marge esquerre i fila superior -------
d_setup:
        push    es
        xor     ax, ax
        mov     es, ax
        mov     ax, [es:0x044A]                 ; columnes del mode actual
        pop     es
        cmp     ax, MENUW
        jae     .c
        mov     ax, MENUW
.c:
        mov     [d_cols], ax
        cmp     byte [CFGBLK+C_LAYOUT], 0
        jne     .cls
        mov     byte [d_w], MENUW
        sub     ax, MENUW
        shr     ax, 1
        mov     [d_left], al
        mov     al, [m_n]
        add     al, 5                           ; t¡tol, buit, opcions,
        mov     ah, 25                          ;   buit, ajuda, compte
        sub     ah, al
        shr     ah, 1
        mov     [d_top], ah
        add     ah, 2
        mov     [d_row0], ah
        ret
.cls:   mov     byte [d_w], CLW                 ; cl…ssica: fila 0 buida,
        mov     byte [d_left], 0                ;   opcions des de la fila 1
        mov     byte [d_top], 0
        mov     byte [d_row0], 1
        ret

; ---- d_addr: DH = fila, DL = columna -> ES:DI a la mem•ria de v¡deo ---
d_addr:
        push    ax
        push    dx
        mov     ax, 0xB800
        mov     es, ax
        mov     al, dh
        xor     ah, ah
        mul     word [d_cols]
        pop     dx
        push    dx
        xor     dh, dh
        add     ax, dx
        shl     ax, 1
        mov     di, ax
        pop     dx
        pop     ax
        ret

; ---- d_bar: omple d_w caselles de la fila DH amb espais (atribut BL) --
d_bar:
        push    cx
        push    dx
        mov     dl, [d_left]
        mov     cl, [d_w]
        xor     ch, ch
        call    d_addr
        mov     al, ' '
        mov     ah, bl
        rep     stosw
        pop     dx
        pop     cx
        ret

; ---- d_text: escriu ASCIIZ (DS:SI) a fila DH, columna DL, atribut BL --
d_text:
        push    ax
        call    d_addr
        mov     ah, bl
.l:     lodsb
        or      al, al
        jz      .f
        stosw
        jmp     short .l
.f:     pop     ax
        ret

; ---- d_center: escriu DS:SI centrat dins del men£, a la fila DH ------
d_center:
        push    cx
        push    si
        xor     cx, cx
.n:     lodsb
        or      al, al
        jz      .e
        inc     cx
        jmp     short .n
.e:     pop     si
        mov     dl, MENUW
        cmp     cl, dl
        jbe     .ok
        mov     cl, dl
.ok:    sub     dl, cl
        shr     dl, 1
        add     dl, [d_left]
        pop     cx
        jmp     d_text

; ---- d_item: repinta l'opci¢ CL ----------------------------------------
d_item:
        push    ax
        push    bx
        push    dx
        push    si
        push    di
        push    es
        mov     dh, [d_row0]
        add     dh, cl
        mov     bl, [CFGBLK+C_ATXT]
        cmp     cl, [m_sel]
        jne     .nsel
        mov     bl, [CFGBLK+C_ASEL]
.nsel:  call    d_bar
        mov     al, cl
        add     al, '1'
        mov     [d_fk+2], al
        mov     [d_fk2+1], al
        mov     dl, [d_left]
        mov     si, d_fk2                       ; cl…ssica: "F1 = nom"
        cmp     byte [CFGBLK+C_LAYOUT], 0
        jne     .cl
        inc     dl
        mov     si, d_fk
        call    d_text
        add     dl, 6
        jmp     short .lb
.cl:    call    d_text
        add     dl, 5
.lb:    mov     si, cx
        and     si, 0x00FF
        shl     si, 1
        mov     si, [m_lbl+si]
        call    d_text
        pop     es
        pop     di
        pop     si
        pop     dx
        pop     bx
        pop     ax
        ret

; ---- d_count: repinta la l¡nia del compte enrere ----------------------
d_count:
        push    ax
        push    bx
        push    dx
        push    si
        push    di
        push    es
        mov     dh, [d_top]
        add     dh, 4
        add     dh, [m_n]
        mov     bl, [CFGBLK+C_ABG]
        cmp     byte [CFGBLK+C_LAYOUT], 0
        jne     .cls
        call    d_bar                           ; esborra la l¡nia
        cmp     byte [m_secs], T_INF
        je      .ret
        mov     al, [m_secs]
        aam                                     ; AH = desenes, AL = unitats
        add     ax, '00'
        cmp     ah, '0'
        jne     .two
        mov     ah, ' '
.two:   mov     [d_cnt+13], ah
        mov     [d_cnt+14], al
        mov     si, d_cnt
        call    d_center
.ret:   pop     es
        pop     di
        pop     si
        pop     dx
        pop     bx
        pop     ax
        ret
.cls:   ; cl…ssica: "T¡tol: 5" a la fila 1+m_n+1, columna 0
        sub     dh, 2
        xor     dl, dl
        push    cx
        push    dx
        call    d_addr                          ; esborra TITLESZ+5 caselles
        mov     cx, TITLESZ+5
        mov     al, ' '
        mov     ah, bl
        rep     stosw
        pop     dx
        pop     cx
        mov     bl, [CFGBLK+C_ATIT]
        mov     si, CFGBLK+C_TITLE
        call    d_text                          ; DI = just darrere el t¡tol
        mov     ah, bl
        mov     al, ':'
        stosw
        cmp     byte [m_secs], T_INF
        je      .ret
        mov     al, ' '
        stosw
        mov     al, [m_secs]
        aam
        add     ax, '00'
        cmp     ah, '0'
        je      .one
        push    ax
        mov     al, ah
        mov     ah, bl
        stosw
        pop     ax
.one:   mov     ah, bl
        stosw
        jmp     short .ret

; ---- drawall: dibuixa tot el men£ -------------------------------------
drawall:
        push    ax
        push    bx
        push    cx
        push    dx
        push    si
        push    di
        push    es
        call    d_setup
        mov     ax, 0x0600                      ; esborra la pantalla
        mov     bh, [CFGBLK+C_ABG]              ;   amb el color de fons
        xor     cx, cx
        mov     dh, 24
        mov     dl, [d_cols]
        dec     dl
        int     0x10
        cmp     byte [CFGBLK+C_LAYOUT], 0
        jne     .op
        ; t¡tol
        mov     dh, [d_top]
        mov     bl, [CFGBLK+C_ATIT]
        call    d_bar
        mov     si, CFGBLK+C_TITLE
        call    d_center
.op:    ; opcions
        xor     cx, cx
.it:    cmp     cl, [m_n]
        jae     .fi
        call    d_item
        inc     cx
        jmp     short .it
.fi:    cmp     byte [CFGBLK+C_LAYOUT], 0
        jne     .cnt
        ; ajuda
        mov     dh, [d_top]
        add     dh, 3
        add     dh, [m_n]
        mov     bl, [CFGBLK+C_ABG]
        mov     si, d_hint
        call    d_center
.cnt:   call    d_count
        pop     es
        pop     di
        pop     si
        pop     dx
        pop     cx
        pop     bx
        pop     ax
        ret

d_fk    db      ' F1', 0
d_fk2   db      'F1 = ', 0
d_hint  db      0x18, 0x19, ' i Retorn: triar   F1-F5: directe', 0
d_cnt   db      'Arrencada en 00 s', 0
