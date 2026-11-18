; =====================================================================
;  IOCONFIG.ASM - Configurador del men£ d'arrencada (IOPATCH 5.0)
;
;  Sintaxi:  IOCONFIG [unitat:]        (per defecte C:)
;
;  Llegeix la configuraci¢ del men£ de l'IO.SYS, permet canviar-la,
;  en mostra una vista prŠvia idŠntica al men£ real (F2) i, en desar
;  (F10), fa primer una c•pia de tot l'IO.SYS a IO.BAK. Nom‚s escriu
;  els 160 bytes de la configuraci¢, sense canviar la mida ni la
;  posici¢ del fitxer, i en restaura els atributs.
;
;  F9 restaura l'IO.BAK: el copia damunt de l'IO.SYS (mateixa mida,
;  mateixos cl£sters) i desa l'IO.SYS que hi havia a IO.BAK, de manera
;  que tornant a pr‚mer F9 es desf….
;
;  Compatible amb MS-DOS 2.x/3.x. Textos en catal… (p…gina de codis 437).
;
;  Construcci¢:  nasm -f bin IOCONFIG.ASM -o IOCONFIG.COM
; =====================================================================

        cpu     8086
%include "CFG.INC"
        org     0x100

MAXF    equ     20000                   ; mida m…xima de l'IO.SYS que es llegeix
FROW    equ     1                       ; primera fila dels camps
VCOL    equ     34                      ; columna dels valors
A_NORM  equ     0x07
A_HI    equ     0x70
A_HEAD  equ     0x0F
A_HELP  equ     0x03

; tipus de camp
F_TEXT  equ     0
F_INK   equ     1
F_PAPER equ     2
F_TIME  equ     3
F_DEF   equ     4
F_MOUSE equ     5
F_BOOL  equ     6
F_SPEED equ     7
F_MCOL  equ     8
F_MPOS  equ     9
F_LAY   equ     10

start:  cld
        mov     dx, m_banner
        call    print
        ; ---- l¡nia d'ordres: [unitat:] ----
        mov     si, 0x81
.par:   lodsb
        cmp     al, ' '
        je      .par
        cmp     al, 9
        je      .par
        cmp     al, 0x0D
        je      .fipar
        and     al, 0xDF
        cmp     al, 'A'
        jb      usage
        cmp     al, 'Z'
        ja      usage
        mov     [fname], al
        mov     [bname], al
        mov     [drv], al
        lodsb
        cmp     al, ':'
        jne     usage
        jmp     short .par
.fipar:
        ; ---- llegeix l'IO.SYS sencer ----
        mov     ax, 0x3D00
        mov     dx, fname
        int     0x21
        mov     dx, m_nofile
        jc      fail
        mov     bx, ax
        mov     ah, 0x3F
        mov     cx, MAXF
        mov     dx, fbuf
        int     0x21
        pushf
        push    ax
        mov     ah, 0x3E
        int     0x21
        pop     ax
        popf
        mov     dx, m_rderr
        jc      fail
        mov     [fsize], ax
        mov     dx, m_nox
        cmp     ax, MAXF
        jae     fail
        call    hasiox
        jne     fail
        call    loadcfg
        ; ---- quins sistemes hi ha al disc (per a la vista prŠvia) ----
        call    findsys
        ; ---- editor ----
        mov     ah, 0x0F
        int     0x10
        mov     [oldmode], al
        mov     ah, 3
        xor     bh, bh
        int     0x10
        mov     [oldcur], cx
        mov     ah, 1
        mov     cx, 0x2000
        int     0x10
        mov     ah, 2                           ; i fora de la pantalla
        xor     bh, bh                          ;   (la BIOS del PC1512 no
        mov     dx, 0x1900                      ;   respecta l'anterior)
        int     0x10
        mov     byte [cur], 0
        call    drawed
        cmp     byte [warnbad], 0
        je      .loop
        mov     si, m_warnbad
        call    status

.loop:  xor     ah, ah
        int     0x16
        cmp     al, 0x1B
        je      .esc
        cmp     al, 0x0D
        je      .enter
        or      al, al
        jnz     .loop
        cmp     ah, 0x48
        je      .up
        cmp     ah, 0x50
        je      .down
        cmp     ah, 0x4B
        je      .left
        cmp     ah, 0x4D
        je      .right
        cmp     ah, 0x3C                        ; F2
        je      .prev
        cmp     ah, 0x44                        ; F10
        je      .save
        cmp     ah, 0x43                        ; F9
        je      .rbak
        jmp     short .loop
.up:    mov     cl, [cur]                       ; camp anterior
        dec     byte [cur]
        jns     .mv
        mov     byte [cur], NFIELD-1
        jmp     short .mv
.down:  mov     cl, [cur]
        inc     byte [cur]
        cmp     byte [cur], NFIELD
        jb      .mv
        mov     byte [cur], 0
.mv:    call    drawfld                         ; nom‚s el camp anterior
        mov     cl, [cur]                       ;   i el nou
        call    drawfld
        jmp     .loop
.left:  mov     al, -1
        call    change
        jmp     short .chg
.right: mov     al, 1
        call    change
        jmp     short .chg
.enter: call    edittext
.chg:   mov     byte [dirty], 1
        mov     cl, [cur]                       ; nom‚s el camp que canvia
        call    drawfld
        jmp     .loop
.prev:  call    preview
        call    drawed
        jmp     .loop
.save:  call    save
        jmp     .loop
.rbak:  call    restbak
        cmp     byte [gone], 0                  ; l'IO.SYS restaurat no t‚
        je      .loop                           ;   men£ configurable: surt
        mov     word [qmsg], m_gone
        jmp     short .quit
.esc:   cmp     byte [dirty], 0
        je      .quit
        mov     si, m_askq
        call    status
.ask:   xor     ah, ah
        int     0x16
        and     al, 0xDF
        cmp     al, 'S'
        je      .quit
        cmp     al, 'N'
        jne     .ask
        mov     si, m_none
        call    status
        jmp     .loop
.quit:  mov     al, [oldmode]
        xor     ah, ah
        int     0x10
        mov     cx, [oldcur]
        mov     ah, 1
        int     0x10
        mov     ah, 2
        xor     bh, bh
        xor     dx, dx
        int     0x10
        mov     dx, [qmsg]
        or      dx, dx
        jz      .q0
        call    print
.q0:    mov     ax, 0x4C00
        int     0x21

usage:  mov     dx, m_usage
fail:   call    print
        mov     ax, 0x4C01
        int     0x21

print:  mov     ah, 9
        int     0x21
        ret

; =====================================================================
;  Taula de camps: tipus, offset a la configuraci¢, text, par…metre
; =====================================================================
%macro FIELD 4
        db      %1, %2
        dw      %3
        db      %4, 0
%endmacro
FSZ     equ     6
fields:
        FIELD   F_TEXT,  C_TITLE,  t_title, TITLESZ-1
        FIELD   F_INK,   C_ABG,    t_bgi,   0
        FIELD   F_PAPER, C_ABG,    t_bgp,   0
        FIELD   F_INK,   C_ATIT,   t_tii,   0
        FIELD   F_PAPER, C_ATIT,   t_tip,   0
        FIELD   F_INK,   C_ATXT,   t_txi,   0
        FIELD   F_PAPER, C_ATXT,   t_txp,   0
        FIELD   F_INK,   C_ASEL,   t_sei,   0
        FIELD   F_PAPER, C_ASEL,   t_sep,   0
        FIELD   F_TIME,  C_TIME,   t_time,  0
        FIELD   F_DEF,   C_DEF,    t_def,   0
        FIELD   F_MOUSE, C_MOUSE,  t_mouse, 0
        FIELD   F_SPEED, C_MSPD,   t_mspd,  0
        FIELD   F_MCOL,  C_MCOL,   t_mcol,  0
        FIELD   F_MPOS,  C_MPOS,   t_mpos,  0
        FIELD   F_BOOL,  C_SINGLE, t_single,0
        FIELD   F_LAY,   C_LAYOUT, t_lay,   0
        FIELD   F_TEXT,  C_LBL+0*LBLSZ, t_l0, LBLSZ-1
        FIELD   F_TEXT,  C_LBL+1*LBLSZ, t_l1, LBLSZ-1
        FIELD   F_TEXT,  C_LBL+2*LBLSZ, t_l2, LBLSZ-1
        FIELD   F_TEXT,  C_LBL+3*LBLSZ, t_l3, LBLSZ-1
        FIELD   F_TEXT,  C_LBL+4*LBLSZ, t_l4, LBLSZ-1
NFIELD  equ     ($-fields)/FSZ

; ---- fld: SI = entrada del camp actual (o AL = ¡ndex -> SI) ----------
fldsi:  mov     ah, FSZ
        mul     ah
        add     ax, fields
        mov     si, ax
        ret

; =====================================================================
;  Dibuix de l'editor
; =====================================================================
drawed: push    es
        mov     ax, 0x0600
        mov     bh, A_NORM
        xor     cx, cx
        mov     dx, 0x184F
        int     0x10
        mov     dx, 0x0002
        mov     bl, A_HEAD
        mov     si, m_head
        call    vputs
        mov     dx, 0x003C
        mov     bl, A_HELP
        mov     si, fname
        call    vputs
        xor     cx, cx
.f:     cmp     cl, NFIELD
        jae     .help
        call    drawfld
        inc     cx
        jmp     short .f
.help:  mov     dx, 0x1802
        mov     bl, A_HELP
        mov     si, m_help1
        call    vputs
        pop     es
        ret

; ---- drawfld: dibuixa el camp CL -------------------------------------
drawfld:
        push    cx
        mov     al, cl
        call    fldsi                           ; SI = entrada
        mov     dh, cl
        add     dh, FROW
        mov     dl, 2
        mov     bl, A_NORM
        cmp     cl, [cur]
        jne     .n
        mov     bl, A_HI
.n:     push    si
        push    bx
        ; barra de la fila
        push    dx
        mov     al, ' '
        mov     cx, 30
        call    vfill
        pop     dx
        inc     dl
        mov     si, [si+2]                      ; text del camp
        call    vputs
        pop     bx
        pop     si
        ; valor: primer s'esborra tota la zona, perquŠ no quedin restes
        mov     dl, VCOL
        push    si
        push    dx
        mov     al, ' '
        mov     cx, 80-VCOL
        mov     bl, A_NORM
        call    vfill
        pop     dx
        pop     si
        mov     bl, A_NORM
        mov     al, [si]                        ; tipus
        xor     bh, bh
        mov     bl, [si+1]                      ; offset a la configuraci¢
        mov     di, bx
        add     di, CFGBLK                      ; DI = valor
        mov     bl, A_NORM
        cmp     al, F_TEXT
        je      .text
        cmp     al, F_INK
        je      .ink
        cmp     al, F_PAPER
        je      .paper
        cmp     al, F_TIME
        je      .time
        cmp     al, F_DEF
        je      .def
        cmp     al, F_MOUSE
        je      .mouse
        cmp     al, F_SPEED
        je      .spd
        cmp     al, F_MCOL
        je      .mcol
        cmp     al, F_MPOS
        je      .mpos
        cmp     al, F_LAY
        je      .lay
        ; F_BOOL
        mov     si, v_no
        cmp     byte [di], 0
        jne     .yes
        jmp     .put
.yes:
        mov     si, v_yes
        jmp     .put
.text:  push    si
        mov     si, v_lb
        call    vputs
        pop     si
        mov     al, ' '
        mov     cl, [si+4]                      ; mida m…xima
        xor     ch, ch
        push    dx
        call    vfill
        pop     dx
        mov     si, di
        call    vputs
        mov     dl, VCOL+1
        add     dl, cl
        mov     si, v_rb
        jmp     .put
.ink:   mov     al, [di]
        and     al, 0x0F
        call    colname
        call    vputs
        jmp     short .swatch
.paper: mov     al, [di]
        mov     cl, 4
        shr     al, cl
        and     al, 0x07
        call    colname
        call    vputs
.swatch:
        mov     dl, VCOL+16
        mov     bl, [di]
        and     bl, 0x7F
        mov     si, v_sample
        jmp     .put
.time:  mov     al, [di]
        cmp     al, T_INF
        je      .tinf
        or      al, al
        jz      .t0
        cmp     al, 1
        je      .t1s
        aam
        add     ax, '00'
        cmp     ah, '0'
        jne     .t2
        mov     ah, ' '
.t2:    mov     [v_secs], ah
        mov     [v_secs+1], al
        mov     si, v_secs
        jmp     .put
.t1s:   mov     si, v_1s
        jmp     .put
.tinf:  mov     si, v_tinf
        jmp     .put
.t0:    mov     si, v_t0
        jmp     .put
.def:   mov     al, [di]
        cmp     al, NSYS
        jae     .dfirst
        call    sysname                         ; SI = nom
        jmp     .put
.dfirst:
        mov     si, v_first
        jmp     .put
.spd:   mov     al, [di]                        ; velocitat (0 = 3)
        dec     al
        cmp     al, 5
        jb      .sp1
        mov     al, 2
.sp1:   xor     ah, ah
        shl     ax, 1
        mov     si, ax
        mov     si, [v_spds+si]
        jmp     .put
.mcol:  mov     al, [di]                        ; color del cursor
        or      al, al
        jz      .mci
        cmp     al, 8
        ja      .mci
        dec     al
        call    colname
        call    vputs
        mov     bl, [di]
        dec     bl
        mov     cl, 4
        shl     bl, cl
        or      bl, 0x0F
        jmp     short .smp
.mci:   mov     si, v_inv
        call    vputs
        mov     bl, 0x70
.smp:   mov     dl, VCOL+16
        mov     si, v_sample
        jmp     .put
.mpos:  mov     al, [di]                        ; posici¢ inicial
        and     al, 3
        xor     ah, ah
        shl     ax, 1
        mov     si, ax
        mov     si, [v_mpos+si]
        jmp     .put
.lay:   mov     si, v_lay0
        cmp     byte [di], 0
        je      .put
        mov     si, v_lay1
        jmp     short .put
.mouse: mov     al, [di]
        cmp     al, 3
        jbe     .mok
        xor     al, al
.mok:   xor     ah, ah
        shl     ax, 1
        mov     si, ax
        mov     si, [v_mice+si]
.put:   call    vputs
        pop     cx
        ret

; ---- colname: AL = color 0..15 -> SI = nom --------------------------
colname:
        xor     ah, ah
        shl     ax, 1
        mov     si, ax
        mov     si, [v_cols+si]
        ret

; ---- sysname: AL = ¡ndex 0..4 -> SI = nom (configuraci¢ o NOM.SYS) ---
sysname:
        push    ax
        push    di
        mov     ah, LBLSZ
        mul     ah
        add     ax, CFGBLK+C_LBL
        mov     si, ax
        cmp     byte [si], 0
        jne     .r
        pop     di
        pop     ax
        push    ax
        push    di
        xor     ah, ah
        shl     ax, 1
        mov     si, ax
        mov     si, [sysfn+si]
.r:     pop     di
        pop     ax
        ret

; ---- status: missatge a la fila 23 -----------------------------------
status: push    si
        mov     dx, 0x1700
        mov     al, ' '
        mov     cx, 80
        mov     bl, A_NORM
        call    vfill
        pop     si
        mov     dx, 0x1702
        mov     bl, A_HEAD
        jmp     vputs

; =====================================================================
;  Canvis de valor
; =====================================================================
; change: AL = +1 / -1 sobre el camp actual
change: mov     dl, al
        mov     al, [cur]
        call    fldsi
        mov     bl, [si+1]
        xor     bh, bh
        lea     di, [bx+CFGBLK]
        mov     al, [si]
        cmp     al, F_INK
        je      .ink
        cmp     al, F_PAPER
        je      .paper
        cmp     al, F_TIME
        je      .time
        cmp     al, F_DEF
        je      .def
        cmp     al, F_MOUSE
        je      .mouse
        cmp     al, F_BOOL
        je      .bool
        cmp     al, F_LAY
        je      .bool
        cmp     al, F_SPEED
        je      .spd
        cmp     al, F_MCOL
        je      .mcol
        cmp     al, F_MPOS
        je      .mpos
        ret                                     ; text: es canvia amb Retorn
.ink:   mov     al, [di]
        mov     ah, al
        and     ah, 0xF0
        add     al, dl
        and     al, 0x0F
        or      al, ah
        mov     [di], al
        ret
.paper: mov     al, [di]
        mov     ah, al
        and     ah, 0x0F
        mov     cl, 4
        shr     al, cl
        add     al, dl
        and     al, 0x07
        shl     al, cl
        or      al, ah
        mov     [di], al
        ret
.time:  mov     al, [di]                        ; 0, 1..99, infinit, 0...
        cmp     al, T_INF
        jne     .tn
        mov     al, 100
.tn:    add     al, dl
        cmp     al, 0xFF
        jne     .t1
        mov     al, 100                         ; de 0 cap avall: infinit
.t1:    cmp     al, 101
        jb      .t2
        xor     al, al                          ; d'infinit cap amunt: 0
.t2:    cmp     al, 100
        jne     .t3
        mov     al, T_INF
.t3:    mov     [di], al
        ret
.def:   mov     al, [di]                        ; 0..4, 5 = la primera
        cmp     al, NSYS
        jbe     .d1
        mov     al, NSYS
.d1:    add     al, dl
        cmp     al, 0xFF
        jne     .d2
        mov     al, NSYS
.d2:    cmp     al, NSYS
        jbe     .d3
        xor     al, al
.d3:    cmp     al, NSYS
        jne     .d4
        mov     al, 0xFF
.d4:    mov     [di], al
        ret
.mouse: mov     al, [di]
        add     al, dl
        and     al, 3
        mov     [di], al
        ret
.bool:  xor     byte [di], 1
        ret
.spd:   mov     al, [di]                        ; 1..5 (0 = 3)
        dec     al
        cmp     al, 5
        jb      .s1
        mov     al, 2
.s1:    add     al, dl
        cmp     al, 0xFF
        jne     .s2
        mov     al, 4
.s2:    cmp     al, 5
        jb      .s3
        xor     al, al
.s3:    inc     al
        mov     [di], al
        ret
.mcol:  mov     al, [di]                        ; 0 invers, 1..8 colors
        cmp     al, 8
        jbe     .m1
        xor     al, al
.m1:    add     al, dl
        cmp     al, 0xFF
        jne     .m2
        mov     al, 8
.m2:    cmp     al, 9
        jb      .m3
        xor     al, al
.m3:    mov     [di], al
        ret
.mpos:  mov     al, [di]                        ; 0..3
        add     al, dl
        and     al, 3
        mov     [di], al
        ret

; ---- edittext: edita el camp de text actual (Retorn accepta, Esc anulúla)
edittext:
        mov     al, [cur]
        call    fldsi
        cmp     byte [si], F_TEXT
        jne     .no
        mov     bl, [si+1]
        xor     bh, bh
        lea     di, [bx+CFGBLK]
        mov     cl, [si+4]                      ; mida m…xima
        xor     ch, ch
        ; c•pia de seguretat per si s'anulúla
        push    si
        push    cx
        mov     si, di
        push    di
        mov     di, ebuf
        push    ds
        pop     es
        inc     cx
        rep     movsb
        pop     di
        pop     cx
        pop     si
        ; longitud actual
        xor     bx, bx
.len:   cmp     byte [di+bx], 0
        je      .ed
        inc     bx
        jmp     short .len
        push    cx
        push    bx
        push    di
        mov     si, m_edit
        call    status
        pop     di
        pop     bx
        pop     cx
.ed:    push    cx
        push    bx
        push    di
        call    drawed1
        pop     di
        pop     bx
        pop     cx
        xor     ah, ah
        int     0x16
        cmp     al, 0x0D
        je      .ok
        cmp     al, 0x1B
        je      .cancel
        cmp     al, 8
        je      .bs
        cmp     al, ' '
        jb      .ed
        cmp     bx, cx
        jae     .ed
        mov     [di+bx], al
        inc     bx
        mov     byte [di+bx], 0
        jmp     short .ed
.bs:    or      bx, bx
        jz      .ed
        dec     bx
        mov     byte [di+bx], 0
        jmp     short .ed
.cancel:
        mov     si, ebuf
        push    ds
        pop     es
        inc     cx
        rep     movsb
.ok:    mov     si, m_none
        call    status
.no:    ret

; redibuixa nom‚s el camp actual
drawed1:
        mov     cl, [cur]
        jmp     drawfld

; =====================================================================
;  Vista prŠvia (fa servir el mateix codi de dibuix que el men£ real)
; =====================================================================
preview:
        ; opcions: els sistemes que hi ha al disc (o tots, si no n'hi ha cap)
        xor     bx, bx
        xor     cx, cx
        mov     byte [m_sel], 0
.p:     cmp     byte [sysok+bx], 0
        jne     .use
        cmp     byte [nsys], 0
        jne     .nx
.use:   mov     al, bl
        cmp     al, [CFGBLK+C_DEF]
        jne     .nd
        mov     [m_sel], cl
.nd:    call    sysname
        mov     di, cx
        shl     di, 1
        mov     [m_lbl+di], si
        inc     cx
.nx:    inc     bx
        cmp     bx, NSYS
        jb      .p
        mov     [m_n], cl
        mov     al, [CFGBLK+C_TIME]
        or      al, al
        jnz     .ts
        mov     al, T_INF
.ts:    mov     [m_secs], al
        call    drawall
        ; nota a la part de baix
        mov     dx, 0x1800
        mov     bl, [CFGBLK+C_ABG]
        mov     si, m_prevk
        call    vputs
        xor     ah, ah
        int     0x16
        ret

; ---- findsys: marca quins fitxers de sistema hi ha a l'arrel ----------
findsys:
        xor     bx, bx
.f:     mov     si, bx
        shl     si, 1
        mov     si, [sysfn+si]
        mov     di, pbuf
        mov     al, [drv]
        mov     [di], al
        mov     word [di+1], ':\'
        add     di, 3
.c:     lodsb
        stosb
        or      al, al
        jnz     .c
        push    bx
        mov     ah, 0x4E
        mov     cx, 0x27
        mov     dx, pbuf
        int     0x21
        pop     bx
        mov     al, 0
        jc      .no
        mov     al, 1
        inc     byte [nsys]
.no:    mov     [sysok+bx], al
        inc     bx
        cmp     bx, NSYS
        jb      .f
        ret

; =====================================================================
;  Desar: IO.BAK + escriptura de la configuraci¢
; =====================================================================
save:   ; suma de verificaci¢
        mov     byte [CFGBLK+C_CHK], 0
        mov     si, CFGBLK
        mov     cx, CFGSZ
        xor     ah, ah
.s:     lodsb
        add     ah, al
        loop    .s
        neg     ah
        mov     [CFGBLK+C_CHK], ah
        ; IO.BAK amb el contingut actual de l'IO.SYS
        mov     ah, 0x3C
        xor     cx, cx
        mov     dx, bname
        int     0x21
        mov     si, m_bakerr
        jc      .err
        mov     bx, ax
        mov     ah, 0x40
        mov     cx, [fsize]
        mov     dx, fbuf
        int     0x21
        pushf
        push    ax
        mov     ah, 0x3E
        int     0x21
        pop     ax
        popf
        jc      .err
        cmp     ax, [fsize]
        jne     .err
        ; treu els atributs de l'IO.SYS
        mov     ax, 0x4300
        mov     dx, fname
        int     0x21
        mov     si, m_wrerr
        jc      .err
        mov     [attr], cx
        mov     ax, 0x4301
        xor     cx, cx
        int     0x21
        jc      .err
        mov     ax, 0x3D02
        int     0x21
        jc      .rest
        mov     bx, ax
        mov     ax, 0x4200
        xor     cx, cx
        mov     dx, CFGOFF
        int     0x21
        jc      .cls
        mov     ah, 0x40
        mov     cx, CFGSZ
        mov     dx, CFGBLK
        int     0x21
        jc      .cls
        cmp     ax, CFGSZ
        jne     .cls
        mov     ah, 0x3E
        int     0x21
        jc      .rest
        call    restattr
        ; la c•pia en mem•ria passa a ser l'actual (per al pr•xim IO.BAK)
        mov     si, CFGBLK
        mov     di, fbuf+CFGOFF
        push    ds
        pop     es
        mov     cx, CFGSZ
        rep     movsb
        mov     byte [dirty], 0
        mov     si, m_saved
        jmp     status
.cls:   mov     ah, 0x3E
        int     0x21
.rest:  call    restattr
        mov     si, m_wrerr
.err:   jmp     status

; ---- hasiox: ZF=1 si l'IO.SYS de fbuf t‚ el men£ de l'IOPATCH 4 ------
hasiox: cmp     word [fsize], CFGOFF+CFGSZ
        jb      .no
        cmp     word [fbuf+XOFF], 'IO'
        jne     .r
        cmp     word [fbuf+XOFF+2], 'X4'
        jne     .r
        cmp     word [fbuf+XOFF+6], CFGOFF
.r:     ret
.no:    or      sp, sp                          ; ZF=0
        ret

; ---- loadcfg: configuraci¢ de fbuf (o la de per defecte) a CFGBLK ------
loadcfg:
        mov     byte [warnbad], 0
        mov     si, fbuf+CFGOFF
        call    cfgok
        jz      .ok
        mov     byte [warnbad], 1
        mov     si, DEFCFG
.ok:    mov     di, CFGBLK
        push    ds
        pop     es
        mov     cx, CFGSZ
        rep     movsb
        ret

; =====================================================================
;  restbak: restaura l'IO.BAK damunt de l'IO.SYS (F9)
;  L'IO.BAK ha de tenir la mateixa mida que l'IO.SYS i comen‡ar igual
;  (carregador de DR). L'IO.SYS que hi havia passa a ser l'IO.BAK.
; =====================================================================
restbak:
        mov     ax, 0x3D00
        mov     dx, bname
        int     0x21
        mov     si, m_nobak
        jc      .err
        mov     bx, ax
        mov     ah, 0x3F
        mov     cx, MAXF
        mov     dx, bbuf
        int     0x21
        pushf
        push    ax
        mov     ah, 0x3E
        int     0x21
        pop     ax
        popf
        mov     si, m_nobak
        jc      .err
        mov     si, m_badbak
        cmp     ax, [fsize]                     ; mateixa mida
        jne     .err
        push    ds
        pop     es
        mov     si, fbuf                        ; mateix comen‡ament
        mov     di, bbuf
        mov     cx, 0x18
        repe    cmpsb
        mov     si, m_badbak
        jne     .err
        mov     si, fbuf                        ; ja s¢n iguals?
        mov     di, bbuf
        mov     cx, [fsize]
        repe    cmpsb
        mov     si, m_samebak
        je      .err
        ; confirmaci¢
        mov     si, m_askbak
        cmp     byte [dirty], 0
        je      .ask
        mov     si, m_askbak2
.ask:   call    status
.k:     xor     ah, ah
        int     0x16
        and     al, 0xDF
        cmp     al, 'S'
        je      .go
        cmp     al, 'N'
        jne     .k
        mov     si, m_none
.err:   jmp     status
.go:    ; treu els atributs i escriu l'IO.BAK damunt de l'IO.SYS
        mov     ax, 0x4300
        mov     dx, fname
        int     0x21
        mov     si, m_rberr
        jc      .err
        mov     [attr], cx
        mov     ax, 0x4301
        xor     cx, cx
        int     0x21
        jc      .err
        mov     ax, 0x3D02
        int     0x21
        jc      .rest
        mov     bx, ax
        mov     ah, 0x40                        ; s'obre al principi
        mov     cx, [fsize]
        mov     dx, bbuf
        int     0x21
        jc      .cls
        cmp     ax, [fsize]
        jne     .cls
        mov     ah, 0x3E
        int     0x21
        jc      .rest
        call    restattr
        ; l'IO.SYS anterior passa a ser l'IO.BAK
        mov     byte [bakok], 1
        mov     ah, 0x3C
        xor     cx, cx
        mov     dx, bname
        int     0x21
        jc      .nobk
        mov     bx, ax
        mov     ah, 0x40
        mov     cx, [fsize]
        mov     dx, fbuf
        int     0x21
        pushf
        push    ax
        mov     ah, 0x3E
        int     0x21
        pop     ax
        popf
        jc      .nobk
        cmp     ax, [fsize]
        je      .copy
.nobk:  mov     byte [bakok], 0
.copy:  mov     si, bbuf                        ; el restaurat ‚s l'actual
        mov     di, fbuf
        push    ds
        pop     es
        mov     cx, [fsize]
        rep     movsb
        mov     byte [dirty], 0
        call    hasiox
        je      .cfg
        mov     byte [gone], 1                  ; sense men£ configurable
        ret
.cfg:   call    loadcfg
        call    drawed
        mov     si, m_warnbad
        cmp     byte [warnbad], 0
        jne     .msg
        mov     si, m_restok
        cmp     byte [bakok], 0
        jne     .msg
        mov     si, m_restnb
.msg:   jmp     status
.cls:   mov     ah, 0x3E
        int     0x21
.rest:  call    restattr
        mov     si, m_rberr
        jmp     status

restattr:
        mov     ax, 0x4301
        mov     cx, [attr]
        mov     dx, fname
        int     0x21
        ret

; ---- cfgok: ZF=1 si DS:SI t‚ signatura i suma correctes ---------------
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

; =====================================================================
;  Escriptura directa a la pantalla (80 columnes)
; =====================================================================
; vaddr: DH fila, DL columna -> ES:DI
vaddr:  push    ax
        push    dx
        mov     ax, 0xB800
        mov     es, ax
        mov     al, 80
        mul     dh
        pop     dx
        push    dx
        xor     dh, dh
        add     ax, dx
        shl     ax, 1
        mov     di, ax
        pop     dx
        pop     ax
        ret
; vputs: DS:SI ASCIIZ a DH,DL amb atribut BL; avan‡a DL
vputs:  push    ax
        push    di
        push    es
        call    vaddr
        mov     ah, bl
.l:     lodsb
        or      al, al
        jz      .f
        stosw
        inc     dl
        jmp     short .l
.f:     pop     es
        pop     di
        pop     ax
        ret
; vfill: CX car…cters AL amb atribut BL a DH,DL
vfill:  push    cx
        push    di
        push    es
        call    vaddr
        mov     ah, bl
        rep     stosw
        pop     es
        pop     di
        pop     cx
        ret

%include "DRAW.INC"

; =====================================================================
;  Dades
; =====================================================================
fname   db      'C:\IO.SYS', 0
bname   db      'C:\IO.BAK', 0
drv     db      'C'
fsize   dw      0
attr    dw      0
cur     db      0
dirty   db      0
warnbad db      0
gone    db      0
bakok   db      0
qmsg    dw      0
oldmode db      3
oldcur  dw      0x0607
nsys    db      0
sysok   times NSYS db 0
pbuf    times 20 db 0
ebuf    times TITLESZ+1 db 0

; variables que fa servir DRAW.INC
m_lbl   times NSYS dw 0
m_n     db      0
m_sel   db      0
m_secs  db      0
d_cols  dw      80
d_left  db      0
d_top   db      0
d_row0  db      0
d_w     db      0

DEFCFG: CFGDEFAULT
CFGBLK  times CFGSZ db 0

sysfn   dw      s0, s1, s2, s3, s4
s0      db      'DOSPLUS.SYS', 0
s1      db      'DOS.SYS', 0
s2      db      'CCPM.SYS', 0
s3      db      'CPCDOS.SYS', 0
s4      db      'CDOS286.SYS', 0

m_banner db     'IOCONFIG - configuraci', 0xA2, ' del men', 0xA3, ' d', 39, 'arrencada (IOPATCH 5.0)', 13, 10, '$'
m_usage db      'Sintaxi: IOCONFIG [unitat:]', 13, 10, '$'
m_nofile db     'No trobo \IO.SYS en aquesta unitat.', 13, 10, '$'
m_rderr db      'Error en llegir l', 39, 'IO.SYS.', 13, 10, '$'
m_nox   db      'Aquest IO.SYS no t', 0x82, ' el men', 0xA3, ' de l', 39, 'IOPATCH 4. Executa primer IOPATCH.', 13, 10, '$'

m_head  db      'IOCONFIG - Configuraci', 0xA2, ' del men', 0xA3, ' d', 39, 'arrencada', 0
m_help1 db      0x18, 0x19, ' camp  ', 0x1B, 0x1A, ' valor  Retorn: editar  F2: vista  F9: IO.BAK  F10: desa  Esc: surt', 0
m_nobak db      'No hi ha cap IO.BAK (o no el puc llegir).', 0
m_badbak db     'L', 39, 'IO.BAK no sembla un IO.SYS d', 39, 'aquest disc (mida o inici diferents).', 0
m_samebak db    'L', 39, 'IO.BAK ', 0x82, 's igual que l', 39, 'IO.SYS: no cal restaurar res.', 0
m_askbak db     'Restaurar l', 39, 'IO.BAK damunt de l', 39, 'IO.SYS? L', 39, 'actual passar', 0x85, ' a IO.BAK. (S/N)', 0
m_askbak2 db    'Restaurar l', 39, 'IO.BAK? Es perdran els canvis sense desar. (S/N)', 0
m_rberr db      'ERROR en escriure l', 39, 'IO.SYS. Comprova-ho abans de reiniciar!', 0
m_restok db     'IO.SYS restaurat. L', 39, 'anterior ara ', 0x82, 's a IO.BAK (amb F9 es desf', 0x85, ').', 0
m_restnb db     'IO.SYS restaurat. Atenci', 0xA2, ': no he pogut desar l', 39, 'anterior a IO.BAK.', 0
m_gone  db      'IO.SYS restaurat des de l', 39, 'IO.BAK. Aquesta versi', 0xA2, ' no t', 0x82, ' el men', 0xA3, ' configurable;', 13, 10
        db      'per tornar-lo a tenir, executa IOPATCH.', 13, 10, '$'
m_edit  db      'Escriu el text. Retorn: acceptar   Esc: anul', 0xFA, 'lar   ', 0x1B, 0xC4, ': esborrar', 0
m_saved db      'Configuraci', 0xA2, ' desada. La c', 0xA2, 'pia anterior de l', 39, 'IO.SYS ', 0x82, 's a IO.BAK.', 0
m_bakerr db     'ERROR: no he pogut crear IO.BAK. No he desat res.', 0
m_wrerr db      'ERROR en escriure l', 39, 'IO.SYS. Restaura-ho amb IO.BAK.', 0
m_none  db      0
m_askq  db      'Hi ha canvis sense desar. Vols sortir igualment? (S/N)', 0
m_warnbad db    'Atenci', 0xA2, ': la configuraci', 0xA2, ' estava malmesa. Es mostra la de per defecte.', 0
m_prevk db      ' Vista pr', 0x8A, 'via. Prem una tecla per tornar. ', 0

t_title db      'T', 0xA1, 'tol del men', 0xA3, 0
t_bgi   db      'Fons: color del text', 0
t_bgp   db      'Fons: color del fons', 0
t_tii   db      'T', 0xA1, 'tol: color del text', 0
t_tip   db      'T', 0xA1, 'tol: color del fons', 0
t_txi   db      'Opcions: color del text', 0
t_txp   db      'Opcions: color del fons', 0
t_sei   db      'Seleccionada: color del text', 0
t_sep   db      'Seleccionada: color del fons', 0
t_time  db      'Temps d', 39, 'espera', 0
t_def   db      'Opci', 0xA2, ' per defecte', 0
t_mouse db      'Ratol', 0xA1, 0
t_single db     'Men', 0xA3, ' amb un sol sistema', 0
t_lay   db      'Disposici', 0xA2, ' del men', 0xA3, 0
v_lay0  db      'Centrada', 0
v_lay1  db      'Cl', 0x85, 'ssica (a dalt a l', 39, 'esquerra)', 0
t_mspd  db      'Ratol', 0xA1, ': velocitat', 0
t_mcol  db      'Ratol', 0xA1, ': color del cursor', 0
t_mpos  db      'Ratol', 0xA1, ': posici', 0xA2, ' inicial', 0
t_l0    db      'Nom de DOSPLUS.SYS', 0
t_l1    db      'Nom de DOS.SYS', 0
t_l2    db      'Nom de CCPM.SYS', 0
t_l3    db      'Nom de CPCDOS.SYS', 0
t_l4    db      'Nom de CDOS286.SYS', 0

v_lb    db      '[', 0
v_rb    db      ']', 0
v_yes   db      'S', 0xA1, 0
v_no    db      'No', 0
v_sample db     ' Mostra ', 0
v_secs  db      '00 segons', 0
v_1s    db      ' 1 segon', 0
v_tinf  db      'Infinit (espera una tecla)', 0
v_t0    db      '0: sense men', 0xA3, ' (Maj per veure', 39, 'l)', 0
v_first db      'La primera que hi hagi', 0
v_inv   db      'Invers', 0
v_spds  dw      vs1, vs2, vs3, vs4, vs5
vs1     db      '1 (lenta)', 0
vs2     db      '2', 0
vs3     db      '3 (normal)', 0
vs4     db      '4', 0
vs5     db      '5 (r', 0x85, 'pida)', 0
v_mpos  dw      vp0, vp1, vp2, vp3
vp0     db      'Sobre l', 39, 'opci', 0xA2, ' per defecte', 0
vp1     db      'Centre de la pantalla', 0
vp2     db      'A dalt a l', 39, 'esquerra', 0
vp3     db      'A baix a la dreta', 0
v_mice  dw      vm0, vm1, vm2, vm3
vm0     db      'Cap', 0
vm1     db      'Amstrad PC1512', 0
vm2     db      'Microsoft (s', 0x8A, 'rie COM1)', 0
vm3     db      'Microsoft (s', 0x8A, 'rie COM2)', 0
v_cols  dw      c0, c1, c2, c3, c4, c5, c6, c7, c8, c9, c10, c11, c12, c13, c14, c15
c0      db      'Negre', 0
c1      db      'Blau', 0
c2      db      'Verd', 0
c3      db      'Cian', 0
c4      db      'Vermell', 0
c5      db      'Magenta', 0
c6      db      'Marr', 0xA2, 0
c7      db      'Gris clar', 0
c8      db      'Gris fosc', 0
c9      db      'Blau clar', 0
c10     db      'Verd clar', 0
c11     db      'Cian clar', 0
c12     db      'Vermell clar', 0
c13     db      'Magenta clar', 0
c14     db      'Groc', 0
c15     db      'Blanc', 0

bbuf    equ     fbuf+MAXF               ; contingut de l'IO.BAK (F9)
fbuf:                                   ; contingut de l'IO.SYS (fins a MAXF)
