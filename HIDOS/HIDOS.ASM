; =====================================================================
;  HIDOS.ASM - Posa el nucli de l'MS-DOS 3.20 (MSDOS.SYS) i les seves
;              taules (FILES, BUFFERS, FCBS, unitats, controladors del
;              CONFIG.SYS) a la mem•ria superior.            versi¢ 0.13
;
;  Sintaxi:   HIDOS [unitat:] [/H:inici-final] [/B|/B-] [/L:BFC|/L-] [/S|/S-]
;                    [/N|/N-] [/U]
;               (sense /U)  aplica el peda‡ a C:\DOS.SYS
;               /H:BE00-FBFF  RAM superior que es fa servir (segments,
;                           en hexadecimal; per defecte BE00-FBFF)
;               /B          tamb‚ el BIOS del DOS.SYS a dalt (/B-: no)
;               /N          nom‚s les ordres noves del CONFIG.SYS (REM,
;                           DEVICEHIGH, ...LOW): MS-DOS a baix (/N-: no)
;               /U          el desf…: el DOS.SYS torna a ser l'original
;
;  Per a la instalúlaci¢ de l'IOPATCH 5.0: C:\IO.SYS ‚s el carregador
;  amb el men£ i C:\DOS.SYS ‚s l'IO.SYS de Microsoft (MS-DOS 3.20
;  castell… de l'Amstrad, 16235 bytes, CRC32 732A8228). HIDOS el canvia
;  en 8 llocs i hi afegeix HIDOSK.BIN al final:
;   - el SYSINIT es creu que la mem•ria acaba al final de la RAM
;     superior, i el nucli s'hi copia en lloc de darrere el BIOS: el DOS
;     hi fa les taules i la cadena de blocs;
;   - just abans de carregar l'intŠrpret (SHELL=), posa davant de la
;     cadena la mem•ria convencional i un bloc de sistema que tapa el
;     v¡deo i les ROM fins a la zona alta (com LOADHI i DOS 5).
;  Si en arrencar no troba RAM a tota la zona, arrenca com sempre.
;
;  Construcci¢:  nasm -f bin HIDOSK.ASM -o HIDOSK.BIN
;                nasm -f bin HIDOS.ASM -o HIDOS.COM
; =====================================================================

        cpu     8086
        org     100h

OSIZE   equ     16235                   ; DOS.SYS original
KOFF    equ     3F70h                   ; on va HIDOSK.BIN al fitxer
NSIZE   equ     KOFF+KSIZE              ; DOS.SYS amb el peda‡
NSIZE01 equ     KOFF+256                ; DOS.SYS amb el peda‡ de la 0.1
NSIZE02 equ     KOFF+544                ;   i de la 0.2
NSIZE03 equ     KOFF+752                ;   i de la 0.3
NSIZE04 equ     KOFF+960                ;   i de la 0.4
NSIZE05 equ     KOFF+1184               ;   i de la 0.5
NSIZE06 equ     KOFF+1504               ;   i de la 0.6
NSIZE07 equ     KOFF+1680               ;   i de la 0.7
NSIZE08 equ     KOFF+1648               ;   i de la 0.8
NSIZE09 equ     KOFF+1664               ;   i de la 0.9
NSIZE10 equ     KOFF+1888               ;   i de la 0.10
NSIZE11 equ     KOFF+2160               ;   i de la 0.11
NSIZE12 equ     KOFF+2176               ;   i de la 0.12
SYSI    equ     2FF0h                   ; inici del SYSINIT al fitxer
MAXF    equ     20000

e_      equ     8Ah
ee      equ     82h
o_      equ     95h
oo      equ     0A2h
u_      equ     0A3h
c_      equ     87h
a_      equ     85h

start:  cld
        mov     dx,m_banner
        call    print
        mov     si,81h
.par:   lodsb
        cmp     al,' '
        je      .par
        cmp     al,9
        je      .par
        cmp     al,0Dh
        je      .fipar
        cmp     al,'/'
        jne     .unit
        lodsb
        and     al,0DFh
        cmp     al,'U'
        jne     .bb
        mov     byte [undo],1
        jmp     .par
.bb:    cmp     al,'B'
        jne     .h
        mov     byte [o_b],1
        cmp     byte [si],'-'
        jne     .par
        inc     si
        mov     byte [o_b],2
        jmp     .par
.h:     cmp     al,'N'                  ; /N nom‚s ordres, /N- tot normal
        jne     .hn
        mov     byte [o_n],1
        cmp     byte [si],'-'
        jne     .hs
        inc     si
        mov     byte [o_n],2
        jmp     .par
.hn:    cmp     al,'S'                  ; /S- intŠrpret a baix, /S a dalt
        jne     .hl
        mov     byte [o_s],1
        cmp     byte [si],'-'
        jne     .hs
        inc     si
        mov     byte [o_s],2
.hs:    jmp     .par
.hl:    cmp     al,'L'                  ; /L:BFC (taules a baix) o /L-
        jne     .h0
        lodsb
        cmp     al,'-'
        jne     .l0
        mov     byte [o_l],80h
        jmp     .par
.l0:    cmp     al,':'
        jne     us
        mov     byte [o_l],80h
.l1:    lodsb
        and     al,0DFh
        mov     ah,4
        cmp     al,'B'
        je      .l2
        mov     ah,1
        cmp     al,'F'
        je      .l2
        mov     ah,2
        cmp     al,'C'
        je      .l2
        dec     si
        cmp     byte [o_l],80h          ; /L: sense cap lletra
        je      us
        jmp     .par
.l2:    or      [o_l],ah
        jmp     .l1
.h0:    cmp     al,'H'
        jne     us
        lodsb
        cmp     al,':'
        jne     us
        call    gethex
        jc      us
        mov     [hs],ax
        lodsb
        cmp     al,'-'
        jne     us
        call    gethex
        jc      us
        inc     ax                      ; final inclusiu -> exclusiu
        jz      us
        mov     [he],ax
        mov     byte [o_h],1
        jmp     .par
.unit:  and     al,0DFh
        cmp     al,'A'
        jb      us
        cmp     al,'Z'
        ja      us
        mov     [fname],al
        lodsb
        cmp     al,':'
        jne     us
        jmp     .par
.fipar: cmp     byte [o_h],0            ; zona v…lida?
        je      .rd
        mov     ax,[hs]
        cmp     ax,0A000h
        jb      .badh
        mov     bx,[he]
        sub     bx,ax
        jbe     .badh
        cmp     bx,0A00h                ; com a m¡nim 40 KB (el nucli
        jae     .rd                     ;   en copia 40 KB)
.badh:  mov     dx,m_badh
        jmp     fail1

; ---- llegeix el DOS.SYS ---------------------------------------------
.rd:    mov     ax,4300h
        mov     dx,fname
        int     21h
        mov     dx,m_nofile
        jc      fail1
        mov     [attr],cx
        mov     ax,3D00h
        mov     dx,fname
        int     21h
        mov     dx,m_nofile
        jc      fail1
        mov     bx,ax
        mov     ah,3Fh
        mov     cx,MAXF
        mov     dx,buf
        int     21h
        pushf
        push    ax
        mov     ah,3Eh
        int     21h
        pop     ax
        popf
        mov     dx,m_nofile
        jc      fail1
        mov     [fsize],ax

; ---- quin ‚s? -----------------------------------------------------------
        cmp     ax,OSIZE
        jne     .p
        call    crc32
        cmp     ax,8228h
        jne     .unk
        cmp     dx,732Ah
        jne     .unk
        jmp     original
.p:     mov     word [rtab],recs01      ; el de HIDOS 0.1 o 0.2?
        cmp     ax,NSIZE01
        je      .p0
        mov     word [rtab],recs02
        cmp     ax,NSIZE02
        je      .p0
        mov     word [rtab],recs03
        cmp     ax,NSIZE03
        je      .p0
        mov     word [rtab],recs04
        cmp     ax,NSIZE04
        je      .p0
        mov     word [rtab],recs05
        cmp     ax,NSIZE05
        je      .p0
        mov     word [rtab],recs06
        cmp     ax,NSIZE06
        je      .p0
        mov     word [rtab],recs07
        cmp     ax,NSIZE07
        je      .p0
        mov     word [rtab],recs08
        cmp     ax,NSIZE08
        je      .p0
        mov     word [rtab],recs09
        cmp     ax,NSIZE09
        je      .p0
        mov     word [rtab],recs10
        cmp     ax,NSIZE10
        je      .p0
        mov     word [rtab],recs11
        cmp     ax,NSIZE11
        je      .p0
        cmp     ax,NSIZE12
        jne     .p2
        mov     word [rtab],recs12
        mov     byte [v12],1
.p0:    call    ispatch
        jne     .unk
        call    sigok
        jne     .unk
        call    unpatch
        mov     word [fsize],OSIZE
        call    crc32
        cmp     ax,8228h
        jne     .unk
        cmp     dx,732Ah
        jne     .unk
        cmp     byte [o_h],0            ; conserva la zona d'abans
        jne     .p1
        mov     ax,[buf+KOFF+0Eh]
        mov     [hs],ax
        mov     ax,[buf+KOFF+10h]
        mov     [he],ax
        mov     byte [o_h],1
.p1:    cmp     word [rtab],recs03      ; de la 0.3 o 0.4: conserva /B
        je      .p4
        cmp     word [rtab],recs04
        je      .p4
        cmp     word [rtab],recs05
        je      .p4
        cmp     word [rtab],recs06
        je      .p4
        cmp     word [rtab],recs07
        je      .p4
        cmp     word [rtab],recs08
        je      .p4
        cmp     word [rtab],recs09
        je      .p4
        cmp     word [rtab],recs10
        je      .p4
        cmp     word [rtab],recs11
        je      .p4
        cmp     byte [v12],0
        je      .p3
.p4:
        cmp     word [rtab],recs10      ; de la 0.10 i 0.11: conserva /L
        je      .p6
        cmp     word [rtab],recs11
        je      .p6
        cmp     byte [v12],0
        je      .p5
        cmp     byte [o_s],0            ; de la 0.12: conserva tamb‚ /S-
        jne     .p6
        test    byte [buf+KOFF+22h],8
        jz      .p6
        mov     byte [o_s],2
.p6:
        cmp     byte [o_l],0
        jne     .p5
        mov     al,[buf+KOFF+22h]
        or      al,80h
        mov     [o_l],al
.p5:    cmp     byte [o_b],0
        jne     .p3
        mov     al,2
        sub     al,[buf+KOFF+17h]
        mov     [o_b],al
.p3:    mov     word [rtab],recs
        cmp     byte [undo],0
        je      original
        mov     word [okmsg],m_okundo
        jmp     write
.p2:    mov     word [rtab],recs
        cmp     ax,NSIZE
        jne     .unk
        call    ispatch                 ; els 7 canvis hi s¢n?
        jne     .unk
        call    sigok
        jne     .unk
        call    unpatch                 ; i la resta ‚s l'original?
        mov     word [fsize],OSIZE
        call    crc32
        mov     word [fsize],NSIZE
        cmp     ax,8228h
        jne     .unk
        cmp     dx,732Ah
        jne     .unk
        call    dopatch                 ; (torna a posar els canvis)
        jmp     patched
.unk:   mov     dx,m_unk
        jmp     fail2

sigok:  mov     si,buf+KOFF+9           ; ZF=1 si hi ha 'HIDOS'
        mov     di,s_sig
        mov     cx,5
        push    ds
        pop     es
        repe    cmpsb
        ret

; ---- l'original: aplica el peda‡ ----------------------------------------
original:
        cmp     byte [undo],0
        mov     dx,m_jaorig
        jne     ok0
        call    dopatch
        mov     si,kblob                ; HIDOSK.BIN al final
        mov     di,buf+OSIZE
        mov     cx,KOFF-OSIZE
        xor     al,al
        push    ds
        pop     es
        rep     stosb
        mov     cx,KSIZE
        rep     movsb
        call    setrange
        mov     word [fsize],NSIZE
        mov     word [okmsg],m_okpatch
        jmp     write

; ---- ja t‚ el peda‡: /U el desf…, /H i /B canvien la zona i el BIOS -----
patched:
        cmp     byte [undo],0
        jne     .u
        mov     al,[o_h]
        or      al,[o_b]
        or      al,[o_l]
        or      al,[o_s]
        or      al,[o_n]
        mov     dx,m_ja
        jz      .ja
        call    setrange
        mov     word [okmsg],m_okrange
        jmp     write
.ja:    call    print                   ; diu la zona que hi ha
        mov     ax,[buf+KOFF+0Eh]
        call    phex4
        mov     dl,'-'
        call    putc
        mov     ax,[buf+KOFF+10h]
        dec     ax
        call    phex4
        mov     dx,m_bno
        cmp     byte [buf+KOFF+17h],0
        je      .jb
        mov     dx,m_bsi
.jb:    call    print
        mov     dx,m_nn                 ; nom‚s ordres (/N)
        test    byte [buf+KOFF+22h],10h
        jz      .jn
        call    print
.jn:    mov     dx,m_sh                 ; l'intŠrpret (/S-)
        test    byte [buf+KOFF+22h],8
        jz      .js
        call    print
.js:    mov     al,[buf+KOFF+22h]       ; i les taules a baix (/L)
        and     al,7
        jz      .jl
        mov     dx,m_lo
        call    print
        mov     dx,m_lb
        test    byte [buf+KOFF+22h],4
        jz      .j1
        call    print
.j1:    mov     dx,m_lf
        test    byte [buf+KOFF+22h],1
        jz      .j2
        call    print
.j2:    mov     dx,m_lc
        test    byte [buf+KOFF+22h],2
        jz      .j3
        call    print
.j3:    mov     dx,m_crlf
        jmp     ok0
.jl:    mov     dx,m_none
        jmp     ok0
.u:     call    unpatch
        mov     word [fsize],OSIZE
        mov     word [okmsg],m_okundo

; ---- escriu el DOS.SYS (al mateix lloc; si s'escur‡a, es talla) ----------
write:  mov     ax,4301h
        xor     cx,cx
        mov     dx,fname
        int     21h
        mov     dx,m_attr
        jc      fail3
        mov     ax,3D02h
        mov     dx,fname
        int     21h
        mov     dx,m_open
        jc      .rest
        mov     bx,ax
        mov     ah,40h
        mov     cx,[fsize]
        mov     dx,buf
        int     21h
        mov     dx,m_werr
        jc      .cls
        cmp     ax,[fsize]
        jne     .cls
        mov     ah,40h                  ; CX=0: talla el fitxer aqu¡
        xor     cx,cx
        int     21h
        jc      .cls
        mov     ah,3Eh
        int     21h
        jc      .rest
        call    rattr
        mov     dx,[okmsg]
        jmp     short ok0
.cls:   push    dx
        mov     ah,3Eh
        int     21h
        pop     dx
.rest:  push    dx
        call    rattr
        pop     dx
fail3:  mov     byte [ecode],3
        jmp     short fail
rattr:  mov     ax,4301h
        mov     cx,[attr]
        mov     dx,fname
        int     21h
        ret

fail1:  mov     byte [ecode],1
        jmp     short fail
fail2:  mov     byte [ecode],2
        jmp     short fail
ok0:    mov     byte [ecode],0
fail:   call    print
        mov     al,[ecode]
        mov     ah,4Ch
        int     21h
us:     mov     dx,m_us
        jmp     short fail1

; ---- canvis: taula (offset, mida, original, nou) ------------------------
; els valors nous es calculen aqu¡ (crides a la taula de salts)
CUP     equ     KOFF+0-(2980h+3)
CFIN    equ     KOFF+3-(2BDDh+3)
CLINK   equ     KOFF+6-(327Fh+3)
CENT    equ     KOFF+19h-3              ; entrada del DOS.SYS -> bioshi
CDH     equ     KOFF+1Ch-(3606h+3)      ; ordres del CONFIG.SYS -> dhook
CNH     equ     KOFF+1Fh-(35B9h+3)      ; segent l¡nia -> nhook
CHF     equ     KOFF+23h-(3329h+3)      ; FILES -> hkfil
CHC     equ     KOFF+26h-(3374h+3)      ; FCBS -> hkfcb
CHB     equ     KOFF+29h-(33DBh+3)      ; BUFFERS -> hkbuf
CHE     equ     KOFF+2Ch-(3486h+3)      ; despr‚s -> hkend
CTAB    equ     0F80h+2Fh               ; taula de paraules del CONFIG
SNEW    equ     KOFF+KSIZE-SYSI         ; mida nova del SYSINIT

recs:   ; offset, n, bytes originals ; bytes nous (a newb, mateix ordre)
        dw      0000h, 3
        db      0E9h,3Eh,28h,   0E9h,CENT & 0FFh,CENT >> 8
        dw      2980h, 3
        db      0A3h,17h,00h,   0E8h,CUP & 0FFh,CUP >> 8
        dw      299Bh, 2
        db      00h,01h,        GAP & 0FFh,GAP >> 8
        dw      2BDDh, 3
        db      0A3h,09h,00h,   0E8h,CFIN & 0FFh,CFIN >> 8
        dw      2C6Ah, 2
        db      00h,01h,        GAP & 0FFh,GAP >> 8
        dw      30FAh, 2
        db      7Bh,0Fh,        (SNEW-1) & 0FFh,(SNEW-1) >> 8
        dw      3104h, 2
        db      7Ch,0Fh,        SNEW & 0FFh,SNEW >> 8
        dw      327Fh, 5
        db      33h,0C0h,0B4h,4Bh,0F9h, 0E8h,CLINK & 0FFh,CLINK >> 8,90h,90h
        dw      35B9h, 5                ; SYSINIT 05C9h: segent l¡nia
        db      0Eh,1Fh,0E8h,0C2h,05h,  0E8h,CNH & 0FFh,CNH >> 8,90h,90h
        dw      3606h, 3                ; SYSINIT 0616h: cmp ah,'D'
        db      80h,0FCh,44h,   0E9h,CDH & 0FFh,CDH >> 8
        dw      3B04h, 2                ; SYSINIT 0B14h: taula de paraules
        db      0F9h,0Ch,       CTAB & 0FFh,CTAB >> 8
        dw      3329h, 3                ; SYSINIT 0339h: abans dels FILES
        db      0E8h,8Eh,08h,   0E8h,CHF & 0FFh,CHF >> 8
        dw      3374h, 3                ; SYSINIT 0384h: abans dels FCBS
        db      0E8h,43h,08h,   0E8h,CHC & 0FFh,CHC >> 8
        dw      33DBh, 5                ; SYSINIT 03EBh: abans dels BUFFERS
        db      83h,3Eh,1Ah,00h,0FFh, 0E8h,CHB & 0FFh,CHB >> 8,90h,90h
        dw      3486h, 3                ; SYSINIT 0496h: despr‚s
        db      0E8h,31h,07h,   0E8h,CHE & 0FFh,CHE >> 8
        dw      0FFFFh

; espai que deixa el BIOS per al SYSINIT mentre arrenca (par…grafs)
GAP     equ     ((0F80h+KSIZE+0FFh)/100h)*10h

; els de HIDOS 0.12 (forat de 180h par…grafs, HIDOSK de 2176 bytes)
SNEW12  equ     KOFF+2176-SYSI
recs12: ; offset, n, bytes originals ; bytes nous (a newb, mateix ordre)
        dw      0000h, 3
        db      0E9h,3Eh,28h,   0E9h,CENT & 0FFh,CENT >> 8
        dw      2980h, 3
        db      0A3h,17h,00h,   0E8h,CUP & 0FFh,CUP >> 8
        dw      299Bh, 2
        db      00h,01h,        80h,01h
        dw      2BDDh, 3
        db      0A3h,09h,00h,   0E8h,CFIN & 0FFh,CFIN >> 8
        dw      2C6Ah, 2
        db      00h,01h,        80h,01h
        dw      30FAh, 2
        db      7Bh,0Fh,        (SNEW12-1) & 0FFh,(SNEW12-1) >> 8
        dw      3104h, 2
        db      7Ch,0Fh,        SNEW12 & 0FFh,SNEW12 >> 8
        dw      327Fh, 5
        db      33h,0C0h,0B4h,4Bh,0F9h, 0E8h,CLINK & 0FFh,CLINK >> 8,90h,90h
        dw      35B9h, 5                ; SYSINIT 05C9h: segent l¡nia
        db      0Eh,1Fh,0E8h,0C2h,05h,  0E8h,CNH & 0FFh,CNH >> 8,90h,90h
        dw      3606h, 3                ; SYSINIT 0616h: cmp ah,'D'
        db      80h,0FCh,44h,   0E9h,CDH & 0FFh,CDH >> 8
        dw      3B04h, 2                ; SYSINIT 0B14h: taula de paraules
        db      0F9h,0Ch,       CTAB & 0FFh,CTAB >> 8
        dw      3329h, 3                ; SYSINIT 0339h: abans dels FILES
        db      0E8h,8Eh,08h,   0E8h,CHF & 0FFh,CHF >> 8
        dw      3374h, 3                ; SYSINIT 0384h: abans dels FCBS
        db      0E8h,43h,08h,   0E8h,CHC & 0FFh,CHC >> 8
        dw      33DBh, 5                ; SYSINIT 03EBh: abans dels BUFFERS
        db      83h,3Eh,1Ah,00h,0FFh, 0E8h,CHB & 0FFh,CHB >> 8,90h,90h
        dw      3486h, 3                ; SYSINIT 0496h: despr‚s
        db      0E8h,31h,07h,   0E8h,CHE & 0FFh,CHE >> 8
        dw      0FFFFh

; els de HIDOS 0.11 (forat de 180h par…grafs, HIDOSK de 2160 bytes)
SNEW11  equ     KOFF+2160-SYSI
recs11: ; offset, n, bytes originals ; bytes nous (a newb, mateix ordre)
        dw      0000h, 3
        db      0E9h,3Eh,28h,   0E9h,CENT & 0FFh,CENT >> 8
        dw      2980h, 3
        db      0A3h,17h,00h,   0E8h,CUP & 0FFh,CUP >> 8
        dw      299Bh, 2
        db      00h,01h,        80h,01h
        dw      2BDDh, 3
        db      0A3h,09h,00h,   0E8h,CFIN & 0FFh,CFIN >> 8
        dw      2C6Ah, 2
        db      00h,01h,        80h,01h
        dw      30FAh, 2
        db      7Bh,0Fh,        (SNEW11-1) & 0FFh,(SNEW11-1) >> 8
        dw      3104h, 2
        db      7Ch,0Fh,        SNEW11 & 0FFh,SNEW11 >> 8
        dw      327Fh, 5
        db      33h,0C0h,0B4h,4Bh,0F9h, 0E8h,CLINK & 0FFh,CLINK >> 8,90h,90h
        dw      35B9h, 5                ; SYSINIT 05C9h: segent l¡nia
        db      0Eh,1Fh,0E8h,0C2h,05h,  0E8h,CNH & 0FFh,CNH >> 8,90h,90h
        dw      3606h, 3                ; SYSINIT 0616h: cmp ah,'D'
        db      80h,0FCh,44h,   0E9h,CDH & 0FFh,CDH >> 8
        dw      3B04h, 2                ; SYSINIT 0B14h: taula de paraules
        db      0F9h,0Ch,       CTAB & 0FFh,CTAB >> 8
        dw      3329h, 3                ; SYSINIT 0339h: abans dels FILES
        db      0E8h,8Eh,08h,   0E8h,CHF & 0FFh,CHF >> 8
        dw      3374h, 3                ; SYSINIT 0384h: abans dels FCBS
        db      0E8h,43h,08h,   0E8h,CHC & 0FFh,CHC >> 8
        dw      33DBh, 5                ; SYSINIT 03EBh: abans dels BUFFERS
        db      83h,3Eh,1Ah,00h,0FFh, 0E8h,CHB & 0FFh,CHB >> 8,90h,90h
        dw      3486h, 3                ; SYSINIT 0496h: despr‚s
        db      0E8h,31h,07h,   0E8h,CHE & 0FFh,CHE >> 8
        dw      0FFFFh

; els de HIDOS 0.10 (forat de 170h par…grafs, HIDOSK de 1888 bytes)
SNEW10  equ     KOFF+1888-SYSI
recs10: ; offset, n, bytes originals ; bytes nous (a newb, mateix ordre)
        dw      0000h, 3
        db      0E9h,3Eh,28h,   0E9h,CENT & 0FFh,CENT >> 8
        dw      2980h, 3
        db      0A3h,17h,00h,   0E8h,CUP & 0FFh,CUP >> 8
        dw      299Bh, 2
        db      00h,01h,        70h,01h
        dw      2BDDh, 3
        db      0A3h,09h,00h,   0E8h,CFIN & 0FFh,CFIN >> 8
        dw      2C6Ah, 2
        db      00h,01h,        70h,01h
        dw      30FAh, 2
        db      7Bh,0Fh,        (SNEW10-1) & 0FFh,(SNEW10-1) >> 8
        dw      3104h, 2
        db      7Ch,0Fh,        SNEW10 & 0FFh,SNEW10 >> 8
        dw      327Fh, 5
        db      33h,0C0h,0B4h,4Bh,0F9h, 0E8h,CLINK & 0FFh,CLINK >> 8,90h,90h
        dw      35B9h, 5                ; SYSINIT 05C9h: segent l¡nia
        db      0Eh,1Fh,0E8h,0C2h,05h,  0E8h,CNH & 0FFh,CNH >> 8,90h,90h
        dw      3606h, 3                ; SYSINIT 0616h: cmp ah,'D'
        db      80h,0FCh,44h,   0E9h,CDH & 0FFh,CDH >> 8
        dw      3B04h, 2                ; SYSINIT 0B14h: taula de paraules
        db      0F9h,0Ch,       CTAB & 0FFh,CTAB >> 8
        dw      3329h, 3                ; SYSINIT 0339h: abans dels FILES
        db      0E8h,8Eh,08h,   0E8h,CHF & 0FFh,CHF >> 8
        dw      3374h, 3                ; SYSINIT 0384h: abans dels FCBS
        db      0E8h,43h,08h,   0E8h,CHC & 0FFh,CHC >> 8
        dw      33DBh, 5                ; SYSINIT 03EBh: abans dels BUFFERS
        db      83h,3Eh,1Ah,00h,0FFh, 0E8h,CHB & 0FFh,CHB >> 8,90h,90h
        dw      3486h, 3                ; SYSINIT 0496h: despr‚s
        db      0E8h,31h,07h,   0E8h,CHE & 0FFh,CHE >> 8
        dw      0FFFFh

; els de HIDOS 0.9 (forat de 160h par…grafs, HIDOSK de 1664 bytes)
SNEW09  equ     KOFF+1664-SYSI
recs09: ; offset, n, bytes originals ; bytes nous (a newb, mateix ordre)
        dw      0000h, 3
        db      0E9h,3Eh,28h,   0E9h,CENT & 0FFh,CENT >> 8
        dw      2980h, 3
        db      0A3h,17h,00h,   0E8h,CUP & 0FFh,CUP >> 8
        dw      299Bh, 2
        db      00h,01h,        60h,01h
        dw      2BDDh, 3
        db      0A3h,09h,00h,   0E8h,CFIN & 0FFh,CFIN >> 8
        dw      2C6Ah, 2
        db      00h,01h,        60h,01h
        dw      30FAh, 2
        db      7Bh,0Fh,        (SNEW09-1) & 0FFh,(SNEW09-1) >> 8
        dw      3104h, 2
        db      7Ch,0Fh,        SNEW09 & 0FFh,SNEW09 >> 8
        dw      327Fh, 5
        db      33h,0C0h,0B4h,4Bh,0F9h, 0E8h,CLINK & 0FFh,CLINK >> 8,90h,90h
        dw      35B9h, 5                ; SYSINIT 05C9h: segent l¡nia
        db      0Eh,1Fh,0E8h,0C2h,05h,  0E8h,CNH & 0FFh,CNH >> 8,90h,90h
        dw      3606h, 3                ; SYSINIT 0616h: cmp ah,'D'
        db      80h,0FCh,44h,   0E9h,CDH & 0FFh,CDH >> 8
        dw      3B04h, 2                ; SYSINIT 0B14h: taula de paraules
        db      0F9h,0Ch,       0A2h,0Fh
        dw      0FFFFh

; els de HIDOS 0.8 (forat de 160h par…grafs, HIDOSK de 1648 bytes)
SNEW08  equ     KOFF+1648-SYSI
recs08: ; offset, n, bytes originals ; bytes nous (a newb, mateix ordre)
        dw      0000h, 3
        db      0E9h,3Eh,28h,   0E9h,CENT & 0FFh,CENT >> 8
        dw      2980h, 3
        db      0A3h,17h,00h,   0E8h,CUP & 0FFh,CUP >> 8
        dw      299Bh, 2
        db      00h,01h,        60h,01h
        dw      2BDDh, 3
        db      0A3h,09h,00h,   0E8h,CFIN & 0FFh,CFIN >> 8
        dw      2C6Ah, 2
        db      00h,01h,        60h,01h
        dw      30FAh, 2
        db      7Bh,0Fh,        (SNEW08-1) & 0FFh,(SNEW08-1) >> 8
        dw      3104h, 2
        db      7Ch,0Fh,        SNEW08 & 0FFh,SNEW08 >> 8
        dw      327Fh, 5
        db      33h,0C0h,0B4h,4Bh,0F9h, 0E8h,CLINK & 0FFh,CLINK >> 8,90h,90h
        dw      35B9h, 5                ; SYSINIT 05C9h: segent l¡nia
        db      0Eh,1Fh,0E8h,0C2h,05h,  0E8h,CNH & 0FFh,CNH >> 8,90h,90h
        dw      3606h, 3                ; SYSINIT 0616h: cmp ah,'D'
        db      80h,0FCh,44h,   0E9h,CDH & 0FFh,CDH >> 8
        dw      3B04h, 2                ; SYSINIT 0B14h: taula de paraules
        db      0F9h,0Ch,       0A2h,0Fh
        dw      0FFFFh

; els de HIDOS 0.7 (forat de 170h par…grafs, HIDOSK de 1680 bytes)
SNEW07  equ     KOFF+1680-SYSI
recs07: ; offset, n, bytes originals ; bytes nous (a newb, mateix ordre)
        dw      0000h, 3
        db      0E9h,3Eh,28h,   0E9h,CENT & 0FFh,CENT >> 8
        dw      2980h, 3
        db      0A3h,17h,00h,   0E8h,CUP & 0FFh,CUP >> 8
        dw      299Bh, 2
        db      00h,01h,        70h,01h
        dw      2BDDh, 3
        db      0A3h,09h,00h,   0E8h,CFIN & 0FFh,CFIN >> 8
        dw      2C6Ah, 2
        db      00h,01h,        70h,01h
        dw      30FAh, 2
        db      7Bh,0Fh,        (SNEW07-1) & 0FFh,(SNEW07-1) >> 8
        dw      3104h, 2
        db      7Ch,0Fh,        SNEW07 & 0FFh,SNEW07 >> 8
        dw      327Fh, 5
        db      33h,0C0h,0B4h,4Bh,0F9h, 0E8h,CLINK & 0FFh,CLINK >> 8,90h,90h
        dw      35B9h, 5                ; SYSINIT 05C9h: segent l¡nia
        db      0Eh,1Fh,0E8h,0C2h,05h,  0E8h,CNH & 0FFh,CNH >> 8,90h,90h
        dw      3606h, 3                ; SYSINIT 0616h: cmp ah,'D'
        db      80h,0FCh,44h,   0E9h,CDH & 0FFh,CDH >> 8
        dw      3B04h, 2                ; SYSINIT 0B14h: taula de paraules
        db      0F9h,0Ch,       0A2h,0Fh
        dw      0FFFFh

; els de HIDOS 0.6 (forat de 160h par…grafs, HIDOSK de 1504 bytes)
SNEW06  equ     KOFF+1504-SYSI
recs06: ; offset, n, bytes originals ; bytes nous (a newb, mateix ordre)
        dw      0000h, 3
        db      0E9h,3Eh,28h,   0E9h,CENT & 0FFh,CENT >> 8
        dw      2980h, 3
        db      0A3h,17h,00h,   0E8h,CUP & 0FFh,CUP >> 8
        dw      299Bh, 2
        db      00h,01h,        60h,01h
        dw      2BDDh, 3
        db      0A3h,09h,00h,   0E8h,CFIN & 0FFh,CFIN >> 8
        dw      2C6Ah, 2
        db      00h,01h,        60h,01h
        dw      30FAh, 2
        db      7Bh,0Fh,        (SNEW06-1) & 0FFh,(SNEW06-1) >> 8
        dw      3104h, 2
        db      7Ch,0Fh,        SNEW06 & 0FFh,SNEW06 >> 8
        dw      327Fh, 5
        db      33h,0C0h,0B4h,4Bh,0F9h, 0E8h,CLINK & 0FFh,CLINK >> 8,90h,90h
        dw      35B9h, 5                ; SYSINIT 05C9h: segent l¡nia
        db      0Eh,1Fh,0E8h,0C2h,05h,  0E8h,CNH & 0FFh,CNH >> 8,90h,90h
        dw      3606h, 3                ; SYSINIT 0616h: cmp ah,'D'
        db      80h,0FCh,44h,   0E9h,CDH & 0FFh,CDH >> 8
        dw      3B04h, 2                ; SYSINIT 0B14h: taula de paraules
        db      0F9h,0Ch,       0A2h,0Fh
        dw      0FFFFh

; els de HIDOS 0.5 (forat de 150h par…grafs, HIDOSK de 1184 bytes)
SNEW05  equ     KOFF+1184-SYSI
recs05: ; offset, n, bytes originals ; bytes nous (a newb, mateix ordre)
        dw      0000h, 3
        db      0E9h,3Eh,28h,   0E9h,CENT & 0FFh,CENT >> 8
        dw      2980h, 3
        db      0A3h,17h,00h,   0E8h,CUP & 0FFh,CUP >> 8
        dw      299Bh, 2
        db      00h,01h,        50h,01h
        dw      2BDDh, 3
        db      0A3h,09h,00h,   0E8h,CFIN & 0FFh,CFIN >> 8
        dw      2C6Ah, 2
        db      00h,01h,        50h,01h
        dw      30FAh, 2
        db      7Bh,0Fh,        (SNEW05-1) & 0FFh,(SNEW05-1) >> 8
        dw      3104h, 2
        db      7Ch,0Fh,        SNEW05 & 0FFh,SNEW05 >> 8
        dw      327Fh, 5
        db      33h,0C0h,0B4h,4Bh,0F9h, 0E8h,CLINK & 0FFh,CLINK >> 8,90h,90h
        dw      35B9h, 5                ; SYSINIT 05C9h: segent l¡nia
        db      0Eh,1Fh,0E8h,0C2h,05h,  0E8h,CNH & 0FFh,CNH >> 8,90h,90h
        dw      3606h, 3                ; SYSINIT 0616h: cmp ah,'D'
        db      80h,0FCh,44h,   0E9h,CDH & 0FFh,CDH >> 8
        dw      3B04h, 2                ; SYSINIT 0B14h: taula de paraules
        db      0F9h,0Ch,       0A2h,0Fh
        dw      0FFFFh

; els de HIDOS 0.4 (forat de 140h par…grafs, HIDOSK de 960 bytes)
SNEW04  equ     KOFF+960-SYSI
recs04: ; offset, n, bytes originals ; bytes nous (a newb, mateix ordre)
        dw      0000h, 3
        db      0E9h,3Eh,28h,   0E9h,CENT & 0FFh,CENT >> 8
        dw      2980h, 3
        db      0A3h,17h,00h,   0E8h,CUP & 0FFh,CUP >> 8
        dw      299Bh, 2
        db      00h,01h,        40h,01h
        dw      2BDDh, 3
        db      0A3h,09h,00h,   0E8h,CFIN & 0FFh,CFIN >> 8
        dw      2C6Ah, 2
        db      00h,01h,        40h,01h
        dw      30FAh, 2
        db      7Bh,0Fh,        (SNEW04-1) & 0FFh,(SNEW04-1) >> 8
        dw      3104h, 2
        db      7Ch,0Fh,        SNEW04 & 0FFh,SNEW04 >> 8
        dw      327Fh, 5
        db      33h,0C0h,0B4h,4Bh,0F9h, 0E8h,CLINK & 0FFh,CLINK >> 8,90h,90h
        dw      0FFFFh

; els de HIDOS 0.3 (forat de 130h par…grafs, HIDOSK de 752 bytes)
SNEW03  equ     KOFF+752-SYSI
recs03: ; offset, n, bytes originals ; bytes nous (a newb, mateix ordre)
        dw      0000h, 3
        db      0E9h,3Eh,28h,   0E9h,CENT & 0FFh,CENT >> 8
        dw      2980h, 3
        db      0A3h,17h,00h,   0E8h,CUP & 0FFh,CUP >> 8
        dw      299Bh, 2
        db      00h,01h,        30h,01h
        dw      2BDDh, 3
        db      0A3h,09h,00h,   0E8h,CFIN & 0FFh,CFIN >> 8
        dw      2C6Ah, 2
        db      00h,01h,        30h,01h
        dw      30FAh, 2
        db      7Bh,0Fh,        (SNEW03-1) & 0FFh,(SNEW03-1) >> 8
        dw      3104h, 2
        db      7Ch,0Fh,        SNEW03 & 0FFh,SNEW03 >> 8
        dw      327Fh, 5
        db      33h,0C0h,0B4h,4Bh,0F9h, 0E8h,CLINK & 0FFh,CLINK >> 8,90h,90h
        dw      0FFFFh

; els de HIDOS 0.2 (forat de 120h par…grafs, HIDOSK de 544 bytes)
SNEW02  equ     KOFF+544-SYSI
recs02: ; offset, n, bytes originals ; bytes nous (a newb, mateix ordre)
        dw      2980h, 3
        db      0A3h,17h,00h,   0E8h,CUP & 0FFh,CUP >> 8
        dw      299Bh, 2
        db      00h,01h,        20h,01h
        dw      2BDDh, 3
        db      0A3h,09h,00h,   0E8h,CFIN & 0FFh,CFIN >> 8
        dw      2C6Ah, 2
        db      00h,01h,        20h,01h
        dw      30FAh, 2
        db      7Bh,0Fh,        (SNEW02-1) & 0FFh,(SNEW02-1) >> 8
        dw      3104h, 2
        db      7Ch,0Fh,        SNEW02 & 0FFh,SNEW02 >> 8
        dw      327Fh, 5
        db      33h,0C0h,0B4h,4Bh,0F9h, 0E8h,CLINK & 0FFh,CLINK >> 8,90h,90h
        dw      0FFFFh

; els de HIDOS 0.1 (forat de 110h par…grafs, HIDOSK de 256 bytes)
SNEW01  equ     KOFF+256-SYSI
recs01: ; offset, n, bytes originals ; bytes nous (a newb, mateix ordre)
        dw      2980h, 3
        db      0A3h,17h,00h,   0E8h,CUP & 0FFh,CUP >> 8
        dw      299Bh, 2
        db      00h,01h,        10h,01h
        dw      2BDDh, 3
        db      0A3h,09h,00h,   0E8h,CFIN & 0FFh,CFIN >> 8
        dw      2C6Ah, 2
        db      00h,01h,        10h,01h
        dw      30FAh, 2
        db      7Bh,0Fh,        (SNEW01-1) & 0FFh,(SNEW01-1) >> 8
        dw      3104h, 2
        db      7Ch,0Fh,        SNEW01 & 0FFh,SNEW01 >> 8
        dw      327Fh, 5
        db      33h,0C0h,0B4h,4Bh,0F9h, 0E8h,CLINK & 0FFh,CLINK >> 8,90h,90h
        dw      0FFFFh

; recorre la taula: AL = 0 compara amb els nous, 1 posa els nous,
; 2 posa els originals. ZF=1 si (AL=0) tots hi s¢n.
recwalk:
        mov     si,[rtab]
.l:     mov     di,[si]
        cmp     di,0FFFFh
        je      .ok
        mov     cx,[si+2]
        add     si,4
        add     di,buf
        mov     bx,si                   ; BX = originals
        add     si,cx                   ; SI = nous
        cmp     al,0
        jne     .w
        push    cx
        push    di
        push    si
        repe    cmpsb
        pop     si
        pop     di
        pop     cx
        jne     .r
        jmp     short .nx
.w:     push    si
        cmp     al,1
        je      .w1
        mov     si,bx
.w1:    push    cx
        rep     movsb
        pop     cx
        pop     si
.nx:    add     si,cx
        jmp     short .l
.ok:    xor     al,al                   ; ZF=1
.r:     ret
ispatch:
        push    ds
        pop     es
        mov     al,0
        jmp     recwalk
dopatch:
        push    ds
        pop     es
        mov     al,1
        jmp     recwalk
unpatch:
        push    ds
        pop     es
        mov     al,2
        jmp     recwalk

; ---- posa la zona /H al HIDOSK del buffer --------------------------------
setrange:
        cmp     byte [o_l],0            ; /L (sense tocar el bit de /S)
        je      .s
        mov     al,[o_l]
        and     al,7
        and     byte [buf+KOFF+22h],18h
        or      [buf+KOFF+22h],al
.s:     cmp     byte [o_s],0            ; /S, /S-
        je      .n
        and     byte [buf+KOFF+22h],17h
        cmp     byte [o_s],2
        jne     .n
        or      byte [buf+KOFF+22h],8
.n:     cmp     byte [o_n],0            ; /N, /N-
        je      .b
        and     byte [buf+KOFF+22h],0EFh
        cmp     byte [o_n],1
        jne     .b
        or      byte [buf+KOFF+22h],10h
.b:     cmp     byte [o_b],0            ; /B, /B-
        je      .h
        mov     al,[o_b]
        and     al,1
        mov     [buf+KOFF+17h],al
.h:     cmp     byte [o_h],0
        je      .r
        mov     ax,[hs]
        mov     [buf+KOFF+0Eh],ax
        mov     ax,[he]
        mov     [buf+KOFF+10h],ax
.r:     ret

; ---- gethex: n£mero hexadecimal de DS:SI -> AX (CF=1 si cap xifra) -------
gethex: xor     bx,bx
        xor     cx,cx
.l:     lodsb
        cmp     al,'0'
        jb      .e
        cmp     al,'9'
        jbe     .d
        and     al,0DFh
        cmp     al,'A'
        jb      .e
        cmp     al,'F'
        ja      .e
        sub     al,7
.d:     sub     al,'0'
        push    cx
        mov     cl,4
        shl     bx,cl
        pop     cx
        or      bl,al
        inc     cx
        cmp     cx,4
        jbe     .l
        stc
        ret
.e:     dec     si
        mov     ax,bx
        cmp     cx,1                    ; CF=1 si CX=0
        ret

; ---- crc32 de buf (fsize bytes) -> DX:AX ---------------------------------
crc32:  mov     si,buf
        mov     cx,[fsize]
        mov     ax,0FFFFh
        mov     dx,ax
.b:     xor     al,[si]
        inc     si
        mov     bl,8
.bit:   shr     dx,1
        rcr     ax,1
        jnc     .z
        xor     dx,0EDB8h
        xor     ax,8320h
.z:     dec     bl
        jnz     .bit
        loop    .b
        not     ax
        not     dx
        ret

print:  mov     ah,9
        int     21h
        ret
putc:   mov     ah,2
        int     21h
        ret
phex4:  mov     cx,4
.l:     push    cx
        mov     cl,4
        rol     ax,cl
        pop     cx
        push    ax
        and     al,0Fh
        add     al,'0'
        cmp     al,'9'
        jbe     .p
        add     al,7
.p:     mov     dl,al
        call    putc
        pop     ax
        loop    .l
        ret

; ---- dades -----------------------------------------------------------------
fname   db      'C:\DOS.SYS',0
s_sig   db      'HIDOS'
undo    db      0
o_h     db      0
o_b     db      0                       ; 1 = /B, 2 = /B-
o_l     db      0                       ; /L: 80h + 1 FILES, 2 FCBS, 4 BUFFERS
o_s     db      0                       ; 1 = /S, 2 = /S-
o_n     db      0                       ; 1 = /N, 2 = /N-
v12     db      0                       ; 1 = DOS.SYS de la 0.12
ecode   db      1
hs      dw      0
he      dw      0
attr    dw      0
fsize   dw      0
okmsg   dw      0
rtab    dw      recs

m_banner db     'HIDOS 0.13 - nucli de l', 39, 'MS-DOS 3.20 a la mem', o_, 'ria superior', 13, 10, '$'
m_us    db      'Sintaxi: HIDOS [unitat:] [/H:inici-final] [/B|/B-] [/L:BFC|/L-] [/S|/S-]', 13, 10
        db      '               [/N|/N-] [/U]', 13, 10
        db      '  /H:BE00-FBFF  RAM superior (per defecte BE00-FBFF)', 13, 10
        db      '  /B            tamb', ee, ' el BIOS del DOS.SYS a dalt (/B-: no)', 13, 10
        db      '  /L:BFC        BUFFERS, FILES i/o FCBS a la mem', o_, 'ria convencional', 13, 10
        db      '                (/L-: totes a dalt; al CONFIG.SYS: BUFFERSLOW=...)', 13, 10
        db      '  /S-           l', 39, 'int', e_, 'rpret (SHELL=) es pot carregar a la convencional', 13, 10
        db      '                (/S: a dalt, per defecte)', 13, 10
        db      '  /N            nom', ee, 's les ordres noves del CONFIG.SYS (REM,', 13, 10
        db      '                DEVICEHIGH, ...LOW); MS-DOS a baix (/N-: tot normal)', 13, 10
        db      '  /U            desf', a_, ' el peda', c_, 13, 10, '$'
m_badh  db      'Zona /H incorrecta: ha de ser per sobre d', 39, 'A000 i de 40 KB o m', e_, 's.', 13, 10, '$'
m_nofile db     'No trobo (o no puc llegir) \DOS.SYS en aquesta unitat.', 13, 10, '$'
m_unk   db      'Aquest DOS.SYS no ', ee, 's l', 39, 'IO.SYS de Microsoft que conec (MS-DOS 3.20', 13, 10
        db      'castell', a_, ' de l', 39, 'Amstrad, 16235 bytes) ni el mateix amb el peda', c_, '.', 13, 10
        db      'No he tocat res.', 13, 10, '$'
m_attr  db      'No puc canviar els atributs del DOS.SYS. No he tocat res.', 13, 10, '$'
m_open  db      'No puc obrir el DOS.SYS per escriure-hi. No he tocat res.', 13, 10, '$'
m_werr  db      'ERROR en escriure el DOS.SYS! Restaura la c', o_, 'pia del disc.', 13, 10, '$'
m_ja    db      'El peda', c_, ' ja hi era. Zona: $'
m_jaorig db     'El DOS.SYS ja ', ee, 's l', 39, 'original. No cal fer res.', 13, 10, '$'
m_okpatch db    'Peda', c_, ' aplicat. Reinicia i mira-ho amb MEM /D.', 13, 10, '$'
m_okrange db    'Configuraci', oo, ' canviada. Reinicia.', 13, 10, '$'
m_okundo db     'Peda', c_, ' desfet: el DOS.SYS torna a ser l', 39, 'original.', 13, 10, '$'
m_crlf  db      13, 10, '$'
m_bno   db      '  (BIOS a baix)', 13, 10, '$'
m_bsi   db      '  (BIOS a dalt: /B)', 13, 10, '$'
m_nn    db      '  Nom', ee, 's ordres noves (/N): MS-DOS a la mem', o_, 'ria convencional', 13, 10, '$'
m_sh    db      '  Int', e_, 'rpret (SHELL=) a la mem', o_, 'ria convencional: /S-', 13, 10, '$'
m_lo    db      '  A baix (/L):$'
m_lb    db      ' BUFFERS$'
m_lf    db      ' FILES$'
m_lc    db      ' FCBS$'
m_none  db      '$'

kblob:  incbin  'HIDOSK.BIN'
KSIZE   equ     $-kblob
buf:
