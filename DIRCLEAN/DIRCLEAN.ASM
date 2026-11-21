; =====================================================================
;  DIRCLEAN.ASM  -  DIRCLEAN.COM 1.1 per a MS-DOS 3.20 ... 6.22 (8086+)
;
;  Funciona a MS-DOS 3.2, 3.3, 4.x, 5.x i 6.x. A partir de DOS 3.31/4.0
;  fa servir la crida INT 25h/26h ampliada (CX=FFFFh + paquet) per a
;  particions de mÇs de 32 MB (FAT16 fins a 2 GB). Rebutja unitats
;  comprimides (DoubleSpace/DriveSpace), SUBST i de xarxa.
;
;  Revisa els directoris d'una unitat FAT12/FAT16 llegint-los directament
;  del disc (INT 25h) i hi detecta:
;
;   - Entrades de nom llarg (VFAT/LFN, atribut 0Fh) ïrfenes
;   - Brossa de macOS: .fseventsd, .Spotlight-V100, .Trashes, ._*,
;     .DS_Store, .TemporaryItems... (amb les seves entrades LFN)
;   - Entrades invÖlides: nom amb carÖcters prohibits, cl£ster inicial
;     fora de rang, cadena de cl£sters trencada, en bucle o encreuada,
;     mida mÇs gran que la cadena
;
;  Per a cada problema pregunta si cal esborrar l'entrada. En esborrar:
;   1) es marca l'entrada (i les seves LFN) com a esborrada (E5h)
;   2) DESPRêS s'alliberen els cl£sters a la FAT (a totes les cïpies),
;      nomÇs si la cadena era vÖlida i no compartida. Un directori
;      s'esborra amb tot el seu contingut.
;  Si s'interromp entre 1 i 2, nomÇs queden cl£sters perduts (CHKDSK /F).
;
;  DIRCLEAN [unitat:] [/N]      /N = nomÇs informe, no modifica res
;
;  Tots els sectors es tracten amb 32 bits. La FAT pot ocupar fins a
;  256 sectors (128 KB, en dos segments).
;
;  Compilar:  nasm -f bin DIRCLEAN.ASM -o DIRCLEAN.COM
; =====================================================================

        cpu     8086
        org     100h

MAXLVL  equ     16              ; profunditat mÖxima de directoris
SECSZ   equ     512
MAXPEND equ     20              ; entrades LFN per grup
ITSZ    equ     16              ; mida de l'estructura d'iterador

; estructura d'iterador de directori (una per nivell)
IT_ROOT equ     0               ; byte: 1 = directori arrel
IT_SEC  equ     1               ; byte: sector dins del cl£ster / arrel
IT_CLUS equ     2               ; word: cl£ster actual
IT_LBA  equ     4               ; dword: sector absolut carregat
IT_OFF  equ     8               ; word: desplaáament de la propera entrada
IT_BUF  equ     10              ; word: buffer del sector
IT_STEP equ     12              ; word: comptador anti-bucle
FATCHNK equ     64              ; sectors per transferäncia de FAT (32 KB)

; ---------------------------------------------------------------------
start:
        mov     ah,30h
        int     21h
        mov     [dosmaj],al
        mov     [dosmin],ah
        cmp     al,3
        jae     .verok
        mov     dx,msg_ver
        call    puts
        jmp     exit_err
.verok: mov     sp,stack_top
        cld
        mov     bx,prog_end+15          ; allibera la memïria sobrant
        mov     cl,4
        shr     bx,cl
        mov     ah,4Ah
        int     21h

        ; ---- parÖmetres ----
        mov     ah,19h
        int     21h
        mov     [drv0],al               ; unitat actual per defecte
        mov     si,81h
.pa:    lodsb
        cmp     al,' '
        je      .pa
        cmp     al,9
        je      .pa
        cmp     al,13
        je      .pdone
        cmp     al,'/'
        je      .sw
        call    upcase
        cmp     al,'A'
        jb      usage
        cmp     al,'Z'
        ja      usage
        cmp     byte [si],':'
        jne     usage
        inc     si
        sub     al,'A'
        mov     [drv0],al
        jmp     .pa
.sw:    lodsb
        cmp     al,'?'
        je      usage
        call    upcase
        cmp     al,'N'
        jne     usage
        mov     byte [reportonly],1
        jmp     .pa
.pdone:
        mov     al,[drv0]
        add     al,'A'
        mov     [path],al
        mov     [msg_drv],al
        mov     word [path+1],'\' * 256 + ':'
        mov     word [pathlen],3

        ; ---- tipus d'unitat ----
        mov     ax,4409h                ; IOCTL: unitat local/remota (DOS 3.1+)
        mov     bl,[drv0]
        inc     bl
        int     21h
        jc      .drvok
        test    dx,8000h                ; SUBST
        jz      .nosubst
        mov     dx,msg_subst
        jmp     .refuse
.nosubst:
        test    dx,1000h                ; xarxa
        jz      .drvok
        mov     dx,msg_net
        jmp     .refuse
.drvok: cmp     byte [dosmaj],6         ; DoubleSpace/DriveSpace (DOS 6)
        jb      .nodbl
        mov     ax,4A11h
        xor     bx,bx
        int     2Fh
        or      ax,ax
        jnz     .nodbl
        cmp     bx,444Dh                ; 'DM': DBLSPACE.BIN carregat
        jne     .nodbl
        mov     ax,4A11h
        mov     bx,1
        mov     dl,[drv0]
        int     2Fh
        or      ax,ax
        jnz     .nodbl
        test    bl,80h                  ; unitat comprimida
        jz      .nodbl
        mov     dx,msg_dbl
.refuse:
        call    puts
        jmp     exit_err
.nodbl:
        call    flush_cache
        mov     ah,0Dh                  ; buida els buffers de DOS
        int     21h

        ; ---- sector d'arrencada i BPB ----
        xor     ax,ax
        xor     dx,dx
        mov     bx,bootbuf
        call    read1
        jnc     .bootok
        cmp     ax,0207h                ; partici¢ >32 MB: cal la crida ampliada
        jne     .booterr
        call    can_big
        jc      .booterr
        mov     byte [bigio],1
        xor     ax,ax
        xor     dx,dx
        mov     bx,bootbuf
        call    read1
        jnc     .bootok
.booterr:
        jmp     err_read
.bootok:
        cmp     word [bootbuf+0Bh],512
        jne     .badbpb
        mov     al,[bootbuf+0Dh]
        or      al,al
        jz      .badbpb
        cmp     al,64
        ja      .badbpb
        mov     [spc],al
        mov     ax,[bootbuf+0Eh]
        or      ax,ax
        jz      .badbpb
        mov     [res],ax
        mov     al,[bootbuf+10h]
        or      al,al
        jz      .badbpb
        cmp     al,2
        ja      .badbpb
        mov     [nfat],al
        mov     ax,[bootbuf+11h]
        or      ax,ax
        jz      .badbpb
        add     ax,15
        mov     cl,4
        shr     ax,cl
        cmp     ax,255
        ja      .badbpb
        mov     [rootsecs],ax
        mov     ax,[bootbuf+16h]
        or      ax,ax
        jz      .badbpb
        cmp     ax,256
        ja      .badbpb
        mov     [spf],ax
        ; sectors totals: 16 bits, o 32 bits a 20h si val 0 (DOS 4+)
        mov     ax,[bootbuf+13h]
        xor     dx,dx
        or      ax,ax
        jnz     .ts16
        mov     ax,[bootbuf+20h]
        mov     dx,[bootbuf+22h]
.ts16:  mov     [totsec],ax
        mov     [totsec+2],dx
        or      dx,dx
        jz      .tsok
        cmp     byte [bigio],0          ; >65535 sectors: crida ampliada
        jne     .tsok
        call    can_big
        jc      .badbpb
        mov     byte [bigio],1
        jmp     .tsok
.badbpb:
        mov     dx,msg_bpb
        call    puts
        jmp     exit_err
.tsok:  ; rootstart = res + nfat*spf
        mov     al,[nfat]
        xor     ah,ah
        mul     word [spf]
        add     ax,[res]
        mov     [rootstart],ax
        mov     word [rootstart+2],0
        add     ax,[rootsecs]
        mov     [datastart],ax
        mov     word [datastart+2],0
        ; cl£sters = (totsec - datastart) / spc
        mov     bx,ax
        mov     ax,[totsec]
        mov     dx,[totsec+2]
        sub     ax,bx
        sbb     dx,0
        jc      .badbpb
        mov     cl,[spc]
        xor     ch,ch
        cmp     dx,cx                   ; el quocient no hi cabria (FAT32?)
        jae     .badbpb
        div     cx
        cmp     ax,2
        jb      .badbpb
        cmp     ax,65525
        ja      .badbpb
        mov     [clusters],ax
        inc     ax
        mov     [maxclus],ax
        cmp     word [clusters],4085
        jb      .f12
        mov     byte [fat16],1
.f12:   mov     al,[spc]
        xor     ah,ah
        mov     cl,9
        shl     ax,cl
        mov     [cbytes],ax

        ; ---- memïria per a la FAT ----
        mov     bx,[spf]
        mov     cl,5
        shl     bx,cl                   ; parÖgrafs = spf*32
        mov     ah,48h
        int     21h
        jnc     .memok
        mov     dx,msg_mem
        call    puts
        jmp     exit_err
.memok: mov     [fatseg],ax

        ; ---- llegeix la primera cïpia de la FAT ----
        mov     word [io_wr],0
        mov     dx,[res]
        call    fat_xfer
        jnc     .fatok
        jmp     err_read
.fatok:
        ; buida el mapa de cl£sters usats
        mov     di,bitmap
        mov     cx,4096
        xor     ax,ax
        rep     stosw
        ; prepara els iteradors
        mov     di,itstructs
        mov     ax,secbufs
        mov     cx,MAXLVL
.itp:   mov     [di+IT_BUF],ax
        add     ax,SECSZ
        add     di,ITSZ
        loop    .itp

        ; ---- capáalera ----
        mov     di,linebuf
        mov     si,msg_hdr1
        call    put_str
        mov     si,msg_f12
        cmp     byte [fat16],0
        je      .h1
        mov     si,msg_f16
.h1:    call    put_str
        mov     ax,[clusters]
        xor     dx,dx
        call    put_dec32
        mov     si,msg_hdr2
        call    put_str
        mov     ax,[cbytes]
        xor     dx,dx
        call    put_dec32
        mov     si,msg_hdr3
        call    put_str
        call    flush_line
        cmp     byte [reportonly],0
        je      .h2
        mov     dx,msg_ronly
        call    puts
.h2:
        ; ---- recorre ----
        mov     byte [level],0
        xor     ax,ax
        call    scan_dir

; ---------------------------------------------------------------------
summary:
        call    flush_cache             ; SMARTDRV: escriu el que tingui pendent
        mov     ah,0Dh                  ; foráa DOS a rellegir el disc
        int     21h
        mov     di,linebuf
        mov     si,msg_s1
        call    put_str
        mov     ax,[nentries]
        xor     dx,dx
        call    put_dec32
        mov     si,msg_s2
        call    put_str
        mov     ax,[nproblems]
        xor     dx,dx
        call    put_dec32
        mov     si,msg_s3
        call    put_str
        mov     ax,[ndeleted]
        xor     dx,dx
        call    put_dec32
        mov     si,msg_s4
        call    put_str
        mov     ax,[nfreed]
        xor     dx,dx
        call    put_dec32
        call    flush_line
        cmp     byte [nwarn],0
        je      .nw
        mov     dx,msg_chk
        call    puts
.nw:    cmp     word [nproblems],0
        jne     exit_ok
        mov     dx,msg_clean
        call    puts
exit_ok:
        mov     ax,4C00h
        int     21h
usage:
        mov     dx,msg_usage
        call    puts
exit_err:
        mov     ax,4C01h
        int     21h
err_read:
        mov     dx,msg_rerr
        call    puts
        jmp     exit_err
err_write:
        mov     dx,msg_werr
        call    puts
        jmp     summary

; ---------------------------------------------------------------------
;  AccÇs al disc (INT 25h/26h)
;  Crida antiga (DOS 3.x, volums < 65536 sectors) o ampliada amb paquet
;  (CX=FFFFh, DOS 3.31/4.0+) si [bigio]=1.
;  Entrada: [io_lo]:[io_hi] = sector, CX = nombre, [io_seg]:BX = buffer,
;           [io_wr] = 0 llegir / 1 escriure.   Sortida: CF, AX = error
; ---------------------------------------------------------------------
disk_rw:
        push    bp
        push    si
        push    di
        mov     si,[io_wr]
        mov     al,[drv0]
        cmp     byte [bigio],0
        jne     .big
        cmp     word [io_hi],0
        jne     .fail
        mov     dx,[io_lo]
        push    ds
        mov     ds,[io_seg]
        or      si,si
        jnz     .w
        int     25h
        jmp     short .d
.w:     int     26h
.d:     pop     cx                      ; INT 25h/26h deixen els flags a la pila
        pop     ds
        jmp     short .x
.big:   mov     dx,[io_lo]
        mov     [pkt],dx
        mov     dx,[io_hi]
        mov     [pkt+2],dx
        mov     [pkt+4],cx
        mov     [pkt+6],bx
        mov     dx,[io_seg]
        mov     [pkt+8],dx
        mov     bx,pkt
        mov     cx,0FFFFh
        or      si,si
        jnz     .bw
        int     25h
        jmp     short .bd
.bw:    int     26h
.bd:    pop     cx
        jmp     short .x
.fail:  mov     ax,0207h
        stc
.x:     pop     di
        pop     si
        pop     bp
        ret

; Un sector: DX:AX = sector, DS:BX = buffer
read1:  mov     word [io_wr],0
rw1:    mov     [io_lo],ax
        mov     [io_hi],dx
        mov     [io_seg],ds
        mov     cx,1
        jmp     disk_rw
write1: mov     word [io_wr],1
        jmp     rw1

; Transfereix tota una cïpia de la FAT (fatseg:0) des del sector DX,
; en blocs de FATCHNK sectors.  [io_wr] = sentit
fat_xfer:
        mov     ax,[fatseg]
        mov     [io_seg],ax
        mov     [io_lo],dx
        mov     word [io_hi],0
        mov     di,[spf]
.l:     mov     cx,FATCHNK
        cmp     di,cx
        jae     .c
        mov     cx,di
.c:     push    cx
        push    di
        xor     bx,bx
        call    disk_rw
        pop     di
        pop     cx
        jc      .r
        add     [io_lo],cx
        adc     word [io_hi],0
        add     word [io_seg],FATCHNK*SECSZ/16
        sub     di,cx
        jnz     .l
        clc
.r:     ret

; Escriu la FAT de memïria a totes les cïpies
write_fat:
        mov     dx,[res]
        mov     bl,[nfat]
.l:     push    bx
        push    dx
        mov     word [io_wr],1
        call    fat_xfer
        pop     dx
        pop     bx
        jc      .err
        add     dx,[spf]
        dec     bl
        jnz     .l
        call    flush_cache
        ret
.err:   jmp     err_write

; CF=0 si aquest DOS tÇ la crida INT 25h/26h ampliada (3.31 o mÇs)
can_big:
        cmp     byte [dosmaj],4
        jae     .ok
        cmp     byte [dosmaj],3
        jne     .no
        cmp     byte [dosmin],31
        jae     .ok
.no:    stc
        ret
.ok:    clc
        ret

; Demana a SMARTDRV (si n'hi ha) que escrigui la memïria cau pendent
flush_cache:
        cmp     byte [dosmaj],3
        jb      .r
        mov     ax,4A10h
        mov     bx,1
        int     2Fh
.r:     ret

; ---------------------------------------------------------------------
;  FAT en memïria
; ---------------------------------------------------------------------
; AX = cl£ster -> AX = valor (FAT12 normalitzat a 16 bits: FF8h -> FFF8h)
fat_get:
        push    bx
        push    cx
        push    es
        mov     es,[fatseg]
        cmp     byte [fat16],0
        jne     .f16
        mov     bx,ax
        shr     bx,1
        add     bx,ax
        mov     cx,ax
        mov     ax,[es:bx]
        test    cl,1
        jz      .even
        mov     cl,4
        shr     ax,cl
        jmp     .n
.even:  and     ax,0FFFh
.n:     cmp     ax,0FF0h
        jb      .x
        or      ax,0F000h
        jmp     .x
.f16:   mov     bx,ax
        shl     bx,1
        test    ah,80h                  ; cl£ster >= 32768: segon segment
        jz      .s0
        mov     cx,es
        add     cx,1000h
        mov     es,cx
.s0:    mov     ax,[es:bx]
.x:     pop     es
        pop     cx
        pop     bx
        ret

; AX = cl£ster, DX = valor
fat_set:
        push    ax
        push    bx
        push    cx
        push    dx
        push    es
        mov     es,[fatseg]
        cmp     byte [fat16],0
        jne     .f16
        mov     bx,ax
        shr     bx,1
        add     bx,ax
        and     dx,0FFFh
        test    al,1
        jz      .even
        mov     cl,4
        shl     dx,cl
        mov     ax,[es:bx]
        and     ax,000Fh
        or      ax,dx
        mov     [es:bx],ax
        jmp     .x
.even:  mov     ax,[es:bx]
        and     ax,0F000h
        or      ax,dx
        mov     [es:bx],ax
        jmp     .x
.f16:   mov     bx,ax
        shl     bx,1
        test    ah,80h
        jz      .s0
        mov     cx,es
        add     cx,1000h
        mov     es,cx
.s0:    mov     [es:bx],dx
.x:     pop     es
        pop     dx
        pop     cx
        pop     bx
        pop     ax
        ret

; AX = cl£ster -> ZF=0 si ja estÖ marcat al mapa; el marca si mark=1
bit_test:
        push    bx
        push    cx
        mov     bx,ax
        mov     cl,3
        shr     bx,cl
        mov     cl,al
        and     cl,7
        mov     ch,1
        shl     ch,cl
        test    [bitmap+bx],ch
        pop     cx
        pop     bx
        ret
bit_set:
        push    bx
        push    cx
        mov     bx,ax
        mov     cl,3
        shr     bx,cl
        mov     cl,al
        and     cl,7
        mov     ch,1
        shl     ch,cl
        or      [bitmap+bx],ch
        pop     cx
        pop     bx
        ret

; AX = cl£ster -> DX:AX = primer sector
clus2lba:
        push    cx
        sub     ax,2
        mov     cl,[spc]
        xor     ch,ch
        mul     cx
        add     ax,[datastart]
        adc     dx,[datastart+2]
        pop     cx
        ret

; ---------------------------------------------------------------------
;  Iterador de directori.  BP = estructura del nivell
; ---------------------------------------------------------------------
; AX = cl£ster inicial (0 = arrel). CF = error de lectura
it_open:
        mov     word [bp+IT_OFF],0
        mov     byte [bp+IT_SEC],0
        mov     word [bp+IT_STEP],0
        mov     [bp+IT_CLUS],ax
        or      ax,ax
        jnz     .sub
        mov     byte [bp+IT_ROOT],1
        mov     ax,[rootstart]
        mov     dx,[rootstart+2]
        jmp     .rd
.sub:   mov     byte [bp+IT_ROOT],0
        call    clus2lba
.rd:    mov     [bp+IT_LBA],ax
        mov     [bp+IT_LBA+2],dx
        mov     bx,[bp+IT_BUF]
        call    read1
        ret

; -> SI = entrada; CF=1 si s'ha acabat el directori
it_next:
        cmp     word [bp+IT_OFF],SECSZ
        jb      .have
        ; sector segÅent
        inc     byte [bp+IT_SEC]
        cmp     byte [bp+IT_ROOT],0
        je      .sub
        mov     al,[bp+IT_SEC]
        xor     ah,ah
        cmp     ax,[rootsecs]
        jae     .end
        add     word [bp+IT_LBA],1
        adc     word [bp+IT_LBA+2],0
        jmp     .load
.sub:   mov     al,[bp+IT_SEC]
        cmp     al,[spc]
        jb      .samecl
        mov     ax,[bp+IT_CLUS]
        call    fat_get
        cmp     ax,2
        jb      .end
        cmp     ax,[maxclus]
        ja      .end
        inc     word [bp+IT_STEP]
        mov     bx,[bp+IT_STEP]
        cmp     bx,[clusters]
        ja      .end                    ; bucle
        mov     [bp+IT_CLUS],ax
        mov     byte [bp+IT_SEC],0
        call    clus2lba
        mov     [bp+IT_LBA],ax
        mov     [bp+IT_LBA+2],dx
        jmp     .load
.samecl:
        add     word [bp+IT_LBA],1
        adc     word [bp+IT_LBA+2],0
.load:  mov     ax,[bp+IT_LBA]
        mov     dx,[bp+IT_LBA+2]
        mov     bx,[bp+IT_BUF]
        call    read1
        jc      .rerr
        mov     word [bp+IT_OFF],0
.have:  mov     si,[bp+IT_BUF]
        add     si,[bp+IT_OFF]
        cmp     byte [si],0
        je      .end                    ; final del directori
        add     word [bp+IT_OFF],32
        clc
        ret
.rerr:  mov     dx,msg_rerr
        call    puts
.end:   mov     word [bp+IT_OFF],SECSZ
        mov     byte [bp+IT_ROOT],2     ; queda acabat
        mov     ax,[rootsecs]
        mov     [bp+IT_SEC],al
        stc
        ret

; BP = estructura del nivell [level]
lvl_struct:
        mov     al,[level]
        mov     ah,ITSZ
        mul     ah
        add     ax,itstructs
        mov     bp,ax
        ret

; Marca com a esborrada l'entrada del sector DX:AX, desplaáament BX
mark_e5:                                ; DX:AX = sector, BX = desplaáament
        mov     [m_lo],ax
        mov     [m_hi],dx
        mov     [m_off],bx
        mov     bx,tmpsec
        call    read1
        jc      .err
        mov     bx,[m_off]
        mov     byte [tmpsec+bx],0E5h
        mov     ax,[m_lo]
        mov     dx,[m_hi]
        mov     bx,tmpsec
        call    write1
        jc      .werr
        ; si el sector Çs al buffer del nivell actual, actualitza'l
        mov     ax,[m_lo]
        cmp     ax,[bp+IT_LBA]
        jne     .r
        mov     ax,[m_hi]
        cmp     ax,[bp+IT_LBA+2]
        jne     .r
        mov     bx,[m_off]
        add     bx,[bp+IT_BUF]
        mov     byte [bx],0E5h
.r:     ret
.err:   jmp     err_read
.werr:  jmp     err_write

; ---------------------------------------------------------------------
;  Recorre un directori.  AX = cl£ster (0 = arrel), [level], [path]
; ---------------------------------------------------------------------
scan_dir:
        push    bp
        push    ax
        call    lvl_struct
        pop     ax
        call    it_open
        jc      .rerr
        mov     byte [pend_n],0
.loop:  call    it_next
        jc      .end
        mov     al,[si]
        cmp     al,0E5h
        je      .deleted
        cmp     byte [si+0Bh],0Fh
        je      .lfn
        inc     word [nentries]
        cmp     byte [level],0          ; "." i ".." dels subdirectoris
        je      .short
        cmp     al,'.'
        jne     .short
        call    flush_orphans
        jmp     .loop
.short: call    handle_short
        jmp     .loop
.deleted:
        call    flush_orphans
        jmp     .loop
.lfn:   inc     word [nentries]
        call    add_lfn
        jmp     .loop
.rerr:  mov     dx,msg_rerr
        call    puts
.end:   call    flush_orphans
        pop     bp
        ret

; ---------------------------------------------------------------------
;  Entrades LFN pendents
; ---------------------------------------------------------------------
add_lfn:
        mov     al,[si]
        test    al,40h                  ; primera entrada (£ltima part)
        jnz     .newgrp
        cmp     byte [pend_n],0
        je      .newgrp
        mov     al,[si+0Dh]
        cmp     al,[pend_chk]
        je      .store
.newgrp:
        call    flush_orphans
        mov     di,lfnbuf
        mov     cx,264
        xor     al,al
        rep     stosb
        mov     al,[si+0Dh]
        mov     [pend_chk],al
.store: mov     al,[pend_n]
        cmp     al,MAXPEND
        jae     .chars
        xor     ah,ah
        shl     ax,1
        mov     bx,ax
        mov     ax,[bp+IT_LBA]
        mov     [pend_lo+bx],ax
        mov     ax,[bp+IT_LBA+2]
        mov     [pend_hi+bx],ax
        mov     ax,si
        sub     ax,[bp+IT_BUF]
        mov     [pend_off+bx],ax
        inc     byte [pend_n]
.chars: mov     al,[si]
        and     al,1Fh
        jz      .r
        cmp     al,20
        ja      .r
        dec     al
        mov     ah,13
        mul     ah
        mov     di,lfnbuf
        add     di,ax
        mov     bx,lfnoffs
        mov     cx,13
.c:     push    bx
        mov     bl,[bx]
        xor     bh,bh
        mov     ax,[si+bx]
        pop     bx
        inc     bx
        cmp     ax,0FFFFh
        je      .zero
        or      ah,ah
        jz      .st
        mov     al,'?'
        jmp     .st
.zero:  xor     al,al
.st:    mov     [di],al
        inc     di
        loop    .c
.r:     ret

; Les LFN pendents no pertanyen a cap entrada: s¢n ïrfenes
flush_orphans:
        cmp     byte [pend_n],0
        jne     .go
        ret
.go:    inc     word [nproblems]
        mov     di,linebuf
        mov     si,path
        mov     cx,[pathlen]
        rep     movsb
        mov     si,msg_orph
        call    put_str
        mov     si,lfnbuf
        call    put_lfn
        mov     si,msg_orph2
        call    put_str
        call    flush_line
        call    ask
        jne     .no
        call    del_pending
        inc     word [ndeleted]
.no:    mov     byte [pend_n],0
        ret

; Marca E5 totes les LFN pendents
del_pending:
        xor     cx,cx
        mov     cl,[pend_n]
        jcxz    .r
        xor     si,si
.l:     push    cx
        push    si
        mov     ax,[pend_lo+si]
        mov     dx,[pend_hi+si]
        mov     bx,[pend_off+si]
        call    mark_e5
        pop     si
        pop     cx
        add     si,2
        loop    .l
.r:     mov     byte [pend_n],0
        ret

; ---------------------------------------------------------------------
;  Entrada curta (8.3).  SI = entrada al buffer, BP = nivell
; ---------------------------------------------------------------------
handle_short:
        ; cïpia de l'entrada i la seva posici¢
        mov     ax,[bp+IT_LBA]
        mov     [cur_lba],ax
        mov     ax,[bp+IT_LBA+2]
        mov     [cur_lba+2],ax
        mov     ax,si
        sub     ax,[bp+IT_BUF]
        mov     [cur_off],ax
        mov     di,cur
        mov     cx,16
        rep     movsw
        ; suma de comprovaci¢ LFN del nom curt
        mov     si,cur
        mov     cx,11
        xor     al,al
.ck:    ror     al,1
        add     al,[si]
        inc     si
        loop    .ck
        mov     byte [has_lfn],0
        cmp     byte [pend_n],0
        je      .nolfn
        cmp     al,[pend_chk]
        jne     .orph
        mov     byte [has_lfn],1
        jmp     .nolfn
.orph:  call    flush_orphans
.nolfn:
        test    byte [cur+0Bh],08h      ; etiqueta de volum: s'ignora
        jz      .notlabel
        mov     byte [pend_n],0
        ret
.notlabel:
        mov     byte [junk],0
        mov     word [reason],0
        mov     byte [warn],0
        mov     byte [chainok],0
        mov     al,[cur+0Bh]
        and     al,10h
        mov     [isdir],al

        ; --- brossa de macOS? ---
        cmp     byte [has_lfn],0
        je      .nolj
        call    lfn_is_junk
        jnc     .nolj
        mov     byte [junk],1
.nolj:  test    byte [cur+0Bh],02h      ; nom curt t°pic + ocult
        jz      .nosj
        call    short_is_junk
        jnc     .nosj
        mov     byte [junk],1
.nosj:
        ; --- nom vÖlid? ---
        mov     si,cur
        mov     cx,11
.nm:    mov     al,[si]
        cmp     cx,11
        jne     .nm2
        cmp     al,05h                  ; 05h = E5h real
        je      .nmok
        cmp     al,' '
        je      .badnm
.nm2:   cmp     al,' '
        jb      .badnm
        cmp     al,'a'
        jb      .nm3
        cmp     al,'z'
        jbe     .badnm
.nm3:   push    cx
        push    si
        mov     di,badchars
        mov     cx,badchars_n
        repne   scasb
        pop     si
        pop     cx
        je      .badnm
.nmok:  inc     si
        loop    .nm
        jmp     .chain
.badnm: mov     word [reason],msg_r_name

        ; --- cadena de cl£sters ---
.chain: call    check_chain

        ; --- decisi¢ ---
        cmp     byte [junk],0
        je      .notjunk
        inc     word [nproblems]
        call    line_entry
        mov     si,msg_junk
        call    put_str
        cmp     byte [has_lfn],0
        je      .j1
        mov     si,msg_lq
        call    put_str
        mov     si,lfnbuf
        call    put_lfn
        mov     si,msg_rq
        call    put_str
.j1:    call    flush_line
        cmp     byte [isdir],0
        je      .j2
        mov     dx,msg_withc
        call    puts
.j2:    call    ask
        jne     .done
        call    delete_entry
        jmp     .done

.notjunk:
        cmp     word [reason],0
        je      .valid
        inc     word [nproblems]
        call    line_entry
        mov     si,msg_inv
        call    put_str
        mov     si,[reason]
        call    put_str
        call    flush_line
        cmp     byte [chainok],0
        jne     .i1
        mov     dx,msg_nofree
        call    puts
.i1:    call    ask
        jne     .done
        call    delete_entry
        jmp     .done

.valid: cmp     byte [warn],0
        je      .desc
        mov     byte [nwarn],1
        call    line_entry
        mov     si,msg_w_long
        call    put_str
        call    flush_line
.desc:  cmp     byte [isdir],0
        je      .done
        cmp     byte [chainok],0
        je      .done
        cmp     byte [level],MAXLVL-1
        jae     .done
        ; entra al subdirectori
        mov     byte [pend_n],0
        mov     di,path
        add     di,[pathlen]
        call    put_name83
        mov     al,'\'
        stosb
        mov     ax,di
        sub     ax,path
        push    word [pathlen]
        mov     [pathlen],ax
        mov     ax,[cur+1Ah]
        inc     byte [level]
        call    scan_dir
        dec     byte [level]
        pop     word [pathlen]
        ret
.done:  mov     byte [pend_n],0
        ret

; Comprova la cadena de [cur]. Fixa reason, warn, chainok
check_chain:
        mov     ax,[cur+1Ah]
        mov     [cstart],ax
        cmp     byte [isdir],0
        jne     .dir
        ; arxiu
        mov     ax,[cur+1Ch]
        or      ax,[cur+1Eh]
        jnz     .fsz
        cmp     word [cstart],0
        jne     .walk0
        mov     byte [chainok],1        ; arxiu buit, sense cl£sters
        ret
.fsz:   cmp     word [cstart],0
        jne     .walk0
        mov     word [reason],msg_r_nocl
        ret
.dir:   cmp     word [cstart],0
        jne     .walk0
        mov     word [reason],msg_r_dir0
        ret
.walk0: mov     ax,[cstart]
        cmp     ax,2
        jb      .range
        cmp     ax,[maxclus]
        jbe     .walk
.range: mov     word [reason],msg_r_range
        ret
.walk:  xor     cx,cx                   ; CX = cl£sters comptats
.wl:    call    bit_test
        jz      .nx
        mov     word [reason],msg_r_cross
        ret
.nx:    call    bit_set
        inc     cx
        cmp     cx,[clusters]
        jbe     .nl
        mov     word [reason],msg_r_loop
        ret
.nl:    call    fat_get
        cmp     ax,0FFF8h
        jae     .eoc
        or      ax,ax
        jnz     .nz
        mov     word [reason],msg_r_free
        ret
.nz:    cmp     ax,2
        jb      .brk
        cmp     ax,[maxclus]
        jbe     .wl
.brk:   mov     word [reason],msg_r_bad
        ret
.eoc:   cmp     byte [isdir],0
        jne     .ok
        ; cl£sters necessaris = ceil(mida / cbytes)
        push    cx
        mov     ax,[cur+1Ch]
        mov     dx,[cur+1Eh]
        mov     bx,[cbytes]
        dec     bx
        add     ax,bx
        adc     dx,0
        inc     bx
        mov     cx,ax
        mov     ax,dx
        xor     dx,dx
        div     bx
        or      ax,ax
        mov     ax,cx
        jz      .lo
        pop     cx
        mov     word [reason],msg_r_size
        ret
.lo:    div     bx                      ; AX = necessaris
        pop     cx
        cmp     cx,ax
        jae     .ge
        mov     word [reason],msg_r_size
        mov     byte [chainok],1        ; cadena vÖlida i prïpia
        ret
.ge:    je      .ok
        mov     byte [warn],1
.ok:    mov     byte [chainok],1
        ret

; Esborra [cur]: LFN + entrada, desprÇs allibera cl£sters
delete_entry:
        cmp     byte [reportonly],0
        jne     .r
        cmp     byte [has_lfn],0
        je      .e
        call    del_pending
.e:     mov     ax,[cur_lba]
        mov     dx,[cur_lba+2]
        mov     bx,[cur_off]
        call    mark_e5
        inc     word [ndeleted]
        cmp     byte [chainok],0
        je      .r
        mov     ax,[cstart]
        or      ax,ax
        jz      .r
        cmp     byte [isdir],0
        je      .file
        call    free_tree               ; contingut del directori
.file:  mov     ax,[cstart]
        mov     byte [fcheck],0
        call    free_chain
        call    write_fat
.r:     ret

; Allibera tot el contingut del directori de cl£ster AX
free_tree:
        cmp     byte [level],MAXLVL-2
        jae     .r0
        inc     byte [level]
        push    bp
        push    ax
        call    lvl_struct
        pop     ax
        call    it_open
        jc      .out
.l:     call    it_next
        jc      .out
        mov     al,[si]
        cmp     al,0E5h
        je      .l
        cmp     al,'.'
        je      .l
        mov     al,[si+0Bh]
        cmp     al,0Fh
        je      .l
        test    al,08h
        jnz     .l
        mov     ax,[si+1Ah]
        cmp     ax,2
        jb      .l
        cmp     ax,[maxclus]
        ja      .l
        test    byte [si+0Bh],10h
        jz      .f
        push    ax
        call    free_tree
        pop     ax
.f:     mov     byte [fcheck],1
        call    free_chain
        jmp     .l
.out:   pop     bp
        dec     byte [level]
.r0:    ret

; Allibera la cadena que comenáa a AX (fcheck=1: s'atura en cl£sters
; que pertanyen a entrades ja revisades)
free_chain:
        xor     cx,cx
.l:     cmp     ax,2
        jb      .r
        cmp     ax,[maxclus]
        ja      .r
        cmp     byte [fcheck],0
        je      .nc
        call    bit_test
        jnz     .r
.nc:    inc     cx
        cmp     cx,[clusters]
        ja      .r
        mov     bx,ax
        call    fat_get
        or      ax,ax
        jz      .r                      ; ja era lliure
        xchg    ax,bx                   ; AX = cl£ster, BX = segÅent
        xor     dx,dx
        call    fat_set
        inc     word [nfreed]
        mov     ax,bx
        cmp     ax,0FFF8h
        jb      .l
.r:     ret

; ---------------------------------------------------------------------
;  Detecci¢ de brossa de macOS
; ---------------------------------------------------------------------
; Nom llarg a lfnbuf -> CF=1 si Çs brossa
lfn_is_junk:
        cmp     word [lfnbuf],'._'
        je      .yes
        mov     bx,junk_lfn
.n:     mov     si,[bx]
        or      si,si
        jz      .no
        mov     di,lfnbuf
.c:     mov     al,[di]
        cmp     al,'A'
        jb      .c2
        cmp     al,'Z'
        ja      .c2
        add     al,20h
.c2:    cmp     al,[si]
        jne     .nx
        or      al,al
        jz      .yes
        inc     si
        inc     di
        jmp     .c
.nx:    add     bx,2
        jmp     .n
.yes:   stc
        ret
.no:    clc
        ret

; Nom curt de [cur] -> CF=1 si Çs un nom curt t°pic de macOS
short_is_junk:
        mov     bx,junk_short
.n:     mov     di,[bx]
        or      di,di
        jz      .no
        mov     si,cur
        mov     cx,11
        repe    cmpsb
        je      .yes
        add     bx,2
        jmp     .n
.yes:   stc
        ret
.no:    clc
        ret

; ---------------------------------------------------------------------
;  Sortida
; ---------------------------------------------------------------------
; L°nia "RUTA\NOM.EXT  <DIR>|mida bytes  "
line_entry:
        mov     di,linebuf
        mov     si,path
        mov     cx,[pathlen]
        rep     movsb
        call    put_name83
        mov     ax,'  '
        stosw
        cmp     byte [isdir],0
        je      .f
        mov     si,msg_dir
        call    put_str
        jmp     .x
.f:     mov     ax,[cur+1Ch]
        mov     dx,[cur+1Eh]
        call    put_dec32
        mov     si,msg_bytes
        call    put_str
.x:     ret

; Nom 8.3 de [cur] -> DI
put_name83:
        mov     si,cur
        mov     cx,8
        call    .part
        mov     si,cur+8
        cmp     byte [si],' '
        je      .r
        mov     al,'.'
        stosb
        mov     cx,3
        call    .part
.r:     ret
.part:  ; copia CX carÖcters sense els espais finals
        mov     bx,si
        add     bx,cx
.t:     cmp     bx,si
        je      .pr
        cmp     byte [bx-1],' '
        jne     .pc
        dec     bx
        jmp     .t
.pc:    lodsb
        cmp     si,cur+1                ; 05h al primer byte = E5h
        jne     .pc1
        cmp     al,05h
        jne     .pc1
        mov     al,0E5h
.pc1:   cmp     al,' '
        jae     .pc2
        mov     al,'?'
.pc2:   stosb
        cmp     si,bx
        jb      .pc
.pr:    ret

; Nom llarg (SI) -> DI, limitat a 40 carÖcters
put_lfn:
        mov     cx,40
.l:     lodsb
        or      al,al
        jz      .r
        cmp     al,' '
        jae     .s
        mov     al,'?'
.s:     stosb
        loop    .l
        mov     ax,'..'
        stosw
.r:     ret

; Pregunta. ZF=1 si cal esborrar
ask:
        cmp     byte [reportonly],0
        je      .a0
        or      al,1                    ; ZF=0
        ret
.a0:    cmp     byte [autoyes],0
        je      .a1
        mov     dx,msg_auto
        call    puts
        cmp     al,al
        ret
.a1:    mov     dx,msg_ask
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
        cmp     al,'N'
        je      .no
        cmp     al,'T'
        je      .all
        cmp     al,'Q'
        jne     .k
        mov     dx,msg_ansq
        call    puts
        jmp     summary
.all:   mov     byte [autoyes],1
        mov     dx,msg_anst
        call    puts
        cmp     al,al
        ret
.yes:   mov     dx,msg_anss
        call    puts
        cmp     al,al
        ret
.no:    mov     dx,msg_ansn
        call    puts
        or      al,1
        ret

flush_line:
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

; ---------------------------------------------------------------------
;  Dades
; ---------------------------------------------------------------------
lfnoffs     db  1,3,5,7,9,14,16,18,20,22,24,28,30
badchars    db  '"*+,./:;<=>?[\]|'
badchars_n  equ $-badchars

junk_lfn    dw  j1,j2,j3,j4,j5,j6,j7,j8,j9,0
j1          db  ".fseventsd",0
j2          db  ".spotlight-v100",0
j3          db  ".trashes",0
j4          db  ".temporaryitems",0
j5          db  ".ds_store",0
j6          db  ".metadata_never_index",0
j7          db  ".apdisk",0
j8          db  ".volumeicon.icns",0
j9          db  ".documentrevisions-v100",0
junk_short  dw  s1,s2,s3,s4,s5,0
s1          db  "FSEVEN~1   "
s2          db  "SPOTLI~1   "
s3          db  "TRASHE~1   "
s4          db  "TEMPOR~1   "
s5          db  "DS_STO~1   "

msg_ver     db  "DIRCLEAN necessita MS-DOS 3.0 o superior.",13,10,0
msg_usage   db  "DIRCLEAN 1.1 - Neteja entrades de directori caducades o invÖlides",13,10
            db  "MS-DOS 3.20 a 6.22, FAT12 i FAT16 (fins a 2 GB)",13,10
            db  "Sintaxi: DIRCLEAN [unitat:] [/N]",13,10
            db  "  /N  NomÇs informe: no modifica res",13,10
            db  "Respostes: S=esborra, N=no, T=esborra totes, Q=surt",13,10
            db  "Fes una cïpia de seguretat del disc abans d'esborrar res.",13,10,0
msg_bpb     db  "El disc no tÇ un BPB FAT12/FAT16 vÖlid (o aquest DOS no el pot llegir).",13,10,0
msg_subst   db  "ês una unitat SUBST: executa DIRCLEAN sobre la unitat real.",13,10,0
msg_net     db  "ês una unitat de xarxa: no es pot revisar.",13,10,0
msg_dbl     db  "Unitat comprimida amb DoubleSpace/DriveSpace: no suportada.",13,10
            db  "Fes servir SCANDISK o revisa la unitat amfitriona.",13,10,0
msg_mem     db  "No hi ha prou memïria.",13,10,0
msg_rerr    db  "Error de lectura del disc.",13,10,0
msg_werr    db  "ERROR D'ESCRIPTURA al disc! Passa CHKDSK.",13,10,0
msg_hdr1    db  "DIRCLEAN - Unitat "
msg_drv     db  "?: ",0
msg_f12     db  "FAT12, ",0
msg_f16     db  "FAT16, ",0
msg_hdr2    db  " cl£sters de ",0
msg_hdr3    db  " bytes",0
msg_ronly   db  "(Mode nomÇs informe: no es modificarÖ res)",13,10,0
msg_orph    db  "  [LFN ïrfena] ",174,0
msg_orph2   db  175," (nom llarg sense entrada)",0
msg_dir     db  "<DIR>  ",0
msg_bytes   db  " bytes  ",0
msg_junk    db  "-> Brossa de macOS",0
msg_lq      db  " ",174,0
msg_rq      db  175,0
msg_withc   db  "   (s'esborrarÖ amb tot el seu contingut)",13,10,0
msg_inv     db  "-> InvÖlida: ",0
msg_nofree  db  "   (no s'alliberaran cl£sters: desprÇs passa CHKDSK /F)",13,10,0
msg_w_long  db  "-> Av°s: la cadena Çs mÇs llarga que la mida",0
msg_r_name  db  "nom amb carÖcters no permesos",0
msg_r_nocl  db  "tÇ mida perï cap cl£ster",0
msg_r_dir0  db  "directori sense cl£ster",0
msg_r_range db  "cl£ster inicial fora de rang",0
msg_r_cross db  "cl£sters compartits amb una altra entrada",0
msg_r_loop  db  "cadena de cl£sters en bucle",0
msg_r_free  db  "cadena trencada (cl£ster lliure)",0
msg_r_bad   db  "cadena trencada (valor no vÖlid)",0
msg_r_size  db  "la mida supera la cadena de cl£sters",0
msg_ask     db  "   Esborrar? (S/N/T/Q): ",0
msg_auto    db  "   Esborrar? S (totes)",13,10,0
msg_anss    db  "S",13,10,0
msg_ansn    db  "N",13,10,0
msg_anst    db  "T",13,10,0
msg_ansq    db  "Q",13,10,0
msg_s1      db  13,10,"Entrades: ",0
msg_s2      db  "  Problemes: ",0
msg_s3      db  "  Esborrades: ",0
msg_s4      db  "  Cl£sters alliberats: ",0
msg_chk     db  "Hi ha avisos de cadenes: CHKDSK /F els corregeix.",13,10,0
msg_clean   db  "No s'ha trobat cap problema.",13,10,0

reportonly  db  0
bigio       db  0
dosmaj      db  0
dosmin      db  0
autoyes     db  0
fat16       db  0
level       db  0
pend_n      db  0
nwarn       db  0
nentries    dw  0
nproblems   dw  0
ndeleted    dw  0
nfreed      dw  0

; ---------------------------------------------------------------------
        section .bss
        alignb  2
drv0        resb 1
spc         resb 1
nfat        resb 1
pend_chk    resb 1
has_lfn     resb 1
junk        resb 1
warn        resb 1
chainok     resb 1
isdir       resb 1
fcheck      resb 1
res         resw 1
rootsecs    resw 1
spf         resw 1
totsec      resd 1
rootstart   resd 1
datastart   resd 1
io_lo       resw 1
io_hi       resw 1
io_seg      resw 1
io_wr       resw 1
pkt         resb 10
m_lo        resw 1
m_hi        resw 1
m_off       resw 1
clusters    resw 1
maxclus     resw 1
cbytes      resw 1
fatseg      resw 1
pathlen     resw 1
reason      resw 1
cstart      resw 1
cur_lba     resd 1
cur_off     resw 1
cur         resb 32
pend_lo     resw MAXPEND
pend_hi     resw MAXPEND
pend_off    resw MAXPEND
lfnbuf      resb 264
path        resb 160
linebuf     resb 256
itstructs   resb MAXLVL*ITSZ
bootbuf     resb SECSZ
tmpsec      resb SECSZ
secbufs     resb MAXLVL*SECSZ
bitmap      resb 8192
            resb 1536
stack_top:
prog_end:
