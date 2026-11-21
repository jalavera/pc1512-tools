; =====================================================================
;  DOSSHELL.ASM - Accessori d'escriptori GEM: shell de DOS
;                 (GEM 2.0, Amstrad PC1512).  Versio 0.2
;
;  Muntatge:   nasm -f bin DOSSHELL.ASM -o DOSSHELL.ACC
;  Us:         copiar DOSSHELL.ACC a \GEMBOOT i tornar a entrar al GEM.
;
;  Entrada "Shell de DOS" al menu d'accessoris, des de qualsevol
;  aplicacio GEM. Passa la pantalla a mode text (v_enter_cur del VDI) i
;  executa COMMAND.COM (el de COMSPEC). Amb EXIT es torna al GEM: el VDI
;  torna al mode grafic (v_exit_cur), es torna a posar la barra de menus
;  (guardada abans amb vro_cpyfm) i el GEM redibuixa l'escriptori i les
;  finestres (form_dial FMD_FINISH).
;  Mentre dura, el GEM esta aturat (wind_update) i el ratoli amagat.
;  Si no hi ha prou memoria de DOS lliure per a COMMAND.COM, ho diu amb
;  una alerta i no canvia res.
;  Fitxer petit (el GEM te poc espai per als accessoris): la barra de
;  menus es guarda en un bloc de memoria de DOS demanat en el moment.
;
;  - Executable MZ d'un sol segment (capcalera inclosa en aquest fitxer),
;    CS=DS=ES=SS, pila propia dins la imatge.
;  - Crides GEM per INT EFh:  AES -> CX=200, ES:BX   VDI -> CX=473h, DS:DX
; =====================================================================

        cpu     8086

section .hdr start=0
        db      'MZ'
        dw      (512+MIDA) % 512
        dw      (512+MIDA+511) / 512
        dw      0
        dw      32
        dw      0
        dw      20h                     ; memoria maxima: 512 bytes
        dw      0
        dw      pila_fi
        dw      0
        dw      inici
        dw      0
        dw      1Ch
        dw      0
        times   512-($-$$) db 0

section .text vstart=0 follows=.hdr

%macro AES 5                    ; opcode, n_int_in, n_int_out, n_addr_in, n_addr_out
        mov     word [control+0], %1
        mov     word [control+2], %2
        mov     word [control+4], %3
        mov     word [control+6], %4
        mov     word [control+8], %5
        call    crida_aes
%endmacro

%macro VDI 4                    ; opcode, n_ptsin, n_intin, subfuncio
        mov     word [contrl+0], %1
        mov     word [contrl+2], %2
        mov     word [contrl+6], %3
        mov     word [contrl+10], %4
        mov     ax, [vhandle]
        mov     [contrl+12], ax
        call    crida_vdi
%endmacro

AC_OPEN      equ 40
WF_WORKXYWH  equ 4
MINPARAS     equ 1800           ; ~28 KB: COMMAND.COM 3.x + entorn + marge
MBMAX        equ 9000           ; maxim de bytes per a la barra de menus

; =====================================================================
inici:
        cli
        mov     ax, cs
        mov     ds, ax
        mov     es, ax
        mov     ss, ax
        mov     sp, pila_fi
        sti
        cld
        call    init_punters

        AES     10,0,1,0,0              ; appl_init
        cmp     ax, -1
        jne     .gem_ok
        mov     ax, 4C00h
        int     21h
.gem_ok:
        mov     [ap_id], ax

        AES     77,0,5,0,0              ; graf_handle
        mov     [vhandle], ax

        mov     di, intin               ; v_opnvwk
        mov     cx, 10
        mov     ax, 1
        rep     stosw
        mov     word [intin+20], 2
        VDI     100,0,11,0
        mov     ax, [contrl+12]
        mov     [vhandle], ax

        mov     word [intin], 1         ; vq_extnd: plans de color
        VDI     102,0,1,0
        mov     ax, [intout+8]
        or      ax, ax
        jnz     .pl
        inc     ax
.pl:    mov     [plans], ax

        mov     ax, [ap_id]             ; menu_register(ap_id, nom)
        mov     [int_in], ax
        mov     word [addr_in], nom_menu
        mov     [addr_in+2], ds
        AES     35,1,1,1,0

bucle:  mov     word [addr_in], msgbuf  ; evnt_mesag
        mov     [addr_in+2], ds
        AES     23,0,1,1,0
        cmp     word [msgbuf], AC_OPEN
        jne     bucle
        call    shell
        jmp     bucle

; ---------------------------------------------------------------------
;  AC_OPEN: la shell
; ---------------------------------------------------------------------
shell:
        mov     word [int_in], 1        ; wind_update(BEG_UPDATE)
        AES     107,1,1,0,0
        mov     word [int_in], 256      ; graf_mouse(M_OFF)
        call    ratoli

        mov     bx, 0FFFFh              ; hi ha memoria de DOS lliure?
        mov     ah, 48h
        int     21h
        cmp     bx, MINPARAS
        jae     .mem
        mov     ax, bx                  ; no: alerta amb els KB lliures
        mov     cl, 6
        shr     ax, cl
        mov     di, al_kb
        call    dec3
        mov     word [int_in], 1        ; boto per defecte
        mov     word [addr_in], alerta
        mov     [addr_in+2], ds
        AES     52,1,1,1,0              ; form_alert
        jmp     .surt

.mem:   call    comspec
        call    desa_menu               ; la barra de menus, a la memoria
        VDI     5,0,0,3                 ; v_enter_cur: mode text
        mov     dx, t_ini
        mov     ah, 9
        int     21h

        mov     [sv_sp], sp             ; EXEC de COMMAND.COM
        mov     [sv_ss], ss
        mov     [pb_tail+2], ds
        mov     [pb_f1+2], ds
        mov     [pb_f2+2], ds
        mov     dx, cami
        mov     bx, pblock
        mov     ax, 4B00h
        int     21h
        cli
        mov     bx, cs
        mov     ss, bx
        mov     sp, [cs:sv_sp]
        mov     ds, bx
        mov     es, bx
        sti
        cld
        jnc     .torna
        mov     dx, t_err               ; no s'ha pogut executar
        mov     ah, 9
        int     21h
        xor     ax, ax                  ; espera una tecla
        int     16h

.torna: VDI     5,0,0,2                 ; v_exit_cur: mode grafic
        call    posa_menu
        mov     word [int_in], 0        ; area de l'escriptori
        mov     word [int_in+2], WF_WORKXYWH
        AES     104,2,5,0,0
        mov     word [int_in], 3        ; form_dial(FMD_FINISH): redibuixa
        mov     si, int_out+2
        mov     di, int_in+2
        mov     cx, 4
        rep     movsw
        mov     si, int_out+2
        mov     cx, 4
        rep     movsw
        AES     51,9,1,0,0

.surt:  mov     word [int_in], 257      ; graf_mouse(M_ON)
        call    ratoli
        mov     word [int_in], 0        ; wind_update(END_UPDATE)
        AES     107,1,1,0,0
        ret

ratoli: mov     word [addr_in], 0
        mov     word [addr_in+2], 0
        AES     78,1,1,1,0
        ret

; ---------------------------------------------------------------------
;  COMSPEC de l'entorn del proces actual -> cami (si no, C:\COMMAND.COM)
; ---------------------------------------------------------------------
comspec:
        push    ds
        push    es
        mov     ah, 51h                 ; PSP actual (DOS 2.0 o posterior)
        int     21h
        mov     es, bx
        mov     ax, [es:2Ch]
        or      ax, ax
        jz      .no
        mov     es, ax
        xor     di, di
.var:   cmp     byte [es:di], 0         ; final de l'entorn
        je      .no
        mov     si, k_comspec
        mov     bx, di
        mov     cx, 8
.cmp:   mov     al, [es:bx]
        cmp     al, [si]
        jne     .seg
        inc     bx
        inc     si
        loop    .cmp
        mov     si, bx                  ; trobat: copia el valor
        mov     di, cami
        mov     cx, 79
.cp:    mov     al, [es:si]
        mov     [di], al
        or      al, al
        jz      .ok
        inc     si
        inc     di
        loop    .cp
        mov     byte [di], 0
        jmp     short .ok
.seg:   mov     al, [es:di]             ; la variable seguent
        inc     di
        or      al, al
        jnz     .seg
        jmp     .var
.no:    mov     si, k_defecte
        mov     di, cami
.cd:    lodsb
        mov     [di], al
        inc     di
        or      al, al
        jnz     .cd
.ok:    pop     es
        pop     ds
        ret

; ---------------------------------------------------------------------
;  Barra de menus: es guarda abans del mode text i es torna a posar
;  despres (el GEM no la redibuixa amb form_dial). vro_cpyfm del VDI.
; ---------------------------------------------------------------------
alt_menu:                               ; -> menuh (linies), 0 si no cap
        mov     word [int_in], 0
        mov     word [int_in+2], WF_WORKXYWH
        AES     104,2,5,0,0
        mov     ax, [int_out+4]         ; y de l'escriptori = alt del menu
        mov     [menuh], ax
        mov     cx, [plans]             ; 80 bytes per linia i pla (640 px)
        mul     cx
        mov     cx, 80
        mul     cx
        or      dx, dx
        jnz     .no
        cmp     ax, MBMAX
        ja      .no
        add     ax, 15                  ; bloc de DOS per guardar-la
        mov     cl, 4
        shr     ax, cl
        mov     bx, ax
        mov     ah, 48h
        int     21h
        jc      .no
        mov     [mbseg], ax
        ret
.no:    mov     word [menuh], 0
        ret

mfdbs:  ; omple el MFDB de memoria i els punts (0,0)-(639,menuh-1)
        mov     word [mf_mem], 0
        mov     ax, [mbseg]
        mov     [mf_mem+2], ax
        mov     word [mf_mem+4], 640
        mov     ax, [menuh]
        mov     [mf_mem+6], ax
        mov     word [mf_mem+8], 40
        mov     word [mf_mem+10], 0
        mov     ax, [plans]
        mov     [mf_mem+12], ax
        mov     word [mf_scr], 0        ; pantalla: adreca 0
        mov     word [mf_scr+2], 0
        mov     di, ptsin
        mov     cx, 2
.p:     xor     ax, ax
        stosw
        stosw
        mov     ax, 639
        stosw
        mov     ax, [menuh]
        dec     ax
        stosw
        loop    .p
        mov     word [intin], 3         ; S_ONLY
        ret

desa_menu:
        call    alt_menu
        cmp     word [menuh], 0
        je      .x
        call    mfdbs
        mov     word [contrl+14], mf_scr
        mov     [contrl+16], ds
        mov     word [contrl+18], mf_mem
        mov     [contrl+20], ds
        VDI     109,4,1,0               ; vro_cpyfm pantalla -> memoria
.x:     ret

posa_menu:
        cmp     word [menuh], 0
        je      .x
        call    mfdbs
        mov     word [contrl+14], mf_mem
        mov     [contrl+16], ds
        mov     word [contrl+18], mf_scr
        mov     [contrl+20], ds
        VDI     109,4,1,0               ; vro_cpyfm memoria -> pantalla
        push    es
        mov     es, [mbseg]             ; allibera el bloc
        mov     ah, 49h
        int     21h
        pop     es
        mov     word [menuh], 0
.x:     ret

; AX (0-999) -> 3 caracters a [di], alineat a la dreta
dec3:   mov     word [di], '  '
        mov     byte [di+2], ' '
        add     di, 2
        mov     bx, 10
        mov     cx, 3
.d:     xor     dx, dx
        div     bx
        add     dl, '0'
        mov     [di], dl
        dec     di
        or      ax, ax
        loopnz  .d
        ret

; ---------------------------------------------------------------------
crida_aes:
        push    bx
        push    si
        push    di
        push    bp
        push    ds
        push    es
        mov     cx, 200
        push    ds
        pop     es
        mov     bx, aespb
        int     0EFh
        pop     es
        pop     ds
        pop     bp
        pop     di
        pop     si
        pop     bx
        cld
        mov     ax, [int_out]
        ret

crida_vdi:
        push    bx
        push    si
        push    di
        push    bp
        push    ds
        push    es
        mov     cx, 473h
        mov     dx, vdipb
        int     0EFh
        pop     es
        pop     ds
        pop     bp
        pop     di
        pop     si
        pop     bx
        cld
        ret

init_punters:
        mov     ax, ds
        mov     bx, aespb+2
        mov     cx, 11
.l:     mov     [bx], ax
        add     bx, 4
        loop    .l
        ret

; =====================================================================
;  Dades (tot dins el fitxer: el GEM no dona memoria extra)
; =====================================================================
nom_menu:  db '  Shell de DOS', 0
k_comspec: db 'COMSPEC='
k_defecte: db 'C:\COMMAND.COM', 0
t_ini:     db 'GEM - Shell de DOS.  Escriu EXIT per tornar al GEM.', 13, 10, '$'
t_err:     db 13, 10, 'No s', 27h, 'ha pogut executar COMMAND.COM (COMSPEC).', 13, 10
           db 'Prem una tecla per tornar al GEM.', 13, 10, '$'
alerta:    db '[3][Shell de DOS: no hi ha|prou mem', 95h, 'ria de DOS lliure.|'
           db 'Cal 28 KB; n', 27h, 'hi ha '
al_kb:     db '    KB.][ D', 27h, 'acord ]', 0

        align 2
pblock:    dw 0                         ; entorn: el del proces actual
pb_tail:   dw tail, 0
pb_f1:     dw fcb, 0
pb_f2:     dw fcb, 0
tail:      db 0, 13
fcb:       db 0, '           ', 0, 0, 0, 0

aespb:  dw control,0, aesglob,0, int_in,0, int_out,0, addr_in,0, addr_out,0
vdipb:  dw contrl,0, intin,0, ptsin,0, intout,0, ptsout,0

control:  times 5   dw 0
aesglob:  times 15  dw 0
int_in:   times 16  dw 0
int_out:  times 8   dw 0
addr_in:  times 4   dw 0
addr_out: times 2   dw 0
contrl:   times 12  dw 0
intin:    times 16  dw 0
ptsin:    times 16  dw 0
intout:   times 48  dw 0
ptsout:   times 16  dw 0
msgbuf:   times 8   dw 0

ap_id:    dw 0
vhandle:  dw 0
plans:    dw 1
menuh:    dw 0
sv_sp:    dw 0
sv_ss:    dw 0
mf_scr:   times 10 dw 0
mf_mem:   times 10 dw 0
cami:     times 80 db 0
mbseg:    dw 0

        times 512 db 0                  ; pila
pila_fi:
        align 16, db 0
MIDA    equ $-$$
