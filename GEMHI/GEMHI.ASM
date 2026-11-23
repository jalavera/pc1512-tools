; =====================================================================
;  GEMHI.ASM - Engega el GEM i li posa a la memoria alta el que carrega
;              en arrencar (AMSTRAD.SYS, accessoris, GEM.RSC...)
;              MS-DOS 3.20 o posterior, Amstrad PC1512.   Versio 0.18
;
;  Muntatge:   nasm -f bin GEMHI.ASM -o GEMHI.COM
;  Us:         GEMHI programa [parametres]      p. ex.  GEMHI GEMVDI
;
;  GEMHI executa el programa (GEMVDI, que engega GEM.EXE) i, mentre el
;  GEM arrenca, respon les peticions de memoria al DOS (INT 21h, 48h)
;  amb blocs de la memoria alta: tapa un moment els blocs lliures de la
;  memoria convencional i fa la peticio al DOS. Quan el GEM executa la
;  primera aplicacio (l'escriptori: el segon EXEC des que s'ha engegat
;  el programa), ho deixa de fer: les aplicacions reben memoria
;  convencional com sempre. Els blocs continuen essent del GEM (el DOS
;  els allibera quan se'n surt).
;  Cal una zona alta enllacada a la cadena de blocs del DOS (LOADHI amb
;  /H). Si no n'hi ha, o no hi cap, la peticio va a la convencional.
;  El programa mateix (GEMVDI) tambe es carrega a dalt: EXEC 4B01h
;  (carrega sense executar) amb la convencional tapada, es destapa i
;  se li passa el control. Si no hi cap, EXEC normal a baix.
;  La ruta del programa es passa completa (C:\GEMSYS\GEMVDI.EXE) perque
;  MEM en trobi la carpeta.
;  GEMHI mateix tambe passa a dalt: es copia a un bloc de la zona alta,
;  i quan GEMVDI s'ha carregat, li fa de pare COMMAND.COM (amb la
;  mateixa adreca de tornada que GEMHI) i allibera els seus blocs de baix.
;  Quan GEMVDI acaba (INT 21h, 4Ch), el ganxo es treu sol i el DOS
;  allibera el bloc de dalt (es de GEMVDI).
;  Aplicacions (0.4): quan el GEM engega un .APP (l'EXEC el fa el GEM
;  mateix: PSP actual = el del GEM), GEMHI prova de carregar-lo a dalt
;  (4B01h amb la convencional tapada); si no hi cap, EXEC normal a baix,
;  sense dir res. La memoria que l'aplicacio demani despres (48h) va a
;  la convencional, com sempre. Els programes de DOS (.COM, .EXE) i el
;  que s'executi des d'una aplicacio o des del Shell de DOS no es toquen.
;  0.14: sense marca, el programa d'una aplicacio va a baix (EXEC
;  normal); nomes amb la marca de programa 'A' es prova a dalt. Les
;  proves (PROVA1-5) han mostrat que el GEM 2.0 es penja quan torna d'una
;  aplicacio que ha estat a dalt: GEMHI hi torna be (4 xiulets), pero
;  despres el GEM ja no continua. Els accessoris i l'escriptori
;  (DESKTOP.APP), sense marca, a dalt.
;  Marca (0.5, 0.6): 4 bytes a l'offset 1Ch de la capcalera MZ del .APP:
;  'G','H', programa, dades. Programa 'B': a la convencional (si no, a
;  dalt si hi cap). Dades 'A' (0.6): el que l'aplicacio demani amb 48h
;  va primer a dalt i, si no hi cap, a baix (si no, a baix). La posa i
;  la treu GEMGO.
;  Marca llarga (0.8): si a 1Ch no hi ha 'GH', es busca 'GHMK', programa,
;  dades a la resta de la capcalera (fins a 1 KB), en llocs alineats a 8.
;  Registre (0.9): mentre corre un .APP engegat pel GEM, GEMHI en compta
;  la memoria de dades (48h/49h: punta i nombre de blocs) i si demana fer
;  creixer un bloc (4Ah amb mes paragrafs: el del programa o un de
;  dades). Quan acaba (4Ch), ho desa a GEMHI.LOG, a la mateixa carpeta
;  que GEMHI.COM (0.10; si no se sap, a l'arrel de la unitat del GEM): registres de 24 bytes, un per aplicacio, amb el maxim de totes
;  les vegades. GEMGO ho llegeix.
;  Accessoris (0.7): mentre el GEM arrenca, quan obre un .ACC (3Dh) que
;  porta la marca amb programa 'B', la peticio de memoria seguent prou
;  gran per a la seva imatge va a la convencional.
;  En acabar, diu quants blocs ha posat a dalt.
; =====================================================================

        cpu     8086
        org     100h

MAXBL   equ     64              ; blocs convencionals tapats a la vegada
MAXREG  equ     40              ; peticions servides a dalt (per l'informe)
MAXPAR  equ     1000h           ; peticions de mes de 64 KB: a baix

start:  jmp     inici

; ---------------------------------------------------------------------
;  Part resident (mentre dura el programa): el ganxo de l'INT 21h
; ---------------------------------------------------------------------
old21   dd      0
fase    db      0               ; 1: arrencada del GEM (a dalt)
nexec   db      0               ; EXEC vistos des d'engegar el programa
firstmcb dw     0
convtop dw      0               ; segment del final de la convencional
nreg    dw      0
totpar  dw      0
reg_seg times MAXREG dw 0
reg_par times MAXREG dw 0
bl_seg  times MAXBL+1 dw 0
sv_bx   dw      0
lowpsp  dw      0               ; PSP de GEMHI (a baix)
hiseg   dw      0               ; GEMHI copiat a dalt: el seu segment
gvpsp   dw      0               ; PSP de GEMVDI carregat a dalt
gempsp  dw      0               ; PSP del GEM (el que fa l'EXEC de les aplicacions)
app_dh  db      0               ; 1: l'aplicacio en marxa vol les dades a dalt
acc_lo  dw      0               ; accessori marcat 'a baix': paragrafs de la imatge
apps    db      0               ; 1: aplicacions a dalt; 2: n'hi ha una en marxa
app_sp  dw      0
app_ss  dw      0
apb     times 22 db 0           ; copia del bloc de parametres de l'EXEC
gem_ret dw      0, 0, 0         ; IP CS FLAGS del GEM a l'EXEC de l'aplicacio
gem_sp  dw      0               ; la pila del GEM a l'EXEC de l'aplicacio
gem_ss  dw      0
APPSTK  equ     160
DOSFRM  equ     48
dosfrm  times DOSFRM db 0       ; marc de retorn per al DOS (PSP:2Eh del GEM)
app_stk times APPSTK db 0       ; pila propia per carregar i tornar
trk     db      0               ; 1: es compta l'aplicacio en marxa
cpsp    dw      0               ; PSP actual (esfill)
st_fl   db      0               ; 1: el programa vol creixer; 2: un bloc de dades
st_cur  dw      0               ; dades ara (paragrafs)
st_pk   dw      0               ; punta de dades
st_nb   dw      0               ; blocs de dades demanats
lognm   times 13 db 0           ; nom de l'aplicacio
logpath db      'C:\GEMHI.LOG', 0
        times 80 db 0
rec     times 24 db 0           ; registre: nom(13) fl prog punta blocs vegades -
rbuf    times 24 db 0

int21:  cmp     ah, 48h
        je      .alloc
        cmp     ah, 49h
        je      .free
        cmp     ah, 4Ah
        je      .resz
        cmp     ah, 3Dh
        je      .open
        cmp     ah, 4Ch
        je      .term
        cmp     ah, 4Bh
        jne     .chain
        cmp     al, 1                   ; EXEC (4B00h, 4B01h)
        ja      .chain
        cmp     byte [cs:fase], 0
        je      .app
        inc     byte [cs:nexec]         ; 1r: GEMVDI -> GEM.EXE
        cmp     byte [cs:nexec], 2      ; 2n: el GEM engega l'escriptori
        jb      .chain
        mov     byte [cs:fase], 0
        push    ax                      ; qui fa l'EXEC: el GEM
        push    bx
        mov     ah, 51h
        pushf
        call    far [cs:old21]
        mov     [cs:gempsp], bx
        pop     bx
        pop     ax
        mov     byte [cs:apps], 1
        call    dbg_on                  ; (0.16) /D
.app:   cmp     al, 0                   ; 4B00h d'un .APP, des del GEM
        jne     .chain
        cmp     byte [cs:apps], 1
        jne     .chain
        push    ax
        push    bx
        mov     ah, 51h
        pushf
        call    far [cs:old21]
        cmp     bx, [cs:gempsp]
        pop     bx
        pop     ax
        jne     .chain
        mov     byte [cs:app_dh], 0
        mov     byte [cs:trk], 0
        call    esapp
        jne     .chain
        call    iniapp
        call    marcat                  ; (0.14) el programa d'una aplicacio
        call    dbgmk                   ; (0.16) per a /D: marca i motiu
        cmp     word [cs:hdr+1Ch], 'GH' ;   nomes va a dalt si la marca ho
        jne     .desk                   ;   demana ('A')
        cmp     byte [cs:hdr+1Eh], 'A'
        mov     byte [cs:dbg_why], 1
        je      .alta
        mov     byte [cs:dbg_why], 3
        cmp     byte [cs:hdr+1Eh], 'B'
        je      .chain
.desk:  mov     byte [cs:dbg_why], 0
        call    esdesk                  ; l'escriptori, sense marca: a dalt
        jne     .chain
        mov     byte [cs:dbg_why], 2
.alta:  jmp     app_exec
.chain: jmp     far [cs:old21]

.alloc: cmp     byte [cs:fase], 0
        je      .dades
        cmp     bx, MAXPAR              ; consultes (FFFFh) i blocs grans:
        jae     .chain                  ;   com sempre
        or      bx, bx
        jz      .chain
        cmp     word [cs:acc_lo], 0     ; l'accessori marcat 'a baix'
        je      .ah
        cmp     bx, [cs:acc_lo]
        jb      .ah
        mov     word [cs:acc_lo], 0
        jmp     .chain
.ah:    mov     [cs:sv_bx], bx
        call    tapa
        mov     ah, 48h
        mov     bx, [cs:sv_bx]
        pushf
        call    far [cs:old21]
        pushf
        call    destapa
        popf
        jc      .baix
        cmp     ax, [cs:convtop]        ; ha anat a dalt?
        jb      .ok
        push    bx
        mov     bx, [cs:nreg]           ; per a l'informe
        cmp     bx, MAXREG
        jae     .r1
        shl     bx, 1
        mov     [cs:reg_seg+bx], ax
        push    ax
        mov     ax, [cs:sv_bx]
        mov     [cs:reg_par+bx], ax
        pop     ax
.r1:    inc     word [cs:nreg]
        push    ax
        mov     ax, [cs:sv_bx]
        add     [cs:totpar], ax
        pop     ax
        pop     bx
.ok:    clc
        retf    2                       ; CF=0, AX = segment
.baix:  mov     bx, [cs:sv_bx]          ; no hi cap a dalt: a baix
        mov     ah, 48h
        jmp     .chain

; dades d'una aplicacio amb la marca 'dades a dalt': si qui demana es
; fill directe del GEM, primer a dalt (sense limit de mida; les consultes
; FFFFh, com sempre), i si no hi cap, a baix
.dades: cmp     byte [cs:trk], 0
        je      .chain
        cmp     bx, 0FFFFh
        je      .chain
        or      bx, bx
        jz      .chain
        call    esfill
        jne     .chain
        mov     [cs:sv_bx], bx
        cmp     byte [cs:app_dh], 0
        je      .dlo
        call    tapa
        mov     ah, 48h
        pushf
        call    far [cs:old21]
        pushf
        call    destapa
        popf
        jnc     .dok
.dlo:   mov     bx, [cs:sv_bx]
        mov     ah, 48h
        pushf
        call    far [cs:old21]
        jc      .dno
.dok:   push    ax                      ; registre: dades i blocs
        push    bx                      ; (0.16) /D: a dalt o a baix
        mov     bx, [cs:sv_bx]
        cmp     ax, [cs:convtop]
        jb      .dl
        inc     word [cs:dhi_n]
        add     [cs:dhi_p], bx
        jmp     short .dh
.dl:    inc     word [cs:dlo_n]
        add     [cs:dlo_p], bx
.dh:    pop     bx
        mov     ax, [cs:sv_bx]
        add     [cs:st_cur], ax
        jnc     .d2
        mov     word [cs:st_cur], 0FFFFh
.d2:    mov     ax, [cs:st_cur]
        cmp     ax, [cs:st_pk]
        jbe     .d3
        mov     [cs:st_pk], ax
.d3:    inc     word [cs:st_nb]
        pop     ax
        clc
.dno:   retf    2

; l'aplicacio allibera un bloc seu: es resta de les dades
.free:  cmp     byte [cs:trk], 0
        je      .chain
        call    esfill
        jne     .chain
        push    ax
        push    ds
        mov     ax, es
        dec     ax
        mov     ds, ax
        mov     ax, [1]
        cmp     ax, [cs:cpsp]
        jne     .f1
        mov     ax, [3]
        sub     [cs:st_cur], ax
        jnc     .f1
        mov     word [cs:st_cur], 0
.f1:    pop     ds
        pop     ax
        jmp     .chain

; l'aplicacio demana fer creixer un bloc seu (no les consultes FFFFh)
.resz:  cmp     byte [cs:trk], 0
        je      .chain
        cmp     bx, 0FFFFh
        je      .chain
        call    esfill
        jne     .chain
        push    ax
        push    ds
        mov     ax, es
        dec     ax
        mov     ds, ax
        cmp     bx, [3]
        jbe     .z1
        mov     ax, es
        cmp     ax, [cs:cpsp]
        je      .zp
        mov     ax, [1]
        cmp     ax, [cs:cpsp]
        jne     .z1
        or      byte [cs:st_fl], 2
        jmp     short .z1
.zp:    or      byte [cs:st_fl], 1
.z1:    pop     ds
        pop     ax
        jmp     .chain

; el GEM obre un fitxer mentre arrenca: si es un .ACC amb la marca
; 'programa a baix', ens apuntem la mida de la seva imatge
.open:  cmp     byte [cs:fase], 0
        je      .chain
        call    esacc
        jne     .chain
        push    ax
        mov     al, [cs:app_dh]
        push    ax
        call    marcat                  ; ZF=1: a baix
        pop     ax
        mov     [cs:app_dh], al
        pop     ax
        mov     word [cs:acc_lo], 0
        jne     .chain
        push    ax
        push    cx
        mov     ax, [cs:hdr+4]          ; pagines de 512 -> paragrafs,
        mov     cl, 5                   ;   menys la capcalera i una pagina
        shl     ax, cl
        sub     ax, [cs:hdr+8]
        jbe     .o1
        sub     ax, 32
        ja      .o2
.o1:    mov     ax, 1
.o2:    mov     [cs:acc_lo], ax
        pop     cx
        pop     ax
        jmp     .chain

; acaba un programa: si es GEMVDI carregat a dalt per GEMHI copiat a
; dalt, treu el ganxo i diu l'informe (despres el DOS ho allibera tot)
.term:  cmp     byte [cs:trk], 0      ; acaba l'aplicacio: el registre
        je      .t0
        call    esfill
        jne     .t0
        call    logapp
        mov     byte [cs:trk], 0
.t0:    cmp     word [cs:gvpsp], 0
        je      .chain
        push    ax
        push    bx
        push    dx
        push    ds
        mov     ah, 51h
        pushf
        call    far [cs:old21]
        cmp     bx, [cs:gvpsp]
        jne     .tx
        mov     word [cs:gvpsp], 0
        mov     byte [cs:fase], 0
        lds     dx, [cs:old21]
        mov     ax, 2521h
        int     21h
        push    cs
        pop     ds
        push    si
        push    cx
        call    informe
        pop     cx
        pop     si
.tx:    pop     ds
        pop     dx
        pop     bx
        pop     ax
        jmp     .chain

; ---------------------------------------------------------------------
;  Aplicacio a dalt: 4B01h amb la convencional tapada; li passem el
;  control i, quan acaba, tornem al GEM com si fos un EXEC normal.
;  Si no hi cap, l'EXEC normal (a baix).
; ---------------------------------------------------------------------
app_exec:
        push    bp                      ; (0.15) el retorn del GEM (IP CS FLAGS
        mov     bp, sp                  ;   del seu INT 21h), a part: mentre
        push    ax                      ;   corre l'aplicacio, l'AES fa servir
        mov     ax, [bp+2]              ;   aquesta pila i ho esborra (traca:
        mov     [cs:gem_ret], ax        ;   tornavem a 0000:0000)
        mov     ax, [bp+4]
        mov     [cs:gem_ret+2], ax
        mov     ax, [bp+6]
        mov     [cs:gem_ret+4], ax
        pop     ax
        pop     bp
        mov     [cs:gem_sp], sp         ; (0.11) a la pila del GEM no hi deixem
        mov     [cs:gem_ss], ss         ;   res mes que el seu INT 21h: l'AES
        cli                             ;   n'aprofita el que hi ha a sota
        push    cs                      ;   mentre corre l'aplicacio
        pop     ss
        mov     sp, app_stk + APPSTK
        sti
        push    ax
        push    bx
        push    cx
        push    dx
        push    si
        push    di
        push    bp
        push    ds
        push    es
        cld
        push    ds                      ; copia els 14 bytes del bloc
        push    es                      ;   (4B01h n'escriu 8 mes)
        pop     ds
        mov     si, bx
        push    cs
        pop     es
        mov     di, apb
        mov     cx, 7
        rep     movsw
        pop     ds                      ; DS:DX = el programa
        mov     [cs:app_sp], sp
        mov     [cs:app_ss], ss
        call    tapa
        push    cs
        pop     es
        mov     bx, apb
        mov     ax, 4B01h
        pushf
        call    far [cs:old21]
        mov     [cs:dbg_max], bx        ; (0.18) /D: si falla, el lloc que hi ha
        pushf
        call    destapa
        popf
        jc      .baix
        mov     ah, 51h                 ; el PSP del programa carregat
        pushf
        call    far [cs:old21]
        cmp     bx, [cs:gempsp]
        jne     .psp
        call    fillg
        or      bx, bx
        jz      .baix
.psp:   mov     byte [cs:apps], 2
        mov     es, bx                  ; quan acabi, torna a app_end
        mov     word [es:0Ah], app_end
        mov     [es:0Ch], cs
        mov     ax, [cs:apb+14h]        ; .COM: CS:IP i SS:SP com fa EXEC
        or      ax, [cs:apb+12h]
        jnz     .pb
        mov     [cs:apb+14h], bx
        mov     word [cs:apb+12h], 100h
        mov     [cs:apb+10h], bx
        mov     word [cs:apb+0Eh], 0FFFEh
        mov     word [es:0FFFEh], 0
.pb:    push    es                      ; (0.12) quan el programa acabi, el DOS
        push    di                      ;   agafa la pila del pare del seu
        push    cx                      ;   PSP:2Eh i hi escriu l'adreca de
        mov     ax, [es:16h]            ;   retorn. Un 4B01h no l'hi posa: hi
        mov     es, ax                  ;   quedava un valor vell i el DOS
        mov     word [es:2Eh], dosfrm   ;   escrivia en una pila qualsevol.
        mov     [es:30h], cs            ;   Ara apunta a un marc nostre, net.
        push    cs                      ; (0.13) i el marc ha de ser com el
        pop     es                      ;   que deixa un INT 21h: AX BX CX DX
        mov     di, dosfrm              ;   SI DI BP DS ES i IP CS FLAGS. El DOS
        mov     cx, DOSFRM/2            ;   torna fent IRET amb aquest marc:
        xor     ax, ax                  ;   ha d'apuntar a app_end.
        rep     stosw
        mov     [cs:dosfrm+14], cs      ; DS
        mov     [cs:dosfrm+16], cs      ; ES
        mov     word [cs:dosfrm+18], app_end
        mov     [cs:dosfrm+20], cs
        mov     word [cs:dosfrm+22], 0202h
        pop     cx
        pop     di
        pop     es
        mov     ah, 50h                 ; PSP actual = el del programa
        pushf
        call    far [cs:old21]
        mov     ds, bx
        mov     dx, 80h                 ; DTA a PSP:0080h
        mov     ah, 1Ah
        pushf
        call    far [cs:old21]
        cli
        mov     ss, [cs:apb+10h]
        mov     sp, [cs:apb+0Eh]
        sti
        mov     ds, bx
        mov     es, bx
        xor     ax, ax
        jmp     far [cs:apb+12h]
.baix:  mov     byte [cs:dbg_why], 4    ; (0.16) /D: no hi cabia
        pop     es                      ; no hi cap a dalt: EXEC normal
        pop     ds
        pop     bp
        pop     di
        pop     si
        pop     dx
        pop     cx
        pop     bx
        pop     ax
        cli
        mov     ss, [cs:gem_ss]
        mov     sp, [cs:gem_sp]
        sti
        jmp     far [cs:old21]

; l'aplicacio ha acabat (el DOS ja ha tornat el PSP actual al GEM)
app_end:
        cli
        mov     ss, [cs:app_ss]
        mov     sp, [cs:app_sp]
        sti
        mov     byte [cs:apps], 1
        pop     es
        pop     ds
        pop     bp
        pop     di
        pop     si
        pop     dx
        pop     cx
        pop     bx
        pop     ax
        cli
        mov     ss, [cs:gem_ss]
        mov     sp, [cs:gem_sp]
        push    bp                      ; (0.15) hi tornem a posar el retorn
        mov     bp, sp
        push    ax
        mov     ax, [cs:gem_ret]
        mov     [bp+2], ax
        mov     ax, [cs:gem_ret+2]
        mov     [bp+4], ax
        mov     ax, [cs:gem_ret+4]
        mov     [bp+6], ax
        pop     ax
        pop     bp
        sti
        clc
        retf    2

; ZF=1 si DS:DX acaba en .APP
esapp:  push    si
        push    ax
        mov     si, dx
.l:     mov     al, [si]
        inc     si
        or      al, al
        jnz     .l
        sub     si, 5                   ; ".APP",0
        jb      .no
        cmp     si, dx
        jb      .no
        cmp     byte [si], '.'
        jne     .x
        mov     ax, [si+1]
        and     ax, 0DFDFh
        cmp     ax, 'AP'
        jne     .x
        mov     al, [si+3]
        and     al, 0DFh
        cmp     al, 'P'
        jmp     short .x
.no:    or      al, 1                   ; ZF=0
.x:     pop     ax
        pop     si
        ret

; ZF=1 si el PSP actual (-> cpsp) es fill directe del GEM
esfill: push    ax
        push    bx
        push    es
        mov     ah, 51h
        pushf
        call    far [cs:old21]
        mov     [cs:cpsp], bx
        mov     es, bx
        mov     bx, [es:16h]
        cmp     bx, [cs:gempsp]
        pop     es
        pop     bx
        pop     ax
        ret

; el GEM engega un .APP (DS:DX): el seu nom i comptadors a zero
iniapp: push    ax
        push    cx
        push    si
        push    di
        push    es
        pushf
        cld
        push    cs
        pop     es
        mov     di, lognm
        mov     cx, 13
        xor     al, al
        rep     stosb
        mov     si, dx                  ; el nom, sense carpeta
        mov     di, dx
.f:     lodsb
        or      al, al
        jz      .g
        cmp     al, '\'
        je      .s
        cmp     al, ':'
        jne     .f
.s:     mov     di, si
        jmp     .f
.g:     mov     si, di
        mov     di, lognm
        mov     cx, 12
.c:     lodsb
        or      al, al
        jz      .e
        cmp     al, 'a'
        jb      .u
        cmp     al, 'z'
        ja      .u
        sub     al, 20h
.u:     stosb
        loop    .c
.e:     mov     byte [cs:st_fl], 0
        mov     word [cs:st_cur], 0
        mov     word [cs:st_pk], 0
        mov     word [cs:st_nb], 0
        mov     byte [cs:trk], 1
        popf
        pop     es
        pop     di
        pop     si
        pop     cx
        pop     ax
        ret

; acaba l'aplicacio (PSP cpsp): desa el seu registre a GEMHI.LOG
; (si ja hi era, el maxim de cada valor i una vegada mes)
logapp: push    ax
        push    bx
        push    cx
        push    dx
        push    si
        push    di
        push    ds
        push    es
        pushf
        cld
        push    cs
        pop     ds
        push    cs
        pop     es
        mov     si, lognm
        mov     di, rec
        mov     cx, 13
        rep     movsb
        mov     al, [st_fl]
        mov     [rec+13], al
        mov     ax, [cpsp]              ; el bloc del programa
        dec     ax
        push    es
        mov     es, ax
        mov     ax, [es:3]
        pop     es
        mov     [rec+14], ax
        mov     ax, [st_pk]
        mov     [rec+16], ax
        mov     ax, [st_nb]
        mov     [rec+18], ax
        mov     word [rec+20], 1
        mov     word [rec+22], 0
        mov     dx, logpath
        mov     ax, 3D02h
        pushf
        call    far [cs:old21]
        jnc     .o
        mov     dx, logpath
        xor     cx, cx
        mov     ah, 3Ch
        pushf
        call    far [cs:old21]
        jc      .x
.o:     mov     bx, ax
.l:     mov     dx, rbuf
        mov     cx, 24
        mov     ah, 3Fh
        pushf
        call    far [cs:old21]
        jc      .cl
        cmp     ax, 24
        jb      .w
        mov     si, rbuf
        mov     di, rec
        mov     cx, 13
        repe    cmpsb
        jne     .l
        mov     al, [rbuf+13]           ; ja hi era: el maxim
        or      [rec+13], al
        mov     si, 14
.m:     mov     ax, [rbuf+si]
        cmp     ax, [rec+si]
        jbe     .m1
        mov     [rec+si], ax
.m1:    inc     si
        inc     si
        cmp     si, 20
        jb      .m
        mov     ax, [rbuf+20]
        inc     ax
        jz      .m2
        mov     [rec+20], ax
.m2:    mov     ax, 4201h               ; enrere 24 bytes
        mov     cx, 0FFFFh
        mov     dx, -24
        pushf
        call    far [cs:old21]
.w:     mov     dx, rec
        mov     cx, 24
        mov     ah, 40h
        pushf
        call    far [cs:old21]
.cl:    mov     ah, 3Eh
        pushf
        call    far [cs:old21]
.x:     popf
        pop     es
        pop     ds
        pop     di
        pop     si
        pop     dx
        pop     cx
        pop     bx
        pop     ax
        ret

; (0.16) /D: enganxa INT EFh (al final de l'arrencada; el GEMVDI ja hi es)
dbg_on: cmp     byte [cs:dbg], 0
        je      .x
        push    ax
        push    bx
        push    dx
        push    ds
        push    es
        mov     ax, 35EFh
        pushf
        call    far [cs:old21]
        mov     [cs:oldefd], bx
        mov     [cs:oldefd+2], es
        push    cs
        pop     ds
        mov     dx, intefd
        mov     ax, 25EFh
        pushf
        call    far [cs:old21]
        pop     es
        pop     ds
        pop     dx
        pop     bx
        pop     ax
.x:     ret

; (0.16) /D: guarda la marca i engega les alertes d'aquesta aplicacio
dbgmk:  push    ax
        mov     ax, [cs:hdr+1Ch]
        mov     [cs:dmark], ax
        mov     ax, [cs:hdr+1Eh]
        mov     [cs:dmark+2], ax
        xor     ax, ax
        mov     [cs:dhi_n], ax
        mov     [cs:dhi_p], ax
        mov     [cs:dlo_n], ax
        mov     [cs:dlo_p], ax
        mov     al, [cs:dbg]
        mov     [cs:dbg_pend], al
        push    bx                      ; (0.18) el que demana: imatge, memoria
        push    cx                      ;   minima i PSP (paragrafs)
        xor     ax, ax
        cmp     word [cs:hdr], 'MZ'
        jne     .n
        mov     ax, [cs:hdr+4]
        mov     cl, 5
        shl     ax, cl
        mov     bx, [cs:hdr+2]
        or      bx, bx
        jz      .p
        sub     ax, 32
        add     bx, 15
        mov     cl, 4
        shr     bx, cl
        add     ax, bx
.p:     sub     ax, [cs:hdr+8]
        add     ax, [cs:hdr+0Ah]
        add     ax, 10h
.n:     mov     [cs:dbg_need], ax
        pop     cx
        pop     bx
        pop     ax
        ret

; ZF=1 si l'aplicacio (lognm) es DESKTOP.APP
esdesk: push    si
        push    di
        push    ax
        mov     si, lognm
        mov     di, t_desk
.l:     mov     al, [cs:si]
        cmp     al, [cs:di]
        jne     .x
        inc     si
        inc     di
        or      al, al
        jnz     .l
.x:     pop     ax
        pop     di
        pop     si
        ret
t_desk  db      'DESKTOP.APP', 0

; ZF=1 si DS:DX acaba en .ACC
esacc:  push    si
        push    ax
        mov     si, dx
.l:     mov     al, [si]
        inc     si
        or      al, al
        jnz     .l
        sub     si, 5                   ; ".ACC",0
        jb      .no
        cmp     si, dx
        jb      .no
        cmp     byte [si], '.'
        jne     .x
        mov     ax, [si+1]
        and     ax, 0DFDFh
        cmp     ax, 'AC'
        jne     .x
        mov     al, [si+3]
        and     al, 0DFh
        cmp     al, 'C'
        jmp     short .x
.no:    or      al, 1                   ; ZF=0
.x:     pop     ax
        pop     si
        ret

; ZF=1 si el fitxer DS:DX te la marca 'GHB',0 a l'offset 1Ch (vol
; anar a baix). Si no es pot llegir, ZF=0: l'EXEC ja dira l'error.
marcat: push    ax
        push    bx
        push    cx
        push    dx
        push    ds
        mov     word [cs:hdr], 0
        mov     word [cs:hdr+1Ch], 0
        mov     ax, 3D00h
        pushf
        call    far [cs:old21]
        jc      .x
        mov     bx, ax
        push    cs
        pop     ds
        mov     dx, hdr
        mov     cx, 32
        mov     ah, 3Fh
        pushf
        call    far [cs:old21]
        call    llarga
        mov     ah, 3Eh
        pushf
        call    far [cs:old21]
.x:     cmp     word [cs:hdr], 'MZ'
        jne     .no
        cmp     word [cs:hdr+1Ch], 'GH'
        jne     .r
        cmp     byte [cs:hdr+1Fh], 'A'  ; dades a dalt
        jne     .p
        mov     byte [cs:app_dh], 1
.p:     cmp     byte [cs:hdr+1Eh], 'B'  ; programa a baix
        jmp     short .r
.no:    or      al, 1                   ; ZF=0
.r:     pop     ds
        pop     dx
        pop     cx
        pop     bx
        pop     ax
        ret
hdr     times 32 db 0
hdr2    times 32 db 0
hlim    dw      0

; BX = fitxer (ja llegits els 32 primers bytes a hdr): si no hi ha la
; marca a 1Ch, busca la llarga ('GHMK', programa, dades) a la resta de
; la capcalera i, si hi es, la copia a hdr+1Ch ('GH', programa, dades)
llarga: push    ax
        push    cx
        push    dx
        push    si
        cmp     word [cs:hdr], 'MZ'
        jne     .x
        cmp     word [cs:hdr+1Ch], 'GH'
        je      .x
        mov     ax, [cs:hdr+8]          ; capcalera, fins a 1 KB
        cmp     ax, 64
        jbe     .a
        mov     ax, 64
.a:     mov     cl, 4
        shl     ax, cl
        mov     [cs:hlim], ax
        mov     si, 32                  ; offset del tros
.l:     mov     ax, si
        add     ax, 32
        cmp     ax, [cs:hlim]
        ja      .x
        mov     dx, hdr2
        mov     cx, 32
        mov     ah, 3Fh
        pushf
        call    far [cs:old21]
        jc      .x
        cmp     ax, 32
        jb      .x
        push    si
        xor     si, si
.s:     cmp     word [cs:hdr2+si], 'GH'
        jne     .n
        cmp     word [cs:hdr2+si+2], 'MK'
        jne     .n
        mov     word [cs:hdr+1Ch], 'GH'
        mov     ax, [cs:hdr2+si+4]
        mov     [cs:hdr+1Eh], ax
        pop     si
        jmp     short .x
.n:     add     si, 8
        cmp     si, 32
        jb      .s
        pop     si
        add     si, 32
        jmp     .l
.x:     pop     si
        pop     dx
        pop     cx
        pop     ax
        ret

; BX = PSP (a dalt) d'un programa fill del GEM, 0 si cap
fillg:  push    es
        push    ax
        push    dx
        mov     ax, [cs:firstmcb]
        xor     bx, bx
.l:     mov     es, ax
        mov     dx, ax
        inc     dx
        cmp     ax, [cs:convtop]
        jb      .n
        cmp     [es:1], dx
        jne     .n
        push    es
        mov     es, dx
        cmp     word [es:0], 20CDh
        jne     .p
        push    ax
        mov     ax, [cs:gempsp]
        cmp     [es:16h], ax
        pop     ax
.p:     pop     es
        jne     .n
        mov     bx, dx
.n:     cmp     byte [es:0], 'Z'
        je      .e
        add     ax, [es:3]
        inc     ax
        jmp     .l
.e:     pop     dx
        pop     ax
        pop     es
        ret

; tapa (a nom de GEMHI) els blocs lliures de la memoria convencional
tapa:   push    ax
        push    di
        push    es
        mov     ax, [cs:firstmcb]
        mov     di, bl_seg
.l:     mov     es, ax
        cmp     ax, [cs:convtop]
        jae     .e
        cmp     word [es:1], 0
        jne     .n
        cmp     di, bl_seg+2*MAXBL
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
        pop     di
        pop     ax
        ret

destapa:
        push    ax
        push    si
        push    es
        mov     si, bl_seg
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

; dades de l'EXEC
pblock  dw      0                       ; entorn: el nostre
        dw      cmdtail, 0
        dw      fcb1, 0
        dw      fcb2, 0
        dw      0, 0                    ; 4B01h: SS:SP del programa
        dw      0, 0                    ;        CS:IP del programa
alt     db      0                       ; 1: el programa s'ha carregat a dalt
tmp     times 80 db 0
fcb1    times 37 db 0
fcb2    times 37 db 0
cmdtail times 130 db 0
prog    times 80 db 0
sv_sp   dw      0
sv_ss   dw      0

; ---------------------------------------------------------------------
;  Inici. Tot el programa es queda a la memoria mentre dura el GEM
;  (uns 2 KB): el codi de despres de l'EXEC ha de continuar-hi.
; ---------------------------------------------------------------------
inici:  cld
        mov     sp, pila
        mov     [lowpsp], cs
        mov     si, 81h                 ; nom del programa
        call    salta
        cmp     byte [si], '/'          ; (0.16) /D: alertes de depuracio
        jne     .nd
        mov     al, [si+1]
        and     al, 0DFh
        cmp     al, 'D'
        jne     .nd
        mov     byte [dbg], 1
        add     si, 2
        call    salta
.nd:
        cmp     byte [si], 13
        jne     .p
        mov     dx, t_us
        jmp     error
.p:     mov     di, prog
.cn:    lodsb
        cmp     al, ' '
        je      .cf
        cmp     al, 9
        je      .cf
        cmp     al, 13
        je      .cf
        cmp     al, '/'
        je      .cf
        stosb
        jmp     .cn
.cf:    dec     si
        mov     byte [di], 0
        push    di                      ; ¨extensio?
        mov     bx, prog
        xor     dl, dl
.x:     cmp     bx, di
        jae     .x2
        mov     al, [bx]
        cmp     al, '.'
        jne     .x1
        mov     dl, 1
.x1:    cmp     al, '\'
        jne     .x1b
        xor     dl, dl
.x1b:   inc     bx
        jmp     .x
.x2:    pop     di
        or      dl, dl
        jnz     .tail
        push    si                      ; sense extensio: .EXE o .COM
        mov     si, e_exe
        call    copia
        call    existeix
        jnc     .ext
        mov     si, e_com
        call    copia
        call    existeix
        jnc     .ext
        pop     si
        mov     dx, t_nofile
        jmp     error
.ext:   pop     si
.tail:  mov     di, cmdtail+1           ; la resta de la linia
        xor     cx, cx
.t:     lodsb
        cmp     al, 13
        je      .te
        stosb
        inc     cx
        jmp     .t
.te:    mov     al, 13
        stosb
        mov     [cmdtail], cl
        mov     si, cmdtail+1           ; FCB 1 i 2
        mov     di, fcb1
        mov     ax, 2901h
        int     21h
        mov     di, fcb2
        mov     ax, 2901h
        int     21h
        mov     [pblock+4], cs
        mov     [pblock+8], cs
        mov     [pblock+12], cs
        call    absolut                 ; ruta completa del programa
        mov     al, [prog]              ; el registre: per si de cas, a l'arrel
        mov     [logpath], al           ;   de la unitat del GEM...
        call    rutalog                 ; ...pero millor al costat de GEMHI.COM

        mov     ah, 52h                 ; cadena de blocs i convencional
        int     21h
        mov     ax, [es:bx-2]
        mov     [firstmcb], ax
        int     12h
        mov     cl, 6
        shl     ax, cl
        mov     [convtop], ax
        call    hiha_zona
        jnc     .z
        mov     dx, t_nozona
        mov     ah, 9
        int     21h

.z:     mov     bx, (fi_resident-start+100h+15)/16
        push    cs
        pop     es
        mov     ah, 4Ah                 ; nomes el que cal
        int     21h

        call    tapa                    ; GEMHI mateix, a dalt: un bloc
        mov     bx, (fi_resident-start+100h+15)/16
        mov     ah, 48h
        int     21h
        pushf
        call    destapa
        popf
        jc      .hook
        cmp     ax, [convtop]
        jae     .cp
        mov     es, ax                  ; ha anat a baix: no serveix
        mov     ah, 49h
        int     21h
        jmp     short .hook
.cp:    mov     es, ax                  ; copia (PSP inclos: mateixos
        xor     si, si                  ;   desplacaments)
        xor     di, di
        mov     cx, fi_resident-start+100h
        rep     movsb
        push    ax
        mov     ax, .alt
        push    ax
        retf                            ; continua al bloc de dalt
.alt:   cli
        mov     ax, cs
        mov     ds, ax
        mov     es, ax
        mov     ss, ax
        mov     sp, pila
        sti
        cld
        mov     [hiseg], ax
        mov     [pblock+4], cs
        mov     [pblock+8], cs
        mov     [pblock+12], cs
        dec     ax                      ; el bloc, de moment, de GEMHI
        mov     es, ax
        mov     ax, [lowpsp]
        mov     [es:1], ax
.hook:  push    cs
        pop     es
        mov     ax, 3521h
        int     21h
        mov     [old21], bx
        mov     [old21+2], es
        mov     dx, int21
        mov     ax, 2521h
        int     21h

        mov     byte [fase], 1
        mov     byte [nexec], 0FFh      ; el nostre EXEC tambe passa pel ganxo
        mov     [sv_sp], sp
        mov     [sv_ss], ss
        call    tapa                    ; el programa, a dalt: 4B01h
        push    cs
        pop     es
        mov     dx, prog
        mov     bx, pblock
        mov     ax, 4B01h
        int     21h
        cli
        mov     ss, [cs:sv_ss]
        mov     sp, [cs:sv_sp]
        sti
        push    cs
        pop     ds
        push    cs
        pop     es
        cld
        pushf
        call    destapa
        popf
        jc      .baix
        call    fill                    ; BX = PSP del programa carregat
        or      bx, bx
        jz      .baix
        mov     byte [alt], 1
        cmp     word [hiseg], 0
        je      .noh
        push    ds                      ; GEMHI a dalt: el pare de GEMVDI
        mov     ds, [lowpsp]            ;   passa a ser COMMAND.COM, amb
        mov     es, bx                  ;   la tornada de GEMHI
        mov     ax, [16h]
        mov     [es:16h], ax
        mov     ax, [0Ah]
        mov     [es:0Ah], ax
        mov     ax, [0Ch]
        mov     [es:0Ch], ax
        mov     ax, [2Ch]               ; i s'alliberen els blocs de baix
        pop     ds
        or      ax, ax
        jz      .nenv
        mov     es, ax
        mov     ah, 49h
        int     21h
.nenv:  mov     es, [lowpsp]
        mov     ah, 49h
        int     21h
        mov     ax, cs                  ; el bloc de dalt, de GEMVDI
        dec     ax
        mov     es, ax
        mov     [es:1], bx
        mov     [gvpsp], bx
.noh:
        mov     ax, [pblock+14h]        ; .COM: CS:IP i SS:SP com fa EXEC
        or      ax, [pblock+12h]
        jnz     .pb
        mov     [pblock+14h], bx
        mov     word [pblock+12h], 100h
        mov     [pblock+10h], bx
        mov     word [pblock+0Eh], 0FFFEh
        push    es
        mov     es, bx
        mov     word [es:0FFFEh], 0
        pop     es
.pb:    mov     ah, 50h                 ; PSP actual = el del programa
        int     21h
        mov     ds, bx
        mov     es, bx
        mov     dx, 80h                 ; DTA a PSP:0080h, com fa EXEC
        mov     ah, 1Ah
        int     21h
        cmp     word [cs:hiseg], 0      ; GEMHI a baix: quan acabi, torna
        jne     .go                     ;   a fi_prog
        mov     word [0Ah], fi_prog
        mov     [0Ch], cs
.go:    cli
        mov     ss, [cs:pblock+10h]
        mov     sp, [cs:pblock+0Eh]
        sti
        xor     ax, ax
        jmp     far [cs:pblock+12h]

.baix:  mov     byte [nexec], 0FFh      ; no hi cap a dalt: EXEC normal
        mov     [sv_sp], sp
        mov     [sv_ss], ss
        push    cs
        pop     es
        mov     dx, prog
        mov     bx, pblock
        mov     ax, 4B00h
        int     21h
fi_prog:
        cli
        mov     ss, [cs:sv_ss]
        mov     sp, [cs:sv_sp]
        sti
        push    cs
        pop     ds
        push    cs
        pop     es
        cld
        pushf                           ; CF de l'EXEC (4B00h)
        cmp     byte [alt], 0           ; carregat a dalt: ha acabat be
        je      .f
        pop     ax
        and     al, 0FEh                ; CF=0
        push    ax
.f:
        mov     byte [fase], 0
        push    ds
        lds     dx, [old21]             ; treu el ganxo
        mov     ax, 2521h
        int     21h
        pop     ds
        popf
        jnc     .ret
        mov     dx, t_noexec
        jmp     error
.ret:   call    informe
        mov     ah, 4Dh                 ; el codi de sortida del programa
        int     21h
        mov     ah, 4Ch
        int     21h

; BX = PSP del programa que acabem de carregar (fill nostre), 0 si cap
fill:   push    es
        push    ax
        push    dx
        mov     ax, [firstmcb]
        xor     bx, bx
.l:     mov     es, ax
        mov     dx, ax
        inc     dx
        cmp     [es:1], dx              ; bloc de programa
        jne     .n
        push    es
        mov     es, dx
        cmp     word [es:0], 20CDh
        jne     .p
        push    ax
        mov     ax, [lowpsp]
        cmp     [es:16h], ax            ; el seu pare som nosaltres
        pop     ax
.p:     pop     es
        jne     .n
        mov     bx, dx
.n:     cmp     byte [es:0], 'Z'
        je      .e
        add     ax, [es:3]
        inc     ax
        jmp     .l
.e:     pop     dx
        pop     ax
        pop     es
        ret

; logpath = la carpeta de GEMHI.COM (de l'entorn: despres de les
; variables, 00 00, una paraula i la ruta del programa) + GEMHI.LOG
rutalog:
        push    ds
        mov     ax, [2Ch]
        or      ax, ax
        jz      .x
        mov     ds, ax
        xor     si, si
.v:     cmp     word [si], 0            ; final de les variables
        je      .p
        inc     si
        cmp     si, 7FF0h
        jb      .v
        jmp     short .x
.p:     add     si, 4                   ; 00 00 i el comptador
        cmp     byte [si], 0            ; (sense ruta: es queda a l'arrel)
        je      .x
        mov     di, logpath
        xor     bx, bx                  ; despres de la darrera '\'
.c:     lodsb
        mov     [cs:di], al
        inc     di
        cmp     al, '\'
        jne     .c1
        mov     bx, di
.c1:    or      al, al
        jz      .f
        cmp     di, logpath+80-12
        jb      .c
        mov     byte [cs:logpath+3], 0  ; massa llarga: a l'arrel
        mov     bx, logpath+3
.f:     or      bx, bx
        jnz     .n
        mov     bx, logpath+3           ; sense '\': a l'arrel
        mov     byte [cs:logpath+2], '\'
.n:     push    cs
        pop     ds
        mov     si, t_log
        mov     di, bx
.k:     lodsb
        mov     [cs:di], al
        inc     di
        or      al, al
        jnz     .k
.x:     pop     ds
        ret
t_log   db      'GEMHI.LOG', 0


; ---------------------------------------------------------------------
;  /D (0.16): alertes del GEM amb el que GEMHI ha fet amb cada aplicacio.
;  INT EFh: just despres del seu appl_init (on es el programa i per que)
;  i just abans del seu appl_exit (on han anat les dades). L'alerta es
;  fa en nom de l'aplicacio, com si la crid‚s ella.
; ---------------------------------------------------------------------
intefd: jmp     short .go               ; (0.17) com el de l'AES: les
        db      'GEMAES20', 0           ;   aplicacions miren que hi sigui
.go:    cmp     byte [cs:dbg_pend], 0
        je      .c
        cmp     cx, 200
        jne     .c
        push    si
        push    ds
        lds     si, [es:bx]             ; aespb -> control
        mov     si, [si]                ; opcode
        cmp     si, 10
        pop     ds
        je      .ini
        cmp     si, 19
        pop     si
        je      .sur
.c:     jmp     far [cs:oldefd]
.ini:   pop     si
        pushf
        call    far [cs:oldefd]         ; l'appl_init de l'aplicacio
        push    ax
        push    bx
        push    cx
        push    dx
        push    si
        push    di
        push    ds
        push    es
        call    alt_ini
        pop     es
        pop     ds
        pop     di
        pop     si
        pop     dx
        pop     cx
        pop     bx
        pop     ax
        iret
.sur:   push    ax
        push    bx
        push    cx
        push    dx
        push    si
        push    di
        push    ds
        push    es
        call    alt_sur
        mov     byte [cs:dbg_pend], 0
        pop     es
        pop     ds
        pop     di
        pop     si
        pop     dx
        pop     cx
        pop     bx
        pop     ax
        jmp     far [cs:oldefd]

; text de l'alerta: comenca
a_ini:  push    cs
        pop     es
        push    cs
        pop     ds
        cld
        mov     di, dtext
        mov     si, d_t0                ; "[1][GEMHI: "
        call    dcpy
        mov     si, lognm
        call    dcpy
        ret

; afegeix SI (ASCIIZ) a ES:DI
dcpy:   lodsb
        or      al, al
        jz      .x
        stosb
        jmp     dcpy
.x:     ret

; AX -> decimal a ES:DI
ddec:   push    bx
        push    cx
        push    dx
        mov     bx, 10
        xor     cx, cx
.l:     xor     dx, dx
        div     bx
        push    dx
        inc     cx
        or      ax, ax
        jnz     .l
.p:     pop     ax
        add     al, '0'
        stosb
        loop    .p
        pop     dx
        pop     cx
        pop     bx
        ret

; AX -> 4 xifres hexadecimals a ES:DI
dhex:   push    cx
        mov     cx, 4
.l:     push    cx
        mov     cl, 4
        rol     ax, cl
        pop     cx
        push    ax
        and     al, 0Fh
        add     al, '0'
        cmp     al, '9'
        jbe     .d
        add     al, 7
.d:     stosb
        pop     ax
        loop    .l
        pop     cx
        ret

; paragrafs AX -> KB
dkb:    add     ax, 63
        jnc     .a
        mov     ax, 0FFFFh
.a:     push    cx
        mov     cl, 6
        shr     ax, cl
        pop     cx
        ret

; alerta despres de l'appl_init: marca, on es el programa i per que
alt_ini:
        call    a_ini
        mov     si, d_mk                ; "|Marca: "
        call    dcpy
        mov     si, d_cap
        cmp     word [dmark], 'GH'
        jne     .m1
        mov     si, d_pa
        cmp     byte [dmark+2], 'B'
        jne     .m0
        mov     si, d_pb
.m0:    call    dcpy
        mov     si, d_da
        cmp     byte [dmark+3], 'A'
        je      .m1
        mov     si, d_db
.m1:    call    dcpy
        mov     si, d_pr                ; "|Programa: "
        call    dcpy
        mov     ah, 51h                 ; on es (el PSP de l'aplicacio)
        pushf
        call    far [cs:old21]
        push    bx
        mov     si, d_alt
        cmp     bx, [convtop]
        jae     .p
        mov     si, d_baix
.p:     call    dcpy
        pop     ax
        call    dhex
        mov     al, ')'
        stosb
        mov     si, d_mot               ; "|Motiu: "
        call    dcpy
        mov     bl, [dbg_why]
        cmp     bl, 4                   ; (0.18) no hi cabia: quant, i quant
        jne     .w                      ;   n'hi havia
        mov     si, d_cal               ; "cal "
        call    dcpy
        mov     ax, [dbg_need]
        call    dkb
        call    ddec
        mov     si, d_hiha              ; "K, a dalt "
        call    dcpy
        mov     ax, [dbg_max]
        call    dkb
        call    ddec
        mov     si, d_k
        call    dcpy
        jmp     short .w2
.w:     xor     bh, bh
        shl     bx, 1
        mov     si, [d_why+bx]
        call    dcpy
.w2:
        mov     si, d_dad               ; "|Dades: "
        call    dcpy
        mov     si, d_dlo
        cmp     byte [app_dh], 0
        je      .d
        mov     si, d_dhi
.d:     call    dcpy
        jmp     alerta

; alerta abans de l'appl_exit: on han anat les dades
alt_sur:
        call    a_ini
        mov     si, d_surt
        call    dcpy
        mov     si, d_dalt              ; "|Dades a dalt: "
        call    dcpy
        mov     ax, [dhi_n]
        call    ddec
        mov     si, d_bl
        call    dcpy
        mov     ax, [dhi_p]
        call    dkb
        call    ddec
        mov     si, d_k
        call    dcpy
        mov     si, d_dbx               ; "|Dades a baix: "
        call    dcpy
        mov     ax, [dlo_n]
        call    ddec
        mov     si, d_bl
        call    dcpy
        mov     ax, [dlo_p]
        call    dkb
        call    ddec
        mov     si, d_k
        call    dcpy
        mov     si, d_crx               ; "|Creix: "
        call    dcpy
        mov     bl, [st_fl]
        and     bx, 3
        shl     bx, 1
        mov     si, [d_crt+bx]
        call    dcpy
; acaba el text i fa form_alert
alerta: mov     si, d_fi                ; "][ D'acord ]"
        call    dcpy
        mov     byte [di], 0
        mov     word [dctl], 52         ; form_alert
        mov     word [dctl+2], 1
        mov     word [dctl+4], 1
        mov     word [dctl+6], 1
        mov     word [dctl+8], 0
        mov     word [dii], 1
        mov     word [dai], dtext
        mov     [dai+2], cs
        mov     ax, cs
        mov     [dpb+2], ax
        mov     [dpb+6], ax
        mov     [dpb+10], ax
        mov     [dpb+14], ax
        mov     [dpb+18], ax
        mov     [dpb+22], ax
        mov     bx, dpb
        mov     cx, 200
        pushf
        call    far [cs:oldefd]
        ret

dbg     db      0               ; /D
dbg_pend db     0               ; 1: l'aplicacio encara no ha fet appl_init/exit
dbg_why db      0               ; motiu (d_why)
dmark   times 4 db 0            ; la marca (normalitzada a 'GH' p d)
dbg_need dw     0               ; paragrafs que demana el programa
dbg_max dw      0               ; bloc mes gran a dalt quan no hi cabia
dhi_n   dw      0
dhi_p   dw      0
dlo_n   dw      0
dlo_p   dw      0
oldefd  dw      0, 0
dpb     dw      dctl, 0, dglob, 0, dii, 0, dio, 0, dai, 0, dao, 0
dctl    times 5 dw 0
dglob   times 15 dw 0
dii     times 4 dw 0
dio     times 4 dw 0
dai     times 2 dw 0
dao     times 2 dw 0
d_t0    db      '[1][GEMHI: ', 0
d_mk    db      '|Marca: ', 0
d_cap   db      'cap', 0
d_pa    db      'prog Alta,', 0
d_pb    db      'prog Conv,', 0
d_da    db      ' dades Alta', 0
d_db    db      ' dades Conv', 0
d_pr    db      '|Programa: ', 0
d_alt   db      'a dalt (', 0
d_baix  db      'a baix (', 0
d_mot   db      '|Motiu: ', 0
d_cal   db      'cal ', 0
d_hiha  db      'K, a dalt ', 0
d_dad   db      '|Dades: ', 0
d_dlo   db      'a baix', 0
d_dhi   db      'a dalt si hi caben', 0
d_surt  db      ' surt', 0
d_dalt  db      '|Dades a dalt: ', 0
d_dbx   db      '|Dades a baix: ', 0
d_bl    db      ' bl., ', 0
d_k     db      'K', 0
d_crx   db      '|Creix: ', 0
d_fi    db      '][ D', 39, 'acord ]', 0
d_w0    db      'sense marca: a baix', 0
d_w1    db      'marca Alta', 0
d_w2    db      'escriptori', 0
d_w3    db      'marca Conv', 0
d_w4    db      'no hi cabia a dalt', 0
d_why   dw      d_w0, d_w1, d_w2, d_w3, d_w4
d_c0    db      'no', 0
d_c1    db      'el programa', 0
d_c2    db      'dades', 0
d_c3    db      'programa i dades', 0
d_crt   dw      d_c0, d_c1, d_c2, d_c3
dtext   times 200 db 0

; prog -> ruta completa (unitat:\directori\nom), com la desa el DOS a
; l'entorn del programa
absolut:
        mov     si, prog
        mov     di, tmp
        mov     ah, 19h
        int     21h
        mov     dl, al                  ; unitat (0 = A)
        cmp     byte [si+1], ':'
        jne     .u
        mov     al, [si]
        and     al, 0DFh
        sub     al, 'A'
        mov     dl, al
        add     si, 2
.u:     mov     al, dl
        add     al, 'A'
        stosb
        mov     al, ':'
        stosb
        cmp     byte [si], '\'
        je      .r
        mov     al, '\'
        stosb
        push    si
        mov     si, di
        inc     dl
        mov     ah, 47h                 ; directori actual d'aquella unitat
        int     21h
        pop     si
        jc      .r
.f:     cmp     byte [di], 0
        je      .f1
        inc     di
        jmp     .f
.f1:    cmp     byte [di-1], '\'
        je      .r
        mov     al, '\'
        stosb
.r:     lodsb                           ; la resta de la ruta
        stosb
        or      al, al
        jnz     .r
        mov     si, tmp
        mov     di, prog
.c:     lodsb
        stosb
        or      al, al
        jnz     .c
        ret

; hi ha algun bloc per sobre de la convencional? CF=1 si no
hiha_zona:
        mov     ax, [firstmcb]
.l:     mov     es, ax
        cmp     ax, [convtop]
        jae     .si
        cmp     byte [es:0], 'Z'
        je      .no
        add     ax, [es:3]
        inc     ax
        jmp     .l
.si:    clc
        ret
.no:    stc
        ret

; "GEMHI: n blocs a la memoria alta (x bytes):" i la llista
informe:
        mov     dx, t_inf1
        mov     ah, 9
        int     21h
        mov     ax, [nreg]
        call    pdec
        mov     dx, t_inf2
        mov     ah, 9
        int     21h
        mov     ax, [totpar]            ; bytes = paragrafs * 16 (32 bits)
        mov     cx, 16
        mul     cx
        call    pdec32
        mov     dx, t_inf3
        mov     ah, 9
        int     21h
        mov     cx, [nreg]
        cmp     cx, MAXREG
        jbe     .c
        mov     cx, MAXREG
.c:     jcxz    .x
        xor     si, si
.l:     mov     dx, t_sp
        mov     ah, 9
        int     21h
        mov     ax, [reg_seg+si]
        dec     ax                      ; adreca del bloc (MCB)
        call    phex4
        mov     dl, '0'
        call    pch
        mov     dx, t_sp
        mov     ah, 9
        int     21h
        mov     ax, [reg_par+si]
        push    cx
        mov     cx, 16
        mul     cx
        call    pdec32
        pop     cx
        mov     dx, t_bytes
        mov     ah, 9
        int     21h
        add     si, 2
        loop    .l
.x:     ret

pch:    mov     ah, 2
        int     21h
        ret

phex4:  push    cx
        mov     cx, 4
.l:     push    cx
        mov     cl, 4
        rol     ax, cl
        pop     cx
        push    ax
        and     al, 0Fh
        add     al, '0'
        cmp     al, '9'
        jbe     .d
        add     al, 7
.d:     mov     dl, al
        call    pch
        pop     ax
        loop    .l
        pop     cx
        ret

pdec:   xor     dx, dx
; DX:AX -> decimal
pdec32: push    bx
        push    cx
        push    si
        xor     cx, cx
.l:     mov     bx, 10                  ; DX:AX / 10
        push    ax
        mov     ax, dx
        xor     dx, dx
        div     bx
        mov     si, ax
        pop     ax
        div     bx
        push    dx
        inc     cx
        mov     dx, si
        or      si, ax
        jnz     .l
.p:     pop     dx
        add     dl, '0'
        call    pch
        loop    .p
        pop     si
        pop     cx
        pop     bx
        ret

salta:  cmp     byte [si], ' '
        je      .s
        cmp     byte [si], 9
        jne     .x
.s:     inc     si
        jmp     salta
.x:     ret

copia:  push    di                      ; SI (ASCIIZ) a DI, sense moure DI
.l:     lodsb
        mov     [di], al
        inc     di
        or      al, al
        jnz     .l
        pop     di
        ret

existeix:
        mov     dx, prog
        mov     ax, 4300h
        int     21h
        ret

error:  mov     ah, 9
        int     21h
        mov     ax, 4C01h
        int     21h

e_exe   db      '.EXE', 0
e_com   db      '.COM', 0
t_us    db      'GEMHI 0.18 - Engega el GEM amb el que carrega en arrencar a la', 13, 10
        db      'mem', 95h, 'ria alta (cal una zona alta enlla', 87h, 'ada: LOADHI /H).', 13, 10, 13, 10
        db      0E9h, 's:  GEMHI [/D] programa [par', 85h, 'metres]   p. ex.  GEMHI GEMVDI', 13, 10
        db      '     /D  alertes del GEM amb on va cada aplicaci', 0A2h, ' i per qu', 8Ah, 13, 10, '$'
t_nofile db     'GEMHI: no trobo el programa.', 13, 10, '$'
t_noexec db     'GEMHI: no s', 27h, 'ha pogut executar el programa.', 13, 10, '$'
t_nozona db     'GEMHI: no hi ha zona alta enlla', 87h, 'ada; tot anir', 85h, ' a baix.', 13, 10, '$'
t_inf1  db      13, 10, 'GEMHI: $'
t_inf2  db      ' blocs a la mem', 95h, 'ria alta ($'
t_inf3  db      ' bytes):', 13, 10, '$'
t_sp    db      '  $'
t_bytes db      ' bytes', 13, 10, '$'

        align   2
        times   384 db 0                ; pila
pila:
fi_resident:
