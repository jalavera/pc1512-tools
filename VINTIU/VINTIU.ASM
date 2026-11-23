; =====================================================================
;  VINT-I-U ENHANCED  -  versio GEM (Amstrad PC1512, GEM Desktop 2.0)
;  Port del joc del VIC-20 (veintiuna_enhanced v5) a 8086 + GEM AES/VDI
;
;  Compilar:  python3 build.py VINTIU.ASM VINTIU.APP   (requereix nasm)
;
;  - Mateixa logica, regles, missatges i temps que la versio VIC-20.
;  - Cartes dibuixades amb el VDI (pals amb poligons), tapet verd.
;  - Teclat igual que al VIC (D/C/P, xifres, RETURN, retroces) i, a mes,
;    es pot clicar Doblar / Carta / Plantar-se amb el ratoli.
;  - Les esperes es fan amb evnt_multi: la finestra es pot moure i
;    redibuixar en qualsevol moment. El boto de tancar surt del joc.
;  - So per l'altaveu del PC (tic de les lletres, frrr del remenat, clac).
;  - Crides GEM:  AES -> INT EFh, CX=200, ES:BX   VDI -> CX=473h, DS:DX
; =====================================================================

%include "exe.inc"

; ---------- disposicio de la finestra (pixels, 640x200) ----------
W       equ 608                 ; amplada de l'area de treball
CARD_W      equ 144                 ; carta: amplada
CARD_H      equ 88                  ;        alcada (pixels alts del PC1512)
FSTEP   equ 112                 ; separacio de les cartes del ventall
FX      equ (W - (4*FSTEP + CARD_W)) / 2
PX      equ (W - CARD_W) / 2        ; pila del remenat
NLLISC  equ 20                  ; cartes que llisquen en cada remenat
DPAS    equ 6                   ; pas (bytes) de la carta repartida
DINI    equ 28                  ; on apareix la carta repartida (bytes des de la pila)

; ---------- interior de la carta ----------
IX      equ 6                   ; index de dalt
IY      equ 4
SPX     equ 12                  ; pal petit sota l'index (centre i mida)
SPY     equ 20
GY0     equ 16                  ; graella de pips: fila 0, separacio, columnes
GDY     equ 9
GDX     equ 28
AS_Y    equ 44                  ; as
FRX     equ 32                  ; marc de les figures
FRY     equ 13
FRW     equ 79
FRH     equ 61
BKX     equ 8                   ; dors
BKY     equ 6
CHW     equ 8                   ; amplada de caracter del GEM
NCOL    equ 28                  ; columnes de missatge (com al VIC)
MSGX    equ (W - NCOL*CHW) / 2
MSGY    equ 4

; ---------- temps, en unitats de 1/30 s (com al VIC) ----------
D_STEP  equ 1
D_TYPE  equ 1
D_CLAC  equ 1
D_CARD  equ 10
D_BANK  equ 40
D_MSG   equ 90
D_RUIN  equ 150

; ---------- colors VDI ----------
BLANC   equ 0
NEGRE   equ 1
C_RED   equ 2
C_GRN   equ 3
C_BLU   equ 4
C_PUR   equ 7
GROC    equ 6
LSTRIDE equ FIG_MAXWD*FIG_MAXH*2    ; bytes d'una capa de figura
TAPET   equ 3
INV     equ 1                   ; marcador: la lletra seguent en invers

; ---------- GEM ----------
MU_KEYBD  equ 1
MU_BUTTON equ 2
MU_MESAG  equ 16
MU_TIMER  equ 32
WM_REDRAW equ 20
WM_TOPPED equ 21
WM_CLOSED equ 22
WM_MOVED  equ 28
WF_NAME   equ 2
WF_WORKXYWH  equ 4
WF_CURRXYWH  equ 5
WF_TOP       equ 10
WF_FIRSTXYWH equ 11
WF_NEXTXYWH  equ 12
TIPUS_FIN    equ 0003h          ; NAME | CLOSER (fixa: no es pot moure)

; crides GEM compactes: un CALL seguit dels comptadors en bytes
; (com el pmsg del VIC): 8 bytes per crida en lloc de ~33
%macro AES 5                    ; opcode, n_int_in, n_int_out, n_addr_in, n_addr_out
        call aes_t
        db %1, %2, %3, %4, %5
%endmacro

%macro VDI 3-4 0                ; opcode, n_ptsin, n_intin, subfuncio
        call vdi_t
        db %1, %2, %3, %4
%endmacro

; missatges inline (com pmsg del VIC): fila, color, columna, text
%macro MSG 4+
        call pmsg
        db %1, %2, %3, %4, 0
%endmacro
%macro MSGR 4+                  ; en acabar salta a result
        call pmsg
        db %1, %2, %3, %4, 0FFh
%endmacro
%macro MSGC 1+                  ; continua al cursor
        call pmsg_c
        db %1, 0
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
        mov ax, [int_out+4]
        mov [car_h], ax

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

        mov si, bmlist                  ; bitmaps: format estandard -> dispositiu
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
        or ax, ax
        jz .nobl
        mov [vplanes], al               ; video directe: nomes 640x200, 1 o 4 plans
        cmp word [scr_xmax], 639
        jne .nobl
        cmp word [scr_ymax], 199
        jne .nobl
        cmp al, 1
        je .dv
        cmp al, 4
        jne .nobl
.dv:    mov byte [dvok], 1
.nobl:

        mov word [int_in], 0            ; graf_mouse(ARROW)
        mov word [addr_in], 0
        mov word [addr_in+2], 0
        AES 78,1,1,1,0
        call fes_menu                   ; barra de menus (accessoris)

        ; mides que depenen de la lletra
        mov ax, [car_h]
        add ax, 3
        mov [lh], ax
        mov bx, 3
        mul bx
        add ax, MSGY + 3
        mov [ty], ax
        add ax, 3 + 8
        mov [cardy0], ax
        add ax, CARD_H + 9
        mov [wh_], ax

        ; escriptori
        mov word [int_in], 0
        mov word [int_in+2], WF_WORKXYWH
        AES 104,2,5,0,0
        mov si, int_out+2
        mov di, escr
        mov cx, 4
        rep movsw

        ; la finestra ocupa tota l'area de l'escriptori
        mov si, escr
        mov di, frect
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

        call posa_wh                    ; titol
        mov word [int_in+2], WF_NAME
        mov word [int_in+4], titol
        mov [int_in+6], ds
        mov word [int_in+8], 0
        mov word [int_in+10], 0
        AES 105,6,1,0,0

        call posa_wh                    ; wind_open
        mov si, frect
        mov di, int_in+2
        mov cx, 4
        rep movsw
        AES 101,5,1,0,0
        call get_work

        call llavor
        jmp restart

; =====================================================================
;  EL JOC (mateix flux que la versio VIC-20)
; =====================================================================
restart:
        xor bx, bx                      ; baralla ordenada
.d:     mov [deck+bx], bl
        inc bx
        cmp bx, 52
        jb .d
        mov word [mu], 100

; ---------- remenat: les cartes llisquen cap a la pila ----------
shuffle:
        mov al, 1                       ; mode remenat: tapet + pila
        call cls
        mov byte [sidx], 0
        mov byte [sacc], 0
        MSG 0, C_RED, (NCOL-17)/2, "Vint-i-u Enhanced"
        MSG 2, C_PUR, (NCOL-12)/2, "Barrejant..."
        cmp byte [dvok], 0
        je shuf_lp
        call dv_captura                 ; el dors de la pila, directe de la VRAM
shuf_lp:
        call rnd                        ; deck(sidx) <-> deck(0..51 a l'atzar)
        and al, 3Fh
        cmp al, 52
        jae shuf_lp
        mov bl, al
        xor bh, bh
        mov al, [sidx]
        xor ah, ah
        mov si, ax
        mov al, [deck+si]
        xchg al, [deck+bx]
        mov [deck+si], al
        inc byte [sidx]
        add byte [sacc], NLLISC         ; NLLISC cartes repartides entre 52
        cmp byte [sacc], 52
        jae .llisca
        jmp shuf_lp
.llisca:
        sub byte [sacc], 52
.np:    call rnd                        ; de 2 a 6 passos fins a la pila
        and al, 7
        cmp al, 5
        jae .np
        add al, 2
        mov [npas], al
        call rnd                        ; costat a l'atzar, mai 3 seguits d'igual
        and al, 1
        cmp al, [costat]
        jne .canvi
        cmp byte [repes], 2
        jb .igual
        xor al, 1
.canvi: mov byte [repes], 0
.igual: inc byte [repes]
        mov [costat], al
        cmp byte [dvok], 0              ; sense video directe: no llisca
        je aterra
        jmp dv_slide
aterra: mov bl, 70                      ; "clac": soroll greu i curt
        mov cx, 70
        call soroll
        call poll                       ; (la finestra continua viva)
        cmp byte [sidx], 52
        jne shuf_lp
        mov byte [z], 0
newhand:
        cmp byte [z], 37                ; remenar quan queda un terc de baralla
        jb round
        jmp shuffle

; ---------- nova ma / nou torn ----------
round:  mov cx, 8                       ; tu nu t2 tb(2) eb gg pl
        jmp short torn0
turn:   mov cx, 3                       ; tu nu t2
torn0:  mov di, tu
        xor al, al
        rep stosb
        mov al, 2                       ; mode taula
        call cls

; ---------- repartir una carta ----------
deal:   inc byte [nu]
        mov bl, [z]
        xor bh, bh
        mov al, [deck+bx]
        inc byte [z]
        mov [cardv], al
        xor ah, ah                      ; pal = carta/13, valor = resta+1
        mov cl, 13
        div cl
        inc ah
        mov [rank], ah
        call clr_top
        mov bl, [ncards]                ; posar la carta al tapet
        xor bh, bh
        mov al, [cardv]
        mov [tcards+bx], al
        inc byte [ncards]
        call dv_deal                    ; la carta entra lliscant (si es pot)
        mov ax, FSTEP
        mul bx
        add ax, FX
        mov bx, [cardy0]
        mov cx, CARD_W
        mov dx, CARD_H
        call inval
        mov ax, D_CARD
        call delay
        mov al, [rank]                  ; sumar: figures = 10
        cmp al, 10
        jb .s
        mov al, 10
.s:     add [tu], al
        cmp byte [rank], 1
        jne .na
        inc byte [t2]
.na:    MSG 0, C_BLU, 0, "Punts "
        cmp byte [pl], 0
        jne .b
        MSGC "teus: "
        jmp short .c
.b:     MSGC "banca: "
.c:     mov al, [tu]
        call pbyte
        mov al, [tu]                    ; l'as pot valer 11?
        mov [best], al
        cmp byte [t2], 0
        je .esp
        cmp al, 12
        jae .esp
        add al, 10
        mov [best], al
        MSGC " o "
        mov al, [best]
        call pbyte
.esp:   ; ---- jugades especials
        cmp byte [best], 21
        jne .e2
        cmp byte [nu], 2
        jne .e2
        mov byte [best], 30
        MSGR 1, C_RED, 0, "Vint-i-u natural!"
.e2:    cmp byte [tu], 22
        jb .e3
        mov byte [best], 0
        cmp byte [pl], 0
        jne .bb
        MSGR 1, C_RED, 0, "T'has passat!"
.bb:    MSGR 1, C_RED, 0, "La banca s'ha passat!"
.e3:    cmp byte [nu], 5
        jne .e4
        mov byte [best], 25
        MSGR 1, C_RED, 0, "5 cartes!"
.e4:    cmp byte [tu], 21
        jne no21
        cmp byte [pl], 0
        jne .b21
        MSGR 1, C_RED, 0, "Tens 21!"
.b21:   MSGR 1, C_RED, 0, "La banca fa 21!"
no21:   cmp byte [pl], 0
        jne bank
        cmp byte [nu], 1
        jne options
        jmp bet

        ; ---- la banca demana fins a 17
bank:   cmp byte [best], 17
        jae .pl
        mov ax, D_BANK
        call delay
        jmp deal
.pl:    MSGR 2, C_GRN, 0, "La banca es planta"

        ; ---- opcions del jugador
options:
        mov byte [mrow], 1
        mov byte [curcol], C_PUR
        mov byte [cx_], 0
        mov byte [candbl], 0
        cmp byte [eb], 0                ; doblar: sense haver demanat i amb fitxes
        jne .nd
        mov ax, [mu]
        cmp ax, [be]
        jb .nd
        inc byte [candbl]
        mov al, 'D'
        mov ah, 6
        call add_hit
        MSGC INV, "Doblar "
.nd:    mov al, 'C'
        mov ah, 5
        call add_hit
        MSGC INV, "Carta "
        cmp byte [best], 16             ; plantar-se amb 16 o mes
        jb .np
        mov al, 'P'
        mov ah, 10
        call add_hit
        MSGC INV, "Plantar-se"
.np:    MSGC " ?"
.k:     call getkey
        cmp al, 'C'
        je hit
        cmp al, 'D'
        jne .p
        cmp byte [candbl], 0
        jne dbl
.p:     cmp al, 'P'
        jne .k
        cmp byte [best], 16
        jb .k
        MSGR 2, C_GRN, 0, "Et plantes."
dbl:    mov ax, [be]                    ; tb += be, mu -= be
        add [tb], ax
        sub [mu], ax
        jmp deal
hit:    inc byte [eb]
        jmp deal

; ---------- aposta ----------
bet:    call showmu
bet_ag: MSG 2, C_PUR, 0, "Aposta?      "
        mov byte [cx_], 8
        mov word [be], 0
bet_lp: mov byte [inv], 80h             ; cursor
        mov al, ' '
        call putc_nc
        call getkey
        cmp al, 13
        jne bet_k
        mov ax, [be]                    ; RETURN: 0 < aposta <= fitxes
        or ax, ax
        jz bet_ag
        cmp ax, [mu]
        jbe dbl                         ; tb = be, mu -= be
        jmp bet_ag
bet_k:  cmp al, 8                       ; retroces
        jne bet_d
        cmp word [be], 0
        je bet_lp
        mov al, ' '
        call putc_nc
        dec byte [cx_]
        mov ax, [be]
        xor dx, dx
        mov bx, 10
        div bx
        mov [be], ax
        jmp bet_lp
bet_d:  cmp al, '0'
        jb bet_lp
        cmp al, '9'
        ja bet_lp
        sub al, '0'
        mov [tmp], al
        jnz .nz                         ; sense zeros a l'esquerra
        cmp word [be], 0
        je bet_lp
.nz:    cmp word [be], 6400             ; cap desbordament
        jae bet_lp
        mov ax, [be]                    ; be = 10*be + xifra
        mov bx, 10
        mul bx
        mov bl, [tmp]
        xor bh, bh
        add ax, bx
        mov [be], ax
        mov al, [tmp]
        add al, '0'
        call putc
        jmp bet_lp

; ---------- final del torn ----------
result: mov ax, D_MSG
        call delay
        cmp byte [pl], 0
        jne final
        mov al, [best]
        mov [yy], al
        or al, al
        jz settle                       ; el jugador s'ha passat
        inc byte [pl]
        jmp turn
final:  mov al, [best]                  ; banca >= jugador: guanya la banca
        cmp al, [yy]
        jae settle
        mov al, 1                       ; gg = 1, o 2 amb natural / cinc cartes
        cmp byte [yy], 22
        jb .g
        inc al
.g:     mov [gg], al

; ---------- cobrar ----------
settle: call clr_top
        cmp byte [gg], 0
        jne won
        MSG 0, C_RED, 0, "Guanya la banca"
        jmp short shm
won:    mov ax, [tb]                    ; tornar l'aposta
        call addmu
        mov ax, [tb]                    ; premi = tb o 2*tb
        cmp byte [gg], 1
        je .p
        shl ax, 1
.p:     mov [num], ax
        call addmu
        MSG 0, C_RED, 0, "Guanyes "
        call pnumv
shm:    call showmu
        MSG 2, C_PUR, 0, "Prem una tecla"
        call getkey
        cmp word [mu], 0
        je .ruina
        jmp newhand
.ruina: mov al, 0
        call cls
        MSG 1, C_RED, (NCOL-15)/2, "T'has arruinat!"
        mov ax, D_MSG
        call delay
        mov ax, 1                       ; per defecte: Jugar
        mov si, al_ruina
        call alerta
        cmp ax, 1
        jne .surt
        jmp restart
.surt:  jmp sortir

; =====================================================================
;  RUTINES DEL JOC
; =====================================================================
addmu:  add [mu], ax                    ; mu += AX, amb topall a 65535
        jnc .r
        mov word [mu], 0FFFFh
.r:     ret

showmu: MSG 1, C_GRN, 0, "Fitxes: "
        mov byte [curcol], C_RED
        mov ax, [mu]
        jmp short pnum
pbyte:  xor ah, ah
pnum:   mov [num], ax
pnumv:  mov ax, [num]                   ; escriu num en decimal, amb "tic"
        xor cx, cx
        mov bx, 10
.d:     xor dx, dx
        div bx
        push dx
        inc cx
        or ax, ax
        jnz .d
.p:     pop ax
        add al, '0'
        call tputc
        loop .p
        ret

; ---- missatges inline: pmsg = fila, color, columna, text; pmsg_c = text
pmsg:   pop si
        lodsb
        mov [mrow], al
        lodsb
        mov [curcol], al
        lodsb
        mov [cx_], al
        jmp short pm_lp
pmsg_c: pop si
pm_lp:  lodsb
        or al, al
        jz .fi
        cmp al, 0FFh
        jne .n
        jmp result
.n:     cmp al, INV
        jne .c
        mov byte [inv], 80h
        jmp pm_lp
.c:     call tputc
        jmp pm_lp
.fi:    jmp si

; ---- caracter al cursor (buffer de missatges + redibuixat de la casella)
tputc:  call putc                       ; lletra a lletra, amb "tic"
        call tic
        push ax
        mov ax, D_TYPE
        call delay
        pop ax
        ret
putc:   call putc_nc
        inc byte [cx_]
        ret
putc_nc:
        push ax
        push bx
        push cx
        push dx
        mov bl, [cx_]
        cmp bl, NCOL
        jae .fi
        push ax
        mov al, [mrow]
        mov ah, NCOL
        mul ah
        add al, bl
        xor ah, ah
        mov bx, ax
        pop ax
        mov [mtxt+bx], al
        mov al, [curcol]
        or al, [inv]
        mov [mattr+bx], al
        mov al, [cx_]                   ; casella: x = MSGX + cx*8, y = MSGY + fila*lh
        xor ah, ah
        mov cl, 3
        shl ax, cl
        add ax, MSGX
        push ax
        mov al, [mrow]
        xor ah, ah
        mul word [lh]
        add ax, MSGY
        mov bx, ax
        pop ax
        mov cx, CHW
        mov dx, [lh]
        call inval
.fi:    mov byte [inv], 0
        pop dx
        pop cx
        pop bx
        pop ax
        ret

; ---- zona clicable de la fila 1: AL = tecla, AH = llargada (a partir del cursor)
add_hit:
        push bx
        mov bl, [nhits]
        xor bh, bh
        mov [hkey+bx], al
        mov al, [cx_]
        mov [hcol0+bx], al
        add al, ah
        mov [hcol1+bx], al
        inc byte [nhits]
        pop bx
        ret

; ---- esborrar: cls(AL = mode 0 blanc, 1 remenat, 2 taula), clr_top
cls:    mov [mode], al
        mov byte [ncards], 0
        call buida_msg
        mov ax, [marg_x]                    ; tota l'area de treball
        neg ax
        mov bx, [marg_y]
        neg bx
        mov cx, [workw]
        mov dx, [workh]
        jmp inval
clr_top:
        call buida_msg
        mov ax, [marg_x]
        neg ax
        mov bx, [marg_y]
        neg bx
        mov cx, [workw]
        mov dx, [ty]
        add dx, [marg_y]
        jmp inval
buida_msg:
        mov di, mtxt
        mov cx, 3*NCOL
        mov al, ' '
        rep stosb
        mov di, mattr
        mov cx, 3*NCOL
        xor al, al
        rep stosb
        mov byte [nhits], 0
        ret

; ---- atzar: xorshift de 16 bits, identic al del VIC
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

; =====================================================================
;  ESDEVENIMENTS: espera, teclat i ratoli, sense bloquejar el GEM
; =====================================================================
; delay: AX = unitats de 1/30 s
delay:  push ax
        push bx
        push cx
        push dx
        push si
        push di
        mov dx, 33
        mul dx
        mov [dly_ms], ax
.lp:    call ticks
        mov [dly_t0], ax
        mov ax, [dly_ms]
        mov [tmr], ax
        mov ax, MU_MESAG | MU_TIMER
        call evnt
        mov [quins], ax
        test ax, MU_MESAG
        jz .t
        call handle_msg
.t:     test word [quins], MU_TIMER
        jnz .fi
        call ticks                      ; un missatge ha tallat l'espera
        sub ax, [dly_t0]
        mov dx, 55
        mul dx
        cmp ax, [dly_ms]
        jae .fi
        sub [dly_ms], ax
        jmp .lp
.fi:    pop di
        pop si
        pop dx
        pop cx
        pop bx
        pop ax
        ret

; getkey: torna AL = tecla en majuscules (13 RETURN, 8 retroces),
;         la lletra d'una opcio clicada, o 0FFh per un clic qualsevol
getkey: push bx
        push cx
        push dx
        push si
        push di
.lp:    call rnd
        mov word [tmr], 0
        mov ax, MU_MESAG | MU_KEYBD | MU_BUTTON
        call evnt
        mov [quins], ax
        test ax, MU_MESAG
        jz .k
        call handle_msg
.k:     test word [quins], MU_KEYBD
        jz .b
        call ticks
        xor [rng], al
        mov al, [int_out+10]            ; codi ASCII
        cmp al, 'a'
        jb .fi
        cmp al, 'z'
        ja .fi
        sub al, 20h
        jmp short .fi
.b:     test word [quins], MU_BUTTON
        jz .lp
        mov ax, [int_out+2]             ; x, y del ratoli
        mov [mx], ax
        mov ax, [int_out+4]
        mov [my], ax
        mov word [int_in], 1            ; evnt_button: esperar que es deixi anar
        mov word [int_in+2], 1
        mov word [int_in+4], 0
        AES 21,3,5,0,0
        call ticks
        xor [rng], al
        call clic_opcio
.fi:    pop di
        pop si
        pop dx
        pop cx
        pop bx
        ret

clic_opcio:                             ; AL = tecla de l'opcio clicada o 0FFh
        mov ax, [my]
        sub ax, [oy]
        sub ax, MSGY
        jb .no
        xor dx, dx
        div word [lh]
        cmp ax, 1                       ; les opcions son a la fila 1
        jne .no
        mov ax, [mx]
        sub ax, [ox]
        sub ax, MSGX
        jb .no
        mov cl, 3
        shr ax, cl
        mov cl, al                      ; columna
        xor bx, bx
.h:     cmp bl, [nhits]
        jae .no
        cmp cl, [hcol0+bx]
        jb .s
        cmp cl, [hcol1+bx]
        jae .s
        mov al, [hkey+bx]
        ret
.s:     inc bx
        jmp .h
.no:    mov al, 0FFh
        ret

; poll: atendre missatges pendents sense esperar
poll:   push ax
        push bx
        push cx
        push dx
        push si
        push di
        mov word [tmr], 0
        mov ax, MU_MESAG | MU_TIMER
        call evnt
        test ax, MU_MESAG
        jz .r
        call handle_msg
.r:     pop di
        pop si
        pop dx
        pop cx
        pop bx
        pop ax
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

handle_msg:
        cmp word [msgbuf], 10           ; MN_SELECTED (menu)
        jne .w
        jmp menu_msg
.w:     mov ax, [msgbuf+6]
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
        jne .m
        call posa_wh
        mov word [int_in+2], WF_TOP
        jmp short .ws
.m:     cmp ax, WM_MOVED
        jne .c
        call posa_wh
        mov word [int_in+2], WF_CURRXYWH
        mov si, msgbuf+8
        mov di, int_in+4
        mov cx, 4
        rep movsw
        AES 105,6,1,0,0
        jmp get_work
.c:     cmp ax, WM_CLOSED
        jne .r
        mov ax, 2                       ; per defecte: Continuar
        mov si, al_tanca
        call alerta
        cmp ax, 1
        jne .r
        jmp sortir
.ws:    mov word [int_in+4], 0
        mov word [int_in+6], 0
        mov word [int_in+8], 0
        mov word [int_in+10], 0
        AES 105,6,1,0,0
.r:     ret

get_work:                               ; area de treball i origen del contingut
        call posa_wh                    ; (centrat dins l'area de treball)
        mov word [int_in+2], WF_WORKXYWH
        AES 104,2,5,0,0
        mov ax, [int_out+6]
        mov [workw], ax
        sub ax, W
        sar ax, 1
        jns .x
        xor ax, ax
.x:     mov [marg_x], ax
        add ax, [int_out+2]
        mov [ox], ax
        mov ax, [int_out+8]
        mov [workh], ax
        sub ax, [wh_]
        sar ax, 1
        jns .y
        xor ax, ax
.y:     mov [marg_y], ax
        add ax, [int_out+4]
        mov [oy], ax
        ret

; ---- sortida (boto de tancar)
sortir: call so_off
        call treu_menu
        call posa_wh
        AES 102,1,1,0,0                 ; wind_close
        call posa_wh
        AES 103,1,1,0,0                 ; wind_delete
vdi_fi: VDI 101,0,0                     ; v_clsvwk
aes_fi: AES 19,0,1,0,0                  ; appl_exit
dos_fi: mov ax, 4C00h
        int 21h


; =====================================================================
;  BARRA DE MENUS: nomes el menu del programa, amb "Quant a" i els
;  accessoris del GEM (el GEM hi posa els noms dels .ACC; sense barra
;  de menus no s'hi pot arribar)
; =====================================================================
fes_menu:
        mov si, menutree
        xor bx, bx
.l:     mov al, [si+6]                  ; ob_type
        cmp al, 28                      ; G_STRING
        je .seg
        cmp al, 32                      ; G_TITLE
        jne .fix
.seg:   mov [si+14], ds                 ; ob_spec: segment del text
.fix:   mov [int_in], bx
        mov word [addr_in], menutree
        mov [addr_in+2], ds
        push si
        push bx
        AES 114,1,1,1,0                 ; rsrc_obfix
        pop bx
        pop si
        test byte [si+8], 20h           ; LASTOB
        jnz .fi
        add si, 24
        inc bx
        jmp .l
.fi:    mov word [int_in], 1
        mov word [addr_in], menutree
        mov [addr_in+2], ds
        AES 30,1,1,1,0                  ; menu_bar(arbre, 1)
        ret

treu_menu:
        mov word [int_in], 0
        mov word [addr_in], menutree
        mov [addr_in+2], ds
        AES 30,1,1,1,0                  ; menu_bar(arbre, 0)
        ret

; msgbuf = MN_SELECTED: el titol torna a normal i, si es "Quant a", ho diu
menu_msg:
        mov ax, [msgbuf+6]
        mov [int_in], ax
        mov word [int_in+2], 1
        mov word [addr_in], menutree
        mov [addr_in+2], ds
        AES 33,2,1,1,0                  ; menu_tnormal
        cmp word [msgbuf+8], 6
        jne .r
        mov ax, 1
        mov si, al_quant
        call alerta
.r:     ret

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

; =====================================================================
;  VIDEO DIRECTE (PC1512, 640x200): B800h, linies entrellacades com la
;  CGA (parelles a 0000h, senars a 2000h, 80 bytes per linia) i 4 plans
;  a les mateixes adreces: port 3DDh tria els plans d'escriptura i
;  3DEh el pla de lectura. La carta es mou de 3 en 3 bytes (24 pixels).
; =====================================================================
VSEG    equ 0B800h
P_WPLA  equ 3DDh
P_RPLA  equ 3DEh

voff:                                   ; AX = y absoluta -> DI = inici de linia
        push ax
        push dx
        xor di, di
        shr ax, 1
        jnc .par
        mov di, 2000h
.par:   mov dx, 80
        mul dx
        add di, ax
        pop dx
        pop ax
        ret

; captura: el dors de la pila i una columna de tapet, pla a pla
dv_captura:
        call lock_ini
        push es
        mov ax, VSEG
        mov es, ax
        mov cl, 3
        mov ax, [ox]
        add ax, PX
        shr ax, cl
        mov [vbx0], ax                  ; primer byte de la carta
        mov ax, [ox]
        add ax, PX + CARD_W - 1
        shr ax, cl
        sub ax, [vbx0]
        inc ax
        mov [vnb], ax                   ; bytes per linia (18 o 19)
        mov ax, [ox]
        add ax, 16
        shr ax, cl
        mov [vfelt], ax                 ; un byte de tapet, a l'esquerra
        mov ax, [oy]
        add ax, [cardy0]
        mov [vy0], ax
        mov si, cardbuf
        mov bx, feltbuf
        mov byte [vpl], 0
.pl:    cmp byte [vplanes], 1
        je .np
        mov al, [vpl]
        mov dx, P_RPLA
        out dx, al
.np:    xor bp, bp                      ; BP = linia
.ln:    mov ax, [vy0]
        add ax, bp
        call voff
        mov dx, di                      ; DX = inici de la linia
        add di, [vbx0]
        mov cx, [vnb]
.b:     mov al, [es:di]
        mov [si], al
        inc di
        inc si
        loop .b
        mov di, dx
        add di, [vfelt]
        mov al, [es:di]
        mov [bx], al
        inc bx
        inc bp
        cmp bp, CARD_H
        jb .ln
        inc byte [vpl]
        mov al, [vpl]
        cmp al, [vplanes]
        jb .pl
        call dv_reset
        mov byte [dvcap], 1             ; ja tenim el dors capturat
        pop es
        jmp lock_fi

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

; ---- dv_deal: BX = posicio al ventall. La carta entra per la dreta
dv_deal:
        cmp byte [dvok], 0
        je .no
        cmp byte [dvcap], 0
        je .no
        call som_dalt
        je .si
.no:    ret
.si:    push ax
        push bx
        push cx
        push dx
        mov ax, bx                      ; desti = (FX + i*FSTEP - PX) / 8
        mov cl, FSTEP/8
        mul cl
        sub ax, (PX - FX)/8
        mov [vtgt], ax
        mov cl, 3                       ; la finestra pot haver-se mogut
        mov ax, [ox]
        add ax, PX
        shr ax, cl
        mov [vbx0], ax
        mov ax, [oy]
        add ax, [cardy0]
        mov [vy0], ax
        call lock_ini
        mov ax, DINI
        mov [vpos], ax
        call dv_posa
.pas:   mov bl, 8                       ; "fft" curt
        mov cx, 60
        call soroll
        mov ax, [vpos]
        cmp ax, [vtgt]
        je .fi
        mov dx, ax                      ; DX = antiga
        sub ax, DPAS
        cmp ax, [vtgt]
        jge .ok
        mov ax, [vtgt]
.ok:    mov [vpos], ax
        call dv_posa
        mov cx, dx                      ; franja a la dreta: antiga - nova bytes
        sub cx, ax
        add ax, [vnb]
        call dv_franja
        jmp .pas
.fi:    call dv_reset
        call lock_fi
        pop dx
        pop cx
        pop bx
        pop ax
        ret

dv_reset:                               ; plans com els vol el GEM
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

; dv_posa: AX = desplacament en bytes respecte de la pila
dv_posa:
        push ax
        push bx
        push cx
        push dx
        push si
        push di
        push bp
        push es
        mov [vk], ax
        mov ax, VSEG
        mov es, ax
        mov si, cardbuf
        mov byte [vpl], 0
.pl:    call dv_wpla
        xor bp, bp
.ln:    mov ax, [vy0]
        add ax, bp
        call voff
        add di, [vbx0]
        add di, [vk]
        mov cx, [vnb]
        rep movsb
        inc bp
        cmp bp, CARD_H
        jb .ln
        inc byte [vpl]
        mov al, [vpl]
        cmp al, [vplanes]
        jb .pl
        pop es
        pop bp
        pop di
        pop si
        pop dx
        pop cx
        pop bx
        pop ax
        ret

; dv_franja: AX = primer byte (relatiu a la pila), CX = bytes. Hi posa tapet
dv_franja:
        push ax
        push bx
        push cx
        push dx
        push si
        push di
        push bp
        push es
        mov [vk], ax
        mov [vw], cx
        mov ax, VSEG
        mov es, ax
        mov si, feltbuf
        mov byte [vpl], 0
.pl:    call dv_wpla
        xor bp, bp
.ln:    mov ax, [vy0]
        add ax, bp
        call voff
        add di, [vbx0]
        add di, [vk]
        mov cx, [vw]
        lodsb
        rep stosb
        inc bp
        cmp bp, CARD_H
        jb .ln
        inc byte [vpl]
        mov al, [vpl]
        cmp al, [vplanes]
        jb .pl
        pop es
        pop bp
        pop di
        pop si
        pop dx
        pop cx
        pop bx
        pop ax
        ret

dv_wpla:                                ; escriure nomes al pla [vpl]
        cmp byte [vplanes], 1
        je .r
        push ax
        push cx
        push dx
        mov cl, [vpl]
        mov al, 1
        shl al, cl
        mov dx, P_WPLA
        out dx, al
        pop dx
        pop cx
        pop ax
.r:     ret

; dv_slide: la carta llisca fins a la pila escrivint directament a la VRAM
dv_slide:
        mov al, [npas]                  ; 3 bytes per pas
        mov ah, 3
        mul ah
        cmp byte [costat], 0
        jne .d
        neg ax
.d:     mov [vpos], ax
        call lock_ini
        mov ax, [vpos]
        call dv_posa
.pas:   mov ax, [vpos]                  ; "frrr"
        add al, 20
        mov bl, al
        mov cx, 120
        call soroll
        mov ax, [vpos]
        or ax, ax
        jz .fi
        js .dr
        sub ax, 3                       ; ve de la dreta
        mov [vpos], ax
        call dv_posa
        add ax, [vnb]                   ; franja que queda a la dreta
        mov cx, 3
        call dv_franja
        jmp .pas
.dr:    mov dx, ax                      ; ve de l'esquerra
        add ax, 3
        mov [vpos], ax
        call dv_posa
        mov ax, dx                      ; franja que queda a l'esquerra
        mov cx, 3
        call dv_franja
        jmp .pas
.fi:    call dv_reset
        call lock_fi
        jmp aterra

; ---- bloquejar la pantalla per a les animacions
lock_ini:
        mov word [int_in], 1
        AES 107,1,1,0,0                 ; wind_update(BEG_UPDATE)
        mov word [int_in], 256
        AES 78,1,1,1,0                  ; graf_mouse(M_OFF)
        mov word [intin], 1             ; vs_clip: area de treball
        mov ax, [ox]
        mov [ptsin], ax
        add ax, W - 1
        mov [ptsin+4], ax
        mov ax, [oy]
        mov [ptsin+2], ax
        add ax, [wh_]
        dec ax
        mov [ptsin+6], ax
        VDI 129,2,1
        ret
lock_fi:
        mov word [int_in], 257
        AES 78,1,1,1,0                  ; graf_mouse(M_ON)
        mov word [int_in], 0
        AES 107,1,1,0,0                 ; wind_update(END_UPDATE)
        ret

; =====================================================================
;  SO (altaveu del PC)
; =====================================================================
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
tic:    push ax
        push cx
        mov ax, 500
        call so_on
        mov cx, 600
.w:     loop .w
        call so_off
        pop cx
        pop ax
        ret

; =====================================================================
;  DIBUIX
; =====================================================================
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
; redraw: redibuixa el rectangle absolut rr dins la finestra
redraw: push ax
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

; ---- tota l'escena, retallada a clip
scene:  mov ax, [marg_x]                     ; zona de missatges (tota l'amplada)
        neg ax
        mov bx, [marg_y]
        neg bx
        mov cx, [workw]
        mov dx, [ty]
        add dx, [marg_y]
        call vis_rect
        jc .taula
        mov byte [fcol], BLANC
        call fill_rect
        call render_msgs
.taula: mov ax, [marg_x]                     ; tapet (fins a les vores)
        neg ax
        mov bx, [ty]
        mov cx, [workw]
        mov dx, [workh]
        sub dx, [marg_y]
        sub dx, bx
        call vis_rect
        jc .fi
        cmp byte [mode], 0
        jne .tap
        mov byte [fcol], BLANC
        call fill_rect
        ret
.tap:   mov byte [fcol], TAPET
        call fill_rect
        mov dx, 3                       ; franja blava
        mov byte [fcol], C_BLU
        call fill_rect
        mov ax, [cardy0]
        mov [cardy], ax
        cmp byte [mode], 1
        jne .cartes
        mov word [cardx], PX            ; pila
        mov al, 0FFh
        call draw_card
.fi:    ret
.cartes:
        mov byte [ci], 0
.c:     mov bl, [ci]
        cmp bl, [ncards]
        jae .fi
        xor bh, bh
        mov ax, FSTEP
        mul bx
        add ax, FX
        mov [cardx], ax
        mov al, [tcards+bx]
        call draw_card
        inc byte [ci]
        jmp .c

; ---- les 3 files de missatges
render_msgs:
        mov byte [rrow], 0
.r:     mov al, [rrow]
        xor ah, ah
        mul word [lh]
        add ax, MSGY
        mov [rowy], ax
        mov bx, ax
        mov ax, MSGX
        mov cx, NCOL*CHW
        mov dx, [lh]
        call vis_rect
        jc .nx
        mov byte [rcol], 0
.c:     mov al, [rcol]
        cmp al, NCOL
        jae .nx
        call msg_idx
        mov al, [mattr+bx]
        mov ah, [mtxt+bx]
        test al, 80h
        jnz .run
        cmp ah, ' '
        jne .run
        inc byte [rcol]
        jmp .c
.run:   mov [rattr], al                 ; tros del mateix color
        mov al, [rcol]
        mov [rstart], al
        mov di, runbuf
.rl:    mov al, [rcol]
        cmp al, NCOL
        jae .dib
        call msg_idx
        mov al, [mattr+bx]
        cmp al, [rattr]
        jne .dib
        mov ah, [mtxt+bx]
        test al, 80h
        jnz .ok
        cmp ah, ' '
        je .dib
.ok:    mov [di], ah
        inc di
        inc byte [rcol]
        jmp .rl
.dib:   mov cx, di
        sub cx, runbuf
        mov al, [rstart]
        xor ah, ah
        push cx
        mov cl, 3
        shl ax, cl
        pop cx
        add ax, MSGX
        mov bx, [rowy]
        inc bx
        mov dl, [rattr]
        test dl, 80h
        jz .nor
        and dl, 7Fh                     ; invers: fons de color, lletra blanca
        mov [fcol], dl
        push cx
        push dx
        push ax
        shl cx, 1
        shl cx, 1
        shl cx, 1
        mov dx, [lh]
        sub dx, 2
        call fill_rect
        pop ax
        pop dx
        pop cx
        mov dl, BLANC
.nor:   mov [tcolor], dl
        mov si, runbuf
        call text_at
        jmp .c
.nx:    inc byte [rrow]
        cmp byte [rrow], 3
        jb .r
        ret

msg_idx:                                ; BX = rrow*NCOL + AL
        push ax
        mov bl, al
        mov al, [rrow]
        mov ah, NCOL
        mul ah
        add al, bl
        xor ah, ah
        mov bx, ax
        pop ax
        ret

; ---- una carta: AL = 0..51 o 0FFh (dors), a (cardx, cardy)
draw_card:
        mov [cardv], al
        mov ax, [cardx]
        mov bx, [cardy]
        mov cx, CARD_W
        mov dx, CARD_H
        call vis_rect
        jnc .vis
        ret
.vis:   mov byte [fcol], NEGRE          ; vora negra i cara blanca
        call rfbox
        inc ax
        inc bx
        sub cx, 2
        sub dx, 2
        mov byte [fcol], BLANC
        call rfbox
        cmp byte [cardv], 0FFh
        jne .cara
        mov ax, [cardx]                 ; dors: trama blava
        add ax, BKX
        mov bx, [cardy]
        add bx, BKY
        mov cx, CARD_W - 2*BKX
        mov dx, CARD_H - 2*BKY
        call rect_abs
        mov word [intin], 2             ; vsf_interior(trama)
        VDI 23,0,1
        mov word [intin], 4             ; vsf_style
        VDI 24,0,1
        mov word [intin], C_BLU
        VDI 25,0,1
        VDI 114,2,0
        ret
.cara:  mov al, [cardv]
        xor ah, ah
        mov cl, 13
        div cl
        mov [csuit], al
        inc ah
        mov [crank], ah
        mov bl, NEGRE                   ; cors i diamants en vermell
        test al, 1
        jz .k
        mov bl, C_RED
.k:     mov [fcol], bl
        mov [tcolor], bl
        call rank_str                   ; index de dalt
        mov ax, [cardx]
        add ax, IX
        mov bx, [cardy]
        add bx, IY
        call text_at
        call rank_str                   ; index de baix
        mov ax, cx
        shl ax, 1
        shl ax, 1
        shl ax, 1
        neg ax
        add ax, [cardx]
        add ax, CARD_W - IX
        mov bx, [cardy]
        add bx, CARD_H - IY - 9
        call text_at
        call fill_attrs
        mov ax, [cardx]                 ; pal sota l'index
        add ax, SPX
        mov bx, [cardy]
        add bx, SPY
        mov cl, 0                       ; mida petita
        call pip
        mov al, [crank]
        cmp al, 1
        je .as
        cmp al, 11
        jae .figura
        sub al, 2                       ; pips: disposicio estandard
        xor ah, ah
        mov si, ax
        mov al, [pipidx+si]
        mov si, ax
        add si, pips                    ; SI -> nombre de pips i posicions
        lodsb
        mov [prow], al
.pip:   lodsb                           ; columna*16 + mitja fila (0..12)
        mov dl, al
        and al, 0Fh
        mov ah, GDY                     ; y = GY0 + mitja_fila * GDY / 2
        mul ah
        shr ax, 1
        add ax, [cardy]
        add ax, GY0
        mov bx, ax
        mov al, dl                      ; x = centre + (columna-1) * GDX
        mov cl, 4
        shr al, cl
        mov ah, GDX
        mul ah
        add ax, [cardx]
        add ax, CARD_W/2 - GDX
        mov cl, 1                       ; mida mitjana
        call pip
        dec byte [prow]
        jnz .pip
        ret
.as:    mov ax, [cardx]                 ; as: un pal gran dins l'ornament
        add ax, CARD_W/2
        mov bx, [cardy]
        add bx, AS_Y
        mov cl, 2                       ; mida gran
        call pip
        mov al, 12                      ; ornament de l'as
        jmp short .dib
.figura:                                ; J Q K: marc i retrat
        mov al, [fcol]
        xor ah, ah
        mov [intin], ax
        VDI 17,0,1                      ; vsl_color
        mov ax, [cardx]                 ; (x1,y1) (x2,y1) (x2,y2) (x1,y2) (x1,y1)
        add ax, [ox]
        add ax, FRX
        mov bx, [cardy]
        add bx, [oy]
        add bx, FRY
        mov [ptsin], ax
        mov [ptsin+2], bx
        mov [ptsin+12], ax
        mov [ptsin+16], ax
        mov [ptsin+6], bx
        mov [ptsin+18], bx
        add ax, FRW
        add bx, FRH
        mov [ptsin+4], ax
        mov [ptsin+8], ax
        mov [ptsin+10], bx
        mov [ptsin+14], bx
        VDI 6,5,0                       ; v_pline
        mov al, [crank]                 ; figura = (valor-11)*4 + pal
        sub al, 11
        shl al, 1
        shl al, 1
        add al, [csuit]
.dib:   call desc_fig                   ; 4 capes: vermell, blau, or, negre
        mov ax, [cardx]
        add ax, CARD_W/2
        mov bx, [cardy]
        add bx, AS_Y
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
        ret

; ---- desc_fig: AL = figura (0..11 J Q K de cada pal, 12 ornament de l'as).
;      Descomprimeix la imatge de 5 colors (vegeu VINTIU.INC), en fa 4 capes
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

rank_str:                               ; SI = text del valor, CX = llargada
        mov al, [crank]
        cmp al, 10
        jne .u
        mov si, deu
        mov cx, 2
        ret
.u:     xor ah, ah
        mov si, ax
        add si, rankch - 1
        mov cx, 1
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

; =====================================================================
;  CRIDES GEM
; =====================================================================
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
titol:  db ' Vint-i-u Enhanced ', 0
; ---- arbre de la barra de menus (coordenades en caracters; rsrc_obfix)
;      next, head, tail, tipus, flags, estat, ob_spec (2 paraules), x, y, w, h
        align 2
menutree:
        dw -1, 1, 4, 25, 0, 0, 0, 0, 0, 0, 80, 25                ; 0
        dw 4, 2, 2, 20, 0, 0, 1100h, 0, 0, 0, 80, 0201h          ; 1
        dw 1, 3, 3, 25, 0, 0, 0, 0, 2, 0, 10, 0301h             ; 2
        dw 2, -1, -1, 32, 0, 0, t_mtit, 0, 0, 0, 10, 0301h      ; 3
        dw 0, 5, 5, 25, 0, 0, 0, 0, 0, 0301h, 80, 19             ; 4
        dw 4, 6, 13, 20, 0, 0, 1100h, 0FFh, 2, 0, 22, 8          ; 5
        dw 7, -1, -1, 28, 0, 0, mt_quant, 0, 0, 0, 22, 1         ; 6
        dw 8, -1, -1, 28, 0, 8, m_sep22, 0, 0, 1, 22, 1          ; 7
        dw 9, -1, -1, 28, 0, 0, m_acc1, 0, 0, 2, 22, 1           ; 8
        dw 10, -1, -1, 28, 0, 0, m_acc2, 0, 0, 3, 22, 1          ; 9
        dw 11, -1, -1, 28, 0, 0, m_acc3, 0, 0, 4, 22, 1          ; 10
        dw 12, -1, -1, 28, 0, 0, m_acc4, 0, 0, 5, 22, 1          ; 11
        dw 13, -1, -1, 28, 0, 0, m_acc5, 0, 0, 6, 22, 1          ; 12
        dw 5, -1, -1, 28, 20h, 0, m_acc6, 0, 0, 7, 22, 1         ; 13
t_mtit: db ' Vint-i-u ', 0
mt_quant: db '  Quant a Vint-i-u... ', 0
m_sep22: db '----------------------', 0
m_acc1: db '  Desk Accessory      ', 0
m_acc2: db '  Desk Accessory      ', 0
m_acc3: db '  Desk Accessory      ', 0
m_acc4: db '  Desk Accessory      ', 0
m_acc5: db '  Desk Accessory      ', 0
m_acc6: db '  Desk Accessory      ', 0
al_quant: db "[1][VINT-I-U ENHANCED 0.2| |Per al GEM 2.0 (Amstrad PC1512).|Port del joc del VIC-20.][D'acord]", 0

rankch: db 'A234567890JQK'
deu:    db '10'

; pips de les cartes 2..10, disposicio de les cartes reals: nombre de pips i,
; per a cadascun, columna*16 + mitja fila (columnes 0 esquerra, 1 centre, 2 dreta;
; mitges files 0 dalt .. 12 baix)
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



        align 2
%include "VINTIU.INC"
al_ruina: db "[2][T'has arruinat!| |Vols tornar a jugar?][Jugar|Sortir]", 0
al_tanca: db "[2][Vols sortir del joc?][Sortir|Continuar]", 0
costat:   db 0FFh               ; 0 esquerra, 1 dreta
colcapa:  db C_RED, C_BLU, GROC, NEGRE   ; colors de les capes de les figures
        align 2
nz:       dw 0ACE1h             ; llavor del soroll
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
cardbuf:  resb 20*CARD_H*4      ; dors de la carta: fins a 4 plans, 20 bytes/linia
feltbuf:  resb 4*CARD_H         ; un byte de tapet per linia i pla

vhandle:  resw 1
whandle:  resw 1
car_h:    resw 1
lh:       resw 1
ty:       resw 1
cardy0:   resw 1
wh_:      resw 1
ox:       resw 1                ; origen del contingut (absolut)
oy:       resw 1
workw:    resw 1                ; area de treball de la finestra
workh:    resw 1
marg_x:   resw 1                ; marges fins al contingut centrat
marg_y:   resw 1
escr:     resw 4
frect:    resw 4
rr:       resw 4
clip:     resw 4
tmr:      resw 1
quins:    resw 1
dly_ms:   resw 1
dly_t0:   resw 1
mx:       resw 1                ; ratoli
my:       resw 1
cardx:    resw 1
cardy:    resw 1
rowy:     resw 1
rng:      resw 1
mu:       resw 1                ; fitxes
be:       resw 1                ; aposta inicial
num:      resw 1
scr_xmax: resw 1
scr_ymax: resw 1
vbx0:     resw 1                ; columna (en bytes) de la pila
vnb:      resw 1                ; bytes per linia de la carta
vfelt:    resw 1
vy0:      resw 1
vk:       resw 1
vw:       resw 1
vpos:     resw 1                ; posicio de la carta que llisca (bytes)
vtgt:     resw 1                ; desti de la carta repartida (bytes)
; a zero cada ma (round) / cada torn (turn, els 3 primers): l'ordre importa
tu:       resb 1                ; total amb l'as = 1
nu:       resb 1                ; cartes del torn
t2:       resb 1                ; hi ha as
tb:       resw 1                ; aposta total
eb:       resb 1                ; ja ha demanat carta
gg:       resb 1                ; premi: 0, 1 o 2
pl:       resb 1                ; 0 jugador, 1 banca
best:     resb 1
yy:       resb 1
rank:     resb 1
candbl:   resb 1
z:        resb 1
sidx:     resb 1
tmp:      resb 1
mode:     resb 1
ncards:   resb 1
ci:       resb 1
cardv:    resb 1
csuit:    resb 1
crank:    resb 1
prow:     resb 1
fcol:     resb 1
tcolor:   resb 1
mrow:     resb 1
cx_:      resb 1
curcol:   resb 1
inv:      resb 1
rrow:     resb 1
rcol:     resb 1
rattr:    resb 1
rstart:   resb 1
nhits:    resb 1
dvok:     resb 1                ; video directe disponible
dvcap:    resb 1                ; dors capturat
sacc:     resb 1                ; acumulador del remenat
vplanes:  resb 1
vpl:      resb 1
npas:     resb 1                ; passos de la carta que llisca
repes:    resb 1                ; vegades seguides pel mateix costat
hkey:     resb 3
hcol0:    resb 3
hcol1:    resb 3
tcards:   resb 5
deck:     resb 52
mtxt:     resb 3*NCOL
mattr:    resb 3*NCOL
runbuf:   resb NCOL
fi_bss:
