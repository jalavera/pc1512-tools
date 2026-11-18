; =====================================================================
;  IOX.ASM - Extensi¢ del men£ d'arrencada (IOPATCH 4)
;
;  Es desa dins l'IO.SYS a partir de l'offset A00h (zona que el
;  carregador de DR no fa servir). El carregador la llegeix del disc a
;  0070:0000 (tot l'inici del fitxer) i la crida amb CALL FAR 0070:entry.
;
;  Entrada: DS = segment del carregador (taula de sistemes, comptador).
;  Sortida: AH = ¡ndex del sistema triat (0..COUNT-1). La resta de
;           registres es conserven.
;
;  Construcci¢:  nasm -f bin IOX.ASM -o IOX.BIN
; =====================================================================

        cpu     8086
%include "CFG.INC"
        org     XOFF

L_TBL   equ     0x06B3                  ; taula de 5 punters a noms (0 = no hi ‚s)
L_COUNT equ     0x06F1                  ; nombre de sistemes trobats


; ---- cap‡alera (A00h) -------------------------------------------------
hdr:    db      'IOX4'                  ; signatura
        dw      entry                   ; punt d'entrada
        dw      CFGBLK                  ; configuraci¢
        dw      XSIZE                   ; mida de l'extensi¢
        times   16-($-hdr) db 0

; ---- configuraci¢ (A10h) - l'edita IOCONFIG ---------------------------
CFGBLK: CFGDEFAULT

; ---- configuraci¢ per defecte, per si la de dalt est… malmesa ---------
DEFCFG: CFGDEFAULT

; =====================================================================
entry:
        push    bx
        push    cx
        push    dx
        push    si
        push    di
        push    bp
        push    ds
        push    es
        mov     [cs:ldr], ds
        push    cs
        pop     ds
        cld

        ; --- comprova la configuraci¢ (signatura i suma) ---
        mov     si, CFGBLK
        call    cfgok
        jz      .cfgbo
        mov     si, DEFCFG                      ; malmesa: la per defecte
        mov     di, CFGBLK
        push    ds
        pop     es
        mov     cx, CFGSZ
        rep     movsb
.cfgbo:
        ; --- recull els sistemes trobats ---
        mov     es, [ldr]
        xor     bx, bx                          ; ¡ndex a la taula (0..4)
        xor     cx, cx                          ; opcions trobades
        mov     byte [m_sel], 0
.rec:   mov     si, bx
        shl     si, 1
        mov     si, [es:L_TBL+si]               ; SI = nom (al carregador)
        or      si, si
        jz      .seg
        cmp     bl, [CFGBLK+C_DEF]              ; ‚s l'opci¢ per defecte?
        jne     .nodef
        mov     [m_sel], cl
.nodef: mov     al, LBLSZ                       ; nom de la configuraci¢
        mul     bl
        add     ax, CFGBLK+C_LBL
        mov     di, ax
        cmp     byte [di], 0
        jne     .lok
        mov     al, 13                          ; buit: construeix NOM.SYS
        mul     cl
        add     ax, lblbuf
        mov     di, ax
        push    di
        push    cx
        mov     cx, 8
.nm:    mov     al, [es:si]
        inc     si
        cmp     al, ' '
        je      .nmf
        mov     [di], al
        inc     di
        loop    .nm
.nmf:   pop     cx
        mov     word [di], '.S'
        mov     word [di+2], 'YS'
        mov     byte [di+4], 0
        pop     di
.lok:   mov     si, cx
        shl     si, 1
        mov     [m_lbl+si], di
        inc     cx
.seg:   inc     bx
        cmp     bx, NSYS
        jb      .rec
        mov     [m_n], cl
        or      cl, cl
        jnz     .some
        xor     ah, ah                          ; (no hauria de passar)
        jmp     .ret

.some:  ; --- cal mostrar el men£? ---
        xor     ax, ax
        mov     es, ax
        test    byte [es:0x0417], 0x03          ; Maj premuda: men£ sempre
        jnz     .show
        cmp     byte [m_n], 1
        jne     .tchk
        cmp     byte [CFGBLK+C_SINGLE], 0
        je      .done                           ; un sol sistema, sense men£
.tchk:  cmp     byte [CFGBLK+C_TIME], 0
        je      .done                           ; temps 0: directe

.show:  mov     al, [CFGBLK+C_TIME]
        or      al, al
        jnz     .tset
        mov     al, T_INF                       ; temps 0 + Maj: sense compte
.tset:  cmp     al, 99
        jbe     .tst
        mov     al, T_INF
.tst:   mov     [m_secs], al
        mov     ah, 3                           ; desa la forma i la posici¢
        xor     bh, bh                          ;   del cursor de text
        int     0x10
        mov     [ocur], cx
        mov     [opos], dx
        mov     ah, 1                           ; l'amaga (la BIOS del PC1512
        mov     cx, 0x2000                      ;   no ho respecta: per aix•
        int     0x10                            ;   tamb‚ el treu de la
        mov     ah, 2                           ;   pantalla, a la fila 25)
        xor     bh, bh
        mov     dx, 0x1900
        int     0x10
        call    drawall                         ; l'£nica vegada que es
        call    minit                           ;   dibuixa tota la pantalla
        call    ticks
        mov     [t0], ax

.loop:  mov     ah, 1
        int     0x16
        jz      .nokey
        xor     ah, ah
        int     0x16
        call    stopcnt
        cmp     al, 0x0D
        je      .done
        cmp     ah, 0x7E                        ; bot¢ esquerre del ratol¡
        je      .mclick                         ;   de l'Amstrad (via teclat)
        cmp     al, 0xE0
        je      .ext
        or      al, al
        jnz     .loop
.ext:   mov     dl, [m_sel]
        mov     dh, [m_n]
        cmp     ah, 0x48
        je      .up
        cmp     ah, 0x50
        je      .down
        cmp     ah, 0x47
        je      .home
        cmp     ah, 0x4F
        je      .end
        sub     ah, 0x3B                        ; F1..F5
        jb      .loop
        cmp     ah, dh
        jae     .loop
        mov     dl, ah
        call    setsel
        jmp     .done
.up:    dec     dl
        jns     .mv
        mov     dl, dh
        dec     dl
        jmp     short .mv
.down:  inc     dl
        cmp     dl, dh
        jb      .mv
        xor     dl, dl
        jmp     short .mv
.home:  xor     dl, dl
        jmp     short .mv
.end:   mov     dl, dh
        dec     dl
.mv:    call    setsel
        jmp     .loop

.nokey: call    mpoll                           ; ratol¡
        or      al, al
        jz      .cnt
        call    stopcnt
        cmp     al, 2
        jne     .cnt                            ; nom‚s s'ha mogut
.mclick:
        call    ptrhit                          ; clic: sobre una opci¢?
        jnc     .onit
        mov     byte [lastit], 0xFF             ; fora: no compta per al
        jmp     .loop                           ;   doble clic
.onit:  mov     dl, al
        call    setsel                          ; un clic: nom‚s selecciona
        call    ticks
        mov     bx, ax
        sub     ax, [lastclk]
        cmp     ax, DCLK
        ja      .first
        cmp     dl, [lastit]
        jne     .first
        jmp     .done                           ; doble clic: arrenca
.first: mov     [lastclk], bx
        mov     [lastit], dl
        jmp     .loop

.cnt:   cmp     byte [m_secs], T_INF            ; compte enrere
        je      .loop
        call    ticks
        sub     ax, [t0]
        cmp     ax, 18
        jb      .loop
        add     word [t0], 18
        dec     byte [m_secs]
        jz      .done
        call    ptrhide
        call    d_count                         ; nom‚s el n£mero
        call    ptrshow
        jmp     .loop

.done:  call    ptrhide
        call    mdone                           ; torna a deixar l'INT 6
        mov     ah, 1                           ; restaura el cursor de text
        mov     cx, [ocur]
        int     0x10
        mov     ah, 2
        xor     bh, bh
        mov     dx, [opos]
        int     0x10
        mov     ah, [m_sel]
.ret:   pop     es
        pop     ds
        pop     bp
        pop     di
        pop     si
        pop     dx
        pop     cx
        pop     bx
        retf

; ---- setsel: selecciona l'opci¢ DL i repinta nom‚s les dues files -----
setsel: mov     cl, [m_sel]
        cmp     cl, dl
        je      .r
        call    ptrhide
        mov     [m_sel], dl
        xor     ch, ch
        call    d_item                          ; l'anterior
        mov     cl, dl
        call    d_item                          ; la nova
        call    ptrshow
.r:     ret

; ---- stopcnt: atura el compte enrere i n'esborra la l¡nia --------------
stopcnt:
        cmp     byte [m_secs], T_INF
        je      .r
        mov     byte [m_secs], T_INF
        push    ax
        call    ptrhide
        call    d_count
        call    ptrshow
        pop     ax
.r:     ret

; ---- AX = comptador de tics de la BIOS ---------------------------------
ticks:  push    es
        xor     ax, ax
        mov     es, ax
        mov     ax, [es:0x046C]
        pop     es
        ret

; ---- cfgok: ZF=1 si el bloc DS:SI t‚ signatura i suma correctes -------
cfgok:  cmp     word [si+C_MAGIC], 'CF'
        jne     .r
        push    cx
        push    si
        mov     cx, CFGSZ
        xor     ah, ah
.s:     lodsb
        add     ah, al
        loop    .s
        pop     si
        pop     cx
        or      ah, ah
.r:     ret

DCLK    equ     9                       ; temps m…xim del doble clic (~0,5 s)

; =====================================================================
;  Ratol¡ (nom‚s durant el men£; no queda resident)
;  Un cursor rectangular (la casella amb els colors intercanviats) es
;  mou per tota la pantalla. Un clic sobre una opci¢ la selecciona i un
;  doble clic l'arrenca.
; =====================================================================

; minit: prepara el ratol¡ configurat i mostra el cursor
minit:  mov     al, [CFGBLK+C_MOUSE]
        mov     [mtype], al
        cmp     al, 1
        je      .ams
        cmp     al, 2
        je      .com1
        cmp     al, 3
        je      .com2
        mov     byte [mtype], 0
        ret
.ams:   in      al, 0x78                        ; buida els comptadors
        in      al, 0x7A
        ; els botons arriben per l'INT 6 (la BIOS la crida en rebre els
        ; codis 7Dh/7Eh del teclat): mentre dura el men£ hi posem la
        ; nostra rutina, que posa 7E00h/7D00h al buffer del teclat
        push    es
        xor     ax, ax
        mov     es, ax
        cli
        mov     ax, [es:6*4]
        mov     [old6], ax
        mov     ax, [es:6*4+2]
        mov     [old6+2], ax
        mov     word [es:6*4], int6
        mov     [es:6*4+2], cs
        sti
        pop     es
        mov     byte [hooked], 1
        jmp     .pos
.com1:  mov     word [mport], 0x3F8
        jmp     short .ser
.com2:  mov     word [mport], 0x2F8
.ser:   mov     dx, [mport]
        add     dx, 5
        in      al, dx                          ; LSR
        cmp     al, 0xFF
        jne     .uart
        mov     byte [mtype], 0                 ; no hi ha port sŠrie
        ret
.uart:  mov     dx, [mport]
        add     dx, 3
        mov     al, 0x80                        ; DLAB
        out     dx, al
        sub     dx, 3
        mov     al, 96                          ; 1200 bauds
        out     dx, al
        inc     dx
        xor     al, al
        out     dx, al
        add     dx, 2
        mov     al, 0x02                        ; 7 bits, sense paritat, 1 stop
        out     dx, al
        sub     dx, 2
        xor     al, al                          ; sense interrupcions
        out     dx, al
        add     dx, 3                           ; MCR
        mov     al, 0x01                        ; DTR, RTS desactivat
        out     dx, al
        call    ticks
        mov     cx, ax
.w:     call    ticks
        sub     ax, cx
        cmp     ax, 3
        jb      .w
        mov     al, 0x03                        ; DTR+RTS: el ratol¡ s'engega
        out     dx, al
        mov     byte [mphase], 0
        mov     byte [mbtn], 0
.pos:   ; velocitat: moviment per columna (per fila, el doble)
        mov     bl, [CFGBLK+C_MSPD]
        dec     bl
        cmp     bl, 5
        jb      .sp
        mov     bl, 2                           ; 0 o fora de l¡mits: 3
.sp:    xor     bh, bh
        mov     al, [spdtab+bx]
        xor     ah, ah
        mov     [mxs], ax
        shl     ax, 1
        mov     [mys], ax
        ; posici¢ inicial
        mov     al, [CFGBLK+C_MPOS]
        cmp     al, 1
        je      .pc
        cmp     al, 2
        je      .ptl
        cmp     al, 3
        je      .pbr
        mov     al, [d_w]                       ; sobre l'opci¢ per defecte
        shr     al, 1
        add     al, [d_left]
        mov     [px], al
        mov     al, [d_row0]
        add     al, [m_sel]
        mov     [py], al
        jmp     ptrshow
.pc:    mov     al, [d_cols]                    ; centre de la pantalla
        shr     al, 1
        mov     [px], al
        mov     byte [py], 12
        jmp     ptrshow
.ptl:   mov     word [px], 0                    ; a dalt a l'esquerra
        jmp     ptrshow
.pbr:   mov     al, [d_cols]                    ; a baix a la dreta
        dec     al
        mov     [px], al
        mov     byte [py], 24
        jmp     ptrshow

; int6: rutina dels botons del ratol¡ de l'Amstrad (mentre dura el men£)
;       Entrada AL: bit 0 = bot¢ (0 esquerre), bit 7 = 1 si es deixa anar
;       Sortida: CF=1 i AX = codi per al buffer del teclat; CF=0 res
int6:   test    al, 0x80
        jnz     .brk
        test    al, 1
        mov     ax, 0x7E00                      ; bot¢ esquerre
        jz      .tok
        mov     ax, 0x7D00                      ; bot¢ dret
.tok:   push    bp
        mov     bp, sp
        or      byte [bp+6], 1                  ; CF=1 en tornar
        pop     bp
        iret
.brk:   push    bp
        mov     bp, sp
        and     byte [bp+6], 0xFE               ; CF=0 en tornar
        pop     bp
        iret

; mdone: torna a deixar l'INT 6 com era
mdone:  cmp     byte [hooked], 0
        je      .r
        push    ax
        push    es
        xor     ax, ax
        mov     es, ax
        cli
        mov     ax, [old6]
        mov     [es:6*4], ax
        mov     ax, [old6+2]
        mov     [es:6*4+2], ax
        sti
        pop     es
        pop     ax
        mov     byte [hooked], 0
.r:     ret

; mpoll: AL = 0 res, 1 s'ha mogut, 2 clic del bot¢ esquerre
mpoll:  mov     byte [mev], 0
        mov     al, [mtype]
        cmp     al, 1
        je      .ams
        cmp     al, 2
        jae     .ser
        xor     al, al
        ret
.ams:   in      al, 0x78                        ; X (positiu = dreta)
        cbw
        add     [mdx], ax
        in      al, 0x7A                        ; Y (positiu = amunt)
        cbw
        sub     [mdy], ax
        jmp     .move
.ser:   mov     cx, 16                          ; com a m…xim 16 bytes
.rd:    mov     dx, [mport]
        add     dx, 5
        in      al, dx
        test    al, 1
        jz      .move
        sub     dx, 5
        in      al, dx
        test    al, 0x40                        ; primer byte del paquet
        jz      .nb
        mov     [mpk], al
        mov     byte [mphase], 1
        jmp     short .nx
.nb:    cmp     byte [mphase], 1
        jne     .p2
        mov     byte [mphase], 2
        and     al, 0x3F                        ; X5..X0
        mov     ah, [mpk]
        and     ah, 0x03                        ; X7..X6
        ror     ah, 1
        ror     ah, 1
        or      al, ah
        cbw
        add     [mdx], ax
        jmp     short .nx
.p2:    cmp     byte [mphase], 2
        jne     .nx
        mov     byte [mphase], 0
        and     al, 0x3F                        ; Y5..Y0
        mov     ah, [mpk]
        and     ah, 0x0C                        ; Y7..Y6
        shl     ah, 1
        shl     ah, 1
        shl     ah, 1
        shl     ah, 1
        or      al, ah
        cbw                                     ; positiu = avall
        add     [mdy], ax
        mov     al, [mpk]
        and     al, 0x20                        ; bot¢ esquerre
        mov     ah, [mbtn]
        mov     [mbtn], al
        or      al, al
        jz      .nx
        or      ah, ah
        jnz     .nx
        mov     byte [mev], 2                   ; clic nou
.nx:    loop    .rd
.move:  ; converteix el moviment acumulat en caselles
        mov     bl, [px]
        mov     bh, [py]
        mov     cx, [mxs]
.mx1:   cmp     [mdx], cx
        jl      .mx2
        sub     [mdx], cx
        inc     bl
        jmp     short .mx1
.mx2:   neg     cx
.mx3:   cmp     [mdx], cx
        jg      .my
        sub     [mdx], cx
        dec     bl
        jmp     short .mx3
.my:    mov     cx, [mys]
.my1:   cmp     [mdy], cx
        jl      .my2
        sub     [mdy], cx
        inc     bh
        jmp     short .my1
.my2:   neg     cx
.my3:   cmp     [mdy], cx
        jg      .clamp
        sub     [mdy], cx
        dec     bh
        jmp     short .my3
.clamp: cmp     bl, 0x80                        ; l¡mits de la pantalla
        jb      .c1
        xor     bl, bl
.c1:    mov     al, [d_cols]
        dec     al
        cmp     bl, al
        jbe     .c2
        mov     bl, al
.c2:    cmp     bh, 0x80
        jb      .c3
        xor     bh, bh
.c3:    cmp     bh, 24
        jbe     .c4
        mov     bh, 24
.c4:    cmp     bl, [px]
        jne     .moved
        cmp     bh, [py]
        je      .ev
.moved: call    ptrhide
        mov     [px], bl
        mov     [py], bh
        call    ptrshow
        cmp     byte [mev], 0
        jne     .ev
        mov     byte [mev], 1
.ev:    mov     al, [mev]
        ret

; ptrhit: CF=0 i AL = opci¢ si el cursor ‚s sobre una opci¢
ptrhit: cmp     byte [mtype], 0
        je      .no
        mov     al, [px]
        sub     al, [d_left]
        jb      .no
        cmp     al, [d_w]
        jae     .no
        mov     al, [py]
        sub     al, [d_row0]
        jb      .no
        cmp     al, [m_n]
        jae     .no
        clc
        ret
.no:    stc
        ret

; ptrshow / ptrhide: dibuixa o esborra el cursor del ratol¡
ptrshow:
        cmp     byte [mtype], 0
        je      .r
        cmp     byte [pon], 0
        jne     .r
        push    ax
        push    cx
        push    dx
        push    di
        push    es
        mov     dh, [py]
        mov     dl, [px]
        call    d_addr
        mov     al, [es:di+1]
        mov     [psave], al
        mov     ah, al
        mov     cl, [CFGBLK+C_MCOL]
        or      cl, cl
        jz      .inv
        cmp     cl, 8
        ja      .inv
        dec     cl                              ; color de fons triat,
        shl     cl, 1                           ;   conservant el color
        shl     cl, 1                           ;   del car…cter
        shl     cl, 1
        shl     cl, 1
        and     al, 0x0F
        or      al, cl
        jmp     short .s
.inv:   mov     cl, 4
        rol     al, cl                          ; intercanvia text i fons
        and     al, 0x7F
        cmp     al, ah
        jne     .s
        mov     al, 0x70
.s:     mov     [es:di+1], al
        mov     byte [pon], 1
        pop     es
        pop     di
        pop     dx
        pop     cx
        pop     ax
.r:     ret
ptrhide:
        cmp     byte [pon], 0
        je      .r
        push    ax
        push    dx
        push    di
        push    es
        mov     dh, [py]
        mov     dl, [px]
        call    d_addr
        mov     al, [psave]
        mov     [es:di+1], al
        mov     byte [pon], 0
        pop     es
        pop     di
        pop     dx
        pop     ax
.r:     ret

%include "DRAW.INC"

; ---- dades --------------------------------------------------------------
ldr     dw      0
t0      dw      0
m_lbl   times NSYS dw 0
m_n     db      0
m_sel   db      0
m_secs  db      0
d_cols  dw      80
d_left  db      0
d_top   db      0
d_row0  db      0
d_w     db      0
mtype   db      0
mport   dw      0
mphase  db      0
mpk     db      0
mbtn    db      0
mev     db      0
mdx     dw      0
mdy     dw      0
px      db      0
py      db      0
mxs     dw      8
mys     dw      16
spdtab  db      16, 12, 8, 6, 4                 ; velocitat 1 (lenta) .. 5
hooked  db      0
lastclk dw      0
lastit  db      0xFF                            ; opci¢ de l'£ltim clic
old6    dw      0, 0
pon     db      0
psave   db      0
ocur    dw      0
opos    dw      0
lblbuf  times NSYS*13 db 0
xend:
%if (xend-hdr) > XSIZE
  %error "l'IOX no cap a XSIZE"
%endif
        times   XSIZE-(xend-hdr) db 0
