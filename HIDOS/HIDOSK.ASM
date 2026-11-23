; =====================================================================
;  HIDOSK.ASM - Codi que HIDOS afegeix al final del DOS.SYS (MS-DOS 3.20
;               de l'Amstrad, IO.SYS castell… de Microsoft, 16235 bytes).
;  Va a la posici¢ 3F70h del fitxer, dins el segment del SYSINIT
;  (offset F80h). Taula de salts fixa al principi (HIDOS hi crida):
;    +0 uptop   +3 setfin   +6 link      +9 'HIDOS'
;    +0Eh ustart   +10h uend   (els escriu HIDOS amb /H)
;  Construcci¢:  nasm -f bin HIDOSK.ASM -o HIDOSK.BIN
; =====================================================================
        cpu     8086
        org     0F80h                   ; offset dins el SYSINIT

        jmp     near uptop
        jmp     near setfin
        jmp     near link
sig     db      'HIDOS'
ustart  dw      0BE00h                  ; on comen‡a la RAM superior
uend    dw      0FC00h                  ; primer par…graf sense RAM
hion    db      0                       ; 1 = la RAM hi ‚s: mode alt
lowseg  dw      0                       ; on hauria anat el nucli
convtop dw      0                       ; final de la mem•ria convencional
bion    db      0                       ; +17h  1 = tamb‚ el BIOS (/B)
bmoved  db      0                       ; +18h  1 = el BIOS s'ha copiat
        jmp     near bioshi             ; +19h  entrada del DOS.SYS (/B)
        jmp     near dhook              ; +1Ch  ordres del CONFIG.SYS
        jmp     near nhook              ; +1Fh  segent l¡nia del CONFIG
lowtab  db      0                       ; +22h  taules a baix: 1 FILES,
                                        ;       2 FCBS, 4 BUFFERS (HIDOS /L:);
                                        ;       8: intŠrpret a baix (/S-)
        jmp     near hkfil              ; +23h  abans dels FILES
        jmp     near hkfcb              ; +26h  abans dels FCBS
        jmp     near hkbuf              ; +29h  abans dels BUFFERS
        jmp     near hkend              ; +2Ch  despr‚s dels BUFFERS
; +2Fh  paraules del CONFIG.SYS: les noves i les de sempre (les noves,
; abans: es compara el principi de la paraula)
ctab    db      10,'DEVICEHIGH','h'
        db      3,'REM','r'             ; comentaris (com el DOS 4)
        db      10,'BUFFERSLOW','b'     ; BUFFERS m‚s, a la convencional
        db      8,'FILESLOW','f'        ; FILES m‚s, a baix
        db      7,'FCBSLOW','x'         ; els FCBS, a baix
        db      07h,42h,55h,46h,46h,45h,52h,53h,42h,05h,42h,52h,45h,41h
        db      4Bh,43h,06h,44h,45h,56h,49h,43h,45h,44h,05h,46h,49h,4Ch
        db      45h,53h,46h,04h,46h,43h,42h,53h,58h,09h,4Ch,41h,53h,54h
        db      44h,52h,49h,56h,45h,4Ch,08h,44h,52h,49h,56h,50h,41h,52h
        db      4Dh,50h,05h,53h,54h,41h,43h,4Bh,4Bh,07h,43h,4Fh,55h,4Eh
        db      54h,52h,59h,51h,05h,53h,48h,45h,4Ch,4Ch,53h,00h
lowon   db      0                       ; 1 = carregant un DEVICE a baix
nbuflo  db      0                       ; BUFFERSLOW=
nfillo  db      0                       ; FILESLOW=
sv5c    dw      0                       ; on anava el segent controlador
sv5e    dw      0                       ;   (a dalt) mentrestant
mcbseg  dw      0                       ; DEVICE a baix: el seu bloc (MCB)
firstlow dw     0                       ; el primer DEVICE a baix (0 = cap)
mcbname db      0,0,0,0,0,0,0,0         ; nom del fitxer, per al bloc
i12on   db      0                       ; DEVICEHIGH: INT 12h canviada
hdron   db      0                       ; DEVICE a dalt: cap‡alera posada
i12old  dd      0

; ---- bioshi: primera instrucci¢ del DOS.SYS (CS = 0070h) -------------
; Amb /B, si tota la zona ‚s RAM, copia tot el DOS.SYS al principi de la
; zona, hi arregla els segments 0070h escrits fixos i continua all…:
; el BIOS resident (CON, AUX, PRN, CLOCK$, discs) queda a dalt.
B       equ     2FF0h                   ; aqu¡ CS = 0070h: offset + 2FF0h
bioshi: pushf
        push    ax
        push    cx
        push    si
        push    di
        push    ds
        push    es
        cmp     byte [cs:bion+B],0
        je      .no
        mov     cx,[cs:ustart+B]        ; tota la zona ‚s RAM?
.t:     cmp     cx,[cs:uend+B]
        jae     .ok
        mov     es,cx
        mov     ax,[es:0]
        not     word [es:0]
        not     ax
        cmp     ax,[es:0]
        not     word [es:0]
        jne     .no
        add     cx,40h
        jmp     short .t
.ok:    mov     byte [cs:bmoved+B],1
        push    cs
        pop     ds
        mov     es,[cs:ustart+B]
        xor     si,si
        xor     di,di
        mov     cx,(3F70h+(fi-$$))/2    ; tot el DOS.SYS
        cld
        rep     movsw
        mov     ax,es                   ; segments 0070h fixos de la
        mov     si,fix70+B              ;   c•pia de dalt
.f:     mov     di,[cs:si]
        or      di,di
        jz      .f2
        mov     [es:di],ax
        inc     si
        inc     si
        jmp     short .f
.f2:    mov     [cs:3162h],ax           ; i les crides del SYSINIT (que
        mov     [cs:3504h],ax           ;   s'executa a baix)
        mov     [cs:.fj+B+3],ax
        pop     es
        pop     ds
        pop     di
        pop     si
        pop     cx
        pop     ax
        popf
.fj:    jmp     0070h:2841h             ; (el segment es posa aqu¡)
.no:    pop     es
        pop     ds
        pop     di
        pop     si
        pop     cx
        pop     ax
        popf
        jmp     near (2841h-B)
; offsets del DOS.SYS amb el segment 0070h escrit fix: cadena de
; controladors (CON, AUX, COM1, COM2, PRN, LPT1-3, CLOCK$, disc), taula
; de discos (BDS), un salt guardat (INT 13h) i crides llargues de la
; inicialitzaci¢.
fix70   dw      0BBAh,0C66h,0C78h,0C8Ah,0D2Bh,0D3Dh,0D4Fh,0D61h,0E49h
        dw      0F1Ah,0F25h,1384h,13D5h,1426h,1477h,1EEAh,2181h,21D2h
        dw      2515h,2572h,2597h,259Eh,25B7h,25C8h
        dw      0

; ---- uptop: AX = mem•ria (par…grafs), DS = SYSINIT -------------------
; (era mov [17h],ax). Si hi ha RAM de ustart a uend, el SYSINIT es creu
; que la mem•ria acaba a uend: s'hi posa ell i el DOS hi fa la cadena.
uptop:  push    ax
        push    cx
        push    es
        mov     [convtop],ax
        mov     byte [hion],0
        mov     cx,[ustart]
        cmp     cx,ax                   ; per sobre de la convencional
        jb      .no
        cmp     cx,[uend]
        jae     .no
.t:     cmp     cx,[uend]               ; prova cada KB sense esborrar-lo
        jae     .si
        mov     es,cx
        mov     ax,[es:0]
        not     word [es:0]
        not     ax
        cmp     ax,[es:0]
        not     word [es:0]
        jne     .no
        add     cx,40h
        jmp     short .t
.si:    mov     byte [hion],1
        mov     ax,[uend]
        jmp     short .w
.no:    mov     ax,[convtop]
.w:     mov     [17h],ax
        pop     es
        pop     cx
        pop     ax
        ret

; ---- setfin: AX = final del BIOS - 70h (par…grafs), DS = SYSINIT -----
; (era mov [9],ax). El nucli va a ustart en lloc de darrere el BIOS.
setfin: cmp     byte [bmoved],0
        jne     .b
        push    ax
        add     ax,70h
        mov     [lowseg],ax
        pop     ax
        cmp     byte [hion],0
        je      .w
        mov     ax,[ustart]
        sub     ax,70h                  ; (el SYSINIT hi suma 70h)
.w:     mov     [9],ax
        ret
.b:     mov     word [lowseg],70h       ; BIOS a dalt: el nucli just
        add     ax,[ustart]             ;   darrere el BIOS, i la
        sub     ax,70h                  ;   convencional des de 0070h
        mov     [9],ax
        ret

; ---- link: just abans de l'EXEC de l'intŠrpret (CS = SYSINIT) --------
; (era xor ax,ax / mov ah,4Bh / stc). Posa davant de la cadena la
; mem•ria convencional i un bloc de sistema ('SC', 0008h) que tapa del
; seu £ltim par…graf fins al primer bloc de dalt, com fa LOADHI.
; La mem•ria convencional queda reservada (propietari 0008h, nom
; 'HIDOS') mentre s'engega l'intŠrpret: aix¡ el SHELL= (LOADHI o
; COMMAND.COM) i el que reserva en engegar-se (l'entorn del COMMAND)
; van a dalt. Un ganxo petit a l'INT 21h (a dalt, 0008h) l'allibera
; quan el COMMAND.COM permanent (/P) executa el primer programa, o al
; tercer EXEC si no n'hi ha cap de permanent.
link:   call    msg                     ; diu on ‚s el DOS
        cmp     byte [cs:hion],0
        jne     .go
        jmp     .fi
.go:    push    bx
        push    cx
        push    dx
        push    si
        push    di
        push    ds
        push    es
        ; ---- el ganxo, a dalt (la cadena encara nom‚s ‚s de dalt) ----
        mov     byte [cs:hkok],0
        test    byte [cs:lowtab],8      ; /S-: l'intŠrpret pot anar a baix
        jz      .hk                     ;   (sense reserva)
        jmp     .nohk
.hk:    mov     ah,48h
        mov     bx,(HKSZ+15)/16
        int     21h
        jc      .nohk
        mov     es,ax
        dec     ax
        mov     ds,ax
        mov     word [1],8              ; propietari: el sistema
        push    cs
        pop     ds
        mov     si,hkstart
        xor     di,di
        mov     cx,HKSZ
        rep     movsb
        mov     ax,[cs:lowseg]
        mov     [es:hk_low-hkstart],ax
        push    es
        mov     ax,3521h
        int     21h
        mov     ax,es
        pop     es
        mov     [es:hk_old-hkstart],bx
        mov     [es:hk_old-hkstart+2],ax
        push    es
        pop     ds
        xor     dx,dx
        mov     ax,2521h
        int     21h
        mov     byte [cs:hkok],1
.nohk:  ; ---- la cadena ----
        mov     ah,52h
        int     21h                     ; ES:BX = llista de llistes
        mov     si,[es:bx-2]            ; primer bloc (a dalt)
        mov     ax,[cs:lowseg]
        mov     dx,[cs:convtop]
        dec     dx                      ; DX = bloc de sistema
        cmp     si,dx
        jbe     .x
        push    es
        mov     es,ax                   ; bloc a baix: lliure o reservat
        call    mcbclr
        mov     cx,dx
        sub     cx,ax
        dec     cx
        mov     [es:3],cx
        cmp     byte [cs:hkok],0
        je      .lliure
        mov     word [es:1],8
        mov     word [es:8],'HI'
        mov     word [es:10],'DO'
        mov     byte [es:12],'S'
.lliure:
        mov     es,dx                   ; bloc de sistema
        call    mcbclr
        mov     word [es:1],8
        mov     cx,si
        sub     cx,dx
        dec     cx
        mov     [es:3],cx
        mov     word [es:8],'SC'
        pop     es
        cmp     word [cs:firstlow],0    ; la cadena comen‡a a baix (pel
        je      .hd                     ;   primer DEVICE a baix, si n'hi ha)
        mov     ax,[cs:firstlow]
.hd:    mov     [es:bx-2],ax
.x:     pop     es
        pop     ds
        pop     di
        pop     si
        pop     dx
        pop     cx
        pop     bx
.fi:    mov     ax,4B00h
        stc
        ret
hkok    db      0

; ---- dhook: cada ordre del CONFIG.SYS (era cmp ah,'D' a 0616h) --------
; AH = lletra, ES:SI = nom del fitxer. Si el DOS ‚s a dalt:
; DEVICE ('D'): el controlador es carrega a la mem•ria convencional
;   (com sense HIDOS), en un bloc seu (MCB de sistema amb el nom del
;   fitxer, com el DOS 4).
; DEVICEHIGH ('h'): a la mem•ria superior, amb una cap‡alera amb el nom
;   i la mida; mentre s'inicia, l'INT 12h diu que la mem•ria arriba fins
;   al final de la zona alta (per als que la miren, com RAMDRIVE).
; El SYSINIT carrega el controlador on diu el punter [5Eh]:[5Ch].
dhook:  cmp     ah,'r'                  ; REM: res, a la l¡nia segent
        jne     .nr
        jmp     near 05C9h
.nr:    cmp     ah,'b'                  ; BUFFERSLOW=n: n BUFFERS m‚s, a
        jne     .nb                     ;   la mem•ria convencional
        call    near 0C2Fh              ; (el n£mero, com BUFFERS=)
        jc      .er
        cmp     ax,100
        jae     .er
        mov     [cs:nbuflo],al
        jmp     near 05C9h
.er:    jmp     near 0539h              ; "Comando irreconocible..."
.nb:    cmp     ah,'f'                  ; FILESLOW=n: n FILES m‚s, a baix
        jne     .nf
        call    near 0C2Fh
        jc      .er
        cmp     ax,0100h
        jae     .er
        mov     [cs:nfillo],al
        jmp     near 05C9h
.nf:    cmp     ah,'x'                  ; FCBSLOW=n,m: els FCBS, a baix
        jne     .nx
        or      byte [cs:lowtab],2
        mov     ah,'X'
        jmp     near 08E4h
.nx:    cmp     ah,'D'
        je      .low
        cmp     ah,'h'
        je      .high
        jmp     near 07F5h
.high:  mov     ah,'D'
        cmp     byte [cs:hion],0
        je      .d
        push    ax
        push    ds
        xor     ax,ax
        mov     ds,ax
        mov     ax,[48h]
        mov     [cs:i12old],ax
        mov     ax,[4Ah]
        mov     [cs:i12old+2],ax
        cli
        mov     word [48h],i12
        mov     [4Ah],cs
        sti
        pop     ds
        mov     byte [cs:i12on],1
        call    hdrbeg
        pop     ax
        jmp     short .d
.low:   cmp     byte [cs:hion],0        ; sense zona alta, com sempre
        je      .d
        call    lowbeg
        call    getname
.d:     jmp     near 061Eh

; ---- lowbeg: el que el SYSINIT posi ara al punter [5Eh]:[5Ch] anir… a
; la mem•ria convencional, en un bloc seu (a lowseg; el nom a mcbname)
lowbeg: push    ax
        mov     ax,[cs:5Ch]
        mov     [cs:sv5c],ax
        mov     ax,[cs:5Eh]
        mov     [cs:sv5e],ax
        mov     word [cs:5Ch],0
        mov     ax,[cs:lowseg]          ; el bloc a lowseg, el contingut
        mov     [cs:mcbseg],ax          ;   al par…graf segent
        inc     ax
        mov     [cs:5Eh],ax
        mov     byte [cs:lowon],1
        pop     ax
        ret

; ---- lowend: tanca el bloc de baix (si s'hi ha posat alguna cosa) i
; el punter torna a dalt
lowend: cmp     byte [cs:lowon],0
        jne     .s
        ret
.s:     push    ds
        push    cs
        pop     ds
        push    ax
        push    bx
        push    cx
        push    si
        push    di
        push    es
        mov     ax,[5Ch]                ; final (par…graf)
        add     ax,15
        mov     cl,4
        shr     ax,cl
        add     ax,[5Eh]
        mov     bx,[mcbseg]
        mov     cx,ax
        sub     cx,bx
        dec     cx                      ; CX = mida (par…grafs)
        jle     .nf                     ; no s'hi ha posat res
        mov     [lowseg],ax
        mov     es,bx                   ; el bloc: 'M', 0008h, mida, nom
        mov     byte [es:0],'M'
        mov     word [es:1],8
        mov     [es:3],cx
        mov     word [es:5],0
        mov     byte [es:7],0
        mov     si,mcbname
        mov     di,8
        mov     cx,4
.cp:    mov     ax,[si]
        mov     [es:di],ax
        add     si,2
        add     di,2
        loop    .cp
        cmp     word [firstlow],0
        jne     .rs
        mov     [firstlow],bx
        jmp     short .rs
.nf:    mov     [lowseg],bx             ; (el lloc queda lliure)
.rs:    mov     ax,[sv5c]
        mov     [5Ch],ax
        mov     ax,[sv5e]
        mov     [5Eh],ax
        mov     byte [lowon],0
        pop     es
        pop     di
        pop     si
        pop     cx
        pop     bx
        pop     ax
        pop     ds
        ret

; ---- les taules (FILES, FCBS, BUFFERS) a baix si ho diu lowtab ----
; Els ganxos van on el SYSINIT, acabat el CONFIG.SYS, les posa al
; punter: 0339h (call 0BCAh abans dels FILES), 0384h (abans dels FCBS),
; 03EBh (cmp [1Ah],-1, abans dels BUFFERS) i 0496h (despr‚s).
hkfil:  call    near 0BCAh
        push    ax
        push    si
        mov     al,1
        mov     si,n_files
        jmp     short hkx
hkfcb:  call    lowend
        call    filelo                  ; FILESLOW: una taula m‚s, a baix
        call    near 0BCAh
        push    ax
        push    si
        mov     al,2
        mov     si,n_fcbs
hkx:    call    tabbeg
        pop     si
        pop     ax
        ret
hkbuf:  call    lowend
        push    ax
        push    si
        mov     al,4
        mov     si,n_bufs
        call    tabbeg
        pop     si
        pop     ax
        cmp     word [cs:1Ah],byte -1   ; (el que hi havia)
        ret
hkend:  call    lowend
        call    buflo                   ; BUFFERSLOW: m‚s BUFFERS, a baix
        call    near 0BCAh
        ret

; ---- FILESLOW=n: una taula de n FILES (SFT) a baix, al final de la
; cadena de taules del DOS (en total, com a molt 255)
filelo: cmp     byte [cs:nfillo],0
        jne     .s
        ret
.s:     push    ds
        push    es
        push    ax
        push    bx
        push    cx
        push    si
        push    di
        mov     al,[cs:nfillo]
        xor     ah,ah
        mov     bl,[cs:1Ch]             ; FILES= (5 si no n'hi ha)
        xor     bh,bh
        cmp     bx,5
        jae     .t
        mov     bx,5
.t:     mov     cx,255
        sub     cx,bx
        cmp     ax,cx
        jbe     .t1
        mov     ax,cx
.t1:    or      ax,ax
        jz      .x
        push    ax
        mov     si,n_files
        mov     al,1
        call    tabbeg1                 ; (a baix si hi ha zona alta)
        call    near 0BCAh
        pop     cx                      ; CX = quants
        les     di,[cs:5Ch]
        mov     word [es:di],0FFFFh     ; la taula: final de cadena,
        mov     word [es:di+2],0FFFFh   ;   quants, i les entrades a 0
        mov     [es:di+4],cx
        mov     ax,35h
        mul     cx
        add     ax,6
        add     [cs:5Ch],ax
        push    di
        push    cx
        mov     cx,ax
        sub     cx,6
        add     di,6
        xor     al,al
        cld
        rep     stosb
        pop     cx
        pop     di
        mov     bx,es                   ; BX:DI = la taula nova
        lds     si,[cs:3]               ; la £ltima taula del DOS
        lds     si,[si+4]
.w:     cmp     word [si],0FFFFh
        je      .wl
        lds     si,[si]
        jmp     .w
.wl:    mov     [si],di
        mov     [si+2],bx
        call    lowend
.x:     pop     di
        pop     si
        pop     cx
        pop     bx
        pop     ax
        pop     es
        pop     ds
        ret

; ---- BUFFERSLOW=n: n BUFFERS m‚s, a baix (com fa el SYSINIT: cada un,
; cap‡alera de 16 bytes + un sector, al principi de la cadena)
buflo:  cmp     byte [cs:nbuflo],0
        jne     .s
        ret
.s:     push    ds
        push    es
        push    ax
        push    bx
        push    cx
        push    si
        push    di
        mov     si,n_bufs
        mov     al,4
        call    tabbeg1
        mov     cl,[cs:nbuflo]
        xor     ch,ch
.l:     push    cx
        call    near 0BCAh
        les     di,[cs:5Ch]
        lds     bx,[cs:3]
        mov     ax,[bx+12h]             ; el primer d'ara, darrere
        mov     [es:di],ax
        mov     ax,[bx+14h]
        mov     [es:di+2],ax
        mov     [bx+12h],di
        mov     [bx+14h],es
        mov     word [es:di+4],0FFh     ; (lliure)
        mov     ax,[bx+10h]             ; mida del sector
        add     ax,10h
        add     [cs:5Ch],ax
        pop     cx
        loop    .l
        call    lowend
        pop     di
        pop     si
        pop     cx
        pop     bx
        pop     ax
        pop     es
        pop     ds
        ret
; AL = bit de lowtab, SI = nom: si toca, comen‡a el bloc de baix
tabbeg: test    [cs:lowtab],al
        jz      tabr
; SI = nom: comen‡a el bloc de baix (si hi ha zona alta)
tabbeg1:
        cmp     byte [cs:hion],0
        je      tabr
        push    ax
        push    cx
        push    di
        mov     di,mcbname
        mov     cx,8
.c:     mov     al,[cs:si]
        mov     [cs:di],al
        inc     si
        inc     di
        loop    .c
        pop     di
        pop     cx
        pop     ax
        call    lowbeg
tabr:   ret
n_files db      'FILES',0,0,0
n_fcbs  db      'FCBS',0,0,0,0
n_bufs  db      'BUFFERS',0

; DEVICE= o DEVICEHIGH= a dalt: un par…graf de cap‡alera davant del
; controlador, com els subblocs del DOS 4 ('D', inici, mida, nom), per
; saber-ne el nom i la mida (MEM)
hdrbeg: push    ax
        push    cx
        mov     ax,[cs:5Ch]
        add     ax,15
        mov     cl,4
        shr     ax,cl
        add     ax,[cs:5Eh]
        mov     [cs:mcbseg],ax
        inc     ax
        mov     [cs:5Eh],ax
        mov     word [cs:5Ch],0
        mov     byte [cs:hdron],1
        call    getname
        pop     cx
        pop     ax
        ret

; ES:SI = cam¡ del fitxer -> mcbname (el nom sense extensi¢, 8 lletres)
getname:
        push    si
        push    di
        push    cx
        mov     di,si                   ; DI = despr‚s de l'£ltim \ o :
.f:     mov     al,[es:si]
        inc     si
        or      al,al
        jz      .c
        cmp     al,' '
        jbe     .c
        cmp     al,'\'
        je      .s
        cmp     al,':'
        jne     .f
.s:     mov     di,si
        jmp     .f
.c:     mov     si,di
        xor     di,di
        mov     cx,8
.n:     mov     al,[es:si]
        cmp     al,'.'
        je      .z
        cmp     al,' '
        jbe     .z
        mov     [cs:mcbname+di],al
        inc     si
        inc     di
        loop    .n
        jmp     short .r
.z:     mov     byte [cs:mcbname+di],0
        inc     di
        loop    .z
.r:     pop     cx
        pop     di
        pop     si
        ret

; INT 12h mentre s'inicia un DEVICEHIGH: KB fins al l¡mit del SYSINIT
i12:    mov     ax,[cs:22h]
        push    cx
        mov     cl,6
        shr     ax,cl
        pop     cx
        iret

; ---- nhook: despr‚s de cada ordre (era push cs, pop ds, call 0B90h) ---
; Despr‚s d'un DEVICE a baix: el seu bloc (MCB) i la mem•ria convencional
; lliure comen‡a on ha acabat; el punter torna a dalt. Despr‚s d'un
; DEVICEHIGH: l'INT 12h torna a ser la d'abans.
nhook:  push    cs
        pop     ds
        cmp     byte [i12on],0
        je      .l
        push    ax
        push    es
        xor     ax,ax
        mov     es,ax
        mov     ax,[i12old]
        cli
        mov     [es:48h],ax
        mov     ax,[i12old+2]
        mov     [es:4Ah],ax
        sti
        mov     byte [i12on],0
        pop     es
        pop     ax
.l:     cmp     byte [hdron],0          ; cap‡alera d'un DEVICE de dalt
        je      .l0
        push    ax
        push    bx
        push    cx
        push    si
        push    di
        push    es
        mov     byte [hdron],0
        mov     ax,[5Ch]
        add     ax,15
        mov     cl,4
        shr     ax,cl
        add     ax,[5Eh]
        mov     bx,[mcbseg]
        mov     cx,ax
        sub     cx,bx
        dec     cx
        jg      .hw
        mov     [5Eh],bx                ; no s'ha carregat: fora
        mov     word [5Ch],0
        jmp     short .hx
.hw:    mov     es,bx
        mov     byte [es:0],'D'
        mov     ax,bx
        inc     ax
        mov     [es:1],ax
        mov     [es:3],cx
        mov     word [es:5],0
        mov     byte [es:7],0
        mov     si,mcbname
        mov     di,8
        mov     cx,4
.hc:    mov     ax,[si]
        mov     [es:di],ax
        add     si,2
        add     di,2
        loop    .hc
.hx:    pop     es
        pop     di
        pop     si
        pop     cx
        pop     bx
        pop     ax
.l0:    call    lowend
.c:     call    near 0B90h
        ret

; ---- msg: el missatge de l'arrencada (CS = SYSINIT) ------------------
msg:    push    ax
        push    dx
        push    ds
        push    cs
        pop     ds
        mov     dx,m_hi
        cmp     byte [hion],0
        jne     .z
        mov     dx,m_lo
.z:     mov     ah,9
        int     21h
        mov     ax,[ustart]
        call    hex4
        mov     dl,'-'
        mov     ah,2
        int     21h
        mov     ax,[uend]
        dec     ax
        call    hex4
        mov     dx,m_lo2
        cmp     byte [hion],0
        je      .p
        mov     dx,m_bio
        cmp     byte [bmoved],0
        jne     .p
        mov     dx,m_fi
.p:     mov     ah,9
        int     21h
        pop     ds
        pop     dx
        pop     ax
        ret
hex4:   push    cx
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
.d:     mov     dl,al
        mov     ah,2
        int     21h
        pop     ax
        loop    .l
        pop     cx
        ret
m_hi    db      13,10,'HIDOS: MS-DOS a la mem',95h,'ria superior, $'
m_lo    db      13,10,'HIDOS: no hi ha RAM a $'
m_lo2   db      '; MS-DOS a baix.',13,10,'$'
m_bio   db      ' (BIOS incl',0A2h,'s).',13,10,'$'
m_fi    db      '.',13,10,'$'

; ---- el ganxo de l'INT 21h (es copia a dalt; CS = el seu bloc) ----------
hkstart:
        jmp     short hk_go
hk_old  dd      0                       ; INT 21h d'abans
hk_low  dw      0                       ; bloc reservat a baix
hk_cnt  db      0                       ; EXEC vistos
hk_done db      0
hk_go:  cmp     ah,4Bh
        jne     .ch
        cmp     byte [cs:hk_done-hkstart],0
        jne     .ch
        inc     byte [cs:hk_cnt-hkstart]
        cmp     byte [cs:hk_cnt-hkstart],1
        je      .ch                     ; el primer ‚s el del SHELL=
        push    ax
        push    bx
        push    es
        cmp     byte [cs:hk_cnt-hkstart],3
        jae     .rel
        mov     ah,62h                  ; PSP actual
        pushf
        call    far [cs:hk_old-hkstart]
        mov     es,bx
        cmp     [es:16h],bx             ; pare = ell mateix: COMMAND /P
        jne     .nr
.rel:   mov     byte [cs:hk_done-hkstart],1
        mov     es,[cs:hk_low-hkstart]
        cmp     word [es:1],8
        jne     .uh
        cmp     word [es:8],'HI'
        jne     .uh
        xor     ax,ax                   ; allibera la convencional
        mov     [es:1],ax
        mov     [es:8],ax
        mov     [es:10],ax
        mov     [es:12],ax
.uh:    xor     ax,ax                   ; treu el ganxo si encara ‚s el
        mov     es,ax                   ;   primer de la cadena
        cmp     word [es:84h],0
        jne     .nr
        mov     ax,cs
        cmp     [es:86h],ax
        jne     .nr
        cli
        mov     ax,[cs:hk_old-hkstart]
        mov     [es:84h],ax
        mov     ax,[cs:hk_old-hkstart+2]
        mov     [es:86h],ax
        sti
.nr:    pop     es
        pop     bx
        pop     ax
.ch:    jmp     far [cs:hk_old-hkstart]
HKSZ    equ     $-hkstart

mcbclr: push    ax                      ; MCB 'M' a ES:0, la resta a zero
        push    cx
        push    di
        xor     di,di
        xor     ax,ax
        mov     cx,8
        rep     stosw
        mov     byte [es:0],'M'
        pop     di
        pop     cx
        pop     ax
        ret
        align   16, db 0
fi:
