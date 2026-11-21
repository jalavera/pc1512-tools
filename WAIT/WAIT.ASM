; ===========================================================================
;  WAIT.ASM  -  Espera amb compte enrere per a fitxers .BAT (MS-DOS 2.0+)
;  Versi¢ 0.1 - CPU 8086
;
;  WAIT [segons] ["missatge"] [/K]
;     segons     1-3600 (per defecte 10)
;     "missatge" el text; # marca on surt el compte enrere
;                (sense #, el compte surt al final del missatge)
;     /K         una tecla atura l'espera (ERRORLEVEL 1)
;
;  ERRORLEVEL: 0 temps esgotat, 1 aturat amb una tecla (/K), 2 error.
;  Nom‚s es reescriuen els d¡gits del compte enrere, a la mateixa posici¢.
;
;  Assemblar:  NASM -f bin WAIT.ASM -o WAIT.COM
; ===========================================================================

        cpu     8086
        org     100h

MAXSEG  equ     3600

start:  cld
        mov     si,81h                  ; marca el final de la l¡nia
        mov     cl,[80h]
        xor     ch,ch
        mov     bx,si
        add     bx,cx
        mov     byte [bx],0Dh

parse:  lodsb
        cmp     al,' '
        je      parse
        cmp     al,9
        je      parse
        cmp     al,0Dh
        je      parsed
        cmp     al,'/'
        je      .sw
        cmp     al,'"'
        je      .quot
        cmp     al,'0'
        jb      .bare
        cmp     al,'9'
        jbe     .num
.bare:  dec     si                      ; text sense cometes: fins al final
        mov     [msgp],si
        mov     di,si
.b1:    lodsb
        cmp     al,0Dh
        je      .b2
        cmp     al,' '
        je      .b1
        mov     di,si                   ; darrer car…cter no blanc + 1
        jmp     short .b1
.b2:    sub     di,[msgp]
        mov     [msgl],di
        jmp     short parsed
.quot:  mov     [msgp],si
.q1:    lodsb
        cmp     al,'"'
        je      .q2
        cmp     al,0Dh
        jne     .q1
        dec     si                      ; sense cometa final
.q2:    mov     ax,si
        dec     ax
        sub     ax,[msgp]
        mov     [msgl],ax
        mov     byte [hasmsg],1
        jmp     parse
.num:   dec     si
        xor     bx,bx
.n1:    lodsb
        sub     al,'0'
        jb      .n2
        cmp     al,9
        ja      .n2
        xor     ah,ah
        xchg    ax,bx
        mov     dx,10
        mul     dx
        jc      .bad
        add     ax,bx
        jc      .bad
        mov     bx,ax
        cmp     bx,MAXSEG
        ja      .bad
        jmp     short .n1
.n2:    dec     si
        or      bx,bx
        jz      .bad
        mov     [secs],bx
        jmp     parse
.sw:    lodsb
        cmp     al,'?'
        je      help
        and     al,0DFh
        cmp     al,'K'
        jne     .bad
        mov     byte [kflag],1
        jmp     parse
.bad:   mov     dx,m_bad
        mov     ah,9
        int     21h
        mov     ax,4C02h
        int     21h

parsed: cmp     word [msgl],0           ; missatge per defecte
        jne     .m
        cmp     byte [hasmsg],0         ; "" expl¡cit: nom‚s el n£mero
        jne     .m
        mov     word [msgp],d_wait
        mov     word [msgl],D_WAITL
        cmp     byte [kflag],0
        je      .m
        mov     word [msgp],d_key
        mov     word [msgl],D_KEYL
.m:
        ; amplada del n£mero = xifres del valor inicial
        mov     ax,[secs]
        mov     bx,10
        xor     cx,cx
.w:     xor     dx,dx
        div     bx
        inc     cx
        or      ax,ax
        jnz     .w
        mov     [width],cl

        call    flushkb                 ; les tecles d'abans no compten

        ; --- escriu el missatge; al # hi va el n£mero
        mov     si,[msgp]
        mov     cx,[msgl]
        jcxz    .nomsg
.p1:    lodsb
        cmp     al,'#'
        jne     .pc
        cmp     byte [placed],0
        jne     .pc
        call    place
        jmp     short .pn
.pc:    mov     dl,al
        mov     ah,2
        int     21h
.pn:    loop    .p1
.nomsg: cmp     byte [placed],0
        jne     .ok
        cmp     word [msgl],0
        je      .sp
        mov     dl,' '
        mov     ah,2
        int     21h
.sp:    call    place
.ok:    call    getcur
        mov     [endpos],dx

        ; --- bucle d'espera
        mov     ax,[secs]
        mov     [shown],ax
        call    ticks
        mov     [last],ax
wloop:  mov     ah,1                    ; tecla?
        int     16h
        jz      .nok
        cmp     al,3                    ; Ctrl+C: que el DOS l'atengui
        jne     .k1
        mov     ah,0Bh
        int     21h
        jmp     short .nok
.k1:    xor     ah,ah
        int     16h
        cmp     byte [kflag],0
        je      .nok                    ; sense /K: s'ignora
        call    newline
        mov     ax,4C01h
        int     21h
.nok:   call    ticks
        mov     bx,ax
        sub     ax,[last]
        mov     [last],bx
        cmp     ax,100                  ; mitjanit o salt estrany: 1 tic
        jbe     .t1
        mov     ax,1
.t1:    add     [elapsed],ax
        mov     ax,[elapsed]            ; segons = tics * 5 / 91
        mov     dx,5
        mul     dx
        mov     bx,91
        div     bx
        mov     bx,[secs]
        sub     bx,ax
        jbe     .end
        cmp     bx,[shown]
        je      wloop
        mov     [shown],bx
        mov     ax,bx
        call    update
        jmp     short wloop
.end:   xor     ax,ax
        call    update
        call    newline
        mov     ax,4C00h
        int     21h

; --- desa la posici¢ del n£mero i l'escriu
place:  push    ax
        push    cx
        push    si
        mov     byte [placed],1
        call    getcur
        mov     [numpos],dx
        mov     ax,[secs]
        call    pnum
        pop     si
        pop     cx
        pop     ax
        ret

; --- AX = segons: reescriu nom‚s el n£mero i torna el cursor al final
update: push    ax
        mov     dx,[numpos]
        call    setcur
        pop     ax
        call    pnum
        mov     dx,[endpos]
        jmp     short setcur

; --- AX en decimal, alineat a la dreta amb [width] posicions
pnum:   mov     bx,10
        xor     cx,cx
.d:     xor     dx,dx
        div     bx
        add     dl,'0'
        push    dx
        inc     cx
        or      ax,ax
        jnz     .d
        mov     al,[width]
        xor     ah,ah
        sub     ax,cx
        jbe     .o
        push    cx
        mov     cx,ax
.s:     mov     dl,' '
        mov     ah,2
        int     21h
        loop    .s
        pop     cx
.o:     pop     dx
        mov     ah,2
        int     21h
        loop    .o
        ret

getcur: mov     ah,3                    ; DX = fila/columna
        call    vpage
        int     10h
        ret

setcur: mov     ah,2
        call    vpage
        int     10h
        ret

vpage:  push    ds                      ; BH = p…gina activa
        push    ax
        mov     ax,40h
        mov     ds,ax
        mov     bh,[62h]
        pop     ax
        pop     ds
        ret

ticks:  push    ds                      ; AX = tics del rellotge (part baixa)
        mov     ax,40h
        mov     ds,ax
        mov     ax,[6Ch]
        pop     ds
        ret

flushkb:
        mov     ah,1
        int     16h
        jz      .r
        cmp     al,3                    ; Ctrl+C es queda per al DOS
        je      .r
        xor     ah,ah
        int     16h
        jmp     short flushkb
.r:     ret

newline:
        mov     dx,m_crlf
        mov     ah,9
        int     21h
        ret

help:   mov     dx,m_help
        mov     ah,9
        int     21h
        mov     ax,4C00h
        int     21h

; --- dades ------------------------------------------------------------------
secs    dw      10
msgp    dw      0
msgl    dw      0
hasmsg  db      0
kflag   db      0
placed  db      0
width   db      1
numpos  dw      0
endpos  dw      0
shown   dw      0
last    dw      0
elapsed dw      0

d_wait  db      'Esperant # s...'
D_WAITL equ     $-d_wait
d_key   db      'Premeu una tecla per continuar (# s)...'
D_KEYL  equ     $-d_key

m_crlf  db      13,10,'$'
m_bad   db      'WAIT: par…metre incorrecte. WAIT /? per a l',27h,'ajuda.',13,10,'$'
m_help  db      'WAIT 0.1 - espera amb compte enrere',13,10,13,10
        db      'WAIT [segons] ["missatge"] [/K]',13,10
        db      '  segons     1-3600 (per defecte 10)',13,10
        db      '  "missatge" text a mostrar; # = on surt el compte enrere',13,10
        db      '  /K         una tecla atura l',27h,'espera',13,10,13,10
        db      'ERRORLEVEL: 0 temps esgotat, 1 tecla (/K), 2 error.',13,10
        db      'Exemple: WAIT 5 "Arrencant el GEM en # s (tecla = DOS)" /K',13,10,'$'
