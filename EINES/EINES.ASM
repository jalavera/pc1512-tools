; =====================================================================
;  EINES.ASM - Accessori d'escriptori GEM amb dues entrades al menu:
;              "Caracters" (CHARMAP 0.7) i "Shell de DOS" (DOSSHELL 0.2);
;              0.4: tambe "Calculadora" i "Rellotge" (per no carregar
;              CALCLOCK.ACC, 28 KB)
;              (GEM 2.0, Amstrad PC1512).  Versio 0.11
;
;  Muntatge:   nasm -f bin EINES.ASM -o EINES.ACC
;  Us:         copiar EINES.ACC a \GEMBOOT (en lloc de CHARMAP.ACC i
;              DOSSHELL.ACC) i tornar a entrar al GEM. El GEM 2.0 nomes
;              carrega 3 fitxers d'accessori: aixi aquests dos n'ocupen un.
;
;  Shell de DOS: passa a mode text (v_enter_cur), executa COMMAND.COM
;  (COMSPEC) i, amb EXIT, torna al mode grafic (v_exit_cur), torna a
;  posar la barra de menus (guardada amb vro_cpyfm en un bloc de DOS) i
;  fa redibuixar el GEM (form_dial FMD_FINISH).
;
;  Caracters: la finestra mostra els
;  caracters 32-255 en la font del sistema.
;    clic         tria un caracter (se'n veu el codi)
;    doble clic   el tria i l'afegeix a la cadena (en realitat: un clic
;                 sobre el caracter ja triat l'afegeix; no depen de la
;                 velocitat del doble clic del GEM ni de l'emulador)
;    teclat       amb la finestra al davant: una tecla l'afegeix a la
;                 cadena; Retroces esborra, Retorn envia, Esc tanca
;    Afegeix      afegeix el caracter triat a la cadena
;    Esborra      treu l'ultim caracter de la cadena
;    Envia        tanca la finestra i escriu la cadena a l'aplicacio
;                 activa, amb appl_tplay del GEM (reproduccio de tecles)
;  Nomes es redibuixa el que canvia (caselles, linia de codi, cadena).
;
;  - Executable MZ d'un sol segment (capcalera inclosa en aquest fitxer),
;    CS=DS=ES=SS, pila propia dins la imatge.
;  - Crides GEM per INT EFh:  AES -> CX=200, ES:BX   VDI -> CX=473h, DS:DX
; =====================================================================

        cpu     8086

; ---------------------------------------------------------------------
;  Capcalera MZ (512 bytes)
; ---------------------------------------------------------------------
section .hdr start=0
        db      'MZ'
        dw      (512+MIDA) % 512        ; bytes de l'ultima pagina
        dw      (512+MIDA+511) / 512    ; pagines de 512 bytes
        dw      0                       ; reubicacions
        dw      32                      ; capcalera en paragrafs
        dw      0                       ; memoria minima extra
        dw      20h                     ; memoria maxima: 512 bytes
        dw      0                       ; SS
        dw      pila_fi                 ; SP
        dw      0                       ; suma
        dw      inici                   ; IP
        dw      0                       ; CS
        dw      1Ch                     ; taula de reubicacions
        dw      0                       ; overlay
        times   512-($-$$) db 0

; ---------------------------------------------------------------------
section .text vstart=0 follows=.hdr

%macro AES 5                    ; opcode, n_int_in, n_int_out, n_addr_in, n_addr_out
        mov     word [control+0], %1
        mov     word [control+2], %2
        mov     word [control+4], %3
        mov     word [control+6], %4
        mov     word [control+8], %5
        call    crida_aes
%endmacro

%macro VDI 3                    ; opcode, n_ptsin, n_intin
        mov     word [contrl+0], %1
        mov     word [contrl+2], %2
        mov     word [contrl+6], %3
        mov     word [contrl+10], 0
        mov     ax, [vhandle]
        mov     [contrl+12], ax
        call    crida_vdi
%endmacro

%macro VDIS 4                   ; opcode, n_ptsin, n_intin, subfuncio
        mov     word [contrl+0], %1
        mov     word [contrl+2], %2
        mov     word [contrl+6], %3
        mov     word [contrl+10], %4
        mov     ax, [vhandle]
        mov     [contrl+12], ax
        call    crida_vdi
%endmacro

MINPARAS     equ 1800           ; ~28 KB: COMMAND.COM 3.x + entorn + marge
MBMAX        equ 9000           ; maxim de bytes per a la barra de menus

AC_OPEN      equ 40
AC_CLOSE     equ 41
WM_REDRAW    equ 20
WM_TOPPED    equ 21
WM_CLOSED    equ 22
WM_MOVED     equ 28
WF_NAME      equ 2
WF_WORKXYWH  equ 4
WF_CURRXYWH  equ 5
WF_TOP       equ 10
WF_FIRSTXYWH equ 11
WF_NEXTXYWH  equ 12
TIPUS_FIN    equ 000Bh          ; NAME | CLOSER | MOVER
FILES        equ 14             ; 224 caracters: 32..255
COLS         equ 16
SMAX         equ 22             ; llargada maxima de la cadena

; =====================================================================
inici:
        cli
        mov     ax, cs
        mov     ds, ax
        mov     es, ax
        mov     ss, ax
        mov     sp, pila_fi
        sti
        cld
        call    init_punters

        AES     10,0,1,0,0              ; appl_init
        cmp     ax, -1
        jne     .gem_ok
        mov     ax, 4C00h
        int     21h
.gem_ok:
        mov     [ap_id], ax

        AES     77,0,5,0,0              ; graf_handle
        mov     [vhandle], ax
        mov     ax, [int_out+2]
        mov     [car_w], ax
        mov     ax, [int_out+4]
        mov     [car_h], ax
        mov     [alt_fila], ax          ; (0.4) tambe per a la calculadora

        mov     di, intin               ; v_opnvwk
        mov     cx, 10
        mov     ax, 1
        rep     stosw
        mov     word [intin+20], 2
        VDI     100,0,11
        mov     ax, [contrl+12]
        mov     [vhandle], ax

        mov     ax, [ap_id]             ; menu_register(ap_id, nom)
        mov     [int_in], ax
        mov     word [addr_in], nom_menu
        mov     [addr_in+2], ds
        AES     35,1,1,1,0
        mov     [menu_id], ax

        mov     word [intin], 1         ; vq_extnd: plans de color
        VDI     102,0,1
        mov     ax, [intout+8]
        or      ax, ax
        jnz     .pl
        inc     ax
.pl:    mov     [plans], ax

        mov     ax, [ap_id]             ; segona entrada: Shell de DOS
        mov     [int_in], ax
        mov     word [addr_in], nom_shell
        mov     [addr_in+2], ds
        AES     35,1,1,1,0
        mov     [menu_id2], ax

        mov     si, nom_calc            ; (0.4) Calculadora i Rellotge
        call    registra
        mov     [menu_id3], ax
        mov     si, nom_rell
        call    registra
        mov     [menu_id4], ax

        mov     ah, 19h                 ; (0.6) l'alarma desada: X:\GEMBOOT\EINES.CFG
        int     21h
        add     al, 'A'
        mov     [t_cfg], al
        mov     dx, t_cfg
        mov     ax, 3D00h
        int     21h
        jc      .nocfg
        mov     bx, ax
        mov     dx, cfgbuf
        mov     cx, 15
        mov     ah, 3Fh
        int     21h
        cmp     ax, 15                  ; (0.7) i les posicions
        jne     .np
        mov     si, cfgbuf+3
        mov     di, wpos
        mov     cx, 6
        rep     movsw
.np:
        mov     ah, 3Eh
        int     21h
        cmp     byte [cfgbuf], 23       ; nomes si te sentit
        ja      .nocfg
        cmp     byte [cfgbuf+1], 59
        ja      .nocfg
        mov     si, cfgbuf
        mov     di, alh
        movsw
        movsb
.nocfg:

; ---------------------------------------------------------------------
;  Bucle d'esdeveniments: un accessori no acaba mai
; ---------------------------------------------------------------------
bucle:
        mov     ax, 10h                 ; MU_MESAG
        mov     bx, [wtab]              ; alguna finestra oberta?
        and     bx, [wtab+2]
        and     bx, [wtab+4]
        js      .f1
        or      ax, 03h                 ; MU_BUTTON i MU_KEYBD (oberta)
.f1:    cmp     word [wtab+4], 0        ; (0.4) el rellotge: MU_TIMER
        jge     .ft
        cmp     byte [alon], 0          ; (0.5) o l'alarma
        je      .f2
.ft:    or      ax, 20h
.f2:    mov     di, int_in
        stosw                           ; flags
        mov     ax, 1
        stosw                           ; 1 clic (el doble, el fem nosaltres)
        mov     ax, 1
        stosw                           ; boto esquerre
        stosw                           ; premut
        xor     ax, ax
        mov     cx, 10
        rep     stosw                   ; sense rectangles de ratoli
        mov     ax, 250
        stosw                           ; temporitzador: 250 ms (rellotge)
        xor     ax, ax
        stosw
        mov     word [addr_in], msgbuf
        mov     [addr_in+2], ds
        AES     25,16,7,1,0             ; evnt_multi
        mov     [quins], ax
        mov     ax, [int_out+2]
        mov     [mx], ax
        mov     ax, [int_out+4]
        mov     [my], ax
        mov     ax, [int_out+12]
        mov     [clics], ax
        mov     ax, [int_out+10]
        mov     [tecla_k], ax
        test    word [quins], 10h
        jz      .e1
        call    missatge
.e1:    test    word [quins], 02h
        jz      .e2
        call    clic
.e2:    test    word [quins], 01h
        jz      .e3
        call    tecla
.e3:    test    word [quins], 20h
        jz      .e4
        call    tic
.e4:    jmp     bucle

; ---------------------------------------------------------------------
;  Missatges del GEM
; ---------------------------------------------------------------------
missatge:
        mov     ax, [msgbuf]
        cmp     ax, AC_OPEN
        jne     .n1
        mov     bx, [msgbuf+8]          ; quina entrada del menu?
        cmp     bx, [menu_id2]
        jne     .car
        cmp     word [menu_id2], -1
        je      .car
        jmp     shell
.car:   mov     dx, obre                ; (0.4) quina finestra
        xor     cx, cx
        cmp     bx, [menu_id3]
        jne     .c1
        mov     dx, obre_k
        mov     cl, 2
.c1:    cmp     bx, [menu_id4]
        jne     .c2
        mov     dx, obre_r
        mov     cl, 4
.c2:    mov     bx, cx
        call    selw
        call    dx
        jmp     desw
.n1:    cmp     ax, AC_CLOSE
        jne     .n2
        mov     ax, -1                  ; el GEM ja ha tancat les finestres
        mov     [whandle], ax
        mov     [wtab], ax
        mov     [wtab+2], ax
        mov     [wtab+4], ax
        ret
.n2:    push    ax                      ; la resta: una de les nostres
        mov     ax, [msgbuf+6]
        call    troba
        pop     ax
        jc      m_ret
        push    ax
        call    selw
        pop     ax
        call    msgw
        jmp     desw
msgw:   cmp     ax, WM_REDRAW
        jne     .n3
        call    redibuixa
        ret
.n3:    cmp     ax, WM_TOPPED
        jne     .n4
        call    al_davant
        ret
.n4:    cmp     ax, WM_MOVED
        jne     .n5
        call    posa_wh
        mov     word [int_in+2], WF_CURRXYWH
        mov     si, msgbuf+8
        mov     di, int_in+4
        mov     cx, 4
        rep     movsw
        AES     105,6,1,0,0             ; wind_set(WF_CURRXYWH)
        mov     bx, [cur]               ; (0.7) la posicio, desada
        shl     bx, 1
        mov     ax, [msgbuf+8]
        mov     [wpos+bx], ax
        mov     ax, [msgbuf+10]
        mov     [wpos+bx+2], ax
        jmp     desa_cfg
.n5:    cmp     ax, WM_CLOSED
        jne     m_ret
tanca:  call    posa_wh
        AES     102,1,1,0,0             ; wind_close
        call    posa_wh
        AES     103,1,1,0,0             ; wind_delete
        mov     word [whandle], -1
m_ret:  ret

; ---------------------------------------------------------------------
;  AC_OPEN: obre la finestra (o la porta al davant si ja hi es)
; ---------------------------------------------------------------------
obre:
        cmp     word [whandle], 0
        jl      .nova
        call    al_davant
        ret
.nova:
        mov     ax, COLS*2+2
        mul     word [car_w]
        mov     [ww], ax
        mov     ax, [car_h]             ; files juntes: la pantalla nomes
        mov     [alt_fila], ax          ; te 200 linies
        mov     bx, FILES
        mul     bx
        add     ax, 4
        mov     [y_info], ax            ; linia del codi
        add     ax, [alt_fila]
        mov     [y_cad], ax             ; linia de la cadena
        add     ax, [alt_fila]
        add     ax, 2
        mov     [y_bot], ax             ; botons
        add     ax, [alt_fila]
        add     ax, 5
        mov     si, titol
        mov     bx, 40
; (0.4) obre la finestra [cur]: AX = alt i [ww] = ample de l'area de
; treball, SI = titol, BX = x (des de l'esquerra de l'escriptori)
obrew:  mov     [int_in+10], ax
        mov     [wtit], si
        mov     [wpar], bx
        cmp     bx, -1
        jne     .p0
        xor     bx, bx
.p0:    push    bx
        mov     word [int_in], 0        ; area util de l'escriptori
        mov     word [int_in+2], WF_WORKXYWH
        AES     104,2,5,0,0
        push    si
        mov     si, int_out+2
        mov     di, escr
        mov     cx, 4
        rep     movsw
        pop     si
        pop     bx
        mov     word [int_in], 0        ; WC_BORDER: mida exterior
        mov     word [int_in+2], TIPUS_FIN
        add     bx, [escr]
        mov     [int_in+4], bx
        mov     ax, [escr+2]
        add     ax, 24
        mov     [int_in+6], ax
        mov     ax, [ww]
        mov     [int_in+8], ax
        AES     108,6,5,0,0
        mov     si, int_out+2
        mov     di, frect
        mov     cx, 4
        rep     movsw
        mov     bx, [cur]               ; (0.7) on era (EINES.CFG)
        shl     bx, 1
        mov     ax, [wpos+bx]
        or      ax, ax
        jz      .def
        mov     [frect], ax
        mov     ax, [wpos+bx+2]
        mov     [frect+2], ax
        jmp     short .cl
.def:   mov     ax, [escr+2]            ; enganxada a dalt de l'escriptori
        inc     ax
        mov     [frect+2], ax
        cmp     word [wpar], -1         ; o al mig
        jne     .cl
        mov     ax, [escr+4]
        sub     ax, [frect+4]
        sar     ax, 1
        add     ax, [escr]
        mov     [frect], ax
        mov     ax, [escr+6]
        sub     ax, [frect+6]
        sar     ax, 1
        add     ax, [escr+2]
        mov     [frect+2], ax
.cl:    mov     ax, [escr]              ; dins de la pantalla
        add     ax, [escr+4]
        sub     ax, [frect+4]
        cmp     [frect], ax
        jle     .c1
        mov     [frect], ax
.c1:    mov     ax, [escr]
        cmp     [frect], ax
        jge     .c2
        mov     [frect], ax
.c2:    mov     ax, [escr+2]
        add     ax, [escr+6]
        sub     ax, [frect+6]
        cmp     [frect+2], ax
        jle     .c3
        mov     [frect+2], ax
.c3:    mov     ax, [escr+2]
        cmp     [frect+2], ax
        jge     .c4
        mov     [frect+2], ax
.c4:

        mov     word [int_in], TIPUS_FIN ; wind_create
        push    si
        mov     si, escr
        mov     di, int_in+2
        mov     cx, 4
        rep     movsw
        pop     si
        AES     100,5,1,0,0
        or      ax, ax
        jns     .ok
        ret                             ; no queden finestres
.ok:    mov     [whandle], ax

        call    posa_wh                 ; wind_set(WF_NAME)
        mov     word [int_in+2], WF_NAME
        mov     ax, [wtit]
        mov     [int_in+4], ax
        mov     [int_in+6], ds
        mov     word [int_in+8], 0
        mov     word [int_in+10], 0
        AES     105,6,1,0,0

        call    posa_wh                 ; wind_open
        mov     si, frect
        mov     di, int_in+2
        mov     cx, 4
        rep     movsw
        AES     101,5,1,0,0
        ret

al_davant:
        call    posa_wh
        mov     word [int_in+2], WF_TOP
        mov     word [int_in+4], 0
        mov     word [int_in+6], 0
        mov     word [int_in+8], 0
        mov     word [int_in+10], 0
        AES     105,6,1,0,0
        ret

; =====================================================================
;  Redibuixat (llista de rectangles visibles de la finestra)
; =====================================================================
redibuixa:
        mov     word [int_in], 1
        AES     107,1,1,0,0             ; wind_update(BEG_UPDATE)
        mov     word [int_in], 256
        mov     word [addr_in], 0
        mov     word [addr_in+2], 0
        AES     78,1,1,1,0              ; graf_mouse(M_OFF)

        call    posa_wh
        mov     word [int_in+2], WF_WORKXYWH
        AES     104,2,5,0,0
        mov     si, int_out+2
        mov     di, treb
        mov     cx, 4
        rep     movsw

        mov     ax, WF_FIRSTXYWH
.seguent:
        mov     [int_in+2], ax
        call    posa_wh
        AES     104,2,5,0,0
        cmp     word [int_out+6], 0
        je      .fi
        cmp     word [int_out+8], 0
        je      .fi
        call    retalla_i_dibuixa
        mov     ax, WF_NEXTXYWH
        jmp     .seguent
.fi:
        mov     word [int_in], 257
        mov     word [addr_in], 0
        mov     word [addr_in+2], 0
        AES     78,1,1,1,0              ; graf_mouse(M_ON)
        mov     word [int_in], 0
        AES     107,1,1,0,0             ; wind_update(END_UPDATE)
        ret

; Interseccio del rectangle visible (int_out[1..4]) amb el del missatge
retalla_i_dibuixa:
        mov     ax, [int_out+2]         ; x1 = max
        mov     bx, [msgbuf+8]
        cmp     ax, bx
        jge     .a1
        mov     ax, bx
.a1:    mov     [clip], ax
        mov     ax, [int_out+4]         ; y1 = max
        mov     bx, [msgbuf+10]
        cmp     ax, bx
        jge     .a2
        mov     ax, bx
.a2:    mov     [clip+2], ax
        mov     ax, [int_out+2]         ; x2 = min
        add     ax, [int_out+6]
        mov     bx, [msgbuf+8]
        add     bx, [msgbuf+12]
        cmp     ax, bx
        jle     .a3
        mov     ax, bx
.a3:    mov     [clip+4], ax
        mov     ax, [int_out+4]         ; y2 = min
        add     ax, [int_out+8]
        mov     bx, [msgbuf+10]
        add     bx, [msgbuf+14]
        cmp     ax, bx
        jle     .a4
        mov     ax, bx
.a4:    mov     [clip+6], ax
        mov     ax, [clip+4]
        cmp     ax, [clip]
        jle     .res
        mov     ax, [clip+6]
        cmp     ax, [clip+2]
        jle     .res
        dec     word [clip+4]
        dec     word [clip+6]
        mov     bx, [cur]               ; (0.4) la de la finestra
        call    [tdib+bx]
.res:   ret

; Dibuixa, dins el rectangle de clip, nomes les parts que el toquen
dibuixa:
        mov     byte [fons], 6          ; (0.8) fons groc, com la resta
        call    prep
        mov     word [intin], 2         ; i el text transparent
        VDI     32,0,1
        jmp     dib_c
; (0.4) comu: retalla al clip i hi pinta el fons blanc
prep:   mov     word [intin], 1         ; vs_clip(on)
        mov     si, clip
        mov     di, ptsin
        mov     cx, 4
        rep     movsw
        VDI     129,2,1
        mov     word [intin], 1         ; vswr_mode(substitucio)
        VDI     32,0,1
        mov     word [intin], 1         ; vsf_interior(solid)
        VDI     23,0,1
        mov     al, [fons]              ; vsf_color (0.7: el fons de cada una)
        xor     ah, ah
        mov     [intin], ax
        VDI     25,0,1
        mov     ax, [treb]              ; vr_recfl: el fons (retallat)
        mov     [ptsin], ax
        add     ax, [treb+4]
        dec     ax
        mov     [ptsin+4], ax
        mov     ax, [treb+2]
        mov     [ptsin+2], ax
        add     ax, [treb+6]
        dec     ax
        mov     [ptsin+6], ax
        VDI     114,2,0
        ret

dib_c:  mov     byte [fila], 0
.fila:  mov     al, [fila]
        xor     ah, ah
        mul     word [alt_fila]
        mov     bx, [alt_fila]
        call    toca                    ; aquesta fila toca el clip?
        jc      .seg
        mov     al, [fila]              ; primer caracter de la fila
        mov     cl, 4
        shl     al, cl
        add     al, 32
        mov     di, intin               ; " c c c ..." (32 caracters)
        mov     cx, COLS
.car:   mov     word [di], ' '
        xor     ah, ah
        mov     [di+2], ax
        add     di, 4
        inc     al
        loop    .car
        mov     ax, [treb]
        mov     [ptsin], ax
        mov     ax, [ytop]
        add     ax, [car_h]             ; linia base de la fila
        sub     ax, 2
        mov     [ptsin+2], ax
        VDI     8,1,COLS*2              ; v_gtext
        mov     al, [sel]               ; el caracter triat es d'aquesta fila?
        sub     al, 32
        mov     ah, al
        mov     cl, 4
        shr     ah, cl
        cmp     ah, [fila]
        jne     .seg
        and     al, 15                  ; el marca en invers
        xor     ah, ah
        shl     ax, 1
        mul     word [car_w]
        mov     bx, [car_w]
        shr     bx, 1
        add     ax, bx
        add     ax, [treb]
        mov     [ptsin], ax
        add     ax, [car_w]
        add     ax, [car_w]
        dec     ax
        mov     [ptsin+4], ax
        mov     ax, [ytop]
        mov     [ptsin+2], ax
        add     ax, [alt_fila]
        dec     ax
        mov     [ptsin+6], ax
        mov     word [intin], 3         ; vswr_mode(XOR)
        VDI     32,0,1
        mov     word [intin], 1         ; vsf_color(negre)
        VDI     25,0,1
        VDI     114,2,0
        mov     word [intin], 2         ; (0.8) transparent
        VDI     32,0,1
        mov     word [intin], 0
        VDI     25,0,1
.seg:   inc     byte [fila]
        cmp     byte [fila], FILES
        jae     .info
        jmp     .fila

.info:  mov     ax, [y_info]            ; linia del codi
        mov     bx, [alt_fila]
        call    toca
        jc      .cad
        mov     di, linia
        mov     si, t_car
        call    copia
        mov     al, [sel]
        stosb
        mov     si, t_dec
        call    copia
        mov     al, [sel]
        call    dec3
        mov     si, t_hex
        call    copia
        mov     al, [sel]
        call    hex2
        mov     al, 'h'
        stosb
        call    text_linia

.cad:   mov     ax, [y_cad]             ; linia de la cadena
        mov     bx, [alt_fila]
        call    toca
        jc      .bot
        mov     di, linia
        mov     si, t_cad
        call    copia
        mov     si, sbuf
        mov     cl, [slen]
        xor     ch, ch
        rep     movsb
        mov     al, '_'
        stosb
        call    text_linia

.bot:   mov     ax, [y_bot]             ; botons
        mov     bx, [alt_fila]
        add     bx, 3
        call    toca
        jc      fiw
        mov     si, botons
.b:     lodsb                           ; columna
        cmp     al, 0FFh
        je      fiw
        xor     ah, ah
        mul     word [car_w]
        add     ax, [treb]
        mov     [bx1], ax
        lodsb                           ; llargada
        mov     [blen], al
        xor     ah, ah
        mul     word [car_w]
        add     ax, [bx1]
        dec     ax
        mov     [bx2], ax
        lodsw                           ; text
        push    si
        push    ax
        call    altbot                  ; (0.8) boto blau, text blanc
        mov     ax, 4
        call    omple
        call    caixa
        pop     si
        mov     cl, [blen]
        xor     ch, ch
        mov     ax, [bx1]
        dec     ax                      ;   (un punt a l'esquerra)
        mov     bl, 0
        call    textx
        mov     word [intin], 2         ;   (textx torna a substitucio)
        VDI     32,0,1
        pop     si
        jmp     .b

; (0.4) SI = text, CX = caracters, AX = x: v_gtext a la linia [ytop]
gtext:  mov     [ptsin], ax
        mov     [contrl+6], cx
        mov     di, intin
.bt:    lodsb
        xor     ah, ah
        stosw
        loop    .bt
        mov     ax, [ytop]              ; (0.8) linia base: un punt mes
        add     ax, [car_h]             ;   amunt (centrat al boto)
        mov     [ptsin+2], ax
        mov     word [contrl+0], 8      ; v_gtext
        mov     word [contrl+2], 1
        mov     ax, [vhandle]
        mov     [contrl+12], ax
        jmp     crida_vdi

; (0.4) marc d'un boto: [bx1]..[bx2], de [ytop] a [ytop]+alt_fila+2
caixa:  mov     ax, [ytop]              ; marc: v_pline de 5 punts
        add     ax, [alt_fila]
        add     ax, 2
        mov     [by2], ax
        mov     di, ptsin
        mov     ax, [bx1]
        stosw
        mov     ax, [ytop]
        stosw                           ; x1,y1
        mov     ax, [bx2]
        stosw
        mov     ax, [ytop]
        stosw                           ; x2,y1
        mov     ax, [bx2]
        stosw
        mov     ax, [by2]
        stosw                           ; x2,y2
        mov     ax, [bx1]
        stosw
        mov     ax, [by2]
        stosw                           ; x1,y2
        mov     ax, [bx1]
        stosw
        mov     ax, [ytop]
        stosw                           ; x1,y1
        VDI     6,5,0
        ret

.fi:
fiw:    mov     word [intin], 0         ; vs_clip(off)
        VDI     129,2,1
        ret

; ax = desplacament vertical dins l'area de treball, bx = alcada
; -> [ytop] = y absoluta; CF=1 si la franja no toca el rectangle de clip
toca:   add     ax, [treb+2]
        mov     [ytop], ax
        cmp     ax, [clip+6]
        jg      .no
        add     ax, bx
        dec     ax
        cmp     ax, [clip+2]
        jl      .no
        clc
        ret
.no:    stc
        ret

; escriu [linia..di) a la columna 1, linia base [ytop]+car_h
text_linia:
        mov     cx, di
        sub     cx, linia
        mov     [contrl+6], cx
        mov     si, linia
        mov     di, intin
.l:     lodsb
        xor     ah, ah
        stosw
        loop    .l
        mov     ax, [treb]
        add     ax, [car_w]
        mov     [ptsin], ax
        mov     ax, [ytop]
        add     ax, [car_h]
        sub     ax, 2
        mov     [ptsin+2], ax
        mov     word [contrl+0], 8      ; v_gtext
        mov     word [contrl+2], 1
        mov     ax, [vhandle]
        mov     [contrl+12], ax
        jmp     crida_vdi

copia:  lodsb                           ; ASCIIZ si -> di (sense el 0)
        or      al, al
        jz      .r
        stosb
        jmp     copia
.r:     ret

dec3:   xor     ah, ah                  ; al -> 3 xifres a di
        mov     bl, 100
        div     bl
        add     al, '0'
        stosb
        mov     al, ah
        xor     ah, ah
        mov     bl, 10
        div     bl
        add     ax, '00'
        stosw
        ret

hex2:   mov     ah, al                  ; al -> 2 xifres hex a di
        mov     cl, 4
        shr     al, cl
        call    .d
        mov     al, ah
        and     al, 0Fh
.d:     add     al, '0'
        cmp     al, '9'
        jbe     .s
        add     al, 7
.s:     stosb
        ret

; =====================================================================
;  Ratoli
; =====================================================================
clic:   mov     ax, [mx]                ; el clic es a una de les nostres?
        mov     [int_in], ax
        mov     ax, [my]
        mov     [int_in+2], ax
        AES     106,2,1,0,0             ; wind_find
        call    troba
        jc      .r
        call    selw
        call    deixa_anar              ; primer, amb la finestra oberta
        call    llegeix_treb
        mov     bx, [cur]
        call    [tclic+bx]
        jmp     desw
.r:     ret

clic_c: mov     ax, [mx]
        sub     ax, [treb]
        js      .fora
        mov     [rx], ax
        mov     ax, [my]
        sub     ax, [treb+2]
        js      .fora
        mov     [ry], ax
        cmp     ax, [y_info]
        jae     .baix
        xor     dx, dx                  ; graella: fila i columna
        div     word [alt_fila]
        cmp     ax, FILES
        jae     .fora
        mov     bx, ax
        mov     ax, [rx]
        mov     cx, [car_w]
        shr     cx, 1
        sub     ax, cx
        js      .fora
        xor     dx, dx
        mov     cx, [car_w]
        shl     cx, 1
        div     cx
        cmp     ax, COLS
        jae     .fora
        mov     cl, 4
        shl     bx, cl
        add     ax, bx
        add     al, 32
        cmp     al, [sel]               ; ja era el triat: segon clic
        je      .afe
        call    tria
        cmp     word [clics], 2
        jb      .espera
.afe:   call    afegeix
        jmp     short .espera
.baix:  mov     ax, [ry]                ; botons?
        sub     ax, [y_bot]
        js      .fora
        mov     bx, [alt_fila]
        add     bx, 3
        cmp     ax, bx
        jae     .fora
        mov     ax, [rx]
        xor     dx, dx
        div     word [car_w]            ; al = columna de caracter
        mov     si, botons
        xor     bx, bx
.cb:    cmp     byte [si], 0FFh
        je      .fora
        mov     ah, [si]
        cmp     al, ah
        jb      .nb
        add     ah, [si+1]
        cmp     al, ah
        jb      .hit
.nb:    add     si, 4
        inc     bx
        jmp     .cb
.hit:   or      bx, bx
        jnz     .h1
        call    afegeix
        jmp     short .espera
.h1:    dec     bx
        jnz     .h2
        call    esborra
        jmp     short .espera
.h2:    call    envia
.espera:
.fora:  ret

; ---------------------------------------------------------------------
;  Teclat (la nostra finestra al davant): el caracter va a la cadena
; ---------------------------------------------------------------------
tecla:  mov     word [int_in], 0        ; (0.4) la finestra del davant
        mov     word [int_in+2], WF_TOP
        AES     104,2,5,0,0
        mov     ax, [int_out+2]
        call    troba
        jc      .r
        call    selw
        call    llegeix_treb
        mov     bx, [cur]
        mov     ax, [tecla_k]
        call    [ttec+bx]
        jmp     desw
.r:     ret

tecla_c:
        cmp     al, 8                   ; Retroces: esborra
        jne     .t1
        jmp     esborra
.t1:    cmp     al, 13                  ; Retorn: envia
        jne     .t2
        jmp     envia
.t2:    cmp     al, 27                  ; Esc: tanca la finestra
        jne     .t3
        jmp     tanca
.t3:    cmp     al, 32                  ; 32-255: tria i afegeix
        jb      .x
        call    tria
        call    afegeix
.x:     ret

; Espera que es deixi anar el boto, mirant l'estat del ratoli (graf_mkstate)
; i no amb evnt_button: si la finestra es tanca, els esdeveniments del
; ratoli ja no ens arriben i evnt_button no tornaria mai. Maxim ~2 s.
deixa_anar:
        mov     byte [compta], 100
.l:     AES     79,0,5,0,0              ; graf_mkstate
        test    word [int_out+6], 1     ; boto esquerre premut?
        jz      .r
        mov     word [int_in], 20
        mov     word [int_in+2], 0
        AES     24,2,1,0,0              ; evnt_timer(20 ms)
        dec     byte [compta]
        jnz     .l
.r:     ret
        ret

llegeix_treb:
        call    posa_wh
        mov     word [int_in+2], WF_WORKXYWH
        AES     104,2,5,0,0
        mov     si, int_out+2
        mov     di, treb
        mov     cx, 4
        rep     movsw
        ret

; al = caracter nou: redibuixa nomes les dues caselles i la linia del codi
tria:   cmp     al, [sel]
        je      .r
        mov     ah, [sel]
        mov     [sel], al
        push    ax
        mov     al, ah
        call    casella
        pop     ax
        call    casella
        mov     ax, [y_info]
        call    franja
.r:     ret

; al = caracter: redibuixa la seva casella
casella:
        sub     al, 32
        mov     bl, al
        mov     cl, 4
        shr     bl, cl                  ; fila
        and     al, 15
        xor     ah, ah
        shl     ax, 1
        mul     word [car_w]
        mov     cx, [car_w]
        shr     cx, 1
        add     ax, cx
        add     ax, [treb]
        mov     [msgbuf+8], ax
        mov     ax, [car_w]
        shl     ax, 1
        mov     [msgbuf+12], ax
        mov     al, bl
        xor     ah, ah
        mul     word [alt_fila]
        add     ax, [treb+2]
        mov     [msgbuf+10], ax
        mov     ax, [alt_fila]
        mov     [msgbuf+14], ax
        jmp     redibuixa

; ax = desplacament vertical d'una linia de text: la redibuixa sencera
franja: mov     bx, [alt_fila]
franjh: add     ax, [treb+2]            ; (0.7) BX = alcada
        mov     [msgbuf+10], ax
        mov     ax, [treb]
        mov     [msgbuf+8], ax
        mov     ax, [treb+4]
        mov     [msgbuf+12], ax
        mov     [msgbuf+14], bx
        jmp     redibuixa

afegeix:
        mov     bl, [slen]
        cmp     bl, SMAX
        jae     .r
        xor     bh, bh
        mov     al, [sel]
        mov     [sbuf+bx], al
        inc     byte [slen]
        mov     ax, [y_cad]
        call    franja
.r:     ret

esborra:
        cmp     byte [slen], 0
        je      .r
        dec     byte [slen]
        mov     ax, [y_cad]
        call    franja
.r:     ret

; Tanca la finestra i fa que el GEM "teclegi" la cadena a l'aplicacio
; que queda al davant. appl_tplay reprodueix una llista d'esdeveniments
; de 6 bytes: tipus (3 = tecla), codi de tecla + caracter, estat de Maj.
envia:  cmp     byte [slen], 0
        jne     .go
        ret
.go:    mov     si, sbuf
        mov     di, tpbuf
        mov     cl, [slen]
        xor     ch, ch
        mov     [tpn], cx
.l:     lodsb
        call    codi_tecla              ; ah = codi de tecla, al = caracter
        push    ax
        mov     ax, 3
        stosw
        pop     ax
        stosw
        xor     ax, ax
        stosw
        loop    .l
        mov     byte [slen], 0
        call    tanca
        mov     word [int_in], 150      ; deixa que el GEM activi l'altra
        mov     word [int_in+2], 0      ; finestra (150 ms)
        AES     24,2,1,0,0              ; evnt_timer
        mov     ax, [tpn]
        mov     [int_in], ax
        mov     word [int_in+2], 100    ; velocitat normal
        mov     word [addr_in], tpbuf
        mov     [addr_in+2], ds
        AES     14,2,1,1,0              ; appl_tplay
        ret

; al = caracter -> ah = codi de tecla (teclat america); 1Eh si no en te
codi_tecla:
        push    si
        push    bx
        mov     bl, al
        cmp     bl, 'A'
        jb      .c
        cmp     bl, 'Z'
        ja      .c
        add     bl, 20h
.c:     mov     si, t_tecles
.t:     mov     ah, [si]                ; codi de la primera tecla del grup
        or      ah, ah
        jz      .no
        inc     si
.g:     mov     bh, [si]
        inc     si
        or      bh, bh
        jz      .t
        cmp     bh, bl
        je      .si
        inc     ah
        jmp     .g
.no:    mov     ah, 1Eh
.si:    pop     bx
        pop     si
        ret

; =====================================================================
;  (0.4) Varies finestres: 0 Caracters, 2 Calculadora, 4 Rellotge
;  ([cur] = index*2). [whandle] es la de la finestra en curs.
; =====================================================================
registra:                               ; SI = nom -> AX = id del menu
        mov     ax, [ap_id]
        mov     [int_in], ax
        mov     [addr_in], si
        mov     [addr_in+2], ds
        AES     35,1,1,1,0
        ret

selw:   mov     [cur], bx               ; BX = index*2: passa a ser la
        mov     ax, [wtab+bx]           ;   finestra en curs
        mov     [whandle], ax
        ret

desw:   mov     bx, [cur]               ; desa [whandle] a la taula
        mov     ax, [whandle]
        mov     [wtab+bx], ax
        ret

troba:  xor     bx, bx                  ; AX = handle -> BX = index*2
.l:     cmp     [wtab+bx], ax           ;   (CF=1 si no es nostra)
        je      .s
        inc     bx
        inc     bx
        cmp     bx, 6
        jb      .l
        stc
        ret
.s:     clc
        ret

; ---------------------------------------------------------------------
;  Rellotge (0.7): com el de l'Amstrad. Fila 1 (verd): [rellotge] hh : mm
;  [nota]; fila 2 (cian): dd / mm / aa. El boto de l'esquerra hi posa
;  l'hora de l'alarma (fons groc; clic a les hores o als minuts: +1);
;  el de la dreta l'engega o l'apaga. Es torna a escriure cada minut.
; ---------------------------------------------------------------------
RCOLS   equ     16
obre_r: cmp     word [whandle], 0
        jl      .n
        jmp     al_davant
.n:     mov     di, rtim
        call    rhora
        mov     byte [aidx], 0
        mov     byte [aview], 0
        mov     ax, RCOLS
        mul     word [car_w]
        mov     [ww], ax
        call    alt_r
        shl     ax, 1
        mov     si, t_rell
        mov     bx, -1                  ; al mig (o on era)
        jmp     obrew

alt_r:  mov     ax, [alt_fila]          ; AX = alcada d'una fila
        add     ax, 4
        ret

; DI -> "hh : mm" i "dd / mm / aa" (7 + 12 bytes)
rhora:  mov     ah, 2Ch
        int     21h
        mov     al, ch
        call    dues
        mov     ax, ' :'
        stosw
        mov     al, ' '
        stosb
        mov     al, cl
        call    dues
        mov     ah, 2Ah
        int     21h
        mov     al, dl
        call    dues
        call    .bar
        mov     al, dh
        call    dues
        call    .bar
        mov     ax, cx
        mov     bl, 100
        div     bl
        mov     al, ah
        jmp     short dues
.bar:   mov     ax, '/ '
        xchg    al, ah
        stosw
        mov     al, ' '
        stosb
        ret
dues:   aam                             ; AL (0-99) -> 2 xifres a [di]
        add     ax, '00'
        xchg    al, ah
        stosw
        ret

tic:    mov     di, rnou
        call    rhora
        cmp     byte [alon], 0          ; l'alarma, encara que la finestra
        je      .a                      ;   sigui tancada
        mov     ah, 2Ch
        int     21h
        cmp     ch, [alh]
        jne     .a
        cmp     cl, [alm]
        jne     .a
        call    sona
.a:     cmp     word [wtab+4], 0
        jl      .r
        mov     bx, 4
        call    selw
        call    llegeix_treb
        xor     dx, dx                  ; fila 0: l'hora (7), 1: la data (12)
        mov     si, rnou
        mov     di, rtim
        mov     cx, 7
.l:     push    cx
        push    si
        push    di
        repe    cmpsb
        pop     di
        pop     si
        pop     cx
        je      .s
        push    si
        push    di
        push    cx
        rep     movsb
        push    dx
        or      dx, dx                  ; l'hora no, si hi ha l'alarma
        jnz     .w
        cmp     byte [aview], 0
        jne     .nw
.w:     call    fila_r
.nw:    pop     dx
        pop     cx
        pop     di
        pop     si
.s:     add     si, cx
        add     di, cx
        mov     cx, 12
        inc     dx
        cmp     dx, 2
        jb      .l
.r:     ret

fila_r: call    alt_r                   ; torna a dibuixar la fila DX
        mov     bx, ax
        mul     dx
        jmp     franjh

dib_r:  mov     byte [fons], 0
        call    prep
        cmp     byte [nnota], 0         ; (0.9) nomes la nota: el fons blanc
        je      .tot                    ;   ja hi es (prep), i la nota
        call    alt_r
        mov     bx, ax
        xor     ax, ax
        call    toca
        call    .nota
        jmp     fiw
.tot:        call    alt_r                   ; fila 1
        mov     bx, ax
        xor     ax, ax
        call    toca
        jc      .f2
        mov     ax, 3                   ; verd (groc: l'alarma)
        cmp     byte [aview], 0
        je      .c1
        mov     ax, 6
.c1:    call    fonsfila
        mov     ax, 0109h               ; boto del rellotge (negre), o la
        cmp     byte [aview], 0         ;   campaneta (vermella): l'alarma
        je      .b1
        xor     ax, ax                  ;   (0.9: dibuixada, no es cap lletra)
.b1:    xor     cx, cx
        call    boto_r
        call    .nota
        mov     si, rtim                ; hh : mm
        cmp     byte [aview], 0
        je      .t
        mov     di, atxt
        push    di
        mov     al, [alh]
        call    dues
        mov     ax, ' :'
        stosw
        mov     al, ' '
        stosb
        mov     al, [alm]
        call    dues
        pop     si
.t:     mov     cx, 7
        mov     ax, 5
        mov     bl, 1
        call    textc
.f2:    call    alt_r                   ; fila 2: la data
        mov     bx, ax
        call    toca
        jc      .x
        mov     ax, 5                   ; cian
        call    fonsfila
        mov     di, ptsin               ; (0.8) linia negra entre les files
        mov     ax, [treb]
        stosw
        mov     ax, [ytop]
        stosw
        mov     ax, [treb]
        add     ax, [treb+4]
        dec     ax
        stosw
        mov     ax, [ytop]
        stosw
        VDI     6,2,0                   ; v_pline
        inc     word [ytop]             ; (0.9) la data, un punt mes avall
        mov     si, rtim+7              ;   (sota la linia: centrada)
        mov     cx, 12
        mov     ax, 2
        mov     bl, 1
        call    textc
        mov     si, t_bar               ; les barres, en blau
        mov     cx, 12
        mov     ax, 2
        mov     bl, 4
        call    textc
        dec     word [ytop]
.x:     jmp     fiw

.nota:  mov     ax, 010Bh               ; la nota: vermella si l'alarma es
        cmp     byte [alon], 0          ;   engegada
        je      .b2
        mov     ah, 2
.b2:    mov     cx, RCOLS-2
        jmp     boto_r

; omple la fila [ytop] (alcada alt_r) del color AX, tot l'ample
fonsfila:
        push    ax
        call    alt_r
        add     ax, [ytop]
        dec     ax
        mov     [by2], ax
        mov     ax, [treb]
        mov     [bx1], ax
        add     ax, [treb+4]
        dec     ax
        mov     [bx2], ax
        pop     ax
        jmp     omple

; boto de la fila 1 a la columna CX: AL = caracter, AH = el seu color
; (1 negre, 2 vermell), sobre blanc i amb marc
boto_r: push    ax                      ; (0.9) franja blanca, sense marc
        mov     ax, cx
        mul     word [car_w]
        add     ax, [treb]
        mov     [bx1], ax
        add     ax, [car_w]
        add     ax, [car_w]
        dec     ax
        mov     [bx2], ax
        call    alt_r
        add     ax, [ytop]
        dec     ax
        mov     [by2], ax
        xor     ax, ax
        call    omple
        pop     ax
        or      al, al
        jz      campana
        mov     [t_un], al
        mov     bl, ah
        mov     si, t_un
        mov     cx, 1
        mov     ax, [bx1]               ; centrada
        add     ax, 4
        jmp     textx

; (0.9) la campaneta vermella, punt a punt (7 files de 7), a la franja
; [bx1].., fila [ytop]: cada tros de punts seguits d'una fila, un rectangle
campana:
        push    word [ytop]
        add     word [ytop], 2
        mov     si, b_camp
.f:     lodsb
        cmp     al, 0FFh
        je      .x
        mov     dl, al                  ; els punts de la fila
        mov     cx, [bx1]
        add     cx, 4                   ; x de la columna 0
.c:     or      dl, dl
        jz      .nf
        shl     dl, 1
        jnc     .s
        mov     [bx1x], cx              ; comenca un tros
.t:     inc     cx                      ; fins on arriba
        shl     dl, 1
        jc      .t
        dec     cx
        mov     [bx2], cx
        push    word [bx1]
        mov     ax, [bx1x]
        mov     [bx1], ax
        mov     ax, [ytop]
        mov     [by2], ax
        mov     ax, 2
        push    si
        push    cx
        push    dx
        call    omple
        pop     dx
        pop     cx
        pop     si
        pop     word [bx1]
        add     cx, 2                   ; el que segueix el 0 que ha aturat
        jmp     .c
.s:     inc     cx
        jmp     .c
.nf:    inc     word [ytop]
        jmp     .f
.x:     pop     word [ytop]
        ret

; (0.6) desa a EINES.CFG l'alarma (hora, minut, engegada) i (0.7) on
; es cada finestra
desa_cfg:
        mov     dx, t_cfg
        xor     cx, cx
        mov     ah, 3Ch
        int     21h
        jc      .x
        mov     bx, ax
        mov     dx, alh
        mov     cx, 15
        mov     ah, 40h
        int     21h
        mov     ah, 3Eh
        int     21h
.x:     ret

; l'alarma sona: tres xiulets i una alerta; despres queda apagada
sona:   mov     byte [alon], 0
        call    desa_cfg
        mov     cx, 3
.b:     push    cx
        mov     ax, 0E07h               ; BEL per la BIOS: nomes xiula
        xor     bx, bx
        int     10h
        mov     word [int_in], 250
        mov     word [int_in+2], 0
        AES     24,2,1,0,0              ; evnt_timer(250 ms)
        pop     cx
        loop    .b
        mov     di, al_hora
        mov     al, [alh]
        call    dues
        inc     di
        mov     al, [alm]
        call    dues
        mov     word [int_in], 1
        mov     word [addr_in], al_alar
        mov     [addr_in+2], ds
        AES     52,1,1,1,0              ; form_alert
        cmp     word [wtab+4], 0
        jl      .x
        mov     bx, 4
        call    selw
        jmp     alarma_l
.x:     ret

alarma_l:                               ; torna a dibuixar la fila 1
        call    llegeix_treb
        xor     dx, dx
        jmp     fila_r

; (0.9) nomes el lloc de la nota (canvia de color): res mes
nota_l: call    llegeix_treb
        mov     ax, RCOLS-2
        mul     word [car_w]
        add     ax, [treb]
        mov     [msgbuf+8], ax
        mov     ax, [treb+2]
        mov     [msgbuf+10], ax
        mov     ax, [car_w]
        shl     ax, 1
        mov     [msgbuf+12], ax
        call    alt_r
        mov     [msgbuf+14], ax
        mov     byte [nnota], 1
        call    redibuixa
        mov     byte [nnota], 0
        ret

; teclat: Esc tanca; A o espai engega / apaga l'alarma; les xifres
; n'escriuen l'hora (hh:mm, una darrera l'altra) i la mostren
tec_r:  cmp     al, 27                  ; Esc: tanca
        jne     .t1
        jmp     tanca
.t1:    cmp     al, ' '
        je      .tg
        and     al, 0DFh
        cmp     al, 'A'
        je      .tg
        mov     al, [tecla_k]
        sub     al, '0'
        jb      .x
        cmp     al, 9
        ja      .x
        mov     byte [aview], 1
        mov     bl, [aidx]              ; 0 1: hores, 2 3: minuts
        mov     bh, al
        mov     si, alh
        cmp     bl, 2
        jb      .h
        inc     si
.h:     mov     al, [si]                ; desenes o unitats
        test    bl, 1
        jnz     .u
        aam                             ; AL = unitats
        mov     ah, bh
        jmp     short .c
.u:     aam
        mov     al, bh                  ; AH = desenes
.c:     aad                             ; AH*10+AL
        mov     ah, 23
        cmp     si, alh
        je      .m
        mov     ah, 59
.m:     cmp     al, ah
        jbe     .k
        mov     al, ah
.k:     mov     [si], al
        inc     bl
        and     bl, 3
        mov     [aidx], bl
        mov     byte [alon], 1
        jnz     alarma_l                ; desada en acabar hh:mm
        call    desa_cfg
        jmp     alarma_l
.tg:    xor     byte [alon], 1
        call    desa_cfg
        jmp     nota_l
.x:     ret

; clic: els dos botons; amb l'alarma a la vista, les hores i els minuts
clic_r: mov     ax, [my]
        sub     ax, [treb+2]
        call    .fila
        mov     ax, [mx]
        sub     ax, [treb]
        xor     dx, dx
        div     word [car_w]            ; AX = columna
        cmp     ax, 2
        jae     .c1
        xor     byte [aview], 1         ; el rellotge: hora / alarma
        mov     byte [aidx], 0
        jmp     alarma_l
.c1:    cmp     ax, RCOLS-2
        jb      .c2
        xor     byte [alon], 1          ; la nota: engegada / apagada
        call    desa_cfg
        jmp     nota_l
.c2:    cmp     byte [aview], 0
        je      .x
        cmp     ax, 8
        jae     .c3
        inc     byte [alh]              ; hores +1
        cmp     byte [alh], 24
        jb      .d
        mov     byte [alh], 0
        jmp     short .d
.c3:    inc     byte [alm]              ; minuts +1
        cmp     byte [alm], 60
        jb      .d
        mov     byte [alm], 0
.d:     call    desa_cfg
        jmp     alarma_l
.fila:  push    ax                      ; nomes la fila 1
        call    alt_r
        mov     bx, ax
        pop     ax
        cmp     ax, bx
        jb      .ok
        pop     ax                      ; (treu el retorn: res a fer)
.x:     ret
.ok:    ret

; ---------------------------------------------------------------------
;  Colors (0.7): omplir i escriure amb color
; ---------------------------------------------------------------------
; omple [bx1]..[bx2] x [ytop]..[by2] del color AX
omple:  mov     [intin], ax
        VDI     25,0,1                  ; vsf_color
        mov     ax, [bx1]
        mov     [ptsin], ax
        mov     ax, [ytop]
        mov     [ptsin+2], ax
        mov     ax, [bx2]
        mov     [ptsin+4], ax
        mov     ax, [by2]
        mov     [ptsin+6], ax
        VDI     114,2,0                 ; vr_recfl
        ret

; marc negre de [bx1]..[bx2] x [ytop]..[by2]
marc:   mov     di, ptsin
        mov     ax, [bx1]
        stosw
        mov     ax, [ytop]
        stosw
        mov     ax, [bx2]
        stosw
        mov     ax, [ytop]
        stosw
        mov     ax, [bx2]
        stosw
        mov     ax, [by2]
        stosw
        mov     ax, [bx1]
        stosw
        mov     ax, [by2]
        stosw
        mov     ax, [bx1]
        stosw
        mov     ax, [ytop]
        stosw
        VDI     6,5,0                   ; v_pline
        ret

; text transparent del color BL: SI, CX caracters, AX = columna (des de
; l'esquerra de l'area de treball), linia [ytop]
textc:  push    dx
        mul     word [car_w]
        add     ax, [treb]
        pop     dx
textx:  push    ax                      ; AX = x en pixels
        push    cx
        push    si
        mov     [intin], bl
        mov     byte [intin+1], 0
        VDI     22,0,1                  ; vst_color
        mov     word [intin], 2
        VDI     32,0,1                  ; vswr_mode(transparent)
        pop     si
        pop     cx
        pop     ax
        call    gtext
        mov     word [intin], 1
        VDI     32,0,1                  ; vswr_mode(substitucio)
        mov     word [intin], 1
        VDI     22,0,1                  ; vst_color(negre)
        ret

; ---------------------------------------------------------------------
;  Calculadora: nombres amb 6 decimals (enters de 64 bits en milionesimes)
; ---------------------------------------------------------------------
KCOLS   equ     31              ; ample, en caracters (5 botons de 6)
KPILA   equ     16              ; (0.5) fondaria de les piles
obre_k: cmp     word [whandle], 0
        jl      .n
        jmp     al_davant
.n:     mov     ax, KCOLS
        mul     word [car_w]
        mov     [ww], ax
        mov     ax, [alt_fila]
        add     ax, 4
        mov     [kpas], ax              ; d'una fila de botons a l'altra
        add     ax, 4
        mov     [ky0], ax               ; la primera fila de botons
        mov     ax, [kpas]
        mov     bx, 5
        mul     bx
        add     ax, [ky0]
        mov     si, t_calc
        mov     bx, -1                  ; (0.7) al mig (o on era)
        jmp     obrew

dib_k:  cmp     byte [kinv], 0          ; (0.11) el boto premut, en negatiu
        je      .norm
        mov     word [intin], 1         ; vs_clip(on)
        mov     si, clip
        mov     di, ptsin
        mov     cx, 4
        rep     movsw
        VDI     129,2,1
        mov     word [intin], 3         ; vswr_mode(XOR)
        VDI     32,0,1
        mov     word [intin], 1         ; vsf_interior(solid)
        VDI     23,0,1
        mov     word [intin], 1         ; vsf_color(negre)
        VDI     25,0,1
        mov     si, krect
        mov     di, ptsin
        mov     cx, 4
        rep     movsw
        VDI     114,2,0                 ; vr_recfl
        mov     word [intin], 1
        VDI     32,0,1
        jmp     fiw
.norm:  mov     byte [fons], 4          ; (0.7) fons blau (groc: nomes el visor)
        cmp     byte [kvis], 0
        je      .k0
        mov     byte [fons], 6
.k0:    call    prep
        mov     ax, 1                   ; el visor, groc i amb marc
        mov     bx, [alt_fila]
        add     bx, 4
        call    toca
        jc      .b
        mov     ax, [treb]
        add     ax, 3
        mov     [bx1], ax
        mov     ax, KCOLS
        mul     word [car_w]
        add     ax, [treb]
        sub     ax, 4
        mov     [bx2], ax
        call    altbot
        mov     ax, 6
        call    omple
        call    caixa
        call    visor
.b:     xor     bp, bp                  ; els 25 botons (sense els buits)
.f:     cmp     byte [ds:t_kc+bp], 0
        je      .s
        mov     ax, bp
        mov     bl, 5
        div     bl
        mov     [kcol], ah
        xor     ah, ah                  ; fila
        mul     word [kpas]
        add     ax, [ky0]
        mov     bx, [alt_fila]
        add     bx, 3
        call    toca
        jc      .s
        mov     al, [kcol]              ; columna: x = (col*6+1) caracters
        xor     ah, ah
        mov     bx, 6
        mul     bx
        inc     ax
        mul     word [car_w]
        add     ax, [treb]
        mov     [bx1], ax
        mov     bx, ax
        mov     ax, 5
        mul     word [car_w]
        add     ax, bx
        dec     ax
        mov     [bx2], ax
        mov     si, bp
        mov     ax, si
        shl     si, 1
        add     si, ax
        add     si, t_kl                ; 3 caracters per boto
        call    altbot                  ; (0.7) xifres en blanc, la resta cian
        mov     al, [ds:t_kc+bp]
        cmp     al, '.'
        je      .w
        sub     al, '0'
        cmp     al, 9
        mov     ax, 0
        jbe     .w0
        mov     ax, 5
        jmp     short .w0
.w:     xor     ax, ax
.w0:    push    si
        call    omple
        call    caixa
        pop     si
        mov     cx, 3                   ; (0.8) l'etiqueta, sense espais,
.tl:    cmp     byte [si], ' '          ;   centrada (un punt a l'esquerra:
        jne     .tt                     ;   la lletra te buida la columna 0)
        inc     si
        dec     cx
        jmp     .tl
.tt:    mov     bx, si
        add     bx, cx
        cmp     byte [bx-1], ' '
        jne     .tc
        dec     cx
        jmp     .tt
.tc:    mov     ax, 5
        sub     ax, cx
        mul     word [car_w]
        shr     ax, 1
        add     ax, [bx1]
        dec     ax
        mov     bl, 1
        call    textx
.s:     inc     bp
        cmp     bp, 25
        jb      .f
        jmp     fiw

visor:  mov     ax, 3                   ; el nombre, alineat a la dreta
        mov     bx, [alt_fila]
        call    toca
        jc      .x
        mov     di, linia
        mov     ax, '  '                ; (0.5) "(2": parentesis oberts
        mov     cl, [kpar]
        or      cl, cl
        jz      .p
        mov     al, '('
        mov     ah, cl
        add     ah, '0'
        cmp     ah, '9'
        jbe     .p
        mov     ah, '+'
.p:     stosw
        mov     cx, KCOLS-4
        mov     bl, [klen]
        xor     bh, bh
        sub     cx, bx
        mov     al, ' '
        rep     stosb
        mov     si, kbuf
        mov     cx, bx
        rep     movsb
        mov     word [intin], 2         ; (0.7) transparent: sobre el groc
        push    di
        VDI     32,0,1
        pop     di
        call    text_linia
        mov     word [intin], 1
        VDI     32,0,1
.x:     ret

altbot: mov     ax, [ytop]              ; by2 = ytop + alt_fila + 2
        add     ax, [alt_fila]
        add     ax, 2
        mov     [by2], ax
        ret

clic_k: mov     ax, [my]                ; quin boto?
        sub     ax, [treb+2]
        sub     ax, [ky0]
        jb      .x
        xor     dx, dx
        div     word [kpas]
        cmp     ax, 5
        jae     .x
        mov     bx, [alt_fila]
        add     bx, 2
        cmp     dx, bx
        ja      .x
        mov     cx, ax                  ; fila
        mov     ax, [mx]
        sub     ax, [treb]
        xor     dx, dx
        div     word [car_w]
        dec     ax
        js      .x
        mov     bl, 6
        div     bl
        cmp     ah, 5
        jae     .x
        cmp     al, 5
        jae     .x
        mov     bl, al
        mov     al, 5
        mul     cl
        add     al, bl
        xor     ah, ah
        mov     bx, ax
        mov     al, [t_kc+bx]
        or      al, al
        jz      .x
        jmp     calc
.x:     ret

tec_k:  cmp     ax, 5300h               ; Supr: C
        je      .c
        cmp     al, 27                  ; Esc: tanca
        jne     .t1
        jmp     tanca
.t1:    cmp     al, 13                  ; Retorn: =
        jne     .t2
        mov     al, '='
.t2:    cmp     al, ','
        jne     .t3
        mov     al, '.'
.t3:    cmp     al, 'a'                 ; c, e, n en minuscula
        jb      calc
        sub     al, 20h
        jmp     short calc
.c:     mov     al, 'C'

; AL = tecla: 0-9 . + - * / = C (tot), E (CE), N (+/-), 8 (retroces)
calc:   call    prem_k                  ; (0.11) el boto, un moment en negatiu
        cmp     byte [kerr], 0          ; despres d'un error, tot de nou
        je      .k0
        push    ax
        call    k_zero
        pop     ax
.k0:    cmp     al, 'C'
        jne     .k1
        call    k_zero
        jmp     visorm
.k1:    cmp     al, 'E'
        jne     .k2
.ce:    mov     word [kbuf], '0'
        mov     byte [klen], 1
        mov     byte [knou], 1
        jmp     visorm
.k2:    cmp     al, 8
        jne     .k3
        cmp     byte [knou], 0
        jne     .r
        dec     byte [klen]
        jz      .ce
        cmp     byte [klen], 1          ; nomes el signe?
        jne     visorm
        cmp     byte [kbuf], '-'
        je      .ce
        jmp     visorm
.k3:    cmp     al, 'N'
        jne     .k4
        cmp     byte [kent], 0          ; (0.5) despres d'una operacio: "-"
        jne     .n1
        mov     byte [kbuf], '-'
        mov     byte [klen], 1
        mov     byte [knou], 0
        mov     byte [kent], 1
        jmp     visorm
.n1:    cmp     byte [klen], 1          ; "0": res
        jne     .n0
        cmp     byte [kbuf], '0'
        je      .r
.n0:    mov     byte [kent], 1
        mov     si, kbuf
        mov     di, kbuf
        mov     cl, [klen]
        xor     ch, ch
        cmp     byte [si], '-'
        jne     .ng
        inc     si                      ; treu el signe
        dec     byte [klen]
        rep     movsb
        jmp     visorm
.ng:    cmp     cl, 21
        jae     .r
        add     si, cx                  ; posa el signe
        mov     di, si
        dec     si
        std
        rep     movsb
        cld
        mov     byte [kbuf], '-'
        inc     byte [klen]
        jmp     visorm
.k4:    cmp     al, 'P'                 ; (0.6) pi: com un resultat
        jne     .k5
        mov     si, t_pi
        mov     di, kbuf
        mov     cx, 8
        rep     movsb
        mov     byte [klen], 8
        mov     byte [kent], 1
        mov     byte [knou], 1
        jmp     visorm
.k5:    cmp     al, '.'
        je      .xif
        cmp     al, '0'
        jb      .op
        cmp     al, '9'
        ja      .op
.xif:   mov     [kkey], al
        cmp     byte [knou], 0          ; una xifra o el punt
        je      .x1
        mov     byte [knou], 0
        mov     byte [klen], 0
.x1:    mov     byte [kent], 1
        mov     si, kbuf                ; quantes xifres hi ha
        mov     cl, [klen]
        xor     ch, ch
        xor     bx, bx                  ; BL enters, BH decimals (+1 si hi ha punt)
.cx:    jcxz    .cf
        lodsb
        dec     cx
        cmp     al, '.'
        jne     .c1
        mov     bh, 1
        jmp     .cx
.c1:    cmp     al, '0'
        jb      .cx
        or      bh, bh
        jz      .c2
        inc     bh
        jmp     .cx
.c2:    inc     bl
        jmp     .cx
.cf:    mov     al, [kkey]
        cmp     al, '.'
        jne     .d
        or      bh, bh                  ; ja hi ha punt
        jnz     .r
        or      bl, bl
        jnz     .ap
        mov     al, '0'                 ; ".5" -> "0.5"
        call    .afe
        mov     al, '.'
        jmp     short .ap
.d:     cmp     bh, 7                   ; 6 decimals, 12 enters
        jae     .r
        or      bh, bh
        jnz     .ap
        cmp     bl, 12
        jae     .r
        cmp     bl, 1                   ; "0" -> la xifra
        jne     .ap
        cmp     byte [si-1], '0'
        jne     .ap
        dec     byte [klen]
.ap:    call    .afe
        jmp     visorm
.afe:   mov     bl, [klen]
        xor     bh, bh
        mov     [kbuf+bx], al
        inc     byte [klen]
.r:     ret

.op:    cmp     al, '('                 ; (0.5) amb jerarquia i parentesis
        je      .pa
        cmp     al, ')'
        je      .pt
        cmp     al, '='
        je      .ig
        call    prec                    ; + - * / -> AH = 1 o 2
        jc      .r
        cmp     byte [kent], 0          ; dues operacions seguides: la
        jne     .o1                     ;   darrera
        mov     bl, [no]
        or      bl, bl
        jz      .r
        xor     bh, bh
        cmp     byte [ops+bx-1], '('
        je      .r
        mov     [ops+bx-1], al
        ret
.o1:    push    ax
        call    empeny                  ; el nombre del visor, a la pila
        pop     ax
        jc      .err
        push    ax
        cmp     ah, 3                   ; (0.6) ^ i arrel, de dreta a esquerra:
        jne     .o3                     ;   2^3^2 = 2^9
        inc     ah
.o3:    call    redueix                 ; fa les que tenen tanta o mes
        pop     ax                      ;   prioritat
        jc      .err
        mov     bl, [no]
        cmp     bl, KPILA
        jae     .err
        xor     bh, bh
        mov     [ops+bx], al
        inc     byte [no]
        mov     byte [kent], 0
.mo:    call    dalt                    ; el visor: el darrer resultat
        call    escriu
        mov     byte [knou], 1
        jmp     visorm
.pa:    cmp     byte [kent], 0          ; '(': nomes on va un nombre
        je      .p0
        cmp     byte [nv], 0            ;   (o al principi)
        jne     .r
        cmp     byte [no], 0
        jne     .r
.p0:    mov     bl, [no]
        cmp     bl, KPILA
        jae     .err
        xor     bh, bh
        mov     byte [ops+bx], '('
        inc     byte [no]
        inc     byte [kpar]
        mov     byte [kent], 0
        mov     byte [knou], 1
        jmp     visorm
.pt:    cmp     byte [kpar], 0          ; ')': cal un '(' obert i un nombre
        je      .r
        cmp     byte [kent], 0
        je      .r
        call    empeny
        jc      .err
        xor     ah, ah                  ; fins al '('
        call    redueix
        jc      .err
        dec     byte [no]               ; treu el '('
        dec     byte [kpar]
        jmp     short .fi
.ig:    cmp     byte [kent], 0          ; '=': si acaba en operacio, fora
        jne     .i1
        mov     bl, [no]
        or      bl, bl
        jz      .i2
        xor     bh, bh
        cmp     byte [ops+bx-1], '('
        je      .i2
        dec     byte [no]
        jmp     short .i2
.i1:    call    empeny
        jc      .err
.i2:    mov     bl, [no]                ; totes, i els '(' que queden
        or      bl, bl
        jz      .i3
        xor     bh, bh
        cmp     byte [ops+bx-1], '('
        jne     .i4
        dec     byte [no]
        jmp     .i2
.i4:    call    aplica
        jc      .err
        jmp     .i2
.i3:    cmp     byte [nv], 0
        je      .mo0
        mov     byte [kpar], 0
.fi:    call    dalt                    ; el resultat passa a ser el nombre
        dec     byte [nv]               ;   del visor
        call    escriu
        mov     byte [kent], 1
        mov     byte [knou], 1
        jmp     visorm
.mo0:   jmp     visorm
.err:   call    k_zero
        mov     si, t_kerr
        mov     di, kbuf
        mov     cx, 5
        rep     movsb
        mov     byte [klen], 5
        mov     byte [kerr], 1
        jmp     visorm                  ; (0.11: abans hi queia a sota)

; (0.11) AL = tecla: si es d'un boto, el posa en negatiu (XOR, nomes
; l'interior), espera un moment i el torna a dibuixar. Conserva AX
prem_k: push    ax
        push    bx
        push    cx
        push    dx
        push    si
        push    di
        push    bp
        push    es
        mov     di, t_kc
        mov     cx, 25
        push    ds
        pop     es
        repne   scasb
        jne     .x
        mov     ax, di
        sub     ax, t_kc+1              ; index del boto
        mov     bl, 5
        div     bl                      ; AL fila, AH columna
        mov     [kcol], ah
        xor     ah, ah
        mul     word [kpas]
        add     ax, [ky0]
        push    ax
        call    llegeix_treb
        pop     ax
        add     ax, [treb+2]
        mov     [msgbuf+10], ax         ; el boto: y
        inc     ax
        mov     [krect+2], ax
        add     ax, [alt_fila]
        mov     [krect+6], ax
        mov     ax, [alt_fila]
        add     ax, 3
        mov     [msgbuf+14], ax
        mov     al, [kcol]              ; x = (col*6+1) caracters
        xor     ah, ah
        mov     bx, 6
        mul     bx
        inc     ax
        mul     word [car_w]
        add     ax, [treb]
        mov     [msgbuf+8], ax
        inc     ax
        mov     [krect], ax
        mov     ax, 5
        mul     word [car_w]
        mov     [msgbuf+12], ax
        add     ax, [krect]
        sub     ax, 3
        mov     [krect+4], ax
        mov     byte [kinv], 1          ; en negatiu
        call    redibuixa
        mov     word [int_in], 90       ; evnt_timer(90 ms)
        mov     word [int_in+2], 0
        AES     24,2,1,0,0
        mov     byte [kinv], 0          ; i com era (tornant-lo a dibuixar:
        call    redibuixa               ;   encara que s'hagi tapat)
.x:     pop     es
        pop     bp
        pop     di
        pop     si
        pop     dx
        pop     cx
        pop     bx
        pop     ax
        ret

visorm: call    llegeix_treb            ; torna a escriure el visor
        mov     byte [kvis], 1
        mov     ax, [treb+2]            ; (0.8) nomes l'interior del visor
        add     ax, 3                   ;   (abans, tot l'ample: deixava
        mov     [msgbuf+10], ax         ;   groc als costats)
        mov     ax, [treb]
        add     ax, 4
        mov     [msgbuf+8], ax
        mov     ax, KCOLS
        mul     word [car_w]
        sub     ax, 8
        mov     [msgbuf+12], ax
        mov     ax, [alt_fila]
        mov     [msgbuf+14], ax
        call    redibuixa
        mov     byte [kvis], 0
        ret

; AL = operacio -> AH = prioritat (CF=1 si no ho es)
prec:   mov     ah, 1
        cmp     al, '+'
        je      .s
        cmp     al, '-'
        je      .s
        inc     ah
        cmp     al, '*'
        je      .s
        cmp     al, '/'
        je      .s
        cmp     al, '^'
        je      .t
        cmp     al, 'R'
        je      .t
        stc
        ret
.s:     clc
        ret
.t:     mov     ah, 3                   ; (0.6) potencia i arrel
        clc
        ret

; el nombre del visor, a la pila de valors (CF=1 si plena)
empeny: call    llegeix
        cmp     byte [nv], KPILA
        jae     .e
        inc     byte [nv]
        call    dalt
        mov     si, kx
        mov     di, [kdalt]
        movsw
        movsw
        movsw
        movsw
        clc
        ret
.e:     stc
        ret

; kval = el valor de dalt de la pila; [kdalt] = on es
dalt:   mov     al, [nv]
        dec     al
        mov     ah, 8
        mul     ah
        add     ax, vals
        mov     [kdalt], ax
        mov     si, ax
        mov     di, kval
        movsw
        movsw
        movsw
        movsw
        ret

; fa les operacions de dalt de la pila amb prioritat >= AH (0: fins al '(')
redueix:
        mov     bl, [no]
        or      bl, bl
        jz      .x
        xor     bh, bh
        mov     al, [ops+bx-1]
        cmp     al, '('
        je      .x
        push    ax
        mov     dh, ah
        call    prec
        cmp     ah, dh
        pop     ax
        jb      .x
        push    ax
        call    aplica
        pop     ax
        jc      .e
        jmp     redueix
.x:     clc
.e:     ret

; la darrera operacio amb els dos valors de dalt
aplica: cmp     byte [nv], 2
        jb      .e
        dec     byte [no]
        mov     bl, [no]
        xor     bh, bh
        mov     al, [ops+bx]
        mov     [kkop], al
        call    dalt                    ; b -> kx
        mov     si, kval
        mov     di, kx
        movsw
        movsw
        movsw
        movsw
        dec     byte [nv]
        call    dalt                    ; a -> kval
        mov     si, kx
        mov     di, kval
        mov     al, [kkop]
        cmp     al, '+'
        jne     .p1
        call    m_add
        jmp     short .f
.p1:    cmp     al, '-'
        jne     .p2
        call    m_sub
        jmp     short .f
.p2:    cmp     al, '*'
        jne     .p3
        call    m_mul
        jmp     short .f
.p3:    cmp     al, '^'
        jne     .p4
        call    m_pot
        jmp     short .f
.p4:    cmp     al, 'R'
        jne     .p5
        call    m_arr
        jmp     short .f
.p5:    call    m_div
.f:     jc      .e
        mov     si, kval                ; el resultat, al lloc de a
        mov     di, [kdalt]
        movsw
        movsw
        movsw
        movsw
        clc
        ret
.e:     stc
        ret

k_zero: xor     ax, ax
        mov     [kerr], al
        mov     [nv], al
        mov     [no], al
        mov     [kpar], al
        mov     byte [kent], 1
        mov     word [kbuf], '0'
        mov     byte [klen], 1
        mov     byte [knou], 1
        ret

; kbuf -> kx (milionesimes)
llegeix:
        xor     ax, ax
        mov     di, kx
        mov     cx, 4
        rep     stosw
        mov     si, kbuf
        mov     cl, [klen]
        xor     ch, ch
        mov     bx, 6                   ; decimals que falten
        xor     dx, dx                  ; DL: signe, DH: despres del punt
.l:     jcxz    .f
        dec     cx
        lodsb
        cmp     al, '-'
        jne     .l1
        inc     dl
        jmp     .l
.l1:    cmp     al, '.'
        jne     .l2
        inc     dh
        jmp     .l
.l2:    sub     al, '0'
        jb      .l
        push    ax
        call    m10
        pop     ax
        xor     ah, ah
        add     [kx], ax
        adc     word [kx+2], 0
        adc     word [kx+4], 0
        adc     word [kx+6], 0
        or      dh, dh
        jz      .l
        dec     bx
        jmp     .l
.f:     or      bx, bx
        jz      .s
        call    m10
        dec     bx
        jmp     .f
.s:     or      dl, dl
        jz      .r
        mov     di, kx
        jmp     neg4
.r:     ret

m10:    push    bx                      ; kx *= 10
        push    cx
        push    dx
        mov     di, kx
        mov     cx, 4
        xor     bx, bx                  ; ròssec
.l:     mov     ax, [di]
        push    dx
        mov     dx, 10
        mul     dx
        add     ax, bx
        adc     dx, 0
        mov     [di], ax
        mov     bx, dx
        pop     dx
        inc     di
        inc     di
        loop    .l
        pop     dx
        pop     cx
        pop     bx
        ret

; kval -> kbuf (fins a 6 decimals, sense zeros de mes)
escriu: mov     si, kval
        mov     di, wt
        movsw
        movsw
        movsw
        movsw
        xor     bp, bp                  ; signe
        test    byte [wt+7], 80h
        jz      .p
        inc     bp
        mov     di, wt
        call    neg4
.p:     mov     di, dig+20              ; xifres, de la darrera a la primera
        xor     cx, cx
.d:     push    di
        mov     si, wt+6
        mov     bx, 10
        xor     dx, dx
        mov     di, 4
.dv:    mov     ax, [si]
        div     bx
        mov     [si], ax
        dec     si
        dec     si
        dec     di
        jnz     .dv
        pop     di
        dec     di
        add     dl, '0'
        mov     [di], dl
        inc     cx
        cmp     cx, 7
        jb      .d
        mov     ax, [wt]
        or      ax, [wt+2]
        or      ax, [wt+4]
        or      ax, [wt+6]
        jnz     .d
        mov     si, di
        mov     di, kbuf
        or      bp, bp
        jz      .e
        mov     al, '-'
        stosb
.e:     sub     cx, 6                   ; la part entera
        rep     movsb
        mov     al, '.'
        stosb
        mov     cx, 6
        rep     movsb
.z:     dec     di                      ; treu els zeros i el punt
        cmp     byte [di], '0'
        je      .z
        cmp     byte [di], '.'
        je      .k
        inc     di
.k:     sub     di, kbuf
        mov     ax, di
        mov     [klen], al
        ret

; ---------------------------------------------------------------------
;  (0.6) a ^ n i arrel n-esima de a (n enter)
; ---------------------------------------------------------------------
; kx -> AX = |n| enter (< 10000), [psg] = signe. CF=1 si no ho es
intx:   mov     byte [ksig], 0
        mov     si, kx
        mov     di, wp
        call    carrega
        mov     si, milio
        mov     di, wb
        call    carrega
        mov     al, [ksig]
        mov     [psg], al
        call    udiv
        mov     si, wr                  ; sense decimals
        mov     cx, 8
.r:     lodsw
        or      ax, ax
        jnz     .e
        loop    .r
        mov     ax, [wp+2]
        or      ax, [wp+4]
        or      ax, [wp+6]
        jnz     .e
        mov     ax, [wp]
        cmp     ax, 10000
        jae     .e
        clc
        ret
.e:     stc
        ret

; [DI] *= [SI] (64 bits, milionesimes); CF=1 si desborda
mulx:   push    si
        push    di
        push    si
        mov     si, di                  ; kval = [DI]
        mov     di, kval
        movsw
        movsw
        movsw
        movsw
        pop     si                      ; kx = [SI]
        mov     di, kx
        movsw
        movsw
        movsw
        movsw
        call    m_mul
        pop     di
        pop     si
        jc      .x
        push    si
        push    di
        mov     si, kval
        movsw
        movsw
        movsw
        movsw
        pop     di
        pop     si
        clc
.x:     ret

; pr = pb ^ pn (pn >= 0), per quadrats; CF=1 si desborda
potencia:
        mov     si, milio
        mov     di, pr
        movsw
        movsw
        movsw
        movsw
        mov     si, pb
        mov     di, pq
        movsw
        movsw
        movsw
        movsw
        mov     ax, [pn]
.l:     or      ax, ax
        jz      .x
        shr     ax, 1
        push    ax
        jnc     .q
        mov     di, pr
        mov     si, pq
        call    mulx
        jc      .e
.q:     pop     ax
        or      ax, ax
        jz      .x
        push    ax
        mov     di, pq
        mov     si, pq
        call    mulx
        jc      .e
        pop     ax
        jmp     .l
.x:     clc
        ret
.e:     pop     ax
        stc
        ret

; kval = kval ^ kx
m_pot:  mov     si, kval
        mov     di, pb
        movsw
        movsw
        movsw
        movsw
        call    intx
        jc      .e
        mov     [pn], ax
        call    potencia
        jc      .e
        cmp     byte [psg], 0
        je      .p
        mov     ax, [pr]                ; exponent negatiu: 1 / pr
        or      ax, [pr+2]
        or      ax, [pr+4]
        or      ax, [pr+6]
        jz      .e
        mov     si, milio
        mov     di, kval
        movsw
        movsw
        movsw
        movsw
        mov     si, pr
        mov     di, kx
        movsw
        movsw
        movsw
        movsw
        jmp     m_div
.p:     mov     si, pr
        mov     di, kval
        movsw
        movsw
        movsw
        movsw
        clc
        ret
.e:     stc
        ret

; kval = arrel kx-esima de kval (per bisseccio: lo^n <= a < hi^n)
m_arr:  mov     si, kval
        mov     di, pa
        movsw
        movsw
        movsw
        movsw
        call    intx
        jc      .e
        cmp     byte [psg], 0
        jne     .e
        or      ax, ax
        jz      .e
        mov     [pn], ax
        mov     byte [pneg], 0
        test    byte [pa+7], 80h        ; a negativa: nomes amb n senar
        jz      .p
        test    al, 1
        jz      .e
        mov     di, pa
        call    neg4
        inc     byte [pneg]
.p:     xor     ax, ax                  ; lo = 0, hi = max(a, 1) + 1
        mov     di, plo
        mov     cx, 4
        rep     stosw
        mov     si, pa
        mov     di, phi
        movsw
        movsw
        movsw
        movsw
        mov     si, pa                  ; a < 1: hi = 1
        mov     di, pq
        movsw
        movsw
        movsw
        movsw
        mov     si, milio
        mov     di, pq
        call    m_sub
        test    byte [pq+7], 80h
        jz      .h
        mov     si, milio
        mov     di, phi
        movsw
        movsw
        movsw
        movsw
.h:     add     word [phi], 1
        adc     word [phi+2], 0
        adc     word [phi+4], 0
        adc     word [phi+6], 0
.b:     mov     si, phi                 ; mentre hi - lo > 1
        mov     di, pb
        movsw
        movsw
        movsw
        movsw
        mov     si, plo
        mov     di, pb
        call    m_sub
        mov     ax, [pb+2]
        or      ax, [pb+4]
        or      ax, [pb+6]
        jnz     .m
        cmp     word [pb], 1
        jbe     .f
.m:     mov     si, plo                 ; mig = (lo + hi) / 2
        mov     di, pb
        movsw
        movsw
        movsw
        movsw
        mov     ax, [phi]
        add     [pb], ax
        mov     ax, [phi+2]
        adc     [pb+2], ax
        mov     ax, [phi+4]
        adc     [pb+4], ax
        mov     ax, [phi+6]
        adc     [pb+6], ax
        rcr     word [pb+6], 1
        rcr     word [pb+4], 1
        rcr     word [pb+2], 1
        rcr     word [pb], 1
        call    potencia                ; mig ^ n
        jc      .gr                     ; massa gran
        mov     si, pa                  ; a - mig^n >= 0?
        mov     di, pq
        movsw
        movsw
        movsw
        movsw
        mov     si, pr
        mov     di, pq
        call    m_sub
        test    byte [pq+7], 80h
        jnz     .gr
        mov     si, pb                  ; lo = mig
        mov     di, plo
        jmp     short .c
.gr:    mov     si, pb                  ; hi = mig
        mov     di, phi
.c:     movsw
        movsw
        movsw
        movsw
        jmp     .b
.f:     mov     si, plo
        mov     di, kval
        movsw
        movsw
        movsw
        movsw
        cmp     byte [pneg], 0
        je      .x
        mov     di, kval
        call    neg4
.x:     clc
        ret
.e:     stc
        ret

; --- aritmetica de 64 bits (4 paraules) amb signe ---
neg4:   not     word [di]               ; DI = -DI
        not     word [di+2]
        not     word [di+4]
        not     word [di+6]
        add     word [di], 1
        adc     word [di+2], 0
        adc     word [di+4], 0
        adc     word [di+6], 0
        ret

m_add:  mov     ax, [si]                ; [DI] += [SI]; CF=1 si desborda
        add     [di], ax
        mov     ax, [si+2]
        adc     [di+2], ax
        mov     ax, [si+4]
        adc     [di+4], ax
        mov     ax, [si+6]
        adc     [di+6], ax
.o:     jo      .e
        clc
        ret
.e:     stc
        ret

m_sub:  mov     ax, [si]                ; [DI] -= [SI]
        sub     [di], ax
        mov     ax, [si+2]
        sbb     [di+2], ax
        mov     ax, [si+4]
        sbb     [di+4], ax
        mov     ax, [si+6]
        sbb     [di+6], ax
        jmp     m_add.o

; kval *= kx: |a| * |b| / 1000000
m_mul:  mov     byte [ksig], 0
        mov     si, kval
        mov     di, wa
        call    carrega
        mov     si, kx
        mov     di, wb
        call    carrega
        call    umul
        mov     si, milio
        mov     di, wb
        call    carrega
        jmp     short m_fi

; kval /= kx: |a| * 1000000 / |b|
m_div:  mov     ax, [kx]
        or      ax, [kx+2]
        or      ax, [kx+4]
        or      ax, [kx+6]
        jnz     .ok
        stc
        ret
.ok:    mov     byte [ksig], 0
        mov     si, kval
        mov     di, wa
        call    carrega
        mov     si, milio
        mov     di, wb
        call    carrega
        call    umul
        mov     si, kx
        mov     di, wb
        call    carrega
m_fi:   call    udiv                    ; wp /= wb
        mov     ax, [wp+8]              ; hi cap en 63 bits?
        or      ax, [wp+10]
        or      ax, [wp+12]
        or      ax, [wp+14]
        jnz     .e
        test    byte [wp+7], 80h
        jnz     .e
        mov     si, wp
        mov     di, kval
        movsw
        movsw
        movsw
        movsw
        cmp     byte [ksig], 0
        je      .x
        mov     di, kval
        call    neg4
.x:     clc
        ret
.e:     stc
        ret

; [SI] (64 bits, amb signe) -> |[SI]| a [DI] (128 bits); el signe a ksig
carrega:
        push    di
        movsw
        movsw
        movsw
        movsw
        xor     ax, ax
        stosw
        stosw
        stosw
        stosw
        pop     di
        test    byte [di+7], 80h
        jz      .x
        xor     byte [ksig], 1
        jmp     neg4
.x:     ret

; wp = wa * wb (128 bits, wb de 64)
umul:   xor     ax, ax
        mov     di, wp
        mov     cx, 8
        rep     stosw
        mov     cx, 64
.l:     push    cx
        mov     di, wb
        clc
        call    w_rcr
        jnc     .s
        mov     di, wp
        mov     si, wa
        call    w_add
.s:     mov     di, wa
        clc
        call    w_rcl
        pop     cx
        loop    .l
        ret

; wp = wp / wb, residu a wr (128 bits)
udiv:   xor     ax, ax
        mov     di, wr
        mov     cx, 8
        rep     stosw
        mov     cx, 128
.l:     push    cx
        mov     di, wp
        clc
        call    w_rcl
        mov     di, wr
        call    w_rcl
        mov     si, wr
        mov     di, wt
        mov     cx, 8
        rep     movsw
        mov     di, wt
        mov     si, wb
        clc
        call    w_sbb
        jc      .s
        mov     si, wt
        mov     di, wr
        mov     cx, 8
        rep     movsw
        or      byte [wp], 1
.s:     pop     cx
        loop    .l
        ret

w_rcl:  mov     cx, 8                   ; [DI] (8 paraules) <<= 1, amb CF
.l:     rcl     word [di], 1
        inc     di
        inc     di
        loop    .l
        ret

w_rcr:  add     di, 14                  ; [DI] >>= 1 (entra un 0)
        clc
        mov     cx, 8
.l:     rcr     word [di], 1
        dec     di
        dec     di
        loop    .l
        ret

w_add:  mov     cx, 8                   ; [DI] += [SI] (CF a 0 abans)
        clc
.l:     lodsw
        adc     [di], ax
        inc     di
        inc     di
        loop    .l
        ret

w_sbb:  mov     cx, 8                   ; [DI] -= [SI]; CF=1 si [SI] > [DI]
.l:     lodsw
        sbb     [di], ax
        inc     di
        inc     di
        loop    .l
        ret

; =====================================================================
;  Rutines auxiliars
; =====================================================================
posa_wh:
        mov     ax, [whandle]
        mov     [int_in], ax
        ret

; ---------------------------------------------------------------------
;  Shell de DOS (segona entrada del menu)
; ---------------------------------------------------------------------
shell:
        mov     word [int_in], 1        ; wind_update(BEG_UPDATE)
        AES     107,1,1,0,0
        mov     word [int_in], 256      ; graf_mouse(M_OFF)
        call    ratoli

        mov     bx, 0FFFFh              ; hi ha memoria de DOS lliure?
        mov     ah, 48h
        int     21h
        cmp     bx, MINPARAS
        jae     .mem
        mov     ax, bx                  ; no: alerta amb els KB lliures
        mov     cl, 6
        shr     ax, cl
        mov     di, al_kb
        call    dec3k
        mov     word [int_in], 1        ; boto per defecte
        mov     word [addr_in], alerta
        mov     [addr_in+2], ds
        AES     52,1,1,1,0              ; form_alert
        jmp     .surt

.mem:   call    comspec
        call    desa_menu               ; la barra de menus, a la memoria
        VDIS    5,0,0,3                 ; v_enter_cur: mode text
        mov     dx, t_ini
        mov     ah, 9
        int     21h

        mov     [sv_sp], sp             ; EXEC de COMMAND.COM
        mov     [sv_ss], ss
        mov     [pb_tail+2], ds
        mov     [pb_f1+2], ds
        mov     [pb_f2+2], ds
        mov     dx, cami
        mov     bx, pblock
        mov     ax, 4B00h
        int     21h
        cli
        mov     bx, cs
        mov     ss, bx
        mov     sp, [cs:sv_sp]
        mov     ds, bx
        mov     es, bx
        sti
        cld
        jnc     .torna
        mov     dx, t_err               ; no s'ha pogut executar
        mov     ah, 9
        int     21h
        xor     ax, ax                  ; espera una tecla
        int     16h

.torna: VDIS    5,0,0,2                 ; v_exit_cur: mode grafic
        call    posa_menu
        mov     word [int_in], 0        ; area de l'escriptori
        mov     word [int_in+2], WF_WORKXYWH
        AES     104,2,5,0,0
        mov     word [int_in], 3        ; form_dial(FMD_FINISH): redibuixa
        mov     si, int_out+2
        mov     di, int_in+2
        mov     cx, 4
        rep     movsw
        mov     si, int_out+2
        mov     cx, 4
        rep     movsw
        AES     51,9,1,0,0

.surt:  mov     word [int_in], 257      ; graf_mouse(M_ON)
        call    ratoli
        mov     word [int_in], 0        ; wind_update(END_UPDATE)
        AES     107,1,1,0,0
        ret

ratoli: mov     word [addr_in], 0
        mov     word [addr_in+2], 0
        AES     78,1,1,1,0
        ret

; ---------------------------------------------------------------------
;  COMSPEC de l'entorn del proces actual -> cami (si no, C:\COMMAND.COM)
; ---------------------------------------------------------------------
comspec:
        push    ds
        push    es
        mov     ah, 51h                 ; PSP actual (DOS 2.0 o posterior)
        int     21h
        mov     es, bx
        mov     ax, [es:2Ch]
        or      ax, ax
        jz      .no
        mov     es, ax
        xor     di, di
.var:   cmp     byte [es:di], 0         ; final de l'entorn
        je      .no
        mov     si, k_comspec
        mov     bx, di
        mov     cx, 8
.cmp:   mov     al, [es:bx]
        cmp     al, [si]
        jne     .seg
        inc     bx
        inc     si
        loop    .cmp
        mov     si, bx                  ; trobat: copia el valor
        mov     di, cami
        mov     cx, 79
.cp:    mov     al, [es:si]
        mov     [di], al
        or      al, al
        jz      .ok
        inc     si
        inc     di
        loop    .cp
        mov     byte [di], 0
        jmp     short .ok
.seg:   mov     al, [es:di]             ; la variable seguent
        inc     di
        or      al, al
        jnz     .seg
        jmp     .var
.no:    mov     si, k_defecte
        mov     di, cami
.cd:    lodsb
        mov     [di], al
        inc     di
        or      al, al
        jnz     .cd
.ok:    pop     es
        pop     ds
        ret

; ---------------------------------------------------------------------
;  Barra de menus: es guarda abans del mode text i es torna a posar
;  despres (el GEM no la redibuixa amb form_dial). vro_cpyfm del VDI.
; ---------------------------------------------------------------------
alt_menu:                               ; -> menuh (linies), 0 si no cap
        mov     word [int_in], 0
        mov     word [int_in+2], WF_WORKXYWH
        AES     104,2,5,0,0
        mov     ax, [int_out+4]         ; y de l'escriptori = alt del menu
        mov     [menuh], ax
        mov     cx, [plans]             ; 80 bytes per linia i pla (640 px)
        mul     cx
        mov     cx, 80
        mul     cx
        or      dx, dx
        jnz     .no
        cmp     ax, MBMAX
        ja      .no
        add     ax, 15                  ; bloc de DOS per guardar-la
        mov     cl, 4
        shr     ax, cl
        mov     bx, ax
        mov     ah, 48h
        int     21h
        jc      .no
        mov     [mbseg], ax
        ret
.no:    mov     word [menuh], 0
        ret

mfdbs:  ; omple el MFDB de memoria i els punts (0,0)-(639,menuh-1)
        mov     word [mf_mem], 0
        mov     ax, [mbseg]
        mov     [mf_mem+2], ax
        mov     word [mf_mem+4], 640
        mov     ax, [menuh]
        mov     [mf_mem+6], ax
        mov     word [mf_mem+8], 40
        mov     word [mf_mem+10], 0
        mov     ax, [plans]
        mov     [mf_mem+12], ax
        mov     word [mf_scr], 0        ; pantalla: adreca 0
        mov     word [mf_scr+2], 0
        mov     di, ptsin
        mov     cx, 2
.p:     xor     ax, ax
        stosw
        stosw
        mov     ax, 639
        stosw
        mov     ax, [menuh]
        dec     ax
        stosw
        loop    .p
        mov     word [intin], 3         ; S_ONLY
        ret

desa_menu:
        call    alt_menu
        cmp     word [menuh], 0
        je      .x
        call    mfdbs
        mov     word [contrl+14], mf_scr
        mov     [contrl+16], ds
        mov     word [contrl+18], mf_mem
        mov     [contrl+20], ds
        VDIS    109,4,1,0               ; vro_cpyfm pantalla -> memoria
.x:     ret

posa_menu:
        cmp     word [menuh], 0
        je      .x
        call    mfdbs
        mov     word [contrl+14], mf_mem
        mov     [contrl+16], ds
        mov     word [contrl+18], mf_scr
        mov     [contrl+20], ds
        VDIS    109,4,1,0               ; vro_cpyfm memoria -> pantalla
        push    es
        mov     es, [mbseg]             ; allibera el bloc
        mov     ah, 49h
        int     21h
        pop     es
        mov     word [menuh], 0
.x:     ret

; AX (0-999) -> 3 caracters a [di], alineat a la dreta
dec3k:   mov     word [di], '  '
        mov     byte [di+2], ' '
        add     di, 2
        mov     bx, 10
        mov     cx, 3
.d:     xor     dx, dx
        div     bx
        add     dl, '0'
        mov     [di], dl
        dec     di
        or      ax, ax
        loopnz  .d
        ret

crida_aes:
        push    bx
        push    si
        push    di
        push    bp
        push    ds
        push    es
        mov     cx, 200                 ; AES: ES:BX -> bloc de parametres
        push    ds
        pop     es
        mov     bx, aespb
        int     0EFh
        pop     es
        pop     ds
        pop     bp
        pop     di
        pop     si
        pop     bx
        cld
        mov     ax, [int_out]
        ret

crida_vdi:
        push    bx
        push    si
        push    di
        push    bp
        push    ds
        push    es
        mov     cx, 473h                ; VDI: DS:DX -> bloc de parametres
        mov     dx, vdipb
        int     0EFh
        pop     es
        pop     ds
        pop     bp
        pop     di
        pop     si
        pop     bx
        cld
        ret

init_punters:                           ; segments dels blocs de parametres
        mov     ax, ds
        mov     bx, aespb+2
        mov     cx, 11
.l:     mov     [bx], ax
        add     bx, 4
        loop    .l
        ret

; =====================================================================
;  Dades (tot dins el fitxer: el GEM no dona memoria extra)
; =====================================================================
nom_menu: db '  Car', 85h, 'cters', 0
nom_shell: db '  Shell de DOS', 0
nom_calc:  db '  Calculadora', 0
nom_rell:  db '  Rellotge', 0
t_calc:    db ' Calculadora ', 0
t_rell:    db ' Rellotge ', 0
t_kerr:    db 'Error'
t_kl:      db ' C ', 'CE ', '<- ', ' ( ', ' ) '   ; (0.5) botons: 5 x 5
           db ' 7 ', ' 8 ', ' 9 ', '+/-', ' / '
           db ' 4 ', ' 5 ', ' 6 ', 'x^n', ' * '   ; (0.6) potencia, arrel i pi
           db ' 1 ', ' 2 ', ' 3 ', 'n', 0FBh, 'x', ' - '   ; (0.10) FBh: arrel, n" x
           db ' 0 ', ' . ', ' = ', 'pi ', ' + '
t_kc:      db 'C', 'E', 8, '()', '789N/', '456^*', '123R-', '0.=P+'
t_pi:      db '3.141593'
tdib:      dw dibuixa, dib_k, dib_r
tclic:     dw clic_c, clic_k, clic_r
ttec:      dw tecla_c, tec_k, tec_r
milio:     dw 4240h, 0Fh, 0, 0          ; 1000000
k_comspec: db 'COMSPEC='
k_defecte: db 'C:\COMMAND.COM', 0
t_ini:     db 'GEM - Shell de DOS.  Escriu EXIT per tornar al GEM.', 13, 10, '$'
t_err:     db 13, 10, 'No s', 27h, 'ha pogut executar COMMAND.COM (COMSPEC).', 13, 10
           db 'Prem una tecla per tornar al GEM.', 13, 10, '$'
alerta:    db '[3][Shell de DOS: no hi ha|prou mem', 95h, 'ria de DOS lliure.|'
           db 'Cal 28 KB; n', 27h, 'hi ha '
al_kb:     db '    KB.][ D', 27h, 'acord ]', 0

pblock:    dw 0                         ; entorn: el del proces actual
pb_tail:   dw tail, 0
pb_f1:     dw fcb, 0
pb_f2:     dw fcb, 0
tail:      db 0, 13
fcb:       db 0, '           ', 0, 0, 0, 0

titol:    db ' Car', 85h, 'cters ', 0
t_car:    db 'Car', 85h, 'cter: ', 0
t_dec:    db '   Codi: ', 0
t_hex:    db '   ', 0
t_cad:    db 'Cadena: ', 0
b_afe:    db ' Afegeix '
b_esb:    db ' Esborra '
b_env:    db ' Envia '
t_tecles: db 02h, '1234567890-=', 0
          db 10h, 'qwertyuiop[]', 0
          db 1Eh, 'asdfghjkl;', 27h, 60h, 0
          db 2Ch, 'zxcvbnm,./', 0
          db 39h, ' ', 0
          db 0
botons:   db 1, 9
          dw b_afe
          db 12, 9
          dw b_esb
          db 24, 7
          dw b_env
          db 0FFh

        align 2
aespb:  dw control,0, aesglob,0, int_in,0, int_out,0, addr_in,0, addr_out,0
vdipb:  dw contrl,0, intin,0, ptsin,0, intout,0, ptsout,0

control:  times 5   dw 0
aesglob:  times 15  dw 0
int_in:   times 16  dw 0
int_out:  times 8   dw 0
addr_in:  times 4   dw 0
addr_out: times 2   dw 0
contrl:   times 12  dw 0
intin:    times 48  dw 0               ; (0.4) nomes el que cal
ptsin:    times 16  dw 0
intout:   times 48  dw 0
ptsout:   times 16  dw 0
msgbuf:   times 8   dw 0

ap_id:    dw 0
menu_id:  dw 0
plans:    dw 1
menuh:    dw 0
sv_sp:    dw 0
sv_ss:    dw 0
mf_scr:   times 10 dw 0
mf_mem:   times 10 dw 0
cami:     times 80 db 0
mbseg:    dw 0
menu_id2: dw 0
vhandle:  dw 0
whandle:  dw -1
wtab:     dw -1, -1, -1                ; (0.4) Caracters, Calculadora, Rellotge
cur:      dw 0
ww:       dw 0
wtit:     dw 0
menu_id3: dw -1
menu_id4: dw -1
kpas:     dw 0
ky0:      dw 0
kcol:     db 0
kinv:     db 0
krect:    dw 0, 0, 0, 0
kval:     times 4 dw 0
kx:       times 4 dw 0
wa:       times 8 dw 0
wb:       times 8 dw 0
wp:       times 8 dw 0
wr:       times 8 dw 0
wt:       times 8 dw 0
nv:       db 0                         ; (0.5) valors a la pila
no:       db 0                         ; operacions a la pila
kpar:     db 0                         ; parentesis oberts
kkop:     db 0
psg:      db 0                         ; (0.6) potencia i arrel
pneg:     db 0
pn:       dw 0
pa:       times 4 dw 0
pb:       times 4 dw 0
pq:       times 4 dw 0
pr:       times 4 dw 0
plo:      times 4 dw 0
phi:      times 4 dw 0
kdalt:    dw 0
ops:      times KPILA db 0
vals:     times KPILA*8 db 0
knou:     db 1
kent:     db 0
kerr:     db 0
ksig:     db 0
kkey:     db 0
klen:     db 1
kbuf:     db '0'
          times 23 db 0
dig:      times 20 db 0
rtim:     times 20 db 0
alh:      db 7                         ; (0.5) alarma: hora, minut, engegada
alm:      db 0
alon:     db 0
wpos:     times 6 dw 0                 ; (0.7) x, y de cada finestra (0: per defecte)
aidx:     db 0
aview:    db 0
fons:     db 0
kvis:     db 0
wpar:     dw 0
t_un:     db 0
bx1x:     dw 0
nnota:    db 0
b_camp:   db 10h, 28h, 44h, 44h, 44h, 0FEh, 10h, 0FFh   ; (0.9) campaneta
t_bar:    db '   /    /   '
atxt:     db '00 : 00'
t_cfg:    db 'C:\GEMBOOT\EINES.CFG', 0
cfgbuf:   db 0FFh
          times 14 db 0
al_alar:  db '[1][Rellotge:| |alarma de les '
al_hora:  db '00:00][ D', 27h, 'acord ]', 0
rnou:     times 20 db 0
car_w:    dw 8
car_h:    dw 8
alt_fila: dw 10
fila:     db 0
sel:      db 'A'
slen:     db 0
blen:     db 0
compta:   db 0
        align 2
quins:    dw 0
mx:       dw 0
my:       dw 0
rx:       dw 0
ry:       dw 0
clics:    dw 0
tecla_k:  dw 0
ytop:     dw 0
y_info:   dw 0
y_cad:    dw 0
y_bot:    dw 0
bx1:      dw 0
bx2:      dw 0
by2:      dw 0
sbuf:     times SMAX db 0
tpn:      dw 0
tpbuf:    times SMAX*6 db 0
linia:    times 48 db 0
        align 2
escr:     times 4 dw 0
frect:    times 4 dw 0
treb:     times 4 dw 0
clip:     times 4 dw 0

        times 1024 db 0                 ; pila
pila_fi:
        align 16, db 0
MIDA    equ $-$$
