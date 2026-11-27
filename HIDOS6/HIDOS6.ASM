; =====================================================================
;  HIDOS6.ASM - el nucli de l'MS-DOS 6.22 i el COMMAND.COM a la mem•ria
;               superior en un 8086 (Amstrad PC1512), sense HMA.
;                                                         versi¢ 0.3
;
;  Sintaxi:   HIDOS6 [unitat:] [/S|/S-] [/L|/L-] [/D[:seg]|/D-] [/U]
;               (res)       aplica el peda‡ a C:\IO.SYS, o diu l'estat
;               /S          l'intŠrpret (SHELL=) a dalt (per defecte)
;               /S-         l'intŠrpret a la mem•ria convencional
;               /L          FILES, FCBS, BUFFERS... a la convencional
;               /L-         ... a dalt (per defecte)
;               /D[:seg]    les dades del DOS (5 KB) a dalt, a seg (BE00);
;                           cal UMBPC 1.3 (/D-: a baix, per defecte)
;               /U          el desf…: l'IO.SYS torna a ser l'original
;
;  Cal UMBPC.SYS (o un altre XMS que doni UMB) i, al CONFIG.SYS,
;  DOS=HIGH,UMB. Amb DOS=HIGH, l'MS-DOS 6.22 copia el codi del nucli i
;  del BIOS a l'HMA; un 8086 no en t‚ i diu "HMA no disponible". El
;  peda‡ fa que, en lloc d'aix•, el copi‹ a un bloc de mem•ria superior.
;  El que s'afegeix a l'IO.SYS ‚s a HIDOS6K.ASM.
;
;  Reconeix l'IO.SYS de l'MS-DOS 6.22 castell… (40963 bytes, A92837B5)
;  i anglŠs (40774 bytes, A7EA3BE4), amb o sense el peda‡ IOPATCH6.
;
;  Construcci¢ (BUILD.SH):
;      (vegeu BUILD.SH: HIDOS6K.ASM s'assembla per a cada IO.SYS)
;      nasm -f bin HIDOS6.ASM -o HIDOS6.COM
; =====================================================================

        cpu     8086
        org     100h

MAXF    equ     0C000h                  ; mida m…xima de l'IO.SYS
IOPB    equ     10h                     ; zona de l'IOPATCH6 (zeros a l'original)
IOPE    equ     105h
IOPC    equ     1E9h                    ; INT 12h / MOV CL,6 de l'MSLOAD
V1LEN   equ     464                     ; el que afegia HIDOS6 0.1
V2LEN   equ     752                     ; ... i la 0.2

e_      equ     8Ah
ee      equ     82h
o_      equ     95h
oo      equ     0A2h
a_      equ     85h
c_      equ     87h

; ---- taula d'un IO.SYS conegut ----------------------------------------
struc   T
.crc    resd    1
.size   resw    1                       ; mida original
.s      resw    1                       ; on comen‡a el SYSINIT al fitxer
.sz     resw    1                       ; mida del SYSINIT (i on va el blob)
.a24    resw    1                       ; "HMA no disponible" (15 bytes)
.sh     resw    1                       ; EXEC del SHELL= (6 bytes)
.szo    resw    3                       ; les 3 mides del SYSINIT
.ds     resw    1                       ; segment on es carrega MSDOS.SYS
.dsv    resw    1                       ; ... el seu valor original
.a24o   resb    15
.sho    resb    6
.t1     resw    1                       ; abans de FILES... (4 bytes)
.t2     resw    1                       ; on el SYSINIT tanca el bloc 'SD' (4 bytes)
.t1o    resb    4
.t2o    resb    4
.bi     resw    1                       ; inici del BIOS: 0070:0003 (8 bytes)
.di     resw    1                       ; crida al DOSINIT (5 bytes)
.sseg   resw    1                       ; segment del SYSINIT en arrencar
.bio    resb    8
.dio    resb    5
.blob   resw    1
.blen   resw    1
.name   resw    1
endstruc

start:  cld
        mov     dx,m_banner
        call    print
        mov     si,81h
.par:   lodsb
        cmp     al,' '
        je      .par
        cmp     al,9
        je      .par
        cmp     al,0Dh
        je      .fi
        cmp     al,'/'
        jne     .unit
        lodsb
        and     al,0DFh
        cmp     al,'U'
        jne     .s
        mov     byte [o_u],1
        jmp     short .par
.s:     cmp     al,'D'
        jne     .s0
        mov     byte [o_d],1            ; /D
        cmp     byte [si],'-'
        jne     .d1
        inc     si
        mov     byte [o_d],2            ; /D-
        jmp     .par
.d1:    cmp     byte [si],':'
        jne     .par
        inc     si
        call    hexnum
        jc      us
        cmp     ax,0A000h               ; dins la zona alta, m£ltiple de 2 KB
        jb      us
        test    ax,7Fh
        jnz     us
        mov     [o_zone],ax
        jmp     .par
.s0:    cmp     al,'L'
        jne     .s2
        mov     byte [o_l],1            ; /L
        cmp     byte [si],'-'
        jne     .par
        inc     si
        mov     byte [o_l],2            ; /L-
        jmp     short .par
.s2:    cmp     al,'S'
        jne     us
        mov     byte [o_s],1            ; /S
        cmp     byte [si],'-'
        jne     .par
        inc     si
        mov     byte [o_s],2            ; /S-
        jmp     .par
.unit:  and     al,0DFh
        cmp     al,'A'
        jb      us
        cmp     al,'Z'
        ja      us
        mov     [fname],al
        lodsb
        cmp     al,':'
        jne     us
        jmp     .par
.fi:    cmp     byte [o_u],0
        je      .rd
        mov     al,[o_s]
        or      al,[o_l]
        or      al,[o_d]
        jnz     us

; ---- llegeix l'IO.SYS --------------------------------------------------
.rd:    mov     ax,4300h
        mov     dx,fname
        int     21h
        mov     dx,m_nofile
        jc      fail
        mov     [attr],cx
        mov     ax,3D00h
        mov     dx,fname
        int     21h
        mov     dx,m_nofile
        jc      fail
        mov     bx,ax
        mov     ah,3Fh
        mov     cx,MAXF
        mov     dx,iob
        int     21h
        pushf
        push    ax
        mov     ah,3Eh
        int     21h
        pop     ax
        popf
        mov     dx,m_nofile
        jc      fail
        mov     [fsize],ax
        mov     dx,m_unk
        cmp     ax,1000h
        jb      fail2
        cmp     ax,MAXF
        jae     fail2

; ---- treu (de moment) l'IOPATCH6, si hi ‚s ----------------------------
        mov     si,iob+IOPB             ; desa la zona
        mov     di,savz
        mov     cx,IOPE-IOPB
        push    ds
        pop     es
        rep     movsb
        mov     si,iob+IOPC
        mov     di,savc
        movsw
        movsw
        mov     di,iob+IOPB             ; i hi posa el que hi ha a l'original
        mov     cx,IOPE-IOPB
        xor     al,al
        rep     stosb
        mov     word [iob+IOPC],12CDh
        mov     word [iob+IOPC+2],06B1h
        mov     si,savz                 ; hi era l'IOPATCH6?
        mov     cx,IOPE-IOPB
.z:     lodsb
        or      al,al
        jnz     .iop
        loop    .z
        jmp     short .ident
.iop:   mov     byte [iop],1

; ---- quin IO.SYS ‚s, i si porta HIDOS6 ---------------------------------
.ident: mov     bp,tabs
.t:     cmp     bp,tabs_end
        jb      .t1
        mov     dx,m_unk
        jmp     fail2
.t1:    mov     ax,[fsize]
        cmp     ax,[bp+T.size]
        je      .orig
        mov     cx,[bp+T.size]          ; amb el peda‡: mida + blob
        add     cx,[bp+T.blen]
        cmp     ax,cx
        je      .sg
        sub     cx,[bp+T.blen]          ; o el de la 0.1
        add     cx,V1LEN
        cmp     ax,cx
        je      .sg
        add     cx,V2LEN-V1LEN          ; o el de la 0.2
        cmp     ax,cx
        jne     .nx
.sg:
        mov     si,[bp+T.s]             ; signatura al final
        add     si,[bp+T.sz]
        add     si,iob
        mov     di,sig
        mov     cx,7
        repe    cmpsb
        jne     .nx
        mov     al,[si]                 ; versi¢ del format
        mov     [pver],al
        mov     al,[si+1]               ; opcions
        mov     [pflags],al
        mov     ax,[si+3]               ; zona de /D
        cmp     byte [pver],3
        jb      .sz
        mov     [pzone],ax
.sz:
        call    unpatch                 ; torna a l'original per comprovar-lo
        mov     byte [patched],1
.orig:  call    crc32
        cmp     ax,[bp+T.crc]
        jne     .bad
        cmp     dx,[bp+T.crc+2]
        je      .known
.bad:   cmp     byte [patched],0
        je      .nx
        mov     dx,m_unk                ; porta HIDOS6 per• la resta no quadra
        jmp     fail2
.nx:    add     bp,T_size
        jmp     .t

; ---- ara iob ‚s l'original (sense IOPATCH6 ni HIDOS6) ------------------
.known: cmp     byte [o_u],0
        je      .ap
        cmp     byte [patched],0        ; /U
        jne     .undo
        mov     dx,m_jaorig
        jmp     ok0
.undo:  mov     word [okmsg],m_okundo
        jmp     write

.ap:    mov     al,[pflags]             ; /S, /S-, /L, /L-: canvia l'opci¢
        cmp     byte [o_s],1
        jne     .ap1
        and     al,0FEh
.ap1:   cmp     byte [o_s],2
        jne     .ap3
        or      al,1
.ap3:   cmp     byte [o_l],1
        jne     .ap4
        or      al,2
.ap4:   cmp     byte [o_l],2
        jne     .ap5
        and     al,0FDh
.ap5:   cmp     byte [o_d],1
        jne     .ap6
        or      al,4
.ap6:   cmp     byte [o_d],2
        jne     .ap2
        and     al,0FBh
.ap2:   mov     [nflags],al
        mov     ax,[pzone]
        cmp     word [o_zone],0
        je      .ap7
        mov     ax,[o_zone]
.ap7:   mov     [nzone],ax
        cmp     byte [patched],0
        je      .new
        cmp     byte [pver],FVER        ; ja hi ‚s, mateixa versi¢
        jne     .upd
        mov     al,[nflags]
        cmp     al,[pflags]
        jne     .chg
        mov     ax,[nzone]
        cmp     ax,[pzone]
        jne     .chg
        call    status                  ; res a canviar: l'estat
        mov     dx,m_ja
        jmp     ok0
.chg:   mov     word [okmsg],m_okchg
        jmp     short .doit
.upd:   mov     word [okmsg],m_okupd
        jmp     short .doit
.new:   mov     word [okmsg],m_okpatch
.doit:  call    patch
        call    status
        jmp     write

; ---- unpatch: treu HIDOS6 de iob (BP = taula) ----------------------------
unpatch:
        push    ds
        pop     es
        mov     si,bp                   ; els 15 bytes de "HMA no disponible"
        add     si,T.a24o
        mov     di,[bp+T.a24]
        add     di,iob
        mov     cx,15
        rep     movsb
        mov     si,bp                   ; l'EXEC del SHELL=
        add     si,T.sho
        mov     di,[bp+T.sh]
        add     di,iob
        mov     cx,6
        rep     movsb
        mov     si,bp                   ; les taules (la 0.1 no les tocava,
        add     si,T.t1o                ; per• ‚s el mateix)
        mov     di,[bp+T.t1]
        add     di,iob
        movsw
        movsw
        mov     si,bp
        add     si,T.t2o
        mov     di,[bp+T.t2]
        add     di,iob
        movsw
        movsw
        mov     si,bp                   ; el BIOS i el DOSINIT
        add     si,T.bio
        mov     di,[bp+T.bi]
        add     di,iob
        mov     cx,8
        rep     movsb
        mov     si,bp
        add     si,T.dio
        mov     di,[bp+T.di]
        add     di,iob
        mov     cx,5
        rep     movsb
        mov     ax,[bp+T.sz]            ; les mides
        call    setsz
        mov     di,[bp+T.ds]
        mov     ax,[bp+T.dsv]
        mov     [iob+di],ax
        mov     ax,[bp+T.size]
        mov     [fsize],ax
        ret

setsz:  mov     di,[bp+T.szo]
        mov     [iob+di],ax
        mov     di,[bp+T.szo+2]
        mov     [iob+di],ax
        mov     di,[bp+T.szo+4]
        mov     [iob+di],ax
        ret

; ---- patch: posa HIDOS6 a iob (original), amb les opcions nflags ---------
patch:  push    ds
        pop     es
        mov     di,[bp+T.s]             ; el blob, al final
        add     di,[bp+T.sz]
        add     di,iob
        mov     si,[bp+T.blob]
        mov     cx,[bp+T.blen]
        mov     bx,di
        rep     movsb
        mov     al,[nflags]
        mov     [bx+8],al
        mov     ax,[nzone]
        mov     [bx+0Ah],ax
        mov     ax,[bp+T.size]
        add     ax,[bp+T.blen]
        mov     [fsize],ax
        mov     ax,[bp+T.sz]            ; el SYSINIT creix
        add     ax,[bp+T.blen]
        call    setsz
        mov     ax,[bp+T.blen]          ; i el MSDOS.SYS es carrega m‚s amunt
        mov     cl,4
        shr     ax,cl
        add     ax,[bp+T.dsv]
        mov     di,[bp+T.ds]
        mov     [iob+di],ax
        mov     di,[bp+T.a24]           ; CALL blob+10h i NOPs
        add     di,iob
        mov     ax,[bp+T.sz]
        add     ax,10h
        mov     dx,[bp+T.a24]
        sub     dx,[bp+T.s]
        call    callnop
        mov     cx,12
        mov     al,90h
        rep     stosb
        mov     di,[bp+T.sh]            ; CALL blob+13h i NOPs
        add     di,iob
        mov     ax,[bp+T.sz]
        add     ax,13h
        mov     dx,[bp+T.sh]
        sub     dx,[bp+T.s]
        call    callnop
        mov     cx,3
        mov     al,90h
        rep     stosb
        mov     di,[bp+T.t1]            ; CALL blob+16h i NOP
        add     di,iob
        mov     ax,[bp+T.sz]
        add     ax,16h
        mov     dx,[bp+T.t1]
        sub     dx,[bp+T.s]
        call    callnop
        mov     al,90h
        stosb
        mov     di,[bp+T.t2]            ; CALL blob+19h i NOP
        add     di,iob
        mov     ax,[bp+T.sz]
        add     ax,19h
        mov     dx,[bp+T.t2]
        sub     dx,[bp+T.s]
        call    callnop
        mov     al,90h
        stosb
        mov     di,[bp+T.di]            ; CALL blob+1Fh i 2 NOPs
        add     di,iob
        mov     ax,[bp+T.sz]
        add     ax,1Fh
        mov     dx,[bp+T.di]
        sub     dx,[bp+T.s]
        call    callnop
        mov     ax,9090h
        stosw
        mov     di,[bp+T.bi]            ; CALL FAR SYSINIT:blob+1Ch i 3 NOPs
        add     di,iob
        mov     al,9Ah
        stosb
        mov     ax,[bp+T.sz]
        add     ax,1Ch
        stosw
        mov     ax,[bp+T.sseg]
        stosw
        mov     al,90h
        stosb
        stosb
        stosb
        ret
; escriu a ES:DI un CALL des de l'offset DX del SYSINIT fins a AX
callnop:
        sub     ax,dx
        sub     ax,3
        push    ax
        mov     al,0E8h
        stosb
        pop     ax
        stosw
        ret

; ---- status: l'estat del peda‡ que hi haur… -----------------------------
status: mov     dx,m_st1
        call    print
        mov     dx,[bp+T.name]
        call    print
        mov     dx,m_iop
        cmp     byte [iop],0
        jne     .p
        mov     dx,m_noiop
.p:     call    print
        mov     dx,m_shhi
        test    byte [nflags],1
        jz      .q
        mov     dx,m_shlo
.q:     call    print
        mov     dx,m_tbhi
        test    byte [nflags],2
        jz      .r
        mov     dx,m_tblo
.r:     call    print
        mov     dx,m_dlo
        test    byte [nflags],4
        jz      .d
        mov     ax,[nzone]
        mov     di,m_dseg
        call    hex4
        mov     dx,m_dhi
.d:     jmp     print

; ---- hexnum: n£mero hexadecimal de DS:SI a AX (CF=1 si cap xifra) --------
hexnum: xor     dx,dx
        xor     cx,cx
.h1:    lodsb
        cmp     al,'0'
        jb      .h9
        cmp     al,'9'
        jbe     .hd
        and     al,0DFh
        cmp     al,'A'
        jb      .h9
        cmp     al,'F'
        ja      .h9
        sub     al,7
.hd:    sub     al,'0'
        push    cx
        mov     cl,4
        shl     dx,cl
        pop     cx
        or      dl,al
        inc     cx
        jmp     short .h1
.h9:    dec     si
        mov     ax,dx
        cmp     cx,1
        ret                             ; CF=1 si CX=0
; ---- hex4: AX en 4 xifres hexadecimals a DS:DI ----------------------------
hex4:   mov     cx,4
.x1:    push    cx
        mov     cl,4
        rol     ax,cl
        pop     cx
        push    ax
        and     al,0Fh
        add     al,'0'
        cmp     al,'9'
        jbe     .x2
        add     al,7
.x2:    mov     [di],al
        inc     di
        pop     ax
        loop    .x1
        ret

; ---- escriu l'IO.SYS ---------------------------------------------------
write:  mov     si,savz                 ; torna a posar l'IOPATCH6
        mov     di,iob+IOPB
        mov     cx,IOPE-IOPB
        push    ds
        pop     es
        rep     movsb
        mov     si,savc
        mov     di,iob+IOPC
        movsw
        movsw
        mov     ax,4301h
        xor     cx,cx
        mov     dx,fname
        int     21h
        mov     dx,m_attr
        jc      fail3
        mov     ax,3D02h                ; el mateix fitxer: el principi no es mou
        mov     dx,fname
        int     21h
        mov     dx,m_open
        jc      .rest
        mov     bx,ax
        mov     ah,40h
        mov     cx,[fsize]
        mov     dx,iob
        int     21h
        mov     dx,m_werr
        jc      .cls
        cmp     ax,[fsize]
        jne     .cls
        mov     ah,40h                  ; talla el que sobri (/U)
        xor     cx,cx
        int     21h
        jc      .cls
        mov     ah,3Eh
        int     21h
        jc      .rest
        call    rattr
        mov     dx,[okmsg]
        jmp     short ok0
.cls:   push    dx
        mov     ah,3Eh
        int     21h
        pop     dx
.rest:  push    dx
        call    rattr
        pop     dx
fail3:  mov     byte [ecode],3
        jmp     short fail

rattr:  mov     ax,4301h
        mov     cx,[attr]
        mov     dx,fname
        int     21h
        ret

fail2:  mov     byte [ecode],2
        jmp     short fail
ok0:    mov     byte [ecode],0
fail:   call    print
        mov     al,[ecode]
        mov     ah,4Ch
        int     21h
us:     mov     dx,m_us
        jmp     short fail
print:  mov     ah,9
        int     21h
        ret

; ---- crc32 de iob (fsize bytes): DX:AX -----------------------------------
crc32:  mov     si,iob
        mov     cx,[fsize]
        mov     ax,0FFFFh
        mov     dx,ax
.b:     xor     al,[si]
        inc     si
        mov     bl,8
.bit:   shr     dx,1
        rcr     ax,1
        jnc     .z
        xor     dx,0EDB8h
        xor     ax,8320h
.z:     dec     bl
        jnz     .bit
        loop    .b
        not     ax
        not     dx
        ret

; ---- IO.SYS coneguts -------------------------------------------------------
tabs:
t_es:   dd      0A92837B5h
        dw      40963, 45E3h, 5A20h, 5007h, 4EC9h
        dw      4A8Ah, 4AA0h, 4ABBh, 1F96h, 0A16h
        db      0Eh,1Fh,0B4h,09h,0BAh,0C0h,09h,0CDh,21h,0BBh,01h,00h,0E8h,46h,00h
        db      0B8h,00h,4Bh,0F9h,0CDh,21h
        dw      5419h, 579Ah
        db      2Eh,0A0h,0A9h,02h, 8Bh,1Eh,6Eh,03h
        dw      22B3h, 4B23h, 0474h
        db      81h,0C7h,70h,00h,89h,3Eh,03h,00h, 2Eh,0FFh,1Eh,7Bh,02h
        dw      k_es, K_ES_LEN, n_es
t_en:   dd      0A7EA3BE4h
        dw      40774, 45D6h, 5970h, 4FE5h, 4EB2h
        dw      4A73h, 4A89h, 4AA4h, 1F99h, 0A0Ah
        db      0Eh,1Fh,0B4h,09h,0BAh,0B6h,09h,0CDh,21h,0BBh,01h,00h,0E8h,46h,00h
        db      0B8h,00h,4Bh,0F9h,0CDh,21h
        dw      53F7h, 5778h
        db      2Eh,0A0h,9Fh,02h, 8Bh,1Eh,64h,03h
        dw      22B6h, 4B0Ch, 0473h
        db      81h,0C7h,70h,00h,89h,3Eh,03h,00h, 2Eh,0FFh,1Eh,71h,02h
        dw      k_en, K_EN_LEN, n_en
tabs_end:
%if t_en-t_es != T_size
  %error "taula mal feta"
%endif

k_es:   incbin  'K_ES.BIN'
K_ES_LEN equ    $-k_es
k_en:   incbin  'K_EN.BIN'
K_EN_LEN equ    $-k_en
FVER    equ     3                       ; versi¢ del format (byte 7 del blob)

; ---- dades ---------------------------------------------------------------
fname   db      'C:\IO.SYS',0
sig     db      'HIDOS6',0
o_u     db      0
o_s     db      0
o_l     db      0
o_d     db      0
o_zone  dw      0
pzone   dw      0BE00h
nzone   dw      0
iop     db      0
patched db      0
pver    db      0
pflags  db      0
nflags  db      0
ecode   db      1
attr    dw      0
fsize   dw      0
okmsg   dw      0

n_es    db      'MS-DOS 6.22 castell',a_,'$'
n_en    db      'MS-DOS 6.22 angl',e_,'s$'
m_banner db     'HIDOS6 0.3 - el nucli de l',39,'MS-DOS 6.22 i el COMMAND.COM a la mem',oo,'ria superior',13,10,'$'
m_us    db      'Sintaxi: HIDOS6 [unitat:] [/S|/S-] [/L|/L-] [/D[:seg]|/D-] [/U]',13,10
        db      '  /S   l',39,'int',e_,'rpret (SHELL=) a la mem',oo,'ria superior (per defecte)',13,10
        db      '  /S-  l',39,'int',e_,'rpret a la mem',oo,'ria convencional',13,10
        db      '  /L   FILES, FCBS, BUFFERS i LASTDRIVE a la mem',oo,'ria convencional',13,10
        db      '  /L-  ... a la mem',oo,'ria superior (per defecte)',13,10
        db      '  /D   les dades del DOS (5 KB) a dalt, a BE00 (/D:seg: a seg); cal UMBPC 1.3',13,10
        db      '  /D-  les dades del DOS a la mem',oo,'ria convencional (per defecte)',13,10
        db      '  /U   desf',a_,' el peda',c_,' (torna a l',39,'IO.SYS original)',13,10
        db      'Cal UMBPC.SYS i DOS=HIGH,UMB al CONFIG.SYS.',13,10,'$'
m_nofile db     'No trobo (o no puc llegir) \IO.SYS en aquesta unitat.',13,10,'$'
m_unk   db      'Aquest IO.SYS no ',ee,'s cap dels coneguts (6.22 castell',a_,' o angl',e_,'s,',13,10
        db      'amb IOPATCH6 o sense). No he tocat res.',13,10,'$'
m_attr  db      'No puc canviar els atributs de l',39,'IO.SYS. No he tocat res.',13,10,'$'
m_open  db      'No puc obrir l',39,'IO.SYS per escriure-hi. No he tocat res.',13,10,'$'
m_werr  db      'ERROR en escriure l',39,'IO.SYS! Restaura la c',oo,'pia del disc.',13,10,'$'
m_ja    db      'El peda',c_,' ja hi era. No cal fer res.',13,10,'$'
m_jaorig db     'L',39,'IO.SYS ja ',ee,'s l',39,'original. No cal fer res.',13,10,'$'
m_okpatch db    'Peda',c_,' aplicat. Posa DOS=HIGH,UMB al CONFIG.SYS i reinicia.',13,10,'$'
m_okchg db      'Opci',oo,' canviada. Reinicia perqu',e_,' tingui efecte.',13,10,'$'
m_okupd db      'Peda',c_,' actualitzat. Reinicia.',13,10,'$'
m_okundo db     'Peda',c_,' desfet: l',39,'IO.SYS torna a ser l',39,'original',13,10
        db      '(si hi havia l',39,'IOPATCH6, el conserva). Pots treure DOS=HIGH.',13,10,'$'
m_st1   db      '  IO.SYS: $'
m_iop   db      ', amb IOPATCH6',13,10,'$'
m_noiop db      13,10,'$'
m_shhi  db      '  Int',e_,'rpret (SHELL=): a la mem',oo,'ria superior (/S)',13,10,'$'
m_shlo  db      '  Int',e_,'rpret (SHELL=): a la mem',oo,'ria convencional (/S-)',13,10,'$'
m_tbhi  db      '  FILES, FCBS, BUFFERS, LASTDRIVE: a la mem',oo,'ria superior (/L-)',13,10,'$'
m_dhi   db      '  Dades del DOS: a la mem',oo,'ria superior, a '
m_dseg  db      '0000 (/D; cal UMBPC 1.3)',13,10,'$'
m_dlo   db      '  Dades del DOS: a la mem',oo,'ria convencional (/D-)',13,10,'$'
m_tblo  db      '  FILES, FCBS, BUFFERS, LASTDRIVE: a la mem',oo,'ria convencional (/L)',13,10,'$'

savz    times IOPE-IOPB db 0
savc    dd      0

        align   16
iob:
%if (iob-$$+100h+MAXF) > 0FF00h
  %error "massa mem•ria"
%endif
