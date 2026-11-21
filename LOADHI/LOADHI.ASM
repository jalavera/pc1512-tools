;  LOADHI.ASM  -  carrega programes a la mem•ria superior amb MS-DOS 3.x
;                                                               versi¢ 0.20
;  és:  LOADHI [@fitxer] [/H:inici[-final]] [/F] [/B:n] [/FILES:n] [/C]
;              [/R:n] [/RB:n] [/RC:n] [programa [par…metres]]
;
;  Funcionament
;  - La primera vegada (despr‚s d'arrencar) crea una zona de mem•ria
;    superior a partir de /H:inici i l'enlla‡a a la cadena de blocs de
;    DOS, com fa DOS 5 amb DOS=UMB:
;      ... [£ltim bloc convencional, un par…graf m‚s curt]
;      [bloc de sistema 'SC', propietari 0008h, tapa v¡deo i ROM]
;      [zona alta: blocs normals de DOS] 'Z'
;  - Per carregar un programa, posa temporalment a nom de LOADHI tots
;    els blocs lliures de la mem•ria convencional i fa EXEC: DOS nom‚s
;    troba lloc a dalt i hi posa l'entorn i el programa. En tornar, els
;    blocs convencionals tornen a quedar lliures. Si el programa queda
;    resident, es queda a dalt amb el seu bloc i el seu entorn, i MEM el
;    veu amb nom, adre‡a i mida.
;  - Si la cadena de DOS no arriba a la zona (p. ex. despr‚s d'un
;    reinici en calent), el que hi hagi a dalt s¢n restes d'abans i la
;    zona es torna a crear.
;
;  Compilar:  nasm -f bin LOADHI.ASM -o LOADHI.COM
;  Nom‚s instruccions 8086.

        cpu     8086
        org     100h

; TRACE: lletra amb la BIOS (versi¢ de prova LOADHIT)
%macro TSTEP 1
%ifdef TRACE
        pushf
        push    ax
        push    bx
        mov     ax,0E00h+%1
        mov     bx,7
        int     10h
        pop     bx
        pop     ax
        popf
%endif
%endmacro
%macro TDIG 1
%ifdef TRACE
        pushf
        push    ax
        push    bx
        mov     al,[cs:%1]
        add     al,'0'
        mov     ah,0Eh
        mov     bx,7
        int     10h
        pop     bx
        pop     ax
        popf
%endif
%endmacro

CR      equ     13
LF      equ     10
MAXBLK  equ     100                     ; blocs convencionals que es tapen
UBASE   equ     0BC00h                  ; on comen‡a la mem•ria superior:
                                        ; per sota, convencional (el v¡deo
                                        ; CGA del PC1512 ‚s a B800-BBFF)
UTOP    equ     0FE00h                  ; fins on pot arribar la zona (la
                                        ; prova de RAM s'atura abans a la ROM)
MAXR    equ     4                       ; trossos de la zona alta
SBLK    equ     16                      ; blocs que tapa el stub (/C)

start:  cld
        mov     sp,stk_top
        mov     di,bss_start            ; DOS no posa la mem•ria a zero
        mov     cx,bss_end-bss_start
        xor     al,al
        rep     stosb
        mov     ah,30h
        int     21h
        mov     [dosver],ax
        cmp     al,3
        jb      .badv
        cmp     al,4
        jbe     .v1
.badv:  mov     dx,m_badver
        jmp     fail
.v1:    mov     ax,3524h                ; errors cr¡tics: els diu LOADHI
        int     21h
        mov     [o24],bx
        mov     [o24+2],es
        push    cs
        pop     es
        mov     dx,int24
        mov     ax,2524h
        int     21h
        mov     ax,4452h                ; DR DOS / DOS Plus?
        stc
        int     21h
        jc      .v2
        mov     dx,m_drdos
        jmp     fail
.v2:    mov     bx,stk_top              ; deixa nom‚s el que cal
        add     bx,15
        mov     cl,4
        shr     bx,cl
        mov     ah,4Ah
        int     21h
        int     12h
        mov     cl,6
        shl     ax,cl
        mov     [convtop],ax
        TSTEP   '<'
        call    parse
        TSTEP   'C'
        TDIG    o_c
        TSTEP   'V'
        TDIG    st_v
        TSTEP   ' '
        call    walk
        jnc     .w1
        mov     dx,m_broken
        jmp     fail
.w1:    cmp     word [astart],0
        jne     .have
        cmp     byte [o_h],0
        jne     .mk
        cmp     byte [prog],0
        je      .noz
        mov     dx,m_nozone
        jmp     fail
.noz:   mov     dx,m_nozone
        jmp     fail
.mk:    call    first_prog              ; nom‚s com a SHELL= del CONFIG.SYS
        jnc     .mk1
        mov     dx,m_notfirst
        jmp     fail
.mk1:   mov     byte [isshell],1        ; si falla, l'intŠrpret igualment
        mov     byte [o_r],0            ; /R: a la l¡nia SHELL= no fa res
        call    make_zone
        TSTEP   '1'
.zdone: call    walk
        call    regions
        mov     bx,o_rb                 ; /RB i /RC: el tros ha d'existir
        call    chk_reg
        mov     bx,o_rc
        call    chk_reg
        call    add_buffers
        call    add_files
        TSTEP   '2'
        cmp     byte [prog],0
        jne     .shell
        mov     dx,m_noshell            ; com a SHELL= cal l'intŠrpret
        jmp     fail
.shell: call    find_prog               ; l'intŠrpret, a baix
        TSTEP   '3'
        jnc     .sh1
        mov     dx,m_notfound
        call    puts
        mov     dx,prog
        call    putz
        mov     dx,m_crlf
        jmp     fail
.sh1:   cmp     byte [o_c],0
        je      .sh2
        call    shell_size              ; espai per a COMMAND a dalt
        call    shell_reg               ; /RC:n: el bloc del tros n
.sh2:   TSTEP   '4'
        TDIG    st_hi
        jmp     shell_go
.have:  mov     al,[o_c]                ; /C /B /FILES: nom‚s com a SHELL=
        or      al,[o_buf]
        or      al,[o_files]
        or      al,[o_rb]
        or      al,[o_rc]
        jz      .hv1
        call    first_prog              ; la zona ja hi ‚s (la fa el DOS:
        jc      .hv0                    ;   HIDOS) i som el SHELL=: /C,
        mov     byte [isshell],1        ;   /B i /FILES s¡ que valen
        mov     byte [o_r],0
        jmp     .zdone
.hv0:   mov     dx,m_shonly
        jmp     fail
.hv1:   cmp     byte [o_h],0
        je      .go
        mov     ax,[rs]
        cmp     ax,[astart]
        je      .go
        mov     dx,m_already
        call    puts
        mov     ax,[astart]
        call    phex4
        mov     dx,m_already2
        call    puts
.go:    cmp     byte [prog],0
        jne     .load
        call    status
        mov     ax,4C00h
        int     21h
.load:  call    find_prog
        jnc     .found
        mov     dx,m_notfound
        call    puts
        mov     dx,prog
        call    putz
        mov     dx,m_crlf
        jmp     fail
.found: cmp     byte [o_r],0            ; /R:n: el tros n ha d'existir
        je      .f1
        call    regions
        mov     al,[o_r]
        call    selreg
        jnc     .f1
        mov     dx,m_noreg
        call    puts
        mov     ax,[nr]
        call    pdec
        mov     dx,m_noreg2             ; " tros." / " trossos."
        cmp     ax,1
        jne     .fr
        mov     dx,m_noreg1
.fr:    jmp     fail
.f1:    call    build_pb
        call    kids_snap               ; fills d'altres LOADHI d'abans
        call    block_low
        call    do_exec
        pushf
        push    ax
        call    unblock
        pop     ax
        popf
        jnc     .ok
        cmp     ax,8                    ; no hi cap
        jne     .xerr
        cmp     byte [o_r],0
        je      .lo
        mov     dx,m_rlow               ; "No hi cap al tros n: ..."
        call    puts
        mov     al,[o_r]
        xor     ah,ah
        call    pdec
        mov     dx,m_rlow2
        jmp     short .lo1
.lo:    mov     dx,m_low
.lo1:   call    puts
        call    do_exec
        jnc     .ok
.xerr:  mov     dx,m_xerr
        cmp     ax,11
        jne     .xe2
        mov     dx,m_badfmt
.xe2:   jmp     fail
.ok:    call    name_child
        mov     ah,4Dh
        int     21h
        mov     ah,4Ch
        int     21h

; DX = missatge d'error -> el mostra i surt amb ERRORLEVEL 1
fail:   call    puts
        cmp     byte [isshell],0        ; com a SHELL=: no deixa el PC
        je      .x                      ; sense intŠrpret, el carrega a baix
        mov     byte [isshell],0
        cmp     byte [prog],0
        je      .x
        mov     dx,m_rescue
        call    puts
        mov     sp,stk_top
        mov     byte [o_c],0
        mov     byte [st_hi],0
        call    find_prog
        jc      .x
        jmp     shell_go
.x:     mov     ax,4C01h
        int     21h

; =====================================================================
;  L¡nia d'ordres
; =====================================================================
parse:  mov     si,81h
        call    skipsp
        cmp     al,'@'                  ; @fitxer: opcions en un fitxer
        jne     .sk
        call    readcfg
.sk:    call    skipsp
        cmp     al,'/'
        jne     .prog
        inc     si
        cmp     byte [si],'?'
        je      .help
        call    getword                 ; paraula de l'opci¢ -> optw
        mov     di,w_f
        call    wcmp
        jne     .c
        mov     byte [o_f],1
        jmp     .sk
.c:     mov     di,w_v
        call    wcmp
        jne     .c0
        mov     byte [st_v],1           ; (a la plantilla del stub)
        jmp     .sk
.c0:    mov     di,w_c
        call    wcmp
        jne     .b
        mov     byte [o_c],1
        jmp     .sk
.b:     mov     di,w_b
        call    wcmp
        je      .b1
        mov     di,w_buffers
        call    wcmp
        jne     .fl
.b1:    call    getnum
        jc      .bad
        mov     [o_buf],ax
        jmp     .sk
.fl:    mov     di,w_files
        call    wcmp
        jne     .h
        call    getnum
        jc      .bad
        mov     [o_files],ax
        jmp     .sk
.h:     mov     di,w_h
        call    wcmp
        jne     .r
        lodsb
        cmp     al,':'
        je      .h1
        cmp     al,'='
        jne     .bad
.h1:    mov     byte [o_h],1
.h2:    cmp     word [nr],MAXR          ; trossos: ini[-fi][,ini[-fi]]...
        jae     .bad
        call    gethex
        jc      .bad
        mov     bx,[nr]
        shl     bx,1
        mov     [rs+bx],ax
        mov     word [re+bx],0
        inc     word [nr]
        cmp     byte [si],'-'
        jne     .h3
        inc     si
        call    gethex
        jc      .bad
        inc     ax                      ; final inclusiu -> exclusiu
        jz      .bad
        mov     bx,[nr]
        dec     bx
        shl     bx,1
        mov     [re+bx],ax
.h3:    cmp     byte [si],','
        jne     .h4
        inc     si
        jmp     .h2
.h4:    jmp     .sk
.r:     mov     bx,o_r                  ; /R:n: el tros on es carrega
        mov     di,w_r
        call    wcmp
        je      .rn
        mov     bx,o_rb                 ; /RB:n: BUFFERS i FILES
        mov     di,w_rb
        call    wcmp
        je      .rn
        mov     bx,o_rc                 ; /RC:n: COMMAND.COM (/C)
        mov     di,w_rc
        call    wcmp
        jne     .bad
.rn:    push    bx
        call    getnum
        pop     bx
        jc      .bad
        or      ax,ax
        jz      .bad
        cmp     ax,MAXR
        ja      .bad
        mov     [bx],al
        jmp     .sk
.bad:   mov     dx,m_badopt
        jmp     fail
.help:  mov     dx,m_help
        call    puts
        mov     ax,4C00h
        int     21h
.prog:  cmp     al,CR
        je      .done
        mov     di,prog
        mov     cx,79
.p1:    lodsb
        cmp     al,' '
        je      .pe
        cmp     al,9
        je      .pe
        cmp     al,CR
        je      .pe
        call    upcase
        stosb
        loop    .p1
.pe:    dec     si
        mov     byte [di],0
        mov     di,tail+1               ; cua: tot el que queda, amb
        xor     cx,cx                   ; l'espai del principi
.t1:    lodsb
        cmp     al,CR
        je      .te
        cmp     cx,126
        jae     .te
        stosb
        inc     cx
        jmp     .t1
.te:    mov     byte [di],CR
        mov     [tail],cl
.done:  ret

; SI -> '@fitxer'. Llegeix el fitxer (fins a 2000 bytes) a cfgbuf, amb
; els salts de l¡nia com a espais i sense els comentaris (';' fins al
; final de la l¡nia), i hi deixa SI. Cal perquŠ a MS-DOS 2.x - 4.x la
; l¡nia SHELL= no pot passar de 31 car…cters de par…metres.
readcfg:
        inc     si
        mov     di,cfgname
        mov     cx,79
.n:     lodsb
        cmp     al,' '
        jbe     .ne
        stosb
        loop    .n
.ne:    mov     byte [di],0
        mov     dx,cfgname
        mov     ax,3D00h
        int     21h
        jc      .err
        mov     bx,ax
        mov     dx,cfgbuf
        mov     cx,2001
        mov     ah,3Fh
        int     21h
        pushf
        push    ax
        mov     ah,3Eh
        int     21h
        pop     cx
        popf
        jc      .err
        cmp     cx,2000                 ; massa llarg: no es talla, es diu
        jbe     .ok
        mov     dx,m_cfgbig
        jmp     fail
.ok:
        mov     si,cfgbuf
        mov     di,si
        xor     dl,dl                   ; dins un comentari
.c:     jcxz    .ce
        dec     cx
        lodsb
        cmp     al,1Ah                  ; Ctrl+Z
        je      .ce
        cmp     al,CR
        je      .sp
        cmp     al,LF
        je      .sp
        cmp     al,';'
        jne     .c1
        mov     dl,1
.c1:    or      dl,dl
        jnz     .c
        cmp     al,9
        jne     .st
        mov     al,' '
.st:    stosb
        jmp     .c
.sp:    xor     dl,dl
        mov     al,' '
        stosb
        jmp     .c
.ce:    mov     al,CR
        stosb
        mov     si,cfgbuf
        ret
.err:   mov     dx,m_nocfg
        call    puts
        mov     dx,cfgname
        call    putz
        mov     dx,m_crlf
        jmp     fail

; SI -> lletres de l'opci¢ (fins a 8) a optw, en maj£scules
getword:
        mov     di,optw
        mov     cx,8
.l:     mov     al,[si]
        call    upcase
        cmp     al,'A'
        jb      .e
        cmp     al,'Z'
        ja      .e
        stosb
        inc     si
        loop    .l
.e:     mov     byte [di],0
        ret

; DI = paraula (acabada en 0). ZF=1 si ‚s igual que optw
wcmp:   push    si
        mov     si,optw
.l:     lodsb
        cmp     al,[di]
        jne     .x
        inc     di
        or      al,al
        jnz     .l
.x:     pop     si
        ret

; SI -> ':' o '=' i un n£mero decimal (0-255) -> AX. CF error
getnum: lodsb
        cmp     al,':'
        je      .n
        cmp     al,'='
        jne     .bad
.n:     xor     ax,ax
        xor     cx,cx
.l:     mov     bl,[si]
        sub     bl,'0'
        jb      .e
        cmp     bl,9
        ja      .e
        mov     dx,10
        mul     dx
        xor     bh,bh
        add     ax,bx
        cmp     ax,255
        ja      .bad
        inc     si
        inc     cx
        jmp     .l
.e:     jcxz    .bad
        clc
        ret
.bad:   stc
        ret

; SI -> AL primer car…cter no blanc (SI hi apunta)
skipsp: lodsb
        cmp     al,' '
        je      skipsp
        cmp     al,9
        je      skipsp
        dec     si
        ret

upcase: cmp     al,'a'
        jb      .x
        cmp     al,'z'
        ja      .x
        sub     al,20h
.x:     ret

; SI -> AX valor hexadecimal (4 xifres = segment, 5 = adre‡a). CF error
gethex: xor     bx,bx
        xor     dx,dx
        xor     cx,cx
.l:     mov     al,[si]
        call    upcase
        cmp     al,'0'
        jb      .e
        cmp     al,'9'
        jbe     .d
        cmp     al,'A'
        jb      .e
        cmp     al,'F'
        ja      .e
        sub     al,7
.d:     sub     al,'0'
        cmp     cx,5
        jae     .bad
        push    cx
        mov     cl,4                    ; DX:BX = DX:BX*16 + AL
.s:     shl     bx,1
        rcl     dx,1
        dec     cl
        jnz     .s
        pop     cx
        xor     ah,ah
        or      bl,al
        inc     cx
        inc     si
        jmp     .l
.e:     jcxz    .bad
        mov     ax,bx
        cmp     cx,5
        jb      .ok
        mov     cl,4                    ; adre‡a -> segment
.s2:    shr     dx,1
        rcr     ax,1
        dec     cl
        jnz     .s2
.ok:    clc
        ret
.bad:   stc
        ret

; =====================================================================
;  Cadena de blocs de mem•ria
; =====================================================================
; Recorre la cadena. Deixa:
;   [zlast]  £ltim bloc abans de la zona alta (o el 'Z' si no n'hi ha)
;   [astart] primer bloc a partir de UBASE (0 = cap)
;   [aend]   final de la zona alta (par…graf, exclusiu)
; CF=1 si la cadena est… trencada.
walk:   push    es
        mov     ah,52h
        int     21h
        mov     ax,[es:bx-2]
        mov     word [astart],0
        mov     cx,4000
.l:     mov     es,ax
        mov     bl,[es:0]
        cmp     bl,'M'
        je      .s
        cmp     bl,'Z'
        jne     .bad
.s:     cmp     ax,UBASE
        jb      .low
        cmp     word [astart],0
        jne     .n
        mov     [astart],ax
        jmp     short .n
.low:   mov     [zlast],ax
.n:     mov     dx,ax
        add     dx,[es:3]
        jc      .bad
        inc     dx
        jz      .ze
        cmp     bl,'Z'
        je      .z
        mov     ax,dx
        loop    .l
.bad:   pop     es
        stc
        ret
.ze:    cmp     bl,'Z'
        jne     .bad
.z:     mov     [aend],dx
        pop     es
        clc
        ret

; CF=0 si LOADHI ‚s el primer programa (no hi ha cap altre PSP a la
; cadena): ‚s el SHELL= del CONFIG.SYS i COMMAND.COM encara no hi ‚s.
first_prog:
        push    es
        mov     ah,52h
        int     21h
        mov     ax,[es:bx-2]
        mov     cx,4000
.l:     mov     es,ax
        mov     dx,ax
        inc     dx
        cmp     [es:1],dx               ; bloc d'un programa?
        jne     .n
        mov     bx,cs
        cmp     dx,bx                   ; (el nostre)
        je      .n
        push    es
        mov     es,dx
        cmp     word [es:0],20CDh
        pop     es
        je      .no
.n:     cmp     byte [es:0],'Z'
        je      .yes
        add     ax,[es:3]
        inc     ax
        loop    .l
.yes:   pop     es
        clc
        ret
.no:    pop     es
        stc
        ret

; Crea la zona alta [hstart, hend) i l'enlla‡a a la cadena
make_zone:
        xor     si,si                   ; SI = tros * 2
.r0:    mov     ax,[rs+si]
        cmp     ax,UBASE
        jb      .range
        cmp     ax,0C000h               ; per sota de C000: que no sigui
        jae     .r00                    ; el mirall del v¡deo (B800)
        call    vmirror
        jnc     .r00
        mov     dx,m_mirror
        jmp     fail
.r00:
        cmp     ax,UTOP
        jae     .range
        or      si,si                   ; per ordre i sense encavalcar
        jz      .r1
        cmp     ax,[re+si-2]
        jb      .range
.r1:    mov     bx,UTOP                 ; l¡mit: el tros segent o UTOP
        mov     cx,si
        add     cx,2
        shr     cx,1
        cmp     cx,[nr]
        jae     .r2
        mov     bx,[rs+si+2]
.r2:    cmp     word [re+si],0
        jne     .given
        call    auto_end                ; AX = inici, BX = l¡mit -> AX
        mov     [re+si],ax
        jmp     short .sz
.given: mov     cx,[re+si]
        cmp     cx,bx
        ja      .range
        cmp     cx,ax
        jbe     .range
.rt:    call    ramtest                 ; tot ha de ser RAM
        jc      .noram
        inc     ax
        cmp     ax,cx
        jb      .rt
.sz:    mov     ax,[re+si]
        sub     ax,[rs+si]
        cmp     ax,40h
        jae     .nx
        mov     dx,m_small
        jmp     fail
.nx:    add     si,2
        mov     ax,si
        shr     ax,1
        cmp     ax,[nr]
        jb      .r0
        call    merge_r                 ; trossos seguits -> un de sol
        jmp     short .big
.range: mov     dx,m_range
        jmp     fail
.noram: push    ax
        mov     dx,m_noram
        call    puts
        pop     ax
        call    phex4
        mov     dx,m_noram2
        jmp     fail
.big:   cmp     byte [o_f],0
        jne     .link
        call    stale_zone              ; restes d'una zona d'abans?
        jnc     .link
        xor     si,si                   ; si no, ha de ser buida
.e0:    mov     ax,[rs+si]
.e1:    call    para_empty
        jnz     .full
        inc     ax
        cmp     ax,[re+si]
        jb      .e1
        add     si,2
        mov     ax,si
        shr     ax,1
        cmp     ax,[nr]
        jb      .e0
        jmp     short .link
.full:  mov     dx,m_full
        call    puts
        call    pranges
        mov     dx,m_full2
        jmp     fail
.link:  push    es
        mov     es,[zlast]
        cmp     byte [es:0],'Z'
        jne     .nolast
        cmp     word [es:1],0
        jne     .nolast
        mov     ax,[es:3]
        cmp     ax,2
        jb      .nolast
        mov     dx,[zlast]              ; final de la convencional
        add     dx,ax
        inc     dx
        cmp     dx,[rs]
        ja      .nolast
        cli
        dec     word [es:3]             ; l'£ltim bloc, un par…graf menys
        mov     byte [es:0],'M'
        dec     dx                      ; bloc de sistema fins al primer tros
        mov     bx,[rs]
        call    gapmcb
        xor     si,si
.lk:    mov     es,[rs+si]              ; tros: un bloc lliure
        call    mcbclr
        mov     word [es:1],0
        mov     ax,si
        shr     ax,1
        inc     ax
        cmp     ax,[nr]
        jae     .last
        mov     byte [es:0],'M'
        mov     ax,[re+si]              ; l'£ltim par…graf del tros ‚s el
        dec     ax                      ; bloc de sistema fins al segent
        mov     dx,ax
        sub     ax,[rs+si]
        dec     ax
        mov     [es:3],ax
        mov     bx,[rs+si+2]
        call    gapmcb
        add     si,2
        jmp     .lk
.last:  mov     byte [es:0],'Z'
        mov     ax,[re+si]
        sub     ax,[rs+si]
        dec     ax
        mov     [es:3],ax
        sti
        pop     es
        mov     dx,m_made
        call    puts
        call    pranges
        mov     dx,m_made2
        call    puts
        call    rtotal
        call    pparas
        mov     dx,m_bytes
        call    puts
        ret
.nolast:
        pop     es
        mov     dx,m_nolast
        jmp     fail

; DX = segment del bloc de sistema ('SC', propietari 0008h) que tapa
; fins a BX (on hi ha el bloc segent)
gapmcb: push    ax
        mov     es,dx
        call    mcbclr
        mov     byte [es:0],'M'
        mov     word [es:1],0008h
        mov     ax,bx
        sub     ax,dx
        dec     ax
        mov     [es:3],ax
        mov     word [es:8],'SC'
        pop     ax
        ret

; Ajunta els trossos seguits (el final d'un ‚s l'inici del segent)
merge_r:
        mov     cx,[nr]
        xor     si,si
.l:     mov     ax,si
        shr     ax,1
        inc     ax
        cmp     ax,cx
        jae     .x
        mov     ax,[re+si]
        cmp     ax,[rs+si+2]
        jne     .n
        mov     ax,[re+si+2]            ; s'enganxa el segent
        mov     [re+si],ax
        push    si                      ; i es corren els altres
        add     si,2
.m:     mov     ax,si
        shr     ax,1
        inc     ax
        cmp     ax,cx
        jae     .me
        mov     ax,[rs+si+2]
        mov     [rs+si],ax
        mov     ax,[re+si+2]
        mov     [re+si],ax
        add     si,2
        jmp     .m
.me:    pop     si
        dec     cx
        jmp     .l
.n:     add     si,2
        jmp     .l
.x:     mov     [nr],cx
        ret

; AX = par…grafs de tots els trossos
rtotal: push    si
        push    cx
        xor     ax,ax
        xor     si,si
        mov     cx,[nr]
.l:     jcxz    .x
        add     ax,[re+si]
        sub     ax,[rs+si]
        add     si,2
        dec     cx
        jmp     .l
.x:     pop     cx
        pop     si
        ret

; Escriu els trossos: "C0000-C7FFF, CC000-EFFFF"
pranges:
        push    ax
        push    cx
        push    si
        xor     si,si
        mov     cx,[nr]
.l:     cmp     word [nr],1             ; m‚s d'un tros: "1) "
        jbe     .l1
        mov     ax,si
        shr     ax,1
        inc     ax
        add     al,'0'
        call    putc
        mov     al,')'
        call    putc
        mov     al,' '
        call    putc
.l1:    mov     ax,[rs+si]
        call    phex4
        mov     al,'0'
        call    putc
        mov     al,'-'
        call    putc
        mov     ax,[re+si]
        dec     ax
        call    phex4
        mov     al,'F'
        call    putc
        add     si,2
        dec     cx
        jz      .x
        mov     al,','
        call    putc
        mov     al,' '
        call    putc
        jmp     .l
.x:     pop     si
        pop     cx
        pop     ax
        ret

; ES = bloc: posa a zero els bytes 5-15 de la cap‡alera
mcbclr: push    ax
        push    cx
        push    di
        mov     di,5
        mov     cx,11
        xor     al,al
        rep     stosb
        pop     di
        pop     cx
        pop     ax
        ret

; Final autom…tic: des d'AX fins on deixa d'haver-hi RAM, una ROM
; d'adaptador (55AAh en un l¡mit de 2 KB) o BX (el tros segent o
; F000h) -> AX
auto_end:
.l:     cmp     ax,bx
        jae     .e
        test    ax,7Fh
        jnz     .r
        push    es
        mov     es,ax
        cmp     word [es:0],0AA55h
        pop     es
        je      .e
.r:     call    ramtest
        jc      .e
        inc     ax
        jmp     .l
.e:     ret

; AX = par…graf entre BC00 i BFFF. CF=1 si ‚s el mirall de la mem•ria
; de v¡deo (el que s'hi escriu apareix 16 KB m‚s avall, a B800-BBFF)
vmirror:
        push    ax
        push    bx
        push    cx
        push    ds
        push    es
        mov     es,ax
        sub     ax,400h
        mov     ds,ax
        cli
        mov     bl,[es:0]               ; es restaura sempre
        mov     bh,bl
        not     bh
        mov     [es:0],bh
        mov     cl,[ds:0]
        mov     bh,bl
        xor     bh,55h
        mov     [es:0],bh
        mov     ch,[ds:0]
        mov     [es:0],bl
        sti
        not     bl                      ; mirall: els dos valors hi surten
        cmp     cl,bl
        jne     .no
        not     bl
        xor     bl,55h
        cmp     ch,bl
        jne     .no
        stc
        jmp     short .x
.no:    clc
.x:     pop     es
        pop     ds
        pop     cx
        pop     bx
        pop     ax
        ret

; AX = par…graf. Prova sense destruir que els 16 bytes s¢n RAM. CF=1 no
ramtest:
        push    bx
        push    cx
        push    di
        push    es
        mov     es,ax
        xor     di,di
        mov     cx,16
.l:     mov     bl,[es:di]
        mov     bh,bl
        not     bh
        cli
        mov     [es:di],bh
        mov     bh,[es:di]
        mov     [es:di],bl
        sti
        not     bh
        cmp     bh,bl
        jne     .no
        inc     di
        loop    .l
        clc
        jmp     short .x
.no:    stc
.x:     pop     es
        pop     di
        pop     cx
        pop     bx
        ret

; AX = par…graf. ZF=1 si ‚s tot 00h o tot FFh
para_empty:
        push    ax
        push    cx
        push    di
        push    es
        mov     es,ax
        xor     di,di
        mov     ax,[es:di]
        cmp     ax,0
        je      .t
        cmp     ax,0FFFFh
        jne     .x
.t:     mov     cx,8
        repe    scasw
.x:     pop     es
        pop     di
        pop     cx
        pop     ax
        ret

; CF=0 si a [rs] hi ha una cadena de blocs v…lida que acaba en 'Z'
; abans de F000h (una zona de LOADHI d'abans d'un reinici en calent)
stale_zone:
        push    es
        mov     ax,[rs]
        mov     cx,500
.l:     mov     es,ax
        mov     bl,[es:0]
        cmp     bl,'M'
        je      .s
        cmp     bl,'Z'
        jne     .no
.s:     add     ax,[es:3]
        jc      .no
        inc     ax
        cmp     ax,UTOP
        ja      .no
        cmp     bl,'Z'
        je      .yes
        loop    .l
.no:    pop     es
        stc
        ret
.yes:   pop     es
        clc
        ret

; Mostra l'estat de la zona alta
status: cmp     word [astart],0
        jne     .s
        mov     dx,m_nozone
        call    puts
        ret
.s:     mov     dx,m_zone
        call    puts
        call    regions
        call    pranges
        mov     dx,m_made2
        call    puts
        call    rtotal
        call    pparas
        mov     dx,m_bytes
        call    puts
        xor     bx,bx                   ; tota la zona
        mov     dx,0FFFFh
        call    freein
        mov     dx,m_free
        call    puts
        mov     ax,bx
        call    pparas
        mov     dx,m_free2
        call    puts
        mov     ax,cx
        call    pparas
        mov     dx,m_free3
        call    puts
        cmp     word [nr],1             ; per trossos, si n'hi ha m‚s d'un
        jbe     .x
        xor     si,si
.t:     mov     dx,m_tros
        call    puts
        mov     ax,si
        shr     ax,1
        inc     ax
        call    pdec
        mov     dx,m_tros2
        call    puts
        mov     bx,[rs+si]
        mov     dx,[re+si]
        call    freein
        mov     ax,bx
        call    pparas
        mov     dx,m_free2
        call    puts
        mov     ax,cx
        call    pparas
        mov     dx,m_free3
        call    puts
        add     si,2
        mov     ax,si
        shr     ax,1
        cmp     ax,[nr]
        jb      .t
.x:     ret

; BX..DX = segments (DX exclusiu). Torna BX = par…grafs lliures dels
; blocs que comencen en aquest interval, CX = el bloc lliure m‚s gran
freein: push    es
        push    ax
        push    si
        mov     si,bx
        mov     ax,[astart]
        xor     bx,bx
        xor     cx,cx
.l:     mov     es,ax
        cmp     word [es:1],0
        jne     .n
        cmp     ax,si
        jb      .n
        cmp     ax,dx
        jae     .n
        push    dx
        mov     dx,[es:3]
        add     bx,dx
        cmp     dx,cx
        jbe     .n0
        mov     cx,dx
.n0:    pop     dx
.n:     cmp     byte [es:0],'Z'
        je      .e
        add     ax,[es:3]
        inc     ax
        jmp     .l
.e:     pop     si
        pop     ax
        pop     es
        ret

; Els trossos de la zona alta, entre els blocs 'SC': nr, rs, re
regions:
        push    es
        push    ax
        push    dx
        push    si
        mov     word [nr],0
        mov     ax,[astart]
        mov     [rs],ax
        xor     si,si
.w:     mov     es,ax
        cmp     byte [es:0],'Z'
        je      .we
        cmp     word [es:1],0008h
        jne     .wn
        cmp     word [es:8],'SC'
        jne     .wn
        mov     dx,ax                   ; fi del tros: el bloc 'SC' ‚s
        inc     dx                      ; el seu £ltim par…graf
        mov     [re+si],dx
        add     si,2
        inc     word [nr]
        cmp     si,MAXR*2
        jae     .we2
        add     ax,[es:3]
        inc     ax
        mov     [rs+si],ax
        jmp     .w
.wn:    add     ax,[es:3]
        inc     ax
        jmp     .w
.we:    mov     ax,[aend]
        mov     [re+si],ax
        inc     word [nr]
.we2:   pop     si
        pop     dx
        pop     ax
        pop     es
        ret

; =====================================================================
;  C…rrega
; =====================================================================
; Busca el programa: tal qual, amb .COM / .EXE, i als directoris del
; PATH si el nom no porta unitat ni directori. Deixa la ruta a [path].
find_prog:
        mov     si,prog                 ; t‚ extensi¢? directori?
        mov     byte [hasext],0
        mov     byte [hasdir],0
.c:     lodsb
        or      al,al
        jz      .c2
        cmp     al,'.'
        jne     .c1
        mov     byte [hasext],1
.c1:    cmp     al,'\'
        je      .cd
        cmp     al,':'
        jne     .c
.cd:    mov     byte [hasext],0
        mov     byte [hasdir],1
        jmp     .c
.c2:    mov     di,path                 ; primer, tal qual
        call    try_dir
        jnc     .x
        cmp     byte [hasdir],0
        jne     .no
        push    es                      ; despr‚s, el PATH
        mov     es,[2Ch]
        xor     di,di
.e:     cmp     byte [es:di],0
        je      .nopath
        cmp     word [es:di],'PA'
        jne     .enx
        cmp     word [es:di+2],'TH'
        jne     .enx
        cmp     byte [es:di+4],'='
        je      .pf
.enx:   mov     al,0
        mov     cx,8000h
        repne   scasb
        jmp     .e
.pf:    add     di,5
.pd:    cmp     byte [es:di],0
        je      .nopath
        mov     si,path                 ; copia un directori
.pc:    mov     al,[es:di]
        or      al,al
        jz      .pce
        inc     di
        cmp     al,';'
        je      .pce
        mov     [si],al
        inc     si
        cmp     si,path+60
        jb      .pc
.pce:   cmp     si,path
        je      .pd
        mov     al,[si-1]
        cmp     al,'\'
        je      .pt
        cmp     al,':'
        je      .pt
        mov     byte [si],'\'
        inc     si
.pt:    push    di
        mov     di,si
        push    es
        push    ds
        pop     es
        call    try_dir
        pop     es
        pop     di
        jnc     .xp
        jmp     .pd
.nopath:
        pop     es
.no:    stc
        ret
.xp:    pop     es
.x:     clc
        ret

; DI = on posar el nom dins de [path] (darrere del directori).
; Hi copia el nom i, si no t‚ extensi¢, prova .COM i .EXE. CF=1 no hi ‚s
try_dir:
        mov     si,prog
.cp:    lodsb
        stosb
        or      al,al
        jnz     .cp
        dec     di
        cmp     byte [hasext],0
        je      .ext
        call    exists
        ret
.ext:   push    di
        mov     si,s_com
        call    .app
        call    exists
        pop     di
        jnc     .r
        push    di
        mov     si,s_exe
        call    .app
        call    exists
        pop     di
.r:     ret
.app:   push    di
.a:     lodsb
        stosb
        or      al,al
        jnz     .a
        pop     di
        ret

; existeix el fitxer [path]? CF=1 no
exists: mov     dx,path
        TSTEP   'o'
        mov     ax,3D00h
        int     21h
        TSTEP   'O'
        jc      .x
        mov     bx,ax
        mov     ah,3Eh
        int     21h
        clc
.x:     ret

; bloc de par…metres d'EXEC i FCB
build_pb:
        mov     word [pb_env],0
        mov     word [pb_tail],tail
        mov     [pb_tail+2],cs
        mov     word [pb_f1],fcb1
        mov     [pb_f1+2],cs
        mov     word [pb_f2],fcb2
        mov     [pb_f2+2],cs
        mov     si,tail+1
        mov     di,fcb1
        mov     ax,2901h
        int     21h
        mov     di,fcb2
        mov     ax,2901h
        int     21h
        ret

; Posa a nom de LOADHI els blocs lliures de la mem•ria convencional
block_low:
        push    es
        mov     ah,52h
        int     21h
        mov     ax,[es:bx-2]
        xor     bx,bx
        xor     dx,dx                   ; bloc anterior
.l:     mov     es,ax
        cmp     word [es:1],0
        jne     .n
        cmp     ax,[astart]
        jb      .blk
        cmp     byte [o_r],0            ; /R:n: fora del tros n, tapat
        je      .cmd
        cmp     ax,[rsel]
        jb      .blk
        cmp     ax,[resel]
        jae     .blk
.cmd:
        ; a la zona alta: el bloc lliure just despr‚s d'un COMMAND.COM
        ; permanent carregat a dalt ‚s on hi ha la seva part transit•ria
        or      dx,dx
        jz      .n
        push    es
        mov     es,dx
        mov     cx,[es:1]
        pop     es
        mov     si,dx
        inc     si
        cmp     cx,si
        jne     .n
        push    es
        mov     es,cx
        cmp     [es:16h],cx
        pop     es
        jne     .n
.blk:   cmp     bx,MAXBLK*2
        jae     .n
        mov     [blocked+bx],ax
        inc     bx
        inc     bx
        mov     [es:1],cs
.n:     mov     dx,ax
        cmp     byte [es:0],'Z'
        je      .e
        add     ax,[es:3]
        inc     ax
        jmp     .l
.e:     mov     [nblocked],bx
        pop     es
        ret

; Els torna a deixar lliures
unblock:
        push    es
        mov     bx,[nblocked]
.l:     or      bx,bx
        jz      .e
        dec     bx
        dec     bx
        mov     es,[blocked+bx]
        mov     ax,cs
        cmp     [es:1],ax
        jne     .l
        mov     word [es:1],0
        jmp     .l
.e:     mov     word [nblocked],0
        pop     es
        ret

; EXEC de [path]. Torna CF i AX
do_exec:
        mov     [ss_save],ss
        mov     [sp_save],sp
        mov     dx,path
        mov     bx,pblock
        push    ds
        pop     es
        mov     ax,4B00h
        int     21h
        cli
        mov     ss,[cs:ss_save]
        mov     sp,[cs:sp_save]
        sti
        push    cs
        pop     ds
        push    cs
        pop     es
        cld
        ret

; Escriu el nom del programa (sense extensi¢) a la cap‡alera del bloc
; del seu PSP (bytes 8-15, com DOS 4+), perquŠ MEM el reconegui encara
; que alliberi l'entorn. Nom‚s als blocs de programa fills de LOADHI
; que encara no tenen nom.
; Abans de l'EXEC: apunta els blocs que ja s¢n fills d'un programa amb el
; nostre CS (TSR carregats abans per altres LOADHI al mateix lloc).
kids_snap:
        push    es
        mov     word [nkids],0
        mov     ah,52h
        int     21h
        mov     ax,[es:bx-2]
        mov     cx,4000
.l:     mov     es,ax
        mov     dx,ax
        inc     dx
        cmp     [es:1],dx
        jne     .n
        push    es
        mov     es,dx
        cmp     word [es:0],20CDh
        jne     .np
        mov     dx,cs
        cmp     [es:16h],dx
.np:    pop     es
        jne     .n
        mov     bx,[nkids]
        cmp     bx,32
        jae     .n
        shl     bx,1
        mov     [kids+bx],ax
        inc     word [nkids]
.n:     cmp     byte [es:0],'Z'
        je      .e
        add     ax,[es:3]
        inc     ax
        loop    .l
.e:     pop     es
        ret
; AX = bloc. ZF=1 si ja hi era abans de l'EXEC
in_kids:
        push    cx
        push    di
        push    es
        push    ds
        pop     es
        mov     di,kids
        mov     cx,[nkids]
        jcxz    .no
        repne   scasw
        jmp     short .x
.no:    or      cx,1                    ; ZF=0
.x:     pop     es
        pop     di
        pop     cx
        ret

name_child:
        mov     si,path                 ; SI = inici del nom
        mov     bx,si
.f:     lodsb
        or      al,al
        jz      .f2
        cmp     al,'\'
        je      .fs
        cmp     al,':'
        jne     .f
.fs:    mov     bx,si
        jmp     .f
.f2:    mov     [nm_at],bx
        push    es
        mov     ah,52h
        int     21h
        mov     ax,[es:bx-2]
        mov     cx,4000
.l:     mov     es,ax
        mov     dx,ax
        inc     dx                      ; bloc que comen‡a amb un PSP
        cmp     [es:1],dx
        jne     .n
        push    es                      ; (DOS 3.x no neteja els bytes 8-15:
        mov     es,dx                   ; s'hi escriu el nom sempre, per•
        cmp     word [es:0],20CDh       ; nom‚s al fill nou, no als d'altres
        jne     .np                     ; LOADHI d'abans amb el mateix CS)
        mov     dx,cs
        cmp     [es:16h],dx
.np:    pop     es
        jne     .n
        call    in_kids
        je      .n
        call    .put
.n:     cmp     byte [es:0],'Z'
        je      .e
        add     ax,[es:3]
        inc     ax
        loop    .l
.e:     pop     es
        ret
.put:   push    ax
        push    si
        push    di
        push    cx
        mov     si,[nm_at]
        mov     di,8
        mov     cx,8
.p:     lodsb
        or      al,al
        jz      .pz
        cmp     al,'.'
        je      .pz
        mov     [es:di],al
        inc     di
        loop    .p
        jmp     short .px
.pz:    mov     byte [es:di],0
        inc     di
        loop    .pz
.px:    pop     cx
        pop     di
        pop     si
        pop     ax
        ret

; =====================================================================
;  Sortida per pantalla
; =====================================================================
; DX = text acabat en '$'
puts:   push    ax
        mov     ah,9
        int     21h
        pop     ax
        ret

; DX = text acabat en 0
putz:   push    ax
        push    dx
        push    si
        mov     si,dx
.l:     lodsb
        or      al,al
        jz      .e
        mov     dl,al
        mov     ah,2
        int     21h
        jmp     .l
.e:     pop     si
        pop     dx
        pop     ax
        ret

putc:   push    ax
        push    dx
        mov     dl,al
        mov     ah,2
        int     21h
        pop     dx
        pop     ax
        ret

; AX -> 4 xifres hex
phex4:  push    ax
        push    cx
        mov     cx,4
.l:     push    cx
        mov     cl,4
        rol     ax,cl
        pop     cx
        push    ax
        and     al,0Fh
        add     al,'0'
        cmp     al,'9'
        jbe     .d
        add     al,7
.d:     call    putc
        pop     ax
        loop    .l
        pop     cx
        pop     ax
        ret

; (antiga) un sol tros
prange: push    ax
        mov     ax,[hstart]
        call    phex4
        mov     al,'0'
        call    putc
        mov     al,'-'
        call    putc
        mov     ax,[hend]
        dec     ax
        call    phex4
        mov     al,'F'
        call    putc
        pop     ax
        ret

; AX par…grafs -> bytes amb punts de milers
pparas: push    ax
        push    bx
        push    cx
        push    dx
        push    si
        xor     dx,dx
        mov     cx,4
.s:     shl     ax,1
        rcl     dx,1
        loop    .s
        mov     si,numbuf+15
        mov     byte [si],0
        xor     cx,cx                   ; xifres escrites
.d:     push    ax                      ; DX:AX / 10
        mov     ax,dx
        xor     dx,dx
        mov     bx,10
        div     bx
        mov     bx,ax
        pop     ax
        push    bx
        mov     bx,10
        div     bx
        pop     bx
        xchg    dx,bx                   ; DX:AX = quocient, BL = residu
        cmp     cx,3
        jne     .nd
        dec     si
        mov     byte [si],'.'
        xor     cx,cx
.nd:    dec     si
        add     bl,'0'
        mov     [si],bl
        inc     cx
        mov     bx,ax
        or      bx,dx
        jnz     .d
        mov     dx,si
        call    putz
        pop     si
        pop     dx
        pop     cx
        pop     bx
        pop     ax
        ret

; =====================================================================
;  Textos (CP850)
; =====================================================================
s_loadhi db     'LOADHI',0,0
m_noshell db    'LOADHI: falta l',39,'intŠrpret d',39,'ordres (p. ex. C:\COMMAND.COM C:\ /P).',CR,LF,'$'
m_cfgbig db     'LOADHI: el fitxer d',39,'opcions passa de 2000 bytes.',CR,LF,'$'
w_f     db      'F',0
w_c     db      'C',0
w_v     db      'V',0
w_b     db      'B',0
w_buffers db    'BUFFERS',0
w_files db      'FILES',0
w_h     db      'H',0
w_r     db      'R',0
w_rb    db      'RB',0
w_rc    db      'RC',0
s_com   db      '.COM',0
s_exe   db      '.EXE',0
m_crlf  db      CR,LF,'$'
m_badver db     'LOADHI ‚s per a MS-DOS 3.x i 4.x. Amb DOS 5 o posterior fes',CR,LF
        db      'servir DOS=UMB i LH.',CR,LF,'$'
m_drdos db      'LOADHI no funciona amb DR DOS ni DOS Plus.',CR,LF,'$'
m_broken db     'La cadena de blocs de mem•ria de DOS est… trencada.',CR,LF,'$'
m_nozone db     'No hi ha zona alta. Es crea des del CONFIG.SYS, per exemple:',CR,LF
        db      '  SHELL=C:\LOADHI.COM @C:\LOADHI.CFG',CR,LF
        db      'amb les opcions al fitxer (DOS 3 no accepta m‚s de 31 car…cters',CR,LF
        db      'de par…metres a SHELL=):  /H:D000 C:\COMMAND.COM C:\ /P',CR,LF,'$'
m_notfirst db   'La zona alta nom‚s es pot crear des del CONFIG.SYS, abans que es',CR,LF
        db      'carregui COMMAND.COM (la seva part transit•ria es torna a carregar',CR,LF
        db      'sempre al capdamunt de la mem•ria i la trencaria). Posa:',CR,LF
        db      '  SHELL=C:\LOADHI.COM @C:\LOADHI.CFG',CR,LF,'$'
m_already db    'La zona alta ja ‚s a $'
m_already2 db   '0; /H no canvia res.',CR,LF,'$'
m_badopt db     'Opci¢ no v…lida. LOADHI /? per veure com es fa servir.',CR,LF,'$'
m_range db      'La zona alta ha de ser entre BC00 i FDFF, en RAM.',CR,LF,'$'
m_mirror db     'La zona alta no pot comen‡ar al mirall del v¡deo (BC00-BFFF).',CR,LF,'$'
m_small db      'La zona alta ‚s massa petita (m¡nim 1 KB).',CR,LF,'$'
m_rescue db     'LOADHI: es carrega l',39,'intŠrpret d',39,'ordres a baix.',CR,LF,'$'
m_noram db      'No hi ha RAM a $'
m_noram2 db     '0.',CR,LF,'$'
m_full  db      'La zona $'
m_full2 db      ' no ‚s buida. Si saps que no la fa servir',CR,LF
        db      'ning£ (p. ex. restes d',27h,'abans d',27h,'un reinici), fes servir /F.',CR,LF,'$'
m_nolast db     'L',27h,'£ltim bloc de mem•ria convencional no ‚s lliure.',CR,LF,'$'
m_made  db      'Zona alta creada: $'
m_made2 db      ' ($'
m_bytes db      ' bytes).',CR,LF,'$'
m_zone  db      'Zona alta: $'
m_free  db      'Lliure: $'
m_free2 db      ' bytes; bloc lliure m‚s gran: $'
m_free3 db      ' bytes.',CR,LF,'$'
m_notfound db   'No es troba el programa $'
m_nocfg db      'No es pot llegir el fitxer d',27h,'opcions $'
m_shonly db     '/C, /B, /FILES, /RB i /RC nom‚s es poden fer servir a la l¡nia SHELL= del',CR,LF
        db      'CONFIG.SYS, quan es crea la zona alta.',CR,LF,'$'
m_v3    db      '/B i /FILES nom‚s funcionen amb MS-DOS 3.10 - 3.30.',CR,LF,'$'
m_nofit db      'No hi cap a la zona alta.',CR,LF,'$'
m_buf   db      'BUFFERS: $'
m_files db      'FILES: $'
m_hi    db      ' m‚s a la zona alta.',CR,LF,'$'
m_cnohi db      '/C: no es pot llegir l',27h,'intŠrpret; es carrega a baix.',CR,LF,'$'
m_noreg db      'LOADHI: la zona alta nom‚s t‚ $'
m_noreg1 db     ' tros.',CR,LF,'$'
m_noreg2 db     ' trossos.',CR,LF,'$'
m_rlow  db      'No hi cap al tros $'
m_rlow2 db      ': es carrega a la mem•ria convencional.',CR,LF,'$'
m_rbfull db     '/RB: no hi cap al tros $'
m_rbfull2 db    '; va a un altre tros.',CR,LF,'$'
m_rcfull db     '/RC: COMMAND.COM no hi cap al tros $'
m_rcfull2 db    '; va al bloc m‚s gran.',CR,LF,'$'
m_tros  db      '  Tros $'
m_tros2 db      ': lliure $'
m_low   db      'No hi cap a la zona alta: es carrega a la mem•ria convencional.',CR,LF,'$'
m_xerr  db      'No s',27h,'ha pogut executar el programa.',CR,LF,'$'
m_badfmt db     'El programa no t‚ un format v…lid (els .BAT no es poden carregar).',CR,LF,'$'
m_help  db      'LOADHI 0.20 - carrega programes a la mem•ria superior (MS-DOS 3.x)',CR,LF
        db      CR,LF
        db      'LOADHI [@fitxer] [/H:ini[-fi]] [/F] [/B:n] [/FILES:n] [/C] [/R:n]',CR,LF
        db      '       [/RB:n] [/RC:n]',CR,LF
        db      '       [programa [par…m.]]',CR,LF
        db      CR,LF
        db      '  /H:inici  crea la zona alta a partir d',27h,'aquest segment (BC00-FDFF)',CR,LF
        db      '            i l',27h,'enlla‡a a DOS. Sense final, arriba fins on hi ha RAM.',CR,LF
        db      '  -final    £ltim segment del tros (p. ex. /H:D000-DFFF). Fins a 4',CR,LF
        db      '            trossos separats per comes: /H:C000-C7FF,CC00-EFFF',CR,LF
        db      '  /F        no comprova que la zona sigui buida.',CR,LF
        db      '  /B:n      n buffers de disc m‚s, a la zona alta.',CR,LF
        db      '  /FILES:n  n fitxers oberts m‚s (FILES), a la zona alta.',CR,LF
        db      '  /C        carrega l',27h,'intŠrpret (COMMAND.COM) a la zona alta.',CR,LF
        db      '  /V        amb /C: mostra on el carrega i quan acaba (per provar).',CR,LF
        db      '            /H, /B, /FILES i /C: nom‚s a SHELL= del CONFIG.SYS.',CR,LF
        db      '  /R:n      carrega el programa al tros n de la zona (1 = el primer).',CR,LF
        db      '  /RB:n     BUFFERS i FILES (/B, /FILES) al tros n.',CR,LF
        db      '  /RC:n     COMMAND.COM (/C) al tros n.  /RB i /RC: nom‚s a SHELL=.',CR,LF
        db      '  programa  el carrega a la zona alta (.COM o .EXE, tamb‚ pel PATH).',CR,LF
        db      '            Si no hi cap, es carrega a la mem•ria convencional.',CR,LF
        db      CR,LF
        db      'Sense programa, mostra la zona alta i quanta mem•ria lliure hi queda.',CR,LF
        db      '@fitxer: les opcions es llegeixen d',27h,'aquest fitxer. Exemple:',CR,LF
        db      '  CONFIG.SYS:   SHELL=C:\LOADHI.COM @C:\LOADHI.CFG',CR,LF
        db      '  LOADHI.CFG:   /H:D000 /B:20 /FILES:12 /C C:\COMMAND.COM C:\ /P',CR,LF
        db      '  AUTOEXEC.BAT: LOADHI KEYBX',CR,LF
        db      '                LOADHI MOUSE',CR,LF,'$'

; =====================================================================
;  BUFFERS i FILES a la zona alta (nom‚s MS-DOS 3.10 - 3.30)
; =====================================================================
; CF=0 si la versi¢ de DOS ‚s 3.10 - 3.30 (estructures conegudes)
chk_v3: mov     ax,[dosver]
        cmp     al,3
        jne     .no
        cmp     ah,10
        jb      .no
        cmp     ah,30
        ja      .no
        clc
        ret
.no:    mov     dx,m_v3
        jmp     fail

; AX = par…grafs -> AX = segment d'un bloc nou a la zona alta, de DOS
; (propietari 0008h). Si no hi cap, error.
alloc_sys:
        push    bx
        push    es
        mov     [sysparas],ax
        cmp     byte [o_rb],0           ; /RB:n: nom‚s al tros n
        je      .a1
        mov     al,[o_rb]
        call    selreg
        mov     al,[o_rb]
        mov     [o_r],al                ; (block_low tapa la resta)
.a1:    call    .try
        mov     byte [o_r],0
        jnc     .got
        cmp     byte [o_rb],0
        je      .no
        mov     dx,m_rbfull             ; no hi cap: a qualsevol tros
        call    puts
        mov     al,[o_rb]
        xor     ah,ah
        call    pdec
        mov     dx,m_rbfull2
        call    puts
        mov     byte [o_rb],0
        call    .try
        jc      .no
.got:   cmp     ax,UBASE
        jb      .low
        dec     ax
        mov     es,ax
        mov     word [es:1],0008h
        call    mcbclr
        inc     ax
        pop     es
        pop     bx
        ret
.low:   mov     es,ax
        mov     ah,49h
        int     21h
.no:    mov     dx,m_nofit
        jmp     fail
.try:   call    block_low
        mov     bx,[sysparas]
        mov     ah,48h
        int     21h
        pushf
        push    ax
        call    unblock
        pop     ax
        popf
        ret

; AL = tros (1..nr) -> rsel, resel. CF=1 si no existeix
selreg: push    ax
        push    bx
        xor     ah,ah
        or      ax,ax
        jz      .no
        cmp     ax,[nr]
        ja      .no
        dec     ax
        shl     ax,1
        mov     bx,ax
        mov     ax,[rs+bx]
        mov     [rsel],ax
        mov     ax,[re+bx]
        mov     [resel],ax
        clc
        jmp     short .x
.no:    stc
.x:     pop     bx
        pop     ax
        ret

; BX -> o_rb / o_rc. Si la zona no t‚ aquest tros, ho diu i l'oblida
chk_reg:
        mov     al,[bx]
        or      al,al
        jz      .x
        call    selreg
        jnc     .x
        mov     byte [bx],0
        mov     dx,m_noreg
        call    puts
        mov     ax,[nr]
        call    pdec
        mov     dx,m_noreg2
        cmp     ax,1
        jne     .p
        mov     dx,m_noreg1
.p:     call    puts
.x:     ret

; /C amb /RC:n: el bloc lliure m‚s gran del tros n -> st_tb (MCB), si
; COMMAND.COM hi cap; si no, ho diu i va al bloc m‚s gran (com sense /RC)
shell_reg:
        mov     word [st_tb],0
        cmp     byte [st_hi],0
        je      .x
        mov     al,[o_rc]
        or      al,al
        jz      .x
        call    selreg
        jc      .x
        push    es
        mov     ax,[astart]
        xor     cx,cx                   ; mida del m‚s gran
        xor     di,di                   ; el seu MCB
.l:     mov     es,ax
        cmp     word [es:1],0
        jne     .n
        cmp     ax,[rsel]
        jb      .n
        cmp     ax,[resel]
        jae     .n
        cmp     [es:3],cx
        jbe     .n
        mov     cx,[es:3]
        mov     di,ax
.n:     cmp     byte [es:0],'Z'
        je      .e
        add     ax,[es:3]
        inc     ax
        jmp     .l
.e:     pop     es
        cmp     cx,[st_r]               ; hi ha de quedar alguna cosa sota
        jbe     .nofit
        mov     [st_tb],di
.x:     ret
.nofit: mov     dx,m_rcfull
        call    puts
        mov     al,[o_rc]
        xor     ah,ah
        call    pdec
        mov     dx,m_rcfull2
        call    puts
        ret

; /B:n -> n buffers de disc m‚s, encadenats al final de la llista de DOS
add_buffers:
        mov     cx,[o_buf]
        jcxz    .x0
        jmp     short .go
.x0:    ret
.go:
        call    chk_v3
        cmp     cx,99                   ; com BUFFERS=, m…xim 99
        jbe     .g1
        mov     cx,99
        mov     [o_buf],cx
.g1:    push    es
        mov     ah,52h
        int     21h
        mov     ax,[es:bx+10h]          ; mida m…xima de sector
        add     ax,16                   ; + cap‡alera
        mov     [bsz],ax
        mul     cx
        add     ax,15
        adc     dx,0
        mov     cx,4
.s:     shr     dx,1
        rcr     ax,1
        loop    .s
        call    alloc_sys
        mov     [newseg],ax
        mov     es,ax                   ; omple els buffers nous
        xor     di,di
        mov     cx,[o_buf]
.b:     push    cx
        push    di
        mov     cx,[bsz]
        xor     al,al
        rep     stosb
        pop     di
        pop     cx
        mov     byte [es:di+4],0FFh     ; unitat: lliure
        mov     byte [es:di+8],1        ; c•pies
        mov     ax,di
        add     ax,[bsz]
        cmp     cx,1
        jne     .nx
        mov     ax,0FFFFh               ; l'£ltim
        mov     [es:di+2],ax
.nx:    mov     [es:di],ax
        cmp     cx,1
        je      .nx2
        mov     [es:di+2],es
.nx2:   add     di,[bsz]
        loop    .b
        mov     ah,52h                  ; enganxa'ls al final de la llista
        int     21h
        les     bx,[es:bx+12h]
        mov     cx,500
.f:     cmp     word [es:bx],0FFFFh
        je      .fe
        les     bx,[es:bx]
        loop    .f
        mov     dx,m_broken
        jmp     fail
.fe:    mov     ax,[newseg]
        cli
        mov     word [es:bx],0
        mov     [es:bx+2],ax
        sti
        pop     es
        mov     dx,m_buf
        call    puts
        mov     ax,[o_buf]
        call    pdec
        mov     dx,m_hi
        call    puts
.x:     ret

; /FILES:n -> una taula de fitxers (SFT) m‚s, amb n entrades, al final
add_files:
        mov     cx,[o_files]
        jcxz    .x0
        jmp     short .go
.x0:    ret
.go:
        call    chk_v3
        push    es
        mov     ah,52h
        int     21h
        les     bx,[es:bx+4]            ; primera taula; compta les entrades
        xor     dx,dx
        mov     cx,500
.c:     add     dx,[es:bx+4]
        cmp     word [es:bx],0FFFFh
        je      .ce
        les     bx,[es:bx]
        loop    .c
        mov     dx,m_broken
        jmp     fail
.ce:    mov     ax,255                  ; m…xim 255 en total
        sub     ax,dx
        jbe     .full
        cmp     ax,[o_files]
        jae     .n
        mov     [o_files],ax
.n:     push    es
        push    bx
        mov     ax,35h                  ; mida d'una entrada (DOS 3.1-3.3)
        mul     word [o_files]
        add     ax,6+15
        mov     cl,4
        shr     ax,cl
        call    alloc_sys
        mov     es,ax
        xor     di,di
        mov     ax,35h
        mul     word [o_files]
        add     ax,6
        mov     cx,ax
        xor     al,al
        rep     stosb
        mov     word [es:0],0FFFFh
        mov     word [es:2],0FFFFh
        mov     ax,[o_files]
        mov     [es:4],ax
        mov     ax,es
        pop     bx
        pop     es
        cli
        mov     word [es:bx],0
        mov     [es:bx+2],ax
        sti
        pop     es
        mov     dx,m_files
        call    puts
        mov     ax,[o_files]
        call    pdec
        mov     dx,m_hi
        call    puts
.x:     ret
.full:  pop     es
        ret

; AX -> decimal
pdec:   push    ax
        push    bx
        push    cx
        push    dx
        push    si
        mov     si,numbuf+15
        mov     byte [si],0
        mov     bx,10
.d:     xor     dx,dx
        div     bx
        dec     si
        add     dl,'0'
        mov     [si],dl
        or      ax,ax
        jnz     .d
        mov     dx,si
        call    putz
        pop     si
        pop     dx
        pop     cx
        pop     bx
        pop     ax
        ret

; /C: espai que cal a dalt per a COMMAND.COM (fitxer + PSP + entorn +
; marge) -> st_r de la plantilla del stub
shell_size:
        mov     dx,path
        mov     ax,3D00h
        int     21h
        jc      .no
        mov     bx,ax
        xor     cx,cx
        xor     dx,dx
        mov     ax,4202h
        int     21h
        pushf
        push    ax
        push    dx
        mov     ah,3Eh
        int     21h
        pop     dx
        pop     ax
        popf
        jc      .no
        or      dx,dx
        jnz     .no
        add     ax,15
        jc      .no
        mov     cl,4
        shr     ax,cl
        add     ax,10h+40h              ; PSP + marge
        mov     bx,[2Ch]                ; + entorn (si n'hi ha)
        or      bx,bx
        jz      .ne
        push    es
        dec     bx
        mov     es,bx
        mov     bx,[es:3]
        pop     es
        cmp     bx,800h                 ; (cap‡alera estranya: no en fa cas)
        ja      .ne
        add     ax,bx
        inc     ax
.ne:
        mov     [st_r],ax
        mov     byte [st_hi],1
        ret
.no:    mov     dx,m_cnohi
        call    puts
        ret

; INT 24h (error cr¡tic) mentre treballa LOADHI: ho escriu amb la BIOS
; ("LOADHI: error cr¡tic AX=xxxx DI=xxxx") i respon Anulúlar.
int24:  sti
        push    ax
        push    bx
        push    si
        push    ds
        push    cs
        pop     ds
        mov     si,m_crit
        call    bputs
        pop     ds
        pop     si
        pop     bx
        pop     ax
        push    ax
        call    bhex
        push    ds
        push    si
        push    cs
        pop     ds
        mov     si,m_crit2
        call    bputs
        pop     si
        pop     ds
        mov     ax,di
        call    bhex
        push    ds
        push    si
        push    cs
        pop     ds
        mov     si,m_crlf0
        call    bputs
        pop     si
        pop     ds
        pop     ax
        mov     al,2                    ; anulúla
        iret
; DS:SI -> text acabat en 0, amb la BIOS
bputs:  push    ax
        push    bx
.l:     lodsb
        or      al,al
        jz      .e
        mov     ah,0Eh
        mov     bx,7
        int     10h
        jmp     .l
.e:     pop     bx
        pop     ax
        ret
; AX en hex amb la BIOS
bhex:   push    ax
        push    bx
        push    cx
        push    dx
        mov     dx,ax
        mov     cx,4
.l:     push    cx
        mov     cl,4
        rol     dx,cl
        pop     cx
        mov     al,dl
        and     al,0Fh
        add     al,'0'
        cmp     al,'9'
        jbe     .d
        add     al,7
.d:     mov     ah,0Eh
        mov     bx,7
        int     10h
        loop    .l
        pop     dx
        pop     cx
        pop     bx
        pop     ax
        ret
m_crit  db      13,10,'LOADHI: error cr¡tic AX=',0
m_crit2 db      ' DI=',0
m_crlf0 db      13,10,0

; =====================================================================
;  Mode SHELL=: LOADHI ha creat la zona i ara executa l'intŠrpret
;  (COMMAND.COM) a la mem•ria convencional. Es queda com a pare seu amb
;  nom‚s 768 bytes: copia un petit programa (stub) a PSP:0100h, que
;  redueix el bloc i fa l'EXEC. Aquest codi ‚s al final perquŠ la c•pia
;  no el trepitgi.
; =====================================================================
shell_go:
        push    ds                      ; torna la INT 24h d'abans
        lds     dx,[o24]
        mov     ax,2524h
        int     21h
        pop     ds
        mov     ax,cs                   ; nom a la cap‡alera del bloc
        dec     ax
        mov     es,ax
        mov     di,8
        mov     si,s_loadhi
        mov     cx,8
        rep     movsb
        push    cs
        pop     es
        mov     si,path                 ; omple la plantilla
        mov     di,st_path
        mov     cx,80
        rep     movsb
        mov     si,tail
        mov     di,st_tail
        mov     cx,130
        rep     movsb
        mov     si,tail+1               ; FCB al PSP
        mov     di,5Ch
        mov     ax,2901h
        int     21h
        mov     di,6Ch
        mov     ax,2901h
        int     21h
        mov     si,stub
        mov     di,100h
        mov     cx,stub_end-stub
        TSTEP   '5'
        cli
        rep     movsb
        jmp     100h

; =====================================================================
;  Plantilla del stub (s'executa a PSP:0100h)
; =====================================================================
%define S(x)    ((x)-stub+100h)         ; adre‡a un cop copiat a 0100h
; /V: escriu un car…cter amb la BIOS (es veu encara que DOS falli)
%macro VSTEP 1
        pushf
%ifndef TRACE
        cmp     byte [cs:S(st_v)],0
        je      %%n
%endif
        push    ax
        push    bx
        mov     ax,0E00h+%1
        mov     bx,7
        int     10h
        pop     bx
        pop     ax
%%n:    popf
%endmacro
stub:   mov     ax,cs
        cli
        mov     ss,ax
        mov     sp,STUBTOP
        sti
        mov     [S(st_pb)+4],ax
        mov     [S(st_pb)+8],ax
        mov     [S(st_pb)+12],ax
        mov     es,ax
        VSTEP   'a'
        mov     bx,STUBPARAS
        mov     ah,4Ah
        int     21h
        VSTEP   'b'
        cmp     byte [S(st_hi)],0
        je      .low
        ; /C: ocupa tota la mem•ria lliure (convencional i zona alta) i
        ; deixa lliures nom‚s els £ltims st_r par…grafs de la zona alta
        mov     ax,[S(st_tb)]           ; /RC:n: el bloc triat
        or      ax,ax
        jz      .any
        push    ds
        mov     ds,ax
        cmp     word [1],0
        jne     .tbx
        mov     [1],cs                  ; ara ‚s de LOADHI (com 48h)
.tbx:   pop     ds
        mov     cl,'3'
        jne     .err
        inc     ax
        mov     [S(st_b2)],ax
        mov     bx,0FFFFh               ; i la convencional, com sempre
        mov     ah,48h
        int     21h
        mov     ah,48h
        int     21h
        mov     cl,'1'
        jc      .err
        mov     [S(st_b1)],ax
        VSTEP   'd'
        mov     ax,[S(st_b2)]
        jmp     short .z
.any:   mov     bx,0FFFFh
        mov     ah,48h
        int     21h
        mov     ah,48h
        int     21h
        mov     cl,'1'
        jc      .err
        mov     [S(st_b1)],ax
        VSTEP   'c'
        mov     bx,0FFFFh
        mov     ah,48h
        int     21h
        mov     ah,48h
        int     21h
        jnc     .any2
        mov     cx,[S(st_b1)]           ; no queda res m‚s: si el primer
        cmp     cx,UBASE                ;   ja ‚s a dalt (HIDOS ja tapa la
        jb      .any1                   ;   convencional), n'hi ha prou
        xchg    ax,cx
        jmp     short .z
.any1:  mov     cl,'2'
        jmp     .err
.any2:  mov     [S(st_b2)],ax
        VSTEP   'd'
        mov     ax,[S(st_b1)]
        cmp     ax,UBASE
        jae     .z
        mov     ax,[S(st_b2)]
        cmp     ax,UBASE
        mov     cl,'3'
        jb      .err
.z:     mov     es,ax
        dec     ax
        push    ds
        mov     ds,ax
        mov     bx,[3]
        pop     ds
        mov     ax,bx                   ; (per al missatge: el que hi ha)
        sub     bx,[S(st_r)]
        mov     cl,'4'
        jbe     .err
        mov     ah,4Ah
        int     21h
        mov     cl,'5'
        jc      .err
        VSTEP   'e'
        mov     ax,es                   ; el tros que queda lliure a dalt
        add     ax,bx
        mov     [S(st_top)],ax
        call    .blk                    ; tota la resta, tapada: COMMAND.COM
        mov     dx,S(st_path)           ; i el seu entorn nom‚s hi caben aqu¡
        mov     bx,S(st_pb)
        push    cs
        pop     es
        mov     ax,4B01h
        int     21h
        cli
        mov     bx,cs
        mov     ss,bx
        mov     sp,STUBTOP
        mov     ds,bx
        sti
        pushf
        call    .unblk
        popf
        VSTEP   'f'
        mov     cl,'6'
        jc      .err
        call    .free
        VSTEP   'g'
        call    .child                  ; BX = PSP del programa carregat
        VSTEP   'h'
        mov     cl,'7'
        xor     ax,ax
        or      bx,bx
        jz      .err
        ; si DOS no ha omplert CS:IP i SS:SP (.COM), es posen com fa EXEC:
        ; CS = SS = PSP, IP = 100h, SP al final del bloc (m…x. FFFEh)
        mov     ax,[S(st_pb)+14h]
        or      ax,[S(st_pb)+12h]
        jnz     .pbok
        mov     [S(st_pb)+14h],bx
        mov     word [S(st_pb)+12h],100h
        mov     [S(st_pb)+10h],bx
        push    es
        mov     ax,bx
        dec     ax
        mov     es,ax
        mov     ax,[es:3]
        pop     es
        mov     dx,0FFFEh
        cmp     ax,1000h
        jae     .sp
        mov     cl,4
        shl     ax,cl
        dec     ax
        dec     ax
        mov     dx,ax
.sp:    mov     [S(st_pb)+0Eh],dx
        push    es
        mov     es,bx
        mov     di,dx
        mov     word [es:di],0          ; RET -> PSP:0000 (INT 20h)
        pop     es
.pbok:  cmp     byte [S(st_v)],0
        je      .nv
        mov     ax,bx                   ; /V: on ‚s i on comen‡ar…
        mov     di,S(st_v1)
        call    .hx
        mov     ax,[S(st_pb)+14h]
        mov     di,S(st_v2)
        call    .hx
        mov     ax,[S(st_pb)+12h]
        mov     di,S(st_v3)
        call    .hx
        mov     ax,[S(st_pb)+10h]
        mov     di,S(st_v4)
        call    .hx
        mov     ax,[S(st_pb)+0Eh]
        mov     di,S(st_v5)
        call    .hx
        mov     dx,S(st_vm)
        mov     ah,9
        int     21h
        push    bx                      ; i vigila si acaba (INT 21h/20h)
        push    es
        mov     ax,3521h
        int     21h
        mov     [S(st_o21)],bx
        mov     [S(st_o21)+2],es
        mov     ax,3520h
        int     21h
        mov     [S(st_o20)],bx
        mov     [S(st_o20)+2],es
        pop     es
        pop     bx
        mov     dx,S(.v21)
        mov     ax,2521h
        int     21h
        mov     dx,S(.v20)
        mov     ax,2520h
        int     21h
.nv:    VSTEP   'i'
        mov     ah,50h                  ; PSP actual = el del programa
        int     21h
        mov     ds,bx
        mov     es,bx
        mov     dx,80h                  ; DTA a PSP:0080h, com fa EXEC
        mov     ah,1Ah
        int     21h
        mov     word [0Ah],S(.endhi)    ; si l'intŠrpret acaba, es torna a
        mov     [0Ch],cs                ; carregar a baix
        cli
        mov     ss,[cs:S(st_pb)+10h]
        mov     sp,[cs:S(st_pb)+0Eh]
        sti
        VSTEP   'j'
        xor     ax,ax
        jmp     far [cs:S(st_pb)+12h]
.err:   ; CL = pas, AX = codi: ho diu i el carrega a baix
        mov     [S(st_mp)],cl
        mov     di,S(st_mc)
        mov     cx,4
.h:     push    cx
        mov     cl,4
        rol     ax,cl
        pop     cx
        push    ax
        and     al,0Fh
        add     al,'0'
        cmp     al,'9'
        jbe     .hd
        add     al,7
.hd:    mov     [di],al
        inc     di
        pop     ax
        loop    .h
        mov     dx,S(st_msg)
        mov     ah,9
        int     21h
        call    .free
.low:   cmp     byte [S(st_v)],0
        je      .low1
        mov     dx,S(st_vl)
        mov     ah,9
        int     21h
.low1:  VSTEP   'L'
        push    cs
        pop     es
        mov     dx,S(st_path)
        mov     bx,S(st_pb)
        mov     ax,4B00h
        int     21h
.end:
%ifdef TRACE
        push    ax                      ; X + codi d'error de l'EXEC
        mov     ah,0Eh
        mov     bx,7
        push    ax
        mov     al,'X'
        int     10h
        pop     ax
        add     al,'0'
        int     10h
        pop     ax
%endif
        mov     ax,4C01h                ; l'intŠrpret ha acabat
        int     21h
.v20:   push    ax
        xor     ax,ax
        call    .vend
        pop     ax
        jmp     far [cs:S(st_o20)]
.v21:   cmp     ah,4Ch
        je      .v21e
        cmp     ah,0
        je      .v21e
        cmp     ah,31h
        jne     .v21x
.v21e:  call    .vend
.v21x:  jmp     far [cs:S(st_o21)]
; /V: "el programa PSP=xxxx acaba (AX=xxxx)"
.vend:  push    ax
        push    bx
        push    dx
        push    di
        push    ds
        push    cs
        pop     ds
        mov     di,S(st_ve2)
        call    .hx
        mov     ah,51h
        pushf
        call    far [cs:S(st_o21)]
        mov     ax,bx
        mov     di,S(st_ve1)
        call    .hx
        mov     dx,S(st_ve)
        mov     ah,9
        pushf
        call    far [cs:S(st_o21)]
        pop     ds
        pop     di
        pop     dx
        pop     bx
        pop     ax
        ret
; AX -> 4 xifres hex a CS:DI
.hx:    push    ax
        push    cx
        push    di
        mov     cx,4
.hl:    push    cx
        mov     cl,4
        rol     ax,cl
        pop     cx
        push    ax
        and     al,0Fh
        add     al,'0'
        cmp     al,'9'
        jbe     .hd2
        add     al,7
.hd2:   mov     [cs:di],al
        inc     di
        pop     ax
        loop    .hl
        pop     di
        pop     cx
        pop     ax
        ret
.endhi: cli                             ; l'intŠrpret carregat a dalt ha
        mov     ax,cs                   ; acabat: es diu i es carrega a baix
        mov     ss,ax
        mov     sp,STUBTOP
        mov     ds,ax
        mov     es,ax
        sti
        mov     ah,4Dh
        int     21h
        mov     cl,'8'
        jmp     .err
; BX = PSP d'un programa fill de LOADHI a la cadena de blocs (0 = cap)
.child: push    es
        push    ax
        push    dx
        mov     ah,52h
        int     21h
        mov     ax,[es:bx-2]
        xor     bx,bx
.cl:    mov     es,ax
        mov     dx,ax
        inc     dx
        cmp     [es:1],dx
        jne     .cn
        push    es
        mov     es,dx
        cmp     word [es:0],20CDh
        jne     .cp
        push    ax
        mov     ax,cs
        cmp     [es:16h],ax
        pop     ax
.cp:    pop     es
        jne     .cn
        mov     bx,dx
.cn:    cmp     byte [es:0],'Z'
        je      .ce
        add     ax,[es:3]
        inc     ax
        jmp     .cl
.ce:    pop     dx
        pop     ax
        pop     es
        ret
; tapa (a nom de LOADHI) tots els blocs lliures menys st_top
.blk:   push    es
        push    ax
        push    bx
        push    di
        mov     ah,52h
        int     21h
        mov     ax,[es:bx-2]
        mov     di,S(st_bl)
.bl:    mov     es,ax
        cmp     word [es:1],0
        jne     .bn
        cmp     ax,[S(st_top)]
        je      .bn
        cmp     di,S(st_bl)+2*SBLK
        jae     .bn
        mov     [es:1],cs
        mov     [di],ax
        inc     di
        inc     di
.bn:    cmp     byte [es:0],'Z'
        je      .be
        add     ax,[es:3]
        inc     ax
        jmp     .bl
.be:    mov     word [di],0
        pop     di
        pop     bx
        pop     ax
        pop     es
        ret
; els torna a deixar lliures
.unblk: push    es
        push    ax
        push    si
        mov     si,S(st_bl)
.ul:    mov     ax,[si]
        or      ax,ax
        jz      .ue
        mov     es,ax
        mov     ax,cs
        cmp     [es:1],ax
        jne     .un
        mov     word [es:1],0
.un:    inc     si
        inc     si
        jmp     .ul
.ue:    mov     word [S(st_bl)],0
        pop     si
        pop     ax
        pop     es
        ret
.free:  xor     ax,ax
        xchg    ax,[S(st_b2)]
        or      ax,ax
        jz      .f1
        mov     es,ax
        mov     ah,49h
        int     21h
.f1:    xor     ax,ax
        xchg    ax,[S(st_b1)]
        or      ax,ax
        jz      .f2
        mov     es,ax
        mov     ah,49h
        int     21h
.f2:    ret
st_v    db      0
        db      0
st_vl   db      'LOADHI /V: es carrega a baix',13,10,'$'
st_o21  dw      0,0
st_o20  dw      0,0
st_vm   db      'LOADHI /V: carregat a PSP='
st_v1   db      '????, CS:IP='
st_v2   db      '????:'
st_v3   db      '????, SS:SP='
st_v4   db      '????:'
st_v5   db      '????',13,10,'$'
st_ve   db      'LOADHI /V: el programa PSP='
st_ve1  db      '???? acaba (AX='
st_ve2  db      '????)',13,10,'$'
st_msg  db      'LOADHI /C: no va a dalt (pas '
st_mp   db      '?, codi '
st_mc   db      '????h); es carrega a baix.',13,10,'$'
st_pb   dw      0,S(st_tail),0,5Ch,0,6Ch,0
        dw      0,0,0,0                 ; SS:SP i CS:IP (4B01h)
st_hi   db      0
        db      0
st_r    dw      0
st_b1   dw      0
st_b2   dw      0
st_tb   dw      0                       ; /RC: MCB del bloc triat
st_top  dw      0
st_bl   times SBLK+1 dw 0
st_path times 80 db 0
st_tail times 130 db 0
stub_end:
STUBTOP equ     (stub_end-stub+100h+256) & 0FFFEh
STUBPARAS equ   (stub_end-stub+100h+256+15) >> 4

; =====================================================================
;  Dades sense valor inicial (es posen a zero en arrencar)
; =====================================================================
        section .bss
        alignb  2
bss_start:
convtop resw    1
zlast   resw    1
astart  resw    1
aend    resw    1
rs      resw    MAXR
re      resw    MAXR
nr      resw    1
rsel    resw    1
sysparas resw   1
resel   resw    1
hstart  resw    1
hend    resw    1
o_h     resb    1
o_f     resb    1
o_c     resb    1
o_r     resb    1
o_rb    resb    1
o_rc    resb    1
isshell resb    1
o24     resd    1
        alignb  2
o_buf   resw    1
o_files resw    1
dosver  resw    1
bsz     resw    1
newseg  resw    1
optw    resb    10
cfgname resb    80
cfgbuf  resb    2004
hasext  resb    1
hasdir  resb    1
ss_save resw    1
sp_save resw    1
nblocked resw   1
nm_at   resw    1
nkids   resw    1
kids    resw    32
pblock:
pb_env  resw    1
pb_tail resw    2
pb_f1   resw    2
pb_f2   resw    2
fcb1    resb    37
fcb2    resb    37
numbuf  resb    16
prog    resb    80
tail    resb    130
path    resb    160
blocked resw    MAXBLK
bss_end:resb    512
stk_top:
