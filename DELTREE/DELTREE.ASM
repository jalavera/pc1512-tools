; =====================================================================
;  DELTREE.ASM  -  DELTREE.COM 0.1 per a MS-DOS 3.20 o superior (8086)
;
;  Clon del DELTREE de MS-DOS 6.22 (missatges en castell…):
;
;     DELTREE [/Y] [unidad:]ruta [[unidad:]ruta[...]]
;
;  - Esborra directoris amb tots els seus arxius i subdirectoris,
;    o arxius solts. Admet comodins a l'£ltim element de la ruta
;    (DELTREE C:\TEMP\*.* buida TEMP per• el conserva).
;  - Esborra tamb‚ arxius i directoris ocults, de sistema i de nom‚s
;    lectura (els treu els atributs abans d'esborrar-los).
;  - Demana confirmaci¢ per a cada element trobat, si no hi ha /Y.
;  - No deixa esborrar el directori arrel ni el directori actual
;    (ni cap directori que el contingui).
;
;  Compilar:  nasm -f bin DELTREE.ASM -o DELTREE.COM
; =====================================================================

        cpu     8086
        org     100h

MAXLVL  equ     32              ; profunditat m…xima de subdirectoris
DTASZ   equ     43
PATHMAX equ     124             ; longitud m…xima de ruta
MAXSPEC equ     16              ; rutes per l¡nia d'ordres
SPECSZ  equ     80

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

        ; ---- l¡nia d'ordres ----
        mov     si,81h
.tok:   lodsb
        call    is_delim
        je      .tok
        cmp     al,13
        je      .parsed
        cmp     al,'/'
        jne     .spec
        ; opci¢
        mov     [swpos],si
        lodsb
        cmp     al,'?'
        je      help
        call    upcase
        cmp     al,'Y'
        jne     err_parm
        mov     byte [yesall],1
        mov     al,[si]
        cmp     al,'/'
        je      .tok
        call    is_delim
        je      .tok
        cmp     al,13
        je      .tok
        jmp     err_parm
.spec:  ; ruta: es copia (en maj£scules) a la seva pr•pia mem•ria
        mov     bl,[nspec]
        cmp     bl,MAXSPEC
        jb      .room
        mov     dx,msg_many
        call    puts
        jmp     exit_err
.room:  mov     al,SPECSZ
        mul     bl
        add     ax,specs
        mov     di,ax
        mov     cx,SPECSZ-1
        dec     si
.sc:    lodsb
        call    is_delim
        je      .send
        cmp     al,13
        je      .send
        cmp     al,'/'
        je      .send
        call    upcase
        jcxz    .sc                     ; massa llarg: es talla
        stosb
        dec     cx
        jmp     .sc
.send:  dec     si
        mov     byte [di],0
        inc     byte [nspec]
        jmp     .tok

.parsed:
        cmp     byte [nspec],0
        jne     .run
        mov     dx,msg_noparm
        call    puts
        jmp     exit_err
.run:   xor     bx,bx
.each:  push    bx
        mov     al,SPECSZ
        mul     bl
        add     ax,specs
        mov     [curspec],ax
        call    do_spec
        pop     bx
        inc     bx
        cmp     bl,[nspec]
        jb      .each
        cmp     byte [errors],0
        jne     exit_err
        mov     ax,4C00h
        int     21h

help:
        mov     dx,msg_help
        call    puts
        mov     ax,4C00h
        int     21h
err_parm:
        mov     di,linebuf
        mov     si,msg_parm
        call    put_str
        call    put_sep
        mov     si,[swpos]
        dec     si
.c:     lodsb
        call    is_delim
        je      .e
        cmp     al,13
        je      .e
        stosb
        jmp     .c
.e:     call    out_line
exit_err:
        mov     ax,4C01h
        int     21h

; ---------------------------------------------------------------------
;  Processa una ruta de la l¡nia d'ordres ([curspec])
; ---------------------------------------------------------------------
do_spec:
        mov     si,[curspec]
        ; treu una '\' final (TEMP\ -> TEMP), excepte a l'arrel
        mov     di,si
.ln:    cmp     byte [di],0
        je      .lnend
        inc     di
        jmp     .ln
.lnend: mov     ax,di
        sub     ax,si
        cmp     ax,2
        jb      .nosl
        cmp     byte [di-1],'\'
        jne     .nosl
        cmp     byte [di-2],':'
        je      .nosl
        mov     byte [di-1],0
.nosl:
        ; separa directori i nom (darrer '\' o ':')
        mov     bx,si
.sp:    lodsb
        or      al,al
        jz      .spend
        cmp     al,'\'
        je      .sep
        cmp     al,':'
        jne     .sp
.sep:   mov     bx,si
        jmp     .sp
.spend: cmp     byte [bx],0             ; sense nom: ‚s l'arrel (o "C:")
        jne     .hasname
        mov     si,msg_root
        jmp     spec_error
.hasname:
        mov     [nameptr],bx
        ; path = part de directori
        mov     si,[curspec]
        mov     di,path
        mov     cx,bx
        sub     cx,si
        mov     [dirlen],cx
        rep     movsb
        mov     [pathlen],di
        sub     word [pathlen],path

        ; cerca les coincidŠncies (arxius de tota mena i directoris)
        mov     byte [level],0
        mov     dx,dtas
        mov     ah,1Ah
        int     21h
        mov     si,[nameptr]
        call    set_pattern
        mov     dx,path
        mov     cx,16h
        mov     ah,4Eh
        int     21h
        jnc     .found
        cmp     ax,3
        jne     .nf
        mov     si,msg_path
        jmp     spec_error
.nf:    mov     si,msg_nf
        jmp     spec_error

.found: mov     byte [anyfound],0
.loop:  cmp     byte [dtas+1Eh],'.'     ; "." i ".."
        je      .next
        mov     byte [anyfound],1
        ; path = directori + nom trobat
        mov     di,path
        add     di,[dirlen]
        mov     si,dtas+1Eh
        call    put_str
        mov     byte [di],0
        mov     ax,di
        sub     ax,path
        mov     [pathlen],ax
        test    byte [dtas+15h],10h
        jz      .file
        ; --- directori ---
        call    check_cwd
        jnc     .dirok
        mov     si,msg_cwd
        call    path_error
        jmp     .next
.dirok: cmp     byte [yesall],0
        jne     .ddel
        mov     si,msg_qd1
        mov     bx,msg_qd2
        call    ask
        jne     .next
.ddel:  call    show_deleting
        mov     byte [level],0
        call    deltree_dir
        mov     bx,[pathlen]
        mov     byte [path+bx],0
        call    remove_dir
        jmp     .next
        ; --- arxiu ---
.file:  cmp     byte [yesall],0
        jne     .fdel
        mov     si,msg_qf1
        mov     bx,msg_qf2
        call    ask
        jne     .next
.fdel:  call    show_deleting
        mov     al,[dtas+15h]
        call    remove_file
.next:  mov     dx,dtas
        mov     ah,1Ah
        int     21h
        mov     ah,4Fh
        int     21h
        jnc     .loop
        cmp     byte [anyfound],0
        jne     .r
        mov     si,msg_nf
        jmp     spec_error
.r:     ret

; Missatge SI + " - " + ruta tal com s'ha escrit
spec_error:
        mov     byte [errors],1
        mov     di,linebuf
        call    put_str
        call    put_sep
        mov     si,[curspec]
        call    put_str
        jmp     out_line

; Missatge SI + " - " + [path]
path_error:
        mov     byte [errors],1
        mov     di,linebuf
        call    put_str
        call    put_sep
        mov     si,path
        call    put_str
        jmp     out_line

show_deleting:
        mov     di,linebuf
        mov     si,msg_deling
        call    put_str
        mov     si,path
        call    put_str
        mov     si,msg_dots
        call    put_str
        jmp     out_line

; ---------------------------------------------------------------------
;  Esborra recursivament el contingut del directori [path] ([pathlen])
; ---------------------------------------------------------------------
deltree_dir:
        push    bp
        inc     byte [level]
        cmp     byte [level],MAXLVL
        jb      .lvok
        mov     si,msg_deep
        call    path_error
        jmp     .out
.lvok:  mov     al,[level]
        mov     ah,DTASZ
        mul     ah
        add     ax,dtas
        mov     bp,ax
        ; path + '\'
        mov     bx,[pathlen]
        cmp     bx,PATHMAX
        jb      .lenok
        mov     si,msg_deep
        call    path_error
        jmp     .out
.lenok: mov     byte [path+bx],'\'
        inc     bx
        mov     [pathlen],bx
        mov     dx,bp
        mov     ah,1Ah
        int     21h
        mov     si,starstar
        call    set_pattern
        mov     dx,path
        mov     cx,16h
        mov     ah,4Eh
        int     21h
        jc      .done
.l:     cmp     byte [bp+1Eh],'.'
        je      .n
        ; path + nom
        mov     di,path
        add     di,[pathlen]
        lea     si,[bp+1Eh]
        call    put_str
        mov     byte [di],0
        test    byte [bp+15h],10h
        jz      .f
        ; subdirectori
        mov     ax,di
        sub     ax,path
        push    word [pathlen]
        push    ax
        mov     [pathlen],ax
        call    deltree_dir
        pop     bx
        mov     byte [path+bx],0
        call    remove_dir
        pop     word [pathlen]
        jmp     .n
.f:     mov     al,[bp+15h]
        call    remove_file
.n:     mov     dx,bp
        mov     ah,1Ah
        int     21h
        mov     ah,4Fh
        int     21h
        jnc     .l
.done:  dec     word [pathlen]          ; treu la '\' afegida
.out:   dec     byte [level]
        pop     bp
        ret

; Esborra l'arxiu [path]; AL = atributs actuals
remove_file:
        test    al,07h                  ; R, H o S: primer els treu
        jz      .del
        mov     dx,path
        xor     cx,cx
        mov     ax,4301h
        int     21h
.del:   mov     dx,path
        mov     ah,41h
        int     21h
        jnc     .r
        mov     si,msg_denied
        call    path_error
.r:     ret

; Esborra el directori buit [path]
remove_dir:
        mov     dx,path
        mov     ah,3Ah
        int     21h
        jnc     .r
        mov     dx,path                 ; potser ‚s de nom‚s lectura/ocult
        xor     cx,cx
        mov     ax,4301h
        int     21h
        mov     dx,path
        mov     ah,3Ah
        int     21h
        jnc     .r
        mov     si,msg_denied
        call    path_error
.r:     ret

; CF=1 si [path] ‚s l'arrel, el directori actual o en cont‚ l'actual
check_cwd:
        mov     si,path
        mov     di,tn1
        mov     ah,60h                  ; TRUENAME (DOS 3.0+)
        int     21h
        jc      .no
        ; directori actual de la mateixa unitat: TRUENAME de "X:."
        mov     al,[tn1]
        mov     [curdot],al
        mov     si,curdot
        mov     di,tn2
        mov     ah,60h
        int     21h
        jc      .no
        mov     si,tn1
        mov     di,tn2
.c:     mov     al,[si]
        or      al,al
        jz      .end1
        cmp     al,[di]
        jne     .no
        inc     si
        inc     di
        jmp     .c
.end1:  mov     ax,si                   ; tn1 = arrel?
        sub     ax,tn1
        cmp     ax,3
        jbe     .yes
        mov     al,[di]                 ; tn2 continua amb 0 o '\'?
        or      al,al
        jz      .yes
        cmp     al,'\'
        je      .yes
.no:    clc
        ret
.yes:   stc
        ret

; Pregunta SI + [path] + BX.  ZF=1 si la resposta ‚s s¡
ask:
        mov     di,linebuf
        call    put_str
        mov     si,path
        call    put_str
        mov     si,bx
        call    put_str
        mov     byte [di],0
        mov     dx,linebuf
        call    puts
.k:     mov     ah,08h
        int     21h
        or      al,al
        jnz     .chk
        mov     ah,08h
        int     21h
        jmp     .k
.chk:   call    upcase
        cmp     al,'S'
        je      .yes
        cmp     al,'Y'
        je      .yes
        cmp     al,'N'
        jne     .k
        mov     dx,ans_n
        call    puts
        or      al,1
        ret
.yes:   mov     dx,ans_s
        call    puts
        cmp     al,al
        ret

; Copia el patr¢ SI a path+pathlen
set_pattern:
        mov     di,path
        add     di,[pathlen]
.l:     lodsb
        stosb
        or      al,al
        jnz     .l
        ret

; ---------------------------------------------------------------------
;  Utilitats
; ---------------------------------------------------------------------
is_delim:                               ; ZF=1 si AL ‚s separador
        cmp     al,' '
        je      .x
        cmp     al,9
        je      .x
        cmp     al,','
        je      .x
        cmp     al,';'
        je      .x
        cmp     al,'='
.x:     ret

upcase:
        cmp     al,'a'
        jb      .x
        cmp     al,'z'
        ja      .x
        sub     al,20h
.x:     ret

put_str:
        lodsb
        or      al,al
        jz      .x
        stosb
        jmp     put_str
.x:     ret

put_sep:
        mov     al,' '
        stosb
        mov     ax,'- '
        stosw
        ret

out_line:                               ; linebuf..DI + CRLF -> pantalla
        mov     ax,0A0Dh
        stosw
        mov     byte [di],0
        mov     dx,linebuf
puts:                                   ; DX ASCIIZ -> STDOUT
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
;  Dades (missatges en castell…, CP437)
; ---------------------------------------------------------------------
msg_ver     db  "Versi¢n incorrecta de DOS",13,10,0
msg_help    db  "Elimina un directorio y todos sus subdirectorios y archivos.",13,10,13,10
            db  "Para eliminar uno o m s archivos y directorios:",13,10
            db  "DELTREE [/Y] [unidad:]ruta [[unidad:]ruta[...]]",13,10,13,10
            db  "  /Y              Suprime la petici¢n de confirmaci¢n para eliminar",13,10
            db  "                  el subdirectorio.",13,10
            db  "  [unidad:]ruta   Especifica el nombre del directorio que desea eliminar.",13,10,13,10
            db  "Nota: Use DELTREE con precauci¢n. Se eliminar n todos los archivos y",13,10
            db  "subdirectorios del directorio especificado.",13,10,0
msg_noparm  db  "Falta un par metro obligatorio",13,10,0
msg_many    db  "Demasiados par metros",13,10,0
msg_parm    db  "Par metro no v lido",0
msg_root    db  "No se puede eliminar el directorio ra¡z",0
msg_cwd     db  "Intento de quitar el directorio actual",0
msg_nf      db  "No se encontr¢ el archivo",0
msg_path    db  "Ruta no v lida",0
msg_denied  db  "Acceso denegado",0
msg_deep    db  "Ruta demasiado larga",0
msg_qd1     db  168,"Eliminar el directorio ",34,0
msg_qd2     db  34," y todos sus subdirectorios? [S/N] ",0
msg_qf1     db  168,"Eliminar el archivo ",34,0
msg_qf2     db  34,"? [S/N] ",0
msg_deling  db  "Eliminando ",0
msg_dots    db  "...",0
ans_s       db  "S",13,10,0
ans_n       db  "N",13,10,0
starstar    db  "*.*",0
curdot      db  "?:.",0

yesall      db  0
errors      db  0
nspec       db  0
level       db  0
anyfound    db  0

        section .bss
        alignb  2
swpos       resw 1
curspec     resw 1
nameptr     resw 1
dirlen      resw 1
pathlen     resw 1
specs       resb MAXSPEC*SPECSZ
path        resb 160
tn1         resb 130
tn2         resb 130
linebuf     resb 256
dtas        resb (MAXLVL+1)*DTASZ
            resb 1024
stack_top:
