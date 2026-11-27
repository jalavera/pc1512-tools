; =====================================================================
;  GEMGO.ASM - Tria on carrega GEMHI cada aplicacio GEM (.APP):
;              (fins a la 0.13 es deia APPHI). F1: ajuda (0.14).
;              0.15: mentre corre el GEM, nomes en queda el tros (mig KB);
;              a la llista, primer els .APP, una linia i els .ACC.
;              0.16: A activa o desactiva un accessori (.ACC <-> .ACX).
;              0.17: el COMMAND.COM que obre el GEM.BAT, a la memoria alta.
;              0.18: tambe amb LOADHI GEMGO (LOADHI 0.22 destapa la
;              convencional al primer EXEC).
;              0.19: GEMGO.$$$ ocult i al costat de GEMGO.COM; en
;              arrencar s'esborra el que hagi quedat.
;              programa i dades, a la memoria alta o a la convencional;
;              i cada accessori (.ACC, nomes el programa: GEMHI 0.7).
;              0.20: MS-DOS 5 i 6: per posar el COMMAND.COM a dalt,
;              enllaca un moment els UMB (5803h).
;              MS-DOS 3.20 o posterior, Amstrad PC1512.   Versio 0.20
;  Intro (0.9): obre l'aplicacio triada amb X:\GEM.BAT ruta (COMMAND /C),
;  i en tornar en rellegeix les mesures.
;
;  Muntatge:   nasm -f bin GEMGO.ASM -o GEMGO.COM
;  Us:         GEMGO [unitat:]          p. ex.  GEMGO   o   GEMGO D:
;
;  Cerca tots els .APP de la unitat (per defecte C:), en mostra la llista
;  i, per a cadascun, la marca que porta i on el carrega GEMHI. Amb P i D
;  es canvia la preferencia del programa i de les dades; el canvi s'escriu
;  al moment al fitxer (4 bytes de la capcalera, conservant la data).
;
;  La marca: 4 bytes a l'offset 1Ch de la capcalera MZ:
;     'G','H', programa ('A' alta, 'B' convencional), dades ('A' alta, 0)
;  Sense marca (4 zeros): programa a dalt si hi cap, dades a baix, que es
;  el que fa GEMHI amb qualsevol .APP. Si es tornen a triar els valors per
;  defecte, GEMGO hi torna a posar els 4 zeros: el fitxer queda com era.
;  Nomes es marquen fitxers que tenen aquests 4 bytes a zero (o ja hi
;  tenen una marca) i que no hi tenen la taula de reubicacions: aixi
;  treure la marca deixa el fitxer exactament com era.
;  Marca llarga (0.3), si l'offset 1Ch no es pot fer servir: 8 bytes
;  'GHMK', programa, dades, f, f en un lloc de la capcalera que era tot
;  f (8 bytes iguals, 00h, FFh o qualsevol altre (0.5): el farciment entre la taula de reubicacions i el
;  programa, que el DOS no carrega), alineat a 8 i a partir de l'offset
;  20h. Treure-la hi torna a posar els 8 bytes f (0.4: tambe FFh, com al
;  BASIC2). GEMHI 0.8 o posterior la llegeix.
;  Columnes (0.6): Prog = KB del bloc del programa (mesurat per GEMHI 0.9
;  a GEMHI.LOG, que GEMGO busca a tota la unitat (0.7), o, amb ~, calculat
;  de la capcalera); Dades = punta de
;  dades; Bl = blocs de dades; Crx = si ha demanat fer creixer el bloc
;  del programa (P) o un de dades (D). Pantalla en 80 columnes.
; =====================================================================

        cpu     8086
        org     100h

MAXAPP  equ     100             ; aplicacions de la llista
ESIZE   equ     84              ; entrada: ruta, estat, marca, tipus, lloc, mida, farciment, KB, registre
E_ST    equ     66
E_M     equ     67
E_ACC   equ     71              ; 1: accessori (.ACC)
E_OFF   equ     72              ; 0: marca a 1Ch; si no, lloc de la marca llarga
E_FIL   equ     78              ; byte de farciment del lloc de la marca llarga
E_DEF   equ     79              ; 1: sense marca, el programa va a dalt (accessoris, DESKTOP.APP)
E_EKB   equ     80              ; KB que demana en carregar-se (de la capcalera)
E_LOG   equ     82              ; registre de GEMHI.LOG (adreca a logbuf), 0 si no n'hi ha
LOGMAX  equ     100             ; registres que es llegeixen de GEMHI.LOG
HMAX    equ     1024            ; capcalera que es mira (bytes)
PATHMAX equ     66
MAXNIV  equ     8               ; nivells de carpetes
LROWS   equ     19              ; files de la llista (2..20)
LTOP    equ     2
A_NOR   equ     07h
A_OFF   equ     08h             ; (0.16) accessori desactivat (.ACX)
A_SEL   equ     70h
A_TIT   equ     70h
A_BO    equ     0Ch             ; fila de detall: lletra vermella clara
A_MAL   equ     0Eh             ;   i groga (no es pot marcar, o arriscat; avisos)
A_VER   equ     0Ah             ; fila "Sense GEMHI": verda clara
A_RUTA  equ     30h             ; fila de la ruta: negre sobre blau clar (cian)

start:  jmp     inici

; ---------------------------------------------------------------------
;  Pantalla (escriptura directa a la memoria de video)
; ---------------------------------------------------------------------
; DI = posicio, AH = atribut, SI = text (ASCIIZ), CX = amplada:
; escriu el text (tallat a CX) i omple amb espais fins a CX
camp:   push    ax
        push    es
        mov     es, [vseg]
        jcxz    .x
.l:     mov     al, [si]
        or      al, al
        jz      .p
        inc     si
        stosw
        loop    .l
        jmp     short .x
.p:     mov     al, ' '
        rep     stosw
.x:     pop     es
        pop     ax
        ret

; DI = fila (0..24), columna 0
fila:   push    ax
        push    dx
        mov     ax, 160
        mul     di
        mov     di, ax
        pop     dx
        pop     ax
        ret

; escriu una fila sencera: DI = fila, AH = atribut, SI = text
linia:  call    fila
        mov     cx, 80
        jmp     camp

; ---------------------------------------------------------------------
;  Entrades
; ---------------------------------------------------------------------
; AX = index -> SI = entrada
entrada:
        push    dx
        mov     si, ESIZE
        mul     si
        add     ax, apps
        mov     si, ax
        pop     dx
        ret

; SI = entrada -> AL = 1 si el programa va a baix, AH = 1 si dades a dalt
prefs:  xor     ax, ax                  ; (0.13) sense marca: aplicacio a baix;
        cmp     byte [si+E_DEF], 0      ;   accessori i escriptori, a dalt
        jne     .m
        mov     al, 1
.m:     cmp     word [si+E_M], 'GH'
        jne     .x
        mov     al, 0
        cmp     byte [si+E_M+2], 'B'
        jne     .d
        mov     al, 1
.d:     cmp     byte [si+E_M+3], 'A'
        jne     .x
        mov     ah, 1
.x:     ret

; SI = entrada -> AX = preferencies per defecte (sense marca)
defecte:
        xor     ax, ax
        cmp     byte [si+E_DEF], 0
        jne     .x
        mov     al, 1
.x:     ret

; DI = posicio, AH = atribut, SI = text, DX = caracters, CX = amplada:
; escriu DX caracters (com a molt CX) i omple fins a CX amb espais
campn:  push    ax
        push    si
        push    es
        mov     es, [vseg]
        jcxz    .x
.l:     or      dx, dx
        jz      .p
        mov     al, [si]
        inc     si
        dec     dx
        stosw
        loop    .l
        jmp     short .x
.p:     mov     al, ' '
        rep     stosw
.x:     pop     es
        pop     si
        pop     ax
        ret

; dibuixa la fila de l'entrada AX (si es veu)
dibuixa:
        push    ax
        push    bx
        push    cx
        push    si
        push    di
        push    dx
        cmp     ax, [top]
        jb      .x
        mov     di, ax
        sub     di, [top]
        cmp     di, LROWS
        jae     .x
        add     di, LTOP
        call    fila
        mov     bl, A_NOR
        cmp     ax, [sel]
        jne     .a
        mov     bl, A_SEL
.a:     call    entrada
        cmp     byte [si+E_ACC], 2      ; (0.15) la linia entre .APP i .ACC
        jne     .a2
        mov     ah, A_NOR
        mov     si, t_sep
        mov     cx, 80
        call    camp
        jmp     .x
.a2:    cmp     bl, A_NOR               ; (0.16) desactivat: gris
        jne     .a3
        call    desact
        jne     .a3
        mov     bl, A_OFF
.a3:    push    si
        ; nom (13) i carpeta (23): la ruta sencera es a la fila 21
        mov     ah, bl
        mov     cx, 1
        push    si
        mov     si, t_sp
        call    camp
        pop     si
        push    si
        mov     dx, si                  ; DX: despres de la darrera '\'
.ll:    mov     al, [si]
        inc     si
        or      al, al
        jz      .lf
        cmp     al, '\'
        jne     .ll
        mov     dx, si
        jmp     .ll
.lf:    pop     si
        push    si
        push    dx
        mov     si, dx                  ; el nom
        mov     cx, 13
        call    camp
        pop     dx
        pop     si
        sub     dx, si                  ; la carpeta (amb la '\')
        mov     cx, 30
        cmp     dx, cx
        jbe     .cn
        mov     dx, 29                  ; massa llarga: 29 i 'ฏ'
        mov     cx, 29
        call    campn
        push    si
        mov     si, t_mes
        mov     cx, 1
        call    camp
        pop     si
        jmp     short .cf
.cn:    call    campn
.cf:    pop     si
        push    si                      ; Prog, Dades, Bl, Creix
        push    bx
        call    t_prog
        pop     bx
        mov     ah, bl
        mov     cx, 6
        call    camp
        pop     si
        push    si
        push    bx
        call    t_dad
        pop     bx
        mov     ah, bl
        mov     cx, 6
        call    camp
        pop     si
        push    si
        push    bx
        call    t_bl
        pop     bx
        mov     ah, bl
        mov     cx, 4
        call    camp
        pop     si
        push    si
        push    bx
        call    t_cr
        pop     bx
        mov     ah, bl
        mov     cx, 5
        call    camp
        pop     si
        mov     al, [si+E_ST]           ; programa, dades, marca
        or      al, al
        jz      .ok
        mov     cx, 7
        push    si
        mov     si, t_guio
        call    camp
        mov     cx, 7
        mov     si, t_guio
        call    camp
        pop     si
        jmp     short .x
.ok:    push    si
        call    prefs
        mov     dx, ax
        mov     ah, bl
        mov     si, t_alta
        or      dl, dl
        jz      .p1
        mov     si, t_conv
.p1:    mov     cx, 7
        call    camp
        mov     si, t_conv
        or      dh, dh
        jz      .p2
        mov     si, t_alta
.p2:    pop     cx                      ; (l'entrada)
        push    cx
        xchg    cx, bx
        cmp     byte [bx+E_ACC], 0
        xchg    cx, bx
        je      .p3
        mov     si, t_guio              ; accessori: sense dades
.p3:    mov     cx, 7
        call    camp
        pop     si
.x:     pop     dx
        pop     di
        pop     si
        pop     cx
        pop     bx
        pop     ax
        ret

; SI = entrada -> SI = text de la marca
t_marca:
        push    di
        push    es
        push    ds
        pop     es
        add     si, E_M
        cmp     word [si], 'GH'
        jne     .cap
        mov     word [tmark], '  '
        mov     di, tmark+2             ; GHBA (0 -> '-')
        mov     cx, 4
.l:     lodsb
        or      al, al
        jnz     .c
        mov     al, '-'
.c:     stosb
        loop    .l
        mov     byte [di], 0
        cmp     word [si-4-E_M+E_OFF], 0
        je      .c2
        mov     word [di], '*'          ; marca llarga
.c2:    mov     si, tmark
        jmp     short .r
.cap:   mov     si, t_cap
.r:     pop     es
        pop     di
        ret

; escriu el text SI a DI (AH = atribut), sense omplir
escr:   push    ax
        push    es
        mov     es, [vseg]
.l:     mov     al, [si]
        or      al, al
        jz      .x
        inc     si
        stosw
        jmp     .l
.x:     pop     es
        pop     ax
        ret

; AX = valor, DL = prefix (0 si cap), DH = sufix (0 si cap), CX = amplada
; -> SI = text alineat a la dreta
fmtn:   push    ax
        push    bx
        push    cx
        push    dx
        push    di
        mov     [fpre], dl
        mov     di, tbuf+15
        mov     byte [di], 0
        or      dh, dh
        jz      .n
        dec     di
        mov     [di], dh
.n:     mov     bx, 10
.l:     xor     dx, dx
        div     bx
        add     dl, '0'
        dec     di
        mov     [di], dl
        or      ax, ax
        jnz     .l
        mov     al, [fpre]
        or      al, al
        jz      .p
        dec     di
        mov     [di], al
.p:     mov     ax, tbuf+15
        sub     ax, cx
.q:     cmp     di, ax
        jbe     .r
        dec     di
        mov     byte [di], ' '
        jmp     .q
.r:     mov     si, di
        pop     di
        pop     dx
        pop     cx
        pop     bx
        pop     ax
        ret

; paragrafs (AX) -> KB arrodonits amunt
pkb:    add     ax, 63
        jnc     .a
        mov     ax, 0FFFFh
.a:     push    cx
        mov     cl, 6
        shr     ax, cl
        pop     cx
        ret

; SI = entrada -> SI = text de cada columna (Prog, Dades, Bl, Creix)
t_prog: mov     bx, [si+E_LOG]
        or      bx, bx
        jz      .e
        mov     ax, [bx+14]
        call    pkb
        mov     dx, 'K'*256
        jmp     short .f
.e:     mov     ax, [si+E_EKB]
        or      ax, ax
        jz      .q
        mov     dx, 'K'*256 + '~'
.f:     mov     cx, 6
        jmp     fmtn
.q:     mov     si, t_q6
        ret

t_dad:  cmp     byte [si+E_ACC], 0
        jne     .g
        mov     bx, [si+E_LOG]
        or      bx, bx
        jz      .q
        mov     ax, [bx+16]
        call    pkb
        mov     dx, 'K'*256
        mov     cx, 6
        jmp     fmtn
.g:     mov     si, t_g6
        ret
.q:     mov     si, t_q6
        ret

t_bl:   cmp     byte [si+E_ACC], 0
        jne     .g
        mov     bx, [si+E_LOG]
        or      bx, bx
        jz      .q
        mov     ax, [bx+18]
        xor     dx, dx
        mov     cx, 4
        jmp     fmtn
.g:     mov     si, t_g4
        ret
.q:     mov     si, t_q4
        ret

t_cr:   cmp     byte [si+E_ACC], 0
        jne     .g
        mov     bx, [si+E_LOG]
        or      bx, bx
        jz      .q
        mov     bl, [bx+13]
        and     bx, 3
        shl     bx, 1
        mov     si, [t_crx+bx]
        ret
.g:     mov     si, t_cg
        ret
.q:     mov     si, t_cq
        ret

; tota la llista
llista: push    ax
        push    cx
        push    di
        mov     cx, LROWS
        mov     ax, [top]
.l:     cmp     ax, [napps]
        jae     .b
        call    dibuixa
        jmp     short .n
.b:     push    ax
        push    cx
        mov     di, ax
        sub     di, [top]
        add     di, LTOP
        mov     ah, A_NOR
        mov     si, t_buit
        call    linia
        pop     cx
        pop     ax
.n:     inc     ax
        loop    .l
        pop     di
        pop     cx
        pop     ax
        ret

; les dues files d'explicacio de l'aplicacio triada (22 i 23)
detall: push    ax
        push    bx
        push    cx
        push    dx
        push    si
        push    di
        mov     ax, [sel]
        call    entrada
        mov     bx, si
        call    ruta21
        mov     al, [si+E_ST]
        or      al, al
        jnz     .no
        call    prefs
        push    ax
        call    color                   ; CL = atribut de la fila 22
        mov     [a22], cl
        mov     di, 22                  ; "Amb GEMHI: programa ..., dades ..."
        mov     ah, cl
        mov     si, t_buit
        call    linia
        mov     di, 22
        call    fila
        pop     dx
        mov     ah, [a22]
        cmp     byte [bx+E_ACC], 0
        jne     .acc
        mov     si, t_amb
        call    escr
        mov     si, t_pd
        or      dl, dl
        jz      .a
        mov     si, t_pb
.a:     call    escr
        mov     si, t_dd
        or      dh, dh
        jz      .b
        mov     si, t_db
.b:     call    escr
        mov     si, t_sense
        jmp     short .s
.acc:   mov     si, t_amba
        call    escr
        mov     si, t_pd
        or      dl, dl
        jz      .c
        mov     si, t_pb
.c:     call    escr
        mov     si, t_sensea
.s:     mov     di, 23
        mov     ah, A_VER
        call    linia
        jmp     short .x
.no:    mov     si, t_nocap
        cmp     al, 1
        je      .n1
        mov     si, t_noocup
        cmp     al, 2
        je      .n1
        mov     si, t_nomz
        cmp     al, 4
        je      .n1
        mov     si, t_noll2
.n1:    mov     di, 22
        mov     ah, A_MAL
        call    linia
        mov     di, 23
        mov     si, t_nomar
        mov     ah, A_VER
        call    linia
.x:     pop     di
        pop     si
        pop     dx
        pop     cx
        pop     bx
        pop     ax
        ret

; AX = preferencies (prefs) de l'entrada BX -> CL = A_BO, o A_MAL si
; GEMHI l'ha vist demanar fer creixer el bloc que es posara a dalt
color:  mov     cl, A_BO
        cmp     byte [bx+E_ACC], 0
        jne     .x
        cmp     byte [bx+E_DEF], 0      ; (0.13) aplicacio amb el programa a
        jne     .c                      ;   dalt: el GEM 2.0 s'hi penja en
        or      al, al                  ;   sortir
        jnz     .c
        mov     cl, A_MAL
        ret
.c:     push    bx
        mov     bx, [bx+E_LOG]
        or      bx, bx
        jz      .p
        mov     ch, [bx+13]             ; 1: programa creix; 2: dades creixen
        or      al, al                  ; programa a dalt?
        jnz     .d
        test    ch, 1
        jnz     .m
.d:     or      ah, ah                  ; dades a dalt?
        jz      .p
        test    ch, 2
        jz      .p
.m:     mov     cl, A_MAL
.p:     pop     bx
.x:     ret

; fila 21: la ruta sencera de l'entrada BX i si s'ha mesurat
ruta21: push    ax
        push    cx
        push    dx
        push    si
        push    di
        mov     di, 21
        call    fila
        mov     ah, A_RUTA
        mov     cx, 1
        mov     si, t_sp
        call    camp
        mov     si, bx
        mov     cx, 79
        call    camp
        mov     si, bx                  ; prou curta per al comentari?
        xor     cx, cx
.l:     cmp     byte [si], 0
        je      .f
        inc     si
        inc     cx
        jmp     .l
.f:     cmp     cx, 44
        ja      .x
        mov     di, 21
        call    fila
        add     di, 46*2
        mov     ah, A_RUTA
        cmp     byte [bx+E_ST], 0       ; la marca
        jne     .m
        mov     si, t_mk
        call    escr
        push    si
        mov     si, bx
        push    di
        call    t_marca
        pop     di
        call    escr
        pop     si
        mov     si, t_sp
        call    escr
.m:     mov     si, t_racc
        cmp     byte [bx+E_ACC], 0
        jne     .e
        mov     si, t_rno
        mov     dx, [bx+E_LOG]
        or      dx, dx
        jz      .e
        mov     si, t_rm1
        call    escr
        push    bx
        mov     bx, dx
        mov     ax, [bx+20]
        pop     bx
        push    ax
        xor     dx, dx
        mov     cx, 1
        call    fmtn
        mov     ah, A_RUTA
        call    escr
        pop     ax
        mov     si, t_rm2
        cmp     ax, 1
        jne     .e
        mov     si, t_rm3
.e:     mov     ah, A_RUTA
        call    escr
.x:     pop     di
        pop     si
        pop     dx
        pop     cx
        pop     ax
        ret

; missatge a la fila 23 (SI)
avis:   push    ax
        push    di
        mov     di, 23
        mov     ah, A_MAL
        call    linia
        pop     di
        pop     ax
        ret

; ---------------------------------------------------------------------
;  Fitxers
; ---------------------------------------------------------------------
; SI = entrada (ruta ja posada): llegeix la capcalera i en posa l'estat
; i la marca. 0: es pot marcar; 1: no (capcalera); 2: bytes ocupats;
; 3: no es pot llegir.
llegeix:
        push    ax
        push    bx
        push    cx
        push    dx
        push    di
        mov     byte [si+E_ST], 3
        mov     word [si+E_OFF], 0
        mov     word [si+E_EKB], 0
        mov     dx, si
        mov     ax, 3D00h
        int     21h
        jc      .x
        mov     bx, ax
        mov     dx, hbig
        mov     cx, HMAX
        mov     ah, 3Fh
        int     21h
        pushf
        push    ax
        mov     ah, 3Eh
        int     21h
        pop     cx
        popf
        jc      .x
        mov     byte [si+E_ST], 1
        cmp     cx, 32
        jb      .x
        mov     byte [si+E_ST], 4
        cmp     word [hbig], 'MZ'
        jne     .x
        mov     byte [si+E_ST], 1
        call    estima
        mov     dx, [hbig+8]            ; capcalera (paragrafs)
        cmp     dx, 2
        jb      .x
        cmp     dx, HMAX/16
        jbe     .h1
        mov     dx, HMAX/16
.h1:    push    cx
        mov     cl, 4
        shl     dx, cl
        pop     cx
        cmp     dx, cx                  ; el que s'ha llegit
        jbe     .h2
        mov     dx, cx
.h2:    mov     [hlen], dx
        mov     ax, [hbig+6]            ; final de la taula de reubicacions
        cmp     ax, 4000h
        jae     .rf
        shl     ax, 1
        shl     ax, 1
        add     ax, [hbig+18h]
        jnc     .rr
.rf:    mov     ax, 0FFFFh
.rr:    cmp     ax, 20h
        jae     .r8
        mov     ax, 20h
.r8:    add     ax, 7                   ; alineat a 8
        and     al, 0F8h
        mov     [rend], ax
        ; 1) ja hi ha una marca llarga?
        mov     di, ax
.m1:    mov     ax, di
        add     ax, 8
        cmp     ax, [hlen]
        ja      .m2
        cmp     word [hbig+di], 'GH'
        jne     .m1n
        cmp     word [hbig+di+2], 'MK'
        jne     .m1n
        mov     [si+E_OFF], di
        mov     word [si+E_M], 'GH'
        mov     ax, [hbig+di+4]
        mov     [si+E_M+2], ax
        mov     al, [hbig+di+6]
        mov     [si+E_FIL], al
        mov     byte [si+E_ST], 0
        jmp     .x
.m1n:   add     di, 8
        jmp     .m1
        ; 2) l'offset 1Ch (si la taula de reubicacions no hi es)
.m2:    cmp     word [hbig+6], 0
        je      .m3
        cmp     word [hbig+18h], 20h
        jb      .m4
.m3:    mov     ax, [hbig+1Ch]
        mov     dx, [hbig+1Eh]
        cmp     ax, 'GH'
        je      .m3s
        push    ax
        or      ax, dx
        pop     ax
        jnz     .m4o                    ; ocupat: busca un lloc mes a fons
.m3s:   mov     [si+E_M], ax
        mov     [si+E_M+2], dx
        mov     byte [si+E_ST], 0
        jmp     short .x
.m4o:   mov     byte [si+E_ST], 2
        ; 3) un lloc a zero a la capcalera (el darrer)
.m4:    xor     bx, bx
        mov     di, [rend]
.m5:    mov     ax, di
        add     ax, 8
        cmp     ax, [hlen]
        ja      .m6
        mov     ax, [hbig+di]       ; 8 bytes iguals (00h, FFh o el que sigui)
        cmp     al, ah
        jne     .m5n
        cmp     ax, [hbig+di+2]
        jne     .m5n
        cmp     ax, [hbig+di+4]
        jne     .m5n
        cmp     ax, [hbig+di+6]
        jne     .m5n
        mov     bx, di
        mov     [fil], al
.m5n:   add     di, 8
        jmp     .m5
.m6:    or      bx, bx
        jz      .x
        mov     [si+E_OFF], bx
        mov     al, [fil]
        mov     [si+E_FIL], al
        mov     word [si+E_M], 0
        mov     word [si+E_M+2], 0
        mov     byte [si+E_ST], 0
.x:     pop     di
        pop     dx
        pop     cx
        pop     bx
        pop     ax
        ret

; capcalera a hbig -> [si+E_EKB] = KB que demana en carregar-se: la
; imatge mes la memoria minima (i el PSP, si es un .APP)
estima: push    ax
        push    bx
        push    cx
        push    dx
        mov     ax, [hbig+4]            ; pagines de 512
        mov     dx, 512
        mul     dx
        mov     cx, [hbig+2]            ; bytes de la darrera pagina
        jcxz    .a
        sub     ax, 512
        sbb     dx, 0
        add     ax, cx
        adc     dx, 0
.a:     mov     bx, [hbig+8]            ; menys la capcalera (paragrafs*16)
        mov     cl, 4
        shl     bx, cl
        sub     ax, bx
        sbb     dx, 0
        mov     bx, [hbig+0Ah]          ; mes la memoria minima (paragrafs*16)
        shl     bx, cl
        add     ax, bx
        adc     dx, 0
        mov     bx, [hbig+0Ah]
        mov     cl, 12
        shr     bx, cl
        add     dx, bx
        cmp     byte [si+E_ACC], 0
        jne     .b
        add     ax, 256                 ; el PSP
        adc     dx, 0
.b:     add     ax, 1023                ; KB arrodonits amunt
        adc     dx, 0
        mov     cx, 10
.c:     shr     dx, 1
        rcr     ax, 1
        loop    .c
        mov     [si+E_EKB], ax
        pop     dx
        pop     cx
        pop     bx
        pop     ax
        ret

; SI = entrada, AL = 1 programa a baix, AH = 1 dades a dalt: escriu la
; marca (o els 4 zeros) conservant la data del fitxer. CF=1 si falla.
escriu: push    ax
        push    bx
        push    cx
        push    dx
        mov     word [nb], 0
        mov     word [nb+2], 0
        push    ax
        call    defecte
        mov     cx, ax
        pop     ax
        cmp     ax, cx                  ; per defecte: sense marca
        je      .w
        mov     word [nb], 'GH'
        mov     byte [nb+2], 'A'
        or      al, al
        jz      .d
        mov     byte [nb+2], 'B'
.d:     or      ah, ah
        jz      .w
        mov     byte [nb+3], 'A'
.w:     mov     cx, 4                   ; marca a 1Ch: 4 bytes
        mov     dx, 1Ch
        mov     ax, [si+E_OFF]
        or      ax, ax
        jz      .w2
        mov     dx, ax                  ; marca llarga: 8 bytes
        mov     cx, 8
        mov     al, [si+E_FIL]          ; el farciment que hi havia
        mov     ah, al
        mov     [nb+6], ax
        cmp     word [nb], 0
        jne     .wm
        mov     [nb], ax                ; sense marca: 8 bytes de farciment
        mov     [nb+2], ax
        mov     [nb+4], ax
        jmp     short .w2
.wm:    mov     ax, [nb+2]              ; 'GH' p d -> 'GHMK' p d f f
        mov     [nb+4], ax
        mov     word [nb+2], 'MK'
.w2:    mov     [wlen], cx
        mov     [woff], dx
        mov     dx, si
        mov     ax, 3D02h
        int     21h
        jc      .x
        mov     bx, ax
        mov     ax, 5700h               ; data i hora
        int     21h
        mov     [ftim], cx
        mov     [fdat], dx
        mov     ax, 4200h
        xor     cx, cx
        mov     dx, [woff]
        int     21h
        mov     dx, nb
        mov     cx, [wlen]
        mov     ah, 40h
        int     21h
        mov     byte [werr], 1
        jc      .t
        cmp     ax, [wlen]
        jne     .t
        mov     byte [werr], 0
.t:     mov     ax, 5701h
        mov     cx, [ftim]
        mov     dx, [fdat]
        int     21h
        mov     ah, 3Eh
        int     21h
        call    llegeix                 ; torna-la a llegir: el que hi ha
        cmp     byte [werr], 1
        cmc
.x:     pop     dx
        pop     cx
        pop     bx
        pop     ax
        ret

; ---------------------------------------------------------------------
;  Cerca recursiva dels .APP.  buf = carpeta, [plen] = la seva llargada,
;  AX = nivell
; ---------------------------------------------------------------------
cerca:  push    bp
        mov     bp, sp
        push    ax                      ; [bp-2] nivell
        mov     bx, 43
        mul     bx
        add     ax, dtas
        push    ax                      ; [bp-4] DTA
        push    word [plen]             ; [bp-6] llargada de la carpeta
        mov     di, buf
        add     di, [plen]
        mov     si, t_tot               ; "\*.*"
        call    copia
        mov     dx, [bp-4]
        mov     ah, 1Ah
        int     21h
        mov     dx, buf
        mov     cx, 10h
        mov     ah, 4Eh
        int     21h
.l:     jc      .fi
        mov     bx, [bp-4]
        lea     si, [bx+1Eh]
        test    byte [bx+15h], 10h
        jz      .fitx
        cmp     byte [si], '.'
        je      .seg
        mov     ax, [bp-2]
        inc     ax
        cmp     ax, MAXNIV
        jae     .seg
        call    afegeix_nom             ; buf = carpeta\nom
        jc      .seg
        mov     ax, [bp-2]
        inc     ax
        call    cerca
        mov     ax, [bp-6]
        mov     [plen], ax
        jmp     .seg
.fitx:  call    es_log                  ; GEMHI.LOG: el primer que es trobi
        jne     .fa
        cmp     byte [logpath], 0
        jne     .seg
        call    afegeix_nom
        jc      .seg
        push    si
        mov     si, buf
        mov     di, logpath
        call    copia
        pop     si
        mov     ax, [bp-6]
        mov     [plen], ax
        jmp     .seg
.fa:    mov     byte [esacc], 0
        call    es_app
        je      .fx
        call    es_acc
        jne     .seg
        mov     byte [esacc], 1
.fx:    cmp     word [napps], MAXAPP
        jae     .seg
        call    afegeix_nom
        jc      .rs
        mov     ax, [napps]
        call    entrada
        mov     di, si
        push    si
        mov     si, buf
        call    copia
        pop     si
        mov     al, [esacc]
        mov     [si+E_ACC], al
        mov     [si+E_DEF], al
        push    si                      ; DESKTOP.APP: per defecte a dalt
        push    di
        mov     bx, [bp-4]
        lea     si, [bx+1Eh]
        mov     di, t_desk
.dk:    mov     al, [si]
        cmp     al, [di]
        jne     .dn
        inc     si
        inc     di
        or      al, al
        jnz     .dk
        pop     di
        pop     si
        mov     byte [si+E_DEF], 1
        jmp     short .dd
.dn:    pop     di
        pop     si
.dd:    mov     word [si+E_LOG], 0
        call    llegeix
        inc     word [napps]
.rs:    mov     ax, [bp-6]
        mov     [plen], ax
.seg:   mov     dx, [bp-4]              ; seguent (la DTA es nostra)
        mov     ah, 1Ah
        int     21h
        mov     ah, 4Fh
        int     21h
        jmp     .l
.fi:    pop     ax
        mov     [plen], ax
        mov     sp, bp
        pop     bp
        ret

; buf + "\" + nom (SI): CF=1 si no hi cap (ruta de mes de 65)
afegeix_nom:
        push    si
        xor     cx, cx
.c:     cmp     byte [si], 0
        je      .m
        inc     si
        inc     cx
        jmp     .c
.m:     pop     si
        mov     ax, [plen]
        add     ax, cx
        inc     ax
        cmp     ax, PATHMAX - 1
        jae     .no
        mov     di, buf
        add     di, [plen]
        mov     byte [di], '\'
        inc     di
        call    copia
        mov     [plen], ax
        clc
        ret
.no:    stc
        ret

; ZF=1 si el nom SI acaba en .APP
es_app: push    si
.l:     cmp     byte [si], 0
        je      .f
        inc     si
        jmp     .l
.f:
        cmp     byte [si-4], '.'
        jne     .x
        cmp     byte [si-3], 'A'
        jne     .x
        cmp     byte [si-2], 'P'
        jne     .x
        cmp     byte [si-1], 'P'
.x:     pop     si
        ret

; ZF=1 si el nom SI es GEMHI.LOG
es_log: push    si
        push    di
        mov     di, t_lognm
.l:     mov     al, [si]
        cmp     al, [di]
        jne     .x
        inc     si
        inc     di
        or      al, al
        jnz     .l
.x:     pop     di
        pop     si
        ret

; ZF=1 si el nom SI acaba en .ACC
es_acc: push    si
.l:     cmp     byte [si], 0
        je      .f
        inc     si
        jmp     .l
.f:     cmp     byte [si-4], '.'
        jne     .x
        cmp     byte [si-3], 'A'
        jne     .x
        cmp     byte [si-2], 'C'
        jne     .x
        cmp     byte [si-1], 'X'        ; (0.16) tambe els desactivats
        je      .x
        cmp     byte [si-1], 'C'
.x:     pop     si
        ret

; llegeix GEMHI.LOG (el de GEMHI 0.9 o posterior, trobat en cercar) i hi
; busca cada aplicacio
registre:
        cmp     byte [logpath], 0       ; no n'hi ha
        je      .x
        mov     dx, logpath
        mov     ax, 3D00h
        int     21h
        jc      .x
        mov     bx, ax
        mov     dx, logbuf
        mov     cx, LOGMAX*24
        mov     ah, 3Fh
        int     21h
        pushf
        push    ax
        mov     ah, 3Eh
        int     21h
        pop     ax
        popf
        jc      .x
        xor     dx, dx
        mov     cx, 24
        div     cx
        mov     [nlog], ax
        or      ax, ax
        jz      .x
        xor     ax, ax                  ; cada entrada
.e:     cmp     ax, [napps]
        jae     .x
        push    ax
        call    entrada
        push    si                      ; l'entrada
        cmp     byte [si+E_ACC], 0
        jne     .s
        mov     di, si                  ; el nom, sense carpeta
.b:     mov     dl, [si]
        inc     si
        or      dl, dl
        jz      .bf
        cmp     dl, '\'
        jne     .b
        mov     di, si
        jmp     .b
.bf:    mov     bx, logbuf
        mov     cx, [nlog]
.r:     mov     si, di
        push    bx
.c:     mov     dl, [si]
        cmp     dl, [bx]
        jne     .rn
        inc     si
        inc     bx
        or      dl, dl
        jnz     .c
        pop     bx
        pop     si
        mov     [si+E_LOG], bx
        push    si
        jmp     short .s
.rn:    pop     bx
        add     bx, 24
        loop    .r
.s:     pop     si
        pop     ax
        inc     ax
        jmp     .e
.x:     ret

; (0.15) primer els .APP, en l'ordre que s'han trobat, i despres els
; .ACC; entre els dos grups, una entrada separadora (E_ACC = 2)
ordena: push    ds
        pop     es
        xor     bx, bx                  ; BX: on va el proper .APP
        xor     dx, dx                  ; DX: entrada que es mira
.l:     cmp     dx, [napps]
        jae     .s
        mov     ax, dx
        call    entrada
        cmp     byte [si+E_ACC], 0
        jne     .n
        cmp     dx, bx
        je      .k
        mov     di, hbig                ; l'entrada, a part
        mov     cx, ESIZE
        push    si
        rep     movsb
        pop     si                      ; corre BX..DX-1 una entrada avall
        lea     si, [si-1]
        lea     di, [si+ESIZE]
        mov     ax, dx
        sub     ax, bx
        mov     cx, ESIZE
        push    dx
        mul     cx
        pop     dx
        mov     cx, ax
        std
        rep     movsb
        cld
        mov     ax, bx                  ; i l'entrada, al seu lloc
        call    entrada
        mov     di, si
        mov     si, hbig
        mov     cx, ESIZE
        rep     movsb
.k:     inc     bx
.n:     inc     dx
        jmp     .l
.s:     or      bx, bx                  ; nomes si hi ha dels dos
        jz      .x
        cmp     bx, [napps]
        jae     .x
        mov     ax, [napps]             ; corre BX.. una entrada avall
        call    entrada
        lea     di, [si+ESIZE-1]
        lea     si, [si-1]
        mov     ax, [napps]
        sub     ax, bx
        mov     cx, ESIZE
        mul     cx
        mov     cx, ax
        std
        rep     movsb
        cld
        mov     ax, bx
        call    entrada
        mov     di, si
        mov     cx, ESIZE
        xor     al, al
        rep     stosb
        mov     byte [si+E_ACC], 2
        mov     byte [si+E_ST], 0FEh
        inc     word [napps]
.x:     ret

; copia SI (ASCIIZ) a DI, amb el 0; DI queda sobre el 0
copia:  push    ax
.l:     lodsb
        stosb
        or      al, al
        jnz     .l
        dec     di
        pop     ax
        ret

; ---------------------------------------------------------------------
;  Inici
; ---------------------------------------------------------------------
inici:  cld
        mov     sp, fi_mem              ; la pila, al final de les dades
        mov     bx, (fi_mem-start+100h+15)/16 ; nomes la memoria que cal (per l'EXEC)
        mov     ah, 4Ah
        int     21h
        call    comsp
        call    nomtmp                  ; (0.19) GEMGO.$$$, al costat de
        call    esbtmp                  ;   GEMGO.COM; el d'abans, fora
        mov     ah, 0Fh                 ; mode de video
        int     10h
        mov     [vmode], al
        cmp     ah, 80                  ; 40 columnes: passa a 80
        jae     .v0
        mov     byte [vcanv], 1
        or      al, 2                   ; 0/1 -> 2/3
        cmp     al, 3
        jbe     .vm
        mov     al, 3
.vm:    xor     ah, ah
        int     10h
        mov     ah, 0Fh
        int     10h
.v0:    mov     [tmode], al
        mov     word [vseg], 0B800h
        cmp     al, 7
        jne     .v
        mov     word [vseg], 0B000h
.v:     mov     ah, 3                   ; el cursor, per tornar-lo
        mov     bh, 0
        int     10h
        mov     [curs], cx
        mov     si, 81h                 ; unitat: GEMGO D:
.s:     lodsb
        cmp     al, ' '
        je      .s
        cmp     al, 13
        je      .u
        and     al, 0DFh
        cmp     al, 'A'
        jb      .us
        cmp     al, 'Z'
        ja      .us
        mov     [buf], al
        cmp     byte [si], ':'
        je      .u
.us:    mov     dx, t_us
        mov     ah, 9
        int     21h
        mov     ax, 4C01h
        int     21h
.u:     mov     byte [buf+1], ':'
        mov     word [plen], 2

        call    neteja
        mov     di, 0
        mov     ah, A_TIT
        mov     si, t_tit
        call    linia
        mov     di, 1
        mov     ah, A_NOR
        mov     si, t_cerc
        call    linia
        mov     ah, 1                   ; amaga el cursor
        mov     cx, 2000h
        int     10h

        xor     ax, ax
        call    cerca
        call    ordena                  ; (0.15) .APP, linia, .ACC
        mov     dx, 80h                 ; la DTA, al seu lloc
        mov     ah, 1Ah
        int     21h
        call    registre

        call    marc
        cmp     word [napps], 0
        jne     .hi
        mov     di, LTOP
        mov     ah, A_NOR
        mov     si, t_cap0
        call    linia
        xor     ah, ah
        int     16h
        jmp     surt
.hi:    call    llista
        call    detall

tecla:  xor     ah, ah
        int     16h
        cmp     ax, 3B00h               ; F1: ajuda
        jne     .t0
        jmp     ajuda
.t0:    cmp     al, 27
        je      surt
        cmp     al, 13
        jne     .t1
        jmp     obre
.t1:    and     al, 0DFh                ; majuscula (0 si era tecla especial)
        cmp     al, 'P'
        je      k_p
        cmp     al, 'D'
        je      k_d
        cmp     al, 'T'
        je      k_t
        cmp     al, 'A'                 ; (0.16) activa / desactiva l'accessori
        jne     .t2
        jmp     k_a
.t2:    mov     al, ah
        mov     bx, [sel]
        cmp     al, 48h
        je      .amunt
        cmp     al, 50h
        je      .avall
        cmp     al, 49h
        je      .repag
        cmp     al, 51h
        je      .avpag
        cmp     al, 47h
        je      .inici
        cmp     al, 4Fh
        je      .final
        jmp     tecla
.amunt: or      bx, bx
        jz      tecla
        dec     bx
        jmp     short mou
.avall: inc     bx
        jmp     short mou
.repag: sub     bx, LROWS
        jnc     mou
        xor     bx, bx
        jmp     short mou
.avpag: add     bx, LROWS
        jmp     short mou
.inici: xor     bx, bx
        jmp     short mou
.final: mov     bx, 0FFFFh
        ; (passa a mou: es retalla a la darrera)

; BX = nova seleccio: nomes es redibuixa el que canvia
mou:    mov     ax, [napps]
        dec     ax
        cmp     bx, ax
        jbe     .b
        mov     bx, ax
.b:     push    si                      ; (0.15) la linia separadora no es tria
        mov     ax, bx
        call    entrada
        cmp     byte [si+E_ACC], 2
        pop     si
        jne     .b2
        cmp     bx, [sel]
        jb      .b1
        inc     bx                      ; avall: la seguent
        jmp     short .b2
.b1:    dec     bx                      ; amunt: l'anterior
.b2:    cmp     bx, [sel]
        je      tecla
        mov     ax, [sel]
        mov     [sel], bx
        cmp     bx, [top]
        jb      .dalt
        mov     cx, [top]
        add     cx, LROWS
        cmp     bx, cx
        jae     .baix
        call    dibuixa                 ; l'anterior
        mov     ax, bx
        call    dibuixa                 ; la nova
        jmp     short .d
.dalt:  mov     [top], bx
        call    llista
        jmp     short .d
.baix:  sub     bx, LROWS - 1
        mov     [top], bx
        call    llista
.d:     call    detall
        jmp     tecla

; P, D, T: canvien la marca de l'aplicacio triada i l'escriuen
k_p:    mov     dx, 1
        jmp     short canvia
k_d:    mov     dx, 100h
        jmp     short canvia
k_t:    xor     dx, dx
canvia: mov     ax, [sel]
        call    entrada
        cmp     byte [si+E_ST], 0
        jne     .bip
        cmp     dh, 0                   ; D en un accessori: no
        je      .ok
        cmp     byte [si+E_ACC], 0
        je      .ok
.bip:   mov     ax, 0E07h               ; no es pot: xiulet
        int     10h
        jmp     tecla
.ok:    call    prefs
        or      dx, dx
        jnz     .x
        call    defecte                 ; T: per defecte (sense marca)
        jmp     short .w
.x:     xor     ax, dx                  ; P o D: commuta
.w:     call    escriu
        pushf
        mov     ax, [sel]
        call    dibuixa
        call    detall
        popf
        jnc     .f
        mov     si, t_noesc
        call    avis
.f:     jmp     tecla

; (0.16) A: un accessori, de .ACC a .ACX (el GEM no el carrega) o al
; reves. Es canvia el nom del fitxer al moment
k_a:    mov     ax, [sel]
        call    entrada
        cmp     byte [si+E_ACC], 1
        jne     .bip
        mov     di, nounom              ; el nom nou: la darrera lletra
        push    si
        call    copia
        pop     si
        mov     al, [di-1]
        mov     ah, 'X'
        cmp     al, 'C'
        je      .n
        mov     ah, 'C'
.n:     mov     [di-1], ah
        mov     dx, si                  ; rename
        mov     di, nounom
        push    ds
        pop     es
        mov     ah, 56h
        int     21h
        jc      .err
        mov     di, si                  ; el nom nou, a la llista
        mov     si, nounom
        call    copia
        mov     ax, [sel]
        call    dibuixa
        call    detall
        jmp     tecla
.err:   mov     si, t_noesc
        call    avis
        jmp     tecla
.bip:   mov     ax, 0E07h               ; no es un accessori: xiulet
        int     10h
        jmp     tecla

; ZF=1 si l'entrada SI es un accessori desactivat (.ACX)
desact: cmp     byte [si+E_ACC], 1
        jne     .x
        push    si
.l:     cmp     byte [si], 0
        je      .f
        inc     si
        jmp     .l
.f:     cmp     byte [si-1], 'X'
        pop     si
.x:     ret

; COMSPEC= de l'entorn -> comspec (si no n'hi ha, C:\COMMAND.COM)
comsp:  push    ds
        mov     ax, [2Ch]
        or      ax, ax
        jz      .x
        mov     ds, ax
        xor     si, si
.v:     cmp     byte [si], 0            ; final de les variables
        je      .x
        push    si
        mov     di, t_cs
        mov     cx, 8
.c:     mov     al, [si]
        cmp     al, [cs:di]
        jne     .n
        inc     si
        inc     di
        loop    .c
        mov     di, comspec             ; trobat: el copia
.k:     lodsb
        mov     [cs:di], al
        inc     di
        or      al, al
        jz      .f
        cmp     di, comspec+79
        jb      .k
        mov     byte [cs:di], 0
.f:     pop     si
        jmp     short .x
.n:     pop     si
.s:     lodsb                           ; la variable seguent
        or      al, al
        jnz     .s
        jmp     .v
.x:     pop     ds
        ret

; titol, capcalera de columnes i tecles
marc:   mov     di, 0
        mov     ah, A_TIT
        mov     si, t_tit
        call    linia
        mov     di, 1
        mov     ah, A_NOR
        mov     si, t_cap1
        call    linia
        mov     di, 24
        mov     ah, A_TIT
        mov     si, t_tecl
        call    linia
        ret

; Intro: obre l'aplicacio triada amb el GEM (COMMAND /C X:\GEM.BAT ruta)
obre:   mov     ax, [sel]
        call    entrada
        cmp     byte [si+E_ACC], 0
        je      .a
.bip:   mov     ax, 0E07h
        int     10h
        jmp     tecla
.a:     push    si
        mov     al, [buf]               ; X:\GEM.BAT existeix?
        mov     [t_gbat], al
        mov     dx, t_gbat
        mov     ax, 4300h
        int     21h
        pop     si
        jnc     .b
        mov     si, t_nogem
        call    avis
        jmp     tecla
.b:     mov     di, tail+1              ; " /C X:\GEM.BAT ruta"
        push    si
        mov     si, t_slc
        call    copia
        mov     si, t_gbat
        call    copia
        mov     byte [di], ' '
        inc     di
        pop     si
        call    copia
        mov     ax, di
        sub     ax, tail+1
        mov     [tail], al
        mov     byte [di], 13
        mov     ah, 19h                 ; unitat i carpeta, per tornar-hi
        int     21h
        mov     [sdrv], al
        mov     byte [sdir], '\'
        mov     si, sdir+1
        xor     dl, dl
        mov     ah, 47h
        int     21h
        call    neteja                  ; pantalla neta i cursor
        mov     ah, 1
        mov     cx, [curs]
        int     10h
        mov     ah, 2
        mov     bh, 0
        xor     dx, dx
        int     10h
        call    desa                    ; (0.15) GEMGO, a GEMGO.$$$; aqui
        jc      .vell                   ;   nomes en queda un tros petit
        jmp     petit
.vell:  mov     [pb_t+4], cs            ; si no s'ha pogut desar: com abans
        mov     [pb_t+8], cs
        mov     [pb_t+12], cs
        mov     [svsp], sp
        mov     dx, comspec
        mov     bx, pb_t
        push    cs
        pop     es
        mov     ax, 4B00h
        int     21h
        cli
        mov     ax, cs
        mov     ss, ax
        mov     sp, [svsp]
        sti
        mov     ds, ax
        mov     es, ax
        cld
.torna: mov     dl, [sdrv]              ; on erem
        mov     ah, 0Eh
        int     21h
        mov     dx, sdir
        mov     ah, 3Bh
        int     21h
        xor     ah, ah                  ; la nostra pantalla
        mov     al, [tmode]
        int     10h
        mov     ah, 1
        mov     cx, 2000h
        int     10h
        mov     cx, [napps]             ; les mesures, de nou
        xor     ax, ax
.r:     push    ax
        call    entrada
        mov     word [si+E_LOG], 0
        pop     ax
        inc     ax
        loop    .r
        mov     word [nlog], 0
        call    registre
        call    neteja
        call    marc
        call    llista
        call    detall
        jmp     tecla

; ---------------------------------------------------------------------
;  (0.15) Mentre corre el GEM, de GEMGO nomes en queda un tros petit:
;  el PSP i 'tros' (uns 200 bytes). Tota la resta (programa, llista,
;  seleccio) es desa a X:\GEMGO.$$$ i, en tornar del GEM, el tros fa
;  creixer el bloc on era (alta o baixa, on l'hagi posat el DOS o
;  LOADHI), el torna a llegir i continua a 'repren'.
; ---------------------------------------------------------------------
%define S(x) ((x)-tros+100h)

; desa GEMGO a X:\GEMGO.$$$ (de 100h fins a la darrera entrada).
; CF=1 si no s'ha pogut
desa:   mov     ax, [napps]
        mov     cx, ESIZE
        mul     cx
        add     ax, apps-100h
        mov     [st_len], ax
        mov     dx, tmpnom
        mov     cx, 2                   ; (0.19) ocult
        mov     ah, 3Ch
        int     21h
        jc      .x
        mov     bx, ax
        mov     dx, 100h
        mov     cx, [st_len]
        mov     ah, 40h
        int     21h
        jc      .e
        cmp     ax, cx
        jne     .e
        mov     ah, 3Eh
        int     21h
        jc      .d
        clc
.x:     ret
.e:     mov     ah, 3Eh
        int     21h
.d:     call    esbtmp
        stc
        ret

; (0.19) esborra GEMGO.$$$ (si hi es): primer li treu l'atribut d'ocult
esbtmp: mov     dx, tmpnom
        xor     cx, cx
        mov     ax, 4301h
        int     21h
        mov     ah, 41h
        int     21h
        ret

; (0.19) tmpnom = carpeta de GEMGO.COM (del nom del programa, a
; l'entorn) + GEMGO.$$$; si no se sap, X:\GEMGO.$$$ (unitat actual)
nomtmp: push    ds
        push    cs
        pop     es
        mov     di, tmpnom
        mov     bx, di
        mov     ax, [2Ch]
        or      ax, ax
        jz      .def
        mov     ds, ax
        xor     si, si
.v:     cmp     byte [si], 0            ; les variables
        je      .fv
.s:     lodsb
        or      al, al
        jnz     .s
        jmp     .v
.fv:    inc     si
        cmp     word [si], 1            ; DOS 3: hi ha el nom del programa
        jb      .def
        inc     si
        inc     si
.c:     lodsb
        stosb
        or      al, al
        jz      .e
        cmp     al, '\'
        je      .sp
        cmp     al, ':'
        jne     .k
.sp:    mov     bx, di
.k:     cmp     di, tmpnom+66
        jb      .c
.e:     cmp     bx, tmpnom
        jne     .nm
.def:   mov     ah, 19h
        int     21h
        add     al, 'A'
        mov     di, tmpnom
        stosb
        mov     ax, '\:'
        xchg    ah, al
        stosw
        mov     bx, di
.nm:    pop     ds
        mov     di, bx
        mov     si, t_tmpn
        jmp     copia

; prepara el tros i el posa a 100h (amb un trampoli al PSP, que no es
; trepitja): d'aqui ja no es torna
petit:  push    cs
        pop     es
        mov     si, comspec             ; el COMSPEC, al final del tros
        mov     di, st_com
        call    copia
        inc     di
        mov     ax, di                  ; (0.19) i el nom de GEMGO.$$$
        sub     ax, tros-100h
        mov     [st_tmpp], ax
        mov     si, tmpnom
        call    copia
        inc     di
        mov     ax, di                  ; on acaba el tros
        sub     ax, tros-100h
        mov     [st_xo], ax             ; i on es llegira GEMGO en tornar
        add     ax, 15
        mov     cl, 4
        shr     ax, cl
        mov     [st_par0], ax
        mov     [st_pb+4], cs
        mov     [st_pb+8], cs
        mov     [st_pb+12], cs
        mov     di, 6Ch                 ; un FCB buit
        mov     cx, 20
        xor     al, al
        rep     stosb
        mov     si, tail                ; la linia d'ordres, al PSP
        mov     di, 80h
        mov     cx, 128
        rep     movsb
        mov     si, st_tr               ; els dos trampolins, al PSP (5Ch,
        mov     di, 5Ch                 ;   d'anada, i 63h, de tornada)
        mov     cx, 14
        rep     movsb
        mov     si, tros
        mov     di, 100h
        mov     cx, [st_xo]
        sub     cx, 100h
        mov     ax, 5Ch
        cli                             ; la pila, dins del tros
        mov     sp, S(st_pila)
        sti
        jmp     ax

st_tr:  db      0F3h, 0A4h, 0B8h        ; rep movsb / mov ax, 100h / jmp ax
        dw      100h
        db      0FFh, 0E0h
        db      0F3h, 0A5h, 0B8h        ; rep movsw / mov ax, repren / jmp ax
        dw      repren
        db      0FFh, 0E0h

; el tros: corre a 100h (adreces amb S)
tros:   mov     bx, [S(st_par0)]        ; nomes el tros
        mov     ah, 4Ah
        int     21h
        mov     ax, 4BFFh               ; (0.18) si ens ha engegat LOADHI, te
        int     21h                     ;   la convencional tapada fins al
                                        ;   primer EXEC: un EXEC buit la destapa
        call    enllaca                 ; (0.20) DOS 5+: els UMB, enllacats
        call    tapa                    ; (0.17) el COMMAND.COM que obre
        mov     dx, S(st_com)           ;   el GEM.BAT, a la memoria alta
        mov     bx, S(st_pb)            ;   si hi cap: la convencional
        mov     ax, 4B01h               ;   tapada, 4B01h, i l'engeguem
        int     21h                     ;   nosaltres
        pushf
        call    destapa
        call    desenl
        popf
        jc      .baix
        mov     ah, 51h                 ; el PSP del COMMAND
        int     21h
        mov     es, bx
        mov     word [es:0Ah], S(.torna); quan acabi, torna aqui
        mov     [es:0Ch], cs
        mov     word [cs:2Eh], S(st_frm); el DOS hi torna amb el marc
        mov     [cs:30h], cs            ;   (un 4B01h no el posa)
        mov     ah, 50h
        int     21h
        mov     ds, bx                  ; DTA a PSP:80h
        mov     dx, 80h
        mov     ah, 1Ah
        int     21h
        cli
        mov     ss, [cs:S(st_pb)+10h]
        mov     sp, [cs:S(st_pb)+0Eh]
        sti
        push    cs                      ; el marc, a dalt de la nostra pila
        pop     es                      ;   (ja no la fem servir): AX..BP
        mov     di, S(st_frm)           ;   a zero, DS ES, IP CS FLAGS
        xor     ax, ax
        mov     cx, 7
        cld
        rep     stosw
        mov     ax, cs
        stosw
        stosw
        mov     ax, S(.torna)
        stosw
        mov     ax, cs
        stosw
        mov     ax, 0202h
        stosw
        mov     es, bx
        mov     ds, bx
        xor     ax, ax
        jmp     far [cs:S(st_pb)+12h]
.baix:  mov     dx, S(st_com)           ; no hi cap: com sempre
        mov     bx, S(st_pb)
        mov     ax, 4B00h
        int     21h
.torna: cli
        mov     ax, cs
        mov     ss, ax
        mov     sp, S(st_pila)
        sti
        mov     ds, ax
        mov     es, ax
        cld
        mov     bx, (fi_mem-start+100h+15)/16  ; tot GEMGO, al mateix lloc
        mov     ah, 4Ah
        int     21h
        jc      .err
        mov     dx, [S(st_tmpp)]
        mov     ax, 3D00h
        int     21h
        jc      .err
        mov     bx, ax
        mov     dx, [S(st_xo)]
        mov     cx, [S(st_len)]
        mov     ah, 3Fh
        int     21h
        pushf
        push    ax
        mov     ah, 3Eh
        int     21h
        pop     ax
        popf
        jc      .err
        cmp     ax, [S(st_len)]
        jne     .err
        mov     dx, [S(st_tmpp)]
        xor     cx, cx
        mov     ax, 4301h
        int     21h
        mov     ah, 41h
        int     21h
        mov     si, [S(st_xo)]
        mov     di, 100h
        mov     cx, [S(st_len)]
        inc     cx
        shr     cx, 1
        mov     ax, 63h                 ; el trampoli de tornada (PSP)
        jmp     ax
.err:   mov     dx, S(st_msg)
        mov     ah, 9
        int     21h
        mov     ax, 4C01h
        int     21h
st_pb   dw      0, 80h, 0, 6Ch, 0, 6Ch, 0
        dw      0, 0, 0, 0              ; (0.17) 4B01h: SS:SP i CS:IP
st_bl   times   9 dw 0                  ; blocs tapats
st_lnk  db      0FFh                    ; (0.20) enllac dels UMB d'abans
; (0.20) DOS 5+: enllaca els UMB (i desa com estava); desenl ho desfa
enllaca:
        mov     ah, 30h
        int     21h
        cmp     al, 5
        jb      .r
        mov     ax, 5802h
        int     21h
        jc      .r
        mov     [cs:S(st_lnk)], al
        mov     ax, 5803h
        mov     bx, 1
        int     21h
.r:     ret
desenl: cmp     byte [cs:S(st_lnk)], 0FFh
        je      .r
        push    ax
        push    bx
        mov     ax, 5803h
        mov     bl, [cs:S(st_lnk)]
        xor     bh, bh
        int     21h
        mov     byte [cs:S(st_lnk)], 0FFh
        pop     bx
        pop     ax
.r:     ret
; (0.17) tapa (a nom nostre) els blocs lliures de la convencional, i
; destapa: els torna a deixar lliures
tapa:   push    es
        mov     ah, 52h
        int     21h
        mov     ax, [es:bx-2]
        push    ax
        int     12h
        mov     cl, 6
        shl     ax, cl
        mov     dx, ax
        pop     ax
        mov     di, S(st_bl)
.l:     mov     es, ax
        cmp     ax, dx
        jae     .e
        cmp     word [es:1], 0
        jne     .n
        cmp     di, S(st_bl)+16
        jae     .n
        mov     [es:1], cs
        mov     [cs:di], ax
        inc     di
        inc     di
.n:     cmp     byte [es:0], 'Z'
        je      .e
        add     ax, [es:3]
        inc     ax
        jmp     .l
.e:     mov     word [cs:di], 0
        pop     es
        ret
destapa:
        push    ax
        push    si
        push    es
        mov     si, S(st_bl)
.l:     mov     ax, [cs:si]
        or      ax, ax
        jz      .e
        mov     es, ax
        mov     ax, cs
        cmp     [es:1], ax
        jne     .n
        mov     word [es:1], 0
.n:     inc     si
        inc     si
        jmp     .l
.e:     pop     es
        pop     si
        pop     ax
        ret
st_par0 dw      0
st_len  dw      0
st_xo   dw      0
st_msg  db      'GEMGO.$$$?', 13, 10, '$'
st_tmpp dw      0                       ; (0.19) nom de GEMGO.$$$ (darrere el COMSPEC)
        times   48 db 0
st_pila:
st_frm  equ     st_pila-24              ; (0.17) marc de tornada del COMMAND
st_com  times   160 db 0                ; COMSPEC i GEMGO.$$$ (nomes la llargada que fan)

; ja hi tornem a ser, sencers: com despres de l'EXEC d'abans
repren: cli
        mov     ax, cs
        mov     ss, ax
        mov     sp, fi_mem
        sti
        mov     ds, ax
        mov     es, ax
        cld
        jmp     obre.torna

; F1: finestra d'ajuda damunt la llista; en tancar-la, torna el que hi
; havia a sota (no es redibuixa res mes)
AJ_F    equ     2               ; fila i columna de la finestra
AJ_C    equ     5
AJ_AL   equ     19              ; alt i ample (amb la vora)
AJ_AM   equ     70
A_AJ    equ     1Fh             ; blanc sobre blau
ajuda:  push    ds                      ; guarda el que hi ha a sota
        push    es
        push    cs
        pop     es
        mov     ds, [cs:vseg]
        mov     di, ajsave
        mov     bx, AJ_F
.g:     mov     ax, 160
        mul     bx
        add     ax, AJ_C*2
        mov     si, ax
        mov     cx, AJ_AM
        rep     movsw
        inc     bx
        cmp     bx, AJ_F+AJ_AL
        jb      .g
        pop     es
        pop     ds
        push    es                      ; la finestra
        mov     es, [vseg]
        mov     si, t_aj
        mov     bx, AJ_F
.l:     mov     ax, 160
        mul     bx
        add     ax, AJ_C*2
        mov     di, ax
        mov     cx, AJ_AM
        mov     ah, A_AJ
.c:     lodsb
        stosw
        loop    .c
        inc     bx
        cmp     bx, AJ_F+AJ_AL
        jb      .l
        pop     es
        xor     ah, ah                  ; qualsevol tecla la tanca
        int     16h
        push    es                      ; torna el que hi havia
        mov     es, [vseg]
        mov     si, ajsave
        mov     bx, AJ_F
.r:     mov     ax, 160
        mul     bx
        add     ax, AJ_C*2
        mov     di, ax
        mov     cx, AJ_AM
        rep     movsw
        inc     bx
        cmp     bx, AJ_F+AJ_AL
        jb      .r
        pop     es
        jmp     tecla

t_aj:
        db      'ษออออออออออออออออออออออออออออออออออออออออออออออออออออออออออออออออออออป'
        db      'บ                           GEMGO - Ajuda                            บ'
        db      'บ                                                                    บ'
        db      'บ Tria on carrega GEMHI el programa i les dades de cada aplicaciข    บ'
        db      'บ (.APP) i de cada accessori (.ACC). Es desa al moment al fitxer.    บ'
        db      'บ                                                                    บ'
        db      'บ ', 18h, 19h, ' ReP…g AvP…g Inici Fi  tria      Intro  obre l', 27h, 'aplicaciข amb GEM บ'
        db      'บ P  programa Alta / Conv             D  dades Alta / Conv           บ'
        db      'บ T  treu la marca (el fitxer com era)  Esc  surt          F1  ajuda บ'
        db      'บ A  accessori activat / desactivat (.ACC <-> .ACX), per al GEM nou  บ'
        db      'บ Prog, Dades  KB mesurats per GEMHI (~: calculat de la capalera)   บ'
        db      'บ Bl           blocs de dades       Crx  ha demanat crixer (P, D)   บ'
        db      'บ Mentre corre el GEM (Intro), de GEMGO noms en queda mig KB.       บ'
        db      'บ Vermell: el que far… GEMHI.  Verd: sense GEMHI.                    บ'
        db      'บ Groc: arriscat (Crx P o D amb aquella part a Alta), o no es        บ'
        db      'บ pot marcar (motiu a sota de la llista).                            บ'
        db      'บ                                                                    บ'
        db      'บ                     Prem una tecla per tornar                      บ'
        db      'ศออออออออออออออออออออออออออออออออออออออออออออออออออออออออออออออออออออผ'

surt:   cmp     byte [vcanv], 0         ; torna el mode de video
        je      .n
        xor     ah, ah
        mov     al, [vmode]
        int     10h
        jmp     short .c
.n:     call    neteja
.c:     mov     ah, 1
        mov     cx, [curs]
        int     10h
        mov     ah, 2                   ; cursor a dalt
        mov     bh, 0
        xor     dx, dx
        int     10h
        mov     ax, 4C00h
        int     21h

neteja: mov     ax, 0600h
        mov     bh, A_NOR
        xor     cx, cx
        mov     dx, 184Fh
        int     10h
        ret

; ---------------------------------------------------------------------
;  Textos (CP850)
; ---------------------------------------------------------------------
t_tit   db      ' GEMGO 0.20 - On carrega GEMHI (0.25) les aplicacions i els accessoris del GEM', 0
t_cerc  db      ' Cercant les aplicacions (.APP) i els accessoris (.ACC)...', 0
t_cap1  db      ' Nom          Carpeta                         Prog Dades  Bl Crx  Tria P Tria D', 0
t_cap0  db      ' No hi ha cap aplicaciข (.APP) ni accessori (.ACC) en aquesta unitat. Prem una tecla.', 0
t_tecl  db      ' F1 ajuda  ', 18h, 19h, ' tria  Intro obre  P prog  D dades  T treu  A accessori  Esc surt', 0
t_sp    db      ' ', 0
t_sep   db      ' ', 0C4h, 0C4h, ' Accessoris (.ACC) '   ; (0.15) entre .APP i .ACC
        times 58 db 0C4h
        db      0
t_3p    db      '...', 0
t_mes   db      'ฏ', 0
t_guio  db      '  --', 0
t_q6    db      '     ?', 0
t_q4    db      '   ?', 0
t_g6    db      '    --', 0
t_g4    db      '  --', 0
t_cq    db      ' ?', 0
t_cg    db      ' --', 0
t_desk  db      'DESKTOP.APP', 0
t_mk    db      'marca:', 0
t_slc   db      ' /C ', 0
t_gbat  db      'C:\GEM.BAT', 0
t_nogem db      " No trobo GEM.BAT a l'arrel de la unitat (Intro l'obre amb GEM.BAT ruta).", 0
t_cs    db      'COMSPEC='
comspec db      'C:\COMMAND.COM', 0
tmpnom  times 80 db 0           ; (0.19) X:\carpeta\GEMGO.$$$
t_tmpn  db      'GEMGO.$$$', 0
        times 66 db 0
tail    times 128 db 0
pb_t    dw      0, tail, 0, 5Ch, 0, 6Ch, 0
svsp    dw      0
sdrv    db      0
tmode   db      3
sdir    times 68 db 0
t_racc  db      '(no es mesura)', 0
t_rno   db      '(sense mesurar)', 0
t_rm1   db      '(mesurat ', 0
t_rm2   db      ' vegades)', 0
t_rm3   db      ' vegada)', 0
t_c0    db      ' no', 0
t_c1    db      ' P', 0
t_c2    db      ' D', 0
t_c3    db      ' P+D', 0
t_crx   dw      t_c0, t_c1, t_c2, t_c3
t_no    db      '  no', 0
t_noll  db      '  error', 0
t_alta  db      '  Alta', 0
t_conv  db      '  Conv', 0
t_cap   db      '  cap', 0
t_buit  db      0
t_amb   db      ' Amb GEMHI:  programa ', 0
t_pd    db      'a dalt si hi cap (si no, a baix)', 0
t_pb    db      'a baix', 0
t_dd    db      '; dades a baix', 0
t_db    db      '; dades a dalt si hi caben', 0
t_sense db      ' Sense GEMHI: programa i dades a baix (la marca no hi fa res).', 0
t_amba  db      ' Amb GEMHI:  accessori ', 0
t_sensea db     ' Sense GEMHI: accessori a baix (la marca no hi fa res).', 0
t_nocap db      ' No es pot marcar: la capalera no t cap lloc lliure (reubicacions).', 0
t_noocup db     ' No es pot marcar: la capalera no t cap lloc lliure (1Ch ocupat).', 0
t_nomz  db      ' No es pot marcar: no s un executable (MZ).', 0
t_noll2 db      " No s'ha pogut llegir el fitxer.", 0
t_nomar db      ' Amb GEMHI: com sense marca (a dalt si hi cap; dades a baix).', 0
t_noesc db      " No s'ha pogut escriure (fitxer noms de lectura?).", 0
t_tot   db      '\*.*', 0
t_us    db      'GEMGO 0.20 - On carrega GEMHI les aplicacions i accessoris GEM', 13, 10
        db      '้s: GEMGO [unitat:]      (per defecte C:)', 13, 10, '$'

; ---------------------------------------------------------------------
;  Dades
; ---------------------------------------------------------------------
vseg    dw      0B800h
curs    dw      0607h
napps   dw      0
sel     dw      0
top     dw      0
plen    dw      0
ftim    dw      0
fdat    dw      0
werr    db      0
esacc   db      0
nb      times 8 db 0
tmark   times 8 db 0
tbuf    times 16 db 0
fpre    db      0
a22     db      A_BO
vmode   db      3
vcanv   db      0
nlog    dw      0
logpath times 80 db 0
t_lognm db      'GEMHI.LOG', 0
hlen    dw      0
fil     db      0
rend    dw      0
wlen    dw      0
woff    dw      0
hbuf    times 32 db 0
nounom  times 80 db 0           ; (0.16) A: el nom nou (.ACC / .ACX)
buf     db      'C:'
        times 80 db 0
dtas    times 43*MAXNIV db 0
apps:
hbig    equ     apps + (MAXAPP+1)*ESIZE ; capcalera llegida (HMAX bytes; +1: la linia)
logbuf  equ     hbig + HMAX             ; GEMHI.LOG (LOGMAX*24 bytes)
ajsave  equ     logbuf + LOGMAX*24      ; F1: el que hi ha sota la finestra
fi_mem  equ     ajsave + 19*70*2 + 800h  ; i la pila (finestra F1: 19x70)
