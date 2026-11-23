; =====================================================================
;  FREENOTE.ASM  -  FREENOTE.COM 0.2 per a MS-DOS 3.20 o superior (8086)
;
;  Treu de la mem•ria els residents anotats per NOTE i restaura els
;  vectors que havien canviat. Funciona amb residents a la mem•ria
;  baixa, a l'alta (LOADHI, o UMB de DOS 5/6) o repartits entre totes
;  dues.
;
;   FREENOTE            allibera els residents posteriors a l'£ltima
;                       marca i esborra la marca (si era l'£nica, tamb‚
;                       treu NOTE)
;   FREENOTE /K         el mateix, per• conserva la marca
;   FREENOTE n [n...]   allibera nom‚s els residents indicats (n£meros
;                       de FREENOTE /L), si ‚s segur
;   FREENOTE nom [...]  allibera els residents que es diuen aix¡ (admet
;                       * i ?); si un nom sense comodins en troba m‚s
;                       d'un, cal /P (el primer), /U (el darrer) o /A
;                       (tots); un nom amb comodins els tria tots
;   FREENOTE /T         ho allibera tot, marques i NOTE inclosos
;   FREENOTE /L         llista les marques i els residents
;
;  Abans de tocar res simula tota l'operaci¢: si un vector d'un resident
;  que s'ha de treure l'ha enganxat despr‚s un altre que es queda, o si
;  algun vector continuaria apuntant a mem•ria que s'allibera, no fa res.
;
;  Compilar:  nasm -f bin FREENOTE.ASM -o FREENOTE.COM
; =====================================================================

        cpu     8086
        org     100h

%include "NOTE.INC"

MAXBLK  equ     128             ; blocs de mem•ria que es recorden
MAXPAT  equ     8               ; noms a la l¡nia d'ordres
PATSZ   equ     16

start:
        mov     ah,30h
        int     21h
        mov     [dosmaj],al
        cmp     al,3
        jae     .verok
        mov     dx,msg_ver
        call    puts
        mov     ax,4C01h
        int     21h
.verok: mov     sp,stack_top
        cld
        mov     di,bss_start            ; la zona no inicialitzada, a zero
        mov     cx,bss_clear
        xor     al,al
        rep     stosb

; ---------------------------------------------------------------------
;  Par…metres
; ---------------------------------------------------------------------
        mov     si,81h
.tok:   lodsb
        cmp     al,' '
        je      .tok
        cmp     al,9
        je      .tok
        cmp     al,','
        je      .tok
        cmp     al,13
        je      .parsed
        cmp     al,'/'
        je      .sw
        ; n£mero (nom‚s xifres) o nom
        dec     si
        mov     di,si
.dg:    mov     al,[di]
        cmp     al,'0'
        jb      .dge
        cmp     al,'9'
        ja      .dge
        inc     di
        jmp     .dg
.dge:   cmp     di,si
        je      .name
        call    is_end
        jne     .name
        lodsb
        xor     bx,bx
.num:   sub     al,'0'
        xor     ah,ah
        xchg    ax,bx
        mov     cx,10
        mul     cx
        add     bx,ax
        lodsb
        cmp     al,'0'
        jb      .ne
        cmp     al,'9'
        jbe     .num
.ne:    dec     si
        or      bx,bx
        jz      .bad
        cmp     bx,99
        ja      .bad
        mov     al,[nnums]
        cmp     al,MAXREC
        jae     .bad
        xor     ah,ah
        mov     di,ax
        mov     [nums+di],bl
        inc     byte [nnums]
        jmp     .tok
.name:  ; nom (sense extensi¢, en maj£scules)
        mov     al,[npat]
        cmp     al,MAXPAT
        jae     .bad
        mov     ah,PATSZ
        mul     ah
        add     ax,pats
        mov     di,ax
        xor     cx,cx
        mov     byte [indot],0
.nc:    lodsb
        call    is_end
        je      .nend
        cmp     al,'.'
        jne     .nc1
        mov     byte [indot],1
.nc1:   cmp     byte [indot],0
        jne     .nc
        cmp     al,'a'
        jb      .nc2
        cmp     al,'z'
        ja      .nc2
        sub     al,20h
.nc2:   cmp     cx,PATSZ-1
        jae     .nc
        stosb
        inc     cx
        jmp     .nc
.nend:  dec     si
        jcxz    .bad
        mov     byte [di],0
        inc     byte [npat]
        jmp     .tok
.sw:    lodsb
        cmp     al,'?'
        je      help
        and     al,0DFh
        cmp     al,'K'
        jne     .s1
        mov     byte [optkeep],1
        jmp     .tok
.s1:    cmp     al,'T'
        jne     .s2
        mov     byte [optall],1
        jmp     .tok
.s2:    cmp     al,'L'
        jne     .s3
        mov     byte [optlist],1
        jmp     .tok
.s3:    cmp     al,'P'
        je      .dm
        cmp     al,'U'
        je      .dm
        cmp     al,'A'
        jne     .bad
.dm:    mov     [dupmode],al
        jmp     .tok
.bad:   mov     dx,msg_parm
        call    puts
        mov     ax,4C01h
        int     21h
.parsed:

; ---------------------------------------------------------------------
;  Localitza NOTE i en copia les dades
; ---------------------------------------------------------------------
        call    umb_link
        call    find_note
        or      ax,ax
        jnz     .have
        mov     dx,msg_nonote
        call    puts
        jmp     exit_err
.have:  mov     [nseg],ax
        push    ds
        mov     ds,ax
        mov     al,[N_NREC]
        mov     ah,[N_NDIFF]
        mov     bl,[N_FLAGS]
        pop     ds
        mov     [nrec],al
        mov     [ndiff],ah
        mov     [nflags],bl
        push    ds
        push    ds
        pop     es
        mov     ds,[nseg]
        mov     si,N_HO21
        mov     di,ho21
        mov     cx,12                   ; ho21, ho27, old21, old27
        rep     movsb
        mov     si,N_RECS
        mov     di,recs
        mov     cx,MAXREC*RECSZ
        rep     movsb
        mov     si,N_DIFFS
        mov     di,diffs
        mov     cx,MAXDIFF*DIFFSZ
        rep     movsb
        pop     ds

        call    scan_memory
        call    number_recs

        cmp     byte [optlist],0
        je      .nolist
        call    do_list
        jmp     exit_ok
.nolist:

; ---------------------------------------------------------------------
;  QuŠ s'ha de treure
; ---------------------------------------------------------------------
        cmp     byte [optall],0
        je      .notall
        xor     bx,bx                   ; /T: tot
.ta:    cmp     bl,[nrec]
        jae     .tadone
        mov     byte [sel+bx],1
        inc     bx
        jmp     .ta
.tadone:
        mov     byte [unload],1
        jmp     .selected
.notall:
        mov     al,[nnums]
        or      al,[npat]
        jnz     .chosen
        jmp     .default
.chosen:
        cmp     byte [nnums],0
        je      .names
        ; n£meros concrets
        xor     si,si
.nl:    mov     al,[nums+si]
        xor     bx,bx
.nf:    cmp     bl,[nrec]
        jae     .badnum
        cmp     [tsrno+bx],al
        je      .nfound
        inc     bx
        jmp     .nf
.nfound:
        mov     byte [sel+bx],1
        inc     si
        mov     ax,si
        cmp     al,[nnums]
        jb      .nl

        ; noms
.names: mov     byte [pidx],0
.pl:    mov     al,[pidx]
        cmp     al,[npat]
        jb      .pl1
        jmp     .selected
.pl1:   mov     ah,PATSZ
        mul     ah
        add     ax,pats
        mov     [curpat],ax
        mov     si,ax                   ; t‚ comodins?
        mov     byte [pwild],0
.hw:    lodsb
        or      al,al
        jz      .hwd
        cmp     al,'*'
        je      .hwy
        cmp     al,'?'
        jne     .hw
.hwy:   mov     byte [pwild],1
.hwd:   mov     byte [nmatch],0
        xor     bx,bx
.ml:    cmp     bl,[nrec]
        jae     .md
        call    rec_ptr
        cmp     byte [si+R_TYPE],'T'
        jne     .mn
        call    rec_name
        mov     si,[curpat]
        mov     di,namebuf
        call    glob
        jnc     .mn
        mov     al,[nmatch]
        xor     ah,ah
        mov     di,ax
        mov     [matches+di],bl
        inc     byte [nmatch]
.mn:    inc     bx
        jmp     .ml
.md:    mov     al,[nmatch]
        or      al,al
        jz      .noname
        cmp     al,1
        je      .mall
        mov     al,[dupmode]
        cmp     al,'P'
        je      .mfirst
        cmp     al,'U'
        je      .mlast
        cmp     al,'A'
        je      .mall
        cmp     byte [pwild],0
        jne     .mall
        jmp     .mdups
.mfirst:
        mov     bl,[matches]
        xor     bh,bh
        mov     byte [sel+bx],1
        jmp     .pn
.mlast: mov     bl,[nmatch]
        dec     bl
        xor     bh,bh
        mov     bl,[matches+bx]
        mov     byte [sel+bx],1
        jmp     .pn
.mall:  xor     cx,cx
        mov     cl,[nmatch]
        xor     si,si
.ma:    mov     bl,[matches+si]
        xor     bh,bh
        mov     byte [sel+bx],1
        inc     si
        loop    .ma
.pn:    inc     byte [pidx]
        jmp     .pl
.noname:
        mov     di,linebuf
        mov     si,msg_noname
        call    put_str
        mov     si,[curpat]
        call    put_str
        mov     al,'.'
        stosb
        call    out_line
        jmp     exit_err
.mdups: mov     di,linebuf
        mov     si,msg_dups
        call    put_str
        mov     si,[curpat]
        call    put_str
        mov     al,':'
        stosb
        xor     si,si
.dl0:   mov     al,' '
        stosb
        mov     bl,[matches+si]
        xor     bh,bh
        mov     al,[tsrno+bx]
        xor     ah,ah
        xor     dx,dx
        call    put_dec32
        inc     si
        mov     ax,si
        cmp     al,[nmatch]
        jae     .dl1
        mov     al,','
        stosb
        jmp     .dl0
.dl1:   call    out_line
        mov     dx,msg_dups2
        call    puts
        jmp     exit_err
.badnum:
        xor     ah,ah
        push    ax
        mov     di,linebuf
        mov     si,msg_badnum
        call    put_str
        pop     ax
        xor     dx,dx
        call    put_dec32
        call    out_line
        jmp     exit_err
.default:
        ; l'£ltima marca
        mov     bl,[nrec]
        xor     bh,bh
.lm:    or      bx,bx
        jz      .nomark
        dec     bx
        call    rec_ptr
        cmp     byte [si+R_TYPE],'M'
        jne     .lm
        mov     [lastmark],bl
        cmp     byte [optkeep],0
        jne     .keep
        mov     byte [sel+bx],1         ; la marca tamb‚ se'n va
.keep:  inc     bx
        jmp     .after
.nomark:
        xor     bx,bx
.after: cmp     bl,[nrec]
        jae     .chkun
        call    rec_ptr
        cmp     byte [si+R_TYPE],'T'
        jne     .an
        mov     byte [sel+bx],1
.an:    inc     bx
        jmp     .after
.chkun: ; si no queda cap registre, tamb‚ es treu NOTE
        cmp     byte [optkeep],0
        jne     .selected
        xor     bx,bx
.cu:    cmp     bl,[nrec]
        jae     .allgone
        cmp     byte [sel+bx],0
        je      .selected
        inc     bx
        jmp     .cu
.allgone:
        mov     byte [unload],1
.selected:
        ; hi ha res a fer?
        cmp     byte [unload],0
        jne     .work
        xor     bx,bx
.any:   cmp     bl,[nrec]
        jae     .nothing
        cmp     byte [sel+bx],0
        jne     .work
        inc     bx
        jmp     .any
.nothing:
        mov     dx,msg_nothing
        call    puts
        jmp     exit_ok
.work:

; ---------------------------------------------------------------------
;  Simulaci¢ (no es toca res)
; ---------------------------------------------------------------------
        cli
        push    ds
        push    ds
        pop     es
        xor     si,si
        mov     ds,si
        mov     di,sim
        mov     cx,512
        rep     movsw
        pop     ds
        sti

        mov     bl,[nrec]
        xor     bh,bh
.sr:    or      bx,bx
        jnz     .sr1
        jmp     .simun
.sr1:   dec     bx
        cmp     byte [sel+bx],0
        je      .sr
        call    rec_ptr
        cmp     byte [si+R_TYPE],'T'
        jne     .sr
        mov     [currec],bx
        test    byte [si+R_FLAGS],1
        jz      .cmpl
        push    si
        mov     si,msg_incomp
        call    reason_rec
        pop     si
.cmpl:  xor     cx,cx
        mov     cl,[si+R_NDIFF]
        jcxz    .sr
        mov     al,[si+R_DIDX]
        mov     ah,DIFFSZ
        mul     ah
        add     ax,diffs
        mov     di,ax
.dl:    push    cx
        xor     ax,ax
        mov     al,[di+D_VEC]
        mov     [curvec],al
        shl     ax,1
        shl     ax,1
        mov     bp,ax
        add     bp,sim                  ; BP -> sim[v]
        mov     ax,[bp]
        mov     dx,[bp+2]
        cmp     ax,[di+D_NEW]
        jne     .dd
        cmp     dx,[di+D_NEW+2]
        jne     .dd
.rest:  mov     ax,[di+D_OLD]           ; restaura el valor anterior
        mov     [bp],ax
        mov     ax,[di+D_OLD+2]
        mov     [bp+2],ax
        jmp     .dn
.dd:    ; el vector ja no ‚s el que hi va posar
        mov     bx,[currec]
        cmp     byte [present+bx],0
        je      .dn                     ; ja no hi ‚s: no importa
        test    byte [di+D_FLAGS],1
        jz      .dn                     ; no apuntava al resident
        ; apunta encara dins del mateix resident? (s'ha tornat a enganxar)
        call    norm                    ; DX:AX -> AX segment normalitzat
        mov     bx,[currec]
        call    rec_ptr
        mov     dx,[si+R_PSP]
        call    in_owner                ; AX dins d'un bloc de DX?
        jc      .rest
        mov     si,msg_after
        call    reason_vec
.dn:    mov     bx,[currec]
        call    rec_ptr
        add     di,DIFFSZ
        pop     cx
        loop    .dl
        mov     bx,[currec]
        jmp     .sr

.simun: ; NOTE: les seves INT 21h i 27h
        cmp     byte [unload],0
        je      .chkv
        mov     ax,[nseg]
        mov     bx,[ho21]
        cmp     [sim+21h*4],bx
        jne     .cant
        cmp     [sim+21h*4+2],ax
        jne     .cant
        mov     bx,[ho27]
        cmp     [sim+27h*4],bx
        jne     .cant
        cmp     [sim+27h*4+2],ax
        jne     .cant
        mov     ax,[old21]
        mov     [sim+21h*4],ax
        mov     ax,[old21+2]
        mov     [sim+21h*4+2],ax
        mov     ax,[old27]
        mov     [sim+27h*4],ax
        mov     ax,[old27+2]
        mov     [sim+27h*4+2],ax
        jmp     .chkv
.cant:  mov     byte [unload],0
        mov     byte [cantunload],1

.chkv:  ; cap vector no pot quedar apuntant a mem•ria que s'allibera
        xor     cx,cx                   ; CX = vector
.cv:    cmp     cx,22h
        jb      .cv1
        cmp     cx,24h
        jbe     .cvn
.cv1:   mov     bp,cx
        shl     bp,1
        shl     bp,1
        mov     ax,[sim+bp]
        mov     dx,[sim+bp+2]
        call    norm
        call    freed_owner             ; -> BX = registre (o FFh = NOTE), CF=1
        jnc     .cvn
        mov     [curvec],cl
        push    cx
        mov     [currec],bx
        mov     si,msg_points
        cmp     bx,0FFh
        je      .cvnote
        call    reason_vec
        jmp     .cvp
.cvnote:
        mov     byte [unload],0         ; NOTE: simplement no es treu
        mov     byte [cantunload],1
        mov     ax,[nseg]               ; i les seves INT 21h/27h es queden
        mov     bx,[ho21]
        mov     [sim+21h*4],bx
        mov     [sim+21h*4+2],ax
        mov     bx,[ho27]
        mov     [sim+27h*4],bx
        mov     [sim+27h*4+2],ax
.cvp:   pop     cx
.cvn:   inc     cx
        cmp     cx,256
        jb      .cv

        cmp     byte [unsafe],0
        je      .apply
        mov     dx,msg_abort
        call    puts
        jmp     exit_err

; ---------------------------------------------------------------------
;  Aplica
; ---------------------------------------------------------------------
.apply:
        cli
        xor     ax,ax
        mov     es,ax
        xor     bx,bx
.wl:    mov     ax,[sim+bx]
        mov     dx,[sim+bx+2]
        cmp     ax,[es:bx]
        jne     .ww
        cmp     dx,[es:bx+2]
        je      .wn
.ww:    mov     [es:bx],ax
        mov     [es:bx+2],dx
.wn:    add     bx,4
        cmp     bx,1024
        jb      .wl
        sti
        push    ds
        pop     es

        ; allibera els blocs
        xor     si,si
.fb:    cmp     si,[nblk]
        jae     .fbd
        mov     bx,si
        shl     bx,1
        mov     ax,[blk_own+bx]
        call    owner_freed
        jnc     .fbn
        mov     ax,[blk_seg+bx]
        inc     ax
        mov     es,ax
        mov     ah,49h
        int     21h
        push    ds
        pop     es
.fbn:   inc     si
        jmp     .fb
.fbd:
        ; missatges: primer els residents, despr‚s les marques
        mov     byte [pass],'T'
.mp0:   xor     bx,bx
.ms:    cmp     bl,[nrec]
        jae     .msd
        cmp     byte [sel+bx],0
        je      .msn
        call    rec_ptr
        mov     al,[pass]
        cmp     [si+R_TYPE],al
        jne     .msn
        mov     di,linebuf
        cmp     byte [si+R_TYPE],'M'
        jne     .mt
        push    si
        mov     si,msg_mrm1
        call    put_str
        xor     ax,ax
        mov     al,[markno+bx]
        xor     dx,dx
        call    put_dec32
        mov     si,msg_mrm2
        call    put_str
        pop     si
        call    out_line
        jmp     .msn
.mt:    cmp     byte [present+bx],0
        jne     .mp
        push    si
        add     si,R_NAME
        call    put_name
        mov     si,msg_gone
        call    put_str
        pop     si
        call    out_line
        jmp     .msn
.mp:    push    si
        mov     si,msg_freed
        call    put_str
        pop     si
        push    si
        add     si,R_NAME
        call    put_name
        mov     si,msg_paren
        call    put_str
        push    bx
        shl     bx,1
        shl     bx,1
        mov     ax,[rbytes+bx]
        mov     dx,[rbytes+bx+2]
        add     [total],ax
        adc     [total+2],dx
        pop     bx
        call    put_dec32
        mov     si,msg_bytesp
        call    put_str
        pop     si
        call    out_line
.msn:   inc     bx
        jmp     .ms
.msd:   cmp     byte [pass],'M'
        je      .msd2
        mov     byte [pass],'M'
        jmp     .mp0
.msd2:
        cmp     byte [unload],0
        je      .noun
        mov     di,linebuf
        mov     si,msg_unload
        call    put_str
        mov     ax,[notebytes]
        mov     dx,[notebytes+2]
        add     [total],ax
        adc     [total+2],dx
        call    put_dec32
        mov     si,msg_bytesp
        call    put_str
        call    out_line
        jmp     .tot
.noun:  cmp     byte [cantunload],0
        je      .upd
        mov     dx,msg_cantun
        call    puts
.upd:   call    write_back
.tot:   mov     di,linebuf
        mov     si,msg_total
        call    put_str
        mov     ax,[total]
        mov     dx,[total+2]
        call    put_dec32
        mov     si,msg_bytesd
        call    put_str
        call    out_line

exit_ok:
        call    umb_restore
        mov     ax,4C00h
        int     21h
exit_err:
        call    umb_restore
        mov     ax,4C01h
        int     21h
help:
        mov     dx,msg_help
        call    puts
        mov     ax,4C00h
        int     21h

; ---------------------------------------------------------------------
;  Desa a NOTE els registres que queden, compactats
; ---------------------------------------------------------------------
write_back:
        mov     es,[nseg]
        mov     di,N_RECS
        xor     bx,bx                   ; registre origen
        xor     dl,dl                   ; registres nous
        xor     dh,dh                   ; canvis nous
.l:     cmp     bl,[nrec]
        jae     .done
        cmp     byte [sel+bx],0
        jne     .skip
        call    rec_ptr
        push    si
        push    di
        mov     cx,RECSZ
        rep     movsb                   ; copia el registre
        pop     di
        pop     si
        ; els seus canvis
        mov     al,[si+R_DIDX]
        mov     [es:di+R_DIDX],dh
        mov     cl,[si+R_NDIFF]
        xor     ch,ch
        jcxz    .nd
        push    si
        push    di
        mov     ah,DIFFSZ
        mul     ah
        add     ax,diffs
        mov     si,ax                   ; origen
        mov     al,dh
        mov     ah,DIFFSZ
        mul     ah
        add     ax,N_DIFFS
        mov     di,ax                   ; dest¡
        add     dh,cl
        mov     ax,cx
        mov     cl,DIFFSZ
        mul     cl
        mov     cx,ax
        rep     movsb
        pop     di
        pop     si
.nd:    add     di,RECSZ
        inc     dl
.skip:  inc     bx
        jmp     .l
.done:  mov     [es:N_NREC],dl
        mov     [es:N_NDIFF],dh
        and     byte [es:N_FLAGS],0FEh
        ; vectors coneguts = els actuals
        mov     di,N_EXP
        cli
        push    ds
        xor     si,si
        mov     ds,si
        mov     cx,512
        rep     movsw
        pop     ds
        sti
        push    ds
        pop     es
        ret

; ---------------------------------------------------------------------
;  Llista (/L)
; ---------------------------------------------------------------------
do_list:
        mov     di,linebuf
        mov     si,msg_l1
        call    put_str
        mov     ax,[nseg]
        call    put_hex16
        mov     al,' '
        stosb
        mov     ax,[nseg]
        call    put_locseg
        mov     si,msg_comma
        call    put_str
        mov     ax,[notebytes]
        mov     dx,[notebytes+2]
        call    put_dec32
        mov     si,msg_bytesd
        call    put_str
        call    out_line
        cmp     byte [nrec],0
        jne     .l0
        mov     dx,msg_empty
        call    puts
.l0:    xor     bx,bx
.l:     cmp     bl,[nrec]
        jb      .l1
        jmp     .done
.l1:    call    rec_ptr
        mov     di,linebuf
        cmp     byte [si+R_TYPE],'M'
        jne     .t
        push    si
        mov     si,msg_lm1
        call    put_str
        xor     ax,ax
        mov     al,[markno+bx]
        xor     dx,dx
        call    put_dec32
        mov     si,msg_lm2
        call    put_str
        pop     si
        call    out_line
        jmp     .n
.t:     ; n£mero
        mov     al,' '
        stosb
        mov     al,[tsrno+bx]
        cmp     al,10
        jae     .t2
        mov     byte [di],' '
        inc     di
.t2:    xor     ah,ah
        xor     dx,dx
        call    put_dec32
        mov     ax,'  '
        stosw
        push    si
        add     si,R_NAME
        call    put_name8
        pop     si
        mov     ax,'  '
        stosw
        push    si
        mov     si,msg_psp
        call    put_str
        pop     si
        mov     ax,[si+R_PSP]
        call    put_hex16
        mov     ax,'  '
        stosw
        cmp     byte [present+bx],0
        jne     .pr
        push    si
        mov     si,msg_lgone
        call    put_str
        pop     si
        call    out_line
        jmp     .n
.pr:    mov     al,[rloc+bx]
        push    si
        mov     si,msg_lbaja
        cmp     al,1
        je      .lc
        mov     si,msg_lalta
        cmp     al,2
        je      .lc
        mov     si,msg_lmixta
.lc:    call    put_str
        pop     si
        push    bx
        shl     bx,1
        shl     bx,1
        mov     ax,[rbytes+bx]
        mov     dx,[rbytes+bx+2]
        pop     bx
        ; mida alineada a la dreta (6 xifres)
        push    di
        mov     di,numbuf
        call    put_dec32
        mov     cx,di
        sub     cx,numbuf
        pop     di
        mov     ax,6
        sub     ax,cx
        jle     .al
        push    cx
        mov     cx,ax
        mov     al,' '
        rep     stosb
        pop     cx
.al:    push    si
        mov     si,numbuf
        rep     movsb
        pop     si
        push    si
        mov     si,msg_bytes
        call    put_str
        pop     si
        ; vectors
        xor     cx,cx
        mov     cl,[si+R_NDIFF]
        jcxz    .nov
        mov     al,[si+R_DIDX]
        mov     ah,DIFFSZ
        mul     ah
        add     ax,diffs
        push    si
        mov     si,ax
        push    si
        mov     si,msg_int
        call    put_str
        pop     si
        xor     dx,dx                   ; DX = vectors escrits
.vl:    test    byte [si+D_FLAGS],1
        jz      .vn
        cmp     dx,10
        jae     .vmore
        mov     al,' '
        stosb
        mov     al,[si+D_VEC]
        call    put_hex8
        inc     dx
        jmp     .vn
.vmore: cmp     dx,10
        jne     .vn
        mov     ax,'..'
        stosw
        inc     dx
.vn:    add     si,DIFFSZ
        loop    .vl
        pop     si
.nov:   test    byte [si+R_FLAGS],1
        jz      .ol
        push    si
        mov     si,msg_linc
        call    put_str
        pop     si
.ol:    call    out_line
.n:     inc     bx
        jmp     .l
.done:  test    byte [nflags],1
        jz      .r
        mov     dx,msg_lfull
        call    puts
.r:     ret

; ---------------------------------------------------------------------
;  Mem•ria: recorre la cadena de MCB
; ---------------------------------------------------------------------
scan_memory:
        mov     ah,52h
        int     21h
        mov     ax,[es:bx-2]
        push    ds
        pop     es
.l:     push    ax
        push    ds
        mov     ds,ax
        mov     dl,[0]
        mov     cx,[1]                  ; propietari
        mov     bx,[3]                  ; par…grafs
        pop     ds
        pop     ax
        cmp     dl,'M'
        je      .ok
        cmp     dl,'Z'
        je      .ok
        ret
.ok:    ; desa el bloc
        mov     si,[nblk]
        cmp     si,MAXBLK
        jae     .nosave
        shl     si,1
        mov     [blk_seg+si],ax
        mov     [blk_own+si],cx
        mov     [blk_size+si],bx
        inc     word [nblk]
.nosave:
        ; de quin registre ‚s?
        push    ax
        push    bx
        push    dx
        mov     [tmpseg],ax
        mov     [tmpsize],bx
        cmp     cx,[nseg]
        jne     .rec
        mov     ax,bx
        call    paras_bytes
        add     [notebytes],ax
        adc     [notebytes+2],dx
        jmp     .nx
.rec:   or      cx,cx
        jz      .nx
        xor     bx,bx
.rl:    cmp     bl,[nrec]
        jae     .nx
        call    rec_ptr
        cmp     byte [si+R_TYPE],'T'
        jne     .rn
        cmp     [si+R_PSP],cx
        jne     .rn
        mov     byte [present+bx],1
        mov     ax,[tmpseg]
        mov     dl,1
        cmp     ax,0A000h
        jb      .lw
        mov     dl,2
.lw:    or      [rloc+bx],dl
        mov     ax,[tmpsize]
        call    paras_bytes
        push    bx
        shl     bx,1
        shl     bx,1
        add     [rbytes+bx],ax
        adc     [rbytes+bx+2],dx
        pop     bx
.rn:    inc     bx
        jmp     .rl
.nx:    pop     dx
        pop     bx
        pop     ax
        cmp     dl,'Z'
        je      .end
        add     ax,bx
        inc     ax
        jmp     .l
.end:   ret

; AX par…grafs -> DX:AX bytes
paras_bytes:
        mov     dx,16
        mul     dx
        ret

; ZF=1 si AL acaba un mot de la l¡nia d'ordres
is_end:
        cmp     al,' '
        je      .x
        cmp     al,9
        je      .x
        cmp     al,','
        je      .x
        cmp     al,'/'
        je      .x
        cmp     al,13
.x:     ret

; Nom del registre SI -> namebuf (sense espais finals, en maj£scules)
rec_name:
        push    si
        push    di
        push    cx
        add     si,R_NAME
        mov     di,namebuf
        mov     cx,8
.c:     lodsb
        cmp     al,'a'
        jb      .s
        cmp     al,'z'
        ja      .s
        sub     al,20h
.s:     stosb
        loop    .c
.t:     cmp     di,namebuf
        je      .z
        cmp     byte [di-1],' '
        jne     .z
        dec     di
        jmp     .t
.z:     mov     byte [di],0
        pop     cx
        pop     di
        pop     si
        ret

; Compara el nom DI amb el patr¢ SI (* i ?).  CF=1 si coincideix
glob:
        push    bx
        push    dx
        xor     bx,bx                   ; BX = patr¢ despr‚s de l'£ltim '*'
.l:     mov     al,[di]
        or      al,al
        jz      .tail
        mov     ah,[si]
        cmp     ah,'*'
        je      .star
        cmp     ah,'?'
        je      .adv
        cmp     ah,al
        je      .adv
        or      bx,bx                   ; no coincideix: torna a l'£ltim '*'
        jz      .no
        mov     si,bx
        inc     dx
        mov     di,dx
        jmp     .l
.adv:   inc     si
        inc     di
        jmp     .l
.star:  inc     si
        mov     bx,si
        mov     dx,di
        jmp     .l
.tail:  cmp     byte [si],'*'
        jne     .end
        inc     si
        jmp     .tail
.end:   cmp     byte [si],0
        jne     .no
        pop     dx
        pop     bx
        stc
        ret
.no:    pop     dx
        pop     bx
        clc
        ret

; Numera marques i residents
number_recs:
        xor     bx,bx
        xor     cx,cx                   ; CL = marques, CH = residents
.l:     cmp     bl,[nrec]
        jae     .r
        call    rec_ptr
        cmp     byte [si+R_TYPE],'M'
        jne     .t
        inc     cl
        mov     [markno+bx],cl
        jmp     .n
.t:     inc     ch
        mov     [tsrno+bx],ch
.n:     inc     bx
        jmp     .l
.r:     ret

; BX = ¡ndex -> SI = registre (c•pia local)
rec_ptr:
        push    ax
        mov     ax,bx
        mov     si,RECSZ
        push    dx
        mul     si
        pop     dx
        add     ax,recs
        mov     si,ax
        pop     ax
        ret

; DX:AX (despla‡ament:segment) -> AX = segment normalitzat
norm:
        push    cx
        mov     cl,4
        shr     ax,cl
        add     ax,dx
        pop     cx
        ret

; CF=1 si el segment AX ‚s dins d'un bloc del propietari DX
in_owner:
        push    bx
        push    si
        xor     si,si
.l:     cmp     si,[nblk]
        jae     .no
        mov     bx,si
        shl     bx,1
        cmp     [blk_own+bx],dx
        jne     .n
        call    in_block
        jc      .yes
.n:     inc     si
        jmp     .l
.no:    clc
.yes:   pop     si
        pop     bx
        ret

; CF=1 si el segment AX ‚s dins del bloc BX (¡ndex*2)
in_block:
        push    cx
        mov     cx,[blk_seg+bx]
        inc     cx
        cmp     ax,cx
        jb      .no
        add     cx,[blk_size+bx]
        cmp     ax,cx
        jae     .no
        pop     cx
        stc
        ret
.no:    pop     cx
        clc
        ret

; El segment AX ‚s dins de mem•ria que s'allibera?
; CF=1 i BX = registre (FFh = NOTE)
freed_owner:
        push    si
        push    dx
        xor     si,si
.l:     cmp     si,[nblk]
        jae     .no
        mov     bx,si
        shl     bx,1
        push    ax
        mov     ax,[blk_own+bx]
        call    owner_freed             ; CF=1, DX = registre
        pop     ax
        jnc     .n
        call    in_block
        jnc     .n
        mov     bx,dx
        pop     dx
        pop     si
        stc
        ret
.n:     inc     si
        jmp     .l
.no:    pop     dx
        pop     si
        clc
        ret

; AX = propietari -> CF=1 si s'allibera, DX = registre (FFh = NOTE)
owner_freed:
        push    bx
        push    si
        or      ax,ax
        jz      .no
        cmp     byte [unload],0
        je      .t
        cmp     ax,[nseg]
        jne     .t
        mov     dx,0FFh
        jmp     .yes
.t:     xor     bx,bx
.l:     cmp     bl,[nrec]
        jae     .no
        cmp     byte [sel+bx],0
        je      .n
        call    rec_ptr
        cmp     byte [si+R_TYPE],'T'
        jne     .n
        cmp     [si+R_PSP],ax
        jne     .n
        mov     dx,bx
.yes:   pop     si
        pop     bx
        stc
        ret
.n:     inc     bx
        jmp     .l
.no:    pop     si
        pop     bx
        clc
        ret

; Motiu de no fer res: "NOM: missatge" (SI) per al registre [currec]
reason_rec:
        mov     byte [unsafe],2
        push    bx
        push    di
        push    si
        mov     bx,[currec]
        call    rec_ptr
        add     si,R_NAME
        mov     di,linebuf
        call    put_name
        pop     si
        call    put_str
        call    out_line
        pop     di
        pop     bx
        ret
; "NOM: la INT xx " + missatge (SI)
reason_vec:
        mov     byte [unsafe],2
        push    bx
        push    di
        push    si
        mov     bx,[currec]
        call    rec_ptr
        add     si,R_NAME
        mov     di,linebuf
        call    put_name
        mov     si,msg_laint
        call    put_str
        mov     al,[curvec]
        call    put_hex8
        mov     al,'h'
        stosb
        pop     si
        call    put_str
        call    out_line
        pop     di
        pop     bx
        ret

; ---------------------------------------------------------------------
;  NOTE a la mem•ria (com a NOTE.ASM)
; ---------------------------------------------------------------------
find_note:
        mov     ah,52h
        int     21h
        mov     ax,[es:bx-2]
.l:     mov     es,ax
        mov     dl,[es:0]
        cmp     dl,'M'
        je      .ok
        cmp     dl,'Z'
        jne     .none
.ok:    mov     bx,ax
        inc     bx
        cmp     [es:1],bx
        jne     .next
        push    es
        mov     es,bx
        mov     di,N_SIG
        mov     si,sigtxt
        mov     cx,6
        repe    cmpsb
        pop     es
        je      .found
.next:  cmp     dl,'Z'
        je      .none
        add     ax,[es:3]
        inc     ax
        jmp     .l
.found: mov     ax,bx
        push    ds
        pop     es
        ret
.none:  xor     ax,ax
        push    ds
        pop     es
        ret

umb_link:
        cmp     byte [dosmaj],5
        jb      .r
        mov     ax,5802h
        int     21h
        jc      .r
        mov     [umbstate],al
        mov     byte [umbsaved],1
        mov     ax,5803h
        mov     bx,1
        int     21h
.r:     ret
umb_restore:
        cmp     byte [umbsaved],0
        je      .r
        mov     ax,5803h
        xor     bh,bh
        mov     bl,[umbstate]
        int     21h
.r:     ret

; ---------------------------------------------------------------------
;  Sortida
; ---------------------------------------------------------------------
put_str:
        lodsb
        or      al,al
        jz      .x
        stosb
        jmp     put_str
.x:     ret

; nom de 8 car…cters sense els espais finals
put_name:
        push    cx
        push    bx
        mov     bx,si
        add     bx,8
.t:     cmp     bx,si
        je      .x
        cmp     byte [bx-1],' '
        jne     .c
        dec     bx
        jmp     .t
.c:     lodsb
        stosb
        cmp     si,bx
        jb      .c
.x:     pop     bx
        pop     cx
        ret
; nom de 8 car…cters tal qual
put_name8:
        push    cx
        mov     cx,8
        rep     movsb
        pop     cx
        ret

put_locseg:                             ; AX = segment
        mov     si,msg_lconv
        cmp     ax,0A000h
        jb      .s
        mov     si,msg_lsup
.s:     jmp     put_str

put_hex16:
        push    ax
        mov     al,ah
        call    put_hex8
        pop     ax
put_hex8:
        push    ax
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

put_dec32:
        push    bx
        push    cx
        push    si
        xor     si,si
        mov     cx,10
.d:     mov     bx,ax
        mov     ax,dx
        xor     dx,dx
        div     cx
        xchg    ax,bx
        div     cx
        push    dx
        inc     si
        mov     dx,bx
        mov     bx,ax
        or      bx,dx
        jnz     .d
.o:     pop     ax
        add     al,'0'
        stosb
        dec     si
        jnz     .o
        pop     si
        pop     cx
        pop     bx
        ret

out_line:
        mov     ax,0A0Dh
        stosw
        mov     byte [di],0
        mov     dx,linebuf
puts:
        push    si
        push    cx
        push    bx
        push    ax
        mov     si,dx
        xor     cx,cx
.l:     cmp     byte [si],0
        je      .w
        inc     si
        inc     cx
        jmp     .l
.w:     jcxz    .x
        mov     bx,1
        mov     ah,40h
        int     21h
.x:     pop     ax
        pop     bx
        pop     cx
        pop     si
        ret

; ---------------------------------------------------------------------
;  Dades (missatges en castell…)
; ---------------------------------------------------------------------
sigtxt      db  "NOTE01"
msg_ver     db  "Versi¢n incorrecta de DOS",13,10,0
msg_parm    db  "Par metro no v lido",13,10,0
msg_nonote  db  "NOTE no est  instalado.",13,10,0
msg_nothing db  "No hay residentes que liberar.",13,10,0
msg_badnum  db  "N£mero de residente no v lido - ",0
msg_noname  db  "No hay ning£n residente que se llame ",0
msg_dups    db  "Hay varios residentes que se llaman ",0
msg_dups2   db  "Indique cu l con /P (el primero), /U (el £ltimo) o /A (todos),",13,10
            db  "o con su n£mero (FREENOTE /L).",13,10,0
msg_incomp  db  ": no se conocen todos sus vectores (la tabla de NOTE estaba llena)",0
msg_laint   db  ": la INT ",0
msg_after   db  " ha sido enganchada despu‚s por otro residente",0
msg_points  db  " apunta todav¡a a su memoria",0
msg_abort   db  "No se ha liberado nada. Libere tambi‚n los residentes cargados despu‚s.",13,10,0
msg_freed   db  "Liberado ",0
msg_paren   db  " (",0
msg_bytesp  db  " bytes)",0
msg_bytesd  db  " bytes.",0
msg_gone    db  " ya no estaba en memoria; se quita de la lista.",0
msg_mrm1    db  "Marca ",0
msg_mrm2    db  " eliminada.",0
msg_unload  db  "NOTE desinstalado (",0
msg_cantun  db  "NOTE se queda en memoria: la INT 21h o 27h ha sido enganchada por otro programa.",13,10,0
msg_total   db  "Memoria liberada: ",0
msg_l1      db  "NOTE 0.2 en ",0
msg_comma   db  ", ",0
msg_lconv   db  "(memoria convencional)",0
msg_lsup    db  "(memoria superior)",0
msg_empty   db  "No hay marcas.",13,10,0
msg_lm1     db  "--- Marca ",0
msg_lm2     db  " ---",0
msg_psp     db  "PSP ",0
msg_lgone   db  "ya no est  en memoria",0
msg_lbaja   db  "baja   ",0
msg_lalta   db  "alta   ",0
msg_lmixta  db  "mixta  ",0
msg_bytes   db  " bytes",0
msg_int     db  "  INT",0
msg_linc    db  " (incompleto)",0
msg_lfull   db  "La tabla de NOTE se llen¢: algunos residentes no se anotaron.",13,10,0
msg_help    db  "Libera los programas residentes cargados despu‚s de NOTE.",13,10,13,10
            db  "FREENOTE [n|nombre [...]] [/P|/U|/A] [/K] [/T] [/L]",13,10,13,10
            db  "  (nada)  Libera los residentes posteriores a la £ltima marca y",13,10
            db  "          elimina la marca (si era la £nica, tambi‚n quita NOTE).",13,10
            db  "  n       Libera s¢lo los residentes indicados (n£meros de /L).",13,10
            db  "  nombre  Libera los residentes con ese nombre (admite * y ?).",13,10
            db  "  /P /U /A  Si un nombre sin comodines coincide con varios:",13,10
            db  "          el primero, el £ltimo o todos. Con comodines, todos.",13,10
            db  "  /K      Como sin nada, pero conserva la marca.",13,10
            db  "  /T      Lo libera todo: residentes, marcas y NOTE.",13,10
            db  "  /L      Muestra las marcas y los residentes.",13,10,0

dosmaj      db  0
umbstate    db  0
umbsaved    db  0
optkeep     db  0
optall      db  0
optlist     db  0
nnums       db  0
unload      db  0
cantunload  db  0
unsafe      db  0
lastmark    db  0
curvec      db  0
pass        db  0
npat        db  0
dupmode     db  0
indot       db  0
pidx        db  0
pwild       db  0
nmatch      db  0
nblk        dw  0
total       dd  0
notebytes   dd  0

        section .bss
        alignb  2
bss_start:
nseg        resw 1
nrec        resb 1
ndiff       resb 1
nflags      resb 1
            resb 1
ho21        resw 1
ho27        resw 1
old21       resd 1
old27       resd 1
currec      resw 1
tmpseg      resw 1
tmpsize     resw 1
numbuf      resb 12
curpat      resw 1
pats        resb MAXPAT*PATSZ
matches     resb MAXREC
namebuf     resb 10
nums        resb MAXREC
sel         resb MAXREC
tsrno       resb MAXREC
markno      resb MAXREC
present     resb MAXREC
rloc        resb MAXREC
rbytes      resd MAXREC
recs        resb MAXREC*RECSZ
diffs       resb MAXDIFF*DIFFSZ
blk_seg     resw MAXBLK
blk_own     resw MAXBLK
blk_size    resw MAXBLK
sim         resb 1024
linebuf     resb 160
bss_clear   equ $-bss_start
            resb 1024
stack_top:
