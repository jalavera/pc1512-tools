; =====================================================================
;  XPATH.ASM - PATH (i altres variables) a l'entorn principal del
;              COMMAND.COM, per a MS-DOS 3.x-6.x (PC1512).   versi¢ 0.7
;  nasm -f bin XPATH.ASM -o XPATH.COM
;
;  Un programa rep una c•pia de l'entorn: si canvia la seva, el
;  COMMAND.COM no se n'assabenta. XPATH escriu directament a l'entorn
;  del COMMAND.COM principal i tamb‚ al del COMMAND que l'ha executat
;  (si ‚s un altre, p. ex. un COMMAND /C d'un .BAT). Expandeix %VAR%,
;  tamb‚ a la l¡nia d'ordres, i comprova cada cam¡.
; =====================================================================
        cpu     8086
        org     100h

WKSZ    equ     32768+512

start:  cld
        mov     sp,stk_top
        mov     di,bss                  ; variables a zero
        mov     cx,arg-bss
        xor     al,al
        rep     stosb
        mov     byte [verb],3
        mov     byte [q],0
        mov     ah,30h                  ; versi¢ del DOS (AL.AH)
        int     21h
        xchg    al,ah
        mov     [dosv],ax
        mov     ax,2524h                ; error cr¡tic: falla (no pregunta)
        mov     dx,i24
        int     21h
        ; ---- la l¡nia d'ordres i les opcions /Vn /F: /S /? ----
        mov     si,81h
        mov     cl,[80h]
        xor     ch,ch
        mov     di,arg
        rep     movsb
        xor     al,al
        stosb
        call    opts
        ; ---- entorns: el del pare i el principal ----
        mov     ah,52h
        int     21h
        mov     ax,[es:bx-2]
        mov     [arena],ax
        push    cs
        pop     es
        mov     ax,[16h]                ; el COMMAND que ens executa
        mov     [par],ax
        call    findenv
        mov     [penv],ax
        mov     ax,[par]
        call    findmaster
        call    findenv
        mov     [menv],ax
        push    cs
        pop     es
        or      ax,ax
        jz      .ne
        cmp     word [penv],0
        jne     .ok
.ne:    mov     dx,m_noenv
        call    lv3
        call    puts
        jmp     fail
.ok:    mov     word [name],'PA'        ; per defecte, el PATH
        mov     word [name+2],'TH'
        mov     byte [name+4],0
        mov     si,arg
        call    trim
        cmp     byte [o_sv],0
        je      .ns
        cmp     byte [si],0             ; /SAVE: sol
        jne     .hs
        mov     al,[o_s]
        or      al,[o_f]
        jnz     .hs
        jmp     save
.hs:    jmp     help
.ns:    cmp     byte [o_s],0
        je      .np
        jmp     gen
.np:    mov     word [name],'PA'
        mov     word [name+2],'TH'
        mov     byte [name+4],0
        cmp     byte [o_f],0
        je      .nf
        cmp     byte [si],0
        jne     help
        jmp     fromfile
.nf:    lodsb
        or      al,al
        jnz     .n0
        jmp     show
.n0:    cmp     al,';'
        jne     .n1
        cmp     byte [si],0
        jne     .n1
        mov     byte [val],0            ; XPATH ;  -> sense PATH
        mov     byte [act],A_CLR
        jmp     setall
.n1:    cmp     al,'+'
        je      .n2
        cmp     al,'-'
        jne     .n3
.n2:    dec     si
        jmp     multi
.n3:    dec     si                      ; XPATH cam¡;cam¡...
        mov     byte [act],A_SET
        mov     di,lbuf
        call    expand
        mov     si,lbuf
        call    setlist
        jmp     setall

; ---- opcions: les treu de arg (les deixa en blanc) ----
opts:   mov     si,arg                  ; primer, /Vn (per si hi ha un
.v:     lodsb                           ;   error abans)
        or      al,al
        jz      .v1
        cmp     al,'/'
        jne     .v
        mov     al,[si]
        and     al,0DFh
        cmp     al,'V'
        jne     .v
        mov     al,[si+1]
        sub     al,'0'
        cmp     al,3
        ja      .v
        mov     [verb],al
        jmp     .v
.v1:    mov     si,arg
.l:     lodsb
        or      al,al
        jz      .e
        cmp     al,'/'
        jne     .l
        mov     bx,si                   ; BX = despr‚s de la /
        mov     al,[si]
        and     al,0DFh
        cmp     al,'V'                  ; /Vn
        jne     .f
        mov     al,[si+1]
        sub     al,'0'
        cmp     al,3
        ja      .hp
        mov     [verb],al
        add     si,2
        jmp     short .blank
.f:     mov     di,k_load               ; /LOAD: (o /F:)
        call    kw
        je      .ld
        mov     di,k_f
        call    kw
        jne     .sv
.ld:    mov     byte [o_f],1
        mov     di,fname
        call    getfn
        jmp     short .blank
.sv:    mov     di,k_save               ; /SAVE:
        call    kw
        jne     .s
        mov     byte [o_sv],1
        mov     di,sname
        call    getfn
        jmp     short .blank
.s:     cmp     byte [si],'?'           ; /?
        jne     .s0
        mov     byte [o_hx],1
        jmp     help
.s0:    mov     al,[si]                 ; /S
        and     al,0DFh
        cmp     al,'S'
        jne     .hp
        mov     al,[si+1]
        cmp     al,' '
        jbe     .s1
        cmp     al,'/'
        jne     .hp
.s1:    mov     byte [o_s],1
        inc     si
.blank: dec     bx                      ; l'opci¢, en blanc
.b:     cmp     bx,si
        jae     .l
        mov     byte [bx],' '
        inc     bx
        jmp     .b
.hp:    jmp     help
.e:     ret

; SI = despr‚s de la /: hi ha la paraula DI (maj£scules) i ':'? Si hi
; ‚s, SI passa el ':' (ZF=1)
kw:     push    si
.c:     mov     al,[di]
        or      al,al
        jz      .z
        mov     ah,[si]
        cmp     ah,'a'
        jb      .c1
        cmp     ah,'z'
        ja      .c1
        sub     ah,20h
.c1:    cmp     al,ah
        jne     .no
        inc     si
        inc     di
        jmp     .c
.z:     cmp     byte [si],':'
        jne     .no
        inc     si
        add     sp,2
        cmp     al,al                   ; ZF=1
        ret
.no:    pop     si
        or      sp,sp                   ; ZF=0
        ret

; nom de fitxer de SI a DI (fins a espai o /); buit -> ajuda
getfn:  push    di
        mov     cx,78
.l:     mov     al,[si]
        cmp     al,' '
        jbe     .e
        cmp     al,'/'
        je      .e
        mov     [di],al
        inc     si
        inc     di
        loop    .l
.e:     mov     byte [di],0
        pop     ax
        cmp     di,ax
        je      .h
        ret
.h:     jmp     help

; ---- XPATH +cam¡ -cam¡ ...: afegeix i treu, en ordre, i ho escriu
;      tot d'un cop. Un cam¡ no v…lid atura l'ordre (no canvia res).
multi:  mov     byte [act],A_MULTI
        mov     byte [emode],1          ; un cam¡ no v…lid ‚s un error
        push    si
        call    curpath                 ; val = PATH actual, net
        call    cleanval
        pop     si
        mov     word [logp],lbuf        ; el que s'ha fet (per a /V1)
        mov     word [nchg],0
.tk:    call    skipsp
        lodsb
        or      al,al
        jnz     .t0
        jmp     .fi
.t0:    mov     [op],al
        cmp     al,'+'
        je      .t1
        cmp     al,'-'
        je      .t1
        jmp     help
.t1:    mov     di,ltmp                 ; el cam¡, fins a l'espai
.t2:    lodsb
        cmp     al,' '
        jbe     .t3
        mov     [di],al
        inc     di
        cmp     di,ltmp+250
        jb      .t2
.t3:    dec     si
        mov     byte [di],0
        push    si
        mov     si,ltmp
        mov     di,tmp
        call    expand
        mov     si,tmp                  ; sense blancs (ALT+255) als extrems
        call    trim
        mov     di,tmp
        call    strcpy0
        mov     si,tmp
        call    upcase
        call    normtmp
        pop     si
        cmp     byte [tmp],0
        jne     .t4
        jmp     help
.t4:    push    si
        cmp     byte [op],'-'
        je      .del
        mov     byte [act],A_ADD        ; +cam¡
        mov     si,val
        call    inlist
        jc      .a1
        mov     al,'J'                  ; ja hi ‚s
        call    logop
        jmp     .nx
.a1:    call    chkel                   ; ‚s un cam¡ v…lid?
        jnc     .a2
        jmp     fail
.a2:    mov     di,val
        call    strend
        cmp     di,val
        je      .c
        cmp     byte [di-1],';'
        je      .c
        mov     al,';'
        stosb
.c:     mov     si,tmp
        call    strcpy
        mov     al,'A'
        call    logop
        inc     word [nchg]
        jmp     .nx
.del:   mov     byte [act],A_DEL        ; -cam¡
        call    delel
        cmp     byte [rem],0
        jne     .d1
        mov     al,'N'                  ; no hi era
        call    logop
        jmp     .nx
.d1:    mov     al,'T'
        call    logop
        inc     word [nchg]
.nx:    pop     si
        jmp     .tk
.fi:    mov     byte [act],A_MULTI
        mov     di,[logp]
        mov     byte [di],0
        cmp     word [nchg],0           ; res a fer: ho diu i ERRORLEVEL 2
        jne     .w
        call    actinfo
        mov     al,2
        jmp     quit
.w:     jmp     setall

; apunta al registre (lbuf) l'operaci¢ AL ('A'/'T') amb el cam¡ de tmp
logop:  mov     di,[logp]
        cmp     di,lbuf+LBSZ-80
        jae     .r
        stosb
        mov     si,tmp
        call    strcpy
        mov     [logp],di
.r:     ret

; treu tmp de val; [rem] = 1 si hi era
delel:  mov     byte [rem],0
        mov     si,val                  ; val -> tmp2 sense l'element
        mov     di,tmp2
.l:     cmp     byte [si],0
        je      .e
        mov     bx,si                   ; un element: de SI fins a ; o 0
.l1:    lodsb
        or      al,al
        jz      .l2
        cmp     al,';'
        jne     .l1
.l2:    dec     si                      ; SI = ; o 0
        push    si
        call    elemeq                  ; [BX..SI) == tmp?
        pop     si
        jne     .nq
        mov     byte [rem],1
        jmp     short .sk
.nq:    cmp     si,bx                   ; (elements buits fora)
        je      .sk
        cmp     di,tmp2
        je      .cp
        mov     al,';'
        stosb
.cp:    push    si
        mov     cx,si
        sub     cx,bx
        mov     si,bx
        rep     movsb
        pop     si
.sk:    cmp     byte [si],0
        je      .e
        inc     si
        jmp     .l
.e:     xor     al,al
        stosb
        cmp     byte [rem],0
        je      .r
        mov     si,tmp2
        mov     di,val
        call    strcpy
.r:     ret

; ---- XPATH /LOAD:fitxer (o /F:): el PATH amb els camins d'un fitxer de text ----
; Un cam¡ per l¡nia (o diversos separats per ;). Les l¡nies buides i
; les que comencen per # no compten. %VAR% s'expandeix.
fromfile:
        mov     byte [act],A_LOAD
        mov     ax,3D00h
        mov     dx,fname
        int     21h
        jnc     .o
        mov     dx,m_nofile
        call    lv3
        call    puts
        mov     si,fname
        call    putz
        mov     dx,m_crlf
        call    puts
        jmp     fail
.o:     mov     bx,ax
        mov     ah,3Fh
        mov     cx,FBSZ-1
        mov     dx,fbuf
        int     21h
        pushf
        push    ax
        mov     ah,3Eh
        int     21h
        pop     cx
        popf
        jnc     .r
        xor     cx,cx
.r:     mov     di,cx
        mov     byte [fbuf+di],0
        mov     si,fbuf                 ; l¡nia per l¡nia -> lbuf (amb ;)
        mov     di,lbuf
.ln:    cmp     byte [si],0
        je      .fi
        call    skipsp
        cmp     byte [si],'#'
        je      .skip
        mov     bx,ltmp                 ; la l¡nia, a ltmp
.c:     lodsb
        cmp     al,0Dh
        je      .ce
        cmp     al,0Ah
        je      .ce
        cmp     al,1Ah
        je      .ce0
        or      al,al
        jz      .ce0
        mov     [bx],al
        inc     bx
        cmp     bx,ltmp+250
        jb      .c
.ce0:   dec     si
.ce:    mov     byte [bx],0
        push    si
        mov     si,ltmp                 ; expandida, al final de lbuf
        call    expand
        mov     al,';'
        stosb
        pop     si
        cmp     di,lbuf+LBSZ-300
        jb      .ln
        jmp     short .fi
.skip:  lodsb
        or      al,al
        jz      .sk0
        cmp     al,0Ah
        jne     .skip
        jmp     .ln
.sk0:   dec     si
        jmp     .ln
.fi:    mov     byte [di],0
        mov     si,lbuf
        call    setlist
        jmp     setall

; ---- SI = llista ja expandida -> val: cada cam¡ comprovat, sense ----
;      repetits ni buits; [ncnt] = quants n'hi ha
setlist:
        mov     word [ncnt],0
        mov     byte [nv],0
.l:     cmp     byte [si],0
        je      .e
        mov     di,tmp                  ; un element -> tmp
        mov     cx,200
.c:     lodsb
        or      al,al
        jz      .ce0
        cmp     al,';'
        je      .ce
        stosb
        loop    .c
.cx:    lodsb                           ; (massa llarg: es talla aqu¡)
        or      al,al
        jz      .ce0
        cmp     al,';'
        jne     .cx
        jmp     short .ce
.ce0:   dec     si
.ce:    xor     al,al
        stosb
        push    si
        mov     si,tmp
        call    trim
        mov     di,tmp                  ; (trim deixa SI al principi)
        call    strcpy0
        mov     si,tmp
        call    upcase
        call    nopfx                   ; sense "PATH=" (de PATH > fitxer)
        call    normtmp
        cmp     byte [tmp],0
        je      .n                      ; buit: res
        mov     si,nv                   ; repetit?
        call    inlist
        jc      .nd
        mov     dx,m_dup
        call    elmsg
        jmp     short .n
.nd:    call    chkel
        jc      .n
        mov     di,nv
        call    strend
        cmp     di,nv
        je      .ap
        mov     al,';'
        stosb
.ap:    mov     si,tmp
        call    strcpy
        inc     word [ncnt]
.n:     pop     si
        jmp     .l
.e:     mov     si,nv
        mov     di,val
        call    strcpy
        cmp     byte [val],0
        jne     .r
        mov     dx,m_empty
        call    lv2
        call    puts
.r:     ret

; ---- tmp comen‡a per "PATH=" (o "PATH =")? El treu: aix¡ es pot
;      carregar el que escriu PATH > FITXER.TXT
nopfx:  cmp     word [tmp],'PA'
        jne     .r
        cmp     word [tmp+2],'TH'
        jne     .r
        mov     si,tmp+4
        call    skipsp
        cmp     byte [si],'='
        jne     .r
        inc     si
        call    skipsp
        mov     di,tmp
        call    strcpy
.r:     ret

; ---- XPATH /SAVE:fitxer: el PATH a un fitxer, un cam¡ per l¡nia ----
save:   mov     byte [act],A_SAVE
        call    curpath
        mov     ah,3Ch
        xor     cx,cx
        mov     dx,sname
        int     21h
        jnc     .o
.wf:    mov     dx,m_nowr
        call    lv3
        call    puts
        mov     si,sname
        call    putz
        mov     dx,m_crlf
        call    puts
        jmp     fail
.o:     mov     bx,ax
        mov     si,val                  ; val -> tmp2: ; -> CR LF
        mov     di,tmp2
        mov     word [ncnt],0
.l:     lodsb
        or      al,al
        jz      .e
        cmp     al,';'
        je      .sep
        stosb
        cmp     byte [si],0             ; final d'un cam¡?
        je      .nl
        cmp     byte [si],';'
        jne     .l
.nl:    inc     word [ncnt]
        mov     ax,0A0Dh
        stosw
        jmp     .l
.sep:   jmp     .l
.e:     mov     cx,di
        sub     cx,tmp2
        mov     dx,tmp2
        mov     ah,40h
        int     21h
        pushf
        mov     ah,3Eh
        int     21h
        popf
        jc      .wf
.ok:    cmp     word [ncnt],0
        jne     .i
        mov     dx,m_svempty
        call    lv2
        call    puts
.i:     call    lv1
        mov     dx,m_isv1
        call    puts
        mov     ax,[ncnt]
        call    putdec
        mov     dx,m_isv2
        call    puts
        mov     si,sname
        call    putz
        mov     dx,m_dot
        call    puts
        xor     al,al
        jmp     quit

; ---- tmp: ‚s un cam¡ acceptable? Avisa del que no va b‚. CF=1: no
;      es pot posar (car…cters no v…lids o massa llarg)
chkel:  mov     si,tmp
        xor     cx,cx
.c:     lodsb
        or      al,al
        jz      .ce
        inc     cx
        cmp     al,':'
        jne     .c1
        cmp     cx,2                    ; ':' nom‚s com a "X:"
        jne     .bad
        jmp     .c
.c1:    cmp     al,80h
        jae     .c
        cmp     al,' '
        jbe     .bad
        push    di
        push    cx
        mov     di,badch
        mov     cx,NBAD
        push    es
        push    cs
        pop     es
        repne   scasb
        pop     es
        pop     cx
        pop     di
        je      .bad
        jmp     .c
.bad:   mov     dx,m_bad
        call    elerr
        stc
        ret
.ce:    cmp     cx,63
        jbe     .l
        mov     dx,m_toolong
        call    elerr
        stc
        ret
.l:     cmp     byte [tmp+1],':'        ; complet: "X:\..."
        jne     .inc
        cmp     byte [tmp+2],'\'
        je      .ex
.inc:   mov     dx,m_incomp
        call    elmsg
.ex:    call    direx                   ; existeix?
        jnc     .ok
        mov     dx,m_noex
        cmp     al,2
        jne     .ex1
        mov     dx,m_nodrv
.ex1:   call    elmsg
.ok:    clc
        ret

; tmp existeix com a directori? CF=1 si no (AL=1: no hi ‚s, 2: unitat
; no v…lida). Hi va amb CHDIR i torna a deixar el directori d'abans.
direx:  push    si
        push    dx
        xor     dl,dl                   ; la unitat
        cmp     byte [tmp+1],':'
        jne     .d
        mov     dl,[tmp]
        sub     dl,'A'-1
        mov     al,dl
        add     al,'A'-1
        jmp     short .g
.d:     mov     ah,19h
        int     21h
        add     al,'A'
.g:     mov     [sdir],al
        mov     word [sdir+1],':\'
        mov     si,sdir+3
        mov     ah,47h
        int     21h
        mov     al,2
        jc      .no
        mov     ah,3Bh
        mov     dx,tmp
        int     21h
        mov     al,1
        jc      .no
        mov     ah,3Bh                  ; torna on era
        mov     dx,sdir
        int     21h
        clc
        jmp     short .r
.no:    stc
.r:     pop     dx
        pop     si
        ret

; ---- XPATH /S [NOM=valor] ----
gen:    cmp     byte [si],0
        jne     .g0
        jmp     list
.g0:    mov     di,name                 ; el nom, en maj£scules
        mov     cx,63
.n:     lodsb
        or      al,al
        jz      .hp
        cmp     al,'='
        je      .v
        cmp     al,'a'
        jb      .s
        cmp     al,'z'
        ja      .s
        sub     al,20h
.s:     stosb
        loop    .n
.hp:    jmp     help
.v:     cmp     di,name
        je      .hp
        cmp     byte [di-1],' '         ; sense espais abans de '='
        jne     .v1
        dec     di
        jmp     .v
.v1:    xor     al,al
        stosb
.v2:    cmp     byte [si],' '           ; ni al principi del valor
        jne     .v3
        inc     si
        jmp     .v2
.v3:    mov     di,val
        call    expand
        mov     byte [act],A_VAR
        jmp     setall

; ---- escriu la variable [name] = [val] als dos entorns ----
setall: mov     ax,[menv]
        call    setvar
        mov     ax,[nsz]
        mov     [msz],ax
        mov     ax,[bsz]
        mov     [mbs],ax
        jc      .fm
        call    actinfo                 ; quŠ s'ha fet
        mov     ax,[penv]
        cmp     ax,[menv]
        je      .ok
        call    setvar
        jnc     .ok
        mov     dx,m_nopar
        call    lv2
        call    puts
.ok:    cmp     word [name],'PA'        ; el PATH: el mostra; massa llarg?
        jne     .s0
        cmp     word [name+2],'TH'
        jne     .s0
        cmp     byte [name+4],0
        jne     .s0
        call    lv3
        call    showv
        call    plimit
.s0:    mov     ax,[mbs]                ; queda poc espai?
        sub     ax,[msz]
        cmp     ax,64
        jae     .ok1
        push    ax
        call    lv2
        mov     dx,m_low1
        call    puts
        pop     ax
        call    putdec
        mov     dx,m_low2
        call    puts
        mov     ax,[mbs]
        call    putdec
        mov     dx,m_low3
        call    puts
        call    suggest
.ok1:   xor     al,al
        jmp     quit
.fm:    call    lv3                     ; no hi cap: quant cal i quant n'hi ha
        mov     dx,m_full1
        call    puts
        mov     ax,[msz]
        call    putdec
        mov     dx,m_full2
        call    puts
        mov     ax,[mbs]
        call    putdec
        mov     dx,m_full3
        call    puts
        call    suggest
        mov     dx,m_full4
        call    puts
        jmp     fail

; proposa /E: per a [msz] bytes amb marge (m£ltiple de 128, 256-32768)
suggest:
        mov     dx,m_sug1
        call    puts
        mov     ax,[msz]
        add     ax,128+127
        jc      .mx
        and     ax,0FF80h
        cmp     ax,256
        jae     .c
        mov     ax,256
.c:     cmp     ax,32768
        jbe     .p
.mx:    mov     ax,32768
.p:     push    ax
        call    putdec
        mov     dx,m_sug2
        call    puts
        pop     ax
        call    putdec
        mov     dx,m_crlf
        call    puts
        ret

; el PATH nou ([val]) passa de 122 car…cters? Ho avisa (ja s'ha posat)
plimit: push    di
        mov     di,val
        call    strend
        mov     ax,di
        sub     ax,val
        pop     di
        cmp     ax,122
        jbe     .r
        push    ax
        call    lv2
        mov     dx,m_long1
        call    puts
        pop     ax
        call    putdec
        mov     dx,m_long2
        call    puts
.r:     ret

; ---- XPATH: mostra el PATH (sempre) ----
show:   call    curpath
        mov     byte [q],0
        call    showv
        xor     al,al
        jmp     quit
showv:  cmp     byte [val],0
        jne     .s
        mov     dx,m_nopath
        jmp     puts
.s:     mov     dx,s_path
        call    puts
        mov     si,val
        call    putz
        mov     dx,m_crlf
        jmp     puts

; ---- XPATH /S: llista l'entorn principal (sempre) ----
list:   push    ds
        mov     ds,[menv]
        xor     si,si
.l:     cmp     byte [si],0
        je      .e
        call    putz
        push    ds
        push    cs
        pop     ds
        mov     dx,m_crlf
        call    puts
        pop     ds
        jmp     .l
.e:     pop     ds
        xor     al,al
        jmp     quit

; ajuda: amb /? sempre; per un error de sintaxi, no amb /V0
help:   cmp     byte [o_hx],0
        jne     .h
        cmp     byte [verb],3           ; error de sintaxi: /V3 l'ajuda,
        je      .h                      ;   /V1 i /V2 una l¡nia, /V0 res
        call    lv1
        mov     dx,m_syn
        call    puts
        jmp     short .r
.h:     mov     byte [q],0
        mov     dx,m_help
        call    puts
.r:     mov     al,1
        jmp     quit
; error: "XPATH: no s'ha pogut <acci¢>." (des de /V1) i ERRORLEVEL 1
fail:   call    lv1
        mov     dx,m_f0
        call    puts
        call    actxt
        mov     dx,m_dot
        call    puts
        mov     al,1
quit:   mov     ah,4Ch
        int     21h

; l'acci¢ de [act], en infinitiu: "afegir C:\X al PATH"...
actxt:  mov     bl,[act]
        xor     bh,bh
        shl     bx,1
        mov     bx,[acttab+bx]
        mov     dx,[bx]
        call    puts
        mov     si,[bx+2]
        or      si,si
        jz      .s
        call    putz
.s:     mov     dx,[bx+4]
        jmp     puts

; quŠ s'ha fet (des de /V1), quan ja ‚s a l'entorn
actinfo:
        call    lv1
        mov     al,[act]
        cmp     al,A_MULTI
        jne     .m9
        mov     si,lbuf                 ; el registre: A=afegit, T=tret
.m1:    lodsb
        or      al,al
        jz      .r
        cmp     al,'J'
        je      .mj
        cmp     al,'N'
        je      .mj
        mov     dx,m_iadd
        cmp     al,'A'
        je      .m2
        mov     dx,m_idel
.m2:    call    puts
        call    putz
        mov     dx,m_dot
        call    puts
        jmp     .m1
.mj:    mov     dx,m_ja2                ; "XPATH: <cam¡> ja ‚s / no ‚s al
        cmp     al,'J'                  ;   PATH: no canvio res."
        je      .m3
        mov     dx,m_no2
.m3:    push    dx
        mov     dx,m_x
        call    puts
        call    putz
        pop     dx
        call    puts
        jmp     .m1
.m9:
        cmp     al,A_ADD
        jne     .d
        mov     dx,m_iadd
        jmp     elinf
.d:     cmp     al,A_DEL
        jne     .c
        mov     dx,m_idel
        jmp     elinf
.c:     cmp     al,A_CLR
        jne     .s
        mov     dx,m_iclr
        jmp     puts
.s:     cmp     al,A_SET
        jne     .l
        mov     dx,m_iset1
        call    puts
        mov     ax,[ncnt]
        call    putdec
        mov     dx,m_iset2
        jmp     puts
.l:     cmp     al,A_LOAD
        jne     .v
        mov     dx,m_ifile
        call    puts
        mov     ax,[ncnt]
        call    putdec
        mov     dx,m_ifile2
        call    puts
        mov     si,fname
        call    putz
        mov     dx,m_ifile3
        jmp     puts
.v:     cmp     al,A_VAR
        jne     .r
        mov     si,name
        call    putz
        mov     dx,m_iset
        cmp     byte [val],0
        jne     .v4
        mov     dx,m_iunset
.v4:    call    puts
        cmp     byte [val],0
        je      .r
        mov     si,val
        call    putz
        mov     dx,m_crlf
        jmp     puts
.r:     ret
elinf:  call    puts
        mov     si,tmp
        call    putz
        mov     dx,m_dot
        jmp     puts

; error cr¡tic (disquetera buida...): falla, sense preguntar
i24:    mov     al,3
        iret

; ---- missatges segons /Vn: lv1 errors, lv2 avisos, lv3 informaci¢ ----
lv1:    push    ax
        mov     al,1
        jmp     short lvx
lv2:    push    ax
        mov     al,2
        jmp     short lvx
lv3:    push    ax
        mov     al,3
lvx:    cmp     [verb],al
        mov     byte [q],0
        jae     .r
        mov     byte [q],1
.r:     pop     ax
        ret
; "XPATH: <tmp>" + DX: resultat (/V1), error explicat (/V3 amb +cam¡,
; si no av¡s) o av¡s (/V2)
elres:  push    dx
        call    lv1
        jmp     short elm
elerr:  push    dx
        cmp     byte [emode],0
        je      .w
        call    lv3
        jmp     short elm
.w:     call    lv2
        jmp     short elm
elmsg:  push    dx
        call    lv2
elm:    mov     dx,m_x
        call    puts
        mov     si,tmp
        call    putz
        pop     dx
        jmp     puts


; =====================================================================
;  Rutines
; =====================================================================
skipsp: cmp     byte [si],' '
        je      .s
        cmp     byte [si],9
        jne     .r
.s:     inc     si
        jmp     skipsp
.r:     ret
; SI -> DI fins al 0 (sense importar si se solapen cap endavant)
strcpy0:
        cmp     si,di
        je      .r
        jmp     strcpy
.r:     ret

; (hi ha 0 o la c•pia que li ha donat l'EXEC): ‚s un bloc seu a part,
; amb COMSPEC=. Es tria el bloc seu amb COMSPEC= que no ‚s el de
; PSP:2Ch; si no n'hi ha, el de PSP:2Ch; si cap no en t‚, el primer
; bloc seu (i CF=1).
findenv:
        push    bx
        push    cx
        push    dx
        push    si
        push    es
        mov     dx,ax
        mov     es,ax
        mov     ax,[es:2Ch]
        mov     [f2c],ax
        cmp     word [dosv],031Eh       ; DOS 3.30 o posterior: PSP:2Ch,
        jb      .old                    ;   si ‚s un bloc seu
        or      ax,ax
        jz      .old
        dec     ax
        mov     es,ax
        inc     ax
        cmp     [es:1],dx
        jne     .old
        clc
        jmp     .r
.old:
        mov     word [fbk],0
        mov     word [c2c],0
        mov     ax,[arena]
        mov     cx,4000
.l:     mov     es,ax
        cmp     [es:1],dx               ; ‚s del COMMAND?
        jne     .n
        mov     bx,ax
        inc     bx
        cmp     bx,dx                   ; (no el del programa)
        je      .n
        cmp     word [fbk],0
        jne     .c
        mov     [fbk],bx
.c:     call    hascs
        jc      .n
        cmp     bx,[f2c]
        jne     .si                     ; el bo
        mov     [c2c],bx
.n:     cmp     byte [es:0],'Z'
        je      .f
        add     ax,[es:3]
        inc     ax
        loop    .l
.f:     mov     ax,[c2c]
        or      ax,ax
        jnz     .ok
        mov     ax,[fbk]
        stc
        jmp     short .r
.si:    mov     ax,bx
.ok:    clc
.r:     pop     es
        pop     si
        pop     dx
        pop     cx
        pop     bx
        ret

; BX = segment: hi ha una variable COMSPEC= ? (CF=0 si s¡)
hascs:  push    ds
        push    si
        push    ax
        mov     ds,bx
        xor     si,si
.e:     cmp     byte [si],0
        je      .no
        cmp     word [si],'CO'
        jne     .e1
        cmp     word [si+2],'MS'
        jne     .e1
        cmp     word [si+4],'PE'
        jne     .e1
        cmp     word [si+6],'C='
        je      .si
.e1:    lodsb
        or      al,al
        jz      .e
        cmp     si,7FF0h
        jb      .e1
.no:    stc
        jmp     short .r
.si:    clc
.r:     pop     ax
        pop     si
        pop     ds
        ret

; AX = PSP del pare -> AX = PSP del COMMAND.COM principal. s el que
; t‚ l'INT 2Eh (un COMMAND /C no la canvia). Si all… no hi ha cap
; COMMAND.COM (programa amb un entorn amb COMSPEC=), es puja pels
; pares (PSP:16h) fins al que ‚s el seu propi pare.
findmaster:
        push    bx
        push    cx
        push    dx
        push    es
        push    ax
        mov     ax,352Eh
        int     21h
        mov     dx,es
        mov     cl,4
        shr     bx,cl
        add     dx,bx
        call    progof                  ; BX = PSP del programa (0 = cap)
        or      bx,bx
        jz      .p
        mov     ax,bx
        call    findenv
        jc      .p
        pop     ax
        mov     ax,bx
        jmp     short .r
.p:     pop     ax
        mov     cx,16
.l:     mov     es,ax
        mov     bx,[es:16h]
        or      bx,bx
        jz      .r
        cmp     bx,ax
        je      .r
        mov     ax,bx
        loop    .l
.r:     pop     es
        pop     dx
        pop     cx
        pop     bx
        ret

; DX = par…graf -> BX = PSP del bloc de programa que el cont‚ (0 = cap)
progof: push    ax
        push    cx
        push    es
        xor     bx,bx
        mov     ax,[arena]
        mov     cx,4000
.l:     mov     es,ax
        inc     ax                      ; AX = dades del bloc
        cmp     dx,ax
        jb      .n
        push    ax
        add     ax,[es:3]
        cmp     dx,ax
        pop     ax
        jae     .n
        cmp     [es:1],ax               ; ‚s un programa (PSP = bloc)?
        jne     .r
        mov     bx,ax
        jmp     short .r
.n:     cmp     byte [es:0],'Z'
        je      .r
        add     ax,[es:3]
        loop    .l
.r:     pop     es
        pop     cx
        pop     ax
        ret

; SI: salta els espais del principi i treu els del final
trim:   lodsb
        call    isblank
        je      trim
        dec     si
        mov     di,si
        push    si
.l:     lodsb
        or      al,al
        jz      .z
        cmp     al,13
        je      .z
        call    isblank
        je      .l
        mov     di,si
        jmp     .l
.z:     mov     byte [di],0
        pop     si
        ret

; AL ‚s un blanc (espai, tabulador o FF, el de l'ALT+255)? ZF=1
isblank:
        cmp     al,' '
        je      .r
        cmp     al,9
        je      .r
        cmp     al,0FFh
.r:     ret

; val (el PATH d'ara): cada cam¡ sense blancs al principi ni al final i
; sense camins buits. Si ha canviat alguna cosa, ho avisa (/V2).
cleanval:
        mov     si,val
        mov     di,tmp2
.l:     cmp     byte [si],0
        je      .e
.b:     lodsb                           ; blancs del principi
        call    isblank
        je      .b
        dec     si
        mov     bx,di                   ; inici d'aquest cam¡ a tmp2
        mov     dx,di                   ; final (despr‚s de l'£ltim no blanc)
.c:     lodsb
        or      al,al
        jz      .ce
        cmp     al,';'
        je      .ce
        stosb
        call    isblank
        je      .c
        mov     dx,di
        jmp     .c
.ce:    dec     si
        mov     di,dx                   ; sense els blancs del final
        cmp     di,bx
        je      .nx                     ; buit: fora
        mov     al,';'
        stosb
.nx:    cmp     byte [si],0
        je      .e
        inc     si
        jmp     .l
.e:     cmp     di,tmp2                 ; treu el ; final
        je      .z
        dec     di
.z:     mov     byte [di],0
        mov     si,val                  ; ha canviat?
        mov     di,tmp2
.k:     mov     al,[si]
        cmp     al,[di]
        jne     .ch
        inc     si
        inc     di
        or      al,al
        jnz     .k
        ret
.ch:    mov     si,tmp2
        mov     di,val
        call    strcpy
        mov     dx,m_clean
        call    lv2
        jmp     puts

upcase: lodsb
        or      al,al
        jz      .r
        cmp     al,'a'
        jb      upcase
        cmp     al,'z'
        ja      upcase
        sub     byte [si-1],20h
        jmp     upcase
.r:     ret

strend: cmp     byte [di],0
        je      .r
        inc     di
        jmp     strend
.r:     ret

strcpy: lodsb
        stosb
        or      al,al
        jnz     strcpy
        ret

; val = valor de [name] a l'entorn del pare (buit si no hi ‚s)
curpath:
        mov     si,name
        mov     di,val
        call    getvar
        ret

; SI = nom (acaba en 0 o '%'), DI = dest¡: el valor (de l'entorn del
; pare), acabat en 0. DI acaba apuntant al 0.
getvar: push    si
        mov     es,[penv]
        xor     bx,bx
.e:     cmp     byte [es:bx],0
        je      .no
        pop     si
        push    si
.c:     lodsb
        cmp     al,'%'
        jne     .c1
        xor     al,al
.c1:    mov     ah,[es:bx]
        inc     bx
        or      al,al
        jz      .eq
        cmp     al,'a'
        jb      .c2
        cmp     al,'z'
        ja      .c2
        sub     al,20h
.c2:    cmp     al,ah
        je      .c
.nx:    or      ah,ah                   ; l'entrada ja s'ha acabat?
        jz      .e
.nx0:   cmp     byte [es:bx],0          ; a la segent
        je      .nx1
        inc     bx
        jmp     .nx0
.nx1:   inc     bx
        jmp     .e
.eq:    cmp     ah,'='
        jne     .nx
.cp:    mov     al,[es:bx]
        inc     bx
        mov     [di],al
        or      al,al
        jz      .r
        inc     di
        jmp     .cp
.no:    mov     byte [di],0
.r:     pop     si
        push    cs
        pop     es
        ret

; SI -> DI amb %VAR% expandit (%% = %). DI acaba al 0.
expand: push    cs
        pop     es
.l:     lodsb
        cmp     al,'%'
        je      .p
        stosb
        or      al,al
        jnz     .l
        dec     di
        ret
.p:     cmp     byte [si],'%'
        jne     .v
        inc     si
        stosb
        jmp     .l
.v:     mov     bx,si                   ; hi ha un % de tancament?
.f:     mov     al,[bx]
        inc     bx
        or      al,al
        jz      .lit
        cmp     al,'%'
        jne     .f
        push    bx
        call    getvar                  ; SI = nom fins al %
        pop     si
        jmp     .l
.lit:   mov     al,'%'
        stosb
        jmp     .l

; ‚s tmp a la llista de val? CF=0 si s¡
inlist:
.l:     cmp     byte [si],0
        je      .no
        mov     bx,si
.l1:    lodsb
        or      al,al
        jz      .l2
        cmp     al,';'
        jne     .l1
.l2:    dec     si
        call    elemeq
        je      .si
        cmp     byte [si],0
        je      .no
        inc     si
        jmp     .l
.si:    clc
        ret
.no:    stc
        ret

; [BX..SI) == tmp? (tmp en maj£scules; un \ final no compta) ZF=1
elemeq: push    di
        push    si
        mov     cx,si
        sub     cx,bx
        cmp     cx,2
        jb      .go
        cmp     byte [si-1],'\'
        jne     .go
        cmp     byte [si-2],':'
        je      .go
        dec     cx
.go:    mov     si,bx
        mov     di,tmp
.c:     jcxz    .f
        lodsb
        cmp     al,'a'
        jb      .c1
        cmp     al,'z'
        ja      .c1
        sub     al,20h
.c1:    cmp     al,[di]
        jne     .r
        inc     di
        dec     cx
        jmp     .c
.f:     cmp     byte [di],0
.r:     pop     si
        pop     di
        ret

; tmp: treu el \ final (no el de "C:\")
normtmp:
        mov     di,tmp
        call    strend
        mov     cx,di
        sub     cx,tmp
        cmp     cx,2
        jb      .r
        cmp     byte [di-1],'\'
        jne     .r
        cmp     byte [di-2],':'
        je      .r
        mov     byte [di-1],0
.r:     ret

; AX = segment de l'entorn: hi posa [name]=[val] (o el treu si val ‚s
; buit). CF=1 si no hi cap.
setvar: mov     [eseg],ax
        push    ds
        mov     ds,ax
        xor     si,si
        mov     di,wk
.e:     cmp     byte [si],0
        je      .fi
        push    si                      ; ‚s [name]?
        mov     bx,name
.c:     mov     al,[si]
        inc     si
        mov     ah,[cs:bx]
        inc     bx
        or      ah,ah
        jz      .z
        cmp     al,ah
        je      .c
        jmp     short .cp
.z:     cmp     al,'='
        jne     .cp
        pop     si                      ; s¡: se salta
.sk:    lodsb
        or      al,al
        jnz     .sk
        jmp     .e
.cp:    pop     si                      ; no: es copia
.cp1:   lodsb
        stosb
        or      al,al
        jnz     .cp1
        jmp     .e
.fi:    inc     si                      ; SI = despr‚s del 0 final
        mov     [tail],si
        xor     cx,cx                   ; cua: 0001h + nom del programa
        cmp     word [si],1
        jne     .nt
        mov     bx,si
        add     bx,2
.t:     inc     cx
        cmp     byte [bx],0
        je      .t2
        inc     bx
        cmp     cx,200
        jb      .t
        xor     cx,cx
        jmp     short .nt
.t2:    add     cx,2
.nt:    pop     ds
        mov     [tlen],cx
        cmp     byte [val],0            ; NOM=valor al final
        je      .nv
        mov     si,name
        call    strcpy
        mov     byte [di-1],'='
        mov     si,val
        call    strcpy
.nv:    xor     al,al
        stosb
        cmp     di,wk+1                 ; entorn buit: dos zeros
        jne     .nv1
        stosb
.nv1:   push    ds                      ; i la cua
        mov     ds,[eseg]
        mov     si,[cs:tail]
        mov     cx,[cs:tlen]
        rep     movsb
        pop     ds
        mov     cx,di
        sub     cx,wk                   ; CX = mida nova
        mov     [nsz],cx
        mov     ax,[eseg]
        dec     ax
        mov     es,ax
        mov     ax,[es:3]
        push    ax
        push    cx
        mov     cl,4
        shl     ax,cl
        mov     [bsz],ax                ; (mida del bloc en bytes)
        pop     cx
        pop     ax
        mov     dx,cx                   ; cap?
        add     dx,15
        push    cx
        mov     cl,4
        shr     dx,cl
        pop     cx
        cmp     dx,ax
        jbe     .w
        mov     bx,dx                   ; prova d'allargar el bloc
        mov     es,[eseg]
        mov     ah,4Ah
        push    cx
        int     21h
        pop     cx
        jc      .no
        push    cx                      ; s'ha allargat
        mov     cl,4
        shl     bx,cl
        mov     [bsz],bx
        pop     cx
.w:     mov     es,[eseg]
        xor     di,di
        mov     si,wk
        rep     movsb
        push    cs
        pop     es
        clc
        ret
.no:    push    cs
        pop     es
        stc
        ret


puts:   cmp     byte [q],0
        jne     .r
        mov     ah,9
        int     21h
.r:     ret
; DS:SI, fins al 0 (SI acaba despr‚s del 0)
putz:   lodsb
        or      al,al
        jz      .r
        cmp     byte [cs:q],0
        jne     putz
        mov     dl,al
        mov     ah,2
        int     21h
        jmp     putz
.r:     ret
; AX en decimal
putdec: cmp     byte [q],0
        jne     .x
        push    ax
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
        mov     ah,2
        int     21h
        loop    .p
        pop     dx
        pop     cx
        pop     bx
        pop     ax
.x:     ret

k_load  db      'LOAD',0
k_f     db      'F',0
k_save  db      'SAVE',0
m_nowr   db     'XPATH: no puc escriure $'
m_svempty db    'XPATH: no hi ha PATH: el fitxer queda buit.',13,10,'$'
m_isv1   db     'Desats $'
m_isv2   db     ' camins a $'
badch   db      '"*+,/;<=>?[]|'
NBAD    equ     $-badch
s_path   db     'PATH=$'
m_crlf   db     13,10,'$'
m_dot    db     '.',13,10,'$'
m_x      db     'XPATH: $'
m_noenv  db     "XPATH: no trobo l'entorn del COMMAND.COM.",13,10,'$'
m_nopath db     'No hi ha PATH.',13,10,'$'
m_ja2    db     ' ja ‚s al PATH: no canvio res.',13,10,'$'
m_no2    db     ' no ‚s al PATH: no canvio res.',13,10,'$'
m_dup    db     ' est… repetit: el poso nom‚s un cop.',13,10,'$'
m_bad    db     ' no ‚s un cam¡ v…lid: no el poso.',13,10,'$'
m_toolong db    ' ‚s massa llarg (m‚s de 63 car…cters): no el poso.',13,10,'$'
m_incomp db     " ‚s incomplet (sense unitat o sense \ al principi):",13,10
         db     '       dependr… de la unitat i el directori actuals.',13,10,'$'
m_noex   db     " no existeix (ara). El poso igualment.",13,10,'$'
m_nodrv  db     ": la unitat no existeix o no est… a punt. El poso igualment.",13,10,'$'
m_empty  db     'XPATH: no queda cap cam¡: trec el PATH.',13,10,'$'
m_nofile db     'XPATH: no puc obrir $'
m_iadd   db     'Afegit al PATH: $'
m_idel   db     'Tret del PATH: $'
m_ifile  db     'Llegits $'
m_ifile2 db     ' camins de $'
m_ifile3 db     '.',13,10,'$'
m_iset   db     ' = $'
m_iclr   db     'PATH tret.',13,10,'$'
m_iset1  db     'PATH posat: $'
m_iset2  db     ' camins.',13,10,'$'
m_clean  db     "XPATH: he tret espais o car",85h,"cters invisibles (ALT+255) i camins",13,10
         db     "buits del PATH d'abans.",13,10,'$'
m_f0     db     "XPATH: no s'ha pogut $"
m_syn    db     "XPATH: no s'ha pogut fer: l'ordre no ‚s v…lida (XPATH /? per a",13,10
         db     "l'ajuda).",13,10,'$'
m_none   db     '$'
fa_any   db     'fer el canvi$'
fa_add   db     'afegir $'
fa_add2  db     ' al PATH$'
fa_del   db     'treure $'
fa_del2  db     ' del PATH$'
fa_set   db     'canviar el PATH$'
fa_clr   db     'treure el PATH$'
fa_load  db     'carregar el PATH de $'
fa_save  db     'desar el PATH a $'
fa_var   db     'posar la variable $'
fa_multi db     'fer els canvis al PATH$'
A_ANY    equ    0
A_ADD    equ    1
A_DEL    equ    2
A_SET    equ    3
A_CLR    equ    4
A_LOAD   equ    5
A_SAVE   equ    6
A_VAR    equ    7
A_MULTI  equ    8
acttab   dw     t_any,t_add,t_del,t_set,t_clr,t_load,t_save,t_var,t_multi
t_any    dw     fa_any,0,m_none
t_add    dw     fa_add,tmp,fa_add2
t_del    dw     fa_del,tmp,fa_del2
t_set    dw     fa_set,0,m_none
t_clr    dw     fa_clr,0,m_none
t_load   dw     fa_load,fname,m_none
t_save   dw     fa_save,sname,m_none
t_var    dw     fa_var,name,m_none
t_multi  dw     fa_multi,0,m_none
m_iunset db     ' tret.',13,10,'$'
m_full1 db      "XPATH: no hi cap. L'entorn del COMMAND.COM principal hauria de",13,10
        db      'fer $'
m_full2 db      ' bytes i en t‚ $'
m_full3 db      '.',13,10,'$'
m_full4 db      'No he canviat res.',13,10,'$'
m_low1  db      "Atenci¢: a l'entorn del COMMAND.COM nom‚s hi queden $"
m_low2  db      ' bytes',13,10,'lliures (de $'
m_low3  db      ').',13,10,'$'
m_sug1  db      "Fes-lo m‚s gran amb /E: a la l¡nia del COMMAND.COM (SHELL= del",13,10
        db      'CONFIG.SYS o LOADHI.CFG) i reinicia; per exemple /E:$'
m_sug2  db      ':',13,10,'  SHELL=C:\COMMAND.COM C:\ /P /E:$'
m_long1 db      'Atenci¢: el PATH fa $'
m_long2 db      " car…cters. S'ha posat, per• l'ordre PATH no el podria",13,10
        db      "tornar a escriure tan llarg (la l¡nia d'ordres no passa de 127).",13,10,'$'
m_nopar  db     "XPATH: l'entorn d'aquest COMMAND.COM (fill) no t‚ espai: el canvi",13,10
         db     "es veur… quan tornis al COMMAND.COM principal.",13,10,'$'
m_help   db     'XPATH 0.7 - PATH i variables a l',39,'entorn principal (MS-DOS 3.x-6.x)',13,10,13,10
         db     '  XPATH                 mostra el PATH',13,10
         db     '  XPATH cam¡[;cam¡...]  posa el PATH (%VAR% s',39,'expandeix:',13,10
         db     '                        XPATH %PATH%;C:\UTIL)',13,10
         db     '  XPATH +cam¡           l',39,'afegeix al final (si no hi ‚s)',13,10
         db     '  XPATH -cam¡           el treu',13,10
         db     '  XPATH +c1 -c2 +c3...  diversos, en ordre, d',39,'un sol cop',13,10
         db     '  XPATH ;               treu el PATH',13,10
         db     '  XPATH /LOAD:fitxer    posa el PATH amb els camins d',39,'un fitxer de',13,10
         db     '                        text (un per l¡nia; # = comentari)',13,10
         db     '  XPATH /SAVE:fitxer    desa el PATH en un fitxer (un cam¡ per l¡nia)',13,10
         db     '  XPATH /S              llista l',39,'entorn principal',13,10
         db     '  XPATH /S NOM=valor    posa una variable (NOM= la treu)',13,10
         db     '  /V0 /V1 /V2 /V3       missatges: /V0 cap; /V1 quŠ ha fet (o que no',13,10
         db     '                        ha pogut); /V2 i els avisos; /V3 i el PATH',13,10
         db     '                        final i els errors explicats (per defecte)',13,10,13,10
         db     'Escriu a l',39,'entorn del COMMAND.COM principal i al del COMMAND',13,10
         db     'que l',39,'executa: el canvi queda despr‚s d',39,'un COMMAND /C.',13,10,'$'

        align   2
bss:
par     equ     bss
penv    equ     par+2
menv    equ     penv+2
eseg    equ     menv+2
tail    equ     eseg+2
tlen    equ     tail+2
arena   equ     tlen+2
fbk     equ     arena+2
f2c     equ     fbk+2
c2c     equ     f2c+2
nsz     equ     c2c+2                   ; mida nova de l'entorn (bytes)
bsz     equ     nsz+2                   ; mida del bloc (bytes)
msz     equ     bsz+2                   ;   (les del principal)
mbs     equ     msz+2
dosv    equ     mbs+2                   ; versi¢ del DOS (3.30 = 031Eh)
ncnt    equ     dosv+2                  ; camins posats (setlist)
rem     equ     ncnt+2                  ; -cam¡: s'ha tret?
verb    equ     rem+1                   ; /Vn
q       equ     verb+1                  ; 1 = no escriure (segons /Vn)
o_s     equ     q+1                     ; /S
o_f     equ     o_s+1                   ; /F:
name    equ     o_f+1                   ; 64
fname   equ     name+64                 ; 80
sname   equ     fname+80                ; 80 (/SAVE:)
o_sv    equ     sname+80                ; /SAVE:
act     equ     o_sv+1                  ; quŠ es fa (A_...)
emode   equ     act+1                   ; 1: cam¡ no v…lid = error (+cam¡)
o_hx    equ     emode+1                 ; /? (ajuda demanada)
op      equ     o_hx+1                  ; '+' o '-'
logp    equ     op+1                    ; registre del que s'ha fet (lbuf)
nchg    equ     logp+2                  ; quants canvis
sdir    equ     nchg+2                  ; 68 (directori d'abans)
arg     equ     sdir+68                 ; 132
val     equ     arg+132                 ; 1024
tmp     equ     val+1024                ; 256
tmp2    equ     tmp+256                 ; 1024
nv      equ     tmp2+1024               ; 1024
ltmp    equ     nv+1024                 ; 256
LBSZ    equ     2048
lbuf    equ     ltmp+256                ; LBSZ
FBSZ    equ     4096
fbuf    equ     lbuf+LBSZ               ; FBSZ
wk      equ     fbuf+FBSZ               ; WKSZ
stk     equ     wk+WKSZ
stk_top equ     stk+512
