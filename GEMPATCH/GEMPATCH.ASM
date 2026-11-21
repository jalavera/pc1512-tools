; =====================================================================
;  GEMPATCH.ASM - Canvia els temps de doble clic del GEM (GEM.EXE)
;                 Versio 0.1 - 8086, MS-DOS 2.0 o superior
;
;  Muntatge:  nasm -f bin GEMPATCH.ASM -o GEMPATCH.COM
;
;  Us:  GEMPATCH [directori] [t1 t2 t3 t4 t5] [/D] [/R] [/?]
;
;  El GEM (AES) te una taula de 5 temps de doble clic en mil.lisegons,
;  un per a cada velocitat del Desktop (1 = la mes lenta). Al codi font
;  de Digital Research es diu gl_dcrates i val 450,330,275,220,165 a
;  totes les versions conegudes, en qualsevol idioma (l'idioma nomes
;  canvia els fitxers .RSC). GEMPATCH la busca per contingut, no per
;  posicio, i per aixo hauria de servir per a altres versions del GEM.
;
;  - Si no hi ha GEM.ORI: GEM.EXE passa a dir-se GEM.ORI (l'original
;    no es toca mai mes) i es crea un GEM.EXE nou amb la taula canviada.
;  - Si ja hi ha GEM.ORI: la taula es localitza a GEM.ORI i es canvia
;    directament a GEM.EXE.
;  - El GEM divideix cada temps pels ms d'un tic del rellotge (~55) i
;    amb 0 tics no detecta el doble clic: el minim acceptat es 55.
; =====================================================================

        cpu     8086
        org     100h

CHUNK   equ     4096
VMIN    equ     55
VMAX    equ     30000

start:  cld
        mov     dx, m_titol
        call    print
        call    parse
        cmp     byte [o_help], 0
        je      .nh
        mov     dx, m_ajuda
        call    print
        jmp     surt0
.nh:    call    troba_exe
        cmp     byte [o_rest], 0
        je      .nr
        jmp     restaura
.nr:    call    localitza
        call    llegeix_actuals
        mov     dx, m_actuals
        call    print
        mov     si, actuals
        call    mostra_valors
        cmp     byte [nnums], 5         ; valors a la linia d'ordres
        je      .aplica
        cmp     byte [o_def], 0
        je      .preg
        mov     si, defecte
        mov     di, nous
        mov     cx, 5
        rep     movsw
        jmp     short .aplica
.preg:  call    pregunta
        jnc     .aplica
        mov     dx, m_cancel
        call    print
        jmp     surt0
.aplica:
        call    aplica
        mov     dx, m_fet
        call    print
        mov     si, nous
        call    mostra_valors
        mov     dx, m_fet2
        call    print
        jmp     surt0

surt0:  mov     ax, 4C00h
        int     21h
error:  call    print                   ; dx = missatge
        mov     ax, 4C01h
        int     21h

; ---------------------------------------------------------------------
;  Linia d'ordres
; ---------------------------------------------------------------------
parse:  mov     si, 81h
        mov     cl, [80h]
        xor     ch, ch
        mov     bx, si
        add     bx, cx
        mov     byte [bx], 0
.seg:   call    salta_espais
        mov     al, [si]
        or      al, al
        jz      .fi
        cmp     al, 13
        je      .fi
        cmp     al, '/'
        je      .sw
        cmp     al, '0'
        jb      .dir
        cmp     al, '9'
        ja      .dir
        call    llegeix_num             ; numero
        jc      .malnum
        mov     bl, [nnums]
        cmp     bl, 5
        jae     .malnum
        xor     bh, bh
        shl     bx, 1
        mov     [nous+bx], ax
        inc     byte [nnums]
        jmp     .seg
.malnum:
        mov     dx, m_malnum
        jmp     error
.dir:   cmp     byte [dir], 0           ; directori
        jne     .malarg
        mov     di, dir
        mov     cx, 64
.dc:    lodsb
        cmp     al, ' '
        jbe     .de
        stosb
        loop    .dc
        jmp     .malarg
.de:    dec     si
        mov     al, [di-1]
        cmp     al, '\'
        je      .dz
        cmp     al, ':'
        je      .dz
        mov     al, '\'
        stosb
.dz:    mov     byte [di], 0
        mov     byte [o_dir], 1
        jmp     .seg
.sw:    inc     si
        lodsb
        and     al, 0DFh                ; majuscula
        cmp     al, 'R'
        je      .r
        cmp     al, 'D'
        je      .d
        cmp     byte [si-1], '?'
        je      .h
.malarg:
        mov     dx, m_malarg
        jmp     error
.r:     mov     byte [o_rest], 1
        jmp     .seg
.d:     mov     byte [o_def], 1
        jmp     .seg
.h:     mov     byte [o_help], 1
        jmp     .seg
.fi:    mov     al, [nnums]
        or      al, al
        jz      .ok
        cmp     al, 5
        jne     .malnum
.ok:    ret

salta_espais:
        cmp     byte [si], ' '
        je      .s
        cmp     byte [si], 9
        jne     .r
.s:     inc     si
        jmp     salta_espais
.r:     ret

; si -> numero decimal; ax = valor, CF=1 si no es valid (VMIN..VMAX)
llegeix_num:
        xor     ax, ax
        xor     cx, cx
.l:     mov     bl, [si]
        cmp     bl, '0'
        jb      .e
        cmp     bl, '9'
        ja      .e
        inc     si
        inc     cx
        cmp     cx, 5
        ja      .mal
        mov     dx, 10
        mul     dx
        jc      .mal
        sub     bl, '0'
        xor     bh, bh
        add     ax, bx
        jc      .mal
        jmp     .l
.e:     cmp     bl, ' '
        ja      .mal
        jcxz    .mal
        cmp     ax, VMIN
        jb      .mal
        cmp     ax, VMAX
        ja      .mal
        clc
        ret
.mal:   stc
        ret

; ---------------------------------------------------------------------
;  Noms de fitxer
; ---------------------------------------------------------------------
; Troba GEM.EXE: al directori indicat, o a l'actual i despres a \GEMBOOT
troba_exe:
        call    nom_exe
        mov     dx, nexe
        call    existeix
        jnc     .ok
        cmp     byte [o_dir], 0
        jne     .no
        mov     si, gemboot
        mov     di, dir
        call    copia_z
        call    nom_exe
        mov     dx, nexe
        call    existeix
        jnc     .ok
.no:    cmp     byte [o_dir], 0
        jne     .nd
        mov     dx, m_noexe2
        jmp     error
.nd:    mov     dx, m_noexe
        call    print
        mov     dx, nexe
        call    printz
        mov     dx, m_crlf
        jmp     error
.ok:    call    nom_ori
        ret

nom_exe:
        mov     si, dir
        mov     di, nexe
        call    copia_z0
        mov     si, s_exe
        jmp     copia_z
nom_ori:
        mov     si, dir
        mov     di, nori
        call    copia_z0
        mov     si, s_ori
        jmp     copia_z

; dx -> nom; CF=0 si es pot obrir
existeix:
        mov     ax, 3D00h
        int     21h
        jc      .r
        mov     bx, ax
        mov     ah, 3Eh
        int     21h
        clc
.r:     ret

copia_z:                                ; amb el 0 final
        lodsb
        stosb
        or      al, al
        jnz     copia_z
        ret
copia_z0:                               ; sense el 0 final
        lodsb
        or      al, al
        jz      .r
        stosb
        jmp     copia_z0
.r:     ret

; ---------------------------------------------------------------------
;  /R: torna a posar el GEM.EXE original
; ---------------------------------------------------------------------
restaura:
        mov     dx, nori
        call    existeix
        jnc     .ok
        mov     dx, m_noori
        jmp     error
.ok:    mov     dx, nexe
        mov     ah, 41h
        int     21h
        mov     dx, nori
        mov     di, nexe
        mov     ah, 56h
        int     21h
        jnc     .fet
        mov     dx, m_errren
        jmp     error
.fet:   mov     dx, m_restaurat
        call    print
        jmp     surt0

; ---------------------------------------------------------------------
;  Localitza la taula -> [offlo],[offhi]; [teori]=1 si hi ha GEM.ORI
; ---------------------------------------------------------------------
localitza:
        mov     byte [teori], 0
        mov     dx, nori
        mov     ax, 3D00h
        int     21h
        jc      .exe
        mov     byte [teori], 1
        mov     [fh], ax
        mov     si, patro
        mov     cx, 10
        call    cerca
        pushf
        push    ax
        push    dx
        call    mida                    ; dx:ax = mida de GEM.ORI
        mov     [orilo], ax
        mov     [orihi], dx
        call    tanca_fh
        pop     dx
        pop     ax
        popf
        jc      .exe
        mov     [offlo], ax
        mov     [offhi], dx
        mov     dx, nexe                ; GEM.EXE ha de tenir la mateixa mida
        mov     ax, 3D00h
        int     21h
        jc      .rd
        mov     [fh], ax
        call    mida
        push    ax
        push    dx
        call    tanca_fh
        pop     dx
        pop     ax
        cmp     ax, [orilo]
        jne     .dif
        cmp     dx, [orihi]
        jne     .dif
        ret
.dif:   mov     dx, m_difmida
        jmp     error
.exe:   mov     dx, nexe                ; busca a GEM.EXE
        mov     ax, 3D00h
        int     21h
        jnc     .o2
.rd:    mov     dx, m_errlect
        jmp     error
.o2:    mov     [fh], ax
        mov     si, patro
        mov     cx, 10
        call    cerca
        jnc     .trob
        call    rebobina
        mov     si, patro+2             ; ja parxejada nomes la velocitat 1
        mov     cx, 8
        call    cerca
        jc      .no
        sub     ax, 2
        sbb     dx, 0
.trob:  mov     [offlo], ax
        mov     [offhi], dx
        jmp     tanca_fh
.no:    call    tanca_fh
        mov     dx, m_notaula
        jmp     error

; Llegeix els 5 valors actuals de GEM.EXE
llegeix_actuals:
        mov     dx, nexe
        mov     ax, 3D00h
        int     21h
        jc      .e
        mov     [fh], ax
        call    posiciona
        mov     bx, [fh]
        mov     dx, actuals
        mov     cx, 10
        mov     ah, 3Fh
        int     21h
        jc      .e
        cmp     ax, 10
        jne     .e
        jmp     tanca_fh
.e:     mov     dx, m_errlect
        jmp     error

tanca_fh:
        mov     bx, [fh]
        mov     ah, 3Eh
        int     21h
        ret

rebobina:
        xor     cx, cx
        xor     dx, dx
        mov     bx, [fh]
        mov     ax, 4200h
        int     21h
        ret

posiciona:
        mov     cx, [offhi]
        mov     dx, [offlo]
        mov     bx, [fh]
        mov     ax, 4200h
        int     21h
        ret

mida:   xor     cx, cx                  ; -> dx:ax
        xor     dx, dx
        mov     bx, [fh]
        mov     ax, 4202h
        int     21h
        ret

; Cerca el patro si (cx bytes) al fitxer [fh] des de la posicio actual.
; CF=0 i dx:ax = posicio al fitxer si el troba.
cerca:  mov     [pat], si
        mov     [plen], cx
        mov     word [carry], 0
        mov     word [baselo], 0
        mov     word [basehi], 0
.rd:    mov     dx, buf
        add     dx, [carry]
        mov     cx, CHUNK
        mov     bx, [fh]
        mov     ah, 3Fh
        int     21h
        jc      .nf
        mov     [nread], ax
        add     ax, [carry]
        mov     [total], ax
        cmp     ax, [plen]
        jb      .nf
        sub     ax, [plen]
        mov     dx, ax                  ; darrer inici possible
        xor     bp, bp
.sc:    mov     si, [pat]
        lea     di, [buf+bp]
        mov     cx, [plen]
        repe    cmpsb
        je      .trob
        inc     bp
        cmp     bp, dx
        jbe     .sc
        cmp     word [nread], 0
        je      .nf
        mov     cx, [plen]              ; guarda la cua per si el patro
        dec     cx                      ; queda entre dos blocs
        mov     [carry], cx
        mov     si, [total]
        sub     si, cx
        add     [baselo], si
        adc     word [basehi], 0
        add     si, buf
        mov     di, buf
        rep     movsb
        jmp     .rd
.trob:  mov     ax, bp
        xor     dx, dx
        add     ax, [baselo]
        adc     dx, [basehi]
        clc
        ret
.nf:    stc
        ret

; ---------------------------------------------------------------------
;  Preguntes
; ---------------------------------------------------------------------
pregunta:
        mov     dx, m_guia
        call    print
        xor     bx, bx
.niv:   mov     [niv], bx
.torna: mov     dx, m_nivell
        call    print
        mov     ax, [niv]
        inc     ax
        call    pdec
        mov     dx, m_obre
        call    print
        mov     bx, [niv]
        shl     bx, 1
        mov     ax, [defecte+bx]
        call    pdec
        mov     dx, m_tanca
        call    print
        call    entrada
        mov     si, inbuf+2
        call    salta_espais
        mov     bx, [niv]
        shl     bx, 1
        mov     ax, [defecte+bx]
        cmp     byte [si], 13           ; Intro: valor per defecte
        je      .desa
        call    llegeix_num
        jnc     .desa
        mov     dx, m_rang
        call    print
        jmp     .torna
.desa:  mov     bx, [niv]
        shl     bx, 1
        mov     [nous+bx], ax
        mov     bx, [niv]
        inc     bx
        cmp     bx, 5
        jb      .niv
        mov     dx, m_resum
        call    print
        mov     si, nous
        call    mostra_valors
        mov     dx, m_conf
        call    print
        call    entrada
        mov     al, [inbuf+2]
        and     al, 0DFh
        cmp     al, 'S'
        je      .si
        stc
        ret
.si:    clc
        ret

entrada:
        mov     byte [inbuf], 7
        mov     dx, inbuf
        mov     ah, 0Ah
        int     21h
        mov     bl, [inbuf+1]
        xor     bh, bh
        mov     byte [inbuf+2+bx], 13
        mov     dx, m_crlf
        jmp     print

; si -> 5 paraules: "t1, t2, t3, t4, t5 ms"
mostra_valors:
        mov     cx, 5
.l:     lodsw
        call    pdec
        cmp     cx, 1
        je      .f
        mov     dx, m_coma
        call    print
.f:     loop    .l
        mov     dx, m_ms
        jmp     print

; ---------------------------------------------------------------------
;  Aplica el pedac
; ---------------------------------------------------------------------
aplica:
        cmp     byte [teori], 0
        jne     .escriu
        mov     dx, nexe                ; GEM.EXE -> GEM.ORI
        mov     di, nori
        mov     ah, 56h
        int     21h
        jnc     .copia
        mov     dx, m_errren
        jmp     error
.copia: mov     dx, nori                ; GEM.ORI -> GEM.EXE nou
        mov     ax, 3D00h
        int     21h
        jc      .eesc
        mov     [fh], ax
        mov     dx, nexe
        xor     cx, cx
        mov     ah, 3Ch
        int     21h
        jc      .eesc
        mov     [fh2], ax
.cl:    mov     bx, [fh]
        mov     dx, buf
        mov     cx, CHUNK
        mov     ah, 3Fh
        int     21h
        jc      .eesc
        or      ax, ax
        jz      .cfi
        mov     cx, ax
        mov     bx, [fh2]
        mov     dx, buf
        mov     ah, 40h
        int     21h
        jc      .eesc
        cmp     ax, cx
        jne     .eesc
        jmp     .cl
.cfi:   call    tanca_fh
        mov     bx, [fh2]
        mov     ah, 3Eh
        int     21h
        mov     dx, m_creat
        call    print
.escriu:
        mov     dx, nexe
        mov     ax, 3D02h
        int     21h
        jc      .eesc
        mov     [fh], ax
        call    posiciona
        mov     bx, [fh]
        mov     dx, nous
        mov     cx, 10
        mov     ah, 40h
        int     21h
        jc      .eesc
        cmp     ax, 10
        jne     .eesc
        jmp     tanca_fh
.eesc:  mov     dx, m_erresc
        jmp     error

; ---------------------------------------------------------------------
;  Sortida
; ---------------------------------------------------------------------
print:  mov     ah, 9
        int     21h
        ret

printz: mov     si, dx
.l:     lodsb
        or      al, al
        jz      .r
        mov     dl, al
        mov     ah, 2
        int     21h
        jmp     .l
.r:     ret

pdec:   push    ax
        push    bx
        push    cx
        push    dx
        mov     bx, 10
        xor     cx, cx
.d:     xor     dx, dx
        div     bx
        push    dx
        inc     cx
        or      ax, ax
        jnz     .d
.p:     pop     dx
        add     dl, '0'
        mov     ah, 2
        int     21h
        loop    .p
        pop     dx
        pop     cx
        pop     bx
        pop     ax
        ret

; ---------------------------------------------------------------------
;  Dades
; ---------------------------------------------------------------------
patro:   dw 450, 330, 275, 220, 165     ; gl_dcrates original
defecte: dw 6000, 3000, 300, 200, 150
gemboot: db '\GEMBOOT\', 0
s_exe:   db 'GEM.EXE', 0
s_ori:   db 'GEM.ORI', 0

m_titol:  db 'GEMPATCH 0.1 - Temps de doble clic del GEM', 13, 10, '$'
m_ajuda:  db 13, 10
          db 'GEMPATCH [directori] [t1 t2 t3 t4 t5] [/D] [/R]', 13, 10, 13, 10
          db "  directori  on ‚s GEM.EXE (si no, l'actual o \GEMBOOT)", 13, 10
          db '  t1..t5     temps en ms de les 5 velocitats, sense preguntar', 13, 10
          db '  /D         aplica els valors per defecte sense preguntar', 13, 10
          db '  /R         torna a posar el GEM.EXE original (GEM.ORI)', 13, 10, 13, 10
          db 'Sense par…metres, pregunta els 5 valors.', 13, 10, '$'
m_actuals: db 'Valors actuals:  $'
m_guia:   db 13, 10
          db 'Velocitat del Desktop (1 = la m‚s lenta) i temps de doble clic:', 13, 10
          db '  1   6000 ms  emulaci¢ a m‚s del 1200%', 13, 10
          db '  2   3000 ms  emulaci¢ al 600-800%', 13, 10
          db '  3    300 ms  temps real (100%)', 13, 10
          db '  4    200 ms  temps real (100%)', 13, 10
          db '  5    150 ms  temps real (100%)', 13, 10
          db 'Emulaci¢ lenta (50%): 55-75 ms. M¡nim 55 ms (un tic del rellotge).', 13, 10
          db 'Intro = valor per defecte.', 13, 10, 13, 10, '$'
m_nivell: db 'Velocitat $'
m_obre:   db ' [$'
m_tanca:  db ']: $'
m_rang:   db 'Ha de ser un n£mero de 55 a 30000.', 13, 10, '$'
m_resum:  db 13, 10, 'Valors nous:     $'
m_conf:   db 'Aplico el canvi? (S/N) $'
m_cancel: db "No s'ha canviat res.", 13, 10, '$'
m_creat:  db 'Original desat com a GEM.ORI.', 13, 10, '$'
m_fet:    db 'GEM.EXE canviat:  $'
m_fet2:   db "Tria la velocitat al Desktop. GEMPATCH /R torna a l'original.", 13, 10, '$'
m_restaurat: db 'GEM.EXE original restaurat.', 13, 10, '$'
m_coma:   db ', $'
m_ms:     db ' ms', 13, 10, '$'
m_crlf:   db 13, 10, '$'
m_noexe:  db 'No es troba $'
m_noexe2: db 'No es troba GEM.EXE aqu¡ ni a \GEMBOOT.', 13, 10, '$'
m_noori:  db 'No hi ha GEM.ORI: no hi ha res a restaurar.', 13, 10, '$'
m_notaula: db 'No es troba la taula de doble clic en aquest GEM.EXE.', 13, 10
          db "Si ja est… canviat i no tens GEM.ORI, recupera l'original.", 13, 10, '$'
m_difmida: db 'GEM.EXE i GEM.ORI no s¢n de la mateixa versi¢.', 13, 10
          db "Fes GEMPATCH /R o esborra GEM.ORI si no ‚s l'original.", 13, 10, '$'
m_errlect: db 'Error de lectura.', 13, 10, '$'
m_erresc: db "Error d'escriptura.", 13, 10, '$'
m_errren: db 'No es pot canviar el nom de GEM.EXE.', 13, 10, '$'
m_malnum: db 'Cal posar 5 temps, de 55 a 30000 ms.', 13, 10, '$'
m_malarg: db "Par…metre incorrecte. GEMPATCH /? per a l'ajuda.", 13, 10, '$'

o_help:  db 0
o_rest:  db 0
o_def:   db 0
o_dir:   db 0
nnums:   db 0
teori:   db 0
        align 2
niv:     dw 0
fh:      dw 0
fh2:     dw 0
offlo:   dw 0
offhi:   dw 0
orilo:   dw 0
orihi:   dw 0
pat:     dw 0
plen:    dw 0
carry:   dw 0
baselo:  dw 0
basehi:  dw 0
nread:   dw 0
total:   dw 0
actuals: times 5 dw 0
nous:    times 5 dw 0
inbuf:   times 10 db 0
dir:     times 80 db 0
nexe:    times 90 db 0
nori:    times 90 db 0
buf:
