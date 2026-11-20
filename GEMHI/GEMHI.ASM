; =====================================================================
;  GEMHI.ASM - Engega el GEM i li posa a la memoria alta el que carrega
;              en arrencar (AMSTRAD.SYS, accessoris, GEM.RSC...)
;              MS-DOS 3.20 o posterior, Amstrad PC1512.   Versio 0.3
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

int21:  cmp     ah, 48h
        je      .alloc
        cmp     ah, 4Ch
        je      .term
        cmp     ah, 4Bh
        jne     .chain
        cmp     al, 1                   ; EXEC (4B00h, 4B01h)
        ja      .chain
        cmp     byte [cs:fase], 0
        je      .chain
        inc     byte [cs:nexec]         ; 1r: GEMVDI -> GEM.EXE
        cmp     byte [cs:nexec], 2      ; 2n: el GEM engega l'escriptori
        jb      .chain
        mov     byte [cs:fase], 0
.chain: jmp     far [cs:old21]

.alloc: cmp     byte [cs:fase], 0
        je      .chain
        cmp     bx, MAXPAR              ; consultes (FFFFh) i blocs grans:
        jae     .chain                  ;   com sempre
        or      bx, bx
        jz      .chain
        mov     [cs:sv_bx], bx
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

; acaba un programa: si es GEMVDI carregat a dalt per GEMHI copiat a
; dalt, treu el ganxo i diu l'informe (despres el DOS ho allibera tot)
.term:  cmp     word [cs:gvpsp], 0
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
t_us    db      'GEMHI 0.3 - Engega el GEM amb el que carrega en arrencar a la', 13, 10
        db      'mem', 95h, 'ria alta (cal una zona alta enlla', 87h, 'ada: LOADHI /H).', 13, 10, 13, 10
        db      0E9h, 's:  GEMHI programa [par', 85h, 'metres]      p. ex.  GEMHI GEMVDI', 13, 10, '$'
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
