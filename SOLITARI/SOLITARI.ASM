; =====================================================================
;  SOLITARI  -  Klondike per a GEM (Amstrad PC1512, GEM Desktop 2.0)
;
;  Compilar:  python3 build.py SOLITARI.ASM SOLITARI.APP   (requereix nasm)
;
;  - Joc 100% amb el ratoli: clic al munt per robar, arrossegar cartes o
;    escales de cartes, i un clic en una carta l'envia a les piles de dalt.
;  - Menus de GEM: Solitari (Quant a), Partida (Nova, Desfer, Sortir),
;    Opcions (robar 1 o 3, puntuacio estandard / Vegas / cap, so) i Ajuda.
;  - Punts i temps al titol de la finestra.
;  - Les cartes arrossegades es mouen escrivint directament a la memoria
;    de video del PC1512 (amb altres pantalles, un contorn del GEM).
;  - Cartes de 80x48 amb les figures del Vint-i-u Enhanced.
;  - Crides GEM:  AES -> INT EFh, CX=200, ES:BX   VDI -> CX=473h, DS:DX
; =====================================================================

%include "exe.inc"

; ---------- disposicio (pixels, relatius a l'origen del contingut) ----------
CARDW      equ 80                  ; carta: 10 bytes d'ample
CARDH      equ 48
W       equ 624                 ; amplada del contingut
COL0    equ 8                   ; primera columna
CSTEP   equ 88                  ; separacio de columnes (11 bytes)
TOPY    equ 3                   ; fila de dalt: munt, descartades, piles
TABY    equ TOPY + CARDH + 5       ; columnes
DOFF    equ 3                   ; desplacament de les cartes tapades
UOFF    equ 10                  ;   i de les destapades (es veu l'index)
WFANX   equ 16                  ; ventall de les descartades (robant 3)
NIMG    equ 55                  ; imatges a la memoria cau: 52 cares, dors, lloc buit, lloc amb cercle
IMG_DORS  equ 52
IMG_BUIT  equ 53
IMG_CERCLE equ 54
IMGPAR  equ CARDW/8*CARDH*4/16  ; paragrafs per imatge (4 plans)

; ---------- piles: 0 munt, 1 descartades, 2..5 piles de dalt, 6..12 columnes
NPILE   equ 13
PSZ     equ 53                  ; nombre de cartes + 52 cartes
P_STOCK equ 0
P_WASTE equ 1
P_FOUND equ 2
P_TAB   equ 6
TAPADA  equ 80h                 ; bit de carta de cara avall

; ---------- colors VDI ----------
BLANC   equ 0
NEGRE   equ 1
C_RED   equ 2
TAPET   equ 3
C_BLU   equ 4
GROC    equ 6
LSTRIDE equ FIG_MAXWD*FIG_MAXH*2    ; bytes d'una capa de figura

; ---------- GEM ----------
MU_BUTTON equ 2
MU_MESAG  equ 16
MU_TIMER  equ 32
MN_SELECTED equ 10
WM_REDRAW equ 20
WM_TOPPED equ 21
WM_CLOSED equ 22
WF_NAME   equ 2
WF_WORKXYWH  equ 4
WF_TOP       equ 10
WF_FIRSTXYWH equ 11
WF_NEXTXYWH  equ 12
TIPUS_FIN    equ 0003h          ; NAME | CLOSER (fixa: no es pot moure)

G_BOX    equ 20
G_IBOX   equ 25
G_STRING equ 28
G_TITLE  equ 32
LASTOB   equ 20h
DISABLED equ 8

; objectes del menu (vegeu menutree)
M_QUANT  equ 9
M_NOVA   equ 18
M_DESFER equ 19
M_PISTA  equ 20
M_SORTIR equ 22
M_R1     equ 24
M_R3     equ 25
M_PSTD   equ 27
M_PVEG   equ 28
M_PCAP   equ 29
M_BUIDA  equ 31
M_SO     equ 32
M_AJ1    equ 34
M_AJ2    equ 35
M_AJ3    equ 36

; video directe del PC1512
VSEG    equ 0B800h
P_WPLA  equ 3DDh
P_RPLA  equ 3DEh

; crides GEM compactes: un CALL seguit dels comptadors en bytes
%macro AES 5                    ; opcode, n_int_in, n_int_out, n_addr_in, n_addr_out
        call aes_t
        db %1, %2, %3, %4, %5
%endmacro

%macro VDI 3-4 0                ; opcode, n_ptsin, n_intin, subfuncio
        call vdi_t
        db %1, %2, %3, %4
%endmacro

; =====================================================================
inici:
        mov ax, cs
        mov ds, ax
        mov es, ax
        cld
        mov di, fi_imatge               ; posar la BSS a zero
        mov cx, fi_bss - fi_imatge
        xor al, al
        rep stosb
        mov byte [fig_cache], 0FFh      ; cap figura descomprimida
        call init_punters

        AES 10,0,1,0,0                  ; appl_init
        cmp ax, -1
        jne .g1
        jmp dos_fi
.g1:    AES 77,0,5,0,0                  ; graf_handle
        mov [vhandle], ax

        mov di, intin                   ; v_opnvwk
        mov cx, 10
        mov ax, 1
        rep stosw
        mov word [intin+20], 2
        VDI 100,0,11
        mov ax, [intout]                ; resolucio: 639 x 199 al PC1512
        mov [scr_xmax], ax
        mov ax, [intout+2]
        mov [scr_ymax], ax
        mov ax, [contrl+12]
        mov [vhandle], ax
        or ax, ax
        jnz .g2
        jmp aes_fi
.g2:
        mov word [intin], 2             ; vswr_mode(transparent)
        VDI 32,0,1
        mov word [intin], 0             ; vst_alignment(esquerra, dalt)
        mov word [intin+2], 5
        VDI 39,0,2
        mov word [intin], 1             ; vsf_perimeter(on)
        VDI 104,0,1

        mov si, bmlist                  ; pals: format estandard -> dispositiu
.bm:    mov bx, [si]
        or bx, bx
        jz .bmfi
        mov di, [si+2]
        mov [bx+2], ds
        mov [di+2], ds
        mov [contrl+14], bx
        mov [contrl+16], ds
        mov [contrl+18], di
        mov [contrl+20], ds
        VDI 110,0,0                     ; vr_trnfm
        add si, 4
        jmp .bm
.bmfi:
        mov word [intin], 1             ; vq_extnd: plans de color
        VDI 102,0,1
        mov ax, [intout+8]
        mov [vplanes], al               ; video directe: nomes 640x200, 1 o 4 plans
        cmp word [scr_xmax], 639
        jne .nodv
        cmp word [scr_ymax], 199
        jne .nodv
        cmp al, 1
        je .dv
        cmp al, 4
        jne .nodv
.dv:    mov byte [dvok], 1
.nodv:
        mov word [int_in], 0            ; graf_mouse(ARROW)
        mov word [addr_in], 0
        mov word [addr_in+2], 0
        AES 78,1,1,1,0

        call fes_menu                   ; barra de menus
        mov word [int_in], 1
        call tree_addr
        AES 30,1,1,1,0                  ; menu_bar(arbre, 1)
        call marca_opcions

        mov word [int_in], 0            ; area de l'escriptori
        mov word [int_in+2], WF_WORKXYWH
        AES 104,2,5,0,0
        mov si, int_out+2
        mov di, escr
        mov cx, 4
        rep movsw

        mov word [int_in], TIPUS_FIN    ; wind_create
        mov si, escr
        mov di, int_in+2
        mov cx, 4
        rep movsw
        AES 100,5,1,0,0
        or ax, ax
        jns .g4
        jmp vdi_fi
.g4:    mov [whandle], ax
        call titol_upd                  ; titol (abans d'obrir-la)
        call posa_wh                    ; wind_open: tota l'area de l'escriptori
        mov si, escr
        mov di, int_in+2
        mov cx, 4
        rep movsw
        AES 101,5,1,0,0
        call get_work
        call prepara                    ; imatges de les cartes per al dibuix directe

        call llavor
        call nova_partida

; ---------------------------------------------------------------------
;  Bucle principal: missatges (menus, redibuix), ratoli i rellotge
; ---------------------------------------------------------------------
bucle:  mov word [tmr], 1000
        mov ax, MU_MESAG | MU_BUTTON | MU_TIMER
        call evnt
        mov [quins], ax
        test ax, MU_MESAG
        jz .b
        call handle_msg
.b:     test word [quins], MU_BUTTON
        jz .t
        mov ax, [int_out+2]
        mov [mx0], ax
        mov ax, [int_out+4]
        mov [my0], ax
        call rnd                        ; (el moment del clic remena l'atzar)
        call premut
.t:     call rellotge
        jmp bucle

; =====================================================================
;  MISSATGES I MENUS
; =====================================================================
handle_msg:
        mov ax, [msgbuf]
        cmp ax, MN_SELECTED
        jne .fin
        mov ax, [msgbuf+6]              ; tornar el titol del menu a normal
        mov [int_in], ax
        mov word [int_in+2], 1
        call tree_addr
        AES 33,2,1,1,0                  ; menu_tnormal
        mov ax, [msgbuf+8]              ; l'opcio triada
        mov si, menu_tab
.m:     mov dx, [si]
        or dx, dx
        jz .r
        cmp ax, dx
        je .crida
        add si, 4
        jmp .m
.crida: jmp [si+2]
.fin:   mov ax, [msgbuf+6]
        cmp ax, [whandle]
        jne .r
        mov ax, [msgbuf]
        cmp ax, WM_REDRAW
        jne .t
        mov si, msgbuf+8
        mov di, rr
        mov cx, 4
        rep movsw
        jmp redraw
.t:     cmp ax, WM_TOPPED
        jne .c
        call posa_wh
        mov word [int_in+2], WF_TOP
        mov word [int_in+4], 0
        mov word [int_in+6], 0
        mov word [int_in+8], 0
        mov word [int_in+10], 0
        AES 105,6,1,0,0
        ret
.c:     cmp ax, WM_CLOSED
        jne .r
        jmp demana_sortir
.r:     ret

; ---- accions del menu
m_quant: mov si, al_quant
        mov ax, 1
        jmp alerta
m_surt:
demana_sortir:
        mov ax, 2                       ; per defecte: Continuar
        mov si, al_sortir
        call alerta
        cmp ax, 1
        je .s
        ret
.s:     jmp sortir
; ---- partida nova des del menu: demana confirmacio si n'hi ha una en curs
m_nova: call confirma_nova
        jne .r
        jmp nova_partida
.r:     ret
confirma_nova:                          ; ZF=1 si es pot comencar
        cmp byte [fi], 0                ; partida acabada: no cal preguntar
        jne .si
        mov ax, 2                       ; per defecte: Continuar
        mov si, al_nova
        call alerta
        cmp ax, 1
        ret
.si:    cmp al, al
        ret

m_r1:   mov byte [draw3], 0
        jmp marca_opcions
m_r3:   mov byte [draw3], 1
        jmp marca_opcions
m_pstd: mov al, 0
        jmp short canvia_punts
m_pveg: mov al, 1
        jmp short canvia_punts
m_pcap: mov al, 2
canvia_punts:                           ; una puntuacio nova vol una partida nova
        cmp al, [modep]
        je .r
        push ax
        call confirma_nova
        pop ax
        jne .r
        mov [modep], al
        call marca_opcions
        jmp nova_partida
.r:     ret
m_so:   xor byte [so], 1
        jmp marca_opcions
m_buida: xor byte [buidaq], 1
        jmp marca_opcions
m_aj1:  mov si, al_aj1                  ; com es juga: 4 pagines
        call pagina
        jne .r
        mov si, al_aj2
        call pagina
        jne .r
        mov si, al_aj3
        call pagina
        jne .r
        mov si, al_aj4
        mov ax, 1
        jmp alerta
.r:     ret
m_aj2:  mov si, al_pt1                  ; puntuacio: 3 pagines
        call pagina
        jne .r
        mov si, al_pt2
        call pagina
        jne .r
        mov si, al_pt3
        mov ax, 1
        jmp alerta
.r:     ret
m_aj3:  mov si, al_ratoli
        mov ax, 1
        jmp alerta
pagina: mov ax, 1                       ; ZF=1 si s'ha triat "Seguent"
        call alerta
        cmp ax, 1
        ret

tree_addr:
        mov word [addr_in], menutree
        mov [addr_in+2], ds
        ret

; ---- fes_menu: segments dels textos i coordenades (rsrc_obfix)
fes_menu:
        mov si, menutree
        xor bx, bx
.l:     mov al, [si+6]                  ; ob_type
        cmp al, G_STRING
        je .seg
        cmp al, G_TITLE
        jne .fix
.seg:   mov [si+14], ds                 ; ob_spec: segment del text
.fix:   mov [int_in], bx
        call tree_addr
        push si
        push bx
        AES 114,1,1,1,0                 ; rsrc_obfix
        pop bx
        pop si
        test byte [si+8], LASTOB
        jnz .fi
        add si, 24
        inc bx
        jmp .l
.fi:    ret

; ---- marques de les opcions i "Desfer" actiu o no
marca_opcions:
        mov bx, M_R1
        mov al, [draw3]
        xor al, 1
        call chk
        mov bx, M_R3
        mov al, [draw3]
        call chk
        mov bx, M_PSTD
        mov ah, 0
        call chk_eq
        mov bx, M_PVEG
        mov ah, 1
        call chk_eq
        mov bx, M_PCAP
        mov ah, 2
        call chk_eq
        mov bx, M_SO
        mov al, [so]
        call chk
        mov bx, M_BUIDA
        mov al, [buidaq]
        call chk
        mov bx, M_DESFER
        mov al, [undo_ok]
        mov [int_in], bx
        xor ah, ah
        mov [int_in+2], ax
        call tree_addr
        AES 32,2,1,1,0                  ; menu_ienable
        ret
chk_eq: xor al, al
        cmp ah, [modep]
        jne chk
        inc al
chk:    mov [int_in], bx                ; menu_icheck(BX, AL)
        xor ah, ah
        mov [int_in+2], ax
        call tree_addr
        AES 31,2,1,1,0
        ret

; ---- sortida
sortir: call so_off
        mov word [int_in], 0            ; treure la barra de menus
        call tree_addr
        AES 30,1,1,1,0
        call posa_wh
        AES 102,1,1,0,0                 ; wind_close
        call posa_wh
        AES 103,1,1,0,0                 ; wind_delete
vdi_fi: VDI 101,0,0                     ; v_clsvwk
aes_fi: AES 19,0,1,0,0                  ; appl_exit
dos_fi: mov ax, 4C00h
        int 21h

; ---- area de treball; el contingut es centra i s'alinea a byte
get_work:
        call posa_wh
        mov word [int_in+2], WF_WORKXYWH
        AES 104,2,5,0,0
        mov ax, [int_out+2]
        mov [wkx], ax
        mov ax, [int_out+4]
        mov [wky], ax
        mov ax, [int_out+6]
        mov [workw], ax
        mov ax, [int_out+8]
        mov [workh], ax
        mov ax, [workw]
        sub ax, W
        sar ax, 1
        jns .x
        xor ax, ax
.x:     add ax, [wkx]
        add ax, 7
        and ax, 0FFF8h
        mov [ox], ax
        sub ax, [wkx]
        mov [marg_x], ax
        mov ax, [wky]
        mov [oy], ax
        mov word [marg_y], 0
        mov ax, [workh]                 ; espai per al ventall de les columnes
        sub ax, TABY + CARDH + 2
        mov [avail], ax
        ret

; =====================================================================
;  EL JOC
; =====================================================================
; padr: AL = pila -> BX = adreca (n, cartes...)
padr:   push ax
        xor ah, ah
        mov bl, PSZ
        mul bl
        add ax, piles
        mov bx, ax
        pop ax
        ret
; push_bx: posa AL dalt de la pila BX
push_bx:
        push si
        push ax
        mov si, bx
        mov al, [si]
        xor ah, ah
        add si, ax
        pop ax
        mov [si+1], al
        inc byte [bx]
        pop si
        ret
; pop_bx: AL = carta de dalt de la pila BX (la treu)
pop_bx: push si
        mov si, bx
        mov al, [si]
        xor ah, ah
        add si, ax
        mov al, [si]
        dec byte [bx]
        pop si
        ret
; carta_k: BX = pila, AL = index -> AL = carta
carta_k:                                ; (conserva AH)
        push si
        push ax
        mov si, bx
        xor ah, ah
        add si, ax
        pop ax
        mov al, [si+1]
        pop si
        ret

; ---- partida nova: barrejar i repartir
nova_partida:
        mov di, estat
        mov cx, ESTAT_SZ
        xor al, al
        rep stosb
        xor bx, bx
.i:     mov [deck+bx], bl
        inc bx
        cmp bx, 52
        jb .i
        mov bx, 51                      ; Fisher-Yates
.s:     call rnd
        push ax
        call rnd
        pop dx
        mov ah, dl
        xor dx, dx
        mov cx, bx
        inc cx
        div cx
        mov si, dx
        mov al, [deck+bx]
        xchg al, [deck+si]
        mov [deck+bx], al
        dec bx
        jnz .s
        xor si, si                      ; repartir: columna c rep c+1 cartes
        xor cx, cx
.c:     mov al, P_TAB
        add al, cl
        call padr
        xor dl, dl
.j:     mov al, [deck+si]
        inc si
        cmp dl, cl
        je .up
        or al, TAPADA
.up:    call push_bx
        inc dl
        cmp dl, cl
        jbe .j
        inc cl
        cmp cl, 7
        jb .c
        mov al, P_STOCK                 ; la resta, al munt
        call padr
.st:    mov al, [deck+si]
        or al, TAPADA
        call push_bx
        inc si
        cmp si, 52
        jb .st
        cmp byte [modep], 1
        jne .z
        mov word [score], -52           ; Vegas: comences devent la baralla
.z:     mov byte [jugant], 0
        mov word [secs], 0
        mov word [deu_s], 0
        mov byte [fi], 0
        mov byte [undo_ok], 0
        call marca_opcions
        call s_recicla
        call inval_tot
        jmp titol_upd

; ---- regles
; can_tab: AL = carta, BL = columna -> CF=0 si s'hi pot posar
can_tab:
        push ax
        push bx
        push si
        mov ah, al
        mov al, bl
        call padr
        mov cl, [bx]
        or cl, cl
        jnz .nb
        cmp byte [buidaq], 0            ; columna buida: qualsevol carta
        jne .si                         ; (opcio) o nomes un rei
        mov bl, ah
        xor bh, bh
        cmp byte [rank_of+bx], 12
        je .si
        jmp short .no
.nb:    mov al, cl
        dec al
        call carta_k                    ; AL = carta de dalt
        test al, TAPADA
        jnz .no
        mov bl, al
        xor bh, bh
        mov si, bx                      ; SI = dalt
        mov bl, ah
        mov al, [suit_of+si]            ; colors diferents
        xor al, [suit_of+bx]
        test al, 1
        jz .no
        mov al, [rank_of+si]            ; valor una unitat mes alt
        dec al
        cmp al, [rank_of+bx]
        jne .no
.si:    clc
        jmp short .fi
.no:    stc
.fi:    pop si
        pop bx
        pop ax
        ret

; can_found: AL = carta, BL = pila de dalt -> CF=0 si s'hi pot posar
can_found:
        push ax
        push bx
        push si
        push di
        mov ah, al
        mov al, bl
        call padr
        mov di, bx                      ; DI = pila
        mov bl, ah
        xor bh, bh
        mov si, bx                      ; SI = carta
        mov cl, [di]
        or cl, cl
        jnz .nb
        cmp byte [rank_of+si], 0        ; buida: nomes un as
        je .si
        jmp short .no
.nb:    mov bx, di
        mov al, cl
        dec al
        call carta_k
        xor ah, ah
        mov bx, ax                      ; BX = carta de dalt
        mov al, [suit_of+bx]
        cmp al, [suit_of+si]
        jne .no
        mov al, [rank_of+bx]
        inc al
        cmp al, [rank_of+si]
        jne .no
.si:    clc
        jmp short .fi
.no:    stc
.fi:    pop di
        pop si
        pop bx
        pop ax
        ret

; valid_moure: [m_src], [m_k] -> [m_dst]. CF=0 si es valid
valid_moure:
        mov al, [m_dst]
        cmp al, [m_src]
        je .no
        mov al, [m_src]
        call padr
        mov cl, [bx]
        sub cl, [m_k]                   ; nombre de cartes
        mov al, [m_k]
        call carta_k
        mov bl, [m_dst]
        cmp bl, P_TAB
        jae .tab
        cmp bl, P_FOUND
        jb .no
        cmp cl, 1
        jne .no
        jmp can_found
.tab:   jmp can_tab
.no:    stc
        ret

; fer_moure: mou les cartes [m_k].. de [m_src] a [m_dst]; punts i girar
fer_moure:
        mov al, [m_src]
        call padr
        mov si, bx
        mov al, [m_dst]
        call padr
        mov di, bx
        mov cl, [si]
        sub cl, [m_k]
        xor ch, ch
        mov [mcnt], cl
        push si
        push di
        mov al, [m_k]
        xor ah, ah
        add si, ax
        inc si                          ; SI = primera carta que es mou
        mov al, [di]
        add di, ax
        inc di                          ; DI = lloc lliure a la pila desti
        rep movsb
        pop di
        pop si
        mov al, [mcnt]
        add [di], al
        mov al, [m_k]
        mov [si], al
        cmp byte [m_src], P_WASTE       ; el ventall de les descartades
        jne .p
        cmp byte [wfan], 0
        je .p
        dec byte [wfan]
.p:     call punts_moure
        mov byte [girada], 0
        cmp byte [m_src], P_TAB         ; girar la carta que queda al descobert
        jb .r
        mov al, [m_src]
        call padr
        mov cl, [bx]
        or cl, cl
        jz .r
        xor ch, ch
        mov si, bx
        add si, cx
        test byte [si], TAPADA
        jz .r
        and byte [si], 7Fh
        mov byte [girada], 1
        cmp byte [modep], 0
        jne .r
        mov ax, 5
        call suma
.r:     jmp engega

; punts d'un moviment
punts_moure:
        mov al, [m_src]
        mov ah, [m_dst]
        cmp byte [modep], 1
        je .vegas
        ja .r
        cmp al, P_WASTE                 ; estandard
        jne .e2
        cmp ah, P_TAB
        jb .e2
        mov ax, 5                       ; descartades -> columna
        jmp suma
.e2:    cmp ah, P_FOUND
        jb .e3
        cmp ah, P_TAB
        jae .e3
        cmp al, P_FOUND                 ; cap a dalt (no d'una pila de dalt)
        jb .deu
        cmp al, P_TAB
        jb .r
.deu:   mov ax, 10
        jmp suma
.e3:    cmp al, P_FOUND                 ; de dalt a una columna
        jb .r
        cmp al, P_TAB
        jae .r
        mov ax, -15
        jmp suma
.vegas: cmp ah, P_FOUND
        jb .v2
        cmp ah, P_TAB
        jae .v2
        cmp al, P_FOUND
        jb .cinc
        cmp al, P_TAB
        jb .r
.cinc:  mov ax, 5
        jmp suma
.v2:    cmp al, P_FOUND
        jb .r
        cmp al, P_TAB
        jae .r
        mov ax, -5
        jmp suma
.r:     ret

; suma: AX = punts (la puntuacio estandard no baixa de zero)
suma:   add [score], ax
        cmp byte [modep], 0
        jne .r
        cmp word [score], 0
        jge .r
        mov word [score], 0
.r:     ret

; engega el rellotge al primer moviment
engega: cmp byte [jugant], 0
        jne .r
        cmp byte [fi], 0
        jne .r
        mov byte [jugant], 1
        call ticks
        mov [t0], ax
.r:     ret

; ---- robar del munt, o girar les descartades quan el munt es buit
robar:  call snap_tmp                   ; (abans de llegir les piles: fa servir CX)
        mov al, P_STOCK
        call padr
        mov cl, [bx]
        or cl, cl
        jz .reci
        mov dl, 1
        cmp byte [draw3], 0
        je .k
        mov dl, 3
.k:     cmp dl, cl
        jbe .k2
        mov dl, cl
.k2:    mov [wfan], dl
        xor dh, dh
        mov cx, dx
.m:     mov al, P_STOCK
        call padr
        call pop_bx
        and al, 7Fh
        push ax
        mov al, P_WASTE
        call padr
        pop ax
        call push_bx
        loop .m
        call commit
        call engega
        call s_robar
        jmp inval_dalt
.reci:  mov al, P_WASTE
        call padr
        mov cl, [bx]
        or cl, cl
        jz .r
        push cx
        call pot_reciclar
        pop cx
        jc .no
        xor ch, ch
.w:     mov al, P_WASTE
        call padr
        call pop_bx
        or al, TAPADA
        push ax
        mov al, P_STOCK
        call padr
        pop ax
        call push_bx
        loop .w
        mov byte [wfan], 0
        inc byte [passes]
        cmp byte [modep], 0             ; penalitzacio estandard
        jne .c
        mov ax, -100
        cmp byte [draw3], 0
        je .pen
        cmp byte [passes], 3
        jb .c
        mov ax, -20
.pen:   call suma
.c:     call commit
        call s_recicla
        jmp inval_dalt
.no:    jmp s_error
.r:     ret

; pot_reciclar: CF=0 si es pot tornar a girar el munt
pot_reciclar:
        push bx
        mov al, P_WASTE
        call padr
        cmp byte [bx], 0
        pop bx
        je .no
        cmp byte [modep], 1
        jne .si
        cmp byte [draw3], 0             ; Vegas robant 1: una sola passada
        je .no
        cmp byte [passes], 2            ; Vegas robant 3: tres passades
        jae .no
.si:    clc
        ret
.no:    stc
        ret

; =====================================================================
;  PISTA: busca una jugada util i la fa parpellejar
; =====================================================================
m_pista:
        cmp byte [fi], 0
        jne .r
        call cerca
        jc .cap
        call mostra_pista
.r:     ret
.cap:   call s_error
        mov si, al_nopista
        mov ax, 1
        jmp alerta

; cerca: CF=0 i [m_src],[m_k],[m_dst] (m_src = munt: robar), CF=1 si no hi ha res
cerca:  mov byte [cs_src], P_WASTE      ; a) una carta de dalt a les piles de dalt
.a:     mov al, [cs_src]
        call padr
        mov al, [bx]
        or al, al
        jz .an
        dec al
        mov [m_k], al
        call carta_k
        test al, TAPADA
        jnz .an
        mov bl, P_FOUND
.af:    call can_found
        jnc .troba
        inc bl
        cmp bl, P_TAB
        jb .af
.an:    call seguent_src
        jnc .a
        mov byte [cs_src], P_TAB        ; b) escales que destapen una carta
.b:     mov al, [cs_src]
        call padr
        mov cl, [bx]
        or cl, cl
        jz .bn
        xor ch, ch                      ; k = primera destapada
        xor dx, dx
        mov si, bx
        inc si
.bk:    test byte [si], TAPADA
        jz .bk2
        inc dx
        inc si
        cmp dx, cx
        jb .bk
        jmp short .bn
.bk2:   mov [m_k], dl
        mov al, [si]                    ; AL = carta
        mov bl, P_TAB
.bd:    cmp bl, [cs_src]
        je .bdn
        push ax
        push bx
        mov al, bl
        call padr
        mov cl, [bx]                    ; CL = cartes del desti
        pop bx
        pop ax
        cmp byte [m_k], 0
        jne .bok                        ; destapa una carta: util
        or cl, cl
        jz .bdn                         ; tota la columna a una buida: no
        mov dl, al                      ; tota la columna sobre una altra:
        and dl, 3Fh                     ; util si no es un rei
        push bx
        mov bl, dl
        xor bh, bh
        cmp byte [rank_of+bx], 12
        pop bx
        je .bdn
.bok:   call can_tab
        jnc .troba
.bdn:   inc bl
        cmp bl, P_TAB + 7
        jb .bd
.bn:    inc byte [cs_src]
        cmp byte [cs_src], P_TAB + 7
        jb .b
        mov al, P_WASTE                 ; c) descartades a una columna
        mov [cs_src], al
        call padr
        mov al, [bx]
        or al, al
        jz .d
        dec al
        mov [m_k], al
        call carta_k
        mov bl, P_TAB
.c:     call can_tab
        jnc .troba
        inc bl
        cmp bl, P_TAB + 7
        jb .c
.d:     mov byte [m_src], P_STOCK       ; d) robar del munt
        mov al, P_STOCK
        call padr
        cmp byte [bx], 0
        jne .ok
        call pot_reciclar
        jnc .ok
        stc
        ret
.troba: mov [m_dst], bl
        mov al, [cs_src]
        mov [m_src], al
.ok:    clc
        ret

seguent_src:                            ; descartades i despres les 7 columnes
        mov al, [cs_src]                ; CF=1 quan s'acaben
        cmp al, P_WASTE
        jne .t
        mov al, P_TAB - 1
.t:     inc al
        mov [cs_src], al
        cmp al, P_TAB + 7
        cmc
        ret

; mostra_pista: l'origen i el desti parpellegen tres vegades (inversio directa)
mostra_pista:
        cmp byte [dvok], 0
        je .nv
        call som_dalt
        je .v
.nv:    mov si, al_pista                ; sense video directe: nomes un avis
        mov ax, 1
        jmp alerta
.v:     call lock_ini
        mov byte [cel_n], 6
.l:     call pista_rects
        mov ax, 4                       ; uns 220 ms
        call espera_t
        dec byte [cel_n]
        jnz .l
        jmp lock_fi

; pista_rects: inverteix el rectangle d'origen i el de desti
pista_rects:
        mov al, [m_src]
        cmp al, P_STOCK
        jne .w
        mov ax, COL0                    ; munt
        mov bx, TOPY
        mov dx, CARDH
        jmp inv_rect
.w:     cmp al, P_WASTE
        jne .t
        call padr
        mov al, [bx]
        call fan_eff
        dec al
        mov cl, WFANX
        mul cl
        add ax, COL0 + CSTEP
        mov bx, TOPY
        mov dx, CARDH
        call inv_rect
        jmp short .dst
.t:     call padr                       ; columna: de la carta k fins a baix
        mov cl, [m_k]
        call col_y
        push ax
        mov cl, [bx]
        dec cl
        call col_y
        pop bx
        sub ax, bx
        add ax, CARDH
        mov dx, ax
        mov al, [m_src]
        sub al, P_TAB
        mov ah, CSTEP
        mul ah
        add ax, COL0
        call inv_rect
.dst:   mov al, [m_dst]
        cmp al, P_TAB
        jae .dt
        add al, 3 - P_FOUND             ; pila de dalt
        mov ah, CSTEP
        mul ah
        add ax, COL0
        mov bx, TOPY
        mov dx, CARDH
        jmp inv_rect
.dt:    call padr                       ; columna: la carta de dalt o el lloc buit
        mov cl, [bx]
        mov ax, TABY
        or cl, cl
        jz .db
        dec cl
        call col_y
.db:    mov bx, ax
        mov al, [m_dst]
        sub al, P_TAB
        mov ah, CSTEP
        mul ah
        add ax, COL0
        mov dx, CARDH
        jmp inv_rect

; inv_rect: AX = x, BX = y (relatives), DX = alcada; amplada d'una carta
inv_rect:
        add ax, [ox]
        mov cl, 3
        shr ax, cl
        mov [vbx], ax
        add bx, [oy]
        mov [vy], bx
        mov [vh], dx
        mov word [vwb], CARDW/8
        jmp vr_inv

; espera_t: AX = tics del rellotge (55 ms), amb un limit de voltes
espera_t:
        mov cx, ax
        call ticks
        mov dx, ax
        mov si, 30000
.l:     call ticks
        sub ax, dx
        cmp ax, cx
        jae .r
        dec si
        jnz .l
.r:     ret

; ---- desfer
snap_tmp:
        mov si, estat
        mov di, tmpst
        jmp short copia_st
rest_tmp:
        mov si, tmpst
        mov di, estat
copia_st:
        mov cx, ESTAT_SZ
        rep movsb
        ret
commit: mov si, tmpst
        mov di, undost
        call copia_st
        mov byte [undo_ok], 1
        jmp marca_opcions
m_desf:
desfer: cmp byte [undo_ok], 0
        je .r
        cmp byte [fi], 0
        jne .r
        mov si, undost
        mov di, estat
        call copia_st
        mov byte [undo_ok], 0
        call marca_opcions
        call inval_tot
        jmp titol_upd
.r:     ret

; ---- s'ha guanyat?
check_win:
        mov al, P_FOUND
.f:     call padr
        cmp byte [bx], 13
        jne .r
        inc al
        cmp al, P_TAB
        jb .f
        mov byte [jugant], 0            ; guanyada!
        mov byte [fi], 1
        mov byte [undo_ok], 0
        call marca_opcions
        cmp byte [modep], 0             ; bonus de temps (estandard)
        jne .t
        cmp word [secs], 30
        jb .t
        mov dx, 000Ah                   ; 700000 / segons
        mov ax, 0AE60h
        div word [secs]
        call suma
.t:     call titol_upd
        call s_fanfara
        call final_anim
        call inval_tot
        mov si, al_guanya
        mov ax, 1
        call alerta
        cmp ax, 1
        jne .r
        jmp nova_partida
.r:     ret

; ---- rellotge i titol
rellotge:
        cmp byte [jugant], 0
        je .r
        call ticks
        sub ax, [t0]
        mov cx, 10
        mul cx
        mov cx, 182
        div cx
        cmp ax, [secs]
        je .r
        mov [secs], ax
        cmp byte [modep], 0             ; estandard: -2 cada 10 segons
        jne .t
        xor dx, dx
        mov cx, 10
        div cx
        cmp ax, [deu_s]
        jbe .t
        mov [deu_s], ax
        mov ax, -2
        call suma
.t:     call titol_upd
.r:     ret

titol_upd:
        mov di, titbuf
        mov si, s_titol
        call cpy0
        cmp byte [modep], 2
        je .tm
        mov si, s_punts
        cmp byte [modep], 1
        jne .p
        mov si, s_vegas
.p:     call cpy0
        mov ax, [score]
        call pnum
        cmp byte [modep], 1
        jne .tm
        mov ax, '$' * 256 + ' '
        stosw
.tm:    mov si, s_temps
        call cpy0
        mov ax, [secs]
        xor dx, dx
        mov cx, 60
        div cx
        push dx
        call pnum
        mov al, ':'
        stosb
        pop ax
        aam                             ; AH = desenes, AL = unitats
        add ax, 3030h
        xchg al, ah
        stosw
        mov ax, ' '
        stosw                           ; espai i 0 final
        mov si, titbuf                  ; nomes si ha canviat
        mov di, titprev
        mov cx, TITLEN
        repe cmpsb
        je .r
        mov si, titbuf
        mov di, titprev
        mov cx, TITLEN
        rep movsb
        call posa_wh
        mov word [int_in+2], WF_NAME
        mov word [int_in+4], titprev
        mov [int_in+6], ds
        mov word [int_in+8], 0
        mov word [int_in+10], 0
        AES 105,6,1,0,0
.r:     ret

cpy0:   lodsb                           ; copia SI (acabat en 0) a DI
        or al, al
        jz .r
        stosb
        jmp cpy0
.r:     ret

pnum:   push bx                         ; AX amb signe -> text a DI
        push cx
        push dx
        or ax, ax
        jns .p
        mov byte [di], '-'
        inc di
        neg ax
.p:     xor cx, cx
        mov bx, 10
.d:     xor dx, dx
        div bx
        push dx
        inc cx
        or ax, ax
        jnz .d
.o:     pop ax
        add al, '0'
        stosb
        loop .o
        pop dx
        pop cx
        pop bx
        ret

; =====================================================================
;  RATOLI: clic, arrossegar i deixar
; =====================================================================
premut: cmp byte [fi], 0
        je .ok
        jmp espera_amollar
.ok:    call hit
        cmp al, 0FFh
        jne .a
        jmp espera_amollar
.a:     cmp al, P_STOCK
        jne .b
        call espera_amollar
        jmp robar
.b:     mov [m_src], al
        mov [m_k], ah
        call padr
        mov al, ah
        call carta_k
        test al, TAPADA
        jz .c
        jmp espera_amollar
.c:     call clic_o_drag
        jc .drag
        mov al, [m_src]                 ; clic: nomes la carta de dalt
        call padr
        mov al, [bx]
        dec al
        cmp al, [m_k]
        jne .r
        jmp auto_found
.drag:  jmp arrossega
.r:     ret

espera_amollar:
        mov word [int_in], 1            ; evnt_button: esperar que es deixi anar
        mov word [int_in+2], 1
        mov word [int_in+4], 0
        AES 21,3,5,0,0
        ret

; clic_o_drag: CF=1 si el ratoli es mou amb el boto premut
clic_o_drag:
.l:     AES 79,0,5,0,0                  ; graf_mkstate
        test word [int_out+6], 1
        jz .clic
        mov ax, [int_out+2]
        sub ax, [mx0]
        cwd
        xor ax, dx
        sub ax, dx
        cmp ax, 2
        ja .drag
        mov ax, [int_out+4]
        sub ax, [my0]
        cwd
        xor ax, dx
        sub ax, dx
        cmp ax, 1
        ja .drag
        jmp .l
.clic:  clc
        ret
.drag:  stc
        ret

; auto_found: la carta de dalt de [m_src] a la primera pila de dalt que l'accepti
auto_found:
        mov al, [m_src]
        call padr
        mov al, [bx]
        dec al
        call carta_k
        mov bl, P_FOUND
.f:     call can_found
        jnc .ok
        inc bl
        cmp bl, P_TAB
        jb .f
        ret
.ok:    mov [m_dst], bl
        call snap_tmp
        call fer_moure
        call commit
        call inval_moure
        call sons_moure
        call titol_upd
        jmp check_win

; ---- hit: [mx0],[my0] -> AL = pila (0FFh cap), AH = index de la carta;
;      [hx],[hy] = posicio relativa de la carta
hit:    mov ax, [mx0]
        sub ax, [ox]
        mov [rx], ax
        mov ax, [my0]
        sub ax, [oy]
        mov [ry], ax
        mov ax, [rx]
        sub ax, COL0
        jl .no
        xor dx, dx
        mov cx, CSTEP
        div cx
        cmp ax, 7
        jae .no
        mov [hcol], al
        mov [hxin], dx
        mov cx, CSTEP                   ; x de la columna
        mul cx
        add ax, COL0
        mov [hx], ax
        mov ax, [ry]
        cmp ax, TOPY
        jl .no
        cmp ax, TOPY + CARDH
        jge .tab
        mov word [hy], TOPY             ; ---- fila de dalt
        mov al, [hcol]
        cmp al, 0
        jne .w
        cmp word [hxin], CARDW
        jae .no
        mov ax, P_STOCK
        ret
.w:     cmp al, 3
        jae .f
        mov al, P_WASTE                 ; descartades: nomes la de dalt
        call padr
        mov al, [bx]
        or al, al
        jz .no
        push ax
        call fan_eff
        dec al
        mov cl, WFANX
        mul cl
        add ax, COL0 + CSTEP
        mov [hx], ax
        pop cx
        mov dx, [rx]
        sub dx, ax
        jl .no
        cmp dx, CARDW
        jae .no
        mov al, P_WASTE
        mov ah, cl
        dec ah
        ret
.f:     cmp word [hxin], CARDW
        jae .no
        dec al                          ; columna 3..6 -> pila 2..5
        mov dl, al
        call padr
        mov ah, [bx]
        or ah, ah
        jz .no
        dec ah
        mov al, dl
        ret
.tab:   cmp ax, TABY                    ; ---- columnes
        jl .no
        cmp word [hxin], CARDW
        jae .no
        mov al, [hcol]
        add al, P_TAB
        mov [hpila], al
        call padr
        mov cl, [bx]
        or cl, cl
        jz .no
        call col_offs
        xor ch, ch
        mov si, bx
        inc si
        mov ax, TABY
        xor dx, dx                      ; DL = index, DH = millor
        mov byte [hidx], 0FFh
.l:     cmp [ry], ax
        jl .s
        mov [hidx], dl
        mov [hy], ax
.s:     mov bl, [uof]
        test byte [si], TAPADA
        jz .u
        mov bl, [dof]
.u:     xor bh, bh
        add ax, bx
        inc si
        inc dl
        cmp dl, cl
        jb .l
        cmp byte [hidx], 0FFh
        je .no
        mov al, [hidx]                  ; la de dalt: dins la carta
        inc al
        cmp al, cl
        jne .ok
        mov ax, [hy]
        add ax, CARDH
        cmp [ry], ax
        jge .no
.ok:    mov al, [hpila]
        mov ah, [hidx]
        ret
.no:    mov al, 0FFh
        ret

; fan_eff: AL = cartes a les descartades -> AL = quantes es veuen en ventall
fan_eff:
        or al, al
        jz .r
        cmp byte [draw3], 0
        jne .t
        mov al, 1
        ret
.t:     mov ah, [wfan]
        cmp ah, al
        jbe .m
        mov ah, al
.m:     or ah, ah
        jnz .k
        mov ah, 1
.k:     mov al, ah
.r:     ret

; col_offs: BX = columna -> [dof], [uof] (es comprimeix si no hi cap)
col_offs:
        push ax
        push bx
        push cx
        push dx
        push si
        mov cl, [bx]
        xor ch, ch
        xor dx, dx
        mov si, bx
        inc si
.d:     cmp dx, cx                      ; DX = cartes tapades
        jae .e
        test byte [si], TAPADA
        jz .e
        inc dx
        inc si
        jmp .d
.e:     mov byte [dof], DOFF
        mov byte [uof], UOFF
        mov ax, cx
        sub ax, dx
        cmp ax, 2
        jb .fi
        dec ax
        mov [cu1], ax                   ; destapades - 1
        mov [cd], dx
        mov ax, dx
        mov cx, DOFF
        mul cx
        mov si, ax                      ; tapades * 3
        mov ax, [cu1]
        mov cx, UOFF
        mul cx
        add ax, si
        cmp ax, [avail]
        jle .fi
        mov ax, [avail]                 ; comprimir les destapades
        sub ax, si
        jl .mes
        xor dx, dx
        div word [cu1]
        cmp ax, 4
        jae .set
.mes:   mov byte [dof], 1               ; i, si cal, tambe les tapades
        mov ax, [avail]
        sub ax, [cd]
        jl .min
        xor dx, dx
        div word [cu1]
        cmp ax, 2
        jae .set
.min:   mov ax, 2
.set:   mov [uof], al
.fi:    pop si
        pop dx
        pop cx
        pop bx
        pop ax
        ret

; col_y: BX = columna, CL = index -> AX = y relativa de la carta
col_y:  push bx
        push cx
        push dx
        push si
        call col_offs
        mov ax, TABY
        xor ch, ch
        mov si, bx
        inc si
        jcxz .r
.l:     mov dl, [uof]
        test byte [si], TAPADA
        jz .u
        mov dl, [dof]
.u:     xor dh, dh
        add ax, dx
        inc si
        loop .l
.r:     pop si
        pop dx
        pop cx
        pop bx
        ret

; ---- arrossegar les cartes [m_k].. de [m_src]
arrossega:
        mov ax, [hx]
        mov [sx], ax
        mov ax, [hy]
        mov [sy], ax
        mov word [sh], CARDH
        mov al, [m_src]
        cmp al, P_TAB
        jb .g
        call padr                       ; alcada de l'escala
        mov cl, [bx]
        dec cl
        call col_y
        sub ax, [sy]
        add ax, CARDH
        mov [sh], ax
.g:     call snap_tmp
        call s_agafa
        cmp byte [dvok], 0
        je .caixa
        call som_dalt
        je .vram
.caixa: mov ax, [ox]                    ; ---- sense video directe: contorn del GEM
        add ax, [sx]
        mov bx, [oy]
        add bx, [sy]
        mov word [int_in], CARDW
        mov cx, [sh]
        mov [int_in+2], cx
        mov [int_in+4], ax
        mov [int_in+6], bx
        mov ax, [wkx]
        mov [int_in+8], ax
        mov ax, [wky]
        mov [int_in+10], ax
        mov ax, [workw]
        mov [int_in+12], ax
        mov ax, [workh]
        mov [int_in+14], ax
        AES 71,8,3,0,0                  ; graf_dragbox
        mov ax, [int_out+2]
        sub ax, [ox]
        mov [fx], ax
        mov ax, [int_out+4]
        sub ax, [oy]
        mov [fy], ax
        jmp deixa
.vram:  call lock_ini                   ; ---- amb video directe
        mov ax, [ox]
        add ax, [sx]
        mov cl, 3
        shr ax, cl
        mov [vbx], ax
        mov [bx0], ax
        mov ax, [oy]
        add ax, [sy]
        mov [vy], ax
        mov [y0v], ax
        mov word [vwb], CARDW/8
        mov ax, [sh]
        mov [vh], ax
        mov di, dragbuf                 ; la imatge de les cartes
        call vr_get
        mov al, [m_src]                 ; treure-les i redibuixar el que hi ha sota
        call padr
        mov al, [m_k]
        mov [bx], al
        cmp byte [m_src], P_WASTE
        jne .tr
        cmp byte [wfan], 0
        je .tr
        dec byte [wfan]
.tr:    mov ax, [ox]
        add ax, [sx]
        mov cx, ax
        add cx, CARDW - 1
        mov bx, [oy]
        add bx, [sy]
        mov dx, bx
        add dx, [sh]
        dec dx
        call clip_set
        call escena
        mov ax, [wkx]                   ; limits del moviment
        add ax, 7
        mov cl, 3
        shr ax, cl
        mov [bxmin], ax
        mov ax, [wkx]
        add ax, [workw]
        sub ax, CARDW
        shr ax, cl
        mov [bxmax], ax
        mov ax, [wky]
        mov [ymin], ax
        add ax, [workh]
        sub ax, [sh]
        mov [ymax], ax
        mov di, savebuf
        call vr_get
        mov si, dragbuf
        call vr_put
.l:     AES 79,0,5,0,0                  ; graf_mkstate
        mov ax, [int_out+6]
        mov [btn], ax
        mov ax, [int_out+2]             ; x: a byte, dins la finestra
        sub ax, [mx0]
        add ax, 4
        mov cl, 3
        sar ax, cl
        add ax, [bx0]
        cmp ax, [bxmin]
        jge .x1
        mov ax, [bxmin]
.x1:    cmp ax, [bxmax]
        jle .x2
        mov ax, [bxmax]
.x2:    mov [nbx], ax
        mov ax, [int_out+4]             ; y
        sub ax, [my0]
        add ax, [y0v]
        cmp ax, [ymin]
        jge .y1
        mov ax, [ymin]
.y1:    cmp ax, [ymax]
        jle .y2
        mov ax, [ymax]
.y2:    mov [nyv], ax
        mov ax, [nbx]
        cmp ax, [vbx]
        jne .mou
        mov ax, [nyv]
        cmp ax, [vy]
        je .bt
.mou:   mov si, savebuf                 ; tornar el fons i dibuixar al lloc nou
        call vr_put
        mov ax, [nbx]
        mov [vbx], ax
        mov ax, [nyv]
        mov [vy], ax
        mov di, savebuf
        call vr_get
        mov si, dragbuf
        call vr_put
.bt:    test word [btn], 1
        jnz .l
        mov si, savebuf                 ; deixat: treure la imatge
        call vr_put
        call lock_fi
        mov ax, [vbx]
        mov cl, 3
        shl ax, cl
        sub ax, [ox]
        mov [fx], ax
        mov ax, [vy]
        sub ax, [oy]
        mov [fy], ax
        call rest_tmp                   ; les cartes, al seu lloc (de moment)

; ---- deixar a [fx],[fy]: la pila es tria pel centre de la primera carta
deixa:  mov ax, [fx]
        add ax, CARDW/2 - COL0
        jge .c0
        xor ax, ax
.c0:    xor dx, dx
        mov cx, CSTEP
        div cx
        cmp ax, 6
        jbe .c1
        mov ax, 6
.c1:    mov bx, [fy]
        add bx, CARDH/2
        cmp bx, TABY
        jge .t
        cmp al, 3                       ; fila de dalt: nomes les piles
        jb .no
        dec al
        jmp short .v
.t:     add al, P_TAB
.v:     mov [m_dst], al
        call valid_moure
        jc .no
        call fer_moure
        call commit
        call inval_moure
        call sons_moure
        call titol_upd
        jmp check_win
.no:    call s_error
        mov al, [m_src]
        jmp inval_pila

; ---- redibuixos
inval_tot:
        mov ax, [marg_x]
        neg ax
        mov bx, [marg_y]
        neg bx
        mov cx, [workw]
        mov dx, [workh]
        jmp inval
inval_dalt:                             ; munt i descartades
        mov ax, COL0
        mov bx, TOPY
        mov cx, CSTEP + CARDW + 2*WFANX
        mov dx, CARDH
        jmp inval
inval_moure:
        mov al, [m_src]
        call inval_pila
        mov al, [m_dst]
inval_pila:                             ; AL = pila
        cmp al, P_FOUND
        jb inval_dalt
        cmp al, P_TAB
        jae .tab
        inc al                          ; pila de dalt: columna 3..6
        mov bx, TOPY
        mov dx, CARDH
        jmp short .x
.tab:   sub al, P_TAB
        mov bx, TABY
        mov dx, [workh]
        sub dx, TABY
.x:     mov ah, CSTEP
        mul ah
        add ax, COL0
        mov cx, CARDW
        jmp inval

sons_moure:
        mov al, [m_dst]
        cmp al, P_FOUND
        jb .d
        cmp al, P_TAB
        jae .d
        call s_pila
        jmp short .g
.d:     call s_deixa
.g:     cmp byte [girada], 0
        je .r
        call s_gira
.r:     ret

; =====================================================================
;  ANIMACIO FINAL (dibuix directe): els 4 reis van al centre en ventall,
;  creixen en 7 mides dibuixades amb tota la resolucio i es dissolen.
;  Un clic l'atura en qualsevol moment.
; =====================================================================
final_anim:
        cmp byte [dcache], 0
        je .r
        call som_dalt
        je .ok
.r:     ret
.ok:    call lock_ini
        mov byte [fcol], TAPET          ; 1) taula neta, amb els reis a les piles
        mov ax, [marg_x]
        neg ax
        mov bx, [marg_y]
        neg bx
        mov cx, [workw]
        mov dx, [workh]
        call fill_rect
        mov word [dhgt], CARDH
        mov ax, [workh]                 ; desti del ventall (relatiu)
        shr ax, 1
        sub ax, CARDH/2
        mov [vent_y], ax
        mov word [vent_x], (W/2 - (CARDW + 3*56)/2) & 0FFF8h
        mov byte [pas_k], 0
        call reis_pas
        mov ax, 8                       ; mig segon quiets
        call espera_ab
        jc .prou
        mov byte [pas_k], 1             ; 2) llisquen fins al centre
.ll:    call ticks
        mov [t_fr], ax
        mov byte [fcol], TAPET          ; esborrar on eren
        mov ax, [rei_x0]
        mov bx, [rei_y]
        mov cx, [rei_x3]
        sub cx, ax
        add cx, CARDW
        mov dx, CARDH
        call fill_rect
        call reis_pas
        mov ax, 1
        call espera_ab
        jc .prou
        inc byte [pas_k]
        cmp byte [pas_k], 10
        jbe .ll
        mov ax, 5
        call espera_ab
        jc .prou
        mov byte [fin_k], 0             ; 3) zoom: cada mida, nitida
.zm:    call ticks
        mov [t_fr], ax
        call dib_fin
        mov ax, 3
        call espera_ab
        jc .prou
        inc byte [fin_k]
        cmp byte [fin_k], NFIN
        jb .zm
        mov ax, 27                      ; contemplar-los un segon i mig
        call espera_ab
        jc .prou
        call dissol                     ; 4) i desapareixen
.prou:  call lock_fi
        jmp espera_amollar

; espera_ab: fins que passin AX tics des de [t_fr]; CF=1 si es prem el boto
espera_ab:
        mov [t_esp], ax
.l:     AES 79,0,5,0,0                  ; graf_mkstate
        test word [int_out+6], 1
        jnz .clic
        call ticks
        sub ax, [t_fr]
        cmp ax, [t_esp]
        jb .l
        call ticks
        mov [t_fr], ax
        clc
        ret
.clic:  stc
        ret

; reis_pas: els 4 reis al pas [pas_k] (0..10) del cami piles -> ventall
reis_pas:
        mov bl, [pas_k]
        xor bh, bh
        mov al, [suau+bx]               ; t (0..64), suavitzat
        xor ah, ah
        mov [t_pas], ax
        mov byte [cel_f], 0
.f:     mov al, [cel_f]                 ; origen x: pila de dalt
        add al, 3
        mov ah, CSTEP
        mul ah
        add ax, COL0
        mov si, ax
        mov al, [cel_f]                 ; desti x: ventall
        mov ah, 56
        mul ah
        add ax, [vent_x]
        sub ax, si                      ; x = origen + (desti-origen)*t/64
        imul word [t_pas]
        mov cl, 6
        sar ax, cl
        add ax, si
        and ax, 0FFF8h
        mov [cardx], ax
        mov ax, [vent_y]
        sub ax, TOPY
        imul word [t_pas]
        mov cl, 6
        sar ax, cl
        add ax, TOPY
        mov [cardy], ax
        cmp byte [cel_f], 0
        jne .n0
        mov dx, [cardx]
        mov [rei_x0], dx
        mov [rei_y], ax
.n0:    mov dx, [cardx]
        mov [rei_x3], dx
        mov al, [cel_f]                 ; el rei del pal: 12 + 13*pal
        mov ah, 13
        mul ah
        add al, 12
        call dput
        inc byte [cel_f]
        cmp byte [cel_f], 4
        jb .f
        ret

; dib_fin: dibuixa el fotograma [fin_k] centrat a la finestra
dib_fin:
        mov al, [fin_k]
        mov ah, 6
        mul ah
        mov bx, ax
        mov si, [fintab+bx]
        mov ax, [fintab+bx+2]
        mov [fw_], ax
        add ax, 7
        mov cl, 3
        shr ax, cl
        mov [fwb], ax
        mov ax, [fintab+bx+4]
        mov [fh_], ax
        mov ax, [fw_]                   ; posicio: centrada, alineada a byte
        shr ax, 1
        neg ax
        add ax, W/2
        add ax, [ox]
        shr ax, cl
        mov [fx0b], ax
        mov ax, [fh_]
        shr ax, 1
        neg ax
        mov dx, [workh]
        shr dx, 1
        add ax, dx
        add ax, [oy]
        mov [fy0], ax
        push si                         ; linia de treball plena de tapet
        mov di, linebuf
        mov ah, [hwcol]
        mov dl, 4
.tp:    mov al, ah
        and al, 1
        neg al
        mov cx, 80
        rep stosb
        shr ah, 1
        dec dl
        jnz .tp
        pop si
        mov word [fy], 0
.lin:   mov word [sbx], 0               ; ---- una linia: tirades
.run:   lodsb
        mov dl, al
        and al, 31
        xor ah, ah
        inc ax
        cmp al, 32
        jne .cu
        lodsb
        xor ah, ah
        add ax, 32
.cu:    mov [sbn], ax
        mov cl, 5
        shr dl, cl
        cmp dl, 6                       ; 6: igual que a sobre (ja hi es)
        je .salt
        mov bl, dl
        xor bh, bh
        mov al, [hwcol+bx]
        mov [hwv], al
        push si
        call setbits
        pop si
        jmp short .seg
.salt:  mov ax, [sbn]
        add [sbx], ax
.seg:   mov ax, [sbx]
        cmp ax, [fw_]
        jb .run
        push si                         ; ---- la linia, a la pantalla
        push es
        mov ax, VSEG
        mov es, ax
        xor bx, bx
.pl:    cmp byte [vplanes], 1
        je .np
        mov cl, bl
        mov al, 1
        shl al, cl
        mov dx, P_WPLA
        out dx, al
.np:    mov ax, [fy0]
        add ax, [fy]
        call voffa
        add ax, [fx0b]
        mov di, ax
        mov al, bl
        mov ah, 80
        mul ah
        add ax, linebuf
        mov si, ax
        mov cx, [fwb]
        rep movsb
        inc bl
        cmp bl, [vplanes]
        jb .pl
        pop es
        pop si
        inc word [fy]
        mov ax, [fy]
        cmp ax, [fh_]
        jb .lin
        jmp vr_fi_r

; setbits: [sbn] pixels des de [sbx] del color de maquinari [hwv], a linebuf
setbits:
.l:     mov ax, [sbx]
        mov bx, ax
        and bx, 7                       ; BX = bit dins el byte
        mov cl, 3
        shr ax, cl                      ; AX = byte
        mov cx, 8
        sub cx, bx
        cmp cx, [sbn]
        jbe .k
        mov cx, [sbn]                   ; CX = pixels en aquest byte
.k:     mov dl, [lmask+bx]              ; mascara dels pixels
        mov di, bx
        add di, cx
        mov dh, [lmask+di]
        not dh
        and dl, dh
        mov di, ax
        add di, linebuf
        mov ah, [hwv]
        mov bh, [vplanes]
.p:     test ah, 1
        jz .c
        or [di], dl
        jmp short .n
.c:     mov dh, dl
        not dh
        and [di], dh
.n:     shr ah, 1
        add di, 80
        dec bh
        jnz .p
        add [sbx], cx
        sub [sbn], cx
        jnz .l
        ret

; dissol: el darrer fotograma desapareix en 8 passades; a cada passada
; cada byte perd un pixel, en un ordre que sembla a l'atzar
dissol: mov byte [pas_k], 0
.pas:   call ticks
        mov [t_fr], ax
        push es
        mov ax, VSEG
        mov es, ax
        xor bx, bx                      ; BL = pla
.pl:    cmp byte [vplanes], 1
        je .np
        mov cl, bl
        mov al, 1
        shl al, cl
        mov dx, P_WPLA
        out dx, al
        mov al, bl
        mov dx, P_RPLA
        out dx, al
.np:    mov cl, bl                      ; BH = 0FFh si el tapet te aquest pla
        mov al, [hwcol]
        shr al, cl
        and al, 1
        neg al
        mov bh, al
        mov word [fy], 0
.lin:   mov ax, [fy0]
        add ax, [fy]
        call voffa
        add ax, [fx0b]
        mov di, ax
        mov ax, [fy]                    ; index inicial: (pas + linia*3) & 7
        mov dx, ax
        shl ax, 1
        add ax, dx
        add al, [pas_k]
        mov dl, al
        mov cx, [fwb]
.b:     and dl, 7
        mov si, dx
        and si, 7
        mov al, [dmask+si]
        or bh, bh
        jz .zero
        or [es:di], al
        jmp short .nx
.zero:  not al
        and [es:di], al
.nx:    inc di
        add dl, 5
        loop .b
        inc word [fy]
        mov ax, [fy]
        cmp ax, [fh_]
        jb .lin
        inc bl
        cmp bl, [vplanes]
        jb .pl
        pop es
        call vr_fi_r
        mov ax, 2
        call espera_ab
        jc .r
        inc byte [pas_k]
        cmp byte [pas_k], 8
        jb .pas
.r:     ret

; vr_fi_r: plans com els vol el GEM
vr_fi_r:
        cmp byte [vplanes], 1
        je .r
        push ax
        push dx
        mov al, 0Fh
        mov dx, P_WPLA
        out dx, al
        xor al, al
        mov dx, P_RPLA
        out dx, al
        pop dx
        pop ax
.r:     ret

; =====================================================================
;  DIBUIX
; =====================================================================
lock_ini:
        mov word [int_in], 1
        AES 107,1,1,0,0                 ; wind_update(BEG_UPDATE)
        mov word [int_in], 256
        AES 78,1,1,1,0                  ; graf_mouse(M_OFF)
        mov ax, [wkx]                   ; retall: area de treball
        mov bx, [wky]
        mov cx, ax
        add cx, [workw]
        dec cx
        mov dx, bx
        add dx, [workh]
        dec dx
        jmp clip_set
lock_fi:
        mov word [int_in], 257
        AES 78,1,1,1,0                  ; graf_mouse(M_ON)
        mov word [int_in], 0
        AES 107,1,1,0,0                 ; wind_update(END_UPDATE)
        ret

; clip_set: AX,BX - CX,DX (absoluts) -> [clip] i vs_clip
clip_set:
        mov [clip], ax
        mov [clip+2], bx
        mov [clip+4], cx
        mov [clip+6], dx
        mov word [intin], 1
        mov si, clip
        mov di, ptsin
        mov cx, 4
        rep movsw
        VDI 129,2,1
        ret

; ---- tota la taula, retallada a [clip]
scene:  mov word [dhgt], CARDH
        mov ax, [marg_x]                ; tapet
        neg ax
        mov bx, [marg_y]
        neg bx
        mov cx, [workw]
        mov dx, [workh]
        mov byte [fcol], TAPET
        call fill_rect
        mov word [cardx], COL0          ; munt
        mov word [cardy], TOPY
        mov al, P_STOCK
        call padr
        cmp byte [bx], 0
        je .mb
        mov al, TAPADA
        call draw_card
        jmp short .desc
.mb:    call draw_slot
        call pot_reciclar
        jc .desc
        call draw_cercle
.desc:  mov al, P_WASTE                 ; descartades, en ventall
        call padr
        mov cl, [bx]
        or cl, cl
        jz .fund
        mov al, cl
        call fan_eff
        mov dl, cl
        sub dl, al                      ; DL = primera que es veu
        mov word [cardx], COL0 + CSTEP
.dl:    mov al, dl
        call carta_k
        call draw_card
        add word [cardx], WFANX
        inc dl
        cmp dl, cl
        jb .dl
.fund:  mov byte [lc], 0                ; piles de dalt
.fl:    mov al, [lc]
        add al, 3
        mov ah, CSTEP
        mul ah
        add ax, COL0
        mov [cardx], ax
        mov al, [lc]
        add al, P_FOUND
        call padr
        mov al, [bx]
        or al, al
        jnz .fc
        call draw_slot
        jmp short .fn
.fc:    dec al
        call carta_k
        call draw_card
.fn:    inc byte [lc]
        cmp byte [lc], 4
        jb .fl
        mov byte [lc], 0                ; columnes
.tc:    mov al, [lc]
        mov ah, CSTEP
        mul ah
        add ax, COL0
        mov [cardx], ax
        mov word [cardy], TABY
        mov bx, TABY                    ; la columna es veu?
        mov cx, CARDW
        mov dx, [workh]
        sub dx, TABY
        call vis_rect
        jc .tn
        mov al, [lc]
        add al, P_TAB
        call padr
        mov cl, [bx]
        or cl, cl
        jnz .tk
        call draw_slot
        jmp short .tn
.tk:    call col_offs
        xor ch, ch
        mov si, bx
        inc si
.tl:    mov dl, [uof]                   ; DL = el que es veu d'aquesta carta
        test byte [si], TAPADA
        jz .tu
        mov dl, [dof]
.tu:    xor dh, dh
        mov word [dhgt], CARDH          ; dibuix directe: de les de sota, nomes
        cmp cx, 1                       ; la part que es veu (+2 linies pels
        je .td                          ; cantons de la de sobre)
        mov ax, dx
        add ax, 2
        cmp ax, CARDH
        jae .td
        mov [dhgt], ax
.td:    mov al, [si]
        call draw_card
        add [cardy], dx
        inc si
        loop .tl
        mov word [dhgt], CARDH
.tn:    inc byte [lc]
        cmp byte [lc], 7
        jb .tc
        ret

; ---- lloc buit: un rectangle negre
draw_slot:
        cmp byte [dmode], 0
        je .v
        push ax
        mov al, IMG_BUIT
        jmp dimg
.v:     push ax
        push bx
        push cx
        push dx
        push si
        push di
        mov ax, [cardx]
        mov bx, [cardy]
        mov cx, CARDW
        mov dx, CARDH
        call vis_rect
        jc .r
        mov word [intin], NEGRE
        VDI 17,0,1                      ; vsl_color
        mov ax, [cardx]
        add ax, [ox]
        mov bx, [cardy]
        add bx, [oy]
        mov [ptsin], ax                 ; (x1,y1) (x2,y1) (x2,y2) (x1,y2) (x1,y1)
        mov [ptsin+12], ax
        mov [ptsin+16], ax
        mov [ptsin+2], bx
        mov [ptsin+6], bx
        mov [ptsin+18], bx
        add ax, CARDW - 1
        add bx, CARDH - 1
        mov [ptsin+4], ax
        mov [ptsin+8], ax
        mov [ptsin+10], bx
        mov [ptsin+14], bx
        VDI 6,5,0                       ; v_pline
.r:     pop di
        pop si
        pop dx
        pop cx
        pop bx
        pop ax
        ret

; ---- cercle al munt buit: es pot tornar a girar
draw_cercle:
        cmp byte [dmode], 0
        je .v
        push ax
        mov al, IMG_CERCLE
        jmp dimg
.v:     mov ax, [cardx]
        mov bx, [cardy]
        mov cx, CARDW
        mov dx, CARDH
        call vis_rect
        jc .r
        mov word [intin], 0             ; vsf_interior(buit)
        VDI 23,0,1
        mov word [intin], NEGRE
        VDI 25,0,1
        mov ax, [cardx]
        add ax, [ox]
        add ax, CARDW/2
        mov [ptsin], ax
        mov ax, [cardy]
        add ax, [oy]
        add ax, CARDH/2
        mov [ptsin+2], ax
        xor ax, ax
        mov [ptsin+4], ax
        mov [ptsin+6], ax
        mov word [ptsin+8], 16
        mov [ptsin+10], ax
        VDI 11,3,0,4                    ; v_circle
.r:     ret

; ---- draw_card: AL = carta (bit 7 = tapada) a [cardx],[cardy]
draw_card:
        push ax
        push bx
        push cx
        push dx
        push si
        push di
        push bp
        mov [cardv], al
        mov ax, [cardx]
        mov bx, [cardy]
        mov cx, CARDW
        mov dx, CARDH
        call vis_rect
        jnc .vis
        jmp .fi
.vis:   cmp byte [dmode], 0
        je .vdi
        mov al, [cardv]                 ; dibuix directe: la imatge de la memoria cau
        test al, TAPADA
        jz .im
        mov al, IMG_DORS
.im:    call dput
        jmp .fi
.vdi:   mov byte [fcol], NEGRE          ; vora negra i cara blanca
        call rfbox
        inc ax
        inc bx
        sub cx, 2
        sub dx, 2
        mov byte [fcol], BLANC
        call rfbox
        test byte [cardv], TAPADA
        jz .cara
        mov ax, [cardx]                 ; dors: trama blava
        add ax, 3
        mov bx, [cardy]
        add bx, 2
        mov cx, CARDW - 6
        mov dx, CARDH - 4
        call rect_abs
        mov word [intin], 2             ; vsf_interior(trama)
        VDI 23,0,1
        mov word [intin], 4             ; vsf_style
        VDI 24,0,1
        mov word [intin], C_BLU
        VDI 25,0,1
        VDI 114,2,0
        jmp .fi
.cara:  mov bl, [cardv]
        xor bh, bh
        mov al, [suit_of+bx]
        mov [csuit], al
        mov al, [rank_of+bx]
        mov [crank], al
        mov bl, NEGRE                   ; cors i diamants en vermell
        test byte [csuit], 1
        jz .k
        mov bl, C_RED
.k:     mov [fcol], bl
        mov [tcolor], bl
        call rank_str                   ; index de dalt: valor i pal al costat
        mov ax, [cardx]
        add ax, 3
        mov bx, [cardy]
        inc bx
        call text_at
        mov ax, cx
        mov cl, 3
        shl ax, cl
        add ax, [cardx]
        add ax, 3 + 1 + 6
        mov bx, [cardy]
        add bx, 4
        mov cl, 0
        call pip
        call rank_str                   ; index de baix (CX = llargada: no tocar)
        mov ax, cx
        shl ax, 1
        shl ax, 1
        shl ax, 1
        neg ax
        add ax, [cardx]
        add ax, CARDW - 3
        mov bx, [cardy]
        add bx, CARDH - 9
        call text_at
        call fill_attrs
        mov al, [crank]
        or al, al
        jz .as
        cmp al, 10
        jae .figura
        dec al                          ; pips: disposicio de les cartes reals
        xor ah, ah
        mov si, ax
        mov al, [pipidx+si]
        mov si, ax
        add si, pips
        lodsb
        mov [prow], al
.pip:   lodsb                           ; columna*16 + mitja fila (0..12)
        mov dl, al
        and al, 0Fh
        mov ah, 9                       ; y = 14 + mitja_fila * 9/4
        mul ah
        shr ax, 1
        shr ax, 1
        add ax, [cardy]
        add ax, 14
        mov bx, ax
        mov al, dl
        mov cl, 4
        shr al, cl
        mov ah, 15                      ; x = 25 + columna * 15
        mul ah
        add ax, [cardx]
        add ax, CARDW/2 - 15
        mov cl, 0
        call pip
        dec byte [prow]
        jnz .pip
        jmp .fi
.as:    mov ax, [cardx]                 ; as: un pal gran
        add ax, CARDW/2
        mov bx, [cardy]
        add bx, 28
        mov cl, 1
        call pip
        jmp .fi
.figura:
        mov ax, [cardx]                 ; marc del retrat, del color del pal
        add ax, CARDW/2 - FIG_MAXW/2 - 1
        mov bx, [cardy]
        add bx, 28 - FIG_MAXH/2 - 1
        mov cx, FIG_MAXW + 2
        mov dx, FIG_MAXH + 2
        call rect_abs
        mov al, [fcol]
        xor ah, ah
        mov [intin], ax
        VDI 17,0,1                      ; vsl_color
        mov ax, [ptsin]
        mov bx, [ptsin+2]
        mov cx, [ptsin+4]
        mov dx, [ptsin+6]
        mov [ptsin+8], cx
        mov [ptsin+10], dx
        mov [ptsin+12], ax
        mov [ptsin+14], dx
        mov [ptsin+16], ax
        mov [ptsin+18], bx
        mov [ptsin+6], bx
        VDI 6,5,0                       ; v_pline
        mov al, [crank]                 ; figura = (valor-10)*4 + pal
        sub al, 10
        shl al, 1
        shl al, 1
        add al, [csuit]
        call desc_fig
        mov ax, [cardx]
        add ax, CARDW/2
        mov bx, [cardy]
        add bx, 28
        mov si, fdev_m
        mov di, colcapa
        mov cx, 4
.cap:   push cx
        mov dl, [di]
        mov [fcol], dl
        inc di
        call blit_si
        add si, 20
        pop cx
        loop .cap
.fi:    pop bp
        pop di
        pop si
        pop dx
        pop cx
        pop bx
        pop ax
        ret

rank_str:                               ; SI = text del valor, CX = llargada
        mov al, [crank]
        cmp al, 9
        jne .u
        mov si, deu
        mov cx, 2
        ret
.u:     xor ah, ah
        mov si, ax
        add si, rankch
        mov cx, 1
        ret

; ---- dimg: (AX a la pila) dibuixa la imatge AL a [cardx],[cardy] i torna
dimg:   push bx
        mov bx, [dhgt]
        mov word [dhgt], CARDH
        call dput
        mov [dhgt], bx
        pop bx
        pop ax
        ret

; =====================================================================
;  DIBUIX DIRECTE AMB MEMORIA CAU
;  En arrencar es dibuixa cada carta un cop amb el VDI i se'n copia la
;  imatge (4 plans x 48 linies x 10 bytes) a un bloc de memoria de DOS.
;  Despres, dibuixar una carta es copiar-la a la memoria de video.
; =====================================================================
prepara:
        cmp byte [dvok], 0
        je .r
        mov ah, 48h                     ; memoria de DOS per a les imatges
        mov bx, NIMG*IMGPAR
        int 21h
        jc .r
        mov [cseg], ax
        mov word [int_in+4], s_prep     ; titol: preparant les cartes
        call titol_txt
        call lock_ini
        mov word [cardx], COL0
        mov word [cardy], TOPY
        mov word [vwb], CARDW/8
        mov word [vh], CARDH
        mov ax, [ox]
        add ax, COL0
        mov cl, 3
        shr ax, cl
        mov [vbx], ax
        mov ax, [oy]
        add ax, TOPY
        mov [vy], ax
        mov byte [pimg], 0
.l:     mov ax, COL0 - 8                ; tapet sota la carta (els cantons)
        mov bx, TOPY - 2
        mov cx, CARDW + 16
        mov dx, CARDH + 4
        mov byte [fcol], TAPET
        call fill_rect
        mov al, [pimg]
        cmp al, IMG_DORS
        jb .cara
        je .dors
        call draw_slot
        cmp byte [pimg], IMG_CERCLE
        jne .cap
        call draw_cercle
        jmp short .cap
.dors:  mov al, TAPADA
.cara:  call draw_card
.cap:   mov al, [pimg]                  ; copiar-la de la pantalla
        xor ah, ah
        mov cx, IMGPAR
        mul cx
        add ax, [cseg]
        push es
        mov es, ax
        xor di, di
        call vr_get
        pop es
        cmp byte [pimg], 0
        jne .nm
        call fes_mask
.nm:    inc byte [pimg]
        cmp byte [pimg], NIMG
        jb .l
        mov si, colvdi                  ; colors de maquinari (plans) per al final
        mov di, hwcol
        mov word [vwb], 1
        mov word [vh], 1
.col:   lodsb
        mov [fcol], al
        push si
        push di
        mov ax, COL0
        mov bx, TOPY
        mov cx, 8
        mov dx, 1
        call fill_rect
        mov di, tmp4
        call vr_get
        xor ax, ax                      ; AL = valor, bit p = pla p
        mov cl, [vplanes]
        xor ch, ch
        mov si, tmp4
        add si, cx
.cb:    dec si
        shl al, 1
        test byte [si], 80h
        jz .c0
        or al, 1
.c0:    loop .cb
        pop di
        pop si
        mov [di], al
        inc di
        cmp si, colvdi + 6
        jb .col
        call lock_fi
        mov byte [dcache], 1
        mov byte [titprev], 0           ; que titol_upd el torni a posar
.r:     ret

; fes_mask: dels cantons de la imatge 0, quins pixels son de la carta
; (diferents del tapet del pixel 0,0). cmask: files 0, 1, 46, 47 x byte 0, 9
fes_mask:
        push es
        mov ax, [cseg]
        mov es, ax
        xor di, di
        mov si, cm_rows
.r:     lodsb
        mov ah, CARDW/8
        mul ah
        mov bx, ax                      ; BX = fila * 10
        xor cx, cx                      ; CL = byte (0 o 9)
.e:     xor dl, dl
        xor dh, dh                      ; DH = pla
.p:     mov al, dh
        xor ah, ah
        push dx
        mov dx, CARDW/8*CARDH
        mul dx
        pop dx
        mov bp, ax                      ; BP = pla*480
        mov ah, 0                       ; byte del tapet en aquest pla
        test byte [es:bp], 80h
        jz .t
        mov ah, 0FFh
.t:     add bp, bx
        add bp, cx
        mov al, [es:bp]
        xor al, ah
        or dl, al
        inc dh
        cmp dh, [vplanes]
        jb .p
        mov [cmask+di], dl
        inc di
        add cl, CARDW/8 - 1
        cmp cl, CARDW/8 - 1
        jbe .e
        cmp si, cm_rows + 4
        jb .r
        pop es
        ret

titol_txt:                              ; [int_in+4] = text del titol
        call posa_wh
        mov word [int_in+2], WF_NAME
        mov [int_in+6], ds
        mov word [int_in+8], 0
        mov word [int_in+10], 0
        AES 105,6,1,0,0
        ret

; ---- dput: imatge AL a [cardx],[cardy], [dhgt] linies, retallada a [clip]
dput:   push ax
        push bx
        push cx
        push dx
        push si
        push di
        push bp
        push ds
        push es
        xor ah, ah
        mov cx, IMGPAR
        mul cx
        add ax, [cseg]
        mov [sp_seg], ax
        mov ax, [ox]
        add ax, [cardx]
        mov cl, 3
        shr ax, cl
        mov [sp_bx], ax
        mov ax, [oy]
        add ax, [cardy]
        mov [sp_y], ax
        mov ax, [clip]                  ; retall en bytes i linies
        shr ax, cl
        sub ax, [sp_bx]
        jge .b0
        xor ax, ax
.b0:    mov [b0], ax
        mov ax, [clip+4]
        shr ax, cl
        sub ax, [sp_bx]
        cmp ax, CARDW/8 - 1
        jle .b1
        mov ax, CARDW/8 - 1
.b1:    mov [b1], ax
        cmp ax, [b0]
        jl .fi
        mov ax, [clip+2]
        sub ax, [sp_y]
        jge .l0
        xor ax, ax
.l0:    mov [l0], ax
        mov ax, [clip+6]
        sub ax, [sp_y]
        mov dx, [dhgt]
        dec dx
        cmp ax, dx
        jle .l1
        mov ax, dx
.l1:    mov [l1], ax
        cmp ax, [l0]
        jl .fi
        mov ax, VSEG
        mov es, ax
        xor bx, bx                      ; BL = pla
.pl:    cmp byte [vplanes], 1
        je .np
        mov cl, bl
        mov al, 1
        shl al, cl
        mov dx, P_WPLA
        out dx, al
        mov al, bl                      ; (i el de lectura, per als cantons)
        mov dx, P_RPLA
        out dx, al
.np:    mov bp, [l0]                    ; BP = linia de la imatge
.ln:    mov si, [b0]                    ; bytes d'aquesta linia: a les 2 primeres
        mov dx, [b1]                    ; i 2 darreres, el primer i el darrer
        mov byte [cant], 0              ; byte van a part (cantons arrodonits)
        cmp bp, 2
        jb .can
        cmp bp, CARDH - 2
        jb .ok
.can:   mov byte [cant], 1
        or si, si
        jnz .c1
        inc si
.c1:    cmp dx, CARDW/8 - 1
        jne .ok
        dec dx
.ok:    sub dx, si
        jl .nx
        inc dx
        mov cx, dx                      ; CX = bytes
        mov ax, [sp_y]
        add ax, bp
        call voffa
        add ax, [sp_bx]
        add ax, si
        mov di, ax
        mov al, bl                      ; origen: pla*480 + linia*10 + byte
        xor ah, ah
        mov dx, CARDW/8*CARDH
        mul dx
        add si, ax
        mov ax, bp
        mov dx, CARDW/8
        mul dx
        add si, ax
        mov ax, [sp_seg]
        push ds
        mov ds, ax
        rep movsb
        pop ds
.nx:    cmp byte [cant], 0
        je .nx2
        call cantons
.nx2:   inc bp
        cmp bp, [l1]
        jbe .ln
        inc bl
        cmp bl, [vplanes]
        jb .pl
        cmp byte [vplanes], 1           ; plans com els vol el GEM
        je .fi
        mov al, 0Fh
        mov dx, P_WPLA
        out dx, al
        xor al, al
        mov dx, P_RPLA
        out dx, al
.fi:    pop es
        pop ds
        pop bp
        pop di
        pop si
        pop dx
        pop cx
        pop bx
        pop ax
        ret

; cantons: BP = linia (0, 1, 46 o 47), BL = pla. Bytes 0 i 9 amb mascara
cantons:
        mov ax, bp                      ; index a cmask: (0,1,2,3)*2
        cmp ax, 2
        jb .f
        sub ax, CARDH - 4
.f:     shl ax, 1
        mov [cmi], ax
        xor cx, cx                      ; CX = byte (0 o 9)
.e:     cmp cx, [b0]
        jb .s
        cmp cx, [b1]
        ja .s
        mov si, [cmi]
        mov ah, [cmask+si]              ; AH = pixels de la carta
        or ah, ah
        jz .s
        mov al, bl                      ; origen: pla*480 + linia*10 + byte
        push ax
        xor ah, ah
        mov dx, CARDW/8*CARDH
        mul dx
        mov si, ax
        mov ax, bp
        mov dx, CARDW/8
        mul dx
        add si, ax
        add si, cx
        mov ax, [sp_y]
        add ax, bp
        call voffa
        add ax, [sp_bx]
        add ax, cx
        mov di, ax
        pop ax
        push ds
        mov dx, [sp_seg]
        mov ds, dx
        mov dl, [si]                    ; nou
        pop ds
        and dl, ah
        not ah
        and ah, [es:di]                 ; vell, fora de la carta
        or dl, ah
        mov [es:di], dl
.s:     inc word [cmi]
        add cx, CARDW/8 - 1
        cmp cx, CARDW/8 - 1
        jbe .e
        ret

; ---- redraw: el rectangle absolut rr. Si es pot, amb dibuix directe
redraw: cmp byte [dcache], 0
        je .vdi
        call som_dalt
        je .dir
.vdi:   jmp redraw_vdi
.dir:   push ax
        push bx
        push cx
        push dx
        push si
        push di
        call lock_ini                   ; retall = area de treball ...
        mov ax, [rr]                    ; ... i el rectangle demanat
        cmp ax, [clip]
        jle .x1
        mov [clip], ax
.x1:    mov ax, [rr+2]
        cmp ax, [clip+2]
        jle .y1
        mov [clip+2], ax
.y1:    mov ax, [rr]
        add ax, [rr+4]
        dec ax
        cmp ax, [clip+4]
        jge .x2
        mov [clip+4], ax
.x2:    mov ax, [rr+2]
        add ax, [rr+6]
        dec ax
        cmp ax, [clip+6]
        jge .y2
        mov [clip+6], ax
.y2:    mov ax, [clip+4]
        cmp ax, [clip]
        jl .fi
        mov ax, [clip+6]
        cmp ax, [clip+2]
        jl .fi
        mov ax, [clip]
        mov bx, [clip+2]
        mov cx, [clip+4]
        mov dx, [clip+6]
        call clip_set
        mov byte [dmode], 1
        call scene
        mov byte [dmode], 0
.fi:    call lock_fi
        pop di
        pop si
        pop dx
        pop cx
        pop bx
        pop ax
        ret

; escena: la taula dins [clip], directa si hi ha memoria cau (ja bloquejat i de dalt)
escena: mov al, [dcache]
        mov [dmode], al
        call scene
        mov byte [dmode], 0
        ret

; =====================================================================
;  VIDEO DIRECTE (PC1512, 640x200): B800h, linies entrellacades com la
;  CGA (parelles a 0000h, senars a 2000h, 80 bytes per linia) i 4 plans
;  a les mateixes adreces: port 3DDh tria els plans d'escriptura i
;  3DEh el pla de lectura. Rectangle: [vbx] (byte), [vy], [vwb], [vh].
; =====================================================================
voffa:  push bx                         ; AX = y -> AX = inici de linia
        push dx
        mov bx, ax
        shr ax, 1
        mov dx, 80
        mul dx
        test bl, 1
        jz .p
        add ax, 2000h
.p:     pop dx
        pop bx
        ret

; vr_get: copia el rectangle de la pantalla a DI
vr_get: push ax
        push bx
        push cx
        push dx
        push si
        push di
        push bp
        xor bx, bx                      ; BL = pla
.pl:    cmp byte [vplanes], 1
        je .np
        mov al, bl
        mov dx, P_RPLA
        out dx, al
.np:    mov dx, [vy]
        mov bp, [vh]
.ln:    mov ax, dx
        call voffa
        add ax, [vbx]
        mov si, ax
        mov cx, [vwb]
        push ds
        mov ax, VSEG
        mov ds, ax
        rep movsb
        pop ds
        inc dx
        dec bp
        jnz .ln
        inc bl
        cmp bl, [vplanes]
        jb .pl
        jmp vr_fi

; vr_inv: inverteix el rectangle de la pantalla (tots els plans)
vr_inv: push ax
        push bx
        push cx
        push dx
        push si
        push di
        push bp
        push es
        mov ax, VSEG
        mov es, ax
        xor bx, bx
.pl:    cmp byte [vplanes], 1
        je .np
        mov cl, bl
        mov al, 1
        shl al, cl
        mov dx, P_WPLA
        out dx, al
        mov al, bl
        mov dx, P_RPLA
        out dx, al
.np:    mov dx, [vy]
        mov bp, [vh]
.ln:    mov ax, dx
        call voffa
        add ax, [vbx]
        mov di, ax
        mov cx, [vwb]
.b:     not byte [es:di]
        inc di
        loop .b
        inc dx
        dec bp
        jnz .ln
        inc bl
        cmp bl, [vplanes]
        jb .pl
        pop es
        jmp vr_fi

; vr_put: copia SI al rectangle de la pantalla
vr_put: push ax
        push bx
        push cx
        push dx
        push si
        push di
        push bp
        push es
        mov ax, VSEG
        mov es, ax
        xor bx, bx
.pl:    cmp byte [vplanes], 1
        je .np
        mov cl, bl
        mov al, 1
        shl al, cl
        mov dx, P_WPLA
        out dx, al
.np:    mov dx, [vy]
        mov bp, [vh]
.ln:    mov ax, dx
        call voffa
        add ax, [vbx]
        mov di, ax
        mov cx, [vwb]
        rep movsb
        inc dx
        dec bp
        jnz .ln
        inc bl
        cmp bl, [vplanes]
        jb .pl
        pop es
vr_fi:  cmp byte [vplanes], 1           ; plans com els vol el GEM
        je .r
        mov al, 0Fh
        mov dx, P_WPLA
        out dx, al
        xor al, al
        mov dx, P_RPLA
        out dx, al
.r:     pop bp
        pop di
        pop si
        pop dx
        pop cx
        pop bx
        pop ax
        ret

; =====================================================================
;  SONS (nomes si l'opcio So esta marcada)
; =====================================================================
; nota: AX = divisor del PIT, CX = durada (~ms)
nota:     cmp byte [so], 0
        je .r
        call so_on
.w:     push cx
        mov cx, 400
.i:     loop .i
        pop cx
        loop .w
        call so_off
.r:     ret
sorollg:
        cmp byte [so], 0
        je .r
        call soroll
.r:     ret
s_agafa:  mov bl, 6
        mov cx, 50
        jmp sorollg
s_deixa:  mov bl, 60
        mov cx, 50
        jmp sorollg
s_robar:  mov bl, 10
        mov cx, 120
        jmp sorollg
s_recicla:
        mov bl, 5
        mov cx, 700
        jmp sorollg
s_error:  mov ax, 9000
        mov cx, 90
        jmp nota
s_pila:   mov ax, 1140                  ; do6 - sol6
        mov cx, 35
        call nota
        mov ax, 761
        mov cx, 60
        jmp nota
s_gira:   mov ax, 1800
        mov cx, 12
        jmp nota
s_rebot:  mov ax, 3000
        mov cx, 3
        jmp nota
s_fanfara:                              ; do5 mi5 sol5 do6
        mov si, fanfara
.n:     lodsw
        or ax, ax
        jz .r
        mov cx, ax
        lodsw
        xchg ax, cx
        push si
        call nota
        pop si
        jmp .n
.r:     ret

; =====================================================================
;  RUTINES GENERIQUES (les mateixes del Vint-i-u Enhanced)
; =====================================================================
rnd:    mov al, [rng+1]
        shr al, 1
        mov al, [rng]
        rcr al, 1
        lahf                            ; (l'EOR del 6502 no toca el carry)
        xor al, [rng+1]
        mov [rng+1], al
        sahf
        rcr al, 1
        xor al, [rng]
        mov [rng], al
        xor al, [rng+1]
        mov [rng+1], al
        ret

llavor: call ticks                      ; temporitzadors del PC
        mov [rng], ax
        mov al, 0
        out 43h, al
        in al, 40h
        mov ah, al
        in al, 40h
        xor [rng], ax
        or byte [rng+1], 1
        ret

ticks:  push ds                         ; comptador BIOS (18,2 Hz)
        mov ax, 40h
        mov ds, ax
        mov ax, [6Ch]
        pop ds
        ret

; evnt_multi: AX = flags, [tmr] = ms
evnt:   mov [int_in], ax
        mov word [int_in+2], 1          ; 1 clic
        mov word [int_in+4], 1          ; boto esquerre
        mov word [int_in+6], 1          ; premut
        mov di, int_in+8
        mov cx, 10
        xor ax, ax
        rep stosw
        mov ax, [tmr]
        mov [int_in+28], ax
        mov word [int_in+30], 0
        mov word [addr_in], msgbuf
        mov [addr_in+2], ds
        AES 25,16,7,1,0
        ret

; ---- form_alert: AX = boto per defecte, SI = text. Torna AX = boto premut
alerta: push bx
        push cx
        push dx
        mov [int_in], ax
        mov [addr_in], si
        mov [addr_in+2], ds
        mov word [int_in+2], 0
        AES 52,1,1,1,0                  ; form_alert
        pop dx
        pop cx
        pop bx
        ret

; ---- som la finestra de dalt de tot? ZF=1 si si
som_dalt:
        push ax
        mov word [int_in], 0
        mov word [int_in+2], WF_TOP
        AES 104,2,5,0,0
        mov ax, [int_out+2]
        cmp ax, [whandle]
        pop ax
        ret

; soroll blanc com el canal de soroll del VIC: CX = mostres, BL = retard
; (mes retard = soroll mes greu i mes llarg). Mou directament el con.
soroll: push ax
        push cx
        push dx
        in al, 61h
        and al, 0FCh
        mov ah, al
.m:     mov dx, [nz]                    ; LFSR de 16 bits
        shr dx, 1
        jnc .z
        xor dx, 0B400h
.z:     mov [nz], dx
        mov al, ah
        test dl, 1
        jz .o
        or al, 2
.o:     out 61h, al
        push cx
        mov cl, bl
        xor ch, ch
.w:     loop .w
        pop cx
        loop .m
        mov al, ah
        out 61h, al
        pop dx
        pop cx
        pop ax
        ret

so_on:  push ax                         ; AX = divisor del PIT
        mov al, 0B6h
        out 43h, al
        pop ax
        out 42h, al
        mov al, ah
        out 42h, al
        in al, 61h
        or al, 3
        out 61h, al
        ret
so_off: push ax
        in al, 61h
        and al, 0FCh
        out 61h, al
        pop ax
        ret

; inval: AX, BX, CX, DX = x, y, w, h relatius a l'area de treball
inval:  push ax
        add ax, [ox]
        mov [rr], ax
        mov ax, bx
        add ax, [oy]
        mov [rr+2], ax
        mov [rr+4], cx
        mov [rr+6], dx
        pop ax
        jmp redraw
; redraw_vdi: redibuixa el rectangle absolut rr amb el VDI
redraw_vdi: push ax
        push bx
        push cx
        push dx
        push si
        push di
        mov word [int_in], 1
        AES 107,1,1,0,0                 ; wind_update(BEG_UPDATE)
        mov word [int_in], 256
        AES 78,1,1,1,0                  ; graf_mouse(M_OFF)
        mov ax, WF_FIRSTXYWH
.s:     mov [int_in+2], ax
        call posa_wh
        AES 104,2,5,0,0
        cmp word [int_out+6], 0
        je .fi
        cmp word [int_out+8], 0
        je .fi
        call retalla
        jc .nx
        mov word [intin], 1             ; vs_clip(on)
        mov si, clip
        mov di, ptsin
        mov cx, 4
        rep movsw
        VDI 129,2,1
        call scene
.nx:    mov ax, WF_NEXTXYWH
        jmp .s
.fi:    mov word [int_in], 257
        AES 78,1,1,1,0                  ; graf_mouse(M_ON)
        mov word [int_in], 0
        AES 107,1,1,0,0                 ; wind_update(END_UPDATE)
        pop di
        pop si
        pop dx
        pop cx
        pop bx
        pop ax
        ret

; interseccio int_out[1..4] amb rr -> clip (x1,y1,x2,y2); CF=1 si es buida
retalla:
        mov ax, [int_out+2]
        mov bx, [rr]
        cmp ax, bx
        jge .a1
        mov ax, bx
.a1:    mov [clip], ax
        mov ax, [int_out+4]
        mov bx, [rr+2]
        cmp ax, bx
        jge .a2
        mov ax, bx
.a2:    mov [clip+2], ax
        mov ax, [int_out+2]
        add ax, [int_out+6]
        mov bx, [rr]
        add bx, [rr+4]
        cmp ax, bx
        jle .a3
        mov ax, bx
.a3:    dec ax
        mov [clip+4], ax
        mov ax, [int_out+4]
        add ax, [int_out+8]
        mov bx, [rr+2]
        add bx, [rr+6]
        cmp ax, bx
        jle .a4
        mov ax, bx
.a4:    dec ax
        mov [clip+6], ax
        mov ax, [clip+4]
        cmp ax, [clip]
        jl .buit
        mov ax, [clip+6]
        cmp ax, [clip+2]
        jl .buit
        clc
        ret
.buit:  stc
        ret

; ---- desc_fig: AL = figura (0..11 J Q K de cada pal, 12 ornament de l'as).
;      Descomprimeix la imatge de 5 colors (vegeu SOLITARI.INC), en fa 4 capes
;      d'un bit i les passa al format del dispositiu (fdev_m). Guarda l'ultima.
desc_fig:
        cmp al, [fig_cache]
        jne .nova
        ret
.nova:  push ax
        push bx
        push cx
        push dx
        push si
        push di
        push bp
        mov [fig_cache], al
        xor ah, ah                      ; figtab: 3 paraules per figura
        mov bx, ax
        shl bx, 1
        add bx, ax
        shl bx, 1
        mov si, [figtab+bx]
        mov ax, [figtab+bx+2]
        mov [fw], ax
        add ax, 15
        mov cl, 4
        shr ax, cl
        mov [fwd], ax
        mov ax, [figtab+bx+4]
        mov [fh], ax
        mul word [fw]
        mov di, idxbuf                  ; tirades -> un byte per pixel
        mov dx, di
        add dx, ax
.r:     cmp di, dx
        jae .pack
        lodsb
        mov ah, al
        and al, 31
        cmp al, 31
        jne .curt
        lodsb                           ; tirada llarga: byte + 32
        mov cl, al
        xor ch, ch
        add cx, 32
        jmp short .sym
.curt:  mov cl, al
        xor ch, ch
        inc cx
.sym:   mov al, ah
        push cx
        mov cl, 5
        shr al, cl
        pop cx
        cmp al, 5
        je .copia
        rep stosb
        jmp .r
.copia: push si                         ; igual que la linia de sobre
        mov si, di
        sub si, [fw]
        rep movsb
        pop si
        jmp .r
.pack:  mov byte [capa], 1              ; una capa d'un bit per color 1..4
        mov di, fstd
.cp:    mov si, idxbuf
        mov dx, [fh]
.row:   mov bp, [fw]
        mov cx, [fwd]
.wd:    push cx
        xor bx, bx
        mov cx, 16
.px:    shl bx, 1
        or bp, bp
        jz .b
        dec bp
        lodsb
        cmp al, [capa]
        jne .b
        or bl, 1
.b:     loop .px
        mov [di], bx
        add di, 2
        pop cx
        loop .wd
        dec dx
        jnz .row
        inc byte [capa]
        mov al, [capa]
        cmp al, 5
        jae .tr
        dec al
        xor ah, ah
        mov cx, LSTRIDE
        mul cx
        add ax, fstd
        mov di, ax
        jmp .cp
.tr:    mov si, fstd_m                  ; vr_trnfm de cada capa
        mov di, fdev_m
        mov bx, fstd
        mov bp, fdev
        mov cx, 4
.t:     push cx
        mov [si], bx
        mov [si+2], ds
        mov [di], bp
        mov [di+2], ds
        mov ax, [fw]
        mov [si+4], ax
        mov [di+4], ax
        mov ax, [fh]
        mov [si+6], ax
        mov [di+6], ax
        mov ax, [fwd]
        mov [si+8], ax
        mov [di+8], ax
        mov word [si+10], 1             ; origen: format estandard
        mov word [di+10], 0             ; desti: format del dispositiu
        mov word [si+12], 1
        mov word [di+12], 1
        mov [contrl+14], si
        mov [contrl+16], ds
        mov [contrl+18], di
        mov [contrl+20], ds
        VDI 110,0,0                     ; vr_trnfm
        add si, 20
        add di, 20
        add bx, LSTRIDE
        add bp, LSTRIDE
        pop cx
        loop .t
        pop bp
        pop di
        pop si
        pop dx
        pop cx
        pop bx
        pop ax
        ret

; ---- pal en bitmap: AX = centre x, BX = centre y (relatius), CL = mida
;      (0 petit, 1 mitja, 2 gran); pal = [csuit], color = [fcol]
pip:    push dx
        mov dl, cl
        shl dl, 1
        shl dl, 1
        add dl, [csuit]
        call corona
        pop dx
        ret
; corona: el mateix amb DL = index directe a bmtab
; vrt_cpyfm no respecta vs_clip: el retall es fa aqui
corona: push ax
        push bx
        push cx
        push dx
        push si
        xor dh, dh
        mov si, dx
        shl si, 1
        mov si, [bmtab+si]              ; SI -> MFDB del dispositiu
        jmp short blit_c
; blit_si: el mateix amb SI = MFDB del dispositiu
blit_si:
        push ax
        push bx
        push cx
        push dx
        push si
blit_c:        mov cx, [si+4]                  ; amplada
        mov dx, [si+6]                  ; alcada
        add ax, [ox]
        push cx
        shr cx, 1
        sub ax, cx
        pop cx
        add bx, [oy]
        push dx
        shr dx, 1
        sub bx, dx
        pop dx
        dec cx
        dec dx
        mov word [ptsin], 0             ; origen: 0,0 - w-1,h-1
        mov word [ptsin+2], 0
        mov [ptsin+4], cx
        mov [ptsin+6], dx
        mov [ptsin+8], ax               ; desti
        mov [ptsin+10], bx
        add ax, cx
        mov [ptsin+12], ax
        add bx, dx
        mov [ptsin+14], bx
        mov ax, [clip]                  ; retallar a clip
        sub ax, [ptsin+8]
        jle .c1
        add [ptsin], ax
        add [ptsin+8], ax
.c1:    mov ax, [ptsin+12]
        sub ax, [clip+4]
        jle .c2
        sub [ptsin+4], ax
        sub [ptsin+12], ax
.c2:    mov ax, [clip+2]
        sub ax, [ptsin+10]
        jle .c3
        add [ptsin+2], ax
        add [ptsin+10], ax
.c3:    mov ax, [ptsin+14]
        sub ax, [clip+6]
        jle .c4
        sub [ptsin+6], ax
        sub [ptsin+14], ax
.c4:    mov ax, [ptsin+8]
        cmp ax, [ptsin+12]
        jg .fi
        mov ax, [ptsin+10]
        cmp ax, [ptsin+14]
        jg .fi
        mov [contrl+14], si             ; origen: el nostre bitmap
        mov [contrl+16], ds
        mov word [contrl+18], scrmfdb   ; desti: la pantalla
        mov [contrl+20], ds
        mov word [intin], 2             ; transparent
        mov al, [fcol]
        xor ah, ah
        mov [intin+2], ax               ; color dels 1
        mov word [intin+4], 0
        VDI 121,4,3                     ; vrt_cpyfm
.fi:    pop si
        pop dx
        pop cx
        pop bx
        pop ax
        ret

; ---- utilitats del VDI
; vis_rect: AX,BX,CX,DX rect relatiu; CF=1 si no toca clip
vis_rect:
        push ax
        push bx
        add ax, [ox]
        cmp ax, [clip+4]
        jg .no
        add ax, cx
        dec ax
        cmp ax, [clip]
        jl .no
        mov ax, bx
        add ax, [oy]
        cmp ax, [clip+6]
        jg .no
        add ax, dx
        dec ax
        cmp ax, [clip+2]
        jl .no
        pop bx
        pop ax
        clc
        ret
.no:    pop bx
        pop ax
        stc
        ret

rect_abs:                               ; ptsin = rect AX,BX,CX,DX en absolut
        push ax
        add ax, [ox]
        mov [ptsin], ax
        add ax, cx
        dec ax
        mov [ptsin+4], ax
        mov ax, bx
        add ax, [oy]
        mov [ptsin+2], ax
        add ax, dx
        dec ax
        mov [ptsin+6], ax
        pop ax
        ret

fill_attrs:                             ; farciment solid de color [fcol]
        push ax
        push cx
        push dx
        mov word [intin], 1
        VDI 23,0,1
        mov al, [fcol]
        xor ah, ah
        mov [intin], ax
        VDI 25,0,1
        pop dx
        pop cx
        pop ax
        ret

fill_rect:                              ; rectangle AX,BX,CX,DX de color [fcol]
        push ax
        push cx
        push dx
        call fill_attrs
        pop dx
        pop cx
        pop ax
        call rect_abs
        push ax
        push cx
        push dx
        VDI 114,2,0
        pop dx
        pop cx
        pop ax
        ret

rfbox:                                  ; rectangle arrodonit ple
        push ax
        push cx
        push dx
        call fill_attrs
        pop dx
        pop cx
        pop ax
        call rect_abs
        push ax
        push cx
        push dx
        VDI 11,2,0,9
        pop dx
        pop cx
        pop ax
        ret

; text_at: AX,BX = x,y relatius (dalt), SI = text, CX = llargada, [tcolor]
text_at:
        push ax
        push bx
        push cx
        push dx
        push si
        push di
        push cx
        push ax
        mov al, [tcolor]
        xor ah, ah
        mov [intin], ax
        VDI 22,0,1                      ; vst_color
        pop ax
        pop cx
        add ax, [ox]
        mov [ptsin], ax
        mov ax, bx
        add ax, [oy]
        mov [ptsin+2], ax
        mov dx, cx
        mov di, intin
.c:     lodsb
        xor ah, ah
        stosw
        loop .c
        call vdi_t                      ; v_gtext
        db 8, 1, 0, 0
        mov [contrl+6], dx              ; (n_intin = llargada del text)
        call crida_vdi
        pop di
        pop si
        pop dx
        pop cx
        pop bx
        pop ax
        ret

posa_wh:
        mov ax, [whandle]
        mov [int_in], ax
        ret

; aes_t / vdi_t: llegeixen els comptadors darrere el CALL i salten
aes_t:  push bp
        mov bp, sp
        push si
        push ax
        mov si, [bp+2]
        add word [bp+2], 5
        mov bp, control
        mov cx, 5
.l:     lodsb
        xor ah, ah
        mov [ds:bp], ax
        inc bp
        inc bp
        loop .l
        pop ax
        pop si
        pop bp
        jmp crida_aes

vdi_t:  push bp
        mov bp, sp
        push si
        push ax
        mov si, [bp+2]
        add word [bp+2], 4
        xor ah, ah
        lodsb
        mov [contrl], ax
        lodsb
        mov [contrl+2], ax
        lodsb
        mov [contrl+6], ax
        lodsb
        mov [contrl+10], ax
        mov ax, [vhandle]
        mov [contrl+12], ax
        pop ax
        pop si
        pop bp
        cmp byte [contrl], 8            ; v_gtext: el text el posa qui crida
        je .r
        jmp crida_vdi
.r:     ret

crida_aes:
        push bx
        push si
        push di
        push bp
        push ds
        push es
        mov cx, 200                     ; AES: ES:BX -> bloc de parametres
        push ds
        pop es
        mov bx, aespb
        int 0EFh
        pop es
        pop ds
        pop bp
        pop di
        pop si
        pop bx
        cld
        mov ax, [int_out]
        ret

crida_vdi:
        push bx
        push si
        push di
        push bp
        push ds
        push es
        mov cx, 473h                    ; VDI: DS:DX -> bloc de parametres
        mov dx, vdipb
        int 0EFh
        pop es
        pop ds
        pop bp
        pop di
        pop si
        pop bx
        cld
        ret

init_punters:
        mov ax, ds
        mov bx, aespb+2
        mov cx, 11
.l:     mov [bx], ax
        add bx, 4
        loop .l
        ret


; =====================================================================
;  DADES
; =====================================================================
TITLEN  equ 64
s_titol: db ' Solitari', 0
s_punts: db '   Punts: ', 0
s_vegas: db '   Vegas: ', 0
s_temps: db '   Temps: ', 0
cm_rows: db 0, 1, CARDH-2, CARDH-1
s_prep:  db ' Solitari - preparant les cartes... ', 0
rankch: db 'A234567890JQK'
deu:    db '10'
draw3:  db 1                    ; opcions (es mantenen entre partides)
modep:  db 0                    ; 0 estandard, 1 Vegas, 2 sense punts
so:     db 1
buidaq: db 1                    ; columna buida: qualsevol carta
colcapa: db C_RED, C_BLU, GROC, NEGRE   ; colors de les capes de les figures

; pips de les cartes 2..10, disposicio de les cartes reals: nombre de pips i,
; per a cadascun, columna*16 + mitja fila (columnes 0 esquerra, 1 centre,
; 2 dreta; mitges files 0 dalt .. 12 baix)
pipidx: db 0, 3, 7, 12, 18, 25, 33, 42, 52
pips:   db 2, 16, 28   ; 2
        db 3, 16, 22, 28   ; 3
        db 4, 0, 32, 12, 44   ; 4
        db 5, 0, 32, 22, 12, 44   ; 5
        db 6, 0, 32, 6, 38, 12, 44   ; 6
        db 7, 0, 32, 19, 6, 38, 12, 44   ; 7
        db 8, 0, 32, 19, 6, 38, 25, 12, 44   ; 8
        db 9, 0, 32, 4, 36, 22, 8, 40, 12, 44   ; 9
        db 10, 0, 32, 18, 4, 36, 8, 40, 26, 12, 44   ; 10

; valor (0 = as .. 12 = rei) i pal de cada carta 0..51
rank_of:
%assign i 0
%rep 52
        db i % 13
%assign i i+1
%endrep
suit_of:
%assign i 0
%rep 52
        db i / 13
%assign i i+1
%endrep

colvdi: db TAPET, BLANC, NEGRE, C_RED, C_BLU, GROC   ; simbols dels fotogrames finals
lmask:  db 0FFh, 7Fh, 3Fh, 1Fh, 0Fh, 07h, 03h, 01h, 00h
dmask:  db 08h, 40h, 01h, 20h, 04h, 80h, 10h, 02h  ; ordre de la dissolucio
suau:   db 0, 2, 6, 12, 20, 32, 44, 52, 58, 62, 64 ; lliscament suavitzat (t*64)

; do5 mi5 sol5 do6 (divisor del PIT, ms)
        align 2
fanfara: dw 4561, 110, 3620, 110, 3044, 110, 2280, 300, 0
nz:      dw 0ACE1h              ; llavor del soroll

menu_tab:
        dw M_QUANT, m_quant, M_NOVA, m_nova, M_DESFER, m_desf
        dw M_SORTIR, m_surt, M_R1, m_r1, M_R3, m_r3
        dw M_PSTD, m_pstd, M_PVEG, m_pveg, M_PCAP, m_pcap, M_SO, m_so
        dw M_PISTA, m_pista, M_BUIDA, m_buida
        dw M_AJ1, m_aj1, M_AJ2, m_aj2, M_AJ3, m_aj3, 0

al_quant: db "[1][SOLITARI per a GEM| |Klondike per a Amstrad PC1512|Cartes de Vint-i-u Enhanced][D'acord]", 0
al_nova: db "[2][Vols deixar aquesta partida|i comencar-ne una de nova?][Nova|Continuar]", 0
al_sortir: db "[2][Vols sortir del Solitari?][Sortir|Continuar]", 0
al_guanya: db "[0][Enhorabona!| |Has guanyat la partida.|Vols jugar-ne una altra?][Nova|Tancar]", 0
al_aj1: db "[0][COM ES JUGA| |Posa les 52 cartes a les 4|piles de dalt a la dreta, per|pals, de l'As fins al Rei.][Seguent|Tanca]", 0
al_aj2: db "[0][A les 7 columnes, ordena les|cartes de mes a menys, i|alternant vermell i negre.|Columna buida: un Rei (o el|que vulguis, a Opcions).][Seguent|Tanca]", 0
al_aj3: db "[0][Clica el munt per robar|cartes (1 o 3, a Opcions).|Quan s'acaba, clica el lloc|buit per tornar-lo a girar.][Seguent|Tanca]", 0
al_aj4: db "[0][Partida > Desfer tira enrere|l'ultim moviment, i Pista et|mostra una jugada possible.|Les tapades es giren soles.][D'acord]", 0
al_nopista: db "[3][No queda cap jugada.| |Pots desfer o comencar una|partida nova.][D'acord]", 0
al_pista: db "[1][Hi ha alguna jugada.|Mira les columnes i el munt.][D'acord]", 0
al_ratoli: db "[0][RATOLI| |Arrossega una carta, o una|escala de cartes, on vulguis.|Un clic la puja a dalt.][D'acord]", 0
al_pt1: db "[0][PUNTUACIO ESTANDARD|Descartades a columna: +5|Carta a les piles de dalt: +10|Girar una carta: +5|Treure de dalt: -15][Seguent|Tanca]", 0
al_pt2: db "[0][Cada 10 segons: -2|Tornar a girar el munt:|-100 robant 1, -20 robant 3|En guanyar, bonus pel temps.][Seguent|Tanca]", 0
al_pt3: db "[0][PUNTUACIO VEGAS|Comences amb -52 $ i guanyes|5 $ per carta a les piles.|Robant 1: una sola passada.|Robant 3: tres passades.][D'acord]", 0

; ---- arbre de la barra de menus (coordenades en caracters; rsrc_obfix)
;      next, head, tail, tipus, flags, estat, ob_spec (2 paraules), x, y, w, h
        align 2
menutree:
        dw -1, 1, 7, G_IBOX, 0, 0, 0, 0, 0, 0, 80, 25   ; 0
        dw 7, 2, 2, G_BOX, 0, 0, 1100h, 0, 0, 0, 80, 0201h   ; 1
        dw 1, 3, 6, G_IBOX, 0, 0, 0, 0, 2, 0, 35, 0301h   ; 2
        dw 4, -1, -1, G_TITLE, 0, 0, t_tit0, 0, 0, 0, 10, 0301h   ; 3
        dw 5, -1, -1, G_TITLE, 0, 0, t_tit1, 0, 10, 0, 9, 0301h   ; 4
        dw 6, -1, -1, G_TITLE, 0, 0, t_tit2, 0, 19, 0, 9, 0301h   ; 5
        dw 2, -1, -1, G_TITLE, 0, 0, t_tit3, 0, 28, 0, 7, 0301h   ; 6
        dw 0, 8, 33, G_IBOX, 0, 0, 0, 0, 0, 0301h, 80, 19   ; 7
        dw 17, 9, 16, G_BOX, 0, 0, 1100h, 0FFh, 2, 0, 22, 8   ; 8
        dw 10, -1, -1, G_STRING, 0, 0, mt_quant, 0, 0, 0, 22, 1   ; 9
        dw 11, -1, -1, G_STRING, 0, DISABLED, m_sep22, 0, 0, 1, 22, 1   ; 10
        dw 12, -1, -1, G_STRING, 0, 0, m_acc1, 0, 0, 2, 22, 1   ; 11
        dw 13, -1, -1, G_STRING, 0, 0, m_acc2, 0, 0, 3, 22, 1   ; 12
        dw 14, -1, -1, G_STRING, 0, 0, m_acc3, 0, 0, 4, 22, 1   ; 13
        dw 15, -1, -1, G_STRING, 0, 0, m_acc4, 0, 0, 5, 22, 1   ; 14
        dw 16, -1, -1, G_STRING, 0, 0, m_acc5, 0, 0, 6, 22, 1   ; 15
        dw 8, -1, -1, G_STRING, 0, 0, m_acc6, 0, 0, 7, 22, 1   ; 16
        dw 23, 18, 22, G_BOX, 0, 0, 1100h, 0FFh, 12, 0, 16, 5   ; 17
        dw 19, -1, -1, G_STRING, 0, 0, mt_nova, 0, 0, 0, 16, 1   ; 18
        dw 20, -1, -1, G_STRING, 0, 0, mt_desfer, 0, 0, 1, 16, 1   ; 19
        dw 21, -1, -1, G_STRING, 0, 0, mt_pista, 0, 0, 2, 16, 1   ; 20
        dw 22, -1, -1, G_STRING, 0, DISABLED, m_sep16, 0, 0, 3, 16, 1   ; 21
        dw 17, -1, -1, G_STRING, 0, 0, mt_sortir, 0, 0, 4, 16, 1   ; 22
        dw 33, 24, 32, G_BOX, 0, 0, 1100h, 0FFh, 21, 0, 28, 9   ; 23
        dw 25, -1, -1, G_STRING, 0, 0, mt_r1, 0, 0, 0, 28, 1   ; 24
        dw 26, -1, -1, G_STRING, 0, 0, mt_r3, 0, 0, 1, 28, 1   ; 25
        dw 27, -1, -1, G_STRING, 0, DISABLED, m_sep28, 0, 0, 2, 28, 1   ; 26
        dw 28, -1, -1, G_STRING, 0, 0, mt_pstd, 0, 0, 3, 28, 1   ; 27
        dw 29, -1, -1, G_STRING, 0, 0, mt_pveg, 0, 0, 4, 28, 1   ; 28
        dw 30, -1, -1, G_STRING, 0, 0, mt_pcap, 0, 0, 5, 28, 1   ; 29
        dw 31, -1, -1, G_STRING, 0, DISABLED, m_sep28, 0, 0, 6, 28, 1   ; 30
        dw 32, -1, -1, G_STRING, 0, 0, mt_buida, 0, 0, 7, 28, 1   ; 31
        dw 23, -1, -1, G_STRING, 0, 0, mt_so, 0, 0, 8, 28, 1   ; 32
        dw 7, 34, 36, G_BOX, 0, 0, 1100h, 0FFh, 30, 0, 18, 3   ; 33
        dw 35, -1, -1, G_STRING, 0, 0, mt_aj1, 0, 0, 0, 18, 1   ; 34
        dw 36, -1, -1, G_STRING, 0, 0, mt_aj2, 0, 0, 1, 18, 1   ; 35
        dw 33, -1, -1, G_STRING, LASTOB, 0, mt_aj3, 0, 0, 2, 18, 1   ; 36
t_tit0: db ' Solitari ', 0
t_tit1: db ' Partida ', 0
t_tit2: db ' Opcions ', 0
t_tit3: db ' Ajuda ', 0
mt_quant: db '  Quant a Solitari... ', 0
m_sep22: db '----------------------', 0
m_acc1: db '  Desk Accessory      ', 0
m_acc2: db '  Desk Accessory      ', 0
m_acc3: db '  Desk Accessory      ', 0
m_acc4: db '  Desk Accessory      ', 0
m_acc5: db '  Desk Accessory      ', 0
m_acc6: db '  Desk Accessory      ', 0
mt_nova: db '  Nova partida  ', 0
mt_desfer: db '  Desfer        ', 0
mt_pista: db '  Pista         ', 0
m_sep16: db '----------------', 0
mt_sortir: db '  Sortir        ', 0
mt_r1: db '  Robar 1 carta             ', 0
mt_r3: db '  Robar 3 cartes            ', 0
m_sep28: db '----------------------------', 0
mt_pstd: db '  Puntuacio estandard       ', 0
mt_pveg: db '  Puntuacio Vegas           ', 0
mt_pcap: db '  Sense puntuacio           ', 0
mt_buida: db '  Columna buida: qualsevol  ', 0
mt_so: db '  So                        ', 0
mt_aj1: db '  Com es juga...  ', 0
mt_aj2: db '  Puntuacio...    ', 0
mt_aj3: db '  Ratoli...       ', 0

        align 2
%include "SOLITARI.INC"
        align 2
aespb:    dw control,0, aesglob,0, int_in,0, int_out,0, addr_in,0, addr_out,0
vdipb:    dw contrl,0, intin,0, ptsin,0, intout,0, ptsout,0

        align 16
fi_imatge:

; =====================================================================
;  BSS: dades a zero que no ocupen lloc al fitxer
; =====================================================================
        absolute fi_imatge
control:  resw 5
aesglob:  resw 15
int_in:   resw 16
int_out:  resw 8
addr_in:  resw 4
addr_out: resw 2
contrl:   resw 12
intin:    resw 128
ptsin:    resw 128
intout:   resw 128
ptsout:   resw 128
msgbuf:   resw 8
scrmfdb:  resw 10               ; MFDB de la pantalla (tot a zero)
        BSS_BITMAPS
idxbuf:   resb FIG_MAXW*FIG_MAXH ; figura descomprimida, un byte per pixel
fstd:     resb 4*LSTRIDE        ; les 4 capes en format estandard
fdev:     resb 4*LSTRIDE        ; i en format del dispositiu
fstd_m:   resw 40               ; MFDB de cada capa (estandard)
fdev_m:   resw 40               ;   i (dispositiu)
fw:       resw 1
fh:       resw 1
fwd:      resw 1
fig_cache: resb 1               ; figura descomprimida ara (0FFh = cap)
capa:     resb 1
        alignb 2
dragbuf:  resb 10*200*4         ; cartes arrossegades (4 plans)
savebuf:  resb 10*200*4         ; el que hi ha sota

estat:                          ; ---- estat de la partida (per desfer)
piles:    resb NPILE*PSZ
wfan:     resb 1                ; cartes del ventall de descartades
passes:   resb 1                ; vegades que s'ha girat el munt
score:    resw 1
estat_fi:
ESTAT_SZ  equ estat_fi - estat
tmpst:    resb ESTAT_SZ         ; abans del moviment en curs
undost:   resb ESTAT_SZ         ; per a "Desfer"
deck:     resb 52
titbuf:   resb TITLEN
titprev:  resb TITLEN           ; el titol que te el GEM

        alignb 2
vhandle:  resw 1
whandle:  resw 1
wkx:      resw 1                ; area de treball de la finestra
wky:      resw 1
workw:    resw 1
workh:    resw 1
ox:       resw 1                ; origen del contingut (absolut, alineat a byte)
oy:       resw 1
marg_x:   resw 1
marg_y:   resw 1
avail:    resw 1                ; alcada per als ventalls de les columnes
escr:     resw 4
rr:       resw 4
clip:     resw 4
tmr:      resw 1
quins:    resw 1
mx0:      resw 1                ; on s'ha premut el boto
my0:      resw 1
rx:       resw 1
ry:       resw 1
hx:       resw 1                ; carta tocada (relativa)
hy:       resw 1
hxin:     resw 1
sx:       resw 1                ; escala arrossegada: posicio i alcada
sy:       resw 1
sh:       resw 1
fx:       resw 1                ; on s'ha deixat
fy:       resw 1
cardx:    resw 1
cardy:    resw 1
rng:      resw 1
secs:     resw 1
t0:       resw 1
deu_s:    resw 1
cd:       resw 1
cu1:      resw 1
scr_xmax: resw 1
scr_ymax: resw 1
vbx:      resw 1                ; rectangle de video directe
vy:       resw 1
vwb:      resw 1
vh:       resw 1
bx0:      resw 1
y0v:      resw 1
bxmin:    resw 1
bxmax:    resw 1
ymin:     resw 1
ymax:     resw 1
nbx:      resw 1
nyv:      resw 1
btn:      resw 1
velx:     resw 1
vely:     resw 1
hcol:     resb 1
hpila:    resb 1
hidx:     resb 1
m_src:    resb 1                ; moviment: pila origen, index, desti
m_k:      resb 1
m_dst:    resb 1
mcnt:     resb 1
girada:   resb 1
jugant:   resb 1                ; el rellotge corre
fi:       resb 1                ; partida guanyada
undo_ok:  resb 1
lc:       resb 1
dof:      resb 1
uof:      resb 1
cardv:    resb 1
csuit:    resb 1
crank:    resb 1
prow:     resb 1
fcol:     resb 1
tcolor:   resb 1
dvok:     resb 1                ; video directe disponible
vplanes:  resb 1
cel_n:    resb 1
cel_f:    resb 1
cs_src:   resb 1
pas_k:    resb 1
fin_k:    resb 1
hwcol:    resb 6                ; color de maquinari de cada simbol
hwv:      resb 1
tmp4:     resb 4
        alignb 2
linebuf:  resb 4*80             ; una linia dels fotogrames finals, 4 plans
vent_x:   resw 1
vent_y:   resw 1
rei_x0:   resw 1
rei_x3:   resw 1
rei_y:    resw 1
t_pas:    resw 1
t_fr:     resw 1
t_esp:    resw 1
fw_:      resw 1
fh_:      resw 1
fwb:      resw 1
fx0b:     resw 1
fy0:      resw 1
sbx:      resw 1
sbn:      resw 1
dcache:   resb 1                ; hi ha memoria cau d'imatges
dmode:    resb 1                ; dibuixant en mode directe
pimg:     resb 1
cant:     resb 1
cmask:    resb 8                ; mascares dels cantons
        alignb 2
cseg:     resw 1                ; segment de les imatges
dhgt:     resw 1                ; linies a dibuixar de la carta
cmi:      resw 1
sp_seg:   resw 1
sp_bx:    resw 1
sp_y:     resw 1
b0:       resw 1
b1:       resw 1
l0:       resw 1
l1:       resw 1
fi_bss:
