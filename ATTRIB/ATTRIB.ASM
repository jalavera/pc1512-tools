; =====================================================================
;  ATTRIB.ASM  -  ATTRIB.COM per a MS-DOS 3.20 (8086/8088, Amstrad PC1512)
;
;  Substitut de l'ATTRIB de MS-DOS 3.20 (que nom‚s gestiona R i A)
;  amb suport per als atributs H (ocult) i S (sistema), a l'estil de
;  l'ATTRIB de MS-DOS 5.0. Missatges en castell….
;
;  ATTRIB [+R|-R] [+A|-A] [+S|-S] [+H|-H] [[unidad:][ruta]nombre] [/S]
;
;  - Sense nom: tots els arxius del directori actual (*.*)
;  - Els directoris nom‚s es tracten si s'indiquen pel nom (sense comodins)
;  - Com MS-DOS 5: no modifica un arxiu ocult o de sistema si no
;    s'especifica tamb‚ +H/-H o +S/-S
;
;  Compilar:  nasm -f bin ATTRIB.ASM -o ATTRIB.COM
; =====================================================================

        cpu     8086
        org     100h

MAXLVL  equ     32
DTASZ   equ     43
PATHMAX equ     118

A_RDO   equ     01h
A_HID   equ     02h
A_SYS   equ     04h
A_DIR   equ     10h
A_ARC   equ     20h

; ---------------------------------------------------------------------
start:
        mov     ah,30h
        int     21h
        cmp     al,3
        jae     .verok
        mov     dx,msg_ver
        call    puts
        mov     ax,4C01h
        int     21h
.verok: mov     sp,stack_top
        cld

; ---------------------------------------------------------------------
;  An…lisi de la l¡nia d'ordres
; ---------------------------------------------------------------------
        mov     si,81h
next_tok:
        call    skip_delim
        cmp     al,13
        je      parsed
        mov     [tokstart],si
        cmp     al,'+'
        je      .attr
        cmp     al,'-'
        je      .attr
        cmp     al,'/'
        je      .switch
        ; --- nom d'arxiu ---
        cmp     byte [havespec],0
        jne     err_nparm
        mov     byte [havespec],1
        mov     di,spec
.fn:    mov     al,[si]
        call    is_delim
        je      .fnend
        cmp     al,'/'
        je      .fnend
        cmp     al,'+'
        je      .fnend
        cmp     di,spec+PATHMAX-14
        jae     .fnskip
        call    upcase
        stosb
.fnskip:
        inc     si
        jmp     .fn
.fnend: mov     byte [di],0
        jmp     next_tok

        ; --- +X / -X (es poden encadenar: +R+H) ---
.attr:  mov     ah,[si]                 ; '+' o '-'
        mov     al,[si+1]
        add     si,2
        call    upcase
        mov     bl,A_RDO
        cmp     al,'R'
        je      .abit
        mov     bl,A_ARC
        cmp     al,'A'
        je      .abit
        mov     bl,A_SYS
        cmp     al,'S'
        je      .abit
        mov     bl,A_HID
        cmp     al,'H'
        je      .abit
        jmp     err_parm
.abit:  cmp     ah,'+'
        jne     .aclr
        or      [setm],bl
        jmp     .anext
.aclr:  or      [clrm],bl
.anext: mov     al,[si]
        cmp     al,'+'
        je      .attr
        cmp     al,'-'
        je      .attr
        call    is_delim
        je      next_tok
        cmp     al,'/'
        je      next_tok
        jmp     err_parm

        ; --- /S  /? ---
.switch:
        mov     al,[si+1]
        add     si,2
        cmp     al,'?'
        je      help
        call    upcase
        cmp     al,'S'
        jne     err_parm
        mov     byte [recurse],1
        mov     al,[si]
        cmp     al,'/'
        je      next_tok
        call    is_delim
        je      next_tok
        jmp     err_parm

parsed:
        mov     al,[setm]
        test    al,[clrm]
        jz      .nocfl
        mov     word [tokstart],0
        jmp     err_parm                ; +X i -X alhora
.nocfl:
        mov     al,[setm]
        or      al,[clrm]
        mov     [chgm],al

; ---------------------------------------------------------------------
;  Separa directori / nom i normalitza el directori
; ---------------------------------------------------------------------
        cmp     byte [spec],0
        jne     .hasspec
        mov     si,starstar
        mov     di,spec
        call    put_str
        mov     byte [di],0
.hasspec:
        mov     si,spec                 ; busca l'£ltim '\' o ':'
        mov     bx,spec                 ; BX = inici del nom
.sc:    lodsb
        or      al,al
        jz      .scend
        cmp     al,'\'
        je      .scsep
        cmp     al,':'
        jne     .sc
.scsep: mov     bx,si
        jmp     .sc
.scend:
        ; nom
        mov     si,bx
        mov     di,fname
        call    put_str
        mov     byte [di],0
        cmp     byte [fname],0
        jne     .hasname
        mov     si,starstar
        mov     di,fname
        call    put_str
        mov     byte [di],0
.hasname:
        ; comodins?
        mov     si,fname
.wc:    lodsb
        or      al,al
        jz      .wcend
        cmp     al,'*'
        je      .wild
        cmp     al,'?'
        jne     .wc
.wild:  mov     byte [wild],1
.wcend:
        ; tmp = part de directori + "."
        mov     si,spec
        mov     di,tmp
        mov     cx,bx
        sub     cx,spec
        rep     movsb
        mov     ax,'.'                  ; "." + 0
        stosw
        ; TRUENAME (INT 21h AH=60h, present des de DOS 3.0)
        mov     si,tmp
        mov     di,path
        mov     ah,60h
        int     21h
        jnc     .canon
        cmp     ax,0Fh
        je      err_drive
        cmp     ax,1
        je      .manual                 ; funci¢ no suportada
        jmp     err_path
.manual:                                ; usa la ruta tal com s'ha escrit
        mov     si,spec
        mov     di,path
        mov     cx,bx
        sub     cx,spec
        rep     movsb
        mov     byte [di],0
.canon: mov     di,path                 ; longitud i '\' final
.ln:    cmp     byte [di],0
        je      .lnend
        inc     di
        jmp     .ln
.lnend: cmp     di,path
        je      .setlen
        mov     al,[di-1]
        cmp     al,'\'
        je      .setlen
        cmp     al,':'
        je      .setlen
        mov     byte [di],'\'
        inc     di
.setlen:
        mov     ax,di
        sub     ax,path
        mov     [pathlen],ax

; ---------------------------------------------------------------------
;  Processa
; ---------------------------------------------------------------------
        mov     byte [level],0
        call    do_dir
        cmp     byte [patherr],0
        jne     err_path
        cmp     word [found],0
        jne     exit_ok
        mov     si,msg_nf
        call    msg_spec
        jmp     exit_err

; ---------------------------------------------------------------------
;  Errors i sortida
; ---------------------------------------------------------------------
err_parm:
        mov     di,linebuf
        mov     si,msg_parm
        call    put_str
        mov     si,[tokstart]
        or      si,si
        jz      .e
        call    put_sep
.cp:    mov     al,[si]
        call    is_delim
        je      .e
        stosb
        inc     si
        jmp     .cp
.e:     call    put_crlf_out
        jmp     exit_err
err_nparm:
        mov     dx,msg_nparm
        call    puts
        jmp     exit_err
err_drive:
        mov     dx,msg_drive
        call    puts
        jmp     exit_err
err_path:
        mov     si,msg_path
        call    msg_spec
        jmp     exit_err
help:
        mov     dx,msg_help
        call    puts
exit_ok:
        mov     ax,4C00h
        int     21h
exit_err:
        mov     ax,4C01h
        int     21h

; Escriu missatge SI + " - " + spec (com l'ha escrit l'usuari)
msg_spec:
        mov     di,linebuf
        call    put_str
        call    put_sep
        mov     si,spec
        call    put_str
; Afegeix CRLF a linebuf..DI i ho escriu
put_crlf_out:
        mov     ax,0A0Dh
        stosw
        mov     byte [di],0
        mov     dx,linebuf
        jmp     puts

; ---------------------------------------------------------------------
;  Processa el directori [path] i, amb /S, els subdirectoris
; ---------------------------------------------------------------------
do_dir:
        push    bp
        mov     al,[level]
        mov     ah,DTASZ
        mul     ah
        add     ax,dtas
        mov     bp,ax

        ; 1) entrades que coincideixen amb el nom
        mov     dx,bp
        mov     ah,1Ah
        int     21h
        mov     si,fname
        call    set_pattern
        mov     dx,path
        mov     cx,A_HID+A_SYS+A_DIR
        mov     ah,4Eh
        int     21h
        jnc     .f1
        cmp     byte [level],0
        jne     .phase2
        cmp     ax,3                    ; ruta inexistent al nivell 0
        jne     .phase2
        mov     byte [patherr],1
        jmp     .done
.f1:    cmp     byte [bp+1Eh],'.'
        je      .n1
        test    byte [bp+15h],A_DIR
        jz      .file
        cmp     byte [wild],0           ; directoris nom‚s pel nom exacte
        jne     .n1
.file:  call    do_entry
.n1:    mov     dx,bp
        mov     ah,1Ah
        int     21h
        mov     ah,4Fh
        int     21h
        jnc     .f1

        ; 2) subdirectoris (/S)
.phase2:
        cmp     byte [recurse],0
        je      .done
        cmp     byte [level],MAXLVL-1
        jae     .done
        mov     dx,bp
        mov     ah,1Ah
        int     21h
        mov     si,starstar
        call    set_pattern
        mov     dx,path
        mov     cx,A_HID+A_SYS+A_DIR
        mov     ah,4Eh
        int     21h
        jc      .done
.f2:    test    byte [bp+15h],A_DIR
        jz      .n2
        cmp     byte [bp+1Eh],'.'
        je      .n2
        mov     di,path
        add     di,[pathlen]
        lea     si,[bp+1Eh]
        call    put_str
        mov     al,'\'
        stosb
        mov     ax,di
        sub     ax,path
        cmp     ax,PATHMAX
        ja      .n2
        push    word [pathlen]
        mov     [pathlen],ax
        inc     byte [level]
        call    do_dir
        dec     byte [level]
        pop     word [pathlen]
.n2:    mov     dx,bp
        mov     ah,1Ah
        int     21h
        mov     ah,4Fh
        int     21h
        jnc     .f2
.done:  pop     bp
        ret

set_pattern:                            ; SI -> path+pathlen (ASCIIZ)
        mov     di,path
        add     di,[pathlen]
.l:     lodsb
        stosb
        or      al,al
        jnz     .l
        ret

; ---------------------------------------------------------------------
;  Una entrada (DTA a [BP]): mostra o canvia atributs
; ---------------------------------------------------------------------
do_entry:
        inc     word [found]
        ; ruta completa a fpath
        mov     di,fpath
        mov     si,path
        mov     cx,[pathlen]
        rep     movsb
        lea     si,[bp+1Eh]
        call    put_str
        mov     byte [di],0

        mov     bl,[bp+15h]             ; atributs actuals
        cmp     byte [chgm],0
        jne     .change

        ; --- mostra:  "A  SHR     C:\RUTA\NOM" ---
        mov     di,linebuf
        mov     al,' '
        test    bl,A_ARC
        jz      .a
        mov     al,'A'
.a:     stosb
        mov     ax,'  '
        stosw
        mov     al,' '
        test    bl,A_SYS
        jz      .s
        mov     al,'S'
.s:     stosb
        mov     al,' '
        test    bl,A_HID
        jz      .h
        mov     al,'H'
.h:     stosb
        mov     al,' '
        test    bl,A_RDO
        jz      .r
        mov     al,'R'
.r:     stosb
        mov     ax,'  '
        stosw
        stosw
        stosb
        mov     si,fpath
        call    put_str
        jmp     put_crlf_out

        ; --- canvia ---
.change:
        test    bl,A_SYS                ; protecci¢ com a MS-DOS 5
        jz      .nosys
        test    byte [chgm],A_SYS
        jnz     .nosys
        mov     si,msg_nosys
        jmp     .refuse
.nosys: test    bl,A_HID
        jz      .apply
        test    byte [chgm],A_SYS+A_HID
        jnz     .apply
        mov     si,msg_nohid
.refuse:
        mov     di,linebuf
        call    put_str
        call    put_sep
        mov     si,fpath
        call    put_str
        jmp     put_crlf_out
.apply: mov     cl,bl
        and     cl,A_RDO+A_HID+A_SYS+A_ARC
        or      cl,[setm]
        mov     al,[clrm]
        not     al
        and     cl,al
        xor     ch,ch
        mov     dx,fpath
        mov     ax,4301h
        int     21h
        jnc     .ok
        mov     si,msg_denied
        jmp     .refuse
.ok:    ret

; ---------------------------------------------------------------------
;  Utilitats
; ---------------------------------------------------------------------
skip_delim:                             ; salta separadors, AL = 1r car…cter
        mov     al,[si]
        call    is_delim
        jne     .x
        cmp     al,13
        je      .x
        inc     si
        jmp     skip_delim
.x:     ret

is_delim:                               ; ZF=1 si AL ‚s separador o CR
        cmp     al,' '
        je      .x
        cmp     al,9
        je      .x
        cmp     al,','
        je      .x
        cmp     al,';'
        je      .x
        cmp     al,'='
        je      .x
        cmp     al,13
.x:     ret

upcase:
        cmp     al,'a'
        jb      .x
        cmp     al,'z'
        ja      .x
        sub     al,20h
.x:     ret

put_str:                                ; SI ASCIIZ -> DI
        lodsb
        or      al,al
        jz      .x
        stosb
        jmp     put_str
.x:     ret

put_sep:                                ; " - "
        mov     al,' '
        stosb
        mov     ax,'- '
        stosw
        ret

puts:                                   ; DX ASCIIZ -> STDOUT
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
;  Dades (missatges en castell…, CP437)
; ---------------------------------------------------------------------
msg_ver     db  "Versi¢n incorrecta de DOS",13,10,0
msg_parm    db  "Par metro no v lido",0
msg_nparm   db  "N£mero de par metros no v lido",13,10,0
msg_drive   db  "Especificaci¢n de unidad no v lida",13,10,0
msg_path    db  "Trayectoria no v lida",0
msg_nf      db  "Archivo no encontrado",0
msg_nosys   db  "No se restablece el archivo de sistema",0
msg_nohid   db  "No se restablece el archivo oculto",0
msg_denied  db  "Acceso denegado",0
msg_help    db  "Muestra o cambia los atributos de los archivos.",13,10,13,10
            db  "ATTRIB [+R | -R] [+A | -A] [+S | -S] [+H | -H] [[unidad:][ruta]nombre] [/S]",13,10,13,10
            db  "  +   Establece un atributo.",13,10
            db  "  -   Elimina un atributo.",13,10
            db  "  R   Atributo de archivo de s¢lo lectura.",13,10
            db  "  A   Atributo de archivo de almacenamiento.",13,10
            db  "  S   Atributo de archivo de sistema.",13,10
            db  "  H   Atributo de archivo oculto.",13,10
            db  "  /S  Procesa los archivos de todos los directorios de la ruta",13,10
            db  "      especificada.",13,10,0
starstar    db  "*.*",0

setm        db  0
clrm        db  0
chgm        db  0
recurse     db  0
wild        db  0
havespec    db  0
patherr     db  0
level       db  0
found       dw  0
tokstart    dw  0
spec        times PATHMAX db 0

        section .bss
        alignb  2
pathlen     resw 1
fname       resb 16
tmp         resb 144
path        resb 144
fpath       resb 144
linebuf     resb 200
dtas        resb MAXLVL*DTASZ
            resb 1024
stack_top:
