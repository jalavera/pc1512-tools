; =====================================================================
;  MEM.ASM  -  MEM per a MS-DOS 3.20 i 6.22 (Amstrad PC1512) versio 0.31
;
;  Substitut de MEM 6.22 que entÇn les estructures de DOS 3.x:
;  - noms de programa tret de l'entorn (DOS 3 no els desa al MCB)
;  - mapa de la zona entre el final de la memïria convencional i 1 MB:
;    v°deo, ROM, cadenes de blocs (UMB), codi resident trobat pels
;    vectors d'interrupci¢ i controladors carregats a dalt.
;  Opcions: /C /D /F /M[:]mïdul /P /?  (i les formes llargues)
;
;  Assemblar:  nasm -f bin MEM.ASM -o MEM.COM
;  (font en CP850: els textos es mostren directament)
; =====================================================================
        cpu     8086
        org     100h

F_C     equ     1
F_D     equ     2
F_F     equ     4
F_M     equ     8
F_P     equ     16
F_H     equ     32
F_NP    equ     64                      ; /NP o /P-: sense pausa
F_G     equ     128                     ; /G: cerca dels fitxers del GEM

MAXBLK  equ     200
MAXBUF  equ     128                     ; BUFFERS que MEM /D pot ordenar
MAXMOD  equ     64
MAXROM  equ     12
MAXREG  equ     8
MAXGRP  equ     16
MAXGV   equ     16
RESGV   equ     9               ; vectors per fila a la taula
MAXDEV  equ     48
MAXLAB  equ     24              ; fitxers del GEM reconeguts dins els blocs

C_VIDEO equ     0
C_ROM   equ     1
C_CHAIN equ     2
C_RESID equ     3
C_SYSROM equ    4
C_USED  equ     5
C_EMPTY equ     6
C_ZERO  equ     7
C_RAMFF equ     8               ; RAM sense usar, plena de FFh
C_RAM0  equ     9               ; RAM sense usar, a zero
C_DOSK  equ     10              ; nucli del DOS a dalt (HIDOS)

start:
        cld
        ; DOS no posa a zero la memoria que hi ha despres del .COM:
        ; totes les variables sense valor inicial comencen a zero
        mov     di,bss_start
        mov     cx,bss_end-bss_start
        xor     al,al
        rep     stosb
        call    lreset
        call    parse
        jnc     .p_ok
        mov     ax,4C01h
        int     21h
.p_ok:  or      byte [flags],F_P        ; pÖgina a pÖgina per defecte,
        test    byte [flags],F_NP       ;   menys amb /NP o /P-, o si la
        jnz     .np                     ;   sortida no Çs la pantalla
        mov     ax,4400h                ;   (MEM > FITXER)
        mov     bx,1
        int     21h
        jc      .np
        and     dl,82h                  ; dispositiu i consola de sortida
        cmp     dl,82h
        je      .pp
.np:    and     byte [flags],~F_P
.pp:    test    byte [flags],F_H
        jz      .nohelp
        call    show_help
        jmp     exit_ok
.nohelp:
        mov     ah,30h
        int     21h
        cmp     al,3
        jae     .v_ok
        mov     si,s_badver
        call    pline
        mov     ax,4C01h
        int     21h
.v_ok:  call    get_country
        call    gather
        jnc     .g_ok
        mov     si,s_chainerr
        call    pline
        mov     ax,4C02h
        int     21h
.g_ok:  call    check_ems
        mov     al,[flags]
        test    al,F_M
        jz      .n1
        call    do_module
        jmp     short .ver
.n1:    test    al,F_D
        jz      .n2
        call    do_debug
        jmp     short .ver
.n2:    test    al,F_C
        jz      .n3
        call    do_classify
        jmp     short .ver
.n3:    test    al,F_F
        jz      .n4
        call    do_free
        jmp     short .ver
.n4:    call    do_summary
.ver:   mov     si,s_buit               ; (0.30) la versio, al final de tot
        call    pline
        mov     si,s_ver
        call    pline
exit_ok:
        mov     ax,4C00h
        int     21h

; =====================================================================
;  L°nia de sortida
; =====================================================================
lreset: mov     word [lptr],lbuf
        ret

lputc:  push    di
        mov     di,[lptr]
        cmp     di,lbuf+150
        jae     .full
        mov     [di],al
        inc     di
        mov     [lptr],di
.full:  pop     di
        ret

lputs:  push    ax
        push    si
.l:     lodsb
        or      al,al
        jz      .e
        call    lputc
        jmp     .l
.e:     pop     si
        pop     ax
        ret

; CL = columna: omple amb espais fins a CL
lcol:   push    ax
.l:     mov     ax,[lptr]
        sub     ax,lbuf
        cmp     al,cl
        jae     .e
        mov     al,' '
        call    lputc
        jmp     .l
.e:     pop     ax
        ret

; SI = cadena, CL = columna on acaba (exclusiva): alineat a la dreta
lputr:  push    ax
        push    cx
        call    strlen
        sub     cl,al
        jnc     .ok
        xor     cl,cl
.ok:    call    lcol
        call    lputs
        pop     cx
        pop     ax
        ret

strlen: push    si
        xor     ax,ax
.l:     cmp     byte [si],0
        je      .e
        inc     si
        inc     ax
        jmp     .l
.e:     pop     si
        ret

; escriu la l°nia + CR LF (i fa la pausa de /P)
lflush: push    ax
        push    bx
        push    cx
        push    dx
        mov     al,13
        call    lputc
        mov     al,10
        call    lputc
        mov     cx,[lptr]
        sub     cx,lbuf
        mov     dx,lbuf
        mov     bx,1
        mov     ah,40h
        int     21h
        call    lreset
        test    byte [flags],F_P
        jz      .e
        inc     word [nlines]
        cmp     word [nlines],23
        jb      .e
        call    page_pause
.e:     pop     dx
        pop     cx
        pop     bx
        pop     ax
        ret

page_pause:
        mov     dx,s_pause
        mov     cx,s_pause_len
        mov     bx,1
        mov     ah,40h
        int     21h
        mov     ah,8
        int     21h
        or      al,al
        jnz     .k
        mov     ah,8
        int     21h
.k:     mov     dx,s_unpause
        mov     cx,s_unpause_len
        mov     bx,1
        mov     ah,40h
        int     21h
        mov     word [nlines],0
        ret

blank:  call    lflush
        ret

; SI = cadena: l°nia completa
pline:  call    lreset
        call    lputs
        call    lflush
        ret

; =====================================================================
;  N£meros
; =====================================================================
; DX:AX -> numstr (amb separador de milers), SI = numstr
fmt_u32:
        push    ax
        push    bx
        push    cx
        push    dx
        push    di
        mov     di,numstr+15
        mov     byte [di],0
        xor     bl,bl
.l:     push    ax
        mov     ax,dx
        xor     dx,dx
        mov     cx,10
        div     cx
        mov     [fq_hi],ax
        pop     ax
        div     cx
        cmp     bl,3
        jne     .nosep
        dec     di
        mov     bh,[thsep]
        mov     [di],bh
        xor     bl,bl
.nosep: dec     di
        add     dl,'0'
        mov     [di],dl
        inc     bl
        mov     dx,[fq_hi]
        mov     cx,ax
        or      cx,dx
        jnz     .l
        mov     si,di
        pop     di
        pop     dx
        pop     cx
        pop     bx
        pop     ax
        ret

; DX:AX n£mero, CL columna final
put_num_r:
        push    si
        call    fmt_u32
        call    lputr
        pop     si
        ret

; DX:AX n£mero de K, CL columna final: "nnnK"
put_numk_r:
        push    si
        push    di
        call    fmt_u32
        mov     di,kstr
.c:     lodsb
        mov     [di],al
        inc     di
        or      al,al
        jnz     .c
        mov     word [di-1],'K'
        mov     si,kstr
        call    lputr
        pop     di
        pop     si
        ret

; DX:AX n£mero de K, CL columna final: "(nnnK)"
put_numkp_r:
        push    si
        push    di
        call    fmt_u32
        mov     di,kstr
        mov     byte [di],'('
        inc     di
.c:     lodsb
        mov     [di],al
        inc     di
        or      al,al
        jnz     .c
        mov     byte [di-1],'K'
        mov     word [di],')'
        mov     si,kstr
        call    lputr
        pop     di
        pop     si
        ret

; DX:AX bytes, CL columna final: "(nnn bytes)"
put_bytesp_r:
        push    si
        push    di
        call    fmt_u32
        mov     di,kstr
        mov     byte [di],'('
        inc     di
.c:     lodsb
        mov     [di],al
        inc     di
        or      al,al
        jnz     .c
        dec     di
        mov     si,s_bytes_cl
.c2:    lodsb
        mov     [di],al
        inc     di
        or      al,al
        jnz     .c2
        mov     si,kstr
        call    lputr
        pop     di
        pop     si
        ret

; parÖgrafs DX:AX -> bytes DX:AX
par2bytes:
        push    cx
        mov     cx,4
.l:     shl     ax,1
        rcl     dx,1
        loop    .l
        pop     cx
        ret

; parÖgrafs DX:AX -> K arrodonits DX:AX
par2k:  push    cx
        add     ax,32
        adc     dx,0
        mov     cx,6
.l:     shr     dx,1
        rcr     ax,1
        loop    .l
        pop     cx
        ret

; AX parÖgrafs (16 bits), CL columna: bytes
put_pb_r:
        push    ax
        push    dx
        xor     dx,dx
        call    par2bytes
        call    put_num_r
        pop     dx
        pop     ax
        ret

; AX parÖgrafs, CL columna: "(nnnK)"
put_pkp_r:
        push    ax
        push    dx
        xor     dx,dx
        call    par2k
        call    put_numkp_r
        pop     dx
        pop     ax
        ret

; AX -> 4 xifres hex
lhex4:  push    ax
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
.d:     call    lputc
        pop     ax
        loop    .l
        pop     cx
        pop     ax
        ret

; AX = primer parÖgraf, CX = parÖgrafs -> "AAAA0-BBBBF" (o "AAAA0" si CX = 0)
lrange: push    ax
        call    lhex4
        mov     al,'0'
        call    lputc
        pop     ax
        jcxz    .x
        push    ax
        mov     al,'-'
        call    lputc
        pop     ax
        push    ax
        add     ax,cx
        dec     ax
        call    lhex4
        mov     al,'F'
        call    lputc
        pop     ax
.x:     ret

; AX segment -> "0SSSS"
lhex5:  push    ax
        mov     al,'0'
        call    lputc
        pop     ax
        call    lhex4
        ret

; AL -> 2 xifres hex
lhex2:  push    ax
        push    cx
        mov     ah,al
        mov     cl,4
        shr     al,cl
        call    .dig
        mov     al,ah
        call    .dig
        pop     cx
        pop     ax
        ret
.dig:   and     al,0Fh
        add     al,'0'
        cmp     al,'9'
        jbe     .o
        add     al,7
.o:     call    lputc
        ret

upcase: cmp     al,'a'
        jb      .e
        cmp     al,'z'
        ja      .e
        sub     al,20h
.e:     ret

; compara DS:SI amb DS:DI (ASCIIZ); ZF=1 si s¢n iguals
strcmp: push    si
        push    di
        push    ax
.l:     mov     al,[si]
        cmp     al,[di]
        jne     .e
        or      al,al
        jz      .e
        inc     si
        inc     di
        jmp     .l
.e:     pop     ax
        pop     di
        pop     si
        ret

; copia DS:SI -> DS:DI (ASCIIZ)
strcpy: push    ax
        push    si
        push    di
.l:     lodsb
        mov     [di],al
        inc     di
        or      al,al
        jnz     .l
        pop     di
        pop     si
        pop     ax
        ret

; =====================================================================
;  L°nia d'ordres
; =====================================================================
parse:  mov     si,81h
        mov     bl,[80h]
        xor     bh,bh
        cmp     bx,7Eh
        jbe     .lenok
        mov     bx,7Eh
.lenok: mov     byte [si+bx],0
.next:  lodsb
        cmp     al,' '
        je      .next
        cmp     al,9
        je      .next
        cmp     al,13
        je      .done
        or      al,al
        jz      .done
        cmp     al,'/'
        je      .switch
        cmp     al,'-'                  ; -D, -C... com a /D, /C
        je      .switch
        dec     si
        cmp     byte [wantname],0
        je      .badparm
        call    readname
        mov     byte [wantname],0
        jmp     .next
.switch:
        mov     di,swbuf
        xor     cx,cx
.sl:    lodsb
        call    upcase
        cmp     al,'?'
        je      .st
        cmp     al,'-'                  ; '-' nomÇs a /P- (si no, Çs
        jne     .sl2                    ;   l'inici d'una altra opci¢)
        cmp     cx,1
        jne     .se
        cmp     byte [swbuf],'P'
        jne     .se
        jmp     short .st
.sl2:
        cmp     al,'A'
        jb      .se
        cmp     al,'Z'
        ja      .se
.st:    cmp     cx,10
        jae     .sl
        mov     [di],al
        inc     di
        inc     cx
        jmp     .sl
.se:    dec     si
        mov     byte [di],0
        mov     bx,swtab
.tl:    mov     di,[bx]
        or      di,di
        jz      .badsw
        push    si
        mov     si,swbuf
        call    strcmp
        pop     si
        je      .found
        add     bx,4
        jmp     .tl
.found: mov     al,[bx+2]
        or      [flags],al
        test    al,F_M
        jz      .next
        cmp     byte [si],':'
        jne     .wn
        inc     si
        call    readname
        jmp     .next
.wn:    mov     byte [wantname],1
        jmp     .next
.done:  cmp     byte [wantname],0
        je      .ok
        test    byte [flags],F_H
        jnz     .ok
        mov     si,s_noname
        call    pline
        stc
        ret
.ok:    clc
        ret
.badsw: call    lreset
        mov     si,s_badsw
        call    lputs
        mov     al,'/'
        call    lputc
        mov     si,swbuf
        call    lputs
        call    lflush
        stc
        ret
.badparm:
        call    lreset
        push    si
        mov     si,s_badparm
        call    lputs
        pop     si
.bp:    lodsb
        cmp     al,' '
        jbe     .bpe
        cmp     al,'/'
        je      .bpe
        call    lputc
        jmp     .bp
.bpe:   call    lflush
        stc
        ret

; llegeix un nom de mïdul (fins a 8 carÖcters) a modname
readname:
        mov     di,modname
        xor     cx,cx
.l:     lodsb
        cmp     al,' '
        jbe     .e
        cmp     al,'/'
        je      .e
        call    upcase
        cmp     cx,8
        jae     .l
        mov     [di],al
        inc     di
        inc     cx
        jmp     .l
.e:     dec     si
        mov     byte [di],0
        ret

get_country:
        mov     ax,3800h
        mov     dx,cbuf
        int     21h
        jc      .e
        mov     al,[cbuf+7]
        cmp     al,' '
        jb      .e
        mov     [thsep],al
.e:     ret

; =====================================================================
;  Recollida d'informaci¢
; =====================================================================
gather: mov     [mypsp],cs
        mov     ah,30h
        int     21h
        mov     [dosmaj],al
        call    find_code
        mov     ah,52h
        int     21h
        mov     [dosseg],es
        mov     ax,[es:bx-2]
        mov     [firstmcb],ax
        lea     ax,[bx+22h]
        mov     [nulofs],ax
        int     12h
        mov     [convkb],ax
        mov     cl,6
        shl     ax,cl
        mov     [convtop],ax
        mov     word [nblk],0
        mov     byte [nreg],0
        mov     ax,[firstmcb]
.w:     mov     es,ax
        mov     dl,[es:0]
        cmp     dl,'M'
        je      .ok
        cmp     dl,'Z'
        jne     .err
.ok:    mov     bx,[nblk]
        cmp     bx,MAXBLK
        jae     .err
        mov     cl,0
        cmp     ax,[convtop]
        jb      .cv
        ; bloc de sistema 'SC' dins la memïria superior (LOADHI, DOS 5):
        ; tapa una ROM o un forat entre dos trossos de RAM. No es compta
        ; i el bloc segÅent comenáa una regi¢ nova.
        cmp     word [es:1],0008h
        jne     .nsc
        cmp     word [es:8],'SC'
        jne     .nsc
        call    is_code                 ; (0.31) el codi del DOS 6 (HIDOS6):
        jnc     .nsc                    ;   un bloc normal, no un forat
        mov     bl,[nreg]
        xor     bh,bh
        shl     bx,1
        mov     cx,ax
        inc     cx
        mov     [reg_end+bx],cx
        mov     byte [newreg],1
        mov     cx,[es:3]
        jmp     .adv
.nsc:   mov     cl,[nreg]
        cmp     cl,0
        je      .nreg
        cmp     byte [newreg],0
        je      .cv
.nreg:  cmp     cl,MAXREG-1
        jae     .cv
        inc     cl
        mov     [nreg],cl
        mov     byte [newreg],0
        push    bx
        mov     bl,cl
        xor     bh,bh
        shl     bx,1
        mov     [reg_start+bx],ax
        pop     bx
.cv:    mov     [blk_reg+bx],cl
        shl     bx,1
        mov     [blk_seg+bx],ax
        mov     cx,[es:1]
        mov     [blk_own+bx],cx
        mov     cx,[es:3]
        mov     [blk_size+bx],cx
        ; bloc convencional que passa del final (enllaá a memïria superior):
        ; es compta nomÇs fins al final de la memïria convencional
        cmp     ax,[convtop]
        jae     .nc
        mov     di,ax
        add     di,cx
        jc      .cl
        inc     di
        jz      .cl
        cmp     di,[convtop]
        jbe     .nc
.cl:    mov     di,[convtop]
        sub     di,ax
        dec     di
        mov     [blk_size+bx],di
.nc:    inc     word [nblk]
.adv:   add     ax,cx
        jc      .err
        inc     ax
        cmp     dl,'Z'
        je      .zz
        or      ax,ax
        jz      .err
        jmp     .w
.zz:    ; (0.31) DOS 5 o mÇs amb els UMB sense enllaáar: la cadena de baix
        ; acaba en 'Z', perï continua a la memïria superior (el bloc de
        ; sistema 'SC' just a sota de la memïria de v°deo)
        cmp     byte [dosmaj],5
        jb      .done
        cmp     byte [zcont],0
        jne     .done
        cmp     ax,[convtop]
        jae     .done
        mov     es,ax
        cmp     byte [es:0],'M'
        je      .zc
        cmp     byte [es:0],'Z'
        jne     .done
.zc:    mov     byte [zcont],1
        jmp     .w
.done:  mov     [dosend],ax
        mov     bl,[nreg]
        or      bl,bl
        jz      .nr
        xor     bh,bh
        shl     bx,1
        mov     [reg_end+bx],ax
.nr:    call    hidos_k
        call    calc_utop
        call    scan_roms
        call    scan_chains
        call    scan_devices
        call    scan_vectors
        call    find_trans
        call    gem_scan
        call    calc_totals
        clc
        ret
.err:   stc
        ret

; (0.31) DOS 5 o mÇs: segment del codi del nucli. L'INT 20h va a les dades
; del DOS: "jmp short $+5 / call ... / jmp far cs:[ptr]" i a ptr hi ha
; l'adreáa del codi (a l'HMA amb DOS=HIGH, o en un bloc 'SC' amb HIDOS6)
find_code:
        push    ax
        push    bx
        push    cx
        push    es
        mov     word [codeseg],0
        cmp     byte [dosmaj],5
        jb      .r
        xor     ax,ax
        mov     es,ax
        les     bx,[es:20h*4]
        cmp     word [es:bx],03EBh
        jne     .r
        cmp     byte [es:bx+2],0E8h
        jne     .r
        cmp     word [es:bx+5],0FF2Eh
        jne     .r
        cmp     byte [es:bx+7],2Eh
        jne     .r
        mov     bx,[es:bx+8]
        mov     ax,[es:bx]              ; el parÖgraf on salta (el segment
        mov     cl,4                    ;   pot comenáar molt mÇs avall)
        shr     ax,cl
        add     ax,[es:bx+2]
        mov     [codeseg],ax
.r:     pop     es
        pop     cx
        pop     bx
        pop     ax
        ret

; ES = MCB: CF=0 si el codi del DOS (codeseg) Çs dins aquest bloc
is_code:
        push    ax
        push    bx
        mov     ax,[codeseg]
        or      ax,ax
        jz      .no
        mov     bx,es
        cmp     ax,bx
        jbe     .no
        add     bx,[es:3]
        jc      .no
        cmp     ax,bx
        ja      .no
        clc
        jmp     short .r
.no:    stc
.r:     pop     bx
        pop     ax
        ret

; =====================================================================
;  GEM: els blocs de dades de GEM.EXE i GEMVDI.EXE porten a dins els
;  accessoris (.ACC), els controladors (.SYS) i els recursos (.RSC) que
;  el GEM carrega pel seu compte. Per a cada fitxer d'aquests de la
;  carpeta del programa (\GEMBOOT, \GEMSYS) es busquen 16 bytes de la
;  seva imatge (fora de les reubicacions) dins els blocs; si hi s¢n, el
;  bloc pren el nom del fitxer.
; =====================================================================
gem_scan:
        mov     word [ngp],0
        mov     word [nlab],0
        xor     bx,bx
.l:     cmp     bx,[nblk]
        jae     .dirs
        push    bx
        shl     bx,1
        mov     ax,[blk_own+bx]
        mov     dx,[blk_seg+bx]
        pop     bx
        inc     dx
        cmp     ax,dx                   ; bloc de programa?
        jne     .n
        cmp     ax,[mypsp]
        je      .n
        call    name_of_owner
        mov     si,nbuf
        mov     di,s_gem
        call    strcmp
        je      .gp
        mov     di,s_gemvdi
        call    strcmp
        jne     .n
.gp:    cmp     word [ngp],2
        jae     .n
        mov     di,[ngp]
        shl     di,1
        mov     [gp_psp+di],ax
        mov     di,[ngp]                ; carpeta: gdir + ngp*80
        push    ax
        mov     ax,80
        mul     di
        mov     di,ax
        pop     ax
        add     di,gdir
        call    gem_dir                 ; CF=1: sense carpeta a l'entorn
        jnc     .gd
        call    gem_def                 ;   (GEM.EXE): la de per defecte
.gd:    call    gd_prog                 ; /G: programa i carpeta
        inc     word [ngp]              ; els seus blocs es miren igual
.n:     inc     bx
        jmp     .l
.dirs:  xor     bx,bx
.d:     cmp     bx,[ngp]
        jae     .x
        mov     ax,80
        mul     bx
        add     ax,gdir
        mov     [gdcur],ax
        mov     si,ax
        cmp     byte [si],0             ; sense carpeta: res a buscar
        je      .dn
        mov     si,s_pacc
        call    gem_pat
        mov     si,s_psys
        call    gem_pat
        mov     si,s_prsc
        call    gem_pat
.dn:    inc     bx
        jmp     .d
.x:     call    gem_hi                  ; GEMHI copiat a dalt
        ret

; GEMHI (0.3 o posterior) es copia sencer (PSP inclïs) a un bloc de dalt
; que passa a ser de GEMVDI: un bloc de dades d'un programa del GEM que
; comenáa amb un PSP (CD 20) i porta el text 'GEMHI 0.'
gem_hi: xor     bx,bx
.l:     cmp     bx,[nblk]
        jae     .x
        call    gcand
        jc      .n
        push    bx
        shl     bx,1
        mov     ax,[blk_seg+bx]
        mov     cx,[blk_size+bx]
        pop     bx
        inc     ax
        mov     es,ax
        cmp     word [es:0],20CDh
        jne     .n
        cmp     cx,0FFh                 ; fins a 4 KB
        jb      .c
        mov     cx,0FFh
.c:     push    cx
        mov     cl,4
        pop     ax
        shl     ax,cl
        sub     ax,8
        jbe     .n
        mov     cx,ax
        xor     di,di
.s:     mov     al,'G'
        repne   scasb
        jne     .n
        push    cx
        push    di
        mov     si,s_gemhi+1
        mov     cx,7
        repe    cmpsb
        pop     di
        pop     cx
        je      .hit
        jcxz    .n
        jmp     .s
.hit:   push    bx                      ; nom i tipus (programa)
        mov     ax,[nlab]
        inc     ax
        mov     [blk_lab+bx],al
        dec     ax
        mov     si,ax
        mov     byte [lab_kind+si],4
        mov     cx,9
        mul     cx
        add     ax,lab_name
        mov     di,ax
        push    ds
        pop     es
        mov     si,s_gemhi
        mov     cx,5
        rep     movsb
        mov     byte [di],0
        inc     word [nlab]
        pop     bx
        call    gd_hi
        ret
.n:     inc     bx
        jmp     .l
.x:     ret

; AX = PSP -> DS:DI = carpeta del programa (amb '\' al final). CF=1 si no
gem_dir:
        push    ax
        push    bx
        push    cx
        push    si
        push    di
        push    es
        mov     es,ax
        mov     ax,[es:2Ch]
        or      ax,ax
        jz      .no
        mov     es,ax
        xor     si,si
        mov     cx,2000
.z:     cmp     word [es:si],0          ; final de les variables
        je      .z1
        inc     si
        loop    .z
        jmp     .no
.z1:    add     si,4                    ; 00 00, comptador
        xor     bx,bx                   ; darrer '\' copiat
        mov     cx,78
.c:     mov     al,[es:si]
        mov     [di],al
        or      al,al
        jz      .c2
        inc     di
        inc     si
        cmp     al,'\'
        jne     .c1
        mov     bx,di
.c1:    loop    .c
.c2:    or      bx,bx
        jz      .no
        mov     byte [bx],0             ; talla desprÇs del darrer '\'
        pop     es
        pop     di
        push    di
        push    es
        call    gabs
        clc
        jmp     short .r
.no:    stc
.r:     pop     es
        pop     di
        pop     si
        pop     cx
        pop     bx
        pop     ax
        ret

; DS:DI: carpeta per defecte quan l'entorn nomÇs diu GEM.EXE o
; GEMVDI.EXE (s'engeguen des de la seva carpeta): GEMBOOT o GEMSYS
; a la unitat de GEMVDI, o a la unitat actual si encara no s'ha vist.
gem_def:
        push    ax
        push    dx
        push    si
        push    di
        mov     byte [di],0
        mov     si,nbuf
        push    di
        mov     di,s_gem
        call    strcmp
        pop     di
        mov     dx,s_gemboot            ; GEM.EXE: GEMBOOT
        je      .ok
        push    di
        mov     di,s_gemvdi
        call    strcmp
        pop     di
        jne     .x
        mov     dx,s_gemsys             ; GEMVDI: GEMSYS
.ok:
        mov     al,0                    ; unitat de GEMVDI, si ja hi Çs
        cmp     word [ngp],0
        je      .cur
        mov     si,gdir
        cmp     byte [si+1],':'
        jne     .cur
        mov     al,[si]
        jmp     short .u
.cur:   mov     ah,19h
        int     21h
        add     al,'A'
.u:     mov     [di],al
        inc     di
        mov     si,dx
        call    strcpy
.x:     pop     di
        pop     si
        pop     dx
        pop     ax
        ret

; DS:DI = carpeta sense unitat (GEMBOOT\ o \GEMBOOT\) -> cam° complet
; amb la unitat i el directori actuals (com quan es va engegar el GEM)
gabs:   cmp     byte [di+1],':'
        je      .x
        push    ds
        pop     es
        push    di
        mov     si,di                   ; cïpia a fpath
        mov     di,fpath
        call    strcpy
        pop     di
        push    di
        mov     ah,19h                  ; unitat actual
        int     21h
        add     al,'A'
        mov     ah,':'
        mov     [di],ax
        add     di,2
        cmp     byte [fpath],'\'
        je      .cp
        mov     byte [di],'\'
        inc     di
        mov     si,di
        mov     dl,0
        mov     ah,47h                  ; directori actual (sense '\')
        int     21h
        call    strend
        cmp     byte [di-1],'\'
        je      .cp
        mov     byte [di],'\'
        inc     di
.cp:    mov     si,fpath
        call    strcpy
        pop     di
.x:     ret

; [gdcur] = carpeta, SI = '*.EXT' -> tracta cada fitxer
gem_pat:
        push    bx
        mov     di,fpath
        push    si
        mov     si,[gdcur]
        call    strcpy
        call    strend
        pop     si
        call    strcpy
        mov     dx,gdta
        mov     ah,1Ah
        int     21h
        mov     dx,fpath
        xor     cx,cx
        mov     ah,4Eh
.f:     int     21h
        jc      .e
        call    gem_file
        mov     ah,4Fh
        jmp     .f
.e:     pop     bx
        ret

; DI -> el 0 final de la cadena DS:DI
strend: cmp     byte [di],0
        je      .e
        inc     di
        jmp     strend
.e:     ret

; un fitxer trobat (gdta): signatura i cerca als blocs del GEM
gem_file:
        cmp     word [nlab],MAXLAB
        jb      .ok
        ret
.ok:    mov     di,fpath                ; cam° complet
        mov     si,[gdcur]
        call    strcpy
        call    strend
        mov     si,gdta+1Eh
        call    strcpy
        mov     dx,fpath
        mov     ax,3D00h
        int     21h
        jc      .r
        mov     [gfh],ax
        mov     word [gmask],0
        mov     word [gmask+2],0
        mov     word [gimg],0
        mov     byte [graw],1
        mov     byte [gtries],0
        mov     word [ghit],0FFFFh
        mov     cx,32
        mov     dx,fhdr
        call    gread
        jc      .cl
        cmp     word [fhdr],'MZ'
        jne     .sig
        mov     byte [graw],0
        mov     ax,[fhdr+8]             ; capáalera en parÖgrafs
        mov     cl,4
        shl     ax,cl
        mov     [gimg],ax
        mov     cx,[fhdr+6]             ; reubicacions (les 64 primeres)
        jcxz    .sig
        cmp     cx,64
        jbe     .rc
        mov     cx,64
.rc:    push    cx
        mov     dx,[fhdr+18h]
        call    gseek
        pop     cx
        push    cx
        shl     cx,1
        shl     cx,1
        mov     dx,frel
        call    gread
        pop     cx
        jc      .cl
        mov     si,frel
.rl:    mov     ax,[si+2]               ; segment: dins els 512 primers?
        cmp     ax,32
        jae     .rn
        push    cx
        mov     cl,4
        shl     ax,cl
        add     ax,[si]
        cmp     ax,512
        jae     .rn0
        mov     dx,ax
        mov     cl,4
        shr     ax,cl                   ; finestra de 16 bytes
        call    gmark
        and     dl,15                   ; i la segÅent si hi entra
        cmp     dl,15
        jne     .rn0
        inc     ax
        call    gmark
.rn0:   pop     cx
.rn:    add     si,4
        loop    .rl
.sig:   xor     bx,bx                   ; primera finestra bona
.w:     cmp     bx,32
        jae     .cl
        mov     ax,bx
        call    gtest
        jnz     .wn
        mov     dx,bx
        mov     cl,4
        shl     dx,cl
        mov     [gsoff],dx
        add     dx,[gimg]
        push    bx
        call    gseek
        mov     cx,16
        mov     dx,gsig
        call    gread
        pop     bx
        jc      .cl
        mov     si,gsig                 ; tots iguals? no serveix
        mov     al,[si]
        mov     cx,15
.u:     inc     si
        cmp     al,[si]
        jne     .good
        loop    .u
.wn:    inc     bx
        jmp     .w
.good:  push    bx
        call    gfind                   ; CF=1: no hi Çs
        pop     bx
        jnc     .cl
        inc     byte [gtries]           ; prova fins a 3 finestres
        cmp     byte [gtries],3
        jb      .wn
.cl:    call    gd_file                 ; /G: resultat
        mov     bx,[gfh]
        mov     ah,3Eh
        int     21h
.r:     ret

gread:  mov     bx,[gfh]                ; CX bytes a DS:DX; CF si curt
        mov     ah,3Fh
        int     21h
        jc      .e
        cmp     ax,cx
        jb      .e
        clc
        ret
.e:     stc
        ret

gseek:  push    cx                      ; a DX (desplaáament < 64 KB)
        mov     bx,[gfh]
        xor     cx,cx
        mov     ax,4200h
        int     21h
        pop     cx
        ret

gmark:  push    ax                      ; AX = finestra (0-31)
        push    bx
        push    cx
        mov     cx,ax
        cmp     ax,16
        jb      .lo
        sub     cl,16
        mov     bx,1
        shl     bx,cl
        or      [gmask+2],bx
        jmp     short .e
.lo:    mov     bx,1
        shl     bx,cl
        or      [gmask],bx
.e:     pop     cx
        pop     bx
        pop     ax
        ret

gtest:  push    bx                      ; AX = finestra -> ZF=1 si lliure
        push    cx
        mov     cx,ax
        cmp     ax,16
        jb      .lo
        sub     cl,16
        mov     bx,1
        shl     bx,cl
        test    [gmask+2],bx
        jmp     short .e
.lo:    mov     bx,1
        shl     bx,cl
        test    [gmask],bx
.e:     pop     cx
        pop     bx
        ret

; busca gsig als blocs de dades del GEM; si la troba, hi posa el nom
gfind:  xor     bx,bx
.l:     cmp     bx,[nblk]
        jb      .t
        cmp     byte [graw],0           ; .RSC i altres sense capáalera:
        je      .x                      ;   si no, per la mida exacta
        call    gfsize
        ret
.x:     stc
        ret
.t:     call    gcand
        jc      .n
        push    bx
        shl     bx,1
        mov     ax,[blk_seg+bx]
        mov     cx,[blk_size+bx]
        pop     bx
        inc     ax
        mov     es,ax
        cmp     cx,0FFFh                ; bytes del bloc (mÖx. 64 KB)
        jb      .c1
        mov     cx,0FFFh
.c1:    mov     ax,cx
        mov     cl,4
        shl     ax,cl
        sub     ax,16
        jbe     .n
        mov     dx,ax                   ; £ltima posici¢ possible
        xor     di,di                   ; tot el bloc
        mov     cx,dx
.s:     mov     al,[gsig]
.sc:    repne   scasb
        jne     .n
        push    cx
        push    di
        mov     si,gsig+1
        mov     cx,15
        repe    cmpsb
        pop     di
        pop     cx
        je      .hit
        jcxz    .n
        jmp     .sc
.hit:   call    gname
        clc
        ret
.n:     inc     bx
        jmp     .l

; BX = bloc -> CF=0 si Çs un bloc de dades d'un programa del GEM sense nom
gcand:  push    ax
        push    di
        push    es
        cmp     byte [blk_lab+bx],0
        jne     .no
        push    bx
        shl     bx,1
        mov     ax,[blk_own+bx]
        mov     di,[blk_seg+bx]
        pop     bx
        inc     di
        cmp     ax,di                   ; el programa mateix: no
        je      .no
        cmp     word [ngp],0
        je      .no
        cmp     ax,[gp_psp]
        je      .g
        cmp     word [ngp],2
        jb      .no
        cmp     ax,[gp_psp+2]
        jne     .no
.g:     mov     es,ax                   ; el seu entorn: no
        cmp     [es:2Ch],di
        je      .no
        clc
        jmp     short .r
.no:    stc
.r:     pop     es
        pop     di
        pop     ax
        ret

; fitxer sense capáalera MZ que no s'ha trobat: un bloc amb la mida justa
gfsize: cmp     word [gdta+1Ch],0
        jne     .x
        mov     ax,[gdta+1Ah]
        add     ax,15
        jc      .x
        mov     cl,4
        shr     ax,cl
        xor     bx,bx
.l:     cmp     bx,[nblk]
        jae     .x
        call    gcand
        jc      .n
        push    bx
        shl     bx,1
        cmp     ax,[blk_size+bx]
        pop     bx
        jne     .n
        call    gname
        clc
        ret
.n:     inc     bx
        jmp     .l
.x:     stc
        ret

; BX = bloc: hi posa el nom del fitxer (gdta) i el tipus segons l'extensi¢
gname:  mov     [ghit],bx
        push    ax
        push    bx
        push    cx
        push    si
        push    di
        push    es
        push    ds
        pop     es
        mov     ax,[nlab]
        inc     ax
        mov     [blk_lab+bx],al
        dec     ax
        mov     cx,9
        mul     cx
        add     ax,lab_name
        mov     di,ax
        mov     si,gdta+1Eh
        xor     bl,bl                   ; tipus: 0 = altres
        mov     cx,8
.c:     lodsb
        cmp     al,'.'
        je      .p
        or      al,al
        jz      .z
        stosb
        loop    .c
.sk:    lodsb                           ; (nom de 8: busca el punt)
        or      al,al
        jz      .z
        cmp     al,'.'
        jne     .sk
.p:     mov     bl,1                    ; tipus per l'extensi¢
        cmp     word [si],'AC'
        je      .z
        mov     bl,2
        cmp     word [si],'SY'
        je      .z
        mov     bl,3                    ; .RSC: el mateix nom (a /C va
        cmp     word [si],'RS'          ;   amb el seu programa:
        je      .z                      ;   SNAPSHOT, GEM)
.z0:    xor     bl,bl
.z:     mov     byte [di],0
        mov     si,[nlab]
        mov     [lab_kind+si],bl
        inc     word [nlab]
        pop     es
        pop     di
        pop     si
        pop     cx
        pop     bx
        pop     ax
        ret

; ---- /G: el que fa la cerca del GEM, per veure per quä no troba res
gd_prog:                                ; AX = PSP, DI = carpeta
        test    byte [flags],F_G
        jz      .x
        call    lreset
        mov     si,s_gd_prog
        call    lputs
        mov     si,nbuf
        call    lputs
        mov     si,s_gd_psp
        call    lputs
        call    lhex4
        mov     si,s_gd_dir
        call    lputs
        mov     si,s_gd_nodir
        cmp     byte [di],0
        je      .p
        mov     si,di
.p:     call    lputs
        call    lflush
.x:     ret

gd_file:
        test    byte [flags],F_G
        jz      .x
        push    ax
        push    bx
        push    si
        call    lreset
        mov     si,s_gd_sp
        call    lputs
        mov     si,fpath
        call    lputs
        mov     si,s_gd_win
        call    lputs
        mov     ax,[gsoff]
        call    lhex4
        mov     si,s_gd_res
        call    lputs
        mov     bx,[ghit]
        cmp     bx,0FFFFh
        jne     .f
        mov     si,s_gd_no
        call    lputs
        jmp     short .e
.f:     shl     bx,1
        mov     ax,[blk_seg+bx]
        call    lhex4
.e:     call    lflush
        pop     si
        pop     bx
        pop     ax
.x:     ret

gd_hi:  test    byte [flags],F_G        ; /G: on Çs GEMHI
        jz      .x
        push    ax
        push    bx
        push    si
        call    lreset
        mov     si,s_gd_hi
        call    lputs
        shl     bx,1
        mov     ax,[blk_seg+bx]
        call    lhex4
        call    lflush
        pop     si
        pop     bx
        pop     ax
.x:     ret

; --- HIDOS: el nucli del DOS Çs per sobre de la memïria convencional,
; dins el bloc de sistema que tapa el v°deo i les ROM (B7FF). kseg i
; kend: des del segment del DOS fins al final d'aquest bloc.
hidos_k:
        push    ax
        push    bx
        push    cx
        push    dx
        push    es
        mov     word [kseg],0
        mov     word [kend],0
        mov     word [iohi],0
        mov     dx,[dosseg]
        cmp     dx,[convtop]
        jb      .r
        mov     ax,[firstmcb]
        mov     cx,4000
.l:     mov     es,ax
        cmp     dx,ax
        jbe     .r
        add     ax,[es:3]
        jc      .r
        inc     ax
        cmp     dx,ax
        jb      .f
        cmp     byte [es:0],'Z'
        jne     .lz
        cmp     byte [dosmaj],5         ; (0.31) DOS 5+: la cadena segueix
        jb      .r                      ;   a la memïria superior
        cmp     ax,[convtop]
        jae     .r
.lz:    loop    .l
        jmp     .r
.f:     mov     [kseg],dx
        mov     [kend],ax
        mov     [d6mid],ax
        cmp     byte [dosmaj],5         ; (0.31) HIDOS6 /D: marca 'HIDOS6DD'
        jb      .f3                     ;   just abans de les dades del DOS
        push    ax
        mov     ax,dx
        dec     ax
        mov     es,ax
        cmp     word [es:0],'HI'
        jne     .f2
        cmp     word [es:6],'DD'
        jne     .f2
        mov     [kseg],ax
        add     ax,[es:8]
        cmp     ax,[kend]
        ja      .f2
        mov     [d6mid],ax
.f2:    pop     ax
        jmp     .r                      ; (el DOS 6 no tÇ DEVICELOW ni /B)
.f3:
        mov     word [iohi],0           ; i el BIOS (HIDOS /B)? Çs el
        mov     ax,[firstmcb]           ;   segment de l'£ltim controlador
        mov     [lowdrv],ax             ;   de la cadena; i de passada,
        mov     es,dx                   ;   el primer DEVICELOW (el mÇs
        mov     bx,[nulofs]             ;   baix entre 0070 i el 1r bloc)
        mov     cx,100
.c:     mov     ax,es
        cmp     ax,70h
        jbe     .c1
        cmp     ax,[lowdrv]
        jae     .c1
        mov     [lowdrv],ax
.c1:    les     bx,[es:bx]
        cmp     bx,0FFFFh
        je      .c2
        loop    .c
        jmp     short .r
.c2:    mov     ax,es                   ; ES = segment de l'£ltim (BIOS)
        cmp     ax,[convtop]
        jb      .r
        cmp     ax,dx
        jae     .r
        mov     [iohi],ax
        mov     [kseg],ax               ; la zona del DOS comenáa al BIOS
        mov     word [lowdrv],70h       ; i els DEVICELOW, des de 0070
.r:     pop     es
        pop     dx
        pop     cx
        pop     bx
        pop     ax
        ret

; --- COMMAND.COM a la memïria superior (LOADHI /C): la seva part
;     transitïria va just a sobre del resident, fins al final de la
;     zona, en un bloc que DOS tÇ per lliure. Si el bloc de programa de
;     COMMAND tÇ a sobre un bloc lliure que Çs l'£ltim de la regi¢, aquest
;     bloc passa a ser de COMMAND (tipus "Parte transitoria") i no es
;     compta com a lliure.
find_trans:
        push    ax
        push    bx
        push    cx
        push    dx
        push    si
        push    di
        push    es
        mov     word [trans_ix],0
        xor     bx,bx
.l:     mov     ax,bx
        inc     ax
        cmp     ax,[nblk]
        jae     .e
        mov     al,[blk_reg+bx]
        or      al,al
        jz      .n
        cmp     al,[blk_reg+bx+1]       ; el segÅent, a la mateixa regi¢
        jne     .n
        mov     si,bx
        shl     si,1
        mov     ax,[blk_own+si]
        mov     cx,[blk_seg+si]
        inc     cx
        cmp     ax,cx                   ; bloc de programa
        jne     .n
        cmp     word [blk_own+si+2],0   ; i el segÅent, lliure
        jne     .n
        call    name_of_owner
        push    si
        mov     si,nbuf
        mov     di,s_command
        call    strcmp
        pop     si
        jne     .n
        mov     ax,[blk_own+si]         ; (0.29) la transitoria va a PSP:2
        push    es                      ;   menys la seva mida: nomes es
        mov     es,ax                   ;   aqui si PSP:2 cau dins el bloc
        mov     dx,[es:2]               ;   lliure (un COMMAND engegat a
        pop     es                      ;   dalt pel GEMHI 0.24 la te a la
        mov     cx,[blk_seg+si+2]       ;   convencional)
        inc     cx
        cmp     dx,cx
        jbe     .n
        add     cx,[blk_size+si+2]
        cmp     dx,cx
        ja      .n
        mov     cx,bx                   ; el lliure ha de ser l'£ltim bloc
        add     cx,2                    ; de la regi¢
        cmp     cx,[nblk]
        jae     .t
        push    bx
        mov     bx,cx
        mov     cl,[blk_reg+bx]
        pop     bx
        cmp     cl,[blk_reg+bx]
        je      .n
.t:     mov     [blk_own+si+2],ax
        mov     ax,bx
        add     ax,2                    ; °ndex del bloc + 1
        mov     [trans_ix],ax
        jmp     short .e
.n:     inc     bx
        jmp     .l
.e:     pop     es
        pop     di
        pop     si
        pop     dx
        pop     cx
        pop     bx
        pop     ax
        ret

; --- final de la memïria superior: F000, o mÇs amunt si a F000 hi ha RAM
;     (p. ex. una targeta de memïria fins a FBFFF), de 1 KB en 1 KB
calc_utop:
        push    ax
        push    di
        push    es
        mov     ax,0F000h
.l:     cmp     ax,0FE00h
        jae     .e
        mov     es,ax
        xor     di,di
        call    ramprobe
        jc      .e
        mov     di,3FFh
        call    ramprobe
        jc      .e
        add     ax,40h
        jmp     .l
.e:     mov     [utop],ax
        pop     es
        pop     di
        pop     ax
        ret

; --- ROM d'adaptador (55AAh) entre C000 i EFFF, cada 2 KB. Si a BC00
;     hi ha una ROM (v°deo de 16 KB sense mirall, p. ex. la DTC 5150X a
;     BC00H), la memïria de v°deo acaba a BC00 i es busca des d'allÖ.
scan_roms:
        mov     word [nrom],0
        mov     word [vidend],0C000h
        mov     ax,0C000h
        call    low_rom
        jc      .l
        mov     ax,0BC00h
        mov     [vidend],ax
.l:     cmp     ax,[utop]
        jae     .e
        mov     es,ax
        cmp     word [es:0],0AA55h
        jne     .n
        mov     dl,[es:2]
        xor     dh,dh
        or      dx,dx
        jz      .n
        mov     cl,5
        shl     dx,cl
        ; finestra de 16 KB: els registres de la targeta (p. ex. SCSI)
        ; poden ser just desprÇs de la ROM; no s'han de llegir.
        ; Per sota de C000 (ROM al lloc del mirall del v°deo) no hi ha
        ; finestra: nomÇs la ROM, en trossos de 2 KB
        cmp     ax,0C000h
        jae     .w16
        add     dx,7Fh
        and     dx,0FF80h
        jmp     short .w
.w16:   add     dx,3FFh
        and     dx,0FC00h
.w:
        mov     bx,[nrom]
        cmp     bx,MAXROM
        jae     .e
        shl     bx,1
        mov     [rom_seg+bx],ax
        mov     [rom_len+bx],dx
        inc     word [nrom]
        add     ax,dx
        jc      .e
        add     ax,7Fh
        jc      .e
        and     ax,0FF80h
        jmp     .l
.n:     add     ax,80h
        jmp     .l
.e:     ret

; CF=0 si a BC00 hi ha una ROM d'adaptador de debï: 55AAh, que no sigui
; el mirall de B800 (els primers 16 bytes iguals) i suma de control 0
low_rom:
        push    ax
        push    cx
        push    si
        push    di
        push    ds
        push    es
        mov     ax,0BC00h
        mov     es,ax
        cmp     word [es:0],0AA55h
        jne     .no
        mov     cl,[es:2]
        xor     ch,ch
        jcxz    .no
        cmp     cx,10h                  ; com a molt 8 KB (fins a BE00)
        ja      .no
        mov     ax,0B800h
        mov     ds,ax
        xor     si,si
        xor     di,di
        push    cx
        mov     cx,8
        repe    cmpsw
        pop     cx
        je      .no                     ; Çs el mirall del v°deo
        push    cs
        pop     ds
        mov     ch,cl                   ; CX = blocs de 512 bytes * 256
        xor     cl,cl
        shl     cx,1                    ; bytes
        xor     si,si
        xor     ah,ah
.s:     add     ah,[es:si]
        inc     si
        loop    .s
        or      ah,ah
        jnz     .no
        clc
        jmp     short .x
.no:    stc
.x:     pop     es
        pop     ds
        pop     di
        pop     si
        pop     cx
        pop     ax
        ret

; AX = parÖgraf. CF=1 si Çs dins una ROM (BX = final)
in_rom: push    cx
        push    si
        mov     cx,[nrom]
        xor     si,si
.l:     jcxz    .no
        mov     bx,[rom_seg+si]
        cmp     ax,bx
        jb      .nx
        add     bx,[rom_len+si]
        cmp     ax,bx
        jb      .yes
.nx:    add     si,2
        dec     cx
        jmp     .l
.no:    pop     si
        pop     cx
        clc
        ret
.yes:   pop     si
        pop     cx
        stc
        ret

; AX = parÖgraf. CF=1 si Çs dins una regi¢ de blocs superior (BX = final,
; DL = n£mero de regi¢)
in_region:
        push    cx
        push    si
        mov     cl,[nreg]
        xor     ch,ch
        mov     si,2
        mov     dl,1
.l:     jcxz    .no
        mov     bx,[reg_start+si]
        cmp     ax,bx
        jb      .nx
        mov     bx,[reg_end+si]
        cmp     ax,bx
        jb      .yes
.nx:    add     si,2
        inc     dl
        dec     cx
        jmp     .l
.no:    pop     si
        pop     cx
        clc
        ret
.yes:   pop     si
        pop     cx
        stc
        ret

; --- cadenes de blocs (MCB) independents a C000-EFFF
scan_chains:
        mov     ax,0C000h
.l:     cmp     ax,[utop]
        jae     .e
        call    in_rom
        jnc     .a
        mov     ax,bx
        jmp     .l
.a:     call    in_region
        jnc     .b
        mov     ax,bx
        jmp     .l
.b:     test    al,3Fh
        jnz     .n
        call    try_chain
        jc      .n
        mov     ax,bx
        jmp     .l
.n:     add     ax,40h
        and     ax,0FFC0h
        jmp     .l
.e:     ret

; AX = possible inici de cadena. CF=0 si Çs vÖlida (BX = final)
try_chain:
        push    ax
        mov     si,ax
        xor     cx,cx
.v:     mov     es,si
        mov     dl,[es:0]
        cmp     dl,'M'
        je      .v1
        cmp     dl,'Z'
        jne     .fail
.v1:    mov     bx,[es:1]
        or      bx,bx
        jz      .vo
        cmp     bx,8
        je      .vo
        cmp     bx,40h
        jb      .fail
.vo:    mov     bx,[es:3]
        or      bx,bx
        jz      .fail
        add     bx,si
        jc      .fail
        inc     bx
        jz      .fail
        cmp     bx,[utop]
        ja      .fail
        inc     cx
        cmp     cx,64
        ja      .fail
        cmp     dl,'Z'
        je      .vend
        mov     si,bx
        jmp     .v
.vend:  test    bl,3Fh
        jnz     .fail
        mov     al,[nreg]
        cmp     al,MAXREG-1
        jae     .fail
        inc     al
        mov     [nreg],al
        xor     ah,ah
        mov     si,ax
        shl     si,1
        mov     dh,al
        pop     ax
        push    ax
        mov     [reg_start+si],ax
        mov     [reg_end+si],bx
        push    bx
.st:    mov     es,ax
        mov     bx,[nblk]
        cmp     bx,MAXBLK
        jae     .sd
        mov     [blk_reg+bx],dh
        shl     bx,1
        mov     [blk_seg+bx],ax
        mov     cx,[es:1]
        mov     [blk_own+bx],cx
        mov     cx,[es:3]
        mov     [blk_size+bx],cx
        inc     word [nblk]
        cmp     byte [es:0],'Z'
        je      .sd
        add     ax,cx
        inc     ax
        jmp     .st
.sd:    pop     bx
        pop     ax
        clc
        ret
.fail:  pop     ax
        stc
        ret

; --- cadena de controladors (des de NUL)
scan_devices:
        mov     word [ndev],0
        mov     es,[dosseg]
        mov     bx,[nulofs]
        ; comprova que hi ha "NUL     " (DOS 3.1 o posterior)
        cmp     word [es:bx+10],'NU'
        jne     .e
        cmp     word [es:bx+12],'L '
        jne     .e
.l:     mov     di,[ndev]
        cmp     di,MAXDEV
        jae     .e
        shl     di,1
        mov     [dev_seg+di],es
        mov     [dev_off+di],bx
        mov     ax,[es:bx+4]
        mov     [dev_attr+di],ax
        shl     di,1
        shl     di,1
        add     di,dev_name
        mov     cx,8
        xor     si,si
.c:     mov     al,[es:bx+si+10]
        mov     [di],al
        inc     di
        inc     si
        loop    .c
        inc     word [ndev]
        mov     ax,[es:bx]
        mov     dx,[es:bx+2]
        cmp     ax,0FFFFh
        je      .e
        mov     es,dx
        mov     bx,ax
        jmp     .l
.e:     call    assign_letters
        ; controladors a memïria superior fora de cap regi¢: grups
        xor     di,di
.g:     cmp     di,[ndev]
        jae     .ge
        push    di
        shl     di,1
        mov     ax,[dev_off+di]
        mov     cl,4
        shr     ax,cl
        mov     dx,[dev_seg+di]
        add     ax,dx
        jc      .gn
        call    upper_target
        jc      .gn
        call    find_grp
.gn:    pop     di
        inc     di
        jmp     .g
.ge:    ret

; lletres d'unitat per als controladors de bloc
assign_letters:
        mov     byte [nextdrv],'A'
        mov     word [biosseg],70h      ; el BIOS: l'£ltim de la cadena
        mov     bx,[ndev]               ;   (amb HIDOS /B no Çs a 0070h)
        or      bx,bx
        jz      .bs
        dec     bx
        shl     bx,1
        mov     ax,[dev_seg+bx]
        mov     [biosseg],ax
.bs:
        xor     di,di
.p1:    cmp     di,[ndev]
        jae     .p2s
        call    .isblk
        jnz     .p1n
        mov     bx,di
        shl     bx,1
        mov     ax,[biosseg]
        cmp     [dev_seg+bx],ax
        jne     .p1n
        call    .give
.p1n:   inc     di
        jmp     .p1
.p2s:   mov     di,[ndev]
.p2:    or      di,di
        jz      .e
        dec     di
        call    .isblk
        jnz     .p2
        mov     bx,di
        shl     bx,1
        mov     ax,[biosseg]
        cmp     [dev_seg+bx],ax
        je      .p2
        call    .give
        jmp     .p2
.e:     ret
.isblk: mov     bx,di
        shl     bx,1
        test    word [dev_attr+bx],8000h
        ret
.give:  mov     al,[nextdrv]
        mov     [dev_drv+di],al
        mov     bx,di
        shl     bx,1
        shl     bx,1
        shl     bx,1
        add     al,[dev_name+bx]
        mov     [nextdrv],al
        ret

; AX = parÖgraf. CF=0 si Çs a memïria superior i no Çs v°deo/ROM/regi¢
upper_target:
        cmp     ax,[convtop]
        jb      .no
        cmp     ax,[utop]
        jae     .no
        cmp     ax,[vidend]
        jae     .c
        cmp     ax,0A000h
        jae     .no
.c:     call    in_rom
        jc      .no
        cmp     word [kseg],0           ; el nucli del DOS (HIDOS) no
        je      .c1                     ;   Çs un resident sense bloc
        cmp     ax,[kseg]
        jb      .c1
        cmp     ax,[kend]
        jb      .no
.c1:    push    dx
        call    in_region
        pop     dx
        jc      .no
        clc
        ret
.no:    stc
        ret

; DX = segment, AX = parÖgraf: busca o crea el grup. BX = °ndex (CF=1 ple)
find_grp:
        push    cx
        xor     bx,bx
.l:     cmp     bx,[ngrp]
        jae     .new
        push    bx
        shl     bx,1
        cmp     [grp_seg+bx],dx
        jne     .nx
        cmp     ax,[grp_min+bx]
        jae     .same
        mov     [grp_min+bx],ax
.same:  pop     bx
        pop     cx
        clc
        ret
.nx:    pop     bx
        inc     bx
        jmp     .l
.new:   cmp     bx,MAXGRP
        jae     .full
        inc     word [ngrp]
        mov     byte [grp_nv+bx],0
        push    bx
        shl     bx,1
        mov     [grp_seg+bx],dx
        mov     [grp_min+bx],ax
        pop     bx
        pop     cx
        clc
        ret
.full:  pop     cx
        stc
        ret

; --- vectors d'interrupci¢ que apunten a memïria superior
scan_vectors:
        xor     di,di
.l:     xor     ax,ax
        mov     es,ax
        mov     ax,[es:di]
        mov     dx,[es:di+2]
        mov     cl,4
        shr     ax,cl
        add     ax,dx
        jc      .n
        call    upper_target
        jc      .n
        call    find_grp
        jc      .n
        mov     cl,[grp_nv+bx]
        cmp     cl,MAXGV
        jae     .over
        mov     al,cl
        xor     ah,ah
        push    bx
        mov     cl,4
        shl     bx,cl
        add     bx,ax
        mov     ax,di
        shr     ax,1
        shr     ax,1
        mov     [grp_vec+bx],al
        pop     bx
.over:  inc     byte [grp_nv+bx]
.n:     add     di,4
        cmp     di,400h
        jb      .l
        ; noms dels grups
        xor     bx,bx
.g:     cmp     bx,[ngrp]
        jae     .e
        push    bx
        shl     bx,1
        mov     ax,[grp_seg+bx]
        call    identify
        pop     bx
        call    grp_extent
        cmp     byte [nbuf],0
        jne     .hn
        push    bx
        shl     bx,1
        mov     ax,[grp_beg+bx]
        pop     bx
        call    sig_name
.hn:    push    bx
        mov     ax,9
        mul     bx
        mov     di,ax
        add     di,grp_name
        mov     si,nbuf
        call    strcpy
        pop     bx
        inc     bx
        jmp     .g
.e:     ret

; AX = parÖgraf. ZF=1 si els 16 bytes s¢n tots 00h o tots FFh
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

; AX = parÖgraf. CF=1 si no pot ser part d'un resident sense bloc
; (memïria convencional, v°deo, ROM, regi¢ de blocs, F000 o mÇs amunt)
lim_chk:
        push    bx
        push    dx
        cmp     ax,[convtop]
        jb      .no
        cmp     ax,[utop]
        jae     .no
        cmp     ax,[vidend]
        jae     .c
        cmp     ax,0A000h
        jae     .no
.c:     call    in_rom
        jc      .no
        call    in_region
        jc      .no
        clc
        jmp     short .x
.no:    stc
.x:     pop     dx
        pop     bx
        ret

; BX = grup. Calcula grp_beg i grp_end (parÖgrafs, final exclusiu) a
; partir dels gestors: cap enrere i cap endavant fins a 1 KB buit seguit
; (buit = tot 00h o tot FFh). Si a segment:0100h hi ha un salt (programa
; .COM copiat amunt, com KEYBX /H), l'inici Çs com a mÖxim allÖ.
grp_extent:
        push    ax
        push    cx
        push    dx
        push    si
        push    di
        mov     si,bx
        shl     si,1
        mov     dx,[grp_min+si]
.b:     mov     ax,dx
        mov     cx,64
.b1:    dec     ax
        call    lim_chk
        jc      .bd
        call    para_empty
        jnz     .bf
        loop    .b1
        jmp     short .bd
.bf:    mov     dx,ax
        jmp     .b
.bd:    mov     ax,[grp_seg+si]         ; segment:0100h
        add     ax,10h
        jc      .bs
        cmp     ax,dx
        jae     .bs
        cmp     ax,[grp_min+si]
        ja      .bs
        call    lim_chk
        jc      .bs
        push    es
        mov     es,ax
        mov     cl,[es:0]
        pop     es
        cmp     cl,0E9h
        je      .bc
        cmp     cl,0EBh
        jne     .bs
.bc:    mov     dx,ax
.bs:    mov     [grp_beg+si],dx
        mov     dx,[grp_min+si]
.f:     mov     ax,dx
        mov     cx,64
        xor     di,di
.f1:    inc     ax
        jz      .fd
        call    lim_chk
        jc      .fd
        call    para_empty
        jz      .f2
        mov     di,ax
.f2:    loop    .f1
.fd:    or      di,di
        jz      .fe
        mov     dx,di
        jmp     .f
.fe:    inc     dx
        mov     [grp_end+si],dx
        pop     di
        pop     si
        pop     dx
        pop     cx
        pop     ax
        ret

; AX = parÖgraf on comenáa el resident. Si comenáa amb un salt (E9h/EBh)
; seguit d'una signatura (p. ex. 'KEYBX1'), en treu el nom -> nbuf
sig_name:
        push    ax
        push    bx
        push    cx
        push    si
        push    di
        push    es
        mov     es,ax
        mov     byte [nbuf],0
        mov     si,3
        cmp     byte [es:0],0E9h
        je      .s
        mov     si,2
        cmp     byte [es:0],0EBh
        jne     .x
.s:     cmp     si,16
        jae     .x
        mov     al,[es:si]
        call    sig_let
        jnc     .c
        inc     si
        jmp     .s
.c:     mov     di,nbuf
        xor     cx,cx
.cl:    mov     al,[es:si]
        call    sig_let
        jnc     .ok
        cmp     al,'0'
        jb      .ce
        cmp     al,'9'
        ja      .ce
.ok:    mov     [di],al
        inc     di
        inc     si
        inc     cx
        cmp     cx,8
        jb      .cl
.ce:    mov     byte [di],0
.td:    cmp     cx,3                    ; treu les xifres del final
        jbe     .lc
        mov     al,[di-1]
        cmp     al,'0'
        jb      .lc
        cmp     al,'9'
        ja      .lc
        dec     di
        dec     cx
        mov     byte [di],0
        jmp     .td
.lc:    cmp     cx,3
        jae     .x
        mov     byte [nbuf],0
.x:     pop     es
        pop     di
        pop     si
        pop     cx
        pop     bx
        pop     ax
        ret
; AL lletra A-Z? CF=0 s°
sig_let:
        cmp     al,'A'
        jb      .no
        cmp     al,'Z'
        ja      .no
        clc
        ret
.no:    stc
        ret

; AX = segment del codi resident -> nbuf (pot quedar buit)
identify:
        push    es
        push    ax
        mov     byte [nbuf],0
        mov     es,ax
        cmp     word [es:0],20CDh
        jne     .m
        call    name_of_owner
        jmp     .x
.m:     dec     ax
        mov     es,ax
        cmp     byte [es:0],'M'
        je      .mm
        cmp     byte [es:0],'Z'
        jne     .dev
.mm:    mov     ax,[es:1]
        cmp     ax,40h
        jb      .dev
        call    name_of_owner
        jmp     .x
.dev:   ; Çs un controlador?
        pop     ax
        push    ax
        xor     bx,bx
.dl:    cmp     bx,[ndev]
        jae     .x
        push    bx
        shl     bx,1
        cmp     [dev_seg+bx],ax
        pop     bx
        je      .df
        inc     bx
        jmp     .dl
.df:    call    dev_label
        mov     si,dlab
        mov     di,nbuf
        call    strcpy
.x:     pop     ax
        pop     es
        ret

; BX = °ndex de controlador -> dlab ("CON", "A: - C:" ...)
dev_label:
        push    ax
        push    bx
        push    cx
        push    si
        push    di
        mov     di,dlab
        mov     si,bx
        shl     si,1
        test    word [dev_attr+si],8000h
        jz      .blk
        shl     si,1
        shl     si,1
        add     si,dev_name
        mov     cx,8
.c:     lodsb
        cmp     al,' '
        jbe     .ce
        mov     [di],al
        inc     di
        loop    .c
.ce:    mov     byte [di],0
        jmp     .x
.blk:   mov     al,[dev_drv+bx]
        or      al,al
        jz      .ce
        mov     [di],al
        mov     byte [di+1],':'
        add     di,2
        shl     si,1
        shl     si,1
        mov     ah,[dev_name+si]
        cmp     ah,1
        jbe     .ce
        dec     ah
        add     al,ah
        mov     byte [di],' '
        mov     byte [di+1],'-'
        mov     byte [di+2],' '
        mov     [di+3],al
        mov     byte [di+4],':'
        add     di,5
        jmp     .ce
.x:     pop     di
        pop     si
        pop     cx
        pop     bx
        pop     ax
        ret

; AX = propietari (PSP) -> nbuf
name_of_owner:
        push    ax
        push    bx
        push    cx
        push    dx
        push    si
        push    di
        push    es
        mov     [tmpown],ax
        mov     word [nmprev],0
        mov     di,nbuf
        cmp     ax,8
        jne     .1
        mov     si,s_msdos
        jmp     .copy
.1:     cmp     ax,[mypsp]
        jne     .2
        mov     si,s_mem
        jmp     .copy
.2:     or      ax,ax
        jz      .hex
        mov     es,ax
        cmp     word [es:0],20CDh
        jne     .mcbname
        cmp     [es:16h],ax
        jne     .3
        mov     word [nmprev],2         ; nom a la capáalera (LOADHI com
        jmp     .mcbname                ; a SHELL=) o, si no, COMMAND
.3:     mov     bx,[es:2Ch]
        or      bx,bx
        jnz     .3e
        ; sense entorn (l'ha alliberat i ha posat PSP:2Ch a 0): primer el
        ; nom de la capáalera del bloc (el posa LOADHI); si no n'hi ha, el
        ; bloc lliure just abans del programa sol ser l'entorn d'abans
        mov     word [nmprev],1
        jmp     .mcbname
.prev:  mov     word [nmprev],0
        mov     ax,[tmpown]
        mov     dx,ax
        dec     dx
        xor     si,si
        xor     cx,cx
.pv:    cmp     cx,[nblk]
        jae     .mcbname
        mov     bx,[blk_seg+si]
        add     bx,[blk_size+si]
        inc     bx
        cmp     bx,dx
        jne     .pvn
        cmp     word [blk_own+si],0
        jne     .mcbname
        mov     bx,[blk_seg+si]
        mov     es,bx
        inc     bx
        jmp     .e00
.pvn:   inc     si
        inc     si
        inc     cx
        jmp     .pv
.3e:    mov     dx,bx
        dec     dx
        mov     es,dx
        mov     dl,[es:0]
        cmp     dl,'M'
        je      .e0
        cmp     dl,'Z'
        jne     .mcbname
.e0:    mov     dx,[es:1]
        or      dx,dx
        jz      .e00
        cmp     dx,ax
        jne     .mcbname
.e00:   mov     cx,[es:3]
        cmp     cx,800h
        jbe     .e01
        mov     cx,800h
.e01:   push    cx                      ; CX = bytes del bloc (tot: el nom
        mov     cl,4                    ;   pot arribar fins al final si
        pop     dx                      ;   l'entorn Çs ple)
        shl     dx,cl
        mov     cx,dx
        cmp     cx,4
        jbe     .mcbname
        mov     es,bx
        xor     si,si
.e1:    mov     dx,si
        inc     dx
        cmp     dx,cx
        jae     .mcbname
        cmp     byte [es:si],0
        jne     .e2
        cmp     byte [es:si+1],0
        je      .e3
.e2:    inc     si
        jmp     .e1
.e3:    add     si,2
        mov     dx,si
        add     dx,2
        cmp     dx,cx
        ja      .mcbname
        cmp     word [es:si],1
        jb      .mcbname
        cmp     word [es:si],8
        ja      .mcbname
        add     si,2
        mov     bx,si
.e4:    cmp     si,cx
        jae     .mcbname
        mov     al,[es:si]
        or      al,al
        jz      .e5
        cmp     al,'\'
        je      .sep
        cmp     al,':'
        je      .sep
        cmp     al,'/'
        je      .sep
        inc     si
        jmp     .e4
.sep:   inc     si
        mov     bx,si
        jmp     .e4
.e5:    mov     si,bx
        mov     cx,8
        xor     dl,dl
.e6:    mov     al,[es:si]
        or      al,al
        jz      .e7
        cmp     al,'.'
        je      .e7d
        call    upcase
        cmp     al,' '
        jbe     .mcbname
        mov     [di],al
        inc     di
        inc     si
        loop    .e6
.e6b:   mov     al,[es:si]          ; nom de mÇs de 8: buscar el punt
        or      al,al
        jz      .e7
        cmp     al,'.'
        je      .e7d
        inc     si
        jmp     .e6b
.e7d:   inc     dl
.e7:    or      dl,dl
        jz      .mcbname
        cmp     di,nbuf
        je      .mcbname
        mov     byte [di],0
        jmp     .ret
.mcbname:
        mov     di,nbuf
        mov     ax,[tmpown]
        dec     ax
        mov     es,ax
        mov     si,8
        mov     cx,8
.m1:    mov     al,[es:si]
        or      al,al
        jz      .m2
        cmp     al,' '
        je      .m2
        cmp     al,'0'
        jb      .m1x
        cmp     al,'9'
        jbe     .m1ok
        cmp     al,'A'
        jb      .m1x
        cmp     al,'Z'
        jbe     .m1ok
.m1x:   cmp     al,'_'
        je      .m1ok
        cmp     al,'$'
        je      .m1ok
        cmp     al,'-'
        jne     .hex
.m1ok:  mov     [di],al
        inc     di
        inc     si
        loop    .m1
.m2:    mov     ax,di
        sub     ax,nbuf
        cmp     ax,2
        jb      .hex
        ; la resta del camp ha de ser 0 o espais
.m3:    jcxz    .m4
        mov     al,[es:si]
        or      al,al
        jz      .m3n
        cmp     al,' '
        jne     .hex
.m3n:   inc     si
        dec     cx
        jmp     .m3
.m4:    mov     byte [di],0
        jmp     .ret
.hex:   cmp     word [nmprev],2
        jne     .hx0
        mov     word [nmprev],0
        mov     di,nbuf
        mov     si,s_command
        jmp     .copy
.hx0:   cmp     word [nmprev],0
        je      .hx
        jmp     .prev
.hx:    mov     di,nbuf
        mov     byte [di],'?'
        inc     di
        mov     ax,[tmpown]
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
        mov     byte [di],0
        jmp     .ret
.copy:  call    strcpy
.ret:   pop     es
        pop     di
        pop     si
        pop     dx
        pop     cx
        pop     bx
        pop     ax
        ret

; --- totals
calc_totals:
        xor     ax,ax
        mov     [cfree],ax
        mov     [ufree],ax
        mov     [utot],ax
        mov     [bigc],ax
        mov     [bigu],ax
        mov     [run],ax
        mov     byte [runreg],0FFh
        xor     bx,bx
.l:     cmp     bx,[nblk]
        jae     .e
        mov     dl,[blk_reg+bx]
        push    bx
        shl     bx,1
        mov     ax,[blk_size+bx]
        inc     ax
        mov     cx,[blk_own+bx]
        pop     bx
        or      dl,dl
        jnz     .up
        jcxz    .cf
        cmp     cx,[mypsp]
        jne     .nf
.cf:    add     [cfree],ax
        jmp     .fr
.up:    add     [utot],ax
        jcxz    .uf
        jmp     .nf
.uf:    add     [ufree],ax
.fr:    cmp     dl,[runreg]
        jne     .rs
        add     [run],ax
        jmp     .rc
.rs:    mov     [run],ax
        mov     [runreg],dl
        push    bx                      ; on comenáa aquest tros lliure
        shl     bx,1
        mov     ax,[blk_seg+bx]
        mov     [runs],ax
        pop     bx
.rc:    mov     ax,[run]
        dec     ax
        mov     cx,[runs]
        or      dl,dl
        jnz     .ru
        cmp     ax,[bigc]
        jbe     .nx
        mov     [bigc],ax
        mov     [bigcs],cx
        jmp     .nx
.ru:    cmp     ax,[bigu]
        jbe     .nx
        mov     [bigu],ax
        mov     [bigus],cx
        jmp     .nx
.nf:    mov     byte [runreg],0FFh
.nx:    inc     bx
        jmp     .l
.e:     mov     ax,[kend]               ; HIDOS: el nucli compta com a
        sub     ax,[kseg]               ;   memïria superior usada
        add     [utot],ax
        ret

check_ems:
        mov     byte [ems],0
        mov     ax,3567h
        int     21h
        mov     di,0Ah
        mov     si,s_emm
        mov     cx,8
        repe    cmpsb
        jne     .e
        mov     ah,42h
        int     67h
        or      ah,ah
        jnz     .e
        mov     [ems_free],bx
        mov     [ems_tot],dx
        mov     byte [ems],1
.e:     ret

; =====================================================================
;  Nom i tipus d'un bloc
; =====================================================================
; BX = °ndex de bloc -> nbuf (buit si Çs lliure)
blk_name:
        push    ax
        push    bx
        mov     al,[blk_lab+bx]         ; fitxer del GEM reconegut?
        or      al,al
        jz      .own
        push    si
        push    di
        dec     al
        mov     ah,9
        mul     ah
        add     ax,lab_name
        mov     si,ax
        mov     di,nbuf
        call    strcpy
        pop     di
        pop     si
        jmp     short .e
.own:   shl     bx,1
        mov     ax,[blk_own+bx]
        mov     byte [nbuf],0
        or      ax,ax
        jz      .e
        cmp     ax,8                    ; bloc de sistema amb nom (un
        jne     .o                      ;   DEVICELOW de HIDOS)?
        push    bx
        shr     bx,1
        call    drvname
        pop     bx
        jnc     .e
.o:     call    name_of_owner
.e:     pop     bx
        pop     ax
        ret

; BX = °ndex d'un bloc de sistema (propietari 0008h): tÇ nom a la
; capáalera (8 lletres a +8, com el DOS 4; HIDOS el posa als
; DEVICELOW)? CF=0 i el nom a nbuf; si no (o Çs SC, SD o HIDOS), CF=1
drvname:
        push    ax
        push    bx
        push    cx
        push    si
        push    es
        shl     bx,1
        mov     es,[blk_seg+bx]
        mov     al,[es:8]
        cmp     al,'0'
        jb      .no
        cmp     al,'Z'
        ja      .no
        cmp     word [es:8],'SC'
        je      .s2
        cmp     word [es:8],'SD'
        jne     .h
.s2:    cmp     byte [es:10],'0'        ; (el DOS 6 hi deixa brossa
        jb      .no                     ;   desprÇs de 'SD')
        cmp     byte [es:10],'Z'
        ja      .no
.h:     cmp     word [es:8],'HI'
        jne     .ok
        cmp     word [es:10],'DO'
        je      .no
.ok:    mov     si,8
        xor     bx,bx
        mov     cx,8
.c:     mov     al,[es:si]
        cmp     al,' '
        jbe     .z
        mov     [nbuf+bx],al
        inc     si
        inc     bx
        loop    .c
.z:     mov     byte [nbuf+bx],0
        clc
        jmp     short .r
.no:    stc
.r:     pop     es
        pop     si
        pop     cx
        pop     bx
        pop     ax
        ret

; nbuf Çs FILES, FCBS o BUFFERS (taules que HIDOS posa a baix)? CF=0
istab:  push    si
        push    di
        mov     di,s_k_fil
        call    .c
        jnc     .r
        mov     di,s_k_fcb
        call    .c
        jnc     .r
        mov     di,s_k_buf
        call    .c
.r:     pop     di
        pop     si
        ret
.c:     mov     si,nbuf
        call    strcmp
        je      .y
        stc
        ret
.y:     clc
        ret

; BX = °ndex de bloc -> SI = text del tipus
blk_type:
        push    ax
        push    bx
        push    es
        mov     al,[blk_lab+bx]         ; fitxer del GEM: segons l'extensi¢
        or      al,al
        jz      .tt
        dec     al
        xor     ah,ah
        mov     si,ax
        mov     al,[lab_kind+si]
        mov     si,s_t_gdat
        cmp     al,1
        jne     .k2
        mov     si,s_t_gacc
.k2:    cmp     al,2
        jne     .k3
        mov     si,s_t_gdrv
.k3:    cmp     al,3
        jne     .k4
        mov     si,s_t_grsc
        jmp     .e
.k4:    cmp     al,4
        jne     .e
        mov     si,s_t_prog
        jmp     .e
.tt:    mov     si,s_t_trans
        inc     bx
        cmp     bx,[trans_ix]
        je      .e
        dec     bx
        shl     bx,1
        mov     ax,[blk_own+bx]
        mov     si,s_t_free
        or      ax,ax
        jz      .e
        mov     si,s_t_sysdata
        cmp     ax,8
        jne     .t1
        push    es                      ; (0.31) el codi del DOS (HIDOS6)
        mov     es,[blk_seg+bx]
        call    is_code
        pop     es
        mov     si,s_t_sysprog
        jnc     .e
        mov     si,s_t_sysdata
        shr     bx,1
        push    word [nbuf]             ; (drvname escriu a nbuf)
        call    drvname
        mov     si,s_t_sysdata
        jc      .t0
        call    istab                   ; FILES, FCBS, BUFFERS (HIDOS):
        jnc     .t0                     ;   dades del sistema
        mov     si,s_t_device
.t0:    pop     word [nbuf]
        jmp     .e
.t1:
        mov     si,s_t_prog
        mov     bx,[blk_seg+bx]
        inc     bx
        cmp     ax,bx
        je      .e
        mov     si,s_t_data
        cmp     word [ngp],0            ; d'un programa del GEM: Datos GEM
        je      .ng
        cmp     ax,[gp_psp]
        je      .gd
        cmp     word [ngp],2
        jb      .ng
        cmp     ax,[gp_psp+2]
        jne     .ng
.gd:    push    es
        mov     es,ax
        cmp     [es:2Ch],bx             ; (el seu entorn no)
        pop     es
        je      .ng
        mov     si,s_t_gdat
        jmp     .e
.ng:    cmp     ax,40h
        jb      .e
        mov     es,ax
        cmp     word [es:0],20CDh
        jne     .e
        cmp     [es:2Ch],bx
        jne     .e
        mov     si,s_t_env
.e:     pop     es
        pop     bx
        pop     ax
        ret

; =====================================================================
;  Resum (MEM sense opcions)
; =====================================================================
; [r_tot],[r_free] = parÖgrafs (32 bits), SI = etiqueta, [cmode]
sum_row:
        push    ax
        push    cx
        push    dx
        call    lreset
        cmp     byte [cmode],0
        jne     .b
        call    lputs
        mov     ax,[r_tot]
        mov     dx,[r_tot+2]
        call    par2k
        mov     [kt],ax
        mov     [kt+2],dx
        mov     cl,25
        call    put_numk_r
        mov     ax,[r_free]
        mov     dx,[r_free+2]
        call    par2k
        mov     [kf],ax
        mov     [kf+2],dx
        mov     ax,[kt]
        mov     dx,[kt+2]
        sub     ax,[kf]
        sbb     dx,[kf+2]
        mov     cl,35
        call    put_numk_r
        mov     ax,[kf]
        mov     dx,[kf+2]
        mov     cl,45
        call    put_numk_r
        jmp     .f
.b:     mov     cl,2
        call    lcol
        call    lputs
        mov     ax,[r_tot]
        mov     dx,[r_tot+2]
        call    par2bytes
        mov     [kt],ax
        mov     [kt+2],dx
        mov     cl,30
        call    put_num_r
        mov     ax,[r_free]
        mov     dx,[r_free+2]
        call    par2bytes
        mov     [kf],ax
        mov     [kf+2],dx
        mov     ax,[kt]
        mov     dx,[kt+2]
        sub     ax,[kf]
        sbb     dx,[kf+2]
        mov     cl,43
        call    put_num_r
        mov     ax,[kf]
        mov     dx,[kf+2]
        mov     cl,56
        call    put_num_r
.f:     call    lflush
        pop     dx
        pop     cx
        pop     ax
        ret

set_rows:               ; AX = total, BX = lliure (16 bits)
        mov     [r_tot],ax
        mov     word [r_tot+2],0
        mov     [r_free],bx
        mov     word [r_free+2],0
        ret

summary_table:
        cmp     byte [cmode],0
        jne     .h2
        mov     si,s_sum_h1
        call    pline
        mov     si,s_sum_d1
        call    pline
        jmp     .rows
.h2:    mov     si,s_cls_h1
        call    pline
        mov     si,s_cls_d1
        call    pline
.rows:  mov     ax,[convtop]
        mov     bx,[cfree]
        call    set_rows
        mov     si,s_conv
        call    sum_row
        mov     ax,[utot]
        mov     bx,[ufree]
        call    set_rows
        mov     si,s_upper
        call    sum_row
        ; reservada = 10000h - convtop - utot
        xor     ax,ax
        mov     dx,1
        sub     ax,[convtop]
        sbb     dx,0
        sub     ax,[utot]
        sbb     dx,0
        mov     [r_tot],ax
        mov     [r_tot+2],dx
        mov     [r_free],ax
        mov     [r_free+2],dx
        ; (tota usada)
        mov     word [r_free],0
        mov     word [r_free+2],0
        mov     si,s_resv
        call    sum_row
        cmp     byte [cmode],0
        jne     .d2
        mov     si,s_sum_d1
        call    pline
        jmp     .tot
.d2:    mov     si,s_cls_d1
        call    pline
.tot:   mov     word [r_tot],0
        mov     word [r_tot+2],1
        mov     ax,[cfree]
        add     ax,[ufree]
        mov     [r_free],ax
        mov     word [r_free+2],0
        mov     si,s_memtot
        call    sum_row
        call    blank
        mov     ax,[convtop]
        add     ax,[utot]
        mov     [r_tot],ax
        mov     word [r_tot+2],0
        adc     word [r_tot+2],0
        mov     si,s_under1m
        call    sum_row
        call    blank
        cmp     byte [ems],0
        je      .noems
        mov     ax,[ems_tot]
        mov     si,s_emstot
        call    ems_line
        mov     ax,[ems_free]
        mov     si,s_emsfree
        call    ems_line
        call    blank
.noems: mov     ax,[bigc]
        mov     bx,[bigcs]
        mov     si,s_bigexe
        call    big_line
        mov     ax,[bigu]
        mov     bx,[bigus]
        mov     si,s_bigumb
        call    big_line
        ret

; AX = pÖgines EMS, SI = etiqueta
ems_line:
        push    ax
        call    lreset
        cmp     byte [cmode],0
        je      .a
        mov     cl,2
        call    lcol
.a:     call    lputs
        pop     ax
        push    ax
        xor     dx,dx
        mov     cx,4
.k:     shl     ax,1
        rcl     dx,1
        loop    .k
        mov     cl,[colA]
        call    put_numk_r
        mov     al,' '
        call    lputc
        pop     ax
        mov     dx,ax
        mov     cl,2
        shr     dx,cl
        mov     cl,14
        shl     ax,cl
        mov     cl,[colB]
        call    put_bytesp_r
        call    lflush
        ret

; AX = parÖgrafs, SI = etiqueta
big_line:
        mov     [bl_sz],ax
        mov     [bl_sg],bx
        push    ax
        call    lreset
        cmp     byte [cmode],0
        je      .k
        mov     cl,2
        call    lcol
        call    lputs
        pop     ax
        xor     dx,dx
        push    ax
        call    par2bytes
        mov     cl,49
        call    put_num_r
        pop     ax
        xor     dx,dx
        call    par2k
        mov     cl,57
        call    put_numkp_r
        jmp     .f
.k:     call    lputs
        pop     ax
        xor     dx,dx
        push    ax
        call    par2k
        mov     cl,43
        call    put_numk_r
        mov     al,' '
        call    lputc
        pop     ax
        xor     dx,dx
        call    par2bytes
        mov     cl,61
        call    put_bytesp_r
.f:     cmp     word [bl_sz],0          ; adreces del bloc
        je      .f0
        mov     al,' '
        call    lputc
        call    lputc
        mov     ax,[bl_sg]              ; inici = MCB+1
        inc     ax
        call    lhex4
        mov     al,'0'
        call    lputc
        mov     al,'-'
        call    lputc
        mov     ax,[bl_sg]
        add     ax,[bl_sz]
        call    lhex4
        mov     al,'F'
        call    lputc
.f0:    call    lflush
        ret

do_summary:
        mov     byte [cmode],0
        mov     byte [colA],43
        mov     byte [colB],61
        call    blank
        call    summary_table
        cmp     word [ngrp],0
        je      .e
        call    blank
        mov     si,s_hint
        call    pline
.e:     ret

; =====================================================================
;  /C
; =====================================================================
; nbuf -> afegeix (si cal) el mïdul; BX = °ndex
find_mod:
        push    ax
        push    dx
        push    di
        push    si
        xor     bx,bx
.l:     cmp     bx,[nmod]
        jae     .new
        mov     ax,9
        push    bx
        mul     bx
        pop     bx
        mov     di,ax
        add     di,mod_name
        mov     si,nbuf
        call    strcmp
        je      .f
        inc     bx
        jmp     .l
.new:   cmp     bx,MAXMOD
        jb      .ok
        mov     bx,MAXMOD-1
        jmp     .f
.ok:    inc     word [nmod]
        mov     ax,9
        push    bx
        mul     bx
        pop     bx
        mov     di,ax
        add     di,mod_name
        mov     si,nbuf
        call    strcpy
        push    bx
        shl     bx,1
        mov     word [mod_conv+bx],0
        mov     word [mod_up+bx],0
        pop     bx
.f:     pop     si
        pop     di
        pop     dx
        pop     ax
        ret

build_modules:
        mov     word [nmod],0
        mov     si,s_msdos
        mov     di,nbuf
        call    strcpy
        call    find_mod
        mov     ax,[firstmcb]
        mov     [mod_conv],ax
        mov     ax,[d6mid]              ; HIDOS: el nucli, a dalt (HIDOS6 /D:
        sub     ax,[kseg]               ;   les dades; darrere, UMBPC)
        mov     [mod_up],ax
        mov     ax,[kend]
        sub     ax,[d6mid]
        jbe     .k6
        push    ax
        mov     si,s_umbpc
        mov     di,nbuf
        call    strcpy
        call    find_mod
        shl     bx,1
        pop     ax
        add     [mod_up+bx],ax
.k6:
        xor     bx,bx
.l:     cmp     bx,[nblk]
        jae     .e
        push    bx
        shl     bx,1
        mov     cx,[blk_own+bx]
        mov     ax,[blk_size+bx]
        inc     ax
        pop     bx
        jcxz    .n
        cmp     cx,[mypsp]
        je      .n
        mov     dl,[blk_reg+bx]
        call    blk_name
        cmp     cx,8                    ; FILES/FCBS/BUFFERS de HIDOS: s¢n
        jne     .bn                     ;   del DOS (MSDOS)
        call    istab
        jc      .bn
        push    si
        push    di
        mov     si,s_msdos
        mov     di,nbuf
        call    strcpy
        pop     di
        pop     si
.bn:    push    bx
        call    find_mod
        shl     bx,1
        or      dl,dl
        jnz     .u
        add     [mod_conv+bx],ax
        jmp     .a
.u:     add     [mod_up+bx],ax
.a:     pop     bx
.n:     inc     bx
        jmp     .l
.e:     xor     di,di                   ; DEVICE= de dalt amb capáalera de
.d:     cmp     di,[ndev]               ;   HIDOS: un mïdul a part, que es
        jae     .de                     ;   treu de MSDOS
        push    di
        shl     di,1
        mov     ax,[dev_seg+di]
        mov     cx,[dev_off+di]
        pop     di
        or      cx,cx
        jnz     .dn
        call    hdrchk
        jc      .dn
        mov     si,hname
        push    di
        mov     di,nbuf
        call    strcpy
        pop     di
        call    find_mod
        shl     bx,1
        cmp     ax,[convtop]
        jb      .dlo
        add     [mod_up+bx],cx
        sub     [mod_up],cx
        jmp     short .dn
.dlo:   add     [mod_conv+bx],cx        ; (0.31) a baix (DOS 4 o mÇs)
        sub     [mod_conv],cx
.dn:    inc     di
        jmp     .d
.de:    ret

; fila de /C: SI = nom, AX = conv, BX = sup (parÖgrafs)
cls_row:
        push    ax
        push    bx
        push    cx
        call    lreset
        mov     cl,2
        call    lcol
        call    lputs
        push    ax
        add     ax,bx
        mov     cl,20
        call    put_pb_r
        mov     cl,28
        call    put_pkp_r
        pop     ax
        mov     cl,39
        call    put_pb_r
        mov     cl,47
        call    put_pkp_r
        mov     ax,bx
        mov     cl,58
        call    put_pb_r
        mov     cl,66
        call    put_pkp_r
        call    lflush
        pop     cx
        pop     bx
        pop     ax
        ret

do_classify:
        call    build_modules
        call    blank
        mov     si,s_cls_title
        call    pline
        call    blank
        mov     si,s_cls_h0
        call    pline
        mov     si,s_cls_d0
        call    pline
        xor     bx,bx
.l:     cmp     bx,[nmod]
        jae     .fr
        push    bx
        mov     ax,9
        mul     bx
        mov     si,ax
        add     si,mod_name
        shl     bx,1
        mov     ax,[mod_conv+bx]
        mov     bx,[mod_up+bx]
        call    cls_row
        pop     bx
        inc     bx
        jmp     .l
.fr:    mov     si,s_free
        mov     ax,[cfree]
        mov     bx,[ufree]
        call    cls_row
        call    blank
        call    print_resid
        mov     si,s_cls_sum
        call    pline
        call    blank
        mov     byte [cmode],1
        mov     byte [colA],43
        mov     byte [colB],61
        call    summary_table
        ret

; llista del codi resident sense bloc
print_resid:
        cmp     word [ngrp],0
        jne     .s
        jmp     .e
.s:     mov     si,s_res_title
        call    pline
        call    blank
        mov     si,s_res_h
        call    pline
        mov     si,s_res_d
        call    pline
        xor     bx,bx
.g:     cmp     bx,[ngrp]
        jb      .g1
        jmp     .ge
.g1:    call    lreset
        mov     cl,2
        call    lcol
        call    grp_range
        mov     cl,27
        call    lcol
        mov     ax,9
        push    bx
        mul     bx
        pop     bx
        mov     si,ax
        add     si,grp_name
        cmp     byte [si],0
        jne     .hn
        mov     si,s_unknown
.hn:    call    lputs
        mov     cl,42
        call    lcol
        mov     cl,[grp_nv+bx]
        xor     ch,ch
        jcxz    .nov
        mov     si,bx
        push    cx
        mov     cl,4
        shl     si,cl
        pop     cx
        cmp     cx,RESGV
        jbe     .vl
        mov     cx,RESGV
.vl:    mov     al,[grp_vec+si]
        call    lhex2
        mov     al,'h'
        call    lputc
        mov     al,' '
        call    lputc
        inc     si
        loop    .vl
        cmp     byte [grp_nv+bx],RESGV
        jbe     .ve
        mov     si,s_more
        call    lputs
        jmp     .ve
.nov:   mov     si,s_novec
        call    lputs
.ve:    call    lflush
        inc     bx
        jmp     .g
.ge:    mov     si,s_res_note
        call    pline
        call    blank
.e:     ret

; BX = grup: escriu "D0000-D145F" i, amb la columna final 24, els bytes
grp_range:
        push    ax
        push    bx
        push    cx
        push    dx
        push    si
        mov     si,bx
        shl     si,1
        mov     ax,[grp_beg+si]
        call    lhex4
        mov     al,'0'
        call    lputc
        mov     al,'-'
        call    lputc
        mov     ax,[grp_end+si]
        dec     ax
        call    lhex4
        mov     al,'F'
        call    lputc
        mov     ax,[grp_end+si]
        sub     ax,[grp_beg+si]
        xor     dx,dx
        call    par2bytes
        mov     cl,24
        call    put_num_r
        pop     si
        pop     dx
        pop     cx
        pop     bx
        pop     ax
        ret

; =====================================================================
;  /F
; =====================================================================
do_free:
        call    blank
        mov     si,s_free_title
        call    pline
        call    blank
        mov     si,s_free_h
        call    pline
        mov     si,s_free_d
        call    pline
        xor     bx,bx
        xor     dx,dx               ; total (parÖgrafs)
.l:     cmp     bx,[nblk]
        jae     .t
        cmp     byte [blk_reg+bx],0
        jne     .n
        push    bx
        shl     bx,1
        mov     cx,[blk_own+bx]
        mov     ax,[blk_size+bx]
        mov     si,[blk_seg+bx]
        pop     bx
        jcxz    .y
        cmp     cx,[mypsp]
        jne     .n
.y:     add     dx,ax
        call    lreset
        mov     cl,3
        call    lcol
        push    ax
        push    cx
        mov     cx,ax                   ; la memïria lliure, sense la
        mov     ax,si                   ; capáalera del bloc
        inc     ax
        call    lrange
        pop     cx
        pop     ax
        mov     cl,28
        call    put_pb_r
        mov     cl,36
        call    put_pkp_r
        call    lflush
.n:     inc     bx
        jmp     .l
.t:     call    blank
        call    lreset
        mov     si,s_totfree
        call    lputs
        mov     ax,dx
        mov     cl,28
        call    put_pb_r
        mov     cl,36
        call    put_pkp_r
        call    lflush
        call    blank
        cmp     byte [nreg],0
        jne     .up
        mov     si,s_noupper
        call    pline
        jmp     .r
.up:    mov     si,s_ufree_title
        call    pline
        call    blank
        mov     si,s_ufree_h
        call    pline
        mov     si,s_ufree_d
        call    pline
        mov     dl,1
.rl:    cmp     dl,[nreg]
        ja      .rd
        call    region_stats
        call    lreset
        mov     al,dl
        xor     ah,ah
        push    dx
        xor     dx,dx
        mov     cl,7
        call    put_num_r
        pop     dx
        mov     ax,[rs_big]
        mov     cl,17
        call    put_pb_r
        mov     cl,24
        call    put_pkp_r
        mov     ax,[rs_free]
        mov     cl,33
        call    put_pb_r
        mov     cl,40
        call    put_pkp_r
        mov     ax,[rs_tot]
        mov     cl,49
        call    put_pb_r
        mov     cl,56
        call    put_pkp_r
        call    lflush
        inc     dl
        jmp     .rl
.rd:    call    blank
.r:     call    print_resid
        ret

; DL = regi¢ -> rs_big, rs_free, rs_tot (parÖgrafs)
region_stats:
        push    ax
        push    bx
        push    cx
        xor     ax,ax
        mov     [rs_big],ax
        mov     [rs_free],ax
        mov     [rs_tot],ax
        mov     [run],ax
        xor     bx,bx
.l:     cmp     bx,[nblk]
        jae     .e
        cmp     [blk_reg+bx],dl
        jne     .n
        push    bx
        shl     bx,1
        mov     ax,[blk_size+bx]
        mov     cx,[blk_own+bx]
        pop     bx
        inc     ax
        add     [rs_tot],ax
        jcxz    .f
        mov     word [run],0
        jmp     .n
.f:     add     [rs_free],ax
        dec     ax
        add     [run],ax
        mov     ax,[run]
        cmp     ax,[rs_big]
        jbe     .r
        mov     [rs_big],ax
.r:     inc     word [run]
.n:     inc     bx
        jmp     .l
.e:     pop     cx
        pop     bx
        pop     ax
        ret

; =====================================================================
;  /D
; =====================================================================
; fila de detall: AX = segment, CX = parÖgrafs, SI = nom, DI = tipus,
; DL = regi¢ (0 = convencional)
dbg_row:
        push    ax
        push    cx
        call    lreset
        push    cx
        mov     [dr_end],ax             ; £ltim parÖgraf: inici + mida - 1
        add     [dr_end],cx
        dec     word [dr_end]
        mov     cl,3
        call    lcol
        call    lhex4                   ; adreáa inicial i final:
        push    ax                      ; "0A810-B7FEF"
        mov     al,'0'
        call    lputc
        pop     ax
        pop     cx
        push    cx
        jcxz    .ne
        push    ax
        mov     al,'-'
        call    lputc
        mov     ax,[dr_end]
        call    lhex4
        mov     al,'F'
        call    lputc
        pop     ax
.ne:    pop     ax
        or      dl,dl
        jz      .nr
        push    ax
        push    dx
        mov     al,dl
        xor     ah,ah
        xor     dx,dx
        mov     cl,22
        call    put_num_r
        pop     dx
        pop     ax
.nr:    mov     cl,33
        call    put_pb_r
        mov     cl,41
        call    put_pkp_r
        mov     cl,43
        call    lcol
        call    lputs
        mov     cl,56
        call    lcol
        push    si
        mov     si,di
        call    lputs
        pop     si
        call    lflush
        pop     cx
        pop     ax
        ret

; subfila: SI = nom, DI = tipus
dbg_sub:
        call    lreset
        mov     cl,43
        call    lcol
        call    lputs
        mov     cl,56
        call    lcol
        push    si
        mov     si,di
        call    lputs
        pop     si
        call    lflush
        ret

; controladors amb segment dins [AX,BX): DI = tipus per defecte
dbg_devs:
        push    ax
        push    bx
        push    cx
        push    dx
        push    si
        push    di
        mov     [dd_lo],ax
        mov     [dd_hi],bx
        mov     [dd_type],di
        mov     [dd_reg],dl
        xor     bx,bx                   ; (els controladors instal˙lats, en
        mov     word [dd_dir],1         ;   ordre invers de la cadena: per
        cmp     di,s_t_device           ;   adreáa, del primer al darrer)
        jne     .l
        mov     bx,[ndev]
        dec     bx
        mov     word [dd_dir],-1
.l:     cmp     bx,[ndev]               ; (-1 tambÇ surt: Çs >= ndev)
        jae     .e
        push    bx
        shl     bx,1
        mov     ax,[dev_seg+bx]
        mov     cx,[dev_off+bx]
        pop     bx
        cmp     ax,[dd_lo]
        jb      .n
        cmp     ax,[dd_hi]
        jae     .n
        or      cx,cx                   ; controlador amb capáalera de
        jnz     .lb                     ;   HIDOS (DEVICE= a dalt): una
        push    cx                      ;   fila amb el seu nom i mida
        call    hdrchk
        jc      .nh
        push    ax
        push    dx
        push    si
        push    di
        dec     ax
        mov     si,hname
        mov     di,s_t_device
        mov     dl,[dd_reg]
        call    dbg_row
        pop     di
        pop     si
        pop     dx
        pop     ax
.nh:    pop     cx
.lb:    call    dev_label
        mov     di,[dd_type]
        cmp     ax,[dosseg]
        jbe     .t
        or      cx,cx
        jnz     .t
        mov     di,s_t_device
.t:     mov     si,dlab
        call    dbg_sub
.n:     add     bx,[dd_dir]
        jmp     .l
.e:     pop     di
        pop     si
        pop     dx
        pop     cx
        pop     bx
        pop     ax
        ret

; AX = segment d'un controlador: tÇ davant la capáalera que hi posa
; HIDOS ('D', segment, mida, nom, com els subblocs del DOS 4)? CF=0,
; el nom a hname i CX = parÖgrafs (capáalera inclosa)
hdrchk: push    es
        push    si
        push    di
        push    ax
        dec     ax
        mov     es,ax
        inc     ax
        cmp     byte [es:0],'D'
        jne     .no
        cmp     [es:1],ax
        jne     .no
        mov     cx,[es:3]
        jcxz    .no
        mov     al,[es:8]
        cmp     al,'0'
        jb      .no
        cmp     al,'Z'
        ja      .no
        inc     cx
        push    cx
        mov     si,8
        xor     di,di
        mov     cx,8
.c:     mov     al,[es:si]
        cmp     al,' '
        jbe     .z
        mov     [hname+di],al
        inc     si
        inc     di
        loop    .c
.z:     mov     byte [hname+di],0
        pop     cx
        clc
        jmp     short .r
.no:    stc
.r:     pop     ax
        pop     di
        pop     si
        pop     es
        ret

do_debug:
        call    blank
        mov     si,s_dbg_title
        call    pline
        call    blank
        mov     si,s_dbg_h
        call    pline
        mov     si,s_dbg_d
        call    pline
        xor     dl,dl
        mov     si,s_empty
        xor     ax,ax
        mov     cx,40h
        mov     di,s_t_ivt
        call    dbg_row
        mov     ax,40h
        mov     cx,10h
        mov     di,s_t_rom
        call    dbg_row
        mov     ax,50h
        mov     cx,20h
        mov     di,s_t_dosc
        call    dbg_row
        cmp     word [kseg],0           ; HIDOS: IO (si no Çs a dalt) i
        je      .io0                    ;   els DEVICELOW
        call    dbg_low
        jmp     .nod
.io0:   mov     bx,[dosseg]             ; final de l'IO: el DOS
.io:    push    bx
        mov     ax,70h
        mov     cx,bx
        sub     cx,70h
        mov     si,s_io
        mov     di,s_t_sysdata
        call    dbg_row
        mov     ax,70h
        pop     bx
        mov     di,s_t_sysdrv
        call    dbg_devs
        cmp     word [kseg],0
        jne     .nod
        mov     ax,[dosseg]
        mov     cx,[firstmcb]
        sub     cx,ax
        mov     si,s_msdos
        mov     di,s_t_sysprog
        cmp     byte [dosmaj],5         ; (0.31) DOS 5+: aqu° nomÇs hi ha
        jb      .io5                    ;   les dades (el codi, en un bloc
        mov     di,s_t_sysdata          ;   'SC' o a l'HMA)
.io5:   call    dbg_row
        mov     bx,[firstmcb]
        mov     di,s_t_sysdrv
        call    dbg_devs
.nod:
        ; blocs convencionals
        xor     bx,bx
.l:     cmp     bx,[nblk]
        jae     .le
        cmp     byte [blk_reg+bx],0
        jne     .ln
        call    dbg_blk
.ln:    inc     bx
        jmp     .l
.le:    cmp     byte [nreg],0
        je      .noup
        call    blank
        mov     si,s_udbg_title
        call    pline
        call    blank
        mov     si,s_udbg_h
        call    pline
        mov     si,s_udbg_d
        call    pline
        cmp     word [kseg],0           ; HIDOS: primer, el nucli
        je      .uk
        cmp     word [iohi],0           ; (i abans, el BIOS amb /B)
        je      .uk1
        mov     ax,[iohi]
        mov     cx,[dosseg]
        sub     cx,ax
        mov     si,s_io
        mov     di,s_t_sysdata
        xor     dl,dl
        call    dbg_row
        mov     ax,[iohi]
        mov     bx,[dosseg]
        mov     di,s_t_sysdrv
        call    dbg_devs
.uk1:   cmp     byte [dosmaj],5         ; (0.31) DOS 6 amb HIDOS6 /D
        jb      .uk3
        call    dbg_d6
        jmp     .uk
.uk3:   mov     ax,[dosseg]
        mov     cx,[kend]
        sub     cx,ax
        mov     si,s_msdos
        mov     di,s_t_sysprog
        xor     dl,dl
        call    dbg_row
        mov     ax,[dosseg]
        mov     bx,[kend]
        mov     di,s_t_sysdrv
        call    dbg_devs
.uk:    xor     bx,bx
.u:     cmp     bx,[nblk]
        jae     .noup
        cmp     byte [blk_reg+bx],0
        je      .un
        call    dbg_blk
.un:    inc     bx
        jmp     .u
.noup:  call    blank
        call    do_bfx
        call    do_map
        call    print_resid
        mov     byte [cmode],0
        mov     byte [colA],43
        mov     byte [colB],61
        call    summary_table
        ret

; (0.31) HIDOS6 /D: les dades del DOS a dalt i, darrere, UMBPC
dbg_d6: mov     ax,[kseg]
        mov     cx,[d6mid]
        sub     cx,ax
        mov     si,s_msdos
        mov     di,s_t_sysdata
        xor     dl,dl
        call    dbg_row
        mov     ax,[kseg]
        mov     bx,[d6mid]
        mov     di,s_t_sysdrv
        call    dbg_devs
        mov     ax,[d6mid]
        mov     cx,[kend]
        sub     cx,ax
        jbe     .e
        mov     si,s_umbpc
        mov     di,s_t_prog
        call    dbg_row
.e:     ret

; HIDOS: a baix, l'IO (sense /B) i els DEVICELOW
dbg_low:
        mov     bx,[lowdrv]
        cmp     word [iohi],0
        jne     .d
        mov     ax,70h
        mov     cx,bx
        sub     cx,ax
        mov     si,s_io
        mov     di,s_t_sysdata
        xor     dl,dl
        call    dbg_row
        mov     ax,70h
        mov     di,s_t_sysdrv
        call    dbg_devs
.d:     mov     ax,[lowdrv]
        mov     cx,[firstmcb]
        sub     cx,ax
        jbe     .e
        mov     si,s_msdos
        mov     di,s_t_sysdata
        xor     dl,dl
        call    dbg_row
        mov     ax,[lowdrv]
        mov     bx,[firstmcb]
        mov     di,s_t_device
        call    dbg_devs
.e:     ret

; BX = °ndex de bloc
dbg_blk:
        push    bx
        push    dx
        call    blk_name
        call    blk_type
        mov     di,si
        mov     si,nbuf
        mov     dl,[blk_reg+bx]
        shl     bx,1
        mov     ax,[blk_seg+bx]
        mov     cx,[blk_size+bx]
        inc     cx
        call    dbg_row
        ; controladors dins el bloc
        mov     bx,ax
        add     bx,cx
        mov     di,s_t_device
        call    dbg_devs
        call    dbg_subs
        pop     dx
        pop     bx
        ret

; (0.31) AX = MCB d'un bloc 'SD' del DOS 4 o mÇs (CX = parÖgrafs amb el
; MCB): una fila per a cada subbloc de FILES, FCBS, BUFFERS, LASTDRIVE,
; STACKS i el tros temporal de l'IO.SYS (els DEVICE= ja hi s¢n)
dbg_subs:
        push    ax
        push    bx
        push    cx
        push    si
        push    di
        push    es
        mov     es,ax
        cmp     word [es:1],8
        jne     .e
        cmp     word [es:8],'SD'
        jne     .e
        cmp     byte [dosmaj],4
        jb      .e
        mov     bx,ax
        add     bx,cx                   ; final del bloc
        inc     ax
.l:     cmp     ax,bx
        jae     .e
        mov     es,ax
        mov     cx,[es:3]
        inc     cx
        mov     al,[es:0]
        mov     si,s_k_fil
        cmp     al,'F'
        je      .p
        mov     si,s_k_fcb
        cmp     al,'X'
        je      .p
        mov     si,s_k_buf
        cmp     al,'B'
        je      .p
        mov     si,s_k_ld
        cmp     al,'L'
        je      .p
        mov     si,s_k_stk
        cmp     al,'S'
        je      .p
        mov     si,s_k_tmp
        cmp     al,'T'
        jne     .n
.p:     mov     ax,es
        mov     di,s_t_sysdata
        call    dbg_row
.n:     mov     ax,es
        add     ax,cx
        jc      .e
        jmp     .l
.e:     pop     es
        pop     di
        pop     si
        pop     cx
        pop     bx
        pop     ax
        ret

; =====================================================================
;  BUFFERS, FILES i FCBS (MEM /D), DOS 3.1-3.3
;  Llista de llistes (INT 21h AH=52h, ES:BX):
;    +04h  dword  primera taula de fitxers (SFT)
;    +10h  word   mida mÖxima de sector
;    +12h  dword  primer buffer de disc
;    +1Ah  dword  taula de FCB (mateix format que les SFT)
;    +1Eh  word   FCB protegits
;  Buffer: +00h dword segÅent (desplaáament FFFFh = final), capáalera de
;  16 bytes + un sector. Taula SFT/FCB: +00h dword segÅent (FFFFh =
;  final), +04h word entrades, +06h entrades de 35h bytes.
; =====================================================================
SFTSZ   equ     35h

do_bfx:
        mov     ah,30h
        int     21h
        mov     word [sftsz],SFTSZ
        cmp     al,5                    ; (0.31) DOS 5 i 6
        jb      .v3
        cmp     al,6
        ja      .nov
        mov     word [sftsz],3Bh
        jmp     short .vok
.v3:    cmp     al,3
        jne     .nov
        cmp     ah,10
        jb      .nov
        cmp     ah,30
        ja      .nov
.vok:
        mov     si,s_bfx_title
        call    pline
        call    blank
        mov     si,s_bfx_h
        call    pline
        mov     si,s_bfx_d
        call    pline
        mov     word [t_buf],0
        mov     word [t_fil],0
        mov     word [t_fcb],0
        push    es
        mov     ah,52h
        int     21h
        mov     [lol_s],es
        mov     [lol_o],bx
        mov     ax,[es:bx+10h]
        add     ax,16
        mov     [bsize],ax
        cmp     word [sftsz],SFTSZ
        je      .b3
        ; (0.31) DOS 5 i 6: +12h apunta a la informaci¢ dels buffers, que
        ; comenáa amb l'adreáa del primer; els buffers fan una cadena
        ; circular (+00h segÅent, +02h anterior, desplaáaments dins el
        ; mateix segment) amb una capáalera de 14h bytes
        add     word [bsize],14h-16
        les     bx,[es:bx+12h]
        mov     ax,[es:bx]
        mov     [p_o],ax
        mov     ax,[es:bx+2]
        mov     [p_s],ax
        mov     word [nbufs],0
        mov     di,bufl
        mov     cx,[p_o]                ; el primer, per saber quan acaba
.b5:    cmp     word [nbufs],MAXBUF
        jae     .bs
        mov     ax,[p_s]
        mov     bx,[p_o]
        call    linear
        mov     [di],ax
        mov     [di+2],dx
        add     di,4
        inc     word [nbufs]
        les     bx,[p_o]
        mov     ax,[es:bx]
        mov     [p_o],ax
        cmp     ax,cx
        jne     .b5
        jmp     .bs
.b3:
        ; --- BUFFERS. DOS els tÇ encadenats per ordre d'£s (el darrer
        ;     que fa servir passa al davant), no per adreáa: primer es
        ;     recullen les adreces, s'ordenen i desprÇs s'agrupen els
        ;     que s¢n seguits a la memïria.
        mov     ax,[es:bx+12h]
        mov     [p_o],ax
        mov     ax,[es:bx+14h]
        mov     [p_s],ax
        mov     word [nbufs],0
        mov     di,bufl
.bc:    cmp     word [p_o],0FFFFh
        je      .bs
        cmp     word [nbufs],MAXBUF
        jae     .bs
        mov     ax,[p_s]
        mov     bx,[p_o]
        call    linear
        mov     [di],ax
        mov     [di+2],dx
        add     di,4
        inc     word [nbufs]
        les     bx,[p_o]
        mov     ax,[es:bx]
        mov     dx,[es:bx+2]
        mov     [p_o],ax
        mov     [p_s],dx
        jmp     .bc
.bs:    ; ordenaci¢ per inserci¢ (DX:AX)
        mov     cx,1
.si:    cmp     cx,[nbufs]
        jae     .sd
        mov     si,cx
        shl     si,1
        shl     si,1
        add     si,bufl
        mov     ax,[si]
        mov     dx,[si+2]
.sj:    cmp     si,bufl
        je      .sp
        cmp     dx,[si-2]
        ja      .sp
        jb      .sm
        cmp     ax,[si-4]
        jae     .sp
.sm:    mov     bx,[si-4]
        mov     [si],bx
        mov     bx,[si-2]
        mov     [si+2],bx
        sub     si,4
        jmp     .sj
.sp:    mov     [si],ax
        mov     [si+2],dx
        inc     cx
        jmp     .si
.sd:    ; grups seguits
        mov     si,bufl
        mov     cx,[nbufs]
.bg:    jcxz    .bend
        mov     ax,[si]                 ; inici del grup
        mov     dx,[si+2]
        call    lin2seg
        mov     word [r_n],0
.bn:    inc     word [r_n]
        inc     word [t_buf]
        dec     cx
        jz      .bf
        mov     ax,[si]
        mov     dx,[si+2]
        add     ax,[bsize]
        adc     dx,0
        add     si,4
        cmp     ax,[si]
        jne     .bf2
        cmp     dx,[si+2]
        je      .bn
        jmp     short .bf2
.bf:    add     si,4
.bf2:   mov     ax,[r_n]
        mul     word [bsize]
        mov     [r_sz],ax
        push    si
        mov     si,s_k_buf
        call    bfx_row
        pop     si
        jmp     .bg
.bend:
        ; --- FILES: cada taula de la cadena
        les     bx,[lol_o]
        mov     ax,[es:bx+4]
        mov     [p_o],ax
        mov     ax,[es:bx+6]
        mov     [p_s],ax
        mov     si,s_k_fil
        mov     di,t_fil
        call    bfx_sft
        ; --- FCBS
        les     bx,[lol_o]
        mov     ax,[es:bx+1Eh]
        mov     [t_prot],ax
        mov     ax,[es:bx+1Ah]
        mov     [p_o],ax
        mov     ax,[es:bx+1Ch]
        mov     [p_s],ax
        or      ax,ax
        jz      .nofcb
        mov     si,s_k_fcb
        mov     di,t_fcb
        call    bfx_sft
.nofcb: pop     es
        ; --- totals
        call    blank
        mov     si,s_k_buf
        mov     ax,[t_buf]
        call    bfx_tot
        mov     si,s_k_fil
        mov     ax,[t_fil]
        call    bfx_tot
        mov     si,s_k_fcb
        mov     ax,[t_fcb]
        call    bfx_tot
        mov     si,s_bfx_prot
        call    lputs
        mov     ax,[t_prot]
        xor     dx,dx
        call    fmt_u32
        call    lputs
        mov     al,')'
        call    lputc
        call    lflush
        call    blank
        ret
.nov:   mov     si,s_bfx_nov
        call    pline
        call    blank
        ret

; cadena de taules SFT/FCB des de [p_s]:[p_o]. SI = tipus, DI = total
bfx_sft:
        mov     word [guard],100
.l:     cmp     word [p_o],0FFFFh
        je      .e
        dec     word [guard]
        jz      .e
        push    es
        les     bx,[p_o]
        mov     ax,[p_s]
        mov     [r_seg],ax
        mov     [r_ofs],bx
        mov     cx,[es:bx+4]
        mov     [r_n],cx
        add     [di],cx
        mov     ax,[sftsz]
        mul     cx
        add     ax,6
        mov     [r_sz],ax
        mov     ax,[es:bx]
        mov     dx,[es:bx+2]
        pop     es
        mov     [p_o],ax
        mov     [p_s],dx
        call    bfx_row
        jmp     .l
.e:     ret

; DX:AX adreáa lineal -> [r_seg]:[r_ofs] (desplaáament 0-15)
lin2seg:
        push    ax
        push    cx
        push    dx
        mov     cx,ax
        and     cx,0Fh
        mov     [r_ofs],cx
        mov     cl,4
        shr     ax,cl
        mov     cl,12
        shl     dx,cl
        or      ax,dx
        mov     [r_seg],ax
        pop     dx
        pop     cx
        pop     ax
        ret

; AX = segment, BX = desplaáament -> DX:AX = adreáa lineal
linear: push    cx
        mov     dx,ax
        mov     cl,4
        shl     ax,cl
        mov     cl,12
        shr     dx,cl
        add     ax,bx
        adc     dx,0
        pop     cx
        ret

; DX:AX adreáa lineal -> 5 xifres hex
lhexlin:
        push    ax
        mov     al,dl
        and     al,0Fh
        add     al,'0'
        cmp     al,'9'
        jbe     .d
        add     al,7
.d:     call    lputc
        pop     ax
        call    lhex4
        ret

; fila: [r_seg]:[r_ofs] inici, [r_sz] bytes, [r_n] quantitat, SI = tipus
bfx_row:
        push    ax
        push    bx
        push    cx
        push    dx
        push    si
        call    lreset
        mov     cl,3
        call    lcol
        mov     ax,[r_seg]
        mov     bx,[r_ofs]
        call    linear
        push    dx
        push    ax
        call    lhexlin
        mov     al,'-'
        call    lputc
        pop     ax
        pop     dx
        add     ax,[r_sz]
        adc     dx,0
        sub     ax,1
        sbb     dx,0
        call    lhexlin
        mov     ax,[r_sz]
        xor     dx,dx
        mov     cl,25
        call    put_num_r
        mov     ax,[r_n]
        xor     dx,dx
        mov     cl,34
        call    put_num_r
        mov     cl,37
        call    lcol
        call    lputs
        mov     cl,47
        call    lcol
        ; on Çs: dins el DOS (abans del primer bloc), en un bloc de
        ; memïria convencional (el que fa el DOS amb el CONFIG.SYS) o a
        ; la memïria superior (LOADHI /B, /FILES)
        mov     ax,[r_ofs]
        mov     cl,4
        shr     ax,cl
        add     ax,[r_seg]
        mov     si,s_o_dos
        cmp     ax,[firstmcb]
        jb      .o
        cmp     byte [dosmaj],5         ; (0.31) dins les dades del DOS 6
        jb      .o2                     ;   de dalt (HIDOS6 /D)
        cmp     word [kseg],0
        je      .o2
        cmp     ax,[kseg]
        jb      .o2
        cmp     ax,[kend]
        jb      .o
.o2:    mov     si,s_o_up
        cmp     ax,[convtop]
        jae     .o
        mov     si,s_o_conv
.o:     call    lputs
        call    lflush
        pop     si
        pop     dx
        pop     cx
        pop     bx
        pop     ax
        ret

; SI = tipus, AX = total
bfx_tot:
        push    ax
        call    lreset
        push    si
        mov     si,s_bfx_tot
        call    lputs
        pop     si
        call    lputs
        mov     al,':'
        call    lputc
        pop     ax
        xor     dx,dx
        mov     cl,26
        call    put_num_r
        cmp     si,s_k_fcb
        je      .x                      ; la l°nia de FCBS continua
        call    lflush
.x:     ret

; --- mapa de convtop a FFFFF
do_map:
        call    lreset
        mov     si,s_map1
        call    lputs
        mov     ax,[convtop]
        call    lhex4
        mov     al,'0'
        call    lputc
        mov     si,s_map2
        call    lputs
        call    lflush
        call    blank
        mov     si,s_map_h
        call    pline
        mov     si,s_map_d
        call    pline
        mov     ax,[convtop]
        mov     [m_start],ax
        call    next_b
        call    classify
        mov     [m_cls],dl
        mov     cx,[cl_grp]
        mov     [m_grp],cx
.l:     mov     ax,bx                   ; tros segÅent
        or      ax,ax
        jz      .end                    ; 1 MB
        call    next_b
        call    classify
        cmp     dl,[m_cls]
        jne     .new
        cmp     dl,C_RESID
        jne     .l
        mov     cx,[cl_grp]
        cmp     cx,[m_grp]
        je      .l
.new:   push    bx
        mov     bx,ax
        call    map_row
        pop     bx
        mov     [m_start],ax
        mov     [m_cls],dl
        mov     cx,[cl_grp]
        mov     [m_grp],cx
        jmp     .l
.end:   mov     word [m_endlo],0
        mov     byte [m_endhi],1
        call    map_row_end
        call    blank
        ret

; AX = parÖgraf -> BX = final del tros (exclusiu; 0 = 1 MB): el
; segÅent l°mit de 2 KB, o l'inici o el final d'un resident sense bloc
next_b:
        push    cx
        push    si
        mov     bx,ax
        and     bx,0FF80h
        add     bx,80h
        mov     cx,[kseg]               ; l°mits del nucli (HIDOS)
        jcxz    .k2
        call    .lim
        mov     cx,[kend]
        call    .lim
.k2:    xor     si,si
.g:     cmp     si,[ngrp]
        jae     .x
        push    si
        shl     si,1
        mov     cx,[grp_beg+si]
        cmp     ax,cx
        jb      .bf
        cmp     ax,[grp_end+si]
        jae     .nx
        mov     bx,[grp_end+si]         ; dins el resident: fins al final
        pop     si
        jmp     short .x
.bf:    or      bx,bx                   ; comenáa abans del l°mit?
        jz      .lt
        cmp     cx,bx
        jae     .nx
.lt:    mov     bx,cx
.nx:    pop     si
        inc     si
        jmp     .g
.x:     pop     si
        pop     cx
        ret
.lim:   cmp     ax,cx                   ; CX dins (AX, BX)? -> BX = CX
        jae     .lm2
        or      bx,bx
        jz      .lm1
        cmp     cx,bx
        jae     .lm2
.lm1:   mov     bx,cx
.lm2:   ret

; fila de mapa de [m_start] fins a BX (exclusiu)
map_row:
        mov     [m_endlo],bx
        mov     byte [m_endhi],0
map_row_end:
        push    ax
        push    bx
        push    cx
        push    dx
        push    si
        call    lreset
        mov     cl,2
        call    lcol
        mov     ax,[m_start]
        call    lhex4
        mov     al,'0'
        call    lputc
        mov     al,'-'
        call    lputc
        mov     ax,[m_endlo]
        dec     ax
        call    lhex4
        mov     al,'F'
        call    lputc
        mov     ax,[m_endlo]
        mov     dl,[m_endhi]
        xor     dh,dh
        sub     ax,[m_start]
        sbb     dx,0
        call    par2bytes
        mov     cl,24
        call    put_num_r
        mov     cl,26
        call    lcol
        mov     bl,[m_cls]
        xor     bh,bh
        cmp     bl,C_RESID
        jne     .t
        mov     si,s_c_res1
        call    lputs
        mov     ax,9
        mul     word [m_grp]
        mov     si,ax
        add     si,grp_name
        cmp     byte [si],0
        jne     .rn
        mov     si,s_unknown
.rn:    call    lputs
        mov     si,s_c_res2
        jmp     short .t2
.t:     shl     bx,1
        mov     si,[cls_txt+bx]
.t2:    call    lputs
        call    lflush
        pop     si
        pop     dx
        pop     cx
        pop     bx
        pop     ax
        ret

; AX = parÖgraf (inici de tros), BX = final (0 = 1 MB) -> DL = classe
classify:
        push    ax
        push    bx
        push    cx
        push    si
        push    di
        push    es
        mov     [cl_ax],ax
        mov     [cl_end],bx
        mov     dl,C_DOSK               ; nucli del DOS (HIDOS)?
        cmp     word [kseg],0
        je      .k0
        cmp     ax,[kseg]
        jb      .k0
        cmp     ax,[kend]
        jae     .k0
        jmp     .x
.k0:
        mov     dl,C_VIDEO
        cmp     ax,[vidend]
        jae     .r
        cmp     ax,0A000h
        jae     .x
.r:     call    in_rom
        mov     dl,C_ROM
        jc      .x
        push    dx
        call    in_region
        pop     dx
        mov     dl,C_CHAIN
        jc      .x
        ; dins un resident sense bloc?
        xor     si,si
.g:     cmp     si,[ngrp]
        jae     .ng
        push    si
        shl     si,1
        cmp     ax,[grp_beg+si]
        jb      .gn0
        cmp     ax,[grp_end+si]
        jae     .gn0
        pop     si
        mov     [cl_grp],si
        mov     dl,C_RESID
        jmp     .x
.gn0:   pop     si
        inc     si
        jmp     .g
.ng:    ; contingut
        mov     cx,[cl_end]
        sub     cx,ax               ; parÖgrafs fins al final del tros
        shl     cx,1
        shl     cx,1
        shl     cx,1                ; paraules
        mov     es,ax
        push    cx
        xor     di,di
        mov     ax,0FFFFh
        repe    scasw
        pop     cx
        mov     dl,C_EMPTY
        je      .ram
        xor     di,di
        xor     ax,ax
        repe    scasw
        mov     dl,C_ZERO
        je      .ram
        mov     dl,C_USED
        push    ax
        mov     ax,[cl_ax]
        cmp     ax,[utop]
        pop     ax
        jb      .x
        mov     dl,C_SYSROM
.x:     pop     es
        pop     di
        pop     si
        pop     cx
        pop     bx
        pop     ax
        ret
.ram:   ; tot 00h o tot FFh: Çs RAM sense usar o no hi ha res? Es prova
        ; el primer i l'£ltim byte del tros (sense canviar-los)
        xor     di,di
        call    ramprobe
        jnc     .rm
        mov     di,[cl_end]
        sub     di,[cl_ax]
        mov     cl,4
        shl     di,cl
        dec     di
        call    ramprobe
        jc      .x
.rm:    add     dl,C_RAMFF-C_EMPTY      ; EMPTY->RAMFF, ZERO->RAM0
        jmp     .x

; ES:DI = byte. CF=0 si Çs RAM (s'hi pot escriure). No el canvia.
ramprobe:
        push    ax
        pushf
        cli
        mov     al,[es:di]
        mov     ah,al
        not     ah
        mov     [es:di],ah
        cmp     [es:di],ah
        mov     [es:di],al
        jne     .no
        popf
        pop     ax
        clc
        ret
.no:    popf
        pop     ax
        stc
        ret

; =====================================================================
;  /M
; =====================================================================
do_module:
        mov     si,modname
        mov     di,s_msdos
        call    strcmp
        jne     .nm
        mov     byte [m_ismsdos],1
.nm:    ; existeix?
        xor     bx,bx
        mov     byte [m_found],0
        cmp     byte [m_ismsdos],0
        jne     .yes
.f:     cmp     bx,[nblk]
        jae     .fg
        call    blk_name
        mov     si,nbuf
        mov     di,modname
        call    strcmp
        je      .yes
        inc     bx
        jmp     .f
.fg:    xor     bx,bx
.fg2:   cmp     bx,[ngrp]
        jae     .no
        mov     ax,9
        push    bx
        mul     bx
        pop     bx
        mov     si,ax
        add     si,grp_name
        mov     di,modname
        call    strcmp
        je      .yes
        inc     bx
        jmp     .fg2
.no:    call    lreset
        mov     si,modname
        call    lputs
        mov     si,s_notfound
        call    lputs
        call    lflush
        ret
.yes:   call    blank
        call    lreset
        mov     si,modname
        call    lputs
        mov     si,s_mod_title
        call    lputs
        call    lflush
        call    blank
        mov     si,s_mod_h
        call    pline
        mov     si,s_mod_d
        call    pline
        mov     word [m_total],0
        cmp     byte [m_ismsdos],0
        je      .bl
        xor     dl,dl
        xor     ax,ax
        mov     cx,[firstmcb]
        mov     di,s_t_sysdata
        call    mod_row
        cmp     word [kseg],0           ; HIDOS: el nucli, a dalt
        je      .bl
        xor     dl,dl
        mov     ax,[kseg]
        mov     cx,[kend]
        sub     cx,ax
        mov     di,s_t_sysprog
        call    mod_row
.bl:    xor     bx,bx
.l:     cmp     bx,[nblk]
        jae     .le
        call    blk_name
        mov     si,nbuf
        mov     di,modname
        call    strcmp
        jne     .ln
        push    bx
        call    blk_type
        mov     di,si
        mov     dl,[blk_reg+bx]
        shl     bx,1
        mov     ax,[blk_seg+bx]
        mov     cx,[blk_size+bx]
        inc     cx
        call    mod_row
        pop     bx
.ln:    inc     bx
        jmp     .l
.le:    mov     si,s_mod_sep
        call    pline
        call    lreset
        mov     si,s_mod_tot
        call    lputs
        mov     ax,[m_total]
        mov     cl,27
        call    put_pb_r
        mov     cl,35
        call    put_pkp_r
        call    lflush
        ; codi resident sense bloc amb aquest nom
        xor     bx,bx
.g:     cmp     bx,[ngrp]
        jae     .e
        mov     ax,9
        push    bx
        mul     bx
        pop     bx
        mov     si,ax
        add     si,grp_name
        mov     di,modname
        call    strcmp
        jne     .gn
        call    blank
        call    lreset
        mov     si,s_mod_res
        call    lputs
        call    lflush
        call    lreset
        mov     cl,2
        call    lcol
        call    grp_range
        mov     si,s_mod_res2
        call    lputs
        call    lflush
.gn:    inc     bx
        jmp     .g
.e:     ret

; AX = segment, CX = parÖgrafs, DL = regi¢, DI = tipus
mod_row:
        add     [m_total],cx
        call    lreset
        push    cx
        push    cx
        mov     cl,3
        call    lcol
        pop     cx
        call    lrange
        pop     ax
        or      dl,dl
        jz      .nr
        push    ax
        push    dx
        mov     al,dl
        xor     ah,ah
        xor     dx,dx
        mov     cl,22
        call    put_num_r
        pop     dx
        pop     ax
.nr:    mov     cl,33
        call    put_pb_r
        mov     cl,41
        call    put_pkp_r
        mov     cl,43
        call    lcol
        mov     si,di
        call    lputs
        call    lflush
        ret

; =====================================================================
;  /?
; =====================================================================
show_help:
        mov     si,help_txt
.l:     cmp     byte [si],0FFh
        je      .e
        call    pline
.s:     lodsb
        or      al,al
        jnz     .s
        jmp     .l
.e:     ret

; =====================================================================
;  Dades
; =====================================================================
flags   db      0
wantname db     0
thsep   db      '.'
cmode   db      0
colA    db      43
colB    db      61
ems     db      0
m_ismsdos db    0
m_found db      0
nlines  dw      0

swtab   dw      sw_c, F_C, sw_classify, F_C, sw_d, F_D, sw_debug, F_D
        dw      sw_f, F_F, sw_free, F_F, sw_m, F_M, sw_module, F_M
        dw      sw_p, F_P, sw_page, F_P, sw_q, F_H
        dw      sw_np, F_NP, sw_pm, F_NP, sw_g, F_G, 0, 0
sw_c    db      'C',0
sw_classify db  'CLASSIFY',0
sw_d    db      'D',0
sw_debug db     'DEBUG',0
sw_f    db      'F',0
sw_free db      'FREE',0
sw_m    db      'M',0
sw_module db    'MODULE',0
sw_p    db      'P',0
sw_page db      'PAGE',0
sw_np   db      'NP',0
sw_pm   db      'P-',0
sw_q    db      '?',0
sw_g    db      'G',0

cls_txt dw      s_c_video, s_c_rom, s_c_chain, s_c_resid, s_c_sysrom
        dw      s_c_used, s_c_empty, s_c_zero, s_c_ramff, s_c_ram0
        dw      s_c_dosk

s_emm   db      'EMMXXXX0'
s_msdos db      'MSDOS',0
s_k_ld  db      'LASTDRIVE',0
s_umbpc db      'UMBPC',0
s_k_stk db      'STACKS',0
s_k_tmp db      'INSTALL',0
s_mem   db      'MEM',0
s_command db    'COMMAND',0
s_io    db      'IO',0
s_empty db      0
s_free  db      'Libre',0
s_unknown db    '(desconocido)',0
s_more  db      '...',0
s_novec db      '(controlador)',0
s_bytes_cl db   ' bytes)',0

s_badver db     'Versi¢n incorrecta de DOS',0
s_chainerr db   'La cadena de bloques de memoria est† da§ada; MEM no puede continuar',0
s_badsw db      'Modificador no v†lido - ',0
s_badparm db    'Par†metro no v†lido - ',0
s_noname db     'Falta el nombre del m¢dulo',0
s_notfound db   ' no se encuentra actualmente en la memoria.',0

s_pause db      'Presione cualquier tecla para continuar . . .'
s_pause_len equ $-s_pause
s_unpause db    13,'                                              ',13
s_unpause_len equ $-s_unpause

s_sum_h1 db     'Tipo de memoria    Total  =  Usada  +  Libre',0
s_sum_d1 db     '----------------  -------   -------   -------',0
s_conv  db      'Convencional',0
s_upper db      'Superior',0
s_resv  db      'Reservada',0
s_memtot db     'Memoria total',0
s_under1m db    'Total menor 1 MB',0
s_emstot db     'Total expandida (EMS)               ',0
s_emsfree db    'Libre expandida (EMS)               ',0
utop    dw      0F000h
bigcs   dw      0
bigus   dw      0
runs    dw      0
bl_sz   dw      0
bl_sg   dw      0
s_bigexe db     'Programa ejecutable m†s extenso      ',0
s_bigumb db     'Bloque memoria superior m†s extenso  ',0
s_hint  db      'Hay c¢digo residente por encima de la memoria convencional; vea MEM /C.',0

s_cls_title db  'M¢dulos que usan memoria por debajo de 1 MB:',0
s_cls_h0 db     '  Nombre    Tama§o programa  =   Convencional   + Memoria superior',0
s_cls_d0 db     '  --------  ----------------   ----------------   ----------------',0
s_cls_sum db    'Sinopsis de memoria:',0
s_cls_h1 db     '  Tipo de memoria     Total    =   Usada    +   Libre',0
s_cls_d1 db     '  ----------------  ----------   ----------   ----------',0

s_res_title db  'C¢digo residente por encima de la memoria convencional sin bloque de memoria:',0
s_res_h db      '  Direcci¢n       Tama§o*  Nombre         Interrupciones',0
s_res_d db      '  -----------  ----------  -------------  ------------------------------------',0
s_res_note db   '  * Hasta el £ltimo byte no vac°o: si acaba con datos a cero, ocupa algo m†s.',0

s_free_title db 'Memoria convencional libre:',0
s_free_h db     '   Direcci¢n            Total',0
s_free_d db     '   -----------    ------------------',0
s_totfree db    '  Total libre: ',0
s_noupper db    'No hay memoria superior disponible',0
s_ufree_title db 'Memoria superior libre:',0
s_ufree_h db    '  Regi¢n  Mayor libre     Total libre     Tama§o total',0
s_ufree_d db    '  ------  --------------  --------------  --------------',0

s_bfx_title db  'Buffers, archivos y FCB (BUFFERS, FILES y FCBS):',0
s_bfx_h db      '   Direcci¢n       Tama§o Cantidad   Tipo      Ubicaci¢n',0
s_bfx_d db      '   -----------  --------- --------   --------  -------------------------',0
s_bfx_nov db    'Buffers, archivos y FCB: solo con MS-DOS 3.1 a 3.3.',0
s_bfx_tot db    '  Total ',0
s_bfx_prot db   '   (protegidos: ',0
s_k_buf db      'BUFFERS',0
s_k_fil db      'FILES',0
s_k_fcb db      'FCBS',0
s_o_dos db      'DOS (interno)',0
s_o_up  db      'Memoria superior',0
s_o_conv db     'Memoria convencional',0
s_dbg_title db  'Informe detallado de memoria convencional:',0
s_dbg_h db      '   Direcci¢n             Tama§o programa   Nombre       Tipo',0
s_dbg_d db      '   -----------           ----------------  -----------  ---------',0
s_udbg_title db 'Informe detallado de memoria superior:',0
s_udbg_h db     '   Direcci¢n    Regi¢n   Tama§o programa   Nombre       Tipo',0
s_udbg_d db     '   -----------  ------   ----------------  -----------  ---------',0
s_t_ivt db      'Vector de interrupci¢n',0
s_t_rom db      'Area de comunicaci¢n ROM',0
s_t_dosc db     'Area de comunicaci¢n DOS',0
s_t_sysdata db  'Datos de sistema',0
s_t_sysprog db  'Programa de sistema',0
s_t_sysdrv db   'Controlador del sistema',0
s_t_device db   'DEVICE=',0
s_t_free db     '-- Libre --',0
s_t_prog db     'Programa',0
s_t_trans db    'Parte transitoria',0
s_t_env db      'Entorno',0
s_t_data db     'Datos',0
s_t_gacc db     'Accesorio GEM',0
s_t_gdrv db     'Controlador GEM',0
s_t_grsc db     'Recursos GEM',0
s_t_gdat db     'Datos GEM',0
s_gem   db      'GEM',0
s_gemvdi db     'GEMVDI',0
s_pacc  db      '*.ACC',0
s_psys  db      '*.SYS',0
s_prsc  db      '*.RSC',0
s_gemboot db    ':\GEMBOOT\',0
s_gemsys db     ':\GEMSYS\',0
s_gd_prog db    'GEM: programa ',0
s_gd_psp db     '  PSP ',0
s_gd_dir db     '  carpeta ',0
s_gd_nodir db   '(ninguna)',0
s_gd_sp db      '  ',0
s_gd_win db     '  firma +',0
s_gd_res db     ' -> ',0
s_gd_no db      'no encontrado',0
s_gemhi db      'GEMHI 0.'
s_gd_hi db      'GEM: GEMHI (copia residente) en el bloque ',0

s_map1  db      'Contenido de la memoria de ',0
s_map2  db      ' a FFFFF:',0
s_map_h db      '  Direcci¢n       Tama§o  Contenido',0
s_map_d db      '  -----------  ---------  --------------------------------------',0
s_c_video db    'Memoria de v°deo',0
s_c_rom db      'ROM de adaptador',0
s_c_chain db    'Bloques de memoria superior (ver arriba)',0
s_c_resid db    'C¢digo residente sin bloque de memoria',0
s_c_res1 db     'C¢digo residente: ',0
s_c_res2 db     ' (sin bloque de memoria)',0
s_c_sysrom db   'ROM del sistema',0
s_c_used db     'Ocupada (contenido desconocido)',0
s_c_empty db    'Sin memoria (lee FFh)',0
s_c_zero db     'Sin memoria (lee 00h)',0
s_c_ramff db    'RAM sin usar (fuera de DOS, llena de FFh)',0
s_c_ram0 db     'RAM sin usar (fuera de DOS, a cero)',0
s_c_dosk db     'MS-DOS en memoria superior (HIDOS)',0

s_mod_title db  ' est† usando esta cantidad de memoria:',0
s_mod_h db      '   Direcci¢n    Regi¢n         Total       Tipo',0
s_mod_d db      '   -----------  ------   ----------------  --------',0
s_mod_sep db    '                   ----------------',0
s_mod_tot db    '  Tama§o total:',0
s_mod_res db    '  Adem†s tiene c¢digo residente sin bloque de memoria:',0
s_mod_res2 db   ' bytes',0

help_txt:
        db      'Muestra la cantidad de memoria libre y usada en el sistema.',0
        db      0
        db      'MEM [/CLASSIFY | /DEBUG | /FREE | /MODULE m¢dulo] [/NP]',0
        db      0
        db      '  /CLASSIFY o /C  Clasifica programas por el uso de memoria. Lista el tama§o',0
        db      '                  de programas, proporciona un resumen de memoria en uso y',0
        db      '                  lista el bloque m†s extenso disponible en memoria.',0
        db      '  /DEBUG o /D     Muestra el estado de programas, unidades internas y',0
        db      '                  otra informaci¢n, y el contenido de la memoria por',0
        db      '                  encima de la convencional (v°deo, ROM, c¢digo residente).',0
        db      '  /FREE o /F      Muestra la cantidad de memoria libre que queda en la',0
        db      '                  memoria convencional y superior.',0
        db      '  /MODULE o /M    Muestra una lista en detalle de memoria usada por m¢dulos.',0
        db      '                  Esta opci¢n debe usarse seguida por el nombre de un m¢dulo,',0
        db      '                  y separada de la /M por dos puntos.',0
        db      '  /NP o /P-       Sin pausas. Por omisi¢n se muestra pantalla por',0
        db      '                  pantalla (/PAGE o /P), salvo si la salida va a',0
        db      '                  un archivo (MEM > ARCHIVO).',0
        db      '  /G              Dentro del GEM: muestra quÇ archivos del GEM busca',0
        db      '                  en la memoria y d¢nde los encuentra.',0
        db      0
s_ver   db      'MEM 0.31 para MS-DOS 3.x a 6.x (PC1512).',0
        db      0FFh
s_buit  db      0

; ---------------------------------------------------------------------
        align   2
bss_start:
lptr    equ     bss_start
lbuf    equ     lptr+2                  ; 160
numstr  equ     lbuf+160                ; 16
kstr    equ     numstr+16               ; 32
fq_hi   equ     kstr+32
swbuf   equ     fq_hi+2                 ; 12
modname equ     swbuf+12                ; 10
nbuf    equ     modname+10              ; 10
dlab    equ     nbuf+10                 ; 12
cbuf    equ     dlab+12                 ; 40
mypsp   equ     cbuf+40
dosseg  equ     mypsp+2
firstmcb equ    dosseg+2
nulofs  equ     firstmcb+2
convkb  equ     nulofs+2
convtop equ     convkb+2
dosend  equ     convtop+2
nblk    equ     dosend+2
nreg    equ     nblk+2
nrom    equ     nreg+2
ndev    equ     nrom+2
ngrp    equ     ndev+2
nmod    equ     ngrp+2
tmpown  equ     nmod+2
nextdrv equ     tmpown+2
cfree   equ     nextdrv+2
ufree   equ     cfree+2
utot    equ     ufree+2
bigc    equ     utot+2
bigu    equ     bigc+2
run     equ     bigu+2
runreg  equ     run+2
ems_free equ    runreg+2
ems_tot equ     ems_free+2
r_tot   equ     ems_tot+2
r_free  equ     r_tot+4
kt      equ     r_free+4
kf      equ     kt+4
rs_big  equ     kf+4
rs_free equ     rs_big+2
rs_tot  equ     rs_free+2
dd_lo   equ     rs_tot+2
dd_hi   equ     dd_lo+2
dd_type equ     dd_hi+2
dd_reg  equ     dd_type+2
hname   equ     dd_reg+2                ; 10
dd_dir  equ     hname+10
m_start equ     dd_dir+2
m_cls   equ     m_start+2
m_endlo equ     m_cls+2
m_endhi equ     m_endlo+2
m_total equ     m_endhi+2
cl_ax   equ     m_total+2
cl_end  equ     cl_ax+2
cl_grp  equ     cl_end+2
m_grp   equ     cl_grp+2
blk_seg equ     m_grp+2
blk_own equ     blk_seg+MAXBLK*2
blk_size equ    blk_own+MAXBLK*2
blk_reg equ     blk_size+MAXBLK*2
reg_start equ   blk_reg+MAXBLK
reg_end equ     reg_start+MAXREG*2
rom_seg equ     reg_end+MAXREG*2
rom_len equ     rom_seg+MAXROM*2
dev_seg equ     rom_len+MAXROM*2
dev_off equ     dev_seg+MAXDEV*2
dev_attr equ    dev_off+MAXDEV*2
dev_name equ    dev_attr+MAXDEV*2
dev_drv equ     dev_name+MAXDEV*8
grp_seg equ     dev_drv+MAXDEV
grp_min equ     grp_seg+MAXGRP*2
grp_nv  equ     grp_min+MAXGRP*2
grp_vec equ     grp_nv+MAXGRP
grp_name equ    grp_vec+MAXGRP*MAXGV
grp_beg equ     grp_name+MAXGRP*9
grp_end equ     grp_beg+MAXGRP*2
mod_name equ    grp_end+MAXGRP*2
mod_conv equ    mod_name+MAXMOD*9
mod_up  equ     mod_conv+MAXMOD*2
nmprev  equ     mod_up+MAXMOD*2
newreg  equ     nmprev+2
vidend  equ     newreg+2              ; final de la memïria de v°deo
trans_ix equ    vidend+2              ; bloc transitori de COMMAND + 1
dr_end  equ     trans_ix+2            ; dbg_row: £ltim parÖgraf
lol_o   equ     dr_end+2              ; llista de llistes (desplaáament
lol_s   equ     lol_o+2               ; i segment, per a LES)
bsize   equ     lol_s+2               ; mida d'un buffer (capáalera + sector)
p_o     equ     bsize+2               ; punter actual (desplaáament,
p_s     equ     p_o+2                 ; segment)
n_o     equ     p_s+2                 ; punter segÅent
n_s     equ     n_o+2
r_seg   equ     n_s+2                 ; fila: inici, mida, quantitat
r_ofs   equ     r_seg+2
r_sz    equ     r_ofs+2
r_n     equ     r_sz+2
t_buf   equ     r_n+2                 ; totals
t_fil   equ     t_buf+2
t_fcb   equ     t_fil+2
t_prot  equ     t_fcb+2
guard   equ     t_prot+2
nbufs   equ     guard+2               ; buffers recollits
bufl    equ     nbufs+2               ; adreces lineals (dword)
kseg    equ     bufl+MAXBUF*4         ; nucli del DOS a dalt (HIDOS):
kend    equ     kseg+2                ;   inici i final (0 = no)
iohi    equ     kend+2                ; BIOS (IO) a dalt (HIDOS /B): segment
lowdrv  equ     iohi+2                ; HIDOS: DEVICELOW des d'aqu° fins al
biosseg equ     lowdrv+2              ;   primer bloc (= 1r bloc: cap)
blk_lab equ     biosseg+2             ; segment del BIOS (l'£ltim de la cadena)
nlab    equ     blk_lab+MAXBLK        ; fitxers del GEM: °ndex+1 per bloc
lab_name equ    nlab+2
lab_kind equ    lab_name+MAXLAB*9
ngp     equ     lab_kind+MAXLAB       ; GEM.EXE i GEMVDI.EXE: PSP i carpeta
gp_psp  equ     ngp+2
gdir    equ     gp_psp+4
gdcur   equ     gdir+160
fpath   equ     gdcur+2
gdta    equ     fpath+96
fhdr    equ     gdta+44
frel    equ     fhdr+32
gsig    equ     frel+256
gsoff   equ     gsig+16
gmask   equ     gsoff+2
gimg    equ     gmask+4
graw    equ     gimg+2
gfh     equ     graw+2
gtries  equ     gfh+2
ghit    equ     gtries+2
dosmaj  equ     ghit+2                ; (0.31) versi¢ del DOS
zcont   equ     dosmaj+1              ; ja ha seguit cap als UMB (DOS 5+)
codeseg equ     zcont+1               ; segment del codi del nucli (DOS 5+)
sftsz   equ     codeseg+2             ; mida d'una entrada de FILES/FCBS
d6mid   equ     sftsz+2               ; HIDOS6 /D: final de les dades
bss_end equ     d6mid+2
