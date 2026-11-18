; =====================================================================
;  IOMENU.ASM - Peda‡ del carregador IO.SYS (DR "multi-boot") per a
;               l'Amstrad PC1512: men£ de selecci¢ configurable (versi¢ 4).
;
;  Versi¢ 4: el men£ ‚s a l'extensi¢ IOX (IOX.ASM), desada dins el mateix
;  IO.SYS a partir de l'offset A00h, que es configura amb IOCONFIG.COM.
;  El carregador la llegeix del disc abans del men£; si no hi ‚s o est…
;  malmesa, fa servir un men£ de reserva senzill (vegeu a sota).
;
;  Canvis respecte a l'original:
;   - Cim de la pila a 4800h (abans A10h) i c•pia del carregador fins a
;     A00h (abans 810h).
;   - El men£ (336h) detecta els sistemes i crida "pick": llegeix l'IOX
;     de l'IO.SYS i l'executa. Si l'IOX falta o est… malmesa, mostra la
;     llista original i accepta F1..F5; RETORN o 5 segons sense cap
;     tecla arrenquen l'MS-DOS (DOS.SYS), o el primer sistema.
;   - Si hi ha RAM entre 640 KB i 736 KB (A000h-B7FFh), l'afegeix al
;     comptador de mem•ria de la BIOS abans d'arrencar el sistema.
;   - La resta del carregador queda byte per byte igual.
;
;  Construcci¢ (cal DRLDR.BIN i IOX.BIN):
;       nasm -f bin IOX.ASM -o IOX.BIN
;       nasm -f bin IOMENU.ASM -o IO_NOU.SYS
;  DRLDR.BIN s¢n els primers 2064 bytes (810h) del carregador de disc
;  dur de Digital Research (el que instalúla el FIXLDR). El resultat,
;  IO_NOU.SYS, ‚s nom‚s la cap‡alera nova (1400h bytes: carregador +
;  IOX), que l'IOPATCH porta a dins.
; =====================================================================

        cpu     8086
%include "CFG.INC"
        org     0

%define ORIGF   'DRLDR.BIN'

; --- Rutines i dades existents del carregador original ------------------
SETMODE equ     0x02E0          ; reinicia el mode de v¡deo (esborra pantalla)
PUTS    equ     0x02E9          ; escriu cadena ASCIIZ (SI) amb INT 10h/0Eh
PUTNAME equ     0x030A          ; escriu "NOM.SYS" des de NAMEBUF
FINDF   equ     0x03F6          ; busca el fitxer (DX -> FCB), AL=0 si hi ‚s
TBL     equ     0x06B3          ; 5 punters als noms (0 = no trobat)
HND     equ     0x06BD          ; 5 adreces de rutina de c…rrega
JMPVEC  equ     0x06EF          ; vector de la rutina de c…rrega triada
COUNT   equ     0x06F1          ; nombre de sistemes trobats
FCB     equ     0x068F
NAMEBUF equ     0x0690
FSTR    equ     0x06FA          ; CR,LF,"F1 = ",0
FDIG    equ     0x06FD          ; el d¡git de "F1"
PROMPT  equ     0x0702          ; CR,LF,LF,"Escull sistema operatiu: ",0
RDREC   equ     0x0472          ; llegeix el segent registre de 128 bytes
DSTOFF  equ     0x0688          ; dest¡ dels registres (offset)
DSTSEG  equ     0x068A          ; dest¡ dels registres (segment)
XSEG    equ     0x0070          ; on es llegeix l'inici de l'IO.SYS


LOADSZ  equ     XOFF            ; bytes que el carregador es copia a dalt
                                ; (abans 0x810; ara fins on comen‡a l'IOX)
STACKTOP equ    0x4800          ; cim de la pila (abans 0xA10). El bloc que
                                ; es reserva a dalt de la mem•ria fa 4800h
                                ; bytes i el darrer buffer (directori, a
                                ; 2690h) acaba a 4690h: hi ha 368 bytes
                                ; lliures per a la pila.

; =====================================================================
        incbin  ORIGF, 0, 0x18
        mov     sp, STACKTOP                    ; era: mov sp,0xA10
        incbin  ORIGF, 0x1B, 0x51-0x1B
        mov     cx, LOADSZ                      ; era: mov cx,0x810
        incbin  ORIGF, 0x54, 0x336-0x54

; =====================================================================
;  0x336  Men£: detecta els sistemes presents i en deixa triar un
; =====================================================================
menu:
        mov     bx, 0
        mov     cx, 5
.det:   mov     si, [bx+TBL]
        push    cx
        push    bx
        push    ds
        pop     es
        mov     dx, FCB
        mov     di, dx
        inc     di
        movsw
        movsw
        movsw
        movsw
        call    FINDF
        pop     bx
        pop     cx
        cmp     al, 0
        jnz     .nohi
        inc     byte [COUNT]
        jmp     short .seg
.nohi:  mov     word [bx+TBL], 0
.seg:   inc     bx
        inc     bx
        loop    .det

        cmp     byte [COUNT], 0
        jnz     .algun
        jmp     .fi                             ; cap: torna (donar… error)
.algun: call    pick                            ; AH = ¡ndex triat (0..COUNT-1)

        ; --- converteix l'¡ndex en entrada de la taula ---
.tria:  mov     bx, 0
.m1:    cmp     word [bx+TBL], byte 0
        jnz     .m2
        inc     bx
        inc     bx
        jmp     short .m1
.m2:    cmp     ah, 0
        jz      .m3
        inc     bx
        inc     bx
        dec     ah
        jmp     short .m1
.m3:    mov     si, [bx+TBL]
        mov     di, [bx+HND]
        mov     [JMPVEC], di
        push    ds
        pop     es
        mov     di, NAMEBUF
        movsw
        movsw
        movsw
        movsw
        call    memfix                          ; ajusta la RAM i esborra pantalla
.fi:    ret

; ---- plist: llista "F1 = NOM.SYS", "F2 = ..." (men£ de reserva) -------
plist:  mov     bx, 0
        mov     cx, 5
        mov     byte [FDIG], '1'
.llst:  push    bx
        push    cx
        mov     si, [bx+TBL]
        test    si, si
        jz      .salt
        push    ds
        pop     es
        mov     di, NAMEBUF
        movsw
        movsw
        movsw
        movsw
        mov     si, FSTR
        call    PUTS
        call    PUTNAME
        inc     byte [FDIG]
.salt:  pop     cx
        pop     bx
        inc     bx
        inc     bx
        loop    .llst
        ret

%if ($-$$) > FINDF
  %error "menu massa llarg: sobreescriu FINDF"
%endif
        times   FINDF-($-$$) db 0x90

; =====================================================================
        incbin  ORIGF, FINDF, 0x47A-FINDF
; RDREC: el carregador original no llegia el darrer registre de 128
; bytes si era incomplet (ax = registre*128 + 128 > mida -> fi). Ara
; nom‚s ‚s fi si el registre comen‡a a la mida o m‚s enll….
        add     ax, 1
        incbin  ORIGF, 0x47D, 0x810-0x47D
; =====================================================================
; =====================================================================
;  0x810  pick: intenta el men£ nou (extensi¢ IOX dins l'IO.SYS); si no hi
;         ‚s o est… malmesa, fa servir el men£ de la versi¢ 3.
;         Sortida: AH = ¡ndex del sistema triat
; =====================================================================
pick:   call    loadext
        jc      .fb
        call    far [xvec]
        ret
.fb:    sub     ax, ax
        cmp     byte [COUNT], 1
        je      .r
        call    plist
        mov     si, PROMPT
        call    PUTS
        call    choose
.r:     ret

; ---- loadext: llegeix l'inici de l'IO.SYS a 0070:0000 i comprova l'IOX
;      Sortida: CF=0 i [xvec] = punt d'entrada si tot va b‚
loadext:
        push    ds
        pop     es
        mov     si, ioname
        mov     di, NAMEBUF
        movsw
        movsw
        movsw
        movsw
        mov     dx, FCB
        call    FINDF
        or      al, al
        jnz     .err
        xor     ax, ax
        mov     [FCB+0x20], ax                  ; registre actual = 0
        mov     [DSTOFF], ax
        mov     word [DSTSEG], XSEG
        mov     cx, NREC
.l:     push    cx
        mov     dx, FCB
        call    RDREC                           ; llegeix 128 bytes
        pop     cx
        or      al, al
        jnz     .err
        add     word [DSTSEG], 8
        loop    .l
        mov     word [FCB+0x20], 0              ; perquŠ el DOS es llegeixi b‚
        mov     ax, XSEG
        mov     es, ax
        cmp     word [es:XOFF], 'IO'
        jne     .bad
        cmp     word [es:XOFF+2], 'X4'
        jne     .bad
        mov     ax, [es:XOFF+4]
        mov     [xvec], ax
        mov     word [xvec+2], XSEG
        clc
        ret
.err:   mov     word [FCB+0x20], 0
.bad:   stc
        ret

;  choose: men£ de reserva (nom‚s si l'IOX falta o est… malmesa).
;         Llista ja escrita. F1..F5 trien directament; RETORN o 5 segons
;         sense cap tecla arrenquen l'MS-DOS (DOS.SYS) o el primer sistema.
;         Sortida: AH = ¡ndex del sistema triat
; ---------------------------------------------------------------------
choose: xor     al, al
        cmp     word [TBL+2], 0                 ; hi ha DOS.SYS?
        je      .d
        cmp     word [TBL], 0                   ; i DOSPLUS.SYS al davant?
        je      .d
        inc     al
.d:     mov     [sel], al
        call    ticks
        mov     [t0], ax
.w:     mov     ah, 1
        int     0x16
        jnz     .k
        call    ticks
        sub     ax, [t0]
        cmp     ax, 91                          ; ~5 segons
        jb      .w
.def:   mov     ah, [sel]
        ret
.k:     xor     ah, ah
        int     0x16
        cmp     al, 0x0D
        je      .def
        sub     ah, 0x3B                        ; F1..F5 -> 0..4
        jb      .w
        cmp     ah, [COUNT]
        jae     .w
        ret

; AX = comptador de tics de la BIOS (0040:006C)
ticks:  push    ds
        mov     ax, 0x40
        mov     ds, ax
        mov     ax, [0x6C]
        pop     ds
        ret

; ---------------------------------------------------------------------
;  memfix: si hi ha RAM a partir de 640 KB (A000h), l'afegeix al
;  comptador de mem•ria de la BIOS (0040:0013), fins a B800h (736 KB),
;  on comen‡a la mem•ria de v¡deo. Aix¡ el DOS la fa servir com a
;  mem•ria convencional. Despr‚s salta a SETMODE.
; ---------------------------------------------------------------------
memfix: push    ds
        push    es
        push    ax
        push    bx
        mov     ax, 0x40
        mov     ds, ax
        mov     bx, [0x13]                      ; KB que diu la BIOS
        cmp     bx, 640
        jne     .fi                             ; nom‚s si ‚s exactament 640
        mov     ax, 0xA000
.bloc:  mov     es, ax
        call    ramok
        jc      .fi                             ; aqu¡ ja no hi ha RAM
        add     bx, 16                          ; +16 KB
        add     ax, 0x400
        cmp     ax, 0xB800
        jb      .bloc
.fi:    mov     [0x13], bx
        pop     bx
        pop     ax
        pop     es
        pop     ds
        jmp     SETMODE

; ramok: CF=0 si ES:0000 ‚s RAM (prova no destructiva)
ramok:  push    ax
        push    cx
        mov     cx, [es:0]                      ; valor original
        mov     word [es:0], 0x55AA
        mov     word [cs:bus], 0                ; "neteja" el bus
        cmp     word [es:0], 0x55AA
        jne     .no
        mov     word [es:0], 0xAA55
        mov     word [cs:bus], 0xFFFF
        cmp     word [es:0], 0xAA55
        jne     .no
        mov     [es:0], cx                      ; restaura
        pop     cx
        pop     ax
        clc
        ret
.no:    pop     cx
        pop     ax
        stc
        ret

bus     dw      0
xvec    dw      0, 0                    ; punt d'entrada de l'IOX (far)
ioname  db      'IO      '              ; nom per buscar l'IO.SYS

sel     db      0
t0      dw      0

%if ($-$$) > LOADSZ
  %error "el carregador no cap abans de l'IOX"
%endif
        times   LOADSZ-($-$$) db 0

; =====================================================================
;  A00h: extensi¢ IOX (men£ configurable)
; =====================================================================
xbeg:   incbin  'IOX.BIN'
xfin:
NREC    equ     ((xfin-$$)+127)/128     ; registres de 128 bytes que cal llegir

; =====================================================================
