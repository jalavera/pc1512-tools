; =====================================================================
;  CHARMAP.ASM - Accessori d'escriptori GEM: mapa de caracters
;                (GEM 2.0, Amstrad PC1512).  Versio 0.7
;
;  Muntatge:   nasm -f bin CHARMAP.ASM -o CHARMAP.ACC
;  Us:         copiar CHARMAP.ACC a \GEMBOOT i tornar a entrar al GEM.
;
;  Entrada "Caracters" al menu d'accessoris. La finestra mostra els
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
        mov     ax, [vhandle]
        mov     [contrl+12], ax
        call    crida_vdi
%endmacro

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

; ---------------------------------------------------------------------
;  Bucle d'esdeveniments: un accessori no acaba mai
; ---------------------------------------------------------------------
bucle:
        mov     ax, 10h                 ; MU_MESAG
        cmp     word [whandle], 0
        jl      .f1
        or      ax, 03h                 ; MU_BUTTON i MU_KEYBD (oberta)
.f1:    mov     di, int_in
        stosw                           ; flags
        mov     ax, 1
        stosw                           ; 1 clic (el doble, el fem nosaltres)
        mov     ax, 1
        stosw                           ; boto esquerre
        stosw                           ; premut
        xor     ax, ax
        mov     cx, 10
        rep     stosw                   ; sense rectangles de ratoli
        mov     ax, 60
        stosw                           ; temporitzador: 60 ms
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
.e3:    jmp     bucle

; ---------------------------------------------------------------------
;  Missatges del GEM
; ---------------------------------------------------------------------
missatge:
        mov     ax, [msgbuf]
        cmp     ax, AC_OPEN
        jne     .n1
        jmp     obre
.n1:    cmp     ax, AC_CLOSE
        jne     .n2
        mov     word [whandle], -1      ; el GEM ja ha tancat la finestra
        ret
.n2:    mov     bx, [whandle]           ; la resta: nomes la nostra finestra
        or      bx, bx
        js      m_ret
        cmp     bx, [msgbuf+6]
        jne     m_ret
        cmp     ax, WM_REDRAW
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
        ret
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
        mov     word [int_in], 0        ; area util de l'escriptori
        mov     word [int_in+2], WF_WORKXYWH
        AES     104,2,5,0,0
        mov     si, int_out+2
        mov     di, escr
        mov     cx, 4
        rep     movsw

        ; mida de l'area de treball -> mida exterior (wind_calc)
        mov     word [int_in], 0        ; WC_BORDER
        mov     word [int_in+2], TIPUS_FIN
        mov     ax, [escr]
        add     ax, 40
        mov     [int_in+4], ax
        mov     ax, [escr+2]
        add     ax, 24
        mov     [int_in+6], ax
        mov     ax, COLS*2+2
        mul     word [car_w]
        mov     [int_in+8], ax
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
        mov     [int_in+10], ax
        AES     108,6,5,0,0
        mov     si, int_out+2
        mov     di, frect
        mov     cx, 4
        rep     movsw
        mov     ax, [escr+2]            ; enganxada a dalt de l'escriptori
        inc     ax
        mov     [frect+2], ax

        mov     word [int_in], TIPUS_FIN ; wind_create
        mov     si, escr
        mov     di, int_in+2
        mov     cx, 4
        rep     movsw
        AES     100,5,1,0,0
        or      ax, ax
        jns     .ok
        ret                             ; no queden finestres
.ok:    mov     [whandle], ax

        call    posa_wh                 ; wind_set(WF_NAME)
        mov     word [int_in+2], WF_NAME
        mov     word [int_in+4], titol
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
        call    dibuixa
.res:   ret

; Dibuixa, dins el rectangle de clip, nomes les parts que el toquen
dibuixa:
        mov     word [intin], 1         ; vs_clip(on)
        mov     si, clip
        mov     di, ptsin
        mov     cx, 4
        rep     movsw
        VDI     129,2,1
        mov     word [intin], 1         ; vswr_mode(substitucio)
        VDI     32,0,1
        mov     word [intin], 1         ; vsf_interior(solid)
        VDI     23,0,1
        mov     word [intin], 0         ; vsf_color(blanc)
        VDI     25,0,1
        mov     ax, [treb]              ; vr_recfl: fons blanc (retallat)
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

        mov     byte [fila], 0
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
        mov     word [intin], 1
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
        jc      .fi
        mov     si, botons
.b:     lodsb                           ; columna
        cmp     al, 0FFh
        je      .fi
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
        mov     si, ax
        mov     di, intin
        mov     cl, [blen]
        xor     ch, ch
        mov     [contrl+6], cx
.bt:    lodsb
        xor     ah, ah
        stosw
        loop    .bt
        mov     ax, [bx1]
        mov     [ptsin], ax
        mov     ax, [ytop]
        add     ax, [car_h]
        inc     ax
        mov     [ptsin+2], ax
        mov     word [contrl+0], 8      ; v_gtext
        mov     word [contrl+2], 1
        mov     ax, [vhandle]
        mov     [contrl+12], ax
        call    crida_vdi
        mov     ax, [ytop]              ; marc: v_pline de 5 punts
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
        pop     si
        jmp     .b

.fi:    mov     word [intin], 0         ; vs_clip(off)
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
clic:
        cmp     word [whandle], 0
        jge     .w
        ret
.w:     mov     ax, [mx]                ; el clic es a la nostra finestra?
        mov     [int_in], ax
        mov     ax, [my]
        mov     [int_in+2], ax
        AES     106,2,1,0,0             ; wind_find
        cmp     ax, [whandle]
        je      .meva
        ret
.meva:  call    deixa_anar              ; primer, amb la finestra oberta
        call    llegeix_treb
        mov     ax, [mx]
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
tecla:  cmp     word [whandle], 0
        jl      .x
        call    llegeix_treb
        mov     ax, [tecla_k]
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
franja: add     ax, [treb+2]
        mov     [msgbuf+10], ax
        mov     ax, [treb]
        mov     [msgbuf+8], ax
        mov     ax, [treb+4]
        mov     [msgbuf+12], ax
        mov     ax, [alt_fila]
        mov     [msgbuf+14], ax
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
;  Rutines auxiliars
; =====================================================================
posa_wh:
        mov     ax, [whandle]
        mov     [int_in], ax
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
intin:    times 128 dw 0
ptsin:    times 128 dw 0
intout:   times 128 dw 0
ptsout:   times 128 dw 0
msgbuf:   times 8   dw 0

ap_id:    dw 0
menu_id:  dw 0
vhandle:  dw 0
whandle:  dw -1
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
