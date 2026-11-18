; =====================================================================
;  IOPATCH.ASM  - Men£ d'arrencada configurable per a l'IO.SYS de
;                 l'MS-DOS 3.20 de l'Amstrad PC1512, sense FIXLDR.
;
;  Sintaxi:   IOPATCH [unitat:] [/U] [/F]
;               (sense /U)  aplica el peda‡ a C:\IO.SYS (o a la unitat)
;               /U          el desf…: l'IO.SYS torna a ser el de Microsoft
;               /F          accepta un IO.SYS de Microsoft que no sigui
;                           cap dels coneguts
;
;  Com funciona:
;   - Els primers 5120 bytes (0x1400) del nou IO.SYS s¢n el carregador
;     de Digital Research (amb el men£, el ratol¡ i la RAM fins a 736 KB)
;     i l'extensi¢ IOX amb la configuraci¢. La resta del fitxer no canvia.
;   - Abans, l'IO.SYS de Microsoft es copia sencer a DOS.SYS, que ‚s el
;     que el carregador arrenca quan es tria l'MS-DOS (el MSDOS.SYS no es
;     toca: el continua carregant l'IO.SYS de Microsoft com sempre).
;   - /U torna a posar els primers 5120 bytes a partir del DOS.SYS, i
;     esborra el DOS.SYS si el va crear l'IOPATCH: l'IO.SYS queda
;     exactament com era.
;   - L'IO.SYS no canvia de mida ni de lloc al disc (nom‚s s'hi
;     sobreescriuen bytes) i en conserva els atributs.
;
;  Reconeix:
;   - IO.SYS de Microsoft: els cinc coneguts (CRC32) o qualsevol amb /F.
;   - IO.SYS ja fet pel FIXLDR (carregador de DR sense men£), amb el seu
;     DOS.SYS: hi posa el men£ (/U deixa l'IO.SYS de Microsoft).
;   - IO.SYS amb el men£ (IOPATCH 4.x o 5): l'actualitza i en conserva
;     la configuraci¢.
;
;  Compatible amb MS-DOS 2.x/3.x (INT 21h 3Ch,3Dh,3Eh,3Fh,40h,41h,42h,
;  43h,4Ch).
;
;  Construcci¢ (cal IO_NOU.SYS, fet amb IOMENU.ASM, i CFG.INC):
;        nasm -f bin IOPATCH.ASM -o IOPATCH.COM
; =====================================================================

        cpu     8086
%include "CFG.INC"
        org     0x100

HEADSZ  equ     XOFF+XSIZE              ; 0x1400: carregador + IOX
MAXF    equ     20000                   ; mida m…xima de l'IO.SYS
FLAGOFF equ     XOFF+15                 ; 1 = el DOS.SYS el va crear l'IOPATCH
K_MS    equ     0                       ; IO.SYS de Microsoft
K_LDR   equ     1                       ; carregador de DR (FIXLDR), sense men£
K_MENU  equ     2                       ; carregador amb el men£ (IOX4)

e_      equ     0x8A                    ; Š
ee      equ     0x82                    ; ‚
o_      equ     0x95                    ; •
oo      equ     0xA2                    ; ¢
u_      equ     0xA3                    ; £
c_      equ     0x87                    ; ‡
a_      equ     0x85                    ; …

start:
        cld
        mov     dx, m_banner
        call    print

; ---- l¡nia d'ordres -------------------------------------------------
        mov     si, 0x81
.par:   lodsb
        cmp     al, ' '
        je      .par
        cmp     al, 9
        je      .par
        cmp     al, 0x0D
        je      .fipar
        cmp     al, '/'
        jne     .unit
        lodsb
        and     al, 0xDF
        cmp     al, 'U'
        jne     .f
        mov     byte [undo], 1
        jmp     short .par
.f:     cmp     al, 'F'
        jne     us
        mov     byte [force], 1
        jmp     short .par
.unit:  and     al, 0xDF
        cmp     al, 'A'
        jb      us
        cmp     al, 'Z'
        ja      us
        mov     [fname], al
        mov     [dname], al
        lodsb
        cmp     al, ':'
        jne     us
        jmp     short .par
.fipar:

; ---- llegeix l'IO.SYS ------------------------------------------------
        mov     ax, 0x4300
        mov     dx, fname
        int     0x21
        mov     dx, m_nofile
        jc      fail
        mov     [attr], cx
        mov     dx, fname
        mov     di, iob
        call    readf
        mov     dx, m_nofile
        jc      fail
        mov     dx, m_size
        cmp     ax, HEADSZ+16
        jb      fail
        cmp     ax, MAXF
        jae     fail
        mov     [fsize], ax

; ---- quina mena d'IO.SYS ‚s? -----------------------------------------
        mov     byte [kind], K_MS
        mov     si, iob+2
        call    isdr
        jne     .kok
        mov     byte [kind], K_LDR
        cmp     word [iob+XOFF], 'IO'
        jne     .kok
        cmp     word [iob+XOFF+2], 'X4'
        jne     .kok
        mov     byte [kind], K_MENU
.kok:

; ---- i el DOS.SYS? ---------------------------------------------------
        mov     dx, dname
        mov     di, dbuf
        call    readf
        jc      .nod
        mov     [dsize], ax
        mov     byte [dexist], 1
.nod:
        cmp     byte [undo], 0
        je      install
        jmp     uninst

; =====================================================================
;  Aplicar
; =====================================================================
install:
        mov     si, head                        ; cap‡alera nova
        mov     di, hbuf
        push    ds
        pop     es
        mov     cx, HEADSZ
        rep     movsb
        cmp     byte [kind], K_MS
        je      .ms
        ; ---- ja t‚ un carregador de DR: cal el seu DOS.SYS ----
        call    dosok
        mov     dx, m_nodos
        jne     fail2
        mov     byte [hbuf+FLAGOFF], 0
        cmp     byte [kind], K_LDR
        je      .write
        ; ---- ja t‚ el men£: en conserva la configuraci¢ ----
        mov     al, [iob+FLAGOFF]
        mov     [hbuf+FLAGOFF], al
        mov     si, iob+CFGOFF
        call    cfgok
        jne     .same
        mov     di, hbuf+CFGOFF
        mov     cx, CFGSZ
        rep     movsb
.same:  mov     si, hbuf                        ; ja ‚s igual?
        mov     di, iob
        mov     cx, HEADSZ
        repe    cmpsb
        jne     .write
        mov     dx, m_ja
        jmp     ok0

        ; ---- IO.SYS de Microsoft ----
.ms:    cmp     byte [iob], 0xE9                ; comen‡a amb un JMP
        mov     dx, m_notms
        jne     fail2
        call    crc32
        mov     si, known
.kn:    cmp     si, known_end
        jae     .unk
        cmp     ax, [si]
        jne     .nx
        cmp     dx, [si+2]
        je      .known
.nx:    add     si, 4
        jmp     short .kn
.unk:   cmp     byte [force], 0
        mov     dx, m_unk
        je      fail2
.known: cmp     byte [dexist], 0
        je      .mkdos
        ; ja hi ha un DOS.SYS: ha de ser igual que aquest IO.SYS
        mov     ax, [dsize]
        cmp     ax, [fsize]
        mov     dx, m_dosdif
        jne     fail2
        mov     si, dbuf
        mov     di, iob
        mov     cx, [fsize]
        repe    cmpsb
        jne     fail2
        mov     byte [hbuf+FLAGOFF], 0          ; no l'he creat jo
        jmp     short .write
.mkdos: call    mkdos
        mov     byte [hbuf+FLAGOFF], 1          ; l'he creat jo

        ; ---- escriu la cap‡alera nova a l'IO.SYS ----
.write: mov     si, hbuf
        call    writehead
        mov     dx, m_okpatch
        cmp     byte [hbuf+FLAGOFF], 0
        je      ok0
        mov     dx, m_okdos
        jmp     ok0

; =====================================================================
;  Desfer
; =====================================================================
uninst:
        cmp     byte [kind], K_MS
        mov     dx, m_jams
        je      ok0
        call    dosok
        mov     dx, m_nodos
        jne     fail2
        mov     si, dbuf
        call    writehead                       ; IO.SYS = Microsoft
        mov     dx, m_okundo
        cmp     byte [kind], K_MENU
        jne     ok0
        cmp     byte [iob+FLAGOFF], 1           ; DOS.SYS creat per mi?
        jne     ok0
        mov     ax, 0x4301
        xor     cx, cx
        mov     dx, dname
        int     0x21
        mov     ah, 0x41
        mov     dx, dname
        int     0x21
        mov     dx, m_okundo2
        jnc     ok0
        mov     dx, m_nodel
        jmp     short ok0

; =====================================================================
;  Sortides
; =====================================================================
fail2:  mov     byte [ecode], 2
        jmp     short fail
ok0:    mov     byte [ecode], 0
fail:   call    print
        mov     al, [ecode]
        mov     ah, 0x4C
        int     0x21
us:     mov     dx, m_us
        jmp     short fail

; ---- dosok: ZF=1 si el DOS.SYS ‚s l'IO.SYS de Microsoft d'aquest -----
;      (mateixa mida, mateix contingut a partir de HEADSZ, i no ‚s un
;      carregador de DR)
dosok:  cmp     byte [dexist], 0
        je      .no
        mov     ax, [dsize]
        cmp     ax, [fsize]
        jne     .r
        mov     si, dbuf+2
        call    isdr
        je      .no
        cmp     byte [dbuf], 0xE9
        jne     .r
        mov     si, dbuf+HEADSZ
        mov     di, iob+HEADSZ
        mov     cx, [fsize]
        sub     cx, HEADSZ
        repe    cmpsb
.r:     ret
.no:    or      sp, sp                          ; ZF=0
        ret

; ---- isdr: ZF=1 si a SI hi ha 'DIGITAL RESEARCH' --------------------
isdr:   mov     di, s_dr
        mov     cx, 16
        push    ds
        pop     es
        repe    cmpsb
        ret

; ---- cfgok: ZF=1 si la configuraci¢ a SI ‚s v…lida (preserva SI) -----
cfgok:  cmp     word [si+C_MAGIC], 'CF'
        jne     .r
        push    si
        mov     cx, CFGSZ
        xor     ah, ah
.s:     lodsb
        add     ah, al
        loop    .s
        pop     si
        or      ah, ah
.r:     ret

; ---- readf: llegeix el fitxer DX a DI (fins a MAXF); AX = mida, CF ---
readf:  mov     ax, 0x3D00
        int     0x21
        jc      .r
        mov     bx, ax
        mov     ah, 0x3F
        mov     cx, MAXF
        mov     dx, di
        int     0x21
        pushf
        push    ax
        mov     ah, 0x3E
        int     0x21
        pop     ax
        popf
.r:     ret

; ---- mkdos: copia l'IO.SYS a DOS.SYS i ho comprova --------------------
mkdos:  mov     ah, 0x3C
        xor     cx, cx
        mov     dx, dname
        int     0x21
        mov     dx, m_mkdos
        jc      .err
        mov     bx, ax
        mov     ah, 0x40
        mov     cx, [fsize]
        mov     dx, iob
        int     0x21
        jc      .cls
        cmp     ax, [fsize]
        jne     .cls
        mov     ah, 0x3E
        int     0x21
        jc      .del
        mov     dx, dname                       ; torna'l a llegir
        mov     di, dbuf
        call    readf
        jc      .del
        cmp     ax, [fsize]
        jne     .del
        mov     si, dbuf
        mov     di, iob
        mov     cx, [fsize]
        repe    cmpsb
        jne     .del
        mov     ax, 0x4301                      ; ocult, sistema, nom‚s lectura
        mov     cx, 7
        mov     dx, dname
        int     0x21
        ret
.cls:   mov     ah, 0x3E
        int     0x21
.del:   mov     ah, 0x41                        ; no deixa un DOS.SYS a mitges
        mov     dx, dname
        int     0x21
        mov     dx, m_mkdos
.err:   mov     byte [ecode], 3
        jmp     fail

; ---- writehead: escriu HEADSZ bytes de SI al principi de l'IO.SYS ----
writehead:
        mov     [wsrc], si
        mov     ax, 0x4301                      ; treu R/H/S temporalment
        xor     cx, cx
        mov     dx, fname
        int     0x21
        mov     dx, m_attr
        jc      .err
        mov     ax, 0x3D02
        mov     dx, fname
        int     0x21
        mov     dx, m_open
        jc      .rest
        mov     bx, ax
        mov     ah, 0x40                        ; s'obre al principi
        mov     cx, HEADSZ
        mov     dx, [wsrc]
        int     0x21
        mov     dx, m_werr
        jc      .cls
        cmp     ax, HEADSZ
        jne     .cls
        mov     ah, 0x3E
        int     0x21
        jc      .rest
        call    rattr
        ret
.cls:   push    dx
        mov     ah, 0x3E
        int     0x21
        pop     dx
.rest:  push    dx
        call    rattr
        pop     dx
.err:   mov     byte [ecode], 3
        jmp     fail
rattr:  mov     ax, 0x4301
        mov     cx, [attr]
        mov     dx, fname
        int     0x21
        ret

; ---- crc32 de l'IO.SYS: DX:AX ----------------------------------------
crc32:  mov     si, iob
        mov     cx, [fsize]
        mov     ax, 0xFFFF
        mov     dx, ax
.b:     xor     al, [si]
        inc     si
        mov     bl, 8
.bit:   shr     dx, 1
        rcr     ax, 1
        jnc     .z
        xor     dx, 0xEDB8
        xor     ax, 0x8320
.z:     dec     bl
        jnz     .bit
        loop    .b
        not     ax
        not     dx
        ret

print:  mov     ah, 9
        int     0x21
        ret

; ---- dades ------------------------------------------------------------
fname   db      'C:\IO.SYS', 0
dname   db      'C:\DOS.SYS', 0
undo    db      0
force   db      0
kind    db      0
dexist  db      0
ecode   db      1
attr    dw      0
fsize   dw      0
dsize   dw      0
wsrc    dw      0
s_dr    db      'DIGITAL RESEARCH'

known:  dd      0x732A8228                      ; castell… (Amstrad), 16235
        dd      0x841BA4E3                      ; castell…, 16508
        dd      0x2AE4F3A1                      ; castell…, 16511
        dd      0x57DF53B2                      ; anglŠs, 16426
        dd      0xFA6444AE                      ; francŠs, 16504
known_end:

m_banner db     'IOPATCH 5.0 - men', u_, ' d', 39, 'arrencada i RAM fins a 736 KB per a l', 39, 'IO.SYS de l', 39, 'MS-DOS 3.20', 13, 10, '$'
m_us    db      'Sintaxi: IOPATCH [unitat:] [/U] [/F]', 13, 10
        db      '  /U  desf', a_, ' el peda', c_, ' (torna a l', 39, 'IO.SYS de Microsoft)', 13, 10
        db      '  /F  accepta un IO.SYS de Microsoft desconegut', 13, 10, '$'
m_nofile db     'No trobo (o no puc llegir) \IO.SYS en aquesta unitat.', 13, 10, '$'
m_size  db      'L', 39, 'IO.SYS no t', ee, ' una mida possible. No he tocat res.', 13, 10, '$'
m_notms db      'L', 39, 'IO.SYS no sembla de Microsoft ni del carregador de DR. No he tocat res.', 13, 10, '$'
m_unk   db      'Aquest IO.SYS de Microsoft no ', ee, 's cap dels coneguts. No he tocat res.', 13, 10
        db      'Si saps que ', ee, 's l', 39, 'MS-DOS 3.2x d', 39, 'un PC1512, fes IOPATCH /F', 13, 10, '$'
m_dosdif db     'Ja hi ha un DOS.SYS i no ', ee, 's igual que aquest IO.SYS. No he tocat res.', 13, 10
        db      'Si sobra, esborra', 39, 'l (o canvia-li el nom) i torna-ho a provar.', 13, 10, '$'
m_nodos db     'No trobo el DOS.SYS que correspon a aquest IO.SYS (l', 39, 'IO.SYS de', 13, 10
        db      'Microsoft original). No he tocat res.', 13, 10, '$'
m_mkdos db      'No puc crear el DOS.SYS (disc ple o arrel plena?). No he tocat l', 39, 'IO.SYS.', 13, 10, '$'
m_attr  db      'No puc canviar els atributs de l', 39, 'IO.SYS. No he tocat res.', 13, 10, '$'
m_open  db      'No puc obrir l', 39, 'IO.SYS per escriure-hi. No he tocat res.', 13, 10, '$'
m_werr  db      'ERROR en escriure l', 39, 'IO.SYS! Restaura la c', o_, 'pia del disc.', 13, 10, '$'
m_ja    db      'El men', u_, ' (versi', oo, ' actual) ja hi era. No cal fer res.', 13, 10, '$'
m_jams  db      'L', 39, 'IO.SYS ja ', ee, 's el de Microsoft. No cal fer res.', 13, 10, '$'
m_okdos db      'IO.SYS copiat a DOS.SYS (ocult). '
m_okpatch db    'Peda', c_, ' aplicat. Configura el men', u_, ' amb IOCONFIG i reinicia.', 13, 10, '$'
m_okundo db     'Peda', c_, ' desfet: l', 39, 'IO.SYS torna a ser el de Microsoft.', 13, 10, '$'
m_okundo2 db    'Peda', c_, ' desfet: l', 39, 'IO.SYS torna a ser el de Microsoft i el DOS.SYS', 13, 10
        db      'que havia creat l', 39, 'IOPATCH s', 39, 'ha esborrat.', 13, 10, '$'
m_nodel db      'Peda', c_, ' desfet, per', o_, ' no he pogut esborrar el DOS.SYS.', 13, 10, '$'

head:   incbin  'IO_NOU.SYS', 0, HEADSZ         ; carregador + IOX (config per defecte)

hbuf    equ     head+HEADSZ                     ; cap‡alera que s'escriur…
iob     equ     hbuf+HEADSZ                     ; l'IO.SYS
dbuf    equ     iob+MAXF                        ; el DOS.SYS
%if (dbuf-$$+0x100+MAXF) > 0xF000
  %error "massa mem•ria"
%endif
