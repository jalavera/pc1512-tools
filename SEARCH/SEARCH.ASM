; =====================================================================
;  SEARCH.ASM  -  SEARCH.COM per a MS-DOS 3.20 (8086/8088, Amstrad PC1512)
;
;  Cerca un nom d'arxiu (admet comodins * i ?) a totes les unitats A..Z
;  accessibles i a tots els directoris, inclosos arxius i directoris
;  ocults i de sistema. Per a cada coincidŠncia mostra:
;
;     RUTA - MIDA - DATA - HORA - HSRA - CRC32
;
;  Al final pregunta si es vol desar la sortida en un .TXT; si ‚s que s¡,
;  demana directori i nom, l'escriu, el torna a llegir i en verifica
;  la mida i el CRC32.
;
;  - Gestor INT 24h propi: respon "Fail" autom…ticament, de manera que
;    les unitats buides o no preparades se salten sense preguntes.
;  - Unitats compartides (B: fantasma en sistemes d'una sola disquetera):
;    s'usa IOCTL 440Eh/440Fh per evitar el missatge "Insert diskette for
;    drive B:" i no explorar dues vegades el mateix disc.
;
;  Compilar:  nasm -f bin SEARCH.ASM -o SEARCH.COM
; =====================================================================

        cpu     8086
        org     100h

MAXLVL  equ     32              ; profunditat m…xima de directoris
DTASZ   equ     43              ; mida d'un DTA
RBUFSZ  equ     8192            ; buffer de lectura per al CRC
PATHMAX equ     118             ; longitud m…xima de la ruta de treball
CHUNK   equ     8000h           ; bloc d'escriptura del TXT (32 KB)

; ---------------------------------------------------------------------
start:
        mov     ah,30h                  ; versi¢ de DOS
        int     21h
        cmp     al,3
        jae     .verok
        mov     dx,msg_ver
        call    puts
        mov     ax,4C01h
        int     21h
.verok:
        mov     sp,stack_top            ; pila pr•pia dins del programa
        cld

        ; Redueix el bloc de mem•ria del programa al m¡nim necessari
        mov     bx,prog_end+15
        mov     cl,4
        shr     bx,cl
        mov     ah,4Ah                  ; ES = PSP
        int     21h

        ; ---- Llegeix el par…metre ----
        mov     si,81h
.skip:  lodsb
        cmp     al,' '
        je      .skip
        cmp     al,9
        je      .skip
        cmp     al,13
        je      usage
        cmp     al,'/'
        je      usage
        dec     si
        mov     di,argbuf
.cp:    lodsb
        cmp     al,' '
        jbe     .cpend                  ; espai, tab o CR
        cmp     al,'\'
        je      .sep
        cmp     al,':'
        je      .sep
        cmp     al,'a'
        jb      .st
        cmp     al,'z'
        ja      .st
        sub     al,20h
.st:    cmp     di,argbuf+12
        jae     .cp                     ; talla noms massa llargs
        stosb
        jmp     .cp
.sep:   mov     di,argbuf               ; nom‚s ens quedem amb el nom final
        jmp     .cp
.cpend: cmp     di,argbuf
        je      usage
        mov     byte [di],0

        ; ---- Gestor d'errors cr¡tics (INT 24h -> Fail) ----
        ; DOS restaura el vector original en acabar (es desa al PSP).
        mov     dx,int24
        mov     ax,2524h
        int     21h

        ; ---- Mem•ria per guardar la sortida (per al TXT) ----
        mov     bx,0FFFFh
        mov     ah,48h
        int     21h                     ; falla i retorna BX = m…xim lliure
        jnc     .gotmem
        cmp     bx,16
        jb      .nomem
        mov     ah,48h
        int     21h
        jc      .nomem
.gotmem:
        mov     [bufseg],ax
        mov     [bufcurseg],ax
        mov     ax,bx                   ; capacitat = BX * 16 (32 bits)
        mov     dx,bx
        mov     cl,4
        shl     ax,cl
        mov     cl,12
        shr     dx,cl
        mov     [caplo],ax
        mov     [caphi],dx
.nomem:

        ; ---- Taula CRC32 (polinomi EDB88320h) ----
        mov     di,crctab
        xor     cx,cx
.tn:    mov     ax,cx
        xor     dx,dx
        mov     bl,8
.tb:    shr     dx,1
        rcr     ax,1
        jnc     .tz
        xor     dx,0EDB8h
        xor     ax,8320h
.tz:    dec     bl
        jnz     .tb
        mov     [di],ax
        mov     [di+2],dx
        add     di,4
        inc     cx
        cmp     cx,256
        jb      .tn

        ; ---- Cap‡alera ----
        mov     si,msg_hdr1
        call    emit_z
        mov     si,argbuf
        call    emit_z
        mov     si,crlf
        call    emit_z
        mov     si,msg_hdr2
        call    emit_z

        ; ---- Recorre les unitats A..Z ----
        mov     byte [drive],1
.dl:    call    scan_drive
        inc     byte [drive]
        cmp     byte [drive],26
        jbe     .dl

        ; ---- Peu ----
        mov     di,linebuf
        mov     si,msg_tot1
        call    put_str
        mov     ax,[found]
        xor     dx,dx
        call    put_dec32
        mov     si,msg_tot2
        call    put_str
        mov     cx,di
        sub     cx,linebuf
        mov     si,linebuf
        call    emit

        cmp     byte [overflow],0
        je      ask_save
        mov     dx,msg_ovf
        call    puts

; ---------------------------------------------------------------------
;  Pregunta si es vol desar la sortida
; ---------------------------------------------------------------------
ask_save:
        mov     dx,msg_ask
        call    ask_yn
        jne     exit_ok                 ; NO -> surt
        cmp     word [bufseg],0
        jne     get_dir
        mov     dx,msg_nomem
        call    puts
        jmp     exit_err

get_dir:
        mov     dx,msg_dir
        call    puts
        mov     dx,inbuf
        mov     ah,0Ah
        int     21h
        mov     dx,crlf
        call    puts
        mov     si,inbuf
        mov     di,outname
        call    copy_input
        cmp     di,outname
        je      .noslash
        mov     al,[di-1]
        cmp     al,'\'
        je      .noslash
        cmp     al,':'
        je      .noslash
        mov     al,'\'
        stosb
.noslash:
        mov     [namestart],di

get_name:
        mov     dx,msg_name
        call    puts
        mov     dx,inbuf
        mov     ah,0Ah
        int     21h
        mov     dx,crlf
        call    puts
        mov     si,inbuf
        mov     di,[namestart]
        call    copy_input
        cmp     di,[namestart]
        je      get_name                ; nom buit: torna a preguntar
        ; si el nom no t‚ extensi¢, afegeix .TXT
        mov     si,[namestart]
.ext:   cmp     si,di
        jae     .addext
        lodsb
        cmp     al,'.'
        je      .hasext
        jmp     .ext
.addext:
        mov     si,txt_ext
        call    put_str
.hasext:
        mov     byte [di],0

        ; ---- Crea el fitxer ----
        mov     dx,outname
        xor     cx,cx
        mov     ah,3Ch
        int     21h
        jnc     .created
        push    ax
        mov     di,linebuf
        mov     si,msg_cerr
        call    put_str
        pop     ax
        xor     dx,dx
        call    put_dec32
        mov     si,msg_cerr2
        call    put_str
        mov     byte [di],0
        mov     dx,linebuf
        call    puts
        jmp     retry
.created:
        mov     [wfh],ax

        ; ---- Escriu el contingut del buffer (blocs de 32 KB) ----
        mov     word [crclo],0FFFFh
        mov     word [crchi],0FFFFh
        mov     ax,[bufseg]
        mov     [wseg],ax
        mov     ax,[usedlo]
        mov     [remlo],ax
        mov     ax,[usedhi]
        mov     [remhi],ax
.wl:    mov     ax,[remlo]
        or      ax,[remhi]
        jz      .wdone
        mov     cx,CHUNK
        cmp     word [remhi],0
        jne     .full
        cmp     [remlo],cx
        jae     .full
        mov     cx,[remlo]
.full:  push    cx
        mov     es,[wseg]
        xor     si,si
        call    crc_update              ; CRC del que s'escriu
        push    ds
        pop     es
        pop     cx
        mov     bx,[wfh]
        push    ds
        mov     ds,[wseg]
        xor     dx,dx
        mov     ah,40h
        int     21h
        pop     ds
        jc      .werr
        cmp     ax,cx
        jne     .werr                   ; disc ple
        sub     [remlo],cx
        sbb     word [remhi],0
        add     word [wseg],CHUNK/16
        jmp     .wl
.wdone:
        mov     bx,[wfh]
        mov     ah,3Eh
        int     21h
        jc      .werr2
        mov     ax,[crclo]
        not     ax
        mov     [bcrclo],ax
        mov     ax,[crchi]
        not     ax
        mov     [bcrchi],ax

        ; ---- Verificaci¢: torna a llegir i compara mida i CRC32 ----
        mov     dx,outname
        call    crc_file
        jc      .verr
        cmp     ax,[bcrclo]
        jne     .verr
        cmp     dx,[bcrchi]
        jne     .verr
        mov     ax,[rsizelo]
        cmp     ax,[usedlo]
        jne     .verr
        mov     ax,[rsizehi]
        cmp     ax,[usedhi]
        jne     .verr

        mov     di,linebuf
        mov     si,msg_ok1
        call    put_str
        mov     si,outname
        call    put_str
        mov     si,msg_ok2
        call    put_str
        mov     ax,[usedlo]
        mov     dx,[usedhi]
        call    put_dec32
        mov     si,msg_ok3
        call    put_str
        mov     ax,[bcrclo]
        mov     dx,[bcrchi]
        call    put_hex32
        mov     si,msg_ok4
        call    put_str
        mov     byte [di],0
        mov     dx,linebuf
        call    puts
        jmp     exit_ok

.werr:  mov     bx,[wfh]
        mov     ah,3Eh
        int     21h
.werr2: mov     dx,outname              ; esborra el fitxer incomplet
        mov     ah,41h
        int     21h
        mov     dx,msg_werr
        call    puts
        jmp     retry
.verr:  mov     dx,msg_verr
        call    puts
        jmp     retry

retry:
        mov     dx,msg_retry
        call    ask_yn
        jne     exit_err
        jmp     get_dir

usage:
        mov     dx,msg_usage
        call    puts
exit_err:
        mov     ax,4C01h
        int     21h
exit_ok:
        mov     ax,4C00h
        int     21h

; ---------------------------------------------------------------------
;  INT 24h: retorna Fail (o Ignore si Fail no est… permŠs)
; ---------------------------------------------------------------------
int24:
        test    ah,08h                  ; Fail permŠs?
        jz      .nofail
        mov     al,3
        iret
.nofail:
        test    ah,20h                  ; Ignore permŠs?
        jz      .abort
        xor     al,al
        iret
.abort: mov     al,3
        iret

; ---------------------------------------------------------------------
;  Explora la unitat [drive] (1 = A:)
; ---------------------------------------------------------------------
scan_drive:
        mov     bl,[drive]
        mov     ax,440Eh                ; mapa d'unitats l•giques (DOS 3.2+)
        int     21h
        jnc     .mapok
        cmp     ax,0Fh                  ; unitat no v…lida -> no existeix
        je      .ret
        jmp     .single                 ; funci¢ no suportada: explora
.mapok: or      al,al
        jz      .single                 ; unitat no compartida
        ; Unitat compartida (p.ex. A:/B: amb una sola disquetera)
        xor     bh,bh
        mov     bl,al                   ; propiet…ria actual
        cmp     byte [owned+bx],0
        jne     .ret                    ; aquest disc ja s'ha explorat
        mov     bl,[drive]
        mov     ax,440Fh                ; fes aquesta lletra propiet…ria
        int     21h                     ; (evita "Insert diskette for B:")
        xor     bh,bh
        mov     bl,[drive]
        mov     byte [owned+bx],1
.single:
        mov     al,[drive]
        add     al,'@'
        mov     [path],al
        mov     word [path+1],'\' * 256 + ':'
        mov     word [pathlen],3
        mov     [msg_stat_drv],al

        mov     dx,msg_stat             ; estat temporal (per STDERR)
        mov     bx,2
        call    hputs
        mov     byte [statshown],1

        ; Prova: hi ha disc i es pot llegir?
        mov     dx,dtas
        mov     ah,1Ah
        int     21h
        mov     si,starstar
        call    set_pattern
        mov     dx,path
        mov     cx,16h
        mov     ah,4Eh
        int     21h
        jnc     .ok
        cmp     ax,2
        je      .ok
        cmp     ax,3
        je      .ok
        cmp     ax,12h
        je      .ok
        jmp     .done                   ; sense disc / no preparada
.ok:    mov     byte [level],0
        call    scan_dir
.done:  call    clear_status
.ret:   ret

; ---------------------------------------------------------------------
;  Explora recursivament el directori [path] (acaba en '\')
; ---------------------------------------------------------------------
scan_dir:
        push    bp
        mov     al,[level]
        mov     ah,DTASZ
        mul     ah
        add     ax,dtas
        mov     bp,ax                   ; BP = DTA d'aquest nivell

        ; 1) arxius que coincideixen (normals, ocults, sistema, R/O)
        mov     dx,bp
        mov     ah,1Ah
        int     21h
        mov     si,argbuf
        call    set_pattern
        mov     dx,path
        mov     cx,07h
        mov     ah,4Eh
        int     21h
        jc      .phase2
.f1:    call    report
        mov     dx,bp
        mov     ah,1Ah
        int     21h
        mov     ah,4Fh
        int     21h
        jnc     .f1

        ; 2) subdirectoris (tamb‚ ocults i de sistema)
.phase2:
        cmp     byte [level],MAXLVL-1
        jae     .done
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
.f2:    test    byte [bp+15h],10h
        jz      .next
        cmp     byte [bp+1Eh],'.'
        je      .next
        ; afegeix NOM\ a la ruta
        mov     di,path
        add     di,[pathlen]
        lea     si,[bp+1Eh]
.an:    lodsb
        or      al,al
        jz      .anend
        stosb
        jmp     .an
.anend: mov     al,'\'
        stosb
        mov     ax,di
        sub     ax,path
        cmp     ax,PATHMAX
        ja      .next                   ; massa llarga: no hi entra
        push    word [pathlen]
        mov     [pathlen],ax
        inc     byte [level]
        call    scan_dir
        dec     byte [level]
        pop     word [pathlen]
.next:  mov     dx,bp
        mov     ah,1Ah
        int     21h
        mov     ah,4Fh
        int     21h
        jnc     .f2
.done:  pop     bp
        ret

; Copia el patr¢ SI (ASCIIZ) a path+pathlen
set_pattern:
        mov     di,path
        add     di,[pathlen]
.l:     lodsb
        stosb
        or      al,al
        jnz     .l
        ret

; ---------------------------------------------------------------------
;  Genera la l¡nia per a l'arxiu del DTA [BP]
; ---------------------------------------------------------------------
report:
        call    clear_status
        ; ruta completa
        mov     di,fpath
        mov     si,path
        mov     cx,[pathlen]
        rep     movsb
        lea     si,[bp+1Eh]
        call    put_str
        mov     byte [di],0

        mov     di,linebuf
        mov     si,fpath
        call    put_str
        call    put_sep
        ; mida
        mov     ax,[bp+1Ah]
        mov     dx,[bp+1Ch]
        call    put_dec32
        call    put_sep
        ; data DD/MM/AAAA
        mov     ax,[bp+18h]
        push    ax
        and     al,1Fh
        call    put2
        mov     al,'/'
        stosb
        pop     ax
        push    ax
        mov     cl,5
        shr     ax,cl
        and     al,0Fh
        call    put2
        mov     al,'/'
        stosb
        pop     ax
        mov     cl,9
        shr     ax,cl
        add     ax,1980
        mov     bl,100
        div     bl                      ; AL = segle, AH = any
        push    ax
        call    put2
        pop     ax
        mov     al,ah
        call    put2
        call    put_sep
        ; hora HH:MM:SS
        mov     ax,[bp+16h]
        push    ax
        mov     cl,11
        shr     ax,cl
        call    put2
        mov     al,':'
        stosb
        pop     ax
        push    ax
        mov     cl,5
        shr     ax,cl
        and     al,3Fh
        call    put2
        mov     al,':'
        stosb
        pop     ax
        and     al,1Fh
        shl     al,1
        call    put2
        call    put_sep
        ; atributs HSRA
        mov     bl,[bp+15h]
        mov     al,'H'
        mov     ah,02h
        call    put_flag
        mov     al,'S'
        mov     ah,04h
        call    put_flag
        mov     al,'R'
        mov     ah,01h
        call    put_flag
        mov     al,'A'
        mov     ah,20h
        call    put_flag
        call    put_sep
        ; CRC32
        push    di
        mov     dx,fpath
        call    crc_file
        pop     di
        jc      .crcerr
        call    put_hex32
        jmp     .eol
.crcerr:
        mov     si,msg_crcerr
        call    put_str
.eol:   mov     ax,0A0Dh
        stosw
        mov     cx,di
        sub     cx,linebuf
        mov     si,linebuf
        call    emit
        inc     word [found]
        ret

; AL = lletra, AH = m…scara, BL = atributs -> escriu lletra o '.'
put_flag:
        test    bl,ah
        jnz     .on
        mov     al,'.'
.on:    stosb
        ret

; ---------------------------------------------------------------------
;  CRC32 d'un fitxer.  DX = ruta ASCIIZ
;  Surt: CF=0 -> DX:AX = CRC32, [rsizelo/hi] = bytes llegits; CF=1 error
; ---------------------------------------------------------------------
crc_file:
        mov     ax,3D00h                ; obre nom‚s lectura
        int     21h
        jc      .r
        mov     [fh],ax
        mov     word [crclo],0FFFFh
        mov     word [crchi],0FFFFh
        mov     word [rsizelo],0
        mov     word [rsizehi],0
        push    ds
        pop     es
.rd:    mov     bx,[fh]
        mov     cx,RBUFSZ
        mov     dx,rbuf
        mov     ah,3Fh
        int     21h
        jc      .err
        or      ax,ax
        jz      .eof
        add     [rsizelo],ax
        adc     word [rsizehi],0
        mov     cx,ax
        mov     si,rbuf
        call    crc_update
        jmp     .rd
.eof:   mov     bx,[fh]
        mov     ah,3Eh
        int     21h
        mov     ax,[crclo]
        mov     dx,[crchi]
        not     ax
        not     dx
        clc
        ret
.err:   mov     bx,[fh]
        mov     ah,3Eh
        int     21h
        stc
.r:     ret

; Actualitza [crclo/crchi] amb CX bytes a ES:SI
crc_update:
        mov     ax,[crclo]
        mov     dx,[crchi]
        jcxz    .x
.l:     mov     bl,al
        xor     bl,[es:si]
        inc     si
        xor     bh,bh
        shl     bx,1
        shl     bx,1
        mov     al,ah
        mov     ah,dl
        mov     dl,dh
        xor     dh,dh
        xor     ax,[crctab+bx]
        xor     dx,[crctab+bx+2]
        loop    .l
.x:     mov     [crclo],ax
        mov     [crchi],dx
        ret

; ---------------------------------------------------------------------
;  Sortida
; ---------------------------------------------------------------------
; Escriu SI/CX a la pantalla (STDOUT) i ho afegeix al buffer del TXT
emit:
        push    si
        push    cx
        mov     dx,si
        mov     bx,1
        mov     ah,40h
        int     21h
        pop     cx
        pop     si
        ; afegeix al buffer
        cmp     word [bufseg],0
        je      .r
        cmp     byte [overflow],0
        jne     .r
        mov     ax,[usedlo]
        mov     dx,[usedhi]
        add     ax,cx
        adc     dx,0
        cmp     dx,[caphi]
        ja      .ovf
        jb      .fits
        cmp     ax,[caplo]
        ja      .ovf
.fits:  mov     [usedlo],ax
        mov     [usedhi],dx
        les     di,[bufoff]
        rep     movsb
        mov     ax,di                   ; normalitza el punter far
        mov     cl,4
        shr     ax,cl
        mov     bx,es
        add     bx,ax
        and     di,0Fh
        mov     [bufoff],di
        mov     [bufcurseg],bx
        push    ds
        pop     es
.r:     ret
.ovf:   mov     byte [overflow],1
        ret

; Emet una cadena ASCIIZ (SI)
emit_z:
        mov     di,si
        xor     cx,cx
.l:     cmp     byte [di],0
        je      .e
        inc     di
        inc     cx
        jmp     .l
.e:     jmp     emit

; Esborra la l¡nia d'estat temporal
clear_status:
        cmp     byte [statshown],0
        je      .r
        mov     byte [statshown],0
        mov     dx,msg_clr
        mov     bx,2
        call    hputs
.r:     ret

; DX = ASCIIZ -> STDOUT
puts:
        mov     bx,1
; DX = ASCIIZ, BX = handle
hputs:
        push    si
        push    cx
        mov     si,dx
        xor     cx,cx
.l:     cmp     byte [si],0
        je      .w
        inc     si
        inc     cx
        jmp     .l
.w:     jcxz    .x
        mov     ah,40h
        int     21h
.x:     pop     cx
        pop     si
        ret

; Pregunta S/N. DX = text. Surt amb ZF=1 si la resposta ‚s "si"
ask_yn:
        call    puts
.k:     mov     ah,08h
        int     21h
        or      al,al
        jnz     .chk
        mov     ah,08h                  ; tecla estesa: descarta-la
        int     21h
        jmp     .k
.chk:   and     al,0DFh
        cmp     al,'S'
        je      .yes
        cmp     al,'Y'
        je      .yes
        cmp     al,'N'
        jne     .k
        mov     dx,ans_no
        call    puts
        or      al,1                    ; ZF=0
        ret
.yes:   mov     dx,ans_yes
        call    puts
        cmp     al,al                   ; ZF=1
        ret

; Copia l'entrada de la funci¢ 0Ah (SI) a DI, sense espais i en maj£scules
copy_input:
        mov     cl,[si+1]
        xor     ch,ch
        add     si,2
        jcxz    .x
.l:     lodsb
        cmp     al,' '
        je      .n
        cmp     al,'a'
        jb      .s
        cmp     al,'z'
        ja      .s
        sub     al,20h
.s:     stosb
.n:     loop    .l
.x:     ret

; ---------------------------------------------------------------------
;  Formatadors (escriuen a ES:DI)
; ---------------------------------------------------------------------
put_str:                                ; SI = ASCIIZ
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

put2:                                   ; AL = 0..99 -> dos d¡gits
        aam
        add     ax,3030h
        xchg    al,ah
        stosw
        ret

put_dec32:                              ; DX:AX -> decimal
        push    bx
        push    cx
        push    si
        xor     si,si
        mov     cx,10
.d:     mov     bx,ax
        mov     ax,dx
        xor     dx,dx
        div     cx                      ; part alta
        xchg    ax,bx
        div     cx                      ; part baixa, DX = residu
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

put_hex32:                              ; DX:AX -> 8 d¡gits hex
        push    ax
        mov     ax,dx
        call    put_hex16
        pop     ax
put_hex16:
        push    bx
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
        pop     bx
        ret

; ---------------------------------------------------------------------
;  Dades
; ---------------------------------------------------------------------
msg_ver     db  "SEARCH necessita MS-DOS 3.0 o superior.",13,10,0
msg_usage   db  "SEARCH 1.0 - Cerca un arxiu a totes les unitats i directoris",13,10
            db  "Sintaxi: SEARCH nom.ext   (admet comodins * i ?)",13,10
            db  "Sortida: RUTA - MIDA - DATA - HORA - HSRA - CRC32",13,10,0
msg_hdr1    db  "SEARCH - Cerca de: ",0
msg_hdr2    db  "RUTA - MIDA (bytes) - DATA - HORA - HSRA - CRC32",13,10
            db  "------------------------------------------------------------",13,10,0
msg_tot1    db  "------------------------------------------------------------",13,10
            db  "Total: ",0
msg_tot2    db  " arxiu(s) trobat(s).",13,10,0
msg_ovf     db  "Atenci¢: mem•ria plena, el TXT nom‚s tindr… una part de la sortida.",13,10,0
msg_ask     db  13,10,"Vols desar la sortida en un fitxer TXT? (S/N): ",0
msg_dir     db  "Directori on desar-lo (Enter = actual, ex. C:\DADES): ",0
msg_name    db  "Nom del fitxer (ex. RESULTAT.TXT): ",0
msg_cerr    db  "Error: no s'ha pogut crear el fitxer (codi DOS ",0
msg_cerr2   db  ").",13,10,0
msg_werr    db  "Error en escriure el fitxer (disc ple, protegit o no preparat).",13,10,0
msg_verr    db  "Error de verificaci¢: el fitxer desat no coincideix.",13,10,0
msg_retry   db  "Vols tornar-ho a provar? (S/N): ",0
msg_nomem   db  "No hi ha mem•ria lliure per desar la sortida.",13,10,0
msg_ok1     db  "Fitxer desat i verificat: ",0
msg_ok2     db  " (",0
msg_ok3     db  " bytes, CRC32 ",0
msg_ok4     db  ") OK",13,10,0
msg_crcerr  db  "ERROR",0
msg_stat    db  "Explorant "
msg_stat_drv db "?: ...",13,0
msg_clr     db  13,"                    ",13,0
ans_yes     db  "S",13,10,0
ans_no      db  "N",13,10,0
crlf        db  13,10,0
starstar    db  "*.*",0
txt_ext     db  ".TXT",0

bufseg      dw  0
bufoff      dw  0                       ; punter far (offset, segment)
bufcurseg   dw  0
caplo       dw  0
caphi       dw  0
usedlo      dw  0
usedhi      dw  0
overflow    db  0
found       dw  0
statshown   db  0
drive       db  0
level       db  0
owned       times 27 db 0
inbuf       db  64, 0
            times 66 db 0

; ---------------------------------------------------------------------
;  Zona no inicialitzada
; ---------------------------------------------------------------------
        section .bss
        alignb  2
pathlen     resw 1
fh          resw 1
wfh         resw 1
wseg        resw 1
remlo       resw 1
remhi       resw 1
crclo       resw 1
crchi       resw 1
bcrclo      resw 1
bcrchi      resw 1
rsizelo     resw 1
rsizehi     resw 1
namestart   resw 1
argbuf      resb 14
path        resb 144
fpath       resb 144
outname     resb 144
linebuf     resb 256
crctab      resb 1024
dtas        resb MAXLVL*DTASZ
rbuf        resb RBUFSZ
            resb 1024
stack_top:
prog_end:
