; =====================================================================
;  NOTE.ASM  -  NOTE.COM 0.3 per a MS-DOS 3.20 o superior (8086)
;
;  Marca l'estat de la mem•ria perquŠ FREENOTE pugui treure despr‚s els
;  residents (TSR) que no es poden desinstalúlar sols.
;
;  La primera vegada NOTE es queda resident (uns 2,6 KB, a la mem•ria
;  baixa o a l'alta si es carrega amb LOADHI) i fa la marca 1. Desa
;  els 256 vectors d'interrupci¢ i vigila INT 21h/31h i INT 27h: quan
;  un programa es queda resident, n'anota el PSP, el nom i quins
;  vectors ha canviat (valor anterior i valor nou). Les execucions
;  segents de NOTE no ocupen m‚s mem•ria: nom‚s afegeixen una marca.
;  NOTE /D treu NOTE de la mem•ria encara que hi hagi marques, sense
;  preguntar res; els residents es queden on s¢n.
;
;  Compilar:  nasm -f bin NOTE.ASM -o NOTE.COM
; =====================================================================

        cpu     8086
        org     100h

%include "NOTE.INC"

start:  jmp     install

; ---------------------------------------------------------------------
;  Part resident (despla‡aments fixos: vegeu NOTE.INC)
; ---------------------------------------------------------------------
        times   (N_SIG-100h)-($-$$) db 0
sig     db      "NOTE01"
ho21    dw      int21
ho27    dw      int27
old21   dd      0
old27   dd      0
nrec    db      0
ndiff   db      0
nflags  db      0
rpsp    dw      0               ; N_TMP: dades de treball de record
rsize   dw      0
currec  dw      0
        times   (N_EXP-100h)-($-$$) db 0
expected times  1024 db 0
recs    times   MAXREC*RECSZ db 0
diffs   times   MAXDIFF*DIFFSZ db 0

; --- INT 21h: nom‚s ens interessa AH=31h (acabar i quedar resident) ---
int21:  cmp     ah,31h
        je      .tsr
        jmp     far [cs:old21]
.tsr:   push    ax
        push    bx
        push    cx
        push    dx
        push    si
        push    di
        push    bp
        push    ds
        push    es
        push    dx                      ; par…grafs que es queda
        mov     ah,51h                  ; PSP actual
        int     21h
        pop     dx
        call    record
        pop     es
        pop     ds
        pop     bp
        pop     di
        pop     si
        pop     dx
        pop     cx
        pop     bx
        pop     ax
        jmp     far [cs:old21]

; --- INT 27h: DX = bytes, CS del que crida = PSP ---
int27:  push    ax
        push    bx
        push    cx
        push    dx
        push    si
        push    di
        push    bp
        push    ds
        push    es
        mov     bp,sp
        mov     bx,[bp+20]              ; CS de qui crida = PSP
        mov     ax,dx
        add     ax,15
        rcr     ax,1
        shr     ax,1
        shr     ax,1
        shr     ax,1
        mov     dx,ax
        call    record
        pop     es
        pop     ds
        pop     bp
        pop     di
        pop     si
        pop     dx
        pop     cx
        pop     bx
        pop     ax
        jmp     far [cs:old27]

; Anota un resident.  BX = PSP, DX = par…grafs
record:
        push    cs
        pop     ds
        cld
        mov     ax,cs
        cmp     bx,ax                   ; NOTE mateix: no
        je      .r
        mov     al,[nrec]
        cmp     al,MAXREC
        jb      .ok
        or      byte [nflags],1
.r:     ret
.ok:    mov     [rpsp],bx
        mov     [rsize],dx
        mov     ah,RECSZ
        mul     ah
        add     ax,recs
        mov     di,ax
        mov     [currec],di
        mov     byte [di+R_TYPE],'T'
        mov     byte [di+R_NDIFF],0
        mov     [di+R_PSP],bx
        mov     al,[ndiff]
        mov     [di+R_DIDX],al
        mov     [di+R_SIZE],dx
        mov     byte [di+R_FLAGS],0
        add     di,R_NAME
        call    getname
        ; compara els vectors amb els coneguts
        xor     ax,ax
        mov     es,ax
        xor     bx,bx                   ; BX = vector*4
        mov     si,expected
.v:     cmp     bx,22h*4                ; 22h-24h: els posa DOS per programa
        jb      .chk
        cmp     bx,24h*4
        jbe     .nx
.chk:   mov     ax,[es:bx]
        mov     dx,[es:bx+2]
        cmp     ax,[si]
        jne     .df
        cmp     dx,[si+2]
        je      .nx
.df:    call    adddiff
        mov     [si],ax
        mov     [si+2],dx
.nx:    add     si,4
        add     bx,4
        cmp     bx,1024
        jb      .v
        inc     byte [nrec]
        ret

; Afegeix un canvi: BX = vector*4, DX:AX = valor nou, SI -> valor anterior
adddiff:
        push    ax
        push    cx
        push    di
        mov     cl,[ndiff]
        cmp     cl,MAXDIFF
        jb      .s
        mov     di,[currec]
        or      byte [di+R_FLAGS],1     ; no hi cap: canvis incomplets
        jmp     .x
.s:     push    ax
        mov     al,cl
        mov     ah,DIFFSZ
        mul     ah
        add     ax,diffs
        mov     di,ax
        pop     ax
        mov     cx,bx
        shr     cx,1
        shr     cx,1
        mov     [di+D_VEC],cl
        mov     [di+D_NEW],ax
        mov     [di+D_NEW+2],dx
        mov     cx,[si]
        mov     [di+D_OLD],cx
        mov     cx,[si+2]
        mov     [di+D_OLD+2],cx
        ; apunta dins del resident? (segment normalitzat)
        push    ax
        mov     cl,4
        shr     ax,cl
        add     ax,dx
        mov     byte [di+D_FLAGS],0
        mov     cx,[rpsp]
        cmp     ax,cx
        jb      .ext
        add     cx,[rsize]
        cmp     ax,cx
        jae     .ext
        mov     byte [di+D_FLAGS],1
.ext:   pop     ax
        inc     byte [ndiff]
        mov     di,[currec]
        inc     byte [di+R_NDIFF]
.x:     pop     di
        pop     cx
        pop     ax
        ret

; Nom del programa (de l'entorn) a DS:DI, 8 car…cters amb espais
getname:
        push    di
        mov     cx,8
.sp:    mov     byte [di],' '
        inc     di
        loop    .sp
        pop     di
        mov     es,[rpsp]
        mov     ax,[es:2Ch]
        or      ax,ax
        jz      .q
        mov     es,ax
        xor     si,si
.s:     cmp     word [es:si],0          ; final de les variables
        je      .f
        inc     si
        cmp     si,7FF0h
        jb      .s
        jmp     .q
.f:     add     si,4                    ; 00 00 + comptador
        mov     bx,si
.p:     mov     al,[es:si]
        inc     si
        or      al,al
        jz      .pe
        cmp     al,'\'
        je      .ps
        cmp     al,':'
        jne     .p
.ps:    mov     bx,si
        jmp     .p
.pe:    mov     si,bx
        mov     cx,8
.c:     mov     al,[es:si]
        or      al,al
        jz      .q
        cmp     al,'.'
        je      .q
        cmp     al,' '
        jbe     .q
        mov     [di],al
        inc     di
        inc     si
        loop    .c
.q:     ret

resident_end:

; ---------------------------------------------------------------------
;  Part transit•ria
; ---------------------------------------------------------------------
install:
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
        ; par…metres: /? o /D
        mov     si,81h
.pa:    lodsb
        cmp     al,' '
        je      .pa
        cmp     al,9
        je      .pa
        cmp     al,13
        je      .pdone
        cmp     al,'/'
        jne     .bad
        lodsb
        cmp     al,'?'
        je      .hlp
        and     al,0DFh                 ; maj£scula
        cmp     al,'D'
        jne     .bad
        mov     byte [optdel],1
        jmp     .pa
.hlp:   mov     dx,msg_help
        call    puts
        mov     ax,4C00h
        int     21h
.bad:   mov     dx,msg_parm
        call    puts
        mov     ax,4C01h
        int     21h
.pdone:
        call    umb_link
        call    find_note
        cmp     byte [optdel],0
        je      .nodel
        jmp     remove_note
.nodel: or      ax,ax
        jz      .new
        ; ---- ja hi ‚s: afegeix una marca ----
        mov     es,ax
        mov     [nseg],ax
        mov     al,[es:N_NREC]
        cmp     al,MAXREC
        jb      .room
        mov     dx,msg_full
        call    puts
        call    umb_restore
        mov     ax,4C01h
        int     21h
.room:  mov     ah,RECSZ
        mul     ah
        add     ax,N_RECS
        mov     di,ax
        mov     byte [es:di+R_TYPE],'M'
        mov     byte [es:di+R_NDIFF],0
        mov     word [es:di+R_PSP],0
        mov     al,[es:N_NDIFF]
        mov     [es:di+R_DIDX],al
        mov     word [es:di+R_SIZE],0
        mov     byte [es:di+R_FLAGS],0
        inc     byte [es:N_NREC]
        ; n£mero de marca
        xor     cx,cx
        mov     cl,[es:N_NREC]
        mov     si,N_RECS
        xor     ax,ax
.cm:    cmp     byte [es:si+R_TYPE],'M'
        jne     .cm2
        inc     ax
.cm2:   add     si,RECSZ
        loop    .cm
        push    ds
        pop     es
        mov     di,linebuf
        push    ax
        mov     si,msg_mark1
        call    put_str
        pop     ax
        xor     dx,dx
        call    put_dec32
        mov     si,msg_mark2
        call    put_str
        call    out_line
        call    umb_restore
        mov     ax,4C00h
        int     21h

        ; ---- primera vegada: es queda resident ----
.new:   mov     ax,3521h
        int     21h
        mov     [old21],bx
        mov     [old21+2],es
        mov     ax,3527h
        int     21h
        mov     [old27],bx
        mov     [old27+2],es
        push    ds
        pop     es
        mov     dx,int21
        mov     ax,2521h
        int     21h
        mov     dx,int27
        mov     ax,2527h
        int     21h
        ; vectors actuals = estat conegut
        cli
        push    ds
        xor     si,si
        mov     ds,si
        mov     di,expected
        mov     cx,512
        rep     movsw
        pop     ds
        sti
        ; marca 1
        mov     byte [nrec],1
        mov     byte [ndiff],0
        mov     byte [nflags],0
        mov     di,recs
        mov     byte [di+R_TYPE],'M'
        ; allibera l'entorn
        mov     es,[2Ch]
        mov     ah,49h
        int     21h
        mov     word [2Ch],0
        push    ds
        pop     es
        ; missatge
        mov     di,linebuf
        mov     si,msg_inst1
        call    put_str
        mov     ax,cs
        call    put_hex16
        mov     si,msg_low
        mov     ax,cs
        cmp     ax,0A000h
        jb      .lo
        mov     si,msg_high
.lo:    call    put_str
        mov     si,msg_inst2
        call    put_str
        mov     ax,(resident_end-start+100h+15)/16*16
        xor     dx,dx
        call    put_dec32
        mov     si,msg_inst3
        call    put_str
        call    out_line
        call    umb_restore
        mov     dx,resident_end+15
        mov     cl,4
        shr     dx,cl
        mov     ax,3100h
        int     21h

; ---------------------------------------------------------------------
;  NOTE /D: treu NOTE de la mem•ria sense preguntar.  AX = PSP o 0
;  Les marques i el que s'hi havia anotat es perden; els residents
;  carregats despr‚s es queden on s¢n.  Cal que les INT 21h i 27h
;  encara apuntin a NOTE: si un altre programa les ha enganxat per
;  sobre, el seu enlla‡ cap a NOTE quedaria trencat.
; ---------------------------------------------------------------------
remove_note:
        or      ax,ax
        jnz     .have
        mov     dx,msg_nonote
        call    puts
        jmp     .err
.have:  mov     [nseg],ax
        mov     es,ax
        xor     bx,bx
        mov     ds,bx                   ; DS = 0: taula de vectors
        mov     dx,[es:N_HO21]
        cmp     [21h*4],dx
        jne     .hooked
        cmp     [21h*4+2],ax
        jne     .hooked
        mov     dx,[es:N_HO27]
        cmp     [27h*4],dx
        jne     .hooked
        cmp     [27h*4+2],ax
        jne     .hooked
        cli
        mov     dx,[es:N_OLD21]
        mov     [21h*4],dx
        mov     dx,[es:N_OLD21+2]
        mov     [21h*4+2],dx
        mov     dx,[es:N_OLD27]
        mov     [27h*4],dx
        mov     dx,[es:N_OLD27+2]
        mov     [27h*4+2],dx
        sti
        push    cs
        pop     ds
        xor     cx,cx                   ; CL = marques, CH = residents
        mov     dl,[es:N_NREC]
        mov     si,N_RECS
.cnt:   or      dl,dl
        jz      .cntd
        cmp     byte [es:si+R_TYPE],'M'
        jne     .ct
        inc     cl
        jmp     .cn
.ct:    inc     ch
.cn:    add     si,RECSZ
        dec     dl
        jmp     .cnt
.cntd:  mov     [nmarks],cl
        mov     [ntsrs],ch
        mov     word [es:N_SIG],0       ; que no es torni a trobar
        mov     ax,es
        dec     ax
        push    es
        mov     es,ax
        mov     ax,[es:3]               ; mida del bloc (par…grafs)
        pop     es
        mov     cl,4
        shl     ax,cl
        mov     [delbytes],ax
        mov     ah,49h                  ; allibera NOTE
        int     21h
        push    ds
        pop     es
        mov     di,linebuf
        mov     si,msg_del1
        call    put_str
        mov     ax,[delbytes]
        xor     dx,dx
        call    put_dec32
        mov     si,msg_del2
        call    put_str
        xor     ax,ax
        mov     al,[nmarks]
        xor     dx,dx
        call    put_dec32
        mov     si,msg_del3
        call    put_str
        xor     ax,ax
        mov     al,[ntsrs]
        xor     dx,dx
        call    put_dec32
        mov     si,msg_del4
        call    put_str
        call    out_line
        call    umb_restore
        mov     ax,4C00h
        int     21h
.hooked:
        push    cs
        pop     ds
        mov     dx,msg_hooked
        call    puts
.err:   push    cs
        pop     ds
        call    umb_restore
        mov     ax,4C01h
        int     21h

; ---------------------------------------------------------------------
;  Cerca un NOTE ja resident a la cadena de mem•ria -> AX = PSP o 0
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
        cmp     [es:1],bx               ; bloc del seu propi PSP?
        jne     .next
        cmp     bx,[cs:ownpsp]
        je      .next
        mov     cx,cs
        cmp     bx,cx                   ; nosaltres mateixos
        je      .next
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

; DOS 5+: enlla‡a la mem•ria superior a la cadena mentre treballem
umb_link:
        mov     [ownpsp],cs
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

put_hex16:
        push    cx
        mov     bx,ax
        mov     ch,4
.h:     mov     cl,4
        rol     bx,cl
        mov     al,bl
        and     al,0Fh
        add     al,'0'
        cmp     al,'9'
        jbe     .s
        add     al,7
.s:     stosb
        dec     ch
        jnz     .h
        pop     cx
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
.x:     pop     bx
        pop     cx
        pop     si
        ret

; ---------------------------------------------------------------------
sigtxt      db  "NOTE01"
msg_ver     db  "Versi¢n incorrecta de DOS",13,10,0
msg_parm    db  "Par metro no v lido",13,10,0
msg_full    db  "La tabla de NOTE est  llena: libere residentes con FREENOTE.",13,10,0
msg_inst1   db  "NOTE 0.3 instalado en ",0
msg_low     db  " (memoria convencional), ",0
msg_high    db  " (memoria superior), ",0
msg_inst2   db  "",0
msg_inst3   db  " bytes. Marca 1.",0
msg_mark1   db  "Marca ",0
msg_mark2   db  " creada.",0
msg_help    db  "Marca el estado de la memoria para poder liberar despu‚s los",13,10
            db  "programas residentes con FREENOTE.",13,10,13,10
            db  "NOTE",13,10,13,10
            db  "La primera vez queda residente (unos 2,6 KB) y crea la marca 1;",13,10
            db  "cada vez que se ejecuta de nuevo crea otra marca sin ocupar m s",13,10
            db  "memoria. Use FREENOTE /L para ver las marcas y los residentes.",13,10,13,10
            db  "NOTE /D",13,10,13,10
            db  "Quita NOTE de la memoria aunque haya marcas, sin preguntar. Las",13,10
            db  "marcas se pierden; los residentes cargados se quedan en memoria.",13,10,0
msg_nonote  db  "NOTE no est  instalado.",13,10,0
msg_hooked  db  "NOTE no se puede quitar: la INT 21h o 27h ha sido enganchada por otro programa.",13,10,0
msg_del1    db  "NOTE desinstalado (",0
msg_del2    db  " bytes). Marcas descartadas: ",0
msg_del3    db  "; residentes anotados: ",0
msg_del4    db  " (siguen en memoria).",0
dosmaj      db  0
umbstate    db  0
umbsaved    db  0
ownpsp      dw  0
nseg        dw  0
optdel      db  0
nmarks      db  0
ntsrs       db  0
delbytes    dw  0

        section .bss
linebuf     resb 128
            resb 512
stack_top:
