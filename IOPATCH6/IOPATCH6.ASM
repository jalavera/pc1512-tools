; =====================================================================
;  IOPATCH6.ASM - RAM convencional fins a 736 KB per a l'IO.SYS de
;                 l'MS-DOS 6.22 en un Amstrad PC1512 (o qualsevol XT).
;
;  Sintaxi:   IOPATCH6 [unitat:] [/U] [/F]
;               (sense /U)  aplica el peda‡ a C:\IO.SYS (o a la unitat)
;               /U          el desf…: l'IO.SYS torna a ser exactament
;                           l'original
;               /F          accepta un IO.SYS que no sigui cap dels
;                           coneguts per• que tingui la mateixa estructura
;
;  Com funciona:
;   L'IO.SYS de l'MS-DOS 6 comen‡a amb el carregador MSLOAD (els primers
;   1443/1446 bytes), que el sector d'arrencada carrega a 0070:0000. Una
;   de les primeres coses que fa ‚s INT 12h (mem•ria convencional). El
;   peda‡ canvia aquest INT 12h per una crida a una rutina que, si la
;   BIOS diu exactament 640 KB, prova la RAM de 16 KB en 16 KB des de
;   A000h fins a B7FFh (sense destruir-ne el contingut) i augmenta el
;   valor de la BIOS (0040:0013). Despr‚s fa l'INT 12h original.
;   La rutina va a la zona de zeros de l'offset 0x10 de l'MSLOAD (‚s
;   l'espai de la pila del carregador un cop s'ha recolúlocat, i no
;   s'utilitza fins despr‚s de la crida). Res m‚s canvia: el fitxer
;   mant‚ la mida, el lloc al disc i els atributs.
;
;  Construcci¢:  nasm -f bin IOPATCH6.ASM -o IOPATCH6.COM
; =====================================================================

        cpu     8086
        org     0x100

BLOFF   equ     0x10            ; on va la rutina dins l'IO.SYS
CALLOFF equ     0x1E9           ; INT 12h / MOV CL,6 de l'MSLOAD
ZEROEND equ     0x105           ; primera variable de l'MSLOAD
MAXF    equ     0xB000          ; mida m…xima de l'IO.SYS

e_      equ     0x8A
ee      equ     0x82
o_      equ     0x95
oo      equ     0xA2
u_      equ     0xA3
c_      equ     0x87
a_      equ     0x85

start:
        cld
        mov     dx, m_banner
        call    print
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
        mov     ax, 0x3D00
        mov     dx, fname
        int     0x21
        mov     dx, m_nofile
        jc      fail
        mov     bx, ax
        mov     ah, 0x3F
        mov     cx, MAXF
        mov     dx, iob
        int     0x21
        pushf
        push    ax
        mov     ah, 0x3E
        int     0x21
        pop     ax
        popf
        mov     dx, m_nofile
        jc      fail
        mov     [fsize], ax
        mov     dx, m_notms
        cmp     ax, 0x1000
        jb      fail2
        cmp     ax, MAXF
        jae     fail2

; ---- estat --------------------------------------------------------------
        call    ispatched
        je      patched
        call    isorig
        mov     dx, m_notms
        jne     fail2
        ; original
        cmp     byte [undo], 0
        mov     dx, m_jaorig
        jne     ok0
        call    crc32
        mov     si, known
.kn:    cmp     si, known_end
        jae     .unk
        cmp     ax, [si]
        jne     .nx
        cmp     dx, [si+2]
        je      .go
.nx:    add     si, 4
        jmp     short .kn
.unk:   cmp     byte [force], 0
        mov     dx, m_unk
        je      fail2
.go:    mov     si, blob                        ; aplica
        mov     di, iob+BLOFF
        mov     cx, BLSZ
        push    ds
        pop     es
        rep     movsb
        mov     si, callp
        mov     di, iob+CALLOFF
        movsw
        movsw
        mov     word [okmsg], m_okpatch
        jmp     short write

patched:
        cmp     byte [undo], 0
        mov     dx, m_ja
        je      ok0
        mov     di, iob+BLOFF                   ; desf…: zeros i INT 12h
        mov     cx, BLSZ
        xor     al, al
        push    ds
        pop     es
        rep     stosb
        mov     si, origc
        mov     di, iob+CALLOFF
        movsw
        movsw
        mov     word [okmsg], m_okundo

; ---- escriu els bytes 0..ZEROEND+... (fins a CALLOFF+4) -----------------
write:  mov     ax, 0x4301
        xor     cx, cx
        mov     dx, fname
        int     0x21
        mov     dx, m_attr
        jc      fail3
        mov     ax, 0x3D02
        mov     dx, fname
        int     0x21
        mov     dx, m_open
        jc      .rest
        mov     bx, ax
        mov     ah, 0x40                        ; principi del fitxer
        mov     cx, CALLOFF+4
        mov     dx, iob
        int     0x21
        mov     dx, m_werr
        jc      .cls
        cmp     ax, CALLOFF+4
        jne     .cls
        mov     ah, 0x3E
        int     0x21
        jc      .rest
        call    rattr
        mov     dx, [okmsg]
        jmp     short ok0
.cls:   push    dx
        mov     ah, 0x3E
        int     0x21
        pop     dx
.rest:  push    dx
        call    rattr
        pop     dx
fail3:  mov     byte [ecode], 3
        jmp     short fail

rattr:  mov     ax, 0x4301
        mov     cx, [attr]
        mov     dx, fname
        int     0x21
        ret

fail2:  mov     byte [ecode], 2
        jmp     short fail
ok0:    mov     byte [ecode], 0
fail:   call    print
        mov     al, [ecode]
        mov     ah, 0x4C
        int     0x21
us:     mov     dx, m_us
        jmp     short fail
print:  mov     ah, 9
        int     0x21
        ret

; ---- ispatched: ZF=1 si l'IO.SYS porta exactament aquest peda‡ --------
ispatched:
        mov     si, iob+BLOFF
        mov     di, blob
        mov     cx, BLSZ
        push    ds
        pop     es
        repe    cmpsb
        jne     .r
        mov     si, iob+CALLOFF
        mov     di, callp
        mov     cx, 4
        repe    cmpsb
        jne     .r
        call    restzero                        ; la resta de la zona, zeros
.r:     ret

; ---- isorig: ZF=1 si t‚ l'estructura de l'MSLOAD de l'MS-DOS 6 ----------
isorig: cmp     word [iob], 0x35E9              ; JMP 0138h
        jne     .r
        cmp     byte [iob+2], 0x01
        jne     .r
        mov     si, iob+CALLOFF                 ; INT 12h / MOV CL,6
        mov     di, origc
        mov     cx, 4
        push    ds
        pop     es
        repe    cmpsb
        jne     .r
        mov     di, iob+BLOFF                   ; zona de zeros
        mov     cx, BLSZ
        xor     al, al
        repe    scasb
        jne     .r
        call    restzero
.r:     ret

restzero:                                       ; zeros de BLOFF+BLSZ a ZEROEND
        mov     di, iob+BLOFF+BLSZ
        mov     cx, ZEROEND-BLOFF-BLSZ
        xor     al, al
        repe    scasb
        ret

; ---- crc32 de l'IO.SYS: DX:AX ------------------------------------------
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

; =====================================================================
;  Rutina que va dins l'IO.SYS, a l'offset BLOFF (s'executa a 0070:BLOFF)
; =====================================================================
blob:
        db      'IOPATCH6', 0                   ; signatura
bl_fix  equ     $-blob+BLOFF                    ; offset dins l'IO.SYS
        push    ds
        push    es
        push    bx
        push    cx
        mov     ax, 0x40
        mov     ds, ax
        mov     bx, [0x13]                      ; KB que diu la BIOS
        cmp     bx, 640
        jne     .fi                             ; nom‚s si ‚s exactament 640
        mov     ax, 0xA000
.bloc:  mov     es, ax
        mov     cx, [es:0]                      ; prova no destructiva
        mov     word [es:0], 0x55AA
        mov     word [es:2], 0                  ; "neteja" el bus
        cmp     word [es:0], 0x55AA
        jne     .rest
        mov     word [es:0], 0xAA55
        mov     word [es:2], 0xFFFF
        cmp     word [es:0], 0xAA55
        jne     .rest
        mov     [es:0], cx
        add     bx, 16                          ; +16 KB
        add     ax, 0x400
        cmp     ax, 0xB800
        jb      .bloc
        jmp     short .fi
.rest:  mov     [es:0], cx
.fi:    mov     [0x13], bx
        pop     cx
        pop     bx
        pop     es
        pop     ds
        int     0x12                            ; el que hi havia
        mov     cl, 6
        ret
BLSZ    equ     $-blob
%if BLOFF+BLSZ > ZEROEND
  %error "la rutina no cap"
%endif

; CALL bl_fix des de CALLOFF (E8 rel16) + NOP
callp:  db      0xE8
        dw      bl_fix-(CALLOFF+3)
        db      0x90
origc:  db      0xCD, 0x12, 0xB1, 0x06          ; INT 12h / MOV CL,6

; ---- dades ------------------------------------------------------------
fname   db      'C:\IO.SYS', 0
undo    db      0
force   db      0
ecode   db      1
attr    dw      0
fsize   dw      0
okmsg   dw      0

known:  dd      0xA92837B5                      ; MS-DOS 6.22 castell…, 40963
        dd      0xA7EA3BE4                      ; MS-DOS 6.22 anglŠs,   40774
known_end:

m_banner db     'IOPATCH6 1.0 - RAM convencional fins a 736 KB per a l', 39, 'IO.SYS de l', 39, 'MS-DOS 6.22', 13, 10, '$'
m_us    db      'Sintaxi: IOPATCH6 [unitat:] [/U] [/F]', 13, 10
        db      '  /U  desf', a_, ' el peda', c_, ' (torna a l', 39, 'IO.SYS original)', 13, 10
        db      '  /F  accepta un IO.SYS desconegut amb la mateixa estructura', 13, 10, '$'
m_nofile db     'No trobo (o no puc llegir) \IO.SYS en aquesta unitat.', 13, 10, '$'
m_notms db      'Aquest IO.SYS no t', ee, ' l', 39, 'estructura de l', 39, 'MS-DOS 6 que espero. No he tocat res.', 13, 10, '$'
m_unk   db      'Aquest IO.SYS no ', ee, 's cap dels coneguts (6.22 castell', a_, ' o angl', e_, 's).', 13, 10
        db      'No he tocat res. Si vols provar-ho igualment: IOPATCH6 /F', 13, 10, '$'
m_attr  db      'No puc canviar els atributs de l', 39, 'IO.SYS. No he tocat res.', 13, 10, '$'
m_open  db      'No puc obrir l', 39, 'IO.SYS per escriure-hi. No he tocat res.', 13, 10, '$'
m_werr  db      'ERROR en escriure l', 39, 'IO.SYS! Restaura la c', o_, 'pia del disc.', 13, 10, '$'
m_ja    db      'El peda', c_, ' ja hi era. No cal fer res.', 13, 10, '$'
m_jaorig db     'L', 39, 'IO.SYS ja ', ee, 's l', 39, 'original. No cal fer res.', 13, 10, '$'
m_okpatch db    'Peda', c_, ' aplicat. Reinicia: CHKDSK o MEM haurien de dir 736 KB.', 13, 10, '$'
m_okundo db     'Peda', c_, ' desfet: l', 39, 'IO.SYS torna a ser l', 39, 'original.', 13, 10, '$'

iob:                                            ; l'IO.SYS
%if (iob-$$+0x100+MAXF) > 0xFF00
  %error "massa mem•ria"
%endif
