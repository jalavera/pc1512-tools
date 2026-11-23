; =====================================================================
;  KEYBX.ASM  -  Remapejador de teclat resident per a MS-DOS 2.x - 6.xx
;               (8086, pensat per a l'Amstrad PC1512 i emuladors)
;               Versio 2.2: taula i ratoli en blocs a part; tot es pot
;               carregar, treure i moure amb KEYBX ja resident
;               Versio 2.3: amb LOADHI, la taula i el ratoli tambe van a dalt
;               Versio 2.4: a baix, el nom al bloc de memoria (MEM)
;
;  Muntatge:   nasm -f bin KEYBX.ASM -o KEYBX.COM
;
;  Us:  KEYBX [fitxer.cfg] [/P:xx] [/M[:n]] [/H:seg [/F]]  instal.la o recarrega
;       KEYBX /M[:n] | /M-                 carrega / treu el ratoli
;       KEYBX /P[:xx] | /P-                carrega / treu la taula emergent
;       KEYBX /H:seg                       mou el resident a memoria alta
;       KEYBX /A [fitxer.cfg]              mode aprenentatge (genera .CFG)
;       KEYBX /T                           mode prova tecla per tecla
;       KEYBX /ON | /OFF                   activa / desactiva el resident
;       KEYBX /U                           desinstal.la
;       KEYBX /?                           ajuda
;
;  Funcionament: intercepta la INT 09h, llegeix el codi de tecla del port
;  60h abans que la BIOS, deixa que la BIOS (o el gestor anterior) faci la
;  seva feina i despres substitueix o afegeix al buffer de teclat el
;  caracter definit a la taula. No toca el maquinari (EOI, port 61h): ho
;  fa la BIOS, aixi es compatible amb BIOS XT/AT i amb la del PC1512.
;
;  Taula emergent (modul a part, com el ratoli): Ctrl+Alt+T (o la tecla
;  de /P:xx) l'activa. S'obre la
;  propera vegada que el programa demana una tecla per la INT 16h (mai
;  dins la interrupcio de teclat) i nomes en modes de text de 80 columnes.
;  La cadena validada es lliura per la INT 16h.
;
;  Ratoli (/M): modul amb segment propi que es copia a un bloc de memoria
;  a part, del mateix tipus que el de KEYBX: convencional (al capdamunt),
;  alta enllacada a la cadena del DOS (LOADHI) o alta sense bloc (/H).
;  Es pot carregar amb KEYBX ja resident i treure amb /M-. Captura la
;  INT 08h (comptadors dels ports 78h/7Ah, amb corba d'acceleracio /M:0-3)
;  i la INT 33h (API Microsoft). Els botons arriben pel teclat (7Eh/7Dh,
;  FEh/FDh): la INT 09h de KEYBX els passa al modul abans de res mes.
; =====================================================================

        cpu     8086
        org     100h

start:  jmp     init

; =====================================================================
;                        PART RESIDENT
; =====================================================================
sig         db  'KEYBX4'        ; signatura (no moure: offset 103h)
enabled     db  1
busy        db  0
prev_e0     db  0
pending     db  0               ; tecla morta pendent 0..4
newword     dw  0
oldtail     dw  0
old9        dd  0
hiseg       dw  0               ; <>0 si carregat a memoria alta (/H)
mousefar    dd  0               ; mbtn del modul de ratoli (seg 0 = sense)
ressz       dw  0               ; bytes residents des de 100h
mtype       db  0               ; ratoli: 0 bloc del DOS, 1 sense bloc (/H)
popkey      db  14h             ; Ctrl+Alt+T
haspop      db  0               ; 1 = modul de la taula carregat
popflag     db  0
popseg      dw  0               ; segment del modul de la taula
ptype       db  0               ; taula: 0 bloc del DOS, 1 sense bloc (/H)
captab      times 16 db 0       ; bit per codi: afectat per Bloq Maj
maptab      times 128*5 dw 0    ; [codi][classe] -> paraula buffer
                                ; classe: 0 cap,1 Maj,2 Ctrl,3 Alt,4 Maj+Alt
                                ; FF00h = empassar, FF01h..FF04h = morta

; Composicio de tecles mortes: base, resultat. 4 taules de 32 bytes.
; Per defecte CP437; amb /850 el carregador hi copia les de CP850.
cp850   db  0                       ; 0 = CP437, 1 = CP850, 2 = joc del GEM
comp1   db 'a',0A0h,'e',82h,'i',0A1h,'o',0A2h,'u',0A3h,'E',90h,' ',27h,0
        times 32-($-comp1) db 0
comp2   db 'a',85h,'e',8Ah,'i',8Dh,'o',95h,'u',97h,' ',60h,0
        times 32-($-comp2) db 0
comp3   db 'a',83h,'e',88h,'i',8Ch,'o',93h,'u',96h,' ',5Eh,0
        times 32-($-comp3) db 0
comp4   db 'a',84h,'e',89h,'i',8Bh,'o',94h,'u',81h,'y',98h
        db 'A',8Eh,'O',99h,'U',9Ah,' ',22h,0
        times 32-($-comp4) db 0
TABLEN  equ $-captab                    ; captab+maptab+cp850+comp1..4
comptab dw  comp1,comp2,comp3,comp4
standalone db 0,27h,60h,5Eh,22h ; accent sol (morta + caracter no compost)

; ---------------------------------------------------------------------
int9:
        push    ax
        push    bx
        push    cx
        push    dx
        push    si
        push    di
        push    ds
        push    es
        mov     ax,cs
        mov     ds,ax
        cmp     word [mousefar+2],0     ; botons del ratoli?
        je      .nom
        in      al,60h
        cmp     al,7Dh
        je      .mb
        cmp     al,7Eh
        je      .mb
        cmp     al,0FDh
        je      .mb
        cmp     al,0FEh
        je      .mb
.nom:   cmp     byte [busy],0
        jne     chain
        cmp     byte [enabled],0
        je      chain
        in      al,60h
        cmp     al,0E0h
        je      .ext
        cmp     al,0E1h
        je      .ext
        mov     ah,[prev_e0]
        mov     byte [prev_e0],0
        test    al,80h                  ; alliberament -> BIOS
        jnz     chain
        or      ah,ah                   ; tecla estesa (E0 xx) -> BIOS
        jnz     chain
        mov     dl,al                   ; dl = codi
        mov     ax,40h
        mov     es,ax
        mov     bl,[es:17h]             ; estat de modificadors
        mov     bh,bl
        and     bh,0Ch
        cmp     bh,0Ch                  ; Ctrl+Alt: nomes la taula emergent
        jne     .nca
        cmp     byte [haspop],0
        je      chain
        cmp     dl,[popkey]
        jne     chain
        mov     byte [popflag],1
        mov     ax,0FF00h               ; s'empassa la tecla
        jmp     short .go
.nca:   call    getclass                ; cl = classe
        cmp     cl,1
        ja      .nocaps
        test    bl,40h                  ; Bloq Maj?
        jz      .nocaps
        call    testcaps
        jz      .nocaps
        xor     cl,1
.nocaps:
        mov     al,10
        mul     dl
        mov     si,ax
        mov     al,cl
        cbw
        shl     ax,1
        add     si,ax
        mov     ax,[maptab+si]
        or      ax,ax
        jnz     .go
        cmp     byte [pending],0        ; no mapejada i sense morta
        je      chain
.go:
        mov     [newword],ax
        mov     ax,[es:1Ch]
        mov     [oldtail],ax
        mov     byte [busy],1
        pushf
        call    far [old9]              ; la BIOS fa la seva feina
        cli
        mov     ax,cs
        mov     ds,ax
        mov     ax,40h
        mov     es,ax
        mov     di,[oldtail]
        cmp     di,[es:1Ch]
        je      .noins
        mov     ax,[newword]            ; la BIOS ha posat una paraula
        or      ax,ax
        jnz     .rep
        mov     ax,[es:di]              ; no mapejada: la de la BIOS
.rep:
        mov     [es:1Ch],di             ; la treu i hi posa la nostra
        call    emit
        jmp     short .done
.noins:
        mov     ax,[newword]            ; la BIOS no ha posat res
        or      ax,ax
        jz      .done
        call    emit
.done:
        mov     byte [busy],0
.pret:  pop     es
        pop     ds
        pop     di
        pop     si
        pop     dx
        pop     cx
        pop     bx
        pop     ax
        iret
.mb:    call    far [mousefar]          ; reconeix el codi i fa l'EOI
        jmp     short .pret
.ext:
        mov     byte [prev_e0],1
chain:
        pop     es
        pop     ds
        pop     di
        pop     si
        pop     dx
        pop     cx
        pop     bx
        pop     ax
        jmp     far [cs:old9]

; bl = indicadors 40:17  ->  cl = classe 0..4
getclass:
        test    bl,08h
        jz      .na
        mov     cl,3
        test    bl,03h
        jz      .r
        mov     cl,4
        ret
.na:    mov     cl,2
        test    bl,04h
        jnz     .r
        mov     cl,0
        test    bl,03h
        jz      .r
        mov     cl,1
.r:     ret

; dl = codi -> ZF=0 si Bloq Maj l'afecta (destrueix al)
testcaps:
        push    bx
        push    cx
        mov     bl,dl
        mov     cl,3
        shr     bl,cl
        xor     bh,bh
        mov     cl,dl
        and     cl,7
        mov     al,1
        shl     al,cl
        test    [captab+bx],al
        pop     cx
        pop     bx
        ret

; ax = paraula a emetre (es=40h, ds=cs)
emit:
        cmp     ah,0FFh
        jne     .normal
        or      al,al
        jz      .ret                    ; FF00: empassar
        mov     ah,[pending]            ; tecla morta
        mov     [pending],al
        or      ah,ah
        jz      .ret
        mov     al,ah                   ; morta + morta: accent sol
        call    putstand
.ret:   ret
.normal:
        mov     cl,[pending]
        or      cl,cl
        jz      put
        mov     byte [pending],0
        or      al,al
        jz      put                     ; tecla sense ASCII: perd l'accent
        push    ax
        mov     bl,cl
        xor     bh,bh
        dec     bx
        shl     bx,1
        mov     si,[comptab+bx]
.lp:    mov     ah,[si]
        or      ah,ah
        jz      .nf
        cmp     ah,al
        je      .found
        add     si,2
        jmp     short .lp
.found: pop     ax
        mov     al,[si+1]
        jmp     short put
.nf:    mov     al,cl                   ; no es compon: accent + caracter
        call    putstand
        pop     ax
        jmp     short put

; al = 1..4 -> posa l'accent sol
putstand:
        mov     bl,al
        xor     bh,bh
        mov     al,[standalone+bx]
        xor     ah,ah
; ax -> buffer de teclat de la BIOS
put:
        push    bx
        push    cx
        push    dx
        push    di
        mov     di,[es:1Ch]
        mov     bx,[es:80h]             ; buffer AT (si es valid)
        mov     dx,[es:82h]
        cmp     bx,1Eh
        jb      .fixed
        cmp     dx,bx
        jbe     .fixed
        cmp     di,bx
        jb      .fixed
        cmp     di,dx
        jae     .fixed
        mov     cx,bx
        jmp     short .ok
.fixed: mov     cx,1Eh                  ; buffer XT classic
        mov     dx,3Eh
        cmp     di,cx
        jb      .out
        cmp     di,dx
        jae     .out
.ok:    mov     bx,di
        add     bx,2
        cmp     bx,dx
        jb      .nw
        mov     bx,cx
.nw:    cmp     bx,[es:1Ah]
        je      .out                    ; ple
        mov     [es:di],ax
        mov     [es:1Ch],bx
.out:   pop     di
        pop     dx
        pop     cx
        pop     bx
        ret

res_end:
RESSIZE   equ   res_end-$$              ; bytes des de 100h

; =====================================================================
;              MODUL DE RATOLI (/M) - AMSMOUSE integrat
;  Tot el modul fa servir el seu propi segment: CS = DS = inici del modul.
;  Les adreces absolutes s'escriuen M(etiqueta) = desplacament dins el modul.
; =====================================================================
mstart:
%define M(x) ((x)-mstart)
old08           dd 0
old33           dd 0
jmpaddr         dw 0

; --- estat desable amb les funcions 15h-17h -------------------------------
st_begin:
hidecnt         dw -1                   ; 0 = cursor visible
posx            dw 320
posy            dw 100
minx            dw 0
maxx            dw 639
miny            dw 0
maxy            dw 199
buttons         dw 0
presscnt        dw 0,0                  ; bot¢ 0 = esquerre, 1 = dret
pressx          dw 0,0
pressy          dw 0,0
relcnt          dw 0,0
relx            dw 0,0
rely            dw 0,0
mickx           dw 8                    ; mickeys per 8 p¡xels
micky           dw 16
accx            dw 0
accy            dw 0
motx            dw 0
moty            dw 0
evmask          dw 0
evhand          dd 0
txtscr          dw 77FFh
txtcur          dw 7700h
hotx            dw 1
hoty            dw 1
gmask:
%macro ARROW 0
        dw 3FFFh,1FFFh,0FFFh,07FFh,03FFh,01FFh,00FFh,007Fh  ; m…scara pantalla
        dw 01FFh,01FFh,0F0FFh,0F0FFh,0F9FFh,0FFFFh,0FFFFh,0FFFFh
        dw 0000h,4000h,6000h,7000h,7800h,7C00h,7E00h,7F00h  ; m…scara cursor
        dw 7C00h,4C00h,0600h,0600h,0000h,0000h,0000h,0000h
%endmacro
        ARROW
sens            dw 50,50,50
vpage           dw 0
disabled        db 0
st_end:
ST_LEN          equ st_end - st_begin

; --- estat intern ----------------------------------------------------------
drawn           db 0                    ; 0 res, 1 text, 2 gr…fic
d_addr          dw 0                    ; text: offset; gr…fic: posici¢ en bits
d_seg           dw 0
d_row           dw 0
d_val           dw 0
d_saved         dw 0
n_kind          db 0
n_addr          dw 0
n_seg           dw 0
n_row           dw 0
g_mode          db 0
g_rsh           db 0
g_lsh           db 0
g_bcol          dw 0
andb            db 0,0,0
xorb            db 0,0,0
gsave           times 48 db 0
tbusy           db 0
hbusy           db 0
alevel          db 2                    ; corba d'acceleracio 0-3
acctab          db 4,4,4,4              ; 0: sense acceleracio
                db 4,5,6,8              ; 1: x1 x1,25 x1,5 x2
                db 4,6,8,12             ; 2: x1 x1,5  x2   x3
                db 4,8,12,16            ; 3: x1 x2    x3   x4
                                        ; (0-3, 4-7, 8-15, 16+ mickeys/tic)

defarrow:
        ARROW

; ---------------------------------------------------------------------------
;  INT 08h - tic del rellotge: llegeix els comptadors de moviment
; ---------------------------------------------------------------------------
int08:
        pushf
        call    far [cs:M(old08)]
        push    ax
        push    bx
        push    cx
        push    dx
        push    si
        push    di
        push    bp
        push    ds
        push    es
        push    cs
        pop     ds
        cmp     byte [M(tbusy)],0
        jne     .out
        cmp     byte [M(disabled)],0    ; desactivat: no toca els ports
        jne     .out
        mov     byte [M(tbusy)],1
        in      al,78h
        mov     bl,al
        in      al,7Ah
        mov     bh,al
        xor     al,al
        out     78h,al
        out     7Ah,al
        or      bx,bx
        jz      .done
        cli
        mov     cl,3
        mov     al,bl                   ; --- X
        cbw
        add     [M(motx)],ax
        call    accel
        add     ax,[M(accx)]
        cwd
        idiv    word [M(mickx)]
        mov     [M(accx)],dx
        add     ax,[M(posx)]
        call    clampx
        mov     al,bh                   ; --- Y (invertit)
        cbw
        neg     ax
        add     [M(moty)],ax
        call    accel
        add     ax,[M(accy)]
        cwd
        idiv    word [M(micky)]
        mov     [M(accy)],dx
        add     ax,[M(posy)]
        call    clampy
        call    cur_update
        sti
        mov     ax,1                    ; esdeveniment: moviment
        call    fire_event
.done:
        mov     byte [M(tbusy)],0
.out:
        pop     es
        pop     ds
        pop     bp
        pop     di
        pop     si
        pop     dx
        pop     cx
        pop     bx
        pop     ax
        iret

; ---------------------------------------------------------------------------
;  Acceleracio: AX = mickeys d'un tic -> AX = mickeys * multiplicador * 8
;  (el multiplicador es en quarts, segons la velocitat i el nivell 0-3)
; ---------------------------------------------------------------------------
accel:
        push    bx
        push    dx
        mov     dx,ax
        or      dx,dx
        jns     .p
        neg     dx
.p:     xor     bx,bx
        cmp     dx,4
        jb      .i
        inc     bx
        cmp     dx,8
        jb      .i
        inc     bx
        cmp     dx,16
        jb      .i
        inc     bx
.i:     mov     dl,[M(alevel)]
        and     dl,3
        shl     dl,1
        shl     dl,1
        add     bl,dl
        mov     dl,[M(acctab)+bx]
        xor     dh,dh
        imul    dx
        shl     ax,1
        pop     dx
        pop     bx
        ret

; ---------------------------------------------------------------------------
;  MBTN - el crida la INT 09h de KEYBX (call far) amb AL = codi de bot¢
;  (7Eh/7Dh pr‚mer, 0FEh/0FDh deixar anar). Reconeix el codi i fa l'EOI.
; ---------------------------------------------------------------------------
mbtn:
        push    bx
        push    cx
        push    dx
        push    si
        push    di
        push    bp
        push    ds
        push    es
        push    cs
        pop     ds
        mov     ah,al
        in      al,61h                  ; reconeix el codi al teclat
        mov     bl,al
        or      al,80h
        out     61h,al
        mov     al,bl
        out     61h,al
        mov     al,20h                  ; EOI
        out     20h,al
        cmp     byte [M(disabled)],0
        jne     .x
        mov     al,ah
        mov     bx,1                    ; esquerre: bit 0, ¡ndex 0, esd. 2
        xor     si,si
        mov     dx,2
        mov     cl,al
        and     cl,7Fh
        cmp     cl,7Eh
        je      .btn
        mov     bx,2                    ; dret: bit 1, ¡ndex 1, esd. 8
        mov     si,2
        mov     dx,8
.btn:
        cli
        test    al,80h
        jnz     .rel
        or      [M(buttons)],bx
        inc     word [M(presscnt)+si]
        mov     ax,[M(posx)]
        mov     [M(pressx)+si],ax
        mov     ax,[M(posy)]
        mov     [M(pressy)+si],ax
        jmp     short .ev
.rel:
        not     bx
        and     [M(buttons)],bx
        inc     word [M(relcnt)+si]
        mov     ax,[M(posx)]
        mov     [M(relx)+si],ax
        mov     ax,[M(posy)]
        mov     [M(rely)+si],ax
        shl     dx,1                    ; esd. deixar anar = pr‚mer * 2
.ev:
        sti
        mov     ax,dx
        call    fire_event
.x:
        pop     es
        pop     ds
        pop     bp
        pop     di
        pop     si
        pop     dx
        pop     cx
        pop     bx
        retf

; ---------------------------------------------------------------------------
;  Crida la rutina d'usuari (funci¢ 0Ch) si toca.  AX = condicions
; ---------------------------------------------------------------------------
fire_event:
        and     ax,[M(evmask)]
        jz      .r
        cmp     byte [M(hbusy)],0
        jne     .r
        mov     byte [M(hbusy)],1
        push    ax
        push    bx
        push    cx
        push    dx
        push    si
        push    di
        push    bp
        push    ds
        push    es
        mov     bx,[M(buttons)]
        mov     cx,[M(posx)]
        mov     dx,[M(posy)]
        mov     si,[M(motx)]
        mov     di,[M(moty)]
        call    far [cs:M(evhand)]
        pop     es
        pop     ds
        pop     bp
        pop     di
        pop     si
        pop     dx
        pop     cx
        pop     bx
        pop     ax
        mov     byte [cs:M(hbusy)],0
.r:     ret

; --- limita AX a [minx,maxx] i el desa a posx ------------------------------
clampx:
        cmp     ax,[M(minx)]
        jge     .a
        mov     ax,[M(minx)]
.a:     cmp     ax,[M(maxx)]
        jle     .b
        mov     ax,[M(maxx)]
.b:     mov     [M(posx)],ax
        ret

clampy:
        cmp     ax,[M(miny)]
        jge     .a
        mov     ax,[M(miny)]
.a:     cmp     ax,[M(maxy)]
        jle     .b
        mov     ax,[M(maxy)]
.b:     mov     [M(posy)],ax
        ret

; ---------------------------------------------------------------------------
;  Cursor.  Totes les rutines cur_* conserven els registres.  DS = CS.
; ---------------------------------------------------------------------------

; Calcula on aniria el cursor: n_kind, n_addr, n_seg, n_row
; (fa servir AX BX CX DX SI ES)
cur_calc:
        mov     byte [M(n_kind)],0
        mov     ax,40h
        mov     es,ax
        mov     al,[es:49h]             ; mode de v¡deo actual
        cmp     al,7
        je      .mono
        cmp     al,3
        jbe     .text
        cmp     al,6
        ja      .r
        mov     bx,[M(posx)]               ; modes gr…fics 4, 5, 6
        sub     bx,[M(hotx)]
        cmp     al,6
        je      .g6
        and     bx,0FFFEh               ; 320x200: 2 bits per p¡xel
.g6:    mov     [M(n_addr)],bx
        mov     bx,[M(posy)]
        sub     bx,[M(hoty)]
        mov     [M(n_row)],bx
        mov     word [M(n_seg)],0B800h
        mov     byte [M(n_kind)],2
.r:     ret
.mono:  mov     word [M(n_seg)],0B000h
        jmp     short .t2
.text:  mov     word [M(n_seg)],0B800h
.t2:    mov     bx,[es:4Ah]             ; columnes
        mov     ax,[M(posx)]
        mov     cl,3
        cmp     bx,40
        ja      .c80
        mov     cl,4
.c80:   shr     ax,cl
        cmp     ax,bx
        jb      .colok
        mov     ax,bx
        dec     ax
.colok: mov     si,ax
        mov     ax,[M(posy)]
        mov     cl,3
        shr     ax,cl
        mul     bx
        add     ax,si
        shl     ax,1
        add     ax,[es:4Eh]             ; inici de la p…gina
        mov     [M(n_addr)],ax
        mov     byte [M(n_kind)],1
        ret

cur_draw:
        cmp     word [M(hidecnt)],0
        jne     .r
        cmp     byte [M(drawn)],0
        jne     .r
        push    ax
        push    bx
        push    cx
        push    dx
        push    si
        push    di
        push    bp
        push    es
        call    cur_calc
        mov     al,[M(n_kind)]
        cmp     al,1
        je      .text
        cmp     al,2
        jne     .done
        mov     ax,[M(n_addr)]
        mov     [M(d_addr)],ax
        mov     ax,[M(n_row)]
        mov     [M(d_row)],ax
        mov     byte [M(drawn)],2
        mov     al,1
        call    gfx_apply
        jmp     short .done
.text:
        mov     es,[M(n_seg)]
        mov     di,[M(n_addr)]
        mov     ax,[es:di]
        mov     [M(d_saved)],ax
        and     ax,[M(txtscr)]
        xor     ax,[M(txtcur)]
        mov     [es:di],ax
        mov     [M(d_val)],ax
        mov     [M(d_addr)],di
        mov     [M(d_seg)],es
        mov     byte [M(drawn)],1
.done:
        pop     es
        pop     bp
        pop     di
        pop     si
        pop     dx
        pop     cx
        pop     bx
        pop     ax
.r:     ret

cur_remove:
        cmp     byte [M(drawn)],0
        je      .r
        push    ax
        push    bx
        push    cx
        push    dx
        push    si
        push    di
        push    bp
        push    es
        cmp     byte [M(drawn)],1
        jne     .g
        mov     es,[M(d_seg)]
        mov     di,[M(d_addr)]
        mov     ax,[es:di]
        cmp     ax,[M(d_val)]              ; nom‚s si ning£ no l'ha sobreescrit
        jne     .clr
        mov     ax,[M(d_saved)]
        mov     [es:di],ax
        jmp     short .clr
.g:     mov     al,0
        call    gfx_apply
.clr:   mov     byte [M(drawn)],0
        pop     es
        pop     bp
        pop     di
        pop     si
        pop     dx
        pop     cx
        pop     bx
        pop     ax
.r:     ret

; Redibuixa nom‚s si el cursor ha canviat de celúla / p¡xel
cur_update:
        cmp     word [M(hidecnt)],0
        jne     .r
        push    ax
        push    bx
        push    cx
        push    dx
        push    si
        push    es
        call    cur_calc
        mov     al,[M(n_kind)]
        cmp     al,[M(drawn)]
        jne     .redo
        or      al,al
        jz      .done
        mov     ax,[M(n_addr)]
        cmp     ax,[M(d_addr)]
        jne     .redo
        cmp     byte [M(drawn)],2
        jne     .done
        mov     ax,[M(n_row)]
        cmp     ax,[M(d_row)]
        je      .done
.redo:  call    cur_remove
        call    cur_draw
.done:  pop     es
        pop     si
        pop     dx
        pop     cx
        pop     bx
        pop     ax
.r:     ret

; Cursor gr…fic CGA (modes 4/5/6).  AL = 1 dibuixa, 0 restaura.
; Fa servir d_addr (posici¢ en bits) i d_row.  No conserva registres.
gfx_apply:
        mov     [M(g_mode)],al
        mov     ax,0B800h
        mov     es,ax
        mov     ax,[M(d_addr)]
        or      ax,ax
        jns     .pos
        neg     ax
        cmp     ax,16
        jbe     .l1
        mov     ax,16
.l1:    mov     [M(g_lsh)],al
        mov     byte [M(g_rsh)],0
        mov     word [M(g_bcol)],0
        jmp     short .go
.pos:   mov     bl,al
        and     bl,7
        mov     [M(g_rsh)],bl
        mov     byte [M(g_lsh)],0
        mov     cl,3
        shr     ax,cl
        mov     [M(g_bcol)],ax
.go:    xor     bp,bp                   ; fila 0..15
.row:
        mov     ax,[M(d_row)]
        add     ax,bp
        cmp     ax,0
        jl      .next
        cmp     ax,200
        jge     .next
        mov     di,ax
        shr     ax,1
        mov     dx,80
        mul     dx
        test    di,1
        mov     di,ax
        jz      .even
        add     di,2000h
.even:  add     di,[M(g_bcol)]
        mov     bx,bp                   ; bx -> gsave[fila*3]
        shl     bx,1
        add     bx,bp
        add     bx,M(gsave)
        cmp     byte [M(g_mode)],0
        jne     .draw
        mov     dx,[M(g_bcol)]             ; --- restaura
        mov     cx,3
.rk:    cmp     dx,80
        jae     .rs
        mov     al,[bx]
        mov     [es:di],al
.rs:    inc     bx
        inc     di
        inc     dx
        loop    .rk
        jmp     short .next
.draw:
        push    bx
        mov     si,bp
        shl     si,1
        mov     ax,[M(gmask)+si]           ; AND
        mov     dx,[M(gmask)+32+si]        ; XOR
        mov     bx,00FFh                ; BL = AND baix, BH = XOR baix
        mov     cl,[M(g_lsh)]
        or      cl,cl
        jz      .nol
.lsh:   stc
        rcl     ax,1
        shl     dx,1
        dec     cl
        jnz     .lsh
.nol:   mov     cl,[M(g_rsh)]
        or      cl,cl
        jz      .nor
.rsh:   stc
        rcr     ax,1
        rcr     bl,1
        clc
        rcr     dx,1
        rcr     bh,1
        dec     cl
        jnz     .rsh
.nor:   mov     [M(andb)],ah
        mov     [M(andb)+1],al
        mov     [M(andb)+2],bl
        mov     [M(xorb)],dh
        mov     [M(xorb)+1],dl
        mov     [M(xorb)+2],bh
        pop     bx
        mov     dx,[M(g_bcol)]
        xor     si,si
        mov     cx,3
.dk:    cmp     dx,80
        jae     .ds
        mov     al,[es:di]
        mov     [bx],al
        and     al,[M(andb)+si]
        xor     al,[M(xorb)+si]
        mov     [es:di],al
.ds:    inc     bx
        inc     di
        inc     si
        inc     dx
        loop    .dk
.next:  inc     bp
        cmp     bp,16
        jb      .row
        ret

; ---------------------------------------------------------------------------
;  INT 33h
; ---------------------------------------------------------------------------
int33:
        cli
        push    ds
        push    cs
        pop     ds
        cmp     ax,25h
        jae     .none
        push    bx
        mov     bx,ax
        shl     bx,1
        mov     bx,[M(fntab)+bx]
        mov     [M(jmpaddr)],bx
        pop     bx
        cld
        call    [M(jmpaddr)]
.none:  pop     ds
        iret

fntab:  dw M(f00),M(f01),M(f02),M(f03),M(f04),M(f05),M(f06),M(f07),M(f08),M(f09),M(f0A),M(f0B),M(f0C),M(fnul),M(fnul),M(f0F)
        dw M(f02),M(fnul),M(fnul),M(fnul),M(f14),M(f15),M(f16),M(f17),M(fnul),M(fnul),M(f1A),M(f1B),M(fnul),M(f1D),M(f1E),M(f1F)
        dw M(f20),M(f21),M(fnul),M(f23),M(f24)

do_reset:
        call    cur_remove
        push    cx
        push    si
        push    di
        push    es
        push    cs
        pop     es
        mov     word [M(hidecnt)],-1
        mov     word [M(posx)],320
        mov     word [M(posy)],100
        mov     word [M(minx)],0
        mov     word [M(maxx)],639
        mov     word [M(miny)],0
        mov     word [M(maxy)],199
        xor     ax,ax
        mov     di,M(buttons)
        mov     cx,13                   ; buttons + 12 comptadors
        rep     stosw
        mov     word [M(mickx)],8
        mov     word [M(micky)],16
        mov     di,M(accx)
        mov     cx,7                    ; accx..evhand
        rep     stosw
        mov     word [M(txtscr)],77FFh
        mov     word [M(txtcur)],7700h
        mov     word [M(hotx)],1
        mov     word [M(hoty)],1
        mov     si,M(defarrow)
        mov     di,M(gmask)
        mov     cx,32
        rep     movsw
        mov     byte [M(disabled)],0
        pop     es
        pop     di
        pop     si
        pop     cx
        ret

f00:
f21:    call    do_reset
        mov     ax,0FFFFh
        mov     bx,2
fnul:   ret

f01:    cmp     word [M(hidecnt)],0
        jge     .r
        inc     word [M(hidecnt)]
        jnz     .r
        call    cur_draw
.r:     ret

f02:    dec     word [M(hidecnt)]
        call    cur_remove
        ret

f03:    mov     bx,[M(buttons)]
        mov     cx,[M(posx)]
        mov     dx,[M(posy)]
        ret

f04:    push    ax
        mov     ax,cx
        call    clampx
        mov     ax,dx
        call    clampy
        pop     ax
        call    cur_update
        ret

f05:    push    di
        mov     di,M(presscnt)
        jmp     short btninfo
f06:    push    di
        mov     di,M(relcnt)
btninfo:
        mov     ax,[M(buttons)]
        cmp     bx,1
        ja      .bad
        push    si
        mov     si,bx
        shl     si,1
        add     di,si
        pop     si
        mov     bx,[di]
        mov     word [di],0
        mov     cx,[di+4]
        mov     dx,[di+8]
        pop     di
        ret
.bad:   xor     bx,bx
        pop     di
        ret

f07:    push    ax
        push    cx
        push    dx
        cmp     cx,dx
        jle     .o
        xchg    cx,dx
.o:     mov     [M(minx)],cx
        mov     [M(maxx)],dx
        mov     ax,[M(posx)]
        call    clampx
        pop     dx
        pop     cx
        pop     ax
        call    cur_update
        ret

f08:    push    ax
        push    cx
        push    dx
        cmp     cx,dx
        jle     .o
        xchg    cx,dx
.o:     mov     [M(miny)],cx
        mov     [M(maxy)],dx
        mov     ax,[M(posy)]
        call    clampy
        pop     dx
        pop     cx
        pop     ax
        call    cur_update
        ret

f09:    call    cur_remove
        mov     [M(hotx)],bx
        mov     [M(hoty)],cx
        push    si
        push    di
        push    cx
        push    es
        push    ds
        mov     si,dx
        push    es
        pop     ds
        push    cs
        pop     es
        mov     di,M(gmask)
        mov     cx,32
        rep     movsw
        pop     ds
        pop     es
        pop     cx
        pop     di
        pop     si
        call    cur_draw
        ret

f0A:    or      bx,bx
        jnz     .r                      ; cursor de maquinari: no suportat
        call    cur_remove
        mov     [M(txtscr)],cx
        mov     [M(txtcur)],dx
        call    cur_draw
.r:     ret

f0B:    mov     cx,[M(motx)]
        mov     dx,[M(moty)]
        mov     word [M(motx)],0
        mov     word [M(moty)],0
        ret

f0C:    mov     [M(evmask)],cx
        mov     [M(evhand)],dx
        mov     [M(evhand)+2],es
        ret

f0F:    or      cx,cx
        jz      .y
        mov     [M(mickx)],cx
        mov     word [M(accx)],0
.y:     or      dx,dx
        jz      .r
        mov     [M(micky)],dx
        mov     word [M(accy)],0
.r:     ret

f14:    push    ax
        mov     ax,[M(evmask)]
        mov     [M(evmask)],cx
        mov     cx,ax
        mov     ax,[M(evhand)]
        mov     [M(evhand)],dx
        mov     dx,ax
        mov     ax,[M(evhand)+2]
        mov     [M(evhand)+2],es
        mov     es,ax
        pop     ax
        ret

f15:    mov     bx,ST_LEN
        ret

f16:    push    si
        push    di
        push    cx
        mov     di,dx
        mov     si,M(st_begin)
        mov     cx,ST_LEN
        rep     movsb
        pop     cx
        pop     di
        pop     si
        ret

f17:    call    cur_remove
        push    si
        push    di
        push    cx
        push    es
        push    ds
        mov     si,dx
        push    es
        pop     ds
        push    cs
        pop     es
        mov     di,M(st_begin)
        mov     cx,ST_LEN
        rep     movsb
        pop     ds
        pop     es
        pop     cx
        pop     di
        pop     si
        call    cur_draw
        ret

f1A:    mov     [M(sens)],bx
        mov     [M(sens)+2],cx
        mov     [M(sens)+4],dx
        ret

f1B:    mov     bx,[M(sens)]
        mov     cx,[M(sens)+2]
        mov     dx,[M(sens)+4]
        ret

f1D:    mov     [M(vpage)],bx
        ret

f1E:    mov     bx,[M(vpage)]
        ret

f1F:    call    cur_remove
        mov     byte [M(disabled)],1
        les     bx,[M(old33)]
        mov     ax,1Fh
        ret

f20:    mov     byte [M(disabled)],0
        ret

f23:    xor     bx,bx                   ; idioma: anglŠs
        ret

f24:    mov     bx,0626h                ; compatible amb la versi¢ 6.26
        mov     cx,0100h                ; CH = 1 (bus), CL = 0
        ret

mend:
MSIZE     equ   mend-mstart
MPARA     equ   (MSIZE+15)/16

; =====================================================================
;              MODUL DE LA TAULA EMERGENT (/P)
;  Segment propi, com el ratoli: P(etiqueta) = desplacament dins el modul.
;  Les dades del nucli (popflag, cp850) es llegeixen amb ES = coreseg.
; =====================================================================
pstart:
%define P(x) ((x)-pstart)

coreseg     dw  0               ; base del nucli (per a popflag i cp850)
old16       dd  0
inpop       db  0
sel         db  'A'             ; caracter seleccionat a la taula
slen        db  0
vbase       dw  0
vseg        dw  0
curpos      dw  0
curshape    dw  0
qhead       dw  0
qtail       dw  0
; ---------------------------------------------------------------------
;  A partir d'aqui: taula emergent. No queda resident amb /P:0.
pop_start:
;  INT 16h: obre la taula si s'ha demanat i lliura la cadena validada
int16:
        sti
        cmp     ah,0
        je      .rd
        cmp     ah,1
        je      .st
        jmp     far [cs:P(old16)]
.rd:    push    bx                      ; AH=0: lectura (espera)
.rl:    mov     bl,1
        call    popchk
        jc      .rret
        mov     ah,1
        pushf
        call    far [cs:P(old16)]
        jz      .rl
        xor     ah,ah
        pushf
        call    far [cs:P(old16)]
.rret:  pop     bx
        iret
.st:    push    bx                      ; AH=1: estat
        xor     bl,bl
        call    popchk
        jc      .sq
        pop     bx
        mov     ah,1
        jmp     far [cs:P(old16)]
.sq:    pop     bx
        push    bp
        mov     bp,sp
        and     word [bp+6],0FFBFh      ; ZF=0: hi ha tecla
        pop     bp
        iret

; bl=1 treu / bl=0 nomes mira. CF=1 i ax=paraula si n'hi ha a la cua
popchk:
        push    ds
        push    cs
        pop     ds
        push    es                      ; dada del nucli
        mov     es,[P(coreseg)]
        cmp     byte [es:popflag],0
        pop     es
        je      .q
        call    popup
.q:     push    si
        mov     si,[P(qhead)]
        cmp     si,[P(qtail)]
        je      .none
        mov     ax,[P(queue)+si]
        or      bl,bl
        jz      .peek
        add     si,2
        mov     [P(qhead)],si
.peek:  pop     si
        pop     ds
        stc
        ret
.none:  pop     si
        pop     ds
        clc
        ret

; ---------------------------------------------------------------------
;  Taula de caracters emergent (ds=cs)
TOP     equ     2
LEFT    equ     14
BOXW      equ     52
BOXH      equ     21
BOXA    equ     70h
SELA    equ     0Fh
SMAX    equ     38
QMAX    equ     40

popup:
        push    ax
        push    bx
        push    cx
        push    dx
        push    si
        push    di
        push    bp
        push    es
        push    es                      ; dada del nucli
        mov     es,[P(coreseg)]
        mov     byte [es:popflag],0
        pop     es
        cmp     byte [P(inpop)],0
        jne     .out
        mov     byte [P(inpop)],1
        push    es                      ; dada del nucli
        mov     es,[P(coreseg)]
        cmp     byte [es:cp850],2       ; joc del GEM: la taula no hi encaixa
        pop     es
        je      .beep
        mov     ah,0Fh
        int     10h                     ; al=mode ah=columnes bh=pagina
        mov     dx,0B000h
        cmp     al,7
        je      .txt
        mov     dx,0B800h
        cmp     al,2
        je      .txt
        cmp     al,3
        je      .txt
.beep:  mov     ax,0E07h                ; no es mode de text de 80 col.
        int     10h
        jmp     .done
.txt:   cmp     ah,80
        jne     .beep
        mov     [P(vseg)],dx
        push    es
        mov     ax,40h
        mov     es,ax
        mov     ax,[es:4Eh]             ; inici de la pagina activa
        pop     es
        mov     [P(vbase)],ax
        mov     ah,3
        int     10h
        mov     [P(curpos)],dx
        mov     [P(curshape)],cx
        mov     ah,1
        mov     cx,2000h                ; amaga el cursor
        int     10h
        call    savescr
        mov     byte [P(slen)],0
        call    draw
.rk:    xor     ah,ah
        pushf
        call    far [P(old16)]
        cmp     al,1Bh                  ; Esc
        je      .close
        cmp     ax,4400h                ; F10
        je      .accept
        cmp     al,0Ah                  ; Ctrl+Intro
        je      .accept
        cmp     al,0Dh                  ; Intro
        je      .addsel
        cmp     al,08h                  ; Retroces
        je      .bs
        or      al,al
        jz      .ext
        cmp     al,0E0h
        je      .ext
        cmp     al,20h
        jb      .rk
        call    setsel                  ; caracter teclejat
        jmp     short .add
.addsel:
        mov     al,[P(sel)]
.add:   mov     bl,[P(slen)]
        cmp     bl,SMAX
        jae     .rk
        xor     bh,bh
        mov     [P(sbuf)+bx],al
        inc     byte [P(slen)]
        call    drawstr
        jmp     .rk
.bs:    cmp     byte [P(slen)],0
        je      .rk
        dec     byte [P(slen)]
        call    drawstr
        jmp     .rk
.rkj:   jmp     .rk
.ext:   mov     al,[P(sel)]
        cmp     ah,48h                  ; amunt
        jne     .e1
        cmp     al,48
        jb      .rkj
        sub     al,16
        jmp     short .set
.e1:    cmp     ah,50h                  ; avall
        jne     .e2
        cmp     al,240
        jae     .rkj
        add     al,16
        jmp     short .set
.e2:    cmp     ah,4Bh                  ; esquerra
        jne     .e3
        cmp     al,32
        jbe     .rkj
        dec     al
        jmp     short .set
.e3:    cmp     ah,4Dh                  ; dreta
        jne     .e4
        cmp     al,255
        je      .rkj
        inc     al
        jmp     short .set
.e4:    cmp     ah,47h                  ; Inici: principi de fila
        jne     .e5
        sub     al,32
        and     al,0F0h
        add     al,32
        jmp     short .set
.e5:    cmp     ah,4Fh                  ; Fi: final de fila
        jne     .e6
        sub     al,32
        or      al,0Fh
        add     al,32
        jmp     short .set
.e6:    cmp     ah,49h                  ; RePag: primera fila
        jne     .e7
        sub     al,32
        and     al,0Fh
        add     al,32
        jmp     short .set
.e7:    cmp     ah,51h                  ; AvPag: darrera fila
        je      .e8
        jmp     .rk
.e8:    sub     al,32
        and     al,0Fh
        add     al,240
.set:   call    setsel
        jmp     .rk
.accept:
        mov     si,[P(qhead)]              ; afegeix la cadena a la cua
        cmp     si,[P(qtail)]
        jne     .ap
        xor     si,si
        mov     [P(qhead)],si
        mov     [P(qtail)],si
.ap:    mov     di,[P(qtail)]
        xor     bx,bx
.al:    cmp     bl,[P(slen)]
        jae     .ae
        cmp     di,QMAX*2
        jae     .ae
        mov     al,[P(sbuf)+bx]
        xor     ah,ah
        mov     [P(queue)+di],ax
        add     di,2
        inc     bx
        jmp     short .al
.ae:    mov     [P(qtail)],di
.close: call    restscr
        mov     ah,1
        mov     cx,[P(curshape)]
        int     10h
        mov     ah,0Fh
        int     10h
        mov     ah,2
        mov     dx,[P(curpos)]
        int     10h
.done:  mov     byte [P(inpop)],0
        push    es                      ; dada del nucli
        mov     es,[P(coreseg)]
        mov     byte [es:popflag],0
        pop     es
.out:   pop     es
        pop     bp
        pop     di
        pop     si
        pop     dx
        pop     cx
        pop     bx
        pop     ax
        ret

; dh = fila, dl = columna (dins la finestra) -> di = offset a la pantalla
vaddr:  push    ax
        push    dx
        mov     al,dh
        add     al,TOP
        mov     ah,80
        mul     ah
        xor     dh,dh
        add     dl,LEFT
        add     ax,dx
        shl     ax,1
        add     ax,[P(vbase)]
        mov     di,ax
        pop     dx
        pop     ax
        ret

savescr:
        mov     bx,P(savebuf)
        xor     dh,dh
.r:     xor     dl,dl
        call    vaddr
        push    ds
        mov     si,di
        mov     di,bx
        push    cs
        pop     es
        mov     ds,[P(vseg)]
        mov     cx,BOXW
        rep     movsw
        pop     ds
        mov     bx,di
        inc     dh
        cmp     dh,BOXH
        jb      .r
        ret

restscr:
        mov     si,P(savebuf)
        mov     es,[P(vseg)]
        xor     dh,dh
.r:     xor     dl,dl
        call    vaddr
        mov     cx,BOXW
        rep     movsw
        inc     dh
        cmp     dh,BOXH
        jb      .r
        ret

; al=esquerra bl=farciment bh=dreta ah=atribut dh=fila
hline:  xor     dl,dl
        call    vaddr
        stosw
        mov     al,bl
        mov     cx,BOXW-2
        rep     stosw
        mov     al,bh
        stosw
        ret

; si -> ASCIIZ a (dh,dl) amb atribut ah / putsc: a partir de di
puts:   call    vaddr
putsc:  lodsb
        or      al,al
        jz      .r
        stosw
        jmp     short putsc
.r:     ret

draw:   mov     es,[P(vseg)]
        mov     ah,BOXA
        xor     dh,dh
        mov     al,0C9h
        mov     bl,0CDh
        mov     bh,0BBh
        call    hline
        mov     dh,1
.r1:    mov     al,0BAh
        mov     bl,' '
        mov     bh,0BAh
        call    hline
        inc     dh
        cmp     dh,BOXH-1
        jb      .r1
        mov     dh,15
        mov     al,0C7h
        mov     bl,0C4h
        mov     bh,0B6h
        call    hline
        mov     dh,BOXH-1
        mov     al,0C8h
        mov     bl,0CDh
        mov     bh,0BCh
        call    hline
        xor     dh,dh
        mov     dl,3
        mov     si,P(t_title)
        call    puts
        push    es                      ; dada del nucli
        mov     es,[P(coreseg)]
        mov     bl,[es:cp850]           ; joc de les tecles mortes
        pop     es
        xor     bh,bh
        shl     bx,1
        mov     si,[P(t_cps)+bx]
        call    putsc
        mov     cl,32                   ; graella 32..255
.g:     call    drawcell
        inc     cl
        jnz     .g
        mov     dh,18
        mov     dl,2
        mov     ah,BOXA
        mov     si,P(t_help1)
        call    puts
        mov     dh,19
        mov     dl,2
        mov     si,P(t_help2)
        call    puts
        call    drawinfo
        jmp     drawstr

; al = nova seleccio: nomes redibuixa les dues caselles i la linia d'info
setsel: push    ax
        mov     cl,[P(sel)]
        mov     [P(sel)],al
        cmp     cl,al
        je      .r
        push    ax
        call    drawcell                ; l'antiga, ja sense ressaltar
        pop     ax
        mov     cl,al
        call    drawcell
        call    drawinfo
.r:     pop     ax
        ret

; cl = caracter: dibuixa la seva casella (conserva cx)
drawcell:
        mov     es,[P(vseg)]
        mov     al,cl
        sub     al,32
        xor     ah,ah
        mov     bl,16
        div     bl                      ; al = fila, ah = columna
        mov     dh,al
        inc     dh
        mov     al,ah
        mov     bl,3
        mul     bl
        add     al,2
        mov     dl,al
        call    vaddr
        mov     ah,BOXA
        cmp     cl,[P(sel)]
        jne     .gn
        mov     ah,SELA
.gn:    mov     al,' '
        stosw
        mov     al,cl
        stosw
        mov     al,' '
        stosw
        ret

; linia amb el caracter, decimal i hexadecimal
drawinfo:
        mov     es,[P(vseg)]
        mov     dh,16
        mov     dl,2
        mov     ah,BOXA
        mov     si,P(t_car)
        call    puts
        mov     al,[P(sel)]
        mov     ah,SELA
        stosw
        mov     ah,BOXA
        mov     si,P(t_dec)
        call    putsc
        mov     al,[P(sel)]
        call    vdec3
        mov     ah,BOXA
        mov     si,P(t_hex)
        call    putsc
        mov     al,[P(sel)]
        jmp     vhex2

; linia de la cadena (i una casella en blanc darrere el cursor)
drawstr:
        mov     es,[P(vseg)]
        mov     dh,17
        mov     dl,2
        mov     ah,BOXA
        mov     si,P(t_str)
        call    puts
        xor     bx,bx
.s:     cmp     bl,[P(slen)]
        jae     .se
        mov     al,[P(sbuf)+bx]
        stosw
        inc     bx
        jmp     short .s
.se:    mov     ax,(SELA<<8)|' '
        stosw
        mov     ax,(BOXA<<8)|' '
        stosw
        ret

vdec3:  xor     ah,ah                   ; al -> 3 xifres a es:di
        mov     bl,100
        div     bl
        mov     dl,ah
        add     al,'0'
        mov     ah,BOXA
        stosw
        mov     al,dl
        xor     ah,ah
        mov     bl,10
        div     bl
        mov     dl,ah
        add     al,'0'
        mov     ah,BOXA
        stosw
        mov     al,dl
        add     al,'0'
        stosw
        ret

vhex2:  mov     dl,al                   ; al -> 2 xifres hex a es:di
        mov     cl,4
        shr     al,cl
        call    .h
        mov     al,dl
        and     al,0Fh
.h:     add     al,'0'
        cmp     al,'9'
        jbe     .s
        add     al,7
.s:     mov     ah,BOXA
        stosw
        ret

t_title db  ` KEYBX: taula de car\x85cters (`,0
t_cps   dw  P(t_437),P(t_850),P(t_gem)
t_437   db  'CP437) ',0
t_850   db  'CP850) ',0
t_gem   db  'GEM) ',0
t_car   db  `Car\x85cter: `,0
t_dec   db  `   Dec: `,0
t_hex   db  `   Hex: `,0
t_str   db  `Cadena: `,0
t_help1 db  `\x18\x19\x1B\x1A mou   Intro afegeix   Retroc esborra`,0
t_help2 db  `F10 insereix   Esc cancel\xFAla   o tecleja`,0

sbuf    times SMAX db 0
queue   times QMAX dw 0
savebuf times BOXW*BOXH dw 0


pend:
PSIZE     equ   pend-pstart
PPARA     equ   (PSIZE+15)/16
RESPARA   equ   (RESSIZE+15)/16
KEEPPARA  equ   (RESSIZE+100h+15)/16    ; amb el PSP

; =====================================================================
;                      PART TRANSITORIA
; =====================================================================
MAXBUF  equ     24000

init:
        cld
        mov     sp,stktop               ; pila dins la zona que es conserva
        mov     dx,m_banner
        call    print
        call    parsecmd
        call    findres
        cmp     byte [o_help],0
        je      .nh
        mov     dx,m_help
        call    print
        jmp     exit0
.nh:    cmp     byte [o_test],0
        je      .nt
        jmp     testmode
.nt:    cmp     byte [o_learn],0
        je      .nl
        jmp     learn
.nl:    cmp     byte [o_on],0
        jne     setonoff
        cmp     byte [o_off],0
        jne     setonoff
        cmp     byte [o_unin],0
        je      .nu
        jmp     uninstall
.nu:    cmp     byte [havename],0
        jne     install
        cmp     word [resseg],0
        jne     .res
        cmp     byte [o_mrem],0
        je      install
        mov     dx,m_nores
        jmp     fail
.res:   cmp     byte [o_high],0         ; nomes /H:seg: mou el nucli
        je      .r1
        mov     al,[o_pop]
        or      al,[o_prem]
        or      al,[o_mouse]
        or      al,[o_mrem]
        jnz     .r1
        call    mvcore
.r1:    cmp     byte [o_850],0          ; nomes /437 /850 /GEM: canvia el joc
        je      .ncp
        call    setcp
.ncp:   call    pcmd                    ; /P, /P:xx, /P-
        call    mcmd                    ; /M, /M:n, /M-
        jmp     status

exit0:  mov     ax,4C00h
        int     21h
exit1:  mov     ax,4C01h
        int     21h
fail:   call    print                   ; dx = missatge
        jmp     exit1

; ---------------------------------------------------------------------
status:
        mov     es,[resseg]
        mov     dx,m_isres
        call    print
        mov     dx,m_on
        cmp     byte [es:enabled],0
        jne     .p
        mov     dx,m_off
.p:     call    print
        mov     es,[resseg]
        mov     al,[es:cp850]
        call    prcpn
        mov     es,[resseg]
        mov     al,[es:haspop]
        mov     ah,[es:popkey]
        mov     bl,[es:cp850]
        mov     bh,[es:enabled]
        call    prpop
        mov     es,[resseg]
        call    prmouse
        mov     es,[resseg]
        cmp     word [es:hiseg],0
        je      .x
        mov     dx,m_athigh
        call    print
        mov     es,[resseg]
        mov     ax,[es:hiseg]
        call    phex16
        call    crlf
.x:     jmp     exit0

setonoff:
        cmp     word [resseg],0
        jne     .ok
        mov     dx,m_nores
        jmp     fail
.ok:    mov     es,[resseg]
        mov     al,0
        cmp     byte [o_on],0
        je      .s
        mov     al,1
.s:     mov     [es:enabled],al
        jmp     status

; ---------------------------------------------------------------------
uninstall:
        cmp     word [resseg],0
        jne     .ok
        mov     dx,m_nores
        jmp     fail
.ok:    mov     es,[resseg]             ; primer comprova els moduls
        cmp     byte [es:haspop],0
        je      .c1
        call    pchk
        jc      .x
.c1:    mov     es,[resseg]
        cmp     word [es:mousefar+2],0
        je      .c2
        call    mchk
        jc      .x
        mov     es,[resseg]
        call    mfree
.c2:    mov     es,[resseg]
        cmp     byte [es:haspop],0
        je      .go1
        call    pfree
        jmp     short .go1
.x:     jmp     exit1
.go1:   mov     es,[resseg]
        cli
        push    ds
        lds     dx,[es:old9]
        mov     ax,2509h
        int     21h
        pop     ds
.n16:   sti
        mov     byte [es:sig],0
        cmp     word [es:hiseg],0
        jne     .hi
        mov     ah,49h                  ; allibera el bloc del resident
        int     21h
        jmp     short .un
.hi:    mov     cx,[es:ressz]           ; memoria alta: deixa la zona buida
        mov     di,100h
        xor     al,al
        rep     stosb
.un:    mov     dx,m_unins
        call    print
        jmp     exit0

; ---------------------------------------------------------------------
install:
        call    loadcfg
        mov     al,[o_850]              ; 1 = /850, 2 = /GEM
        or      al,al
        jz      .n850
        cmp     al,3                    ; /437: les taules per defecte
        je      .n850
        mov     [cp850],al
        push    cs
        pop     es
        mov     si,c850
        cmp     al,1
        je      .c1
        mov     si,cgem
.c1:    mov     di,comp1
        mov     cx,128
        rep     movsb
.n850:
        cmp     word [resseg],0
        je      .new
        mov     es,[resseg]             ; ja resident: recarrega taula
        mov     si,captab
        mov     di,captab
        mov     cx,TABLEN
        cli
        rep     movsb
        mov     byte [es:pending],0
        sti
        call    pcmd
        call    mcmd
        mov     dx,m_reload
        call    print
        jmp     status
.new:
        cmp     byte [o_pop],1          ; nomes /P:xx porta tecla
        jne     .np2
        mov     al,[newpop]
        mov     [popkey],al
        or      al,al                   ; /P:0 -> sense taula emergent
        jnz     .np2
        mov     byte [wantpop],0
.np2:   cmp     byte [o_prem],0         ; /P- -> sense taula emergent
        je      .np3
        mov     byte [wantpop],0
.np3:   mov     ax,[rsize]
        mov     [ressz],ax
        mov     ax,3509h
        int     21h
        mov     [old9],bx
        mov     [old9+2],es
        cmp     byte [o_high],0
        je      .low
        jmp     highinst
.low:
        mov     dx,int9
        mov     ax,2509h
        int     21h
        mov     es,[2Ch]                ; allibera l'entorn
        mov     ah,49h
        int     21h
        mov     word [2Ch],0
        mov     ax,cs                   ; i posa el nom al bloc (com el
        dec     ax                      ;   DOS 4): sense entorn, MEM
        mov     es,ax                   ;   no el sabria
        mov     word [es:8],'KE'
        mov     word [es:10],'YB'
        mov     word [es:12],'X'
        mov     word [es:14],0
        cmp     byte [wantpop],0
        je      .lp
        push    cs
        pop     es
        call    popload                 ; si falla, el teclat va igual
.lp:    cmp     byte [o_mouse],0
        je      .lm
        push    cs
        pop     es
        call    mload
.lm:
        int     12h                     ; carregat a dalt (LOADHI, LH)?
        mov     cl,6
        shl     ax,cl
        mov     bx,cs
        cmp     bx,ax
        jb      .conv
        mov     dx,m_instup
        call    print
        mov     ax,cs
        call    phex16
        mov     dx,m_paren
        call    print
        jmp     short .sz
.conv:  mov     dx,m_inst
        call    print
.sz:    mov     ax,[rsize]
        add     ax,100h+15
        mov     cl,4
        shr     ax,cl
        push    ax
        shl     ax,cl
        call    pdec
        mov     dx,m_bytes
        call    print
        call    prcp
        push    cs
        pop     es
        call    prpopl
        push    cs
        pop     es
        call    prmouse
        pop     dx
        mov     ax,3100h
        int     21h

highinst:
        int     12h                     ; KB de memoria convencional
        mov     cl,6
        shl     ax,cl
        cmp     [hseg],ax
        jae     .a1
        mov     dx,m_hlow
        jmp     fail
.a1:    mov     ax,[rsize]
        add     ax,15
        mov     cl,4
        shr     ax,cl
        add     ax,[hseg]
        jnc     .a2
        mov     dx,m_hrange
        jmp     fail
.a2:    mov     es,[hseg]
        cmp     byte [o_force],0
        jne     .ramt
        xor     di,di                   ; ha d'estar buida (tot 00 o FF)
        mov     al,[es:0]
        cmp     al,0
        je      .e0
        cmp     al,0FFh
        jne     .notempty
.e0:    mov     cx,[rsize]
        repe    scasb
        je      .ramt
.notempty:
        mov     dx,m_hused
        jmp     fail
.ramt:  xor     di,di                   ; prova de RAM byte a byte
        mov     cx,[rsize]
.t:     mov     al,[es:di]
        mov     ah,al
        not     al
        mov     [es:di],al
        mov     bl,[es:di]
        mov     [es:di],ah
        cmp     bl,al
        jne     .noram
        inc     di
        loop    .t
        jmp     short .copy
.noram: mov     dx,m_hnoram
        jmp     fail
.copy:  mov     ax,[hseg]
        mov     [hiseg],ax
        sub     ax,10h                  ; offsets 100h.. -> hseg:0000..
        mov     es,ax
        mov     si,100h
        mov     di,100h
        mov     cx,[rsize]
        cli
        rep     movsb
        push    ds
        mov     ds,ax
        mov     dx,int9
        mov     ax,2509h
        int     21h
        pop     ds
        sti
        cmp     byte [wantpop],0
        je      .hp
        mov     ax,[hseg]
        sub     ax,10h
        mov     es,ax
        call    popload                 ; just darrere del nucli
.hp:    cmp     byte [o_mouse],0
        je      .hm
        mov     ax,[hseg]
        sub     ax,10h
        mov     es,ax
        call    mload                   ; i despres el ratoli
.hm:
        mov     dx,m_insthi
        call    print
        mov     ax,[hseg]
        call    phex16
        mov     dx,m_paren
        call    print
        mov     ax,[rsize]
        call    pdec
        mov     dx,m_bytes
        call    print
        call    prcp
        mov     ax,[hseg]
        sub     ax,10h
        mov     es,ax
        call    prpopl
        mov     ax,[hseg]
        sub     ax,10h
        mov     es,ax
        call    prmouse
        jmp     exit0

; ---------------------------------------------------------------------
;  Moduls (taula emergent i ratoli): cada un en un bloc a part, del
;  mateix tipus de memoria que el nucli de KEYBX
; ---------------------------------------------------------------------

; Ordres de la taula amb KEYBX ja resident: /P, /P:xx, /P:0, /P-
pcmd:   mov     es,[resseg]
        cmp     byte [o_prem],0
        jne     .free
        cmp     byte [o_pop],0
        je      .r
        cmp     byte [o_pop],1
        jne     .load
        cmp     byte [newpop],0         ; /P:0 = /P-
        je      .free0
        cmp     byte [es:haspop],0
        je      .load
        mov     al,[newpop]             ; ja hi es: nomes canvia la tecla
        mov     [es:popkey],al
.r:     ret
.load:  cmp     byte [es:haspop],0
        jne     .r
        xor     ax,ax
        cmp     byte [o_high],0         ; /P /H:seg: on diu l'usuari
        je      .l2
        mov     ax,[hseg]
        mov     byte [hused],1
.l2:    mov     [mrawseg],ax
        call    popload
        jc      .x
        mov     es,[resseg]
        cmp     byte [o_pop],1
        jne     .k
        mov     al,[newpop]
        mov     [es:popkey],al
        ret
.k:     cmp     byte [es:popkey],0
        jne     .r
        mov     byte [es:popkey],14h    ; Ctrl+Alt+T
        ret
.free0: cmp     byte [es:haspop],0
        je      .r
.free:  call    pfree
        jc      .x
        mov     dx,m_pfreed
        jmp     print
.x:     jmp     exit1

; Ordres de ratoli amb KEYBX ja resident: /M, /M:n, /M-
mcmd:   cmp     byte [o_mrem],0
        je      .a
        mov     es,[resseg]
        call    mfree
        jnc     .fr
        jmp     exit1
.fr:    mov     dx,m_mfreed
        jmp     print
.a:     cmp     byte [o_mouse],0
        je      .r
        mov     es,[resseg]
        mov     ax,[es:mousefar+2]
        or      ax,ax
        jz      .ld
        cmp     byte [o_mlevg],0        ; ja hi es: nomes canvia la corba
        je      .r
        mov     es,ax
        mov     al,[mlev]
        mov     [es:M(alevel)],al
.r:     ret
.ld:    xor     ax,ax
        cmp     byte [o_high],0
        je      .l2
        mov     ax,[hseg]
        cmp     byte [hused],0          ; /H:seg ja fet servir per la taula:
        je      .l2                     ; el ratoli just darrere seu
        mov     ax,[pseg]
        add     ax,PPARA
.l2:    mov     [mrawseg],ax
        mov     es,[resseg]
        call    mload
        jnc     .r
        jmp     exit1

; modalloc: troba lloc per a un modul.  ES = base del nucli,
; [need] paragrafs, [needb] bytes, SI = nom (8 bytes) per a l'MCB,
; [mrawseg] = segment demanat (0 = automatic), [oseg]/[opara] = l'altre
; modul si es a memoria alta sense bloc.
; -> AX = segment, [mtyp] = 0 bloc del DOS / 1 sense bloc.  CF = 1 error.
modalloc:
        mov     [corebase],es
        mov     [aname],si
        int     12h
        mov     cl,6
        shl     ax,cl
        mov     [convtop],ax
        mov     ax,[mrawseg]
        mov     word [mrawseg],0
        or      ax,ax
        jz      .auto
        jmp     .raw
.auto:  mov     es,[corebase]
        cmp     word [es:hiseg],0       ; nucli a /H: darrere seu
        je      .nh
        mov     ax,[es:ressz]
        add     ax,15
        mov     cl,4
        shr     ax,cl
        add     ax,[es:hiseg]
        cmp     word [opara],0
        je      .raw
        mov     bx,ax                   ; salta l'altre modul si toca
        add     bx,[need]
        cmp     bx,[oseg]
        jbe     .raw
        mov     bx,[oseg]
        add     bx,[opara]
        cmp     ax,bx
        jae     .raw
        mov     ax,bx
        jmp     .raw
.nh:    mov     ax,es                   ; nucli baix o a dalt (LOADHI, LH)
        mov     bx,cs                   ; i nosaltres?
        cmp     ax,[convtop]
        sbb     dl,dl
        cmp     bx,[convtop]
        sbb     dh,dh
        cmp     dl,dh
        je      .carve
        or      dl,dl                   ; nucli a dalt i nosaltres a baix:
        jz      .umb                    ; un bloc lliure de dalt
        jmp     .nomem
        ; --- som al mateix tipus de memoria que el nucli: tenim tot el
        ; bloc lliure mes gran (tambe amb LOADHI); ens encongim i el modul
        ; va al capdamunt del que queda lliure just darrere nostre
.carve:
        push    cs
        pop     es
        mov     bx,TRANSPARA
        mov     ah,4Ah
        int     21h
        mov     ax,cs
        dec     ax
        mov     es,ax
        add     ax,[es:3]
        inc     ax
        mov     es,ax
        mov     cl,[es:0]
        cmp     cl,'M'
        je      .c1
        cmp     cl,'Z'
        jne     .nomem
.c1:    cmp     word [es:1],0
        jne     .nomem
        mov     dx,[es:3]
        mov     bx,[need]
        inc     bx
        cmp     dx,bx
        jb      .nomem
        sub     dx,bx
        mov     byte [es:0],'M'
        mov     [es:3],dx
        mov     ax,es
        add     ax,dx
        inc     ax
        mov     es,ax                   ; MCB nou, al capdamunt
        mov     [es:0],cl
        mov     word [es:1],0
        mov     bx,[need]
        mov     [es:3],bx
        inc     ax
        jmp     short .mcb
.umb:   call    find_umb
        jc      .nomem
.mcb:   push    ax
        dec     ax
        mov     es,ax
        mov     ax,[corebase]           ; propietari: el PSP de KEYBX
        mov     [es:1],ax
        mov     si,[aname]
        mov     di,8
        mov     cx,8
        rep     movsb
        pop     ax
        mov     byte [mtyp],0
        clc
        ret
.nomem: mov     dx,m_nomem
        jmp     .err
.raw:   mov     [rseg],ax               ; --- memoria alta sense bloc
        cmp     ax,[convtop]
        jb      .rbad
        mov     bx,ax
        add     bx,[need]
        jc      .rbad
        mov     es,ax
        cmp     byte [o_force],0
        jne     .rt
        xor     di,di                   ; ha d'estar buida (tot 00 o FF)
        mov     al,[es:0]
        cmp     al,0
        je      .e0
        cmp     al,0FFh
        jne     .rused
.e0:    mov     cx,[needb]
        repe    scasb
        jne     .rused
.rt:    xor     di,di
        mov     cx,[needb]
.t:     mov     al,[es:di]
        mov     ah,al
        not     al
        mov     [es:di],al
        mov     bl,[es:di]
        mov     [es:di],ah
        cmp     bl,al
        jne     .rnoram
        inc     di
        loop    .t
        mov     ax,[rseg]
        mov     byte [mtyp],1
        clc
        ret
.rbad:  mov     dx,m_mrbad
        jmp     short .err
.rused: mov     dx,m_hused
        jmp     short .err
.rnoram:
        mov     dx,m_hnoram
.err:   call    print
        stc
        ret

; modfree: ES = segment del modul, AL = tipus, CX = bytes
modfree:
        or      al,al
        jnz     .z
        mov     ah,49h                  ; bloc del DOS
        int     21h
        ret
.z:     xor     di,di                   ; sense bloc: deixa la zona buida
        xor     al,al
        rep     stosb
        ret

; ---- ratoli ---------------------------------------------------------
; mload: ES = base del nucli.  CF = 1 si no s'ha pogut.
mload:
        mov     [corebase],es
        cmp     word [es:mousefar+2],0
        je      .n1
        mov     dx,m_mhave
        jmp     .err
.n1:    mov     ax,3533h                ; ja hi ha un driver de ratoli?
        int     21h
        mov     ax,es
        or      ax,bx
        jz      .n2
        cmp     byte [es:bx],0CFh       ; IRET
        je      .n2
        xor     ax,ax
        int     33h
        cmp     ax,0FFFFh
        jne     .n2
        mov     dx,m_omouse
        jmp     .err
.n2:    mov     es,[corebase]
        mov     word [opara],0
        cmp     byte [es:haspop],0
        je      .n3
        cmp     byte [es:ptype],1
        jne     .n3
        mov     ax,[es:popseg]
        mov     [oseg],ax
        mov     word [opara],PPARA
.n3:    mov     word [need],MPARA
        mov     word [needb],MSIZE
        mov     si,mname
        call    modalloc
        jc      .ret
        mov     [mseg],ax
        mov     es,ax
        mov     si,mstart
        xor     di,di
        mov     cx,MSIZE
        rep     movsb
        mov     al,[mlev]
        mov     [es:M(alevel)],al
        mov     ax,3508h
        int     21h
        mov     dx,es
        mov     es,[mseg]
        mov     [es:M(old08)],bx
        mov     [es:M(old08)+2],dx
        mov     ax,3533h
        int     21h
        mov     dx,es
        mov     es,[mseg]
        mov     [es:M(old33)],bx
        mov     [es:M(old33)+2],dx
        push    ds
        mov     ax,[mseg]
        mov     ds,ax
        mov     dx,M(int33)
        mov     ax,2533h
        int     21h
        mov     dx,M(int08)
        mov     ax,2508h
        int     21h
        pop     ds
        xor     ax,ax
        int     33h
        mov     es,[corebase]
        mov     al,[mtyp]
        mov     bx,[mseg]
        cli
        mov     [es:mtype],al
        mov     word [es:mousefar],M(mbtn)
        mov     [es:mousefar+2],bx
        sti
        clc
.ret:   ret
.err:   call    print
        stc
        ret

; mchk: ES = base del nucli.  CF = 1 si la INT 08h o 33h no son nostres.
mchk:   push    es
        mov     ax,[es:mousefar+2]
        mov     [mseg],ax
        mov     ax,3508h
        int     21h
        mov     ax,es
        cmp     ax,[mseg]
        jne     .b
        mov     ax,3533h
        int     21h
        mov     ax,es
        cmp     ax,[mseg]
        jne     .b
        pop     es
        clc
        ret
.b:     pop     es
        mov     dx,m_mbusy
        call    print
        stc
        ret

; mfree: ES = base del nucli.  CF = 1 si no s'ha pogut.
mfree:
        mov     [corebase],es
        cmp     word [es:mousefar+2],0
        jne     .h
        mov     dx,m_mnone
        call    print
        stc
        ret
.h:     call    mchk
        jc      .r
        xor     ax,ax                   ; treu el cursor de la pantalla
        int     33h
        mov     es,[corebase]
        cli
        mov     word [es:mousefar+2],0  ; la INT 09h ja no hi va
        mov     al,[es:mtype]
        mov     [mtyp],al
        mov     es,[mseg]
        push    ds
        lds     dx,[es:M(old08)]
        mov     ax,2508h
        int     21h
        lds     dx,[es:M(old33)]
        mov     ax,2533h
        int     21h
        pop     ds
        sti
        mov     al,[mtyp]
        mov     cx,MSIZE
        call    modfree
        clc
.r:     ret

; ---- taula emergent -------------------------------------------------
; popload: ES = base del nucli.  CF = 1 si no s'ha pogut.
popload:
        mov     [corebase],es
        cmp     byte [es:haspop],0
        je      .n1
        mov     dx,m_phave
        call    print
        stc
        ret
.n1:    mov     word [opara],0
        cmp     word [es:mousefar+2],0
        je      .n3
        cmp     byte [es:mtype],1
        jne     .n3
        mov     ax,[es:mousefar+2]
        mov     [oseg],ax
        mov     word [opara],MPARA
.n3:    mov     word [need],PPARA
        mov     word [needb],PSIZE
        mov     si,pname
        call    modalloc
        jc      .r
        mov     [pseg],ax
        mov     es,ax
        mov     si,pstart
        xor     di,di
        mov     cx,PSIZE
        rep     movsb
        mov     ax,[corebase]
        mov     [es:P(coreseg)],ax
        mov     ax,3516h
        int     21h
        mov     dx,es
        mov     es,[pseg]
        mov     [es:P(old16)],bx
        mov     [es:P(old16)+2],dx
        push    ds
        mov     ax,[pseg]
        mov     ds,ax
        mov     dx,P(int16)
        mov     ax,2516h
        int     21h
        pop     ds
        mov     es,[corebase]
        mov     al,[mtyp]
        mov     bx,[pseg]
        cli
        mov     [es:ptype],al
        mov     [es:popseg],bx
        mov     byte [es:popflag],0
        mov     byte [es:haspop],1
        sti
        clc
.r:     ret

; pchk: ES = base del nucli.  CF = 1 si la INT 16h no es nostra.
pchk:   push    es
        mov     ax,[es:popseg]
        mov     [pseg],ax
        mov     ax,3516h
        int     21h
        mov     ax,es
        pop     es
        cmp     ax,[pseg]
        jne     .b
        cmp     bx,P(int16)
        jne     .b
        clc
        ret
.b:     mov     dx,m_busy
        call    print
        stc
        ret

; pfree: ES = base del nucli.  CF = 1 si no s'ha pogut.
pfree:
        mov     [corebase],es
        cmp     byte [es:haspop],0
        jne     .h
        mov     dx,m_pnone
        call    print
        stc
        ret
.h:     call    pchk
        jc      .r
        mov     es,[corebase]
        cli
        mov     byte [es:haspop],0      ; la INT 09h ja no l'obre
        mov     byte [es:popflag],0
        mov     al,[es:ptype]
        mov     [mtyp],al
        mov     es,[pseg]
        push    ds
        lds     dx,[es:P(old16)]
        mov     ax,2516h
        int     21h
        pop     ds
        sti
        mov     al,[mtyp]
        mov     cx,PSIZE
        call    modfree
        clc
.r:     ret

; ---- trasllat del nucli: KEYBX /H:seg amb KEYBX ja resident ----------
; Nomes la INT 09h apunta al nucli: es copia, es repunta i s'allibera.
mvcore:
        mov     es,[resseg]
        mov     [corebase],es
        mov     ax,[es:ressz]
        mov     [needb],ax
        add     ax,15
        mov     cl,4
        shr     ax,cl
        mov     [need],ax
        mov     ax,[hseg]               ; no ha de tocar res nostre
        cmp     word [es:hiseg],0
        je      .o1
        mov     bx,[es:hiseg]
        mov     cx,[need]
        call    ovl
        jc      .ov
.o1:    cmp     byte [es:haspop],0
        je      .o2
        cmp     byte [es:ptype],1
        jne     .o2
        mov     bx,[es:popseg]
        mov     cx,PPARA
        call    ovl
        jc      .ov
.o2:    cmp     word [es:mousefar+2],0
        je      .o3
        cmp     byte [es:mtype],1
        jne     .o3
        mov     bx,[es:mousefar+2]
        mov     cx,MPARA
        call    ovl
        jc      .ov
.o3:    mov     [mrawseg],ax            ; comprova segment, zona buida i RAM
        mov     si,mname
        call    modalloc
        jnc     .cp
        jmp     exit1
.ov:    mov     dx,m_ovl
        jmp     fail
.cp:    mov     ax,[hseg]
        sub     ax,10h
        mov     [nbase],ax
        mov     cx,[needb]
        mov     es,ax
        push    ds
        mov     ds,[resseg]
        mov     si,100h
        mov     di,100h
        cli
        rep     movsb
        pop     ds
        mov     ax,[hseg]
        mov     [es:hiseg],ax
        push    ds
        mov     ds,[nbase]
        mov     dx,int9
        mov     ax,2509h
        int     21h
        pop     ds
        mov     es,[nbase]              ; els moduls apunten al nucli nou
        cmp     byte [es:haspop],0
        je      .m1
        mov     ax,[es:popseg]
        mov     bl,[es:ptype]
        push    es
        mov     es,ax
        mov     dx,[nbase]
        mov     [es:P(coreseg)],dx
        pop     es
        or      bl,bl
        jnz     .m1
        call    selfown                 ; el PSP vell desapareix
.m1:    cmp     word [es:mousefar+2],0
        je      .m2
        cmp     byte [es:mtype],0
        jne     .m2
        mov     ax,[es:mousefar+2]
        call    selfown
.m2:    sti
        mov     es,[resseg]             ; allibera el nucli vell
        cmp     word [es:hiseg],0
        jne     .oz
        mov     byte [es:sig],0
        mov     ah,49h
        int     21h
        jmp     short .ok
.oz:    mov     cx,[es:ressz]
        mov     di,100h
        xor     al,al
        rep     stosb
.ok:    mov     ax,[nbase]
        mov     [resseg],ax
        mov     dx,m_moved
        call    print
        mov     ax,[hseg]
        call    phex16
        mov     dx,m_dot
        jmp     print

; AX = segment del bloc: el fa propietari d'ell mateix (conserva ES)
selfown:
        push    es
        mov     bx,ax
        dec     ax
        mov     es,ax
        mov     [es:1],bx
        pop     es
        ret

; [hseg, hseg+need) toca [BX, BX+CX)?  CF = 1 si si.  Conserva AX.
ovl:    push    dx
        mov     dx,ax
        add     dx,[need]
        cmp     dx,bx
        jbe     .no
        add     bx,cx
        cmp     ax,bx
        jae     .no
        pop     dx
        stc
        ret
.no:    pop     dx
        clc
        ret

; Bloc lliure de la cadena per sobre de la memoria convencional -> AX
find_umb:
        push    es
        mov     ah,52h
        int     21h
        mov     ax,[es:bx-2]
.walk:  mov     es,ax
        mov     cl,[es:0]
        cmp     cl,'M'
        je      .ok
        cmp     cl,'Z'
        jne     .fail
.ok:    mov     dx,[es:3]
        cmp     word [es:1],0
        jne     .next
        mov     bx,ax
        inc     bx
        cmp     bx,[convtop]
        jb      .next
        cmp     dx,[need]
        jb      .next
        je      .take
        push    es                      ; parteix el bloc
        mov     ax,bx
        add     ax,[need]
        mov     es,ax
        mov     [es:0],cl
        mov     word [es:1],0
        sub     dx,[need]
        dec     dx
        mov     [es:3],dx
        pop     es
        mov     byte [es:0],'M'
        push    ax
        mov     ax,[need]
        mov     [es:3],ax
        pop     ax
.take:  mov     ax,bx
        pop     es
        clc
        ret
.next:  cmp     cl,'Z'
        je      .fail
        add     ax,dx
        inc     ax
        jmp     short .walk
.fail:  pop     es
        stc
        ret

; Estat del ratoli.  ES = base del nucli.
prmouse:
        mov     ax,[es:mousefar+2]
        or      ax,ax
        jnz     .y
        mov     dx,m_mno
        jmp     print
.y:     push    ax
        mov     dx,m_myes
        call    print
        pop     ax
        push    ax
        mov     es,ax
        mov     dl,[es:M(alevel)]
        add     dl,'0'
        mov     ah,2
        int     21h
        mov     dx,m_mseg
        call    print
        pop     ax
        call    phex16
        mov     dx,m_dot
        jmp     print

; Estat de la taula emergent: sempre el mateix text quan no es pot obrir
; (sense taula, /P:0, joc del GEM o KEYBX /OFF)
; al = haspop, ah = popkey, bl = joc, bh = actiu
prpopl: mov     al,[es:haspop]          ; ES = base del nucli
        mov     ah,[es:popkey]
        mov     bl,[es:cp850]
        mov     bh,1
prpop:  or      al,al
        jz      .off
        or      ah,ah
        jz      .off
        cmp     bl,2
        je      .off
        or      bh,bh
        jz      .off
        push    ax
        mov     dx,m_popk
        call    print
        pop     ax
        mov     al,ah
        call    phex8
        mov     dx,m_dot
        jmp     print
.off:   mov     dx,m_popoff
        jmp     print

; Diu quina codepage s'ha carregat (segons /850)
prcp:   mov     al,[cp850]
prcpn:  mov     bl,al                   ; al = 0, 1, 2
        xor     bh,bh
        shl     bx,1
        mov     dx,[m_cps+bx]
        jmp     print

; Canvia nomes el joc de les tecles mortes del resident (sense .CFG)
setcp:  mov     es,[resseg]
        mov     al,[o_850]
        mov     si,c850
        cmp     al,1
        je      .go
        mov     si,cgem
        cmp     al,2
        je      .go
        mov     si,comp1                ; /437
        xor     al,al
.go:    cli
        mov     [es:cp850],al
        mov     di,comp1
        mov     cx,128
        rep     movsb
        mov     byte [es:pending],0
        sti
        ret

; ---------------------------------------------------------------------
;  Cerca el resident: el vector INT 9 ha d'apuntar a int9 amb signatura
findres:
        mov     word [resseg],0
        mov     ax,3509h
        int     21h
        cmp     bx,int9
        jne     .no
        mov     di,sig
        mov     si,sig
        mov     cx,6
        repe    cmpsb
        jne     .no
        mov     [resseg],es
.no:    push    cs
        pop     es
        ret

; ---------------------------------------------------------------------
;  Analisi de la linia d'ordres
parsecmd:
        mov     si,81h
        mov     cl,[80h]
        xor     ch,ch
        mov     bx,si
        add     bx,cx
        mov     byte [bx],0
.next:  call    skipws
        lodsb
        or      al,al
        jz      .end
        cmp     al,13
        je      .end
        cmp     al,'/'
        je      .sw
        dec     si
        cmp     byte [havename],0
        jne     .bad
        mov     byte [havename],1
        mov     di,fname
        mov     cx,79
.cp:    lodsb
        cmp     al,' '
        jbe     .cpe
        cmp     al,'/'
        je      .cpe
        stosb
        loop    .cp
        inc     si
.cpe:   dec     si
        mov     byte [di],0
        jmp     .next
.sw:    lodsb
        call    upcase
        cmp     al,'?'
        je      .help
        cmp     al,'U'
        je      .u
        cmp     al,'T'
        je      .t
        cmp     al,'A'
        je      .a
        cmp     al,'F'
        je      .f
        cmp     al,'H'
        je      .h
        cmp     al,'P'
        je      .p
        cmp     al,'8'
        je      .c8
        cmp     al,'G'
        je      .cg
        cmp     al,'4'
        je      .c4
        cmp     al,'O'
        je      .o
        cmp     al,'M'
        je      .m
.bad:   mov     dx,m_badarg
        jmp     fail
.help:  mov     byte [o_help],1
        jmp     .next
.u:     mov     byte [o_unin],1
        jmp     .next
.t:     mov     byte [o_test],1
        jmp     .next
.a:     mov     byte [o_learn],1
        jmp     .next
.f:     mov     byte [o_force],1
        jmp     .next
.m:     cmp     byte [si],'-'           ; /M-
        jne     .m1
        inc     si
        mov     byte [o_mrem],1
        jmp     .next
.m1:    mov     byte [o_mouse],1
        cmp     byte [si],':'           ; /M:n
        jne     .m2
        inc     si
        lodsb
        sub     al,'0'
        cmp     al,3
        ja      .bad
        mov     [mlev],al
        mov     byte [o_mlevg],1
.m2:    jmp     .next
.o:     lodsb
        call    upcase
        cmp     al,'N'
        jne     .o2
        mov     byte [o_on],1
        jmp     .next
.o2:    cmp     al,'F'
        jne     .bad
        lodsb
        call    upcase
        cmp     al,'F'
        jne     .bad
        mov     byte [o_off],1
        jmp     .next
.c8:    lodsb                           ; /850
        cmp     al,'5'
        jne     .bad
        lodsb
        cmp     al,'0'
        jne     .bad
        mov     byte [o_850],1
        jmp     .next
.c4:    lodsb                           ; /437
        cmp     al,'3'
        jne     .bad
        lodsb
        cmp     al,'7'
        jne     .bad
        mov     byte [o_850],3
        jmp     .next
.cg:    lodsb                           ; /GEM
        call    upcase
        cmp     al,'E'
        jne     .bad
        lodsb
        call    upcase
        cmp     al,'M'
        jne     .bad
        mov     byte [o_850],2
        jmp     .next
.p:     cmp     byte [si],'-'           ; /P-
        jne     .p1
        inc     si
        mov     byte [o_prem],1
        jmp     .next
.p1:    cmp     byte [si],':'
        je      .p2
        mov     byte [o_pop],2          ; /P sol: carrega la taula
        jmp     .next
.p2:    call    swhex                   ; /P:xx  tecla de la taula
        jc      .bad
        cmp     dx,7Fh
        ja      .bad
        mov     [newpop],dl
        mov     byte [o_pop],1
        jmp     .next
.h:     call    swhex                   ; /H:seg
        jc      .bad
        mov     [hseg],dx
        mov     byte [o_high],1
        jmp     .next
.end:   ret

; ":" + 1..4 xifres hex -> dx. CF=1 si error
swhex:  lodsb
        cmp     al,':'
        jne     .bad
        xor     dx,dx
        xor     cx,cx
.hl:    mov     al,[si]
        call    hexdig
        jc      .he
        inc     si
        push    cx
        mov     cl,4
        shl     dx,cl
        pop     cx
        or      dl,al
        inc     cx
        cmp     cx,4
        jbe     .hl
.bad:   stc
        ret
.he:    jcxz    .bad
        clc
        ret

; ---------------------------------------------------------------------
;  Lectura i analisi del fitxer de configuracio
loadcfg:
        cmp     byte [havename],0
        jne     .open
        mov     si,defname              ; KEYBX.CFG al directori actual
        mov     di,fname
        call    strcpy
        mov     dx,fname
        mov     ax,3D00h
        int     21h
        jnc     .opened
        call    progdir                 ; DOS 3+: directori del programa
        jc      .nofile
.open:  mov     dx,fname
        mov     ax,3D00h
        int     21h
        jnc     .opened
.nofile:
        mov     dx,m_nofile
        call    print
        mov     dx,fname
        call    printz
        call    crlf
        jmp     exit1
.opened:
        mov     bx,ax
        mov     dx,buf
        mov     cx,MAXBUF
        mov     ah,3Fh
        int     21h
        pushf
        push    ax
        mov     ah,3Eh
        int     21h
        pop     ax
        popf
        jnc     .rd
        mov     dx,m_rderr
        jmp     fail
.rd:    mov     bx,ax
        mov     byte [buf+bx],0
        push    cs
        pop     es
        mov     di,captab               ; buida taules
        mov     cx,16+128*5*2
        xor     al,al
        rep     stosb
        mov     si,buf
        mov     word [lineno],0
.line:  inc     word [lineno]
        call    skipws
        mov     al,[si]
        or      al,al
        jz      .eof
        cmp     al,1Ah
        je      .eof
        cmp     al,13
        je      .skip
        cmp     al,10
        je      .skip
        cmp     al,';'
        je      .skip
        call    gettok                  ; codi
        call    hextok
        jc      .ecode
        cmp     cx,2
        ja      .ecode
        or      ax,ax
        jz      .ecode
        cmp     ax,7Fh
        ja      .ecode
        mov     [cscan],al
        call    skipws
        call    gettok                  ; modificadors
        mov     bx,modnames
        call    findkw
        jc      .emods
        mov     [ccls],al
        call    skipws
        cmp     byte [si],'='
        jne     .eeq
        inc     si
        call    skipws
        cmp     byte [si],27h
        je      .lit
        call    gettok                  ; valor
        mov     bx,valnames
        call    findkw
        jc      .hexv
        mov     ah,0FFh                 ; AGUT..DIER = 1..4, NUL = 0
        jmp     short .store
.hexv:  call    hextok
        jc      .eval
        cmp     cx,4
        je      .store
        cmp     cx,2
        jne     .eval
        mov     ah,[cscan]
        jmp     short .store
.lit:   inc     si
        lodsb
        cmp     byte [si],27h
        jne     .eval
        inc     si
        mov     ah,[cscan]
.store: push    ax
        mov     al,10
        mul     byte [cscan]
        mov     bx,ax
        mov     al,[ccls]
        xor     ah,ah
        shl     ax,1
        add     bx,ax
        pop     ax
        mov     [maptab+bx],ax
.skip:  mov     al,[si]                 ; fins al final de linia
        or      al,al
        jz      .eof
        cmp     al,1Ah
        je      .eof
        inc     si
        cmp     al,10
        jne     .skip
        jmp     .line
.ecode: mov     dx,e_code
        jmp     short .err
.emods: mov     dx,e_mods
        jmp     short .err
.eeq:   mov     dx,e_eq
        jmp     short .err
.eval:  mov     dx,e_val
.err:   push    dx
        mov     dx,m_line
        call    print
        mov     ax,[lineno]
        call    pdec
        mov     dx,m_colon
        call    print
        pop     dx
        jmp     fail
.eof:
; calcula quines tecles afecta Bloq Maj
        mov     dl,1
.cl:    mov     al,10
        mul     dl
        mov     bx,ax
        mov     ax,[maptab+bx]          ; sense modificador
        mov     cx,[maptab+bx+2]        ; amb Maj
        or      ax,ax
        jz      .cn
        or      cx,cx
        jz      .cn
        cmp     ah,0FFh
        je      .cn
        cmp     ch,0FFh
        je      .cn
        cmp     al,'a'
        jb      .pairs
        cmp     al,'z'
        ja      .pairs
        mov     ah,al
        sub     ah,20h
        cmp     ah,cl
        je      .setc
.pairs: mov     si,cappairs
.pl:    mov     ah,[si]
        or      ah,ah
        jz      .cn
        cmp     ah,al
        jne     .pn
        cmp     [si+1],cl
        je      .setc
.pn:    add     si,2
        jmp     short .pl
.setc:  mov     bl,dl
        mov     cl,3
        shr     bl,cl
        xor     bh,bh
        mov     cl,dl
        and     cl,7
        mov     al,1
        shl     al,cl
        or      [captab+bx],al
.cn:    inc     dl
        cmp     dl,80h
        jb      .cl
        mov     dx,m_cfgok
        call    print
        mov     dx,fname
        call    printz
        call    crlf
        ret

; Construeix <directori del programa>\KEYBX.CFG a fname (DOS 3+). CF=1 si no
progdir:
        mov     ah,30h
        int     21h
        cmp     al,3
        jb      .no
        push    ds
        mov     ds,[2Ch]
        xor     si,si
.e:     cmp     word [si],0
        je      .f
        inc     si
        jmp     short .e
.f:     add     si,4                    ; 00 00 + comptador
        mov     di,fname
        mov     bx,di                   ; bx = darrer separador + 1
.c:     lodsb
        cmp     al,'\'
        je      .sep
        cmp     al,':'
        jne     .ns
.sep:   lea     bx,[di+1]
.ns:    stosb
        or      al,al
        jnz     .c
        pop     ds
        mov     di,bx
        mov     si,defname
        call    strcpy
        clc
        ret
.no:    stc
        ret

; ---------------------------------------------------------------------
;  Mode prova (/T)
testmode:
        call    hookcap
        mov     dx,m_test
        call    print
        cmp     word [resseg],0
        je      .lp
        mov     dx,m_tres
        call    print
.lp:    call    getev
        jc      .kb
        cmp     al,0E0h
        jne     .n1
        mov     byte [e0flag],1
        jmp     short .lp
.n1:    test    al,80h
        jz      .make
        mov     byte [e0flag],0
        jmp     short .lp
.make:  push    ax
        call    crlf
        mov     dx,m_code
        call    print
        pop     ax
        push    ax
        call    phex8
        cmp     byte [e0flag],0
        je      .n2
        mov     dx,m_e0
        call    print
.n2:    pop     ax
        push    ax
        mov     bl,ah
        call    printmods
        pop     ax
        cmp     al,1                    ; Esc fisica -> surt
        jne     .n3
        cmp     byte [e0flag],0
        je      .quit
.n3:    mov     byte [e0flag],0
.kb:    mov     ah,1
        int     16h
        jz      .lp
        xor     ah,ah
        int     16h
        push    ax
        mov     dx,m_arrow
        call    print
        pop     ax
        push    ax
        call    phex16
        mov     dl,' '
        call    pchar
        pop     ax
        or      al,al
        jz      .lp
        call    putglyph
        jmp     .lp
.quit:  call    unhookcap
        call    flushkb
        call    crlf
        jmp     exit0

; ---------------------------------------------------------------------
;  Mode aprenentatge (/A)
learn:
        cmp     byte [havename],0
        jne     .hn
        mov     si,defname
        mov     di,fname
        call    strcpy
.hn:    push    cs
        pop     es
        mov     di,maptab
        mov     cx,128*5*2
        xor     al,al
        rep     stosb
        call    hookcap
        mov     dx,m_learn
        call    print
        mov     word [lidx],0
.next:  mov     bx,[lidx]
        cmp     bx,NTARGETS
        jb      .prompt
        jmp     .finish
.prompt:
        call    crlf
        mov     ax,bx
        inc     ax
        call    pdec
        mov     dl,'/'
        call    pchar
        mov     ax,NTARGETS
        call    pdec
        mov     dx,m_press
        call    print
        mov     bx,[lidx]
        mov     al,[targets+bx]
        cmp     al,4
        ja      .gl
        mov     bl,al
        xor     bh,bh
        shl     bx,1
        mov     dx,[deadnames+bx]
        call    print
        jmp     short .w
.gl:    call    putglyph
        mov     dx,m_sp3
        call    print
.w:     call    flushkb
        mov     byte [e0flag],0
.wait:  call    flushkb2
        call    getev
        jc      .wait
        cmp     al,0E0h
        jne     .w1
        mov     byte [e0flag],1
        jmp     short .wait
.w1:    test    al,80h
        jz      .w2
        mov     byte [e0flag],0
        jmp     short .wait
.w2:    cmp     byte [e0flag],0
        je      .w3
        mov     byte [e0flag],0
        jmp     short .wait
.w3:    cmp     al,1                    ; Esc: salta
        jne     .w4
        mov     dx,m_skip
        call    print
        inc     word [lidx]
        jmp     .next
.w4:    cmp     al,44h                  ; F10: acaba
        jne     .w5
        jmp     .finish
.w5:    mov     di,modkeys              ; ignora tecles modificadores
        mov     cx,NMODKEYS
        push    cs
        pop     es
        repne   scasb
        je      .wait
        mov     bh,ah
        and     bh,0Ch
        cmp     bh,0Ch
        jne     .w6
        mov     dx,m_ctrlalt
        call    print
        jmp     .next
.w6:    mov     dl,al                   ; dl = codi
        mov     bl,ah
        call    getclass                ; cl = classe
        mov     [ccls],cl
        mov     [cscan],dl
        mov     al,10
        mul     dl
        mov     bx,ax
        mov     al,cl
        xor     ah,ah
        shl     ax,1
        add     bx,ax
        cmp     word [maptab+bx],0
        je      .free
        mov     dx,m_dup
        call    print
        jmp     .next
.free:  mov     si,[lidx]
        mov     al,[targets+si]
        mov     ah,0FFh
        cmp     al,4
        jbe     .st
        mov     ah,[cscan]
.st:    mov     [maptab+bx],ax
        mov     dx,m_got
        call    print
        mov     al,[cscan]
        call    phex8
        mov     dl,' '
        call    pchar
        mov     bl,[ccls]
        xor     bh,bh
        shl     bx,1
        mov     dx,[clsnames+bx]
        call    print
        mov     dx,m_ok
        call    print
        inc     word [lidx]
        jmp     .next
.finish:
        call    unhookcap
        call    flushkb
        call    crlf
        call    savecfg
        jmp     exit0

; Desa maptab a fname
savecfg:
        mov     dx,fname
        xor     cx,cx
        mov     ah,3Ch
        int     21h
        jnc     .ok
        mov     dx,m_wrerr
        jmp     fail
.ok:    mov     [fhandle],ax
        mov     dx,cfghdr
        mov     cx,CFGHDRLEN
        call    fwrite
        mov     byte [cscan],1
.sl:    mov     byte [ccls],0
.cl:    mov     al,10
        mul     byte [cscan]
        mov     bx,ax
        mov     al,[ccls]
        xor     ah,ah
        shl     ax,1
        add     bx,ax
        mov     ax,[maptab+bx]
        or      ax,ax
        jz      .nx
        mov     [cval],ax
        push    cs
        pop     es
        mov     di,linebuf
        mov     al,[cscan]
        call    hex8s
        mov     al,' '
        stosb
        mov     bl,[ccls]
        xor     bh,bh
        shl     bx,1
        mov     si,[clsnames+bx]
        movsw                           ; 2 lletres
        mov     ax,' ='
        stosw
        mov     al,' '
        stosb
        mov     ax,[cval]
        cmp     ah,0FFh
        jne     .nv
        mov     bl,al                   ; nom de tecla morta / NUL
        xor     bh,bh
        shl     bx,1
        mov     si,[valstr+bx]
        call    strcpy0
        jmp     short .eol
.nv:    cmp     ah,[cscan]
        jne     .w4
        call    hex8s
        mov     ax,'  '
        stosw
        jmp     short .cm
.w4:    xchg    al,ah
        call    hex8s
        xchg    al,ah
        call    hex8s
.cm:    mov     al,[cval]
        cmp     al,20h
        jb      .eol
        mov     si,s_cmt
        call    strcpy0
        mov     al,[cval]
        stosb
.eol:   mov     ax,0A0Dh
        stosw
        mov     cx,di
        mov     dx,linebuf
        sub     cx,dx
        call    fwrite
.nx:    inc     byte [ccls]
        cmp     byte [ccls],5
        jb      .cl
        inc     byte [cscan]
        cmp     byte [cscan],80h
        jb      .sl
        mov     bx,[fhandle]
        mov     ah,3Eh
        int     21h
        mov     dx,m_saved
        call    print
        mov     dx,fname
        call    printz
        call    crlf
        ret

fwrite: mov     bx,[fhandle]
        mov     ah,40h
        int     21h
        jc      .e
        cmp     ax,cx
        jne     .e
        ret
.e:     mov     dx,m_wrerr
        jmp     fail

; ---------------------------------------------------------------------
;  Captura de codis per a /T i /A
cap9:   push    ax
        push    bx
        push    ds
        in      al,60h
        mov     bx,40h
        mov     ds,bx
        mov     ah,[17h]
        mov     bx,cs
        mov     ds,bx
        mov     bl,[rhead]
        xor     bh,bh
        mov     [rbuf+bx],ax
        add     bl,2
        and     bl,3Fh
        cmp     bl,[rtail]
        je      .full
        mov     [rhead],bl
.full:  pop     ds
        pop     bx
        pop     ax
        jmp     far [cs:capold]

int23:  iret                            ; ignora Ctrl+C durant /T i /A

hookcap:
        mov     dx,int23
        mov     ax,2523h
        int     21h
        mov     ax,3509h
        int     21h
        mov     [capold],bx
        mov     [capold+2],es
        mov     byte [rhead],0
        mov     byte [rtail],0
        mov     dx,cap9
        mov     ax,2509h
        int     21h
        push    cs
        pop     es
        ret

unhookcap:
        push    ds
        lds     dx,[capold]
        mov     ax,2509h
        int     21h
        pop     ds
        ret

; -> CF=1 si buit; si no al=codi ah=indicadors
getev:  cli
        mov     bl,[rtail]
        cmp     bl,[rhead]
        je      .none
        xor     bh,bh
        mov     ax,[rbuf+bx]
        add     bl,2
        and     bl,3Fh
        mov     [rtail],bl
        sti
        clc
        ret
.none:  sti
        stc
        ret

flushkb:                                ; buida buffer BIOS i cua
        cli
        mov     al,[rhead]
        mov     [rtail],al
        sti
flushkb2:                               ; nomes buffer BIOS
        mov     ah,1
        int     16h
        jz      .r
        xor     ah,ah
        int     16h
        jmp     short flushkb2
.r:     ret

; bl = indicadors -> imprimeix modificadors
printmods:
        test    bl,03h
        jz      .a
        mov     dx,m_mshift
        call    print
.a:     test    bl,04h
        jz      .b
        mov     dx,m_mctrl
        call    print
.b:     test    bl,08h
        jz      .c
        mov     dx,m_malt
        call    print
.c:     test    bl,40h
        jz      .d
        mov     dx,m_mcaps
        call    print
.d:     ret

; ---------------------------------------------------------------------
;  Utilitats
skipws: cmp     byte [si],' '
        je      .s
        cmp     byte [si],9
        jne     .r
.s:     inc     si
        jmp     short skipws
.r:     ret

; copia un mot (majuscules) a tok, cx = llargada
gettok: mov     di,tok
        xor     cx,cx
.l:     mov     al,[si]
        cmp     al,' '
        jbe     .e
        cmp     al,';'
        je      .e
        cmp     al,'='
        je      .e
        cmp     al,1Ah
        je      .e
        inc     si
        call    upcase
        cmp     cx,15
        jae     .l
        mov     [di],al
        inc     di
        inc     cx
        jmp     short .l
.e:     mov     byte [di],0
        ret

; tok hexadecimal -> ax, CF=1 si error (cx = llargada)
hextok: jcxz    .bad
        cmp     cx,4
        ja      .bad
        push    si
        push    cx
        mov     si,tok
        xor     dx,dx
.l:     lodsb
        or      al,al
        jz      .e
        call    hexdig
        jc      .b2
        mov     cl,4
        shl     dx,cl
        or      dl,al
        jmp     short .l
.e:     mov     ax,dx
        pop     cx
        pop     si
        clc
        ret
.b2:    pop     cx
        pop     si
.bad:   stc
        ret

; al -> valor 0..15, CF=1 si no es hex
hexdig: call    upcase
        cmp     al,'0'
        jb      .no
        cmp     al,'9'
        jbe     .d
        cmp     al,'A'
        jb      .no
        cmp     al,'F'
        ja      .no
        sub     al,'A'-10
        clc
        ret
.d:     sub     al,'0'
        clc
        ret
.no:    stc
        ret

upcase: cmp     al,'a'
        jb      .r
        cmp     al,'z'
        ja      .r
        sub     al,20h
.r:     ret

; bx -> llista de paraules (ASCIIZ, valor), acaba en 0. CF=1 si no hi es
findkw: push    si
.n:     cmp     byte [bx],0
        je      .no
        mov     si,tok
        mov     di,bx
.c:     mov     al,[si]
        cmp     al,[di]
        jne     .sk
        inc     si
        inc     di
        or      al,al
        jnz     .c
        mov     al,[di]                 ; valor despres del 0
        pop     si
        clc
        ret
.sk:    cmp     byte [bx],0             ; salta paraula + 0 + valor
        je      .sk2
        inc     bx
        jmp     short .sk
.sk2:   add     bx,2
        jmp     short .n
.no:    pop     si
        stc
        ret

strcpy: lodsb                           ; amb el 0
        stosb
        or      al,al
        jnz     strcpy
        ret
strcpy0:                                ; sense el 0
        lodsb
        or      al,al
        jz      .r
        stosb
        jmp     short strcpy0
.r:     ret

hex8s:  push    ax                      ; al -> 2 hex a es:di
        push    cx
        mov     ah,al
        mov     cl,4
        shr     al,cl
        call    .d
        mov     al,ah
        and     al,0Fh
        call    .d
        pop     cx
        pop     ax
        ret
.d:     add     al,'0'
        cmp     al,'9'
        jbe     .s
        add     al,7
.s:     stosb
        ret

print:  mov     ah,9
        int     21h
        ret

printz: mov     si,dx                   ; ASCIIZ
.l:     lodsb
        or      al,al
        jz      .r
        mov     dl,al
        call    pchar
        jmp     short .l
.r:     ret

pchar:  push    ax
        mov     ah,2
        int     21h
        pop     ax
        ret

crlf:   mov     dx,m_crlf
        jmp     print

phex16: push    ax
        mov     al,ah
        call    phex8
        pop     ax
phex8:  push    ax
        push    cx
        push    di
        push    cs
        pop     es
        mov     di,hexout
        call    hex8s
        mov     dx,hexout
        call    print
        pop     di
        pop     cx
        pop     ax
        ret

pdec:   push    ax                      ; ax -> decimal
        push    bx
        push    cx
        push    dx
        mov     bx,10
        xor     cx,cx
.d:     xor     dx,dx
        div     bx
        push    dx
        inc     cx
        or      ax,ax
        jnz     .d
.p:     pop     dx
        add     dl,'0'
        call    pchar
        loop    .p
        pop     dx
        pop     cx
        pop     bx
        pop     ax
        ret

; al = caracter -> el dibuixa tal qual (sense interpretar controls)
putglyph:
        push    ax
        push    bx
        push    cx
        push    dx
        push    ax
        mov     ah,0Fh
        int     10h                     ; bh = pagina
        pop     ax
        mov     ah,0Ah
        mov     cx,1
        int     10h
        mov     ah,3
        int     10h
        inc     dl
        mov     ah,2
        int     10h
        pop     dx
        pop     cx
        pop     bx
        pop     ax
        ret

; ---------------------------------------------------------------------
;  Dades de la part transitoria
resseg      dw  0
rsize       dw  RESSIZE
hseg        dw  0
lineno      dw  0
lidx        dw  0
fhandle     dw  0
cval        dw  0
capold      dd  0
cscan       db  0
ccls        db  0
e0flag      db  0
rhead       db  0
rtail       db  0
havename    db  0
o_help      db  0
o_unin      db  0
o_test      db  0
o_learn     db  0
o_force     db  0
o_high      db  0
o_on        db  0
o_off       db  0
o_pop       db  0
o_850       db  0
newpop      db  0
o_mouse     db  0
o_prem      db  0
wantpop     db  1
hused       db  0
pseg        dw  0
need        dw  0
needb       dw  0
oseg        dw  0
opara       dw  0
aname       dw  0
rseg        dw  0
nbase       dw  0
pname       db  'KEYBXP',0,0
o_mrem      db  0
o_mlevg     db  0
mlev        db  2               ; corba per defecte
mtyp        db  0
mseg        dw  0
mrawseg     dw  0
corebase    dw  0
convtop     dw  0
mname       db  'KEYBXM',0,0
hexout      db  0,0,'$'
rbuf        times 32 dw 0
tok         times 16 db 0
linebuf     times 48 db 0
fname       times 80 db 0
defname     db  'KEYBX.CFG',0

; tecles mortes per a la codepage 850 (4 x 32 bytes)
c850:
.1      db 'a',0A0h,'e',82h,'i',0A1h,'o',0A2h,'u',0A3h,'y',0ECh
        db 'A',0B5h,'E',90h,'I',0D6h,'O',0E0h,'U',0E9h,'Y',0EDh,' ',27h,0
        times 32-($-.1) db 0
.2      db 'a',85h,'e',8Ah,'i',8Dh,'o',95h,'u',97h
        db 'A',0B7h,'E',0D4h,'I',0DEh,'O',0E3h,'U',0EBh,' ',60h,0
        times 32-($-.2) db 0
.3      db 'a',83h,'e',88h,'i',8Ch,'o',93h,'u',96h
        db 'A',0B6h,'E',0D2h,'I',0D7h,'O',0E2h,'U',0EAh,' ',5Eh,0
        times 32-($-.3) db 0
.4      db 'a',84h,'e',89h,'i',8Bh,'o',94h,'u',81h,'y',98h
        db 'A',8Eh,'E',0D3h,'I',0D8h,'O',99h,'U',9Ah,' ',22h,0
        times 32-($-.4) db 0

; tecles mortes per al joc de caracters del GEM (4 x 32 bytes)
cgem:
.1      db 'a',0A0h,'e',82h,'i',0A1h,'o',0A2h,'u',0A3h
        db 'A',0C7h,'E',90h,'I',0CDh,'O',0D1h,'U',0D6h,' ',27h,0
        times 32-($-.1) db 0
.2      db 'a',85h,'e',8Ah,'i',8Dh,'o',95h,'u',97h
        db 'A',0B6h,'E',0C9h,'I',0CCh,'O',0D0h,'U',0D5h,' ',60h,0
        times 32-($-.2) db 0
.3      db 'a',83h,'e',88h,'i',8Ch,'o',93h,'u',96h
        db 'A',0C8h,'E',0CAh,'I',0CEh,'O',0D2h,'U',0D7h,' ',5Eh,0
        times 32-($-.3) db 0
.4      db 'a',84h,'e',89h,'i',8Bh,'o',94h,'u',81h,'y',98h
        db 'A',8Eh,'E',0CBh,'I',0CFh,'O',99h,'U',9Ah,'Y',0D8h,' ',22h,0
        times 32-($-.4) db 0

modnames    db  'N',0,0, 'S',0,1, 'C',0,2, 'A',0,3, 'SA',0,4, 'AS',0,4, 0
valnames    db  'NUL',0,0, 'AGUT',0,1, 'GREU',0,2, 'CIRC',0,3, 'DIER',0,4, 0
valstr      dw  s_nul,s_agut,s_greu,s_circ,s_dier
s_nul       db  'NUL',0
s_agut      db  'AGUT',0
s_greu      db  'GREU',0
s_circ      db  'CIRC',0
s_dier      db  'DIER',0
s_cmt       db  '   ; ',0
clsnames    dw  c_n,c_s,c_c,c_a,c_sa
c_n         db  'N $'
c_s         db  'S $'
c_c         db  'C $'
c_a         db  'A $'
c_sa        db  'SA$'

cappairs    db  0A4h,0A5h, 87h,80h, 81h,9Ah, 84h,8Eh, 94h,99h
            db  82h,90h, 86h,8Fh, 91h,92h, 0

modkeys     db  2Ah,36h,1Dh,38h,3Ah,45h,46h
NMODKEYS    equ $-modkeys

; caracters que demana el mode aprenentatge (1..4 = tecles mortes)
targets     db  1,2,3,4
            db  '1234567890'
            db  '!"#$%&/()=?', 27h, 0ADh, 0A8h
            db  '@|\~', 0AAh, '[]{}+*-_.:,;<>'
            db  0A7h, 0A6h, 0FAh, 0A4h, 0A5h, 87h, 80h
NTARGETS    equ $-targets

deadnames   dw  0,d_1,d_2,d_3,d_4
d_1         db  `accent agut '  (tecla morta)$`
d_2         db  `accent greu \x60  (tecla morta)$`
d_3         db  `circumflex  ^  (tecla morta)$`
d_4         db  `di\x8Aresi     "  (tecla morta)$`

cfghdr      db  `; KEYBX.CFG - generat amb KEYBX /A\r\n`
            db  `; codi mods = valor   (mods: N S C A SA)\r\n`
            db  `; valor: 2 hex = car\x85cter, 4 hex = paraula, 'c',\r\n`
            db  `;        AGUT GREU CIRC DIER (tecles mortes), NUL\r\n`
CFGHDRLEN   equ $-cfghdr

m_banner    db  `KEYBX 2.4 - remapejador de teclat i ratol\xA1 per a DOS (8086)\r\n$`
m_help      db  `\r\n`
            db  `KEYBX [fitxer.cfg] [/437|/850|/GEM] [/P:xx] [/M[:n]] [/H:seg [/F]]\r\n`
            db  `KEYBX /A [fitxer.cfg]   aprenentatge: genera el .CFG\r\n`
            db  `KEYBX /T                prova: codis i car\x85cters\r\n`
            db  `KEYBX /ON | /OFF        activa / desactiva\r\n`
            db  `KEYBX /U                desinstal\xFAla\r\n`
            db  `/850    tecles mortes per a la codepage 850 (maj\xA3scules accentuades)\r\n`
            db  `/GEM    tecles mortes per al joc de car\x85cters del GEM\r\n`
            db  `        (/437 /850 /GEM sols: canvien el joc del resident)\r\n`
            db  `/P:xx   taula emergent amb Ctrl+Alt+codi xx (14 = T; 0 = sense taula)\r\n`
            db  `Amb KEYBX ja resident:\r\n`
            db  `KEYBX /P[:xx] | /P-     carrega / treu la taula emergent\r\n`
            db  `KEYBX /M[:n] | /M-      carrega / treu el ratol\xA1\r\n`
            db  `KEYBX /H:seg            mou KEYBX a RAM alta (els m\x95duls no es mouen)\r\n`
            db  `/M[:n]  driver de ratol\xA1 del PC1512 (INT 33h), acceleraci\xA2 n = 0-3\r\n`
            db  `        (per defecte 2; amb el ratol\xA1 carregat, /M:n la canvia)\r\n`
            db  `/H:seg  copia el resident a RAM alta (p.ex. /H:D000)\r\n`
            db  `/F      no comprova que la zona alta sigui buida\r\n$`
m_isres     db  `KEYBX \x82s resident: $`
m_on        db  `actiu.\r\n$`
m_off       db  `inactiu.\r\n$`
m_popk      db  `Taula de car\x85cters emergent: Ctrl+Alt+codi $`
m_dot       db  `.\r\n$`
m_phave     db  `La taula de car\x85cters ja \x82s carregada.\r\n$`
m_pnone     db  `La taula de car\x85cters no \x82s carregada.\r\n$`
m_pfreed    db  `Taula de car\x85cters descarregada.\r\n$`
m_moved     db  `KEYBX traslladat a mem\x95ria alta, segment $`
m_ovl       db  `/H: la zona toca una part de KEYBX que ja \x82s a dalt.\r\n$`
m_popoff    db  `Taula de car\x85cters emergent: desactivada.\r\n$`
m_cps       dw  m_cp437,m_cp850,m_cpgem
m_cpgem     db  `Joc de car\x85cters: GEM.\r\n$`
m_cp437     db  `Codepage: 437.\r\n$`
m_cp850     db  `Codepage: 850.\r\n$`
m_myes      db  `Ratol\xA1: s\xA1 (INT 33h), acceleraci\xA2 $`
m_mseg      db  `, segment $`
m_mhave     db  `El ratol\xA1 ja \x82s carregat.\r\n$`
m_mnone     db  `El ratol\xA1 no \x82s carregat.\r\n$`
m_mfreed    db  `Ratol\xA1 descarregat.\r\n$`
m_nomem     db  `No hi ha mem\x95ria lliure per al m\x95dul (taula o ratol\xA1).\r\n$`
m_mrbad     db  `/H: segment no v\x85lid (ha de ser per sobre de la mem\x95ria convencional).\r\n$`
m_mno       db  `Ratol\xA1: no.\r\n$`
m_omouse    db  `/M: ja hi ha un altre driver de ratol\xA1 instal\xFAlat.\r\n$`
m_mbusy     db  `Un altre programa ha capturat la INT 08h o 33h despr\x82s de KEYBX.\r\n$`
m_athigh    db  `Mem\x95ria alta, segment $`
m_nores     db  `KEYBX no \x82s resident (o no \x82s l'\x9Altim a la INT 9).\r\n$`
m_busy      db  `Un altre programa ha capturat la INT 16h despr\x82s de KEYBX.\r\n$`
m_unins     db  `KEYBX desinstal\xFAlat.\r\n$`
m_reload    db  `Taula del resident actualitzada.\r\n$`
m_inst      db  `Instal\xFAlat a mem\x95ria convencional ($`
m_insthi    db  `Instal\xFAlat a mem\x95ria alta, segment $`
m_instup    db  `Instal\xFAlat a mem\x95ria superior, segment $`
m_paren     db  ` ($`
m_bytes     db  ` bytes)\r\n$`
m_hlow      db  `/H: el segment \x82s dins la mem\x95ria convencional.\r\n$`
m_hrange    db  `/H: el segment \x82s massa alt.\r\n$`
m_hused     db  `/H: la zona no sembla buida (fes servir /F per for\x87ar).\r\n$`
m_hnoram    db  `/H: no hi ha RAM en aquest segment.\r\n$`
m_badarg    db  `Par\x85metre incorrecte. KEYBX /? per a l'ajuda.\r\n$`
m_nofile    db  `No es pot obrir: $`
m_rderr     db  `Error de lectura.\r\n$`
m_wrerr     db  `Error d'escriptura.\r\n$`
m_cfgok     db  `Configuraci\xA2 llegida: $`
m_line      db  `Error a la l\xA1nia $`
m_colon     db  `: $`
e_code      db  `codi de tecla incorrecte (01-7F).\r\n$`
e_mods      db  `modificador incorrecte (N S C A SA).\r\n$`
e_eq        db  `falta '='.\r\n$`
e_val       db  `valor incorrecte.\r\n$`
m_test      db  `\r\nMode prova. Prem tecles; Esc surt.\r\n`
            db  `Codi = el que rep el PC; -> = paraula del buffer i car\x85cter.\r\n$`
m_tres      db  `(KEYBX resident: els car\x85cters ja passen per la taula)\r\n$`
m_code      db  `Codi $`
m_e0        db  ` (E0)$`
m_arrow     db  `  -> $`
m_mshift    db  ` Maj$`
m_mctrl     db  ` Ctrl$`
m_malt      db  ` Alt$`
m_mcaps     db  ` BloqMaj$`
m_learn     db  `\r\nMode aprenentatge. Per a cada s\xA1mbol, prem la tecla o la\r\n`
            db  `combinaci\xA2 del TEU teclat que el mostra (Maj, Alt/Opci\xA2...).\r\n`
            db  `Esc = salta el s\xA1mbol, F10 = acaba i desa.\r\n$`
m_press     db  `  Prem: $`
m_sp3       db  `   $`
m_skip      db  `  (saltat)$`
m_ctrlalt   db  `  Ctrl+Alt no es pot fer servir; torna-ho a provar.$`
m_dup       db  `  Aquesta combinaci\xA2 ja est\x85 assignada; prova'n una altra.$`
m_got       db  `  -> $`
m_ok        db  ` OK$`
m_saved     db  `Desat a $`
m_crlf      db  `\r\n$`

buf:                                    ; buffer de lectura del .CFG
stktop      equ buf+MAXBUF+400h         ; pila al final del buffer
TRANSPARA   equ (stktop-$$+100h+15)/16  ; paragrafs que necessita la part transitoria
