; HIDOS6K.ASM - el que HIDOS6 afegeix al final de l'IO.SYS de l'MS-DOS 6.22
; (dins el SYSINIT). S'assembla una vegada per a cada IO.SYS conegut:
;   nasm -f bin -DSZ=5A20h -DA79=0A79h HIDOS6K.ASM -o HIDOS6K.BIN
; SZ:  mida original del SYSINIT (aqu° comenáa aquest codi)
; A79: rutina del SYSINIT que copia el codi del BIOS i del DOS a un bloc
;      nou amb la funci¢ 48h (el que fa quan no hi ha HMA)
; P36E: variable del SYSINIT amb el segment on es posa la taula segÅent
;      (a P36E-2, l'offset)
; P372, P36A: inici del bloc 'SD' i la seva mida final
; P27B: punter (offset, segment) a l'entrada del MSDOS.SYS (DOSINIT)
; P2AF: l°mit d'aquest punter; P2A9: el nombre de FILES (instrucci¢ que
;      es fa en lloc del SYSINIT)
        cpu     8086
        org     SZ

sig     db      'HIDOS6',0              ; +0  signatura
ver     db      5                       ; +7  versi¢ del format
flags   db      0                       ; +8  bit 0: intärpret a baix (/S-)
                                        ;     bit 1: taules a baix (/L)
                                        ;     bit 2: dades del DOS a dalt (/D)
                                        ;     bit 3: UMB sempre enllaáats (/E)
        db      0                       ; +9
d_zone  dw      0BE00h                  ; +0Ah on van les dades del DOS (/D:)
        db      0,0,0,0                 ; reservat
        jmp     near kern               ; +10h des del lloc de "HMA no disponible"
        jmp     near shell              ; +13h des de l'EXEC del SHELL=
        jmp     near tabbeg             ; +16h abans de FILES, FCBS, BUFFERS...
        jmp     near tabend             ; +19h quan el SYSINIT tanca el bloc 'SD'
        jmp     near bioshk             ; +1Ch (crida far) des del BIOS, abans del SYSINIT
        jmp     near dosini             ; +1Fh en lloc de "call far [P27B]"

; ---- les dades del DOS (DOSDATA) a la memïria superior (/D) -----------------
; El MSDOS.SYS, en iniciar-se, copia les seves dades (5 KB) al segment que
; li deixa el BIOS a 0070:0003, el primer parÖgraf lliure desprÇs del BIOS,
; i la memïria comenáa just desprÇs. Amb /D, el BIOS hi posa un segment de
; la zona alta (RAM de debï, encara sense UMBPC) i, en lloc de la suma
; "dades + mida", el DOSINIT fa comenáar la memïria on hauria comenáat.
; Al primer parÖgraf de la zona hi queda una marca perquä UMBPC (1.3) no
; doni aquest tros al DOS:  'HIDOS6DD', parÖgrafs (word)
DPARA   equ     180h                    ; 6 KB, amb la marca

bioshk: add     di,70h                  ; el que hi havia: primer lliure
        mov     [cs:d_low],di
        mov     [3],di                  ; (DS = 0070)
        test    byte [cs:flags],4
        jz      .r
        push    ax
        push    bx
        push    es
        mov     ax,[cs:d_zone]
        cmp     ax,0A000h
        jb      .x
        mov     es,ax                   ; RAM? (a tres llocs)
        call    ramw
        jc      .x
        add     ax,DPARA/2
        mov     es,ax
        call    ramw
        jc      .x
        add     ax,DPARA/2-1
        mov     es,ax
        call    ramw
        jc      .x
        mov     ax,[cs:d_zone]
        mov     es,ax
        mov     word [es:0],'HI'
        mov     word [es:2],'DO'
        mov     word [es:4],'S6'
        mov     word [es:6],'DD'
        mov     word [es:8],DPARA
        inc     ax
        mov     [3],ax                  ; les dades, a dalt
        mov     byte [cs:d_on],1
.x:     pop     es
        pop     bx
        pop     ax
.r:     retf

; prova no destructiva de la paraula ES:0 (CF=1 si no Çs RAM)
ramw:   mov     bx,[es:0]
        mov     word [es:0],55AAh
        push    word [es:8]             ; "neteja" el bus
        pop     word [es:8]
        cmp     word [es:0],55AAh
        jne     .no
        mov     word [es:0],0AA55h
        push    word [es:8]
        pop     word [es:8]
        cmp     word [es:0],0AA55h
        jne     .no
        mov     [es:0],bx
        clc
        ret
.no:    mov     [es:0],bx
        stc
        ret

; En lloc de "call far [P27B]" (crida al DOSINIT del MSDOS.SYS): si les
; dades van a dalt, canvia al MSDOS.SYS (a la memïria, no al disc)
; "mov dx,ds / add dx,ax" per "mov dx,d_low / nop": la memïria comenáa a
; baix, on hauria comenáat.
dosini: cmp     byte [cs:d_on],0
        je      .call
        push    ax
        push    cx
        push    di
        push    es
        mov     ax,[cs:P27B]            ; ES:0 = principi del MSDOS.SYS
        mov     cl,4
        shr     ax,cl
        add     ax,[cs:P27B+2]
        mov     es,ax
        mov     di,7000h
        mov     cx,2000h
.s:     cmp     word [es:di],0DA8Ch
        jne     .n
        cmp     word [es:di+2],0D003h
        jne     .n
        cmp     word [es:di+4],0FBBh
        jne     .n
        mov     byte [es:di],0BAh       ; mov dx,d_low
        mov     ax,[cs:d_low]
        mov     [es:di+1],ax
        mov     byte [es:di+3],90h
        jmp     short .ok
.n:     inc     di
        loop    .s
        mov     byte [cs:d_on],0        ; no l'he trobat: no es pot
        push    ds
        mov     ax,70h
        mov     ds,ax
        mov     ax,[cs:d_low]
        mov     [3],ax
        pop     ds
.ok:    pop     es
        pop     di
        pop     cx
        pop     ax
.call:  call    far [cs:P27B]
        ret

d_on    db      0
d_low   dw      0

; ---- FILES, FCBS, BUFFERS, LASTDRIVE (i STACKS) a la memïria superior ------
; El SYSINIT els posa un darrere l'altre al punter [P36E-2]:[P36E], just
; desprÇs dels controladors (DEVICE=), i al final en fa el bloc 'SD'.
; Abans de comenáar, HIDOS6 demana un UMB i hi apunta el punter; quan el
; SYSINIT tanca el bloc, ajusta l'UMB a la mida feta, li posa el nom 'SD'
; i torna el punter on era (el bloc de baix nomÇs tÇ els controladors).
tabbeg: test    byte [cs:flags],2
        jnz     .fi
        push    ax
        push    bx
        push    es
        call    savelk
        mov     bx,40h                  ; nomÇs a dalt
        call    linkbx
        jc      .lo
        mov     ah,48h
        mov     bx,0FFFFh
        int     21h                     ; BX = el mÇs gran
        cmp     bx,40h
        jb      .lo                     ; menys d'1 KB: no val la pena
        mov     ah,48h
        int     21h
        jc      .lo
        mov     [cs:t_seg],ax
        push    word [cs:P2AF]
        pop     word [cs:t_lim]
        add     bx,ax
        mov     [cs:P2AF],bx            ; nou l°mit
        mov     bx,[cs:P36E]
        mov     [cs:t_p0],bx
        mov     bx,[cs:P36E-2]
        mov     [cs:t_p0+2],bx
        mov     [cs:P36E],ax
        mov     word [cs:P36E-2],0
        mov     byte [cs:t_on],1
.lo:    call    linklo
        pop     es
        pop     bx
        pop     ax
.fi:    mov     al,[cs:P2A9]            ; el que hi havia
        ret

tabend: cmp     byte [cs:t_on],0
        je      .fi
        push    ax
        push    es
        mov     es,[cs:t_seg]
        mov     bx,[cs:P36E]
        sub     bx,[cs:t_seg]
        mov     ah,4Ah                  ; l'UMB, de la mida feta
        int     21h
        mov     ax,es
        dec     ax
        mov     es,ax
        mov     word [es:1],8
        mov     word [es:8],'SD'
        mov     word [es:10],0
        mov     bx,[cs:t_p0]            ; el punter, on era
        mov     [cs:P36E],bx
        sub     bx,[cs:P372]            ; i la mida del bloc de baix
        mov     [cs:P36A],bx            ; (sense el tros temporal 'T')
        mov     bx,[cs:t_p0+2]
        mov     [cs:P36E-2],bx
        mov     bx,[cs:t_lim]
        mov     [cs:P2AF],bx
        mov     byte [cs:t_on],0
        pop     es
        pop     ax
.fi:    mov     bx,[cs:P36E]            ; el que hi havia
        ret

t_on    db      0
t_seg   dw      0
t_p0    dw      0,0
t_lim   dw      0

; ---- DOS=HIGH sense HMA: el nucli a la memïria superior -------------------
kern:   call    linkhi
        mov     bx,1
        call    A79                     ; bloc 'SC' amb la funci¢ 48h: a dalt
        pushf
        call    linklo
        popf
        push    cs
        pop     ds
        mov     dx,m_hi
        cmp     byte [cs:d_on],0
        je      .q
        mov     dx,m_hid
.q:     mov     ax,es                   ; ES = segment del bloc - 3
        cmp     ax,0B000h
        jae     .p
        mov     dx,m_lo
.p:     mov     ah,9
        int     21h
        ret

linkhi: call    savelk
        mov     bx,80h                  ; primer a dalt
; enllaáa els UMB i posa l'estratägia BX; CF si no hi ha UMB
linkbx: push    bx
        mov     ax,5803h
        mov     bx,1
        int     21h
        pop     bx
        jc      .r
        mov     ax,5801h
        int     21h
        clc
.r:     ret
; desa l'estratägia i l'enllaá que hi ha ara
savelk: mov     ax,5800h
        int     21h
        mov     [cs:l_str],ax
        mov     ax,5802h
        int     21h
        mov     [cs:l_lnk],al
        ret
; els torna a posar
linklo: mov     ax,5801h
        mov     bx,[cs:l_str]
        int     21h
        mov     ax,5803h
        mov     bl,[cs:l_lnk]
        xor     bh,bh
        int     21h
        ret
l_str   dw      0
l_lnk   db      0

; ---- l'intärpret (SHELL=) a la memïria superior ------------------------------
; Es crida en lloc de "mov ax,4B00h / stc / int 21h", amb DS:DX i ES:BX a
; punt per a l'EXEC.
shell:  test    byte [cs:flags],1
        jz      .hi
        test    byte [cs:flags],8       ; /S- /E: els UMB, enllaáats des d'ara
        jz      .exec
        push    ax
        push    bx
        mov     ax,5803h
        mov     bx,1
        int     21h
        pop     bx
        pop     ax
        jmp     .exec
.hi:
        push    ax
        push    bx
        push    cx
        push    dx
        push    si
        push    di
        push    ds
        push    es
        mov     ax,5803h
        mov     bx,1
        int     21h
        jc      .no                     ; sense DOS=UMB
        mov     ax,5801h                ; nomÇs a dalt
        mov     bx,40h
        int     21h
        mov     ax,3D00h                ; (0.5) hi cap? El DOS el carrega
        int     21h                     ;   sencer en un bloc: la mida del
        jc      .lo                     ;   fitxer, en parÖgrafs
        mov     bx,ax
        mov     ax,4202h
        xor     cx,cx
        xor     dx,dx
        int     21h
        push    ax
        push    dx
        mov     ah,3Eh
        int     21h
        pop     dx
        pop     ax
        cmp     dx,10h
        jae     .lo
        add     ax,15
        adc     dx,0
        mov     cl,4
        shr     ax,cl
        mov     cl,12
        shl     dx,cl
        or      ax,dx
        add     ax,10h+(HKLEN+15)/16+40h ; PSP, ganxo, MCB i entorn
        mov     si,ax
        mov     ah,48h                  ; el bloc lliure mÇs gran de dalt
        mov     bx,0FFFFh
        int     21h
        cmp     bx,si
        jb      .lo                     ; no hi cap: a baix
        mov     ah,48h                  ; bloc per al ganxo
        mov     bx,(HKLEN+15)/16
        int     21h
        jc      .lo
        mov     es,ax
        dec     ax
        mov     ds,ax
        mov     word [1],8              ; del sistema
        mov     word [8],'HI'
        mov     word [10],'DO'
        mov     word [12],'S6'
        mov     word [14],0
        push    cs
        pop     ds
        mov     si,hk
        xor     di,di
        mov     cx,HKLEN
        cld
        rep     movsb
        mov     al,[cs:flags]           ; /E: en acabar, els UMB enllaáats
        mov     cl,3
        shr     al,cl
        and     al,1
        mov     [es:hk_lnk-hk],al
        xor     ax,ax
        mov     ds,ax
        cli
        mov     ax,[84h]
        mov     [es:hk_old-hk],ax
        mov     ax,[86h]
        mov     [es:hk_old-hk+2],ax
        mov     word [84h],0
        mov     [86h],es
        sti
        jmp     short .no
.lo:    call    linklo                  ; no hi cap: tot com sempre
.no:    pop     es
        pop     ds
        pop     di
        pop     si
        pop     dx
        pop     cx
        pop     bx
        pop     ax
.exec:  mov     ax,4B00h
        stc
        int     21h
        ret

; Ganxo de l'INT 21h (es copia a dalt, offset 0): al primer EXEC que fa
; l'intärpret, o a la primera funci¢ 58h (LH la fa servir abans de
; carregar el programa), torna l'estratägia i l'enllaá com sempre, es
; treu de la cadena i allibera el seu bloc.
hk:     cmp     ah,58h
        je      .t
        cmp     ah,4Bh
        jne     .c
        cmp     byte [cs:hk_st-hk],1    ; 2: l'EXEC del mateix SHELL=
        jb      .c                      ; 0: ja fet
        je      .u
        dec     byte [cs:hk_st-hk]
        jmp     short .c
.t:     cmp     byte [cs:hk_st-hk],1    ; 58h: nomÇs un cop engegat
        jne     .c
.u:     mov     byte [cs:hk_st-hk],0
        push    ax
        push    bx
        push    ds
        push    es
        mov     ax,5801h
        xor     bx,bx
        pushf
        call    far [cs:hk_old-hk]
        mov     ax,5803h
        mov     bl,[cs:hk_lnk-hk]       ; 0, o 1 amb /E
        xor     bh,bh
        pushf
        call    far [cs:hk_old-hk]
        xor     ax,ax
        mov     ds,ax
        mov     ax,cs
        cli
        cmp     word [84h],0
        jne     .k
        cmp     [86h],ax
        jne     .k
        mov     bx,[cs:hk_old-hk]
        mov     [84h],bx
        mov     bx,[cs:hk_old-hk+2]
        mov     [86h],bx
        sti
        mov     es,ax                   ; allibera el bloc (encara es pot llegir)
        mov     ah,49h
        pushf
        call    far [cs:hk_old-hk]
.k:     sti
        pop     es
        pop     ds
        pop     bx
        pop     ax
.c:     jmp     far [cs:hk_old-hk]
hk_old  dd      0
hk_st   db      2
hk_lnk  db      0
HKLEN   equ     $-hk

m_hi    db      'HIDOS6: MS-DOS a la mem',0A2h,'ria superior.',13,10,'$'
m_hid   db      'HIDOS6: MS-DOS (tamb',82h,' les dades) a la mem',0A2h,'ria superior.',13,10,'$'
m_lo    db      'HIDOS6: sense mem',0A2h,'ria superior (cal UMBPC i DOS=UMB); MS-DOS a baix.',13,10,'$'
        align   16, db 0
