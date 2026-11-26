; ===========================================================================
;  AMSMOUSE.ASM  -  Driver de ratol¡ m¡nim (INT 33h) per a l'Amstrad PC1512
;  Versi¢ 0.3  -  MS-DOS 2.x-6.x, CPU 8086
;
;  Maquinari del PC1512:
;    - Comptadors de moviment: port 78h (X) i 7Ah (Y), 8 bits amb signe.
;      S'esborren escrivint-hi qualsevol valor. Y positiu = cap amunt.
;    - Botons: arriben pel teclat com a codis 7Eh (esquerre) i 7Dh (dret),
;      i 0FEh / 0FDh en deixar-los anar.
;
;  El resident ‚s un m•dul amb segment propi (el mateix que el ratol¡ de
;  KEYBX 2.2) que es copia a un bloc de mem•ria a part, sense PSP:
;    - mem•ria convencional: al capdamunt (no deixa forats);
;    - mem•ria alta (/H, o si s'executa amb LOADHI): bloc lliure de la
;      cadena del DOS;
;    - /H:ssss: al segment ssss, sense bloc.
;  Captura INT 08h (moviment, amb corba d'acceleraci¢ /A:0-3), INT 09h
;  (botons) i INT 33h (API Microsoft).
;
;  Assemblar:  NASM -f bin AMSMOUSE.ASM -o AMSMOUSE.COM
; ===========================================================================

        cpu     8086
        org     100h

start:  jmp     init

; ===========================================================================
;  MODUL RESIDENT.  Tot el m•dul fa servir el seu propi segment
;  (CS = DS = inici del m•dul): M(etiqueta) = despla‡ament dins el m•dul.
; ===========================================================================
mstart:
%define M(x) ((x)-mstart)
msig            db 'AMSMOUSE'           ; signatura (offset 0 del m•dul)
mtype           db 0                    ; 0 bloc del DOS, 1 sense bloc (/H:ssss)
old09           dd 0
old08           dd 0
old33           dd 0
jmpaddr         dw 0

; --- estat desable amb les funcions 15h-17h -------------------------------
st_begin:
hidecnt         dw -1                   ; 0 = cursor visible
posx            dw 320
posy            dw 100
minx            dw 0
maxx            dw 639
miny            dw 0
maxy            dw 199
buttons         dw 0
presscnt        dw 0,0                  ; bot¢ 0 = esquerre, 1 = dret
pressx          dw 0,0
pressy          dw 0,0
relcnt          dw 0,0
relx            dw 0,0
rely            dw 0,0
mickx           dw 8                    ; mickeys per 8 p¡xels
micky           dw 16
accx            dw 0
accy            dw 0
motx            dw 0
moty            dw 0
evmask          dw 0
evhand          dd 0
txtscr          dw 77FFh
txtcur          dw 7700h
hotx            dw 1
hoty            dw 1
gmask:
%macro ARROW 0
        dw 3FFFh,1FFFh,0FFFh,07FFh,03FFh,01FFh,00FFh,007Fh  ; m…scara pantalla
        dw 01FFh,01FFh,0F0FFh,0F0FFh,0F9FFh,0FFFFh,0FFFFh,0FFFFh
        dw 0000h,4000h,6000h,7000h,7800h,7C00h,7E00h,7F00h  ; m…scara cursor
        dw 7C00h,4C00h,0600h,0600h,0000h,0000h,0000h,0000h
%endmacro
        ARROW
sens            dw 50,50,50
vpage           dw 0
disabled        db 0
st_end:
ST_LEN          equ st_end - st_begin

; --- estat intern ----------------------------------------------------------
drawn           db 0                    ; 0 res, 1 text, 2 gr…fic
d_addr          dw 0                    ; text: offset; gr…fic: posici¢ en bits
d_seg           dw 0
d_row           dw 0
d_val           dw 0
d_saved         dw 0
n_kind          db 0
n_addr          dw 0
n_seg           dw 0
n_row           dw 0
g_mode          db 0
g_rsh           db 0
g_lsh           db 0
g_bcol          dw 0
m_andb            db 0,0,0
m_xorb            db 0,0,0
gsave           times 48 db 0
tbusy           db 0
hbusy           db 0
alevel          db 2                    ; corba d'acceleracio 0-3
acctab          db 4,4,4,4              ; 0: sense acceleracio
                db 4,5,6,8              ; 1: x1 x1,25 x1,5 x2
                db 4,6,8,12             ; 2: x1 x1,5  x2   x3
                db 4,8,12,16            ; 3: x1 x2    x3   x4
                                        ; (0-3, 4-7, 8-15, 16+ mickeys/tic)

defarrow:
        ARROW

; ---------------------------------------------------------------------------
;  INT 08h - tic del rellotge: llegeix els comptadors de moviment
; ---------------------------------------------------------------------------
int08:
        pushf
        call    far [cs:M(old08)]
        push    ax
        push    bx
        push    cx
        push    dx
        push    si
        push    di
        push    bp
        push    ds
        push    es
        push    cs
        pop     ds
        cmp     byte [M(tbusy)],0
        jne     .out
        cmp     byte [M(disabled)],0    ; desactivat: no toca els ports
        jne     .out
        mov     byte [M(tbusy)],1
        in      al,78h
        mov     bl,al
        in      al,7Ah
        mov     bh,al
        xor     al,al
        out     78h,al
        out     7Ah,al
        or      bx,bx
        jz      .done
        cli
        mov     cl,3
        mov     al,bl                   ; --- X
        cbw
        add     [M(motx)],ax
        call    accel
        add     ax,[M(accx)]
        cwd
        idiv    word [M(mickx)]
        mov     [M(accx)],dx
        add     ax,[M(posx)]
        call    clampx
        mov     al,bh                   ; --- Y (invertit)
        cbw
        neg     ax
        add     [M(moty)],ax
        call    accel
        add     ax,[M(accy)]
        cwd
        idiv    word [M(micky)]
        mov     [M(accy)],dx
        add     ax,[M(posy)]
        call    clampy
        call    cur_update
        sti
        mov     ax,1                    ; esdeveniment: moviment
        call    fire_event
.done:
        mov     byte [M(tbusy)],0
.out:
        pop     es
        pop     ds
        pop     bp
        pop     di
        pop     si
        pop     dx
        pop     cx
        pop     bx
        pop     ax
        iret

; ---------------------------------------------------------------------------
;  Acceleracio: AX = mickeys d'un tic -> AX = mickeys * multiplicador * 8
;  (el multiplicador es en quarts, segons la velocitat i el nivell 0-3)
; ---------------------------------------------------------------------------
accel:
        push    bx
        push    dx
        mov     dx,ax
        or      dx,dx
        jns     .p
        neg     dx
.p:     xor     bx,bx
        cmp     dx,4
        jb      .i
        inc     bx
        cmp     dx,8
        jb      .i
        inc     bx
        cmp     dx,16
        jb      .i
        inc     bx
.i:     mov     dl,[M(alevel)]
        and     dl,3
        shl     dl,1
        shl     dl,1
        add     bl,dl
        mov     dl,[M(acctab)+bx]
        xor     dh,dh
        imul    dx
        shl     ax,1
        pop     dx
        pop     bx
        ret

; ---------------------------------------------------------------------------
;  INT 09h - teclat: els botons del ratol¡ no passen mai al programa
; ---------------------------------------------------------------------------
int09:
        push    ax
        in      al,60h
        cmp     al,7Dh
        je      .m
        cmp     al,7Eh
        je      .m
        cmp     al,0FDh
        je      .m
        cmp     al,0FEh
        je      .m
        pop     ax
        jmp     far [cs:M(old09)]
.m:     push    cs                      ; mbtn acaba amb RETF
        call    mbtn
        pop     ax
        iret

; ---------------------------------------------------------------------------
;  MBTN - el crida la INT 09h de KEYBX (call far) amb AL = codi de bot¢
;  (7Eh/7Dh pr‚mer, 0FEh/0FDh deixar anar). Reconeix el codi i fa l'EOI.
; ---------------------------------------------------------------------------
mbtn:
        push    bx
        push    cx
        push    dx
        push    si
        push    di
        push    bp
        push    ds
        push    es
        push    cs
        pop     ds
        mov     ah,al
        in      al,61h                  ; reconeix el codi al teclat
        mov     bl,al
        or      al,80h
        out     61h,al
        mov     al,bl
        out     61h,al
        mov     al,20h                  ; EOI
        out     20h,al
        cmp     byte [M(disabled)],0
        jne     .x
        mov     al,ah
        mov     bx,1                    ; esquerre: bit 0, ¡ndex 0, esd. 2
        xor     si,si
        mov     dx,2
        mov     cl,al
        and     cl,7Fh
        cmp     cl,7Eh
        je      .btn
        mov     bx,2                    ; dret: bit 1, ¡ndex 1, esd. 8
        mov     si,2
        mov     dx,8
.btn:
        cli
        test    al,80h
        jnz     .rel
        or      [M(buttons)],bx
        inc     word [M(presscnt)+si]
        mov     ax,[M(posx)]
        mov     [M(pressx)+si],ax
        mov     ax,[M(posy)]
        mov     [M(pressy)+si],ax
        jmp     short .ev
.rel:
        not     bx
        and     [M(buttons)],bx
        inc     word [M(relcnt)+si]
        mov     ax,[M(posx)]
        mov     [M(relx)+si],ax
        mov     ax,[M(posy)]
        mov     [M(rely)+si],ax
        shl     dx,1                    ; esd. deixar anar = pr‚mer * 2
.ev:
        sti
        mov     ax,dx
        call    fire_event
.x:
        pop     es
        pop     ds
        pop     bp
        pop     di
        pop     si
        pop     dx
        pop     cx
        pop     bx
        retf

; ---------------------------------------------------------------------------
;  Crida la rutina d'usuari (funci¢ 0Ch) si toca.  AX = condicions
; ---------------------------------------------------------------------------
fire_event:
        and     ax,[M(evmask)]
        jz      .r
        cmp     byte [M(hbusy)],0
        jne     .r
        mov     byte [M(hbusy)],1
        push    ax
        push    bx
        push    cx
        push    dx
        push    si
        push    di
        push    bp
        push    ds
        push    es
        mov     bx,[M(buttons)]
        mov     cx,[M(posx)]
        mov     dx,[M(posy)]
        mov     si,[M(motx)]
        mov     di,[M(moty)]
        call    far [cs:M(evhand)]
        pop     es
        pop     ds
        pop     bp
        pop     di
        pop     si
        pop     dx
        pop     cx
        pop     bx
        pop     ax
        mov     byte [cs:M(hbusy)],0
.r:     ret

; --- limita AX a [minx,maxx] i el desa a posx ------------------------------
clampx:
        cmp     ax,[M(minx)]
        jge     .a
        mov     ax,[M(minx)]
.a:     cmp     ax,[M(maxx)]
        jle     .b
        mov     ax,[M(maxx)]
.b:     mov     [M(posx)],ax
        ret

clampy:
        cmp     ax,[M(miny)]
        jge     .a
        mov     ax,[M(miny)]
.a:     cmp     ax,[M(maxy)]
        jle     .b
        mov     ax,[M(maxy)]
.b:     mov     [M(posy)],ax
        ret

; ---------------------------------------------------------------------------
;  Cursor.  Totes les rutines cur_* conserven els registres.  DS = CS.
; ---------------------------------------------------------------------------

; Calcula on aniria el cursor: n_kind, n_addr, n_seg, n_row
; (fa servir AX BX CX DX SI ES)
cur_calc:
        mov     byte [M(n_kind)],0
        mov     ax,40h
        mov     es,ax
        mov     al,[es:49h]             ; mode de v¡deo actual
        cmp     al,7
        je      .mono
        cmp     al,3
        jbe     .text
        cmp     al,6
        ja      .r
        mov     bx,[M(posx)]               ; modes gr…fics 4, 5, 6
        sub     bx,[M(hotx)]
        cmp     al,6
        je      .g6
        and     bx,0FFFEh               ; 320x200: 2 bits per p¡xel
.g6:    mov     [M(n_addr)],bx
        mov     bx,[M(posy)]
        sub     bx,[M(hoty)]
        mov     [M(n_row)],bx
        mov     word [M(n_seg)],0B800h
        mov     byte [M(n_kind)],2
.r:     ret
.mono:  mov     word [M(n_seg)],0B000h
        jmp     short .t2
.text:  mov     word [M(n_seg)],0B800h
.t2:    mov     bx,[es:4Ah]             ; columnes
        mov     ax,[M(posx)]
        mov     cl,3
        cmp     bx,40
        ja      .c80
        mov     cl,4
.c80:   shr     ax,cl
        cmp     ax,bx
        jb      .colok
        mov     ax,bx
        dec     ax
.colok: mov     si,ax
        mov     ax,[M(posy)]
        mov     cl,3
        shr     ax,cl
        mul     bx
        add     ax,si
        shl     ax,1
        add     ax,[es:4Eh]             ; inici de la p…gina
        mov     [M(n_addr)],ax
        mov     byte [M(n_kind)],1
        ret

cur_draw:
        cmp     word [M(hidecnt)],0
        jne     .r
        cmp     byte [M(drawn)],0
        jne     .r
        push    ax
        push    bx
        push    cx
        push    dx
        push    si
        push    di
        push    bp
        push    es
        call    cur_calc
        mov     al,[M(n_kind)]
        cmp     al,1
        je      .text
        cmp     al,2
        jne     .done
        mov     ax,[M(n_addr)]
        mov     [M(d_addr)],ax
        mov     ax,[M(n_row)]
        mov     [M(d_row)],ax
        mov     byte [M(drawn)],2
        mov     al,1
        call    gfx_apply
        jmp     short .done
.text:
        mov     es,[M(n_seg)]
        mov     di,[M(n_addr)]
        mov     ax,[es:di]
        mov     [M(d_saved)],ax
        and     ax,[M(txtscr)]
        xor     ax,[M(txtcur)]
        mov     [es:di],ax
        mov     [M(d_val)],ax
        mov     [M(d_addr)],di
        mov     [M(d_seg)],es
        mov     byte [M(drawn)],1
.done:
        pop     es
        pop     bp
        pop     di
        pop     si
        pop     dx
        pop     cx
        pop     bx
        pop     ax
.r:     ret

cur_remove:
        cmp     byte [M(drawn)],0
        je      .r
        push    ax
        push    bx
        push    cx
        push    dx
        push    si
        push    di
        push    bp
        push    es
        cmp     byte [M(drawn)],1
        jne     .g
        mov     es,[M(d_seg)]
        mov     di,[M(d_addr)]
        mov     ax,[es:di]
        cmp     ax,[M(d_val)]              ; nom‚s si ning£ no l'ha sobreescrit
        jne     .clr
        mov     ax,[M(d_saved)]
        mov     [es:di],ax
        jmp     short .clr
.g:     mov     al,0
        call    gfx_apply
.clr:   mov     byte [M(drawn)],0
        pop     es
        pop     bp
        pop     di
        pop     si
        pop     dx
        pop     cx
        pop     bx
        pop     ax
.r:     ret

; Redibuixa nom‚s si el cursor ha canviat de celúla / p¡xel
cur_update:
        cmp     word [M(hidecnt)],0
        jne     .r
        push    ax
        push    bx
        push    cx
        push    dx
        push    si
        push    es
        call    cur_calc
        mov     al,[M(n_kind)]
        cmp     al,[M(drawn)]
        jne     .redo
        or      al,al
        jz      .done
        mov     ax,[M(n_addr)]
        cmp     ax,[M(d_addr)]
        jne     .redo
        cmp     byte [M(drawn)],2
        jne     .done
        mov     ax,[M(n_row)]
        cmp     ax,[M(d_row)]
        je      .done
.redo:  call    cur_remove
        call    cur_draw
.done:  pop     es
        pop     si
        pop     dx
        pop     cx
        pop     bx
        pop     ax
.r:     ret

; Cursor gr…fic CGA (modes 4/5/6).  AL = 1 dibuixa, 0 restaura.
; Fa servir d_addr (posici¢ en bits) i d_row.  No conserva registres.
gfx_apply:
        mov     [M(g_mode)],al
        mov     ax,0B800h
        mov     es,ax
        mov     ax,[M(d_addr)]
        or      ax,ax
        jns     .pos
        neg     ax
        cmp     ax,16
        jbe     .l1
        mov     ax,16
.l1:    mov     [M(g_lsh)],al
        mov     byte [M(g_rsh)],0
        mov     word [M(g_bcol)],0
        jmp     short .go
.pos:   mov     bl,al
        and     bl,7
        mov     [M(g_rsh)],bl
        mov     byte [M(g_lsh)],0
        mov     cl,3
        shr     ax,cl
        mov     [M(g_bcol)],ax
.go:    xor     bp,bp                   ; fila 0..15
.row:
        mov     ax,[M(d_row)]
        add     ax,bp
        cmp     ax,0
        jl      .next
        cmp     ax,200
        jge     .next
        mov     di,ax
        shr     ax,1
        mov     dx,80
        mul     dx
        test    di,1
        mov     di,ax
        jz      .even
        add     di,2000h
.even:  add     di,[M(g_bcol)]
        mov     bx,bp                   ; bx -> gsave[fila*3]
        shl     bx,1
        add     bx,bp
        add     bx,M(gsave)
        cmp     byte [M(g_mode)],0
        jne     .draw
        mov     dx,[M(g_bcol)]             ; --- restaura
        mov     cx,3
.rk:    cmp     dx,80
        jae     .rs
        mov     al,[bx]
        mov     [es:di],al
.rs:    inc     bx
        inc     di
        inc     dx
        loop    .rk
        jmp     short .next
.draw:
        push    bx
        mov     si,bp
        shl     si,1
        mov     ax,[M(gmask)+si]           ; AND
        mov     dx,[M(gmask)+32+si]        ; XOR
        mov     bx,00FFh                ; BL = AND baix, BH = XOR baix
        mov     cl,[M(g_lsh)]
        or      cl,cl
        jz      .nol
.lsh:   stc
        rcl     ax,1
        shl     dx,1
        dec     cl
        jnz     .lsh
.nol:   mov     cl,[M(g_rsh)]
        or      cl,cl
        jz      .nor
.rsh:   stc
        rcr     ax,1
        rcr     bl,1
        clc
        rcr     dx,1
        rcr     bh,1
        dec     cl
        jnz     .rsh
.nor:   mov     [M(m_andb)],ah
        mov     [M(m_andb)+1],al
        mov     [M(m_andb)+2],bl
        mov     [M(m_xorb)],dh
        mov     [M(m_xorb)+1],dl
        mov     [M(m_xorb)+2],bh
        pop     bx
        mov     dx,[M(g_bcol)]
        xor     si,si
        mov     cx,3
.dk:    cmp     dx,80
        jae     .ds
        mov     al,[es:di]
        mov     [bx],al
        and     al,[M(m_andb)+si]
        xor     al,[M(m_xorb)+si]
        mov     [es:di],al
.ds:    inc     bx
        inc     di
        inc     si
        inc     dx
        loop    .dk
.next:  inc     bp
        cmp     bp,16
        jb      .row
        ret

; ---------------------------------------------------------------------------
;  INT 33h
; ---------------------------------------------------------------------------
int33:
        cli
        push    ds
        push    cs
        pop     ds
        cmp     ax,25h
        jae     .none
        push    bx
        mov     bx,ax
        shl     bx,1
        mov     bx,[M(fntab)+bx]
        mov     [M(jmpaddr)],bx
        pop     bx
        cld
        call    [M(jmpaddr)]
.none:  pop     ds
        iret

fntab:  dw M(f00),M(f01),M(f02),M(f03),M(f04),M(f05),M(f06),M(f07),M(f08),M(f09),M(f0A),M(f0B),M(f0C),M(fnul),M(fnul),M(f0F)
        dw M(f02),M(fnul),M(fnul),M(fnul),M(f14),M(f15),M(f16),M(f17),M(fnul),M(fnul),M(f1A),M(f1B),M(fnul),M(f1D),M(f1E),M(f1F)
        dw M(f20),M(f21),M(fnul),M(f23),M(f24)

do_reset:
        call    cur_remove
        push    cx
        push    si
        push    di
        push    es
        push    cs
        pop     es
        mov     word [M(hidecnt)],-1
        mov     word [M(posx)],320
        mov     word [M(posy)],100
        mov     word [M(minx)],0
        mov     word [M(maxx)],639
        mov     word [M(miny)],0
        mov     word [M(maxy)],199
        xor     ax,ax
        mov     di,M(buttons)
        mov     cx,13                   ; buttons + 12 comptadors
        rep     stosw
        mov     word [M(mickx)],8
        mov     word [M(micky)],16
        mov     di,M(accx)
        mov     cx,7                    ; accx..evhand
        rep     stosw
        mov     word [M(txtscr)],77FFh
        mov     word [M(txtcur)],7700h
        mov     word [M(hotx)],1
        mov     word [M(hoty)],1
        mov     si,M(defarrow)
        mov     di,M(gmask)
        mov     cx,32
        rep     movsw
        mov     byte [M(disabled)],0
        pop     es
        pop     di
        pop     si
        pop     cx
        ret

f00:
f21:    call    do_reset
        mov     ax,0FFFFh
        mov     bx,2
fnul:   ret

f01:    cmp     word [M(hidecnt)],0
        jge     .r
        inc     word [M(hidecnt)]
        jnz     .r
        call    cur_draw
.r:     ret

f02:    dec     word [M(hidecnt)]
        call    cur_remove
        ret

f03:    mov     bx,[M(buttons)]
        mov     cx,[M(posx)]
        mov     dx,[M(posy)]
        ret

f04:    push    ax
        mov     ax,cx
        call    clampx
        mov     ax,dx
        call    clampy
        pop     ax
        call    cur_update
        ret

f05:    push    di
        mov     di,M(presscnt)
        jmp     short btninfo
f06:    push    di
        mov     di,M(relcnt)
btninfo:
        mov     ax,[M(buttons)]
        cmp     bx,1
        ja      .bad
        push    si
        mov     si,bx
        shl     si,1
        add     di,si
        pop     si
        mov     bx,[di]
        mov     word [di],0
        mov     cx,[di+4]
        mov     dx,[di+8]
        pop     di
        ret
.bad:   xor     bx,bx
        pop     di
        ret

f07:    push    ax
        push    cx
        push    dx
        cmp     cx,dx
        jle     .o
        xchg    cx,dx
.o:     mov     [M(minx)],cx
        mov     [M(maxx)],dx
        mov     ax,[M(posx)]
        call    clampx
        pop     dx
        pop     cx
        pop     ax
        call    cur_update
        ret

f08:    push    ax
        push    cx
        push    dx
        cmp     cx,dx
        jle     .o
        xchg    cx,dx
.o:     mov     [M(miny)],cx
        mov     [M(maxy)],dx
        mov     ax,[M(posy)]
        call    clampy
        pop     dx
        pop     cx
        pop     ax
        call    cur_update
        ret

f09:    call    cur_remove
        mov     [M(hotx)],bx
        mov     [M(hoty)],cx
        push    si
        push    di
        push    cx
        push    es
        push    ds
        mov     si,dx
        push    es
        pop     ds
        push    cs
        pop     es
        mov     di,M(gmask)
        mov     cx,32
        rep     movsw
        pop     ds
        pop     es
        pop     cx
        pop     di
        pop     si
        call    cur_draw
        ret

f0A:    or      bx,bx
        jnz     .r                      ; cursor de maquinari: no suportat
        call    cur_remove
        mov     [M(txtscr)],cx
        mov     [M(txtcur)],dx
        call    cur_draw
.r:     ret

f0B:    mov     cx,[M(motx)]
        mov     dx,[M(moty)]
        mov     word [M(motx)],0
        mov     word [M(moty)],0
        ret

f0C:    mov     [M(evmask)],cx
        mov     [M(evhand)],dx
        mov     [M(evhand)+2],es
        ret

f0F:    or      cx,cx
        jz      .y
        mov     [M(mickx)],cx
        mov     word [M(accx)],0
.y:     or      dx,dx
        jz      .r
        mov     [M(micky)],dx
        mov     word [M(accy)],0
.r:     ret

f14:    push    ax
        mov     ax,[M(evmask)]
        mov     [M(evmask)],cx
        mov     cx,ax
        mov     ax,[M(evhand)]
        mov     [M(evhand)],dx
        mov     dx,ax
        mov     ax,[M(evhand)+2]
        mov     [M(evhand)+2],es
        mov     es,ax
        pop     ax
        ret

f15:    mov     bx,ST_LEN
        ret

f16:    push    si
        push    di
        push    cx
        mov     di,dx
        mov     si,M(st_begin)
        mov     cx,ST_LEN
        rep     movsb
        pop     cx
        pop     di
        pop     si
        ret

f17:    call    cur_remove
        push    si
        push    di
        push    cx
        push    es
        push    ds
        mov     si,dx
        push    es
        pop     ds
        push    cs
        pop     es
        mov     di,M(st_begin)
        mov     cx,ST_LEN
        rep     movsb
        pop     ds
        pop     es
        pop     cx
        pop     di
        pop     si
        call    cur_draw
        ret

f1A:    mov     [M(sens)],bx
        mov     [M(sens)+2],cx
        mov     [M(sens)+4],dx
        ret

f1B:    mov     bx,[M(sens)]
        mov     cx,[M(sens)+2]
        mov     dx,[M(sens)+4]
        ret

f1D:    mov     [M(vpage)],bx
        ret

f1E:    mov     bx,[M(vpage)]
        ret

f1F:    call    cur_remove
        mov     byte [M(disabled)],1
        les     bx,[M(old33)]
        mov     ax,1Fh
        ret

f20:    mov     byte [M(disabled)],0
        ret

f23:    xor     bx,bx                   ; idioma: anglŠs
        ret

f24:    mov     bx,0626h                ; compatible amb la versi¢ 6.26
        mov     cx,0100h                ; CH = 1 (bus), CL = 0
        ret

mend:

MSIZE   equ     mend-mstart
MPARA   equ     (MSIZE+15)/16

; ===========================================================================
;  Part transit•ria
; ===========================================================================
opt_u   db      0
opt_h   db      0                       ; 0 auto, 1 /H, 2 /H:ssss
opt_f   db      0
opt_a   db      0FFh                    ; /A:n (FFh = no s'ha dit)
opt_seg dw      0
resseg  dw      0
mseg    dw      0
mtyp    db      0
convtop dw      0

init:
        cld
        mov     sp,stktop               ; pila dins la zona que es conserva
        mov     dx,msg_banner
        call    print
        mov     si,81h
.scan:  lodsb
        cmp     al,0Dh
        je      .parsed
        cmp     al,' '
        je      .scan
        cmp     al,9
        je      .scan
        cmp     al,'/'
        je      .opt
        cmp     al,'-'
        je      .opt
        jmp     bad_opt
.opt:   lodsb
        cmp     al,'?'
        je      help
        and     al,0DFh
        cmp     al,'U'
        je      .u
        cmp     al,'H'
        je      .h
        cmp     al,'F'
        je      .f
        cmp     al,'A'
        je      .a
        jmp     bad_opt
.u:     mov     byte [opt_u],1
        jmp     short .scan
.f:     mov     byte [opt_f],1
        jmp     short .scan
.a:     lodsb
        cmp     al,':'
        jne     bad_opt
        lodsb
        sub     al,'0'
        cmp     al,3
        ja      bad_opt
        mov     [opt_a],al
        jmp     short .scan
.h:     mov     byte [opt_h],1
        cmp     byte [si],':'
        jne     .scan
        inc     si
        call    parse_hex
        jc      bad_opt
        mov     [opt_seg],ax
        mov     byte [opt_h],2
        jmp     short .scan

.parsed:
        int     12h
        mov     cl,6
        shl     ax,cl
        mov     [convtop],ax
        call    find_res                ; AL = 1 si hi ‚s, ES = segment
        cmp     byte [opt_u],0
        je      .nu
        jmp     unload
.nu:    or      al,al
        jz      install
        mov     [resseg],es
        cmp     byte [opt_a],0FFh       ; ja hi ‚s: /A:n canvia la corba
        je      .al
        mov     al,[opt_a]
        mov     [es:M(alevel)],al
        call    pstatus
        jmp     exit_ok
.al:    mov     dx,msg_already
        call    print
        call    pstatus
        jmp     exit_err

; --- desc…rrega ------------------------------------------------------------
unload:
        or      al,al
        jnz     .found
        mov     dx,msg_notinst
        call    print
        jmp     exit_err
.found: mov     [resseg],es
        mov     ax,3508h
        call    .chk
        mov     ax,3509h
        call    .chk
        mov     ax,3533h
        call    .chk
        xor     ax,ax                   ; treu el cursor de la pantalla
        int     33h
        mov     es,[resseg]
        cli
        push    ds
        lds     dx,[es:M(old08)]
        mov     ax,2508h
        int     21h
        lds     dx,[es:M(old09)]
        mov     ax,2509h
        int     21h
        lds     dx,[es:M(old33)]
        mov     ax,2533h
        int     21h
        pop     ds
        sti
        cmp     byte [es:M(mtype)],0
        jne     .z
        mov     ah,49h                  ; allibera el bloc
        int     21h
        jmp     short .ok
.z:     xor     di,di                   ; sense bloc: deixa la zona buida
        mov     cx,MSIZE
        xor     al,al
        rep     stosb
.ok:    mov     dx,msg_unloaded
        call    print
        jmp     exit_ok
.chk:   int     21h
        mov     ax,es
        cmp     ax,[resseg]
        jne     .cant
        ret
.cant:  mov     dx,msg_cant
        call    print
        jmp     exit_err

; --- instalúlaci¢ ----------------------------------------------------------
install:
        mov     ax,3533h                ; hi ha un altre driver?
        int     21h
        mov     ax,es
        or      ax,bx
        jz      .none
        cmp     byte [es:bx],0CFh       ; IRET
        je      .none
        xor     ax,ax
        int     33h
        cmp     ax,0FFFFh
        jne     .none
        mov     dx,msg_other
        call    print
        jmp     exit_err
.none:  cmp     byte [opt_h],2
        jne     .n1
        jmp     inst_raw
.n1:    cmp     byte [opt_h],1          ; /H des de baix: bloc lliure a dalt
        jne     .carve
        mov     ax,cs
        cmp     ax,[convtop]
        jb      .umb

        ; --- on som (baix, o a dalt amb LOADHI): el programa t‚ tot el bloc
        ; lliure m‚s gran; s'encongeix i el driver va al capdamunt del que
        ; queda lliure just a continuaci¢ (no deixa forats)
.carve:
        push    cs
        pop     es
        mov     bx,TRANSPARA
        mov     ah,4Ah
        int     21h
        mov     ax,cs
        dec     ax
        mov     es,ax
        add     ax,[es:3]
        inc     ax
        mov     es,ax
        mov     cl,[es:0]
        cmp     cl,'M'
        je      .c1
        cmp     cl,'Z'
        jne     .nomem
.c1:    cmp     word [es:1],0
        jne     .nomem
        mov     dx,[es:3]
        cmp     dx,MPARA+1
        jb      .nomem
        sub     dx,MPARA+1
        mov     byte [es:0],'M'
        mov     [es:3],dx
        mov     ax,es
        add     ax,dx
        inc     ax
        mov     es,ax                   ; MCB nou, al capdamunt
        mov     [es:0],cl
        mov     word [es:1],0
        mov     word [es:3],MPARA
        inc     ax
        jmp     short .mcb
.umb:   call    find_umb
        jnc     .mcb
        mov     dx,msg_noumb
        call    print
        jmp     exit_err
.nomem: mov     dx,msg_nomem
        call    print
        jmp     exit_err
.mcb:   mov     [mseg],ax
        dec     ax
        mov     es,ax
        mov     ax,[mseg]               ; propietari: el mateix bloc
        mov     [es:1],ax
        mov     si,mstart               ; nom (camp de DOS 4+)
        mov     di,8
        mov     cx,8
        rep     movsb
        mov     byte [mtyp],0
        jmp     connect

inst_raw:
        mov     ax,[opt_seg]
        cmp     ax,[convtop]
        jb      .bad
        mov     bx,ax
        add     bx,MPARA
        jc      .bad
        mov     [mseg],ax
        call    in_chain
        jnc     .c1
        mov     dx,msg_chain
        call    print
        jmp     exit_err
.c1:    mov     es,[mseg]
        cmp     byte [opt_f],0
        jne     .rt
        xor     di,di                   ; ha d'estar buida (tot 00 o FF)
        mov     al,[es:0]
        cmp     al,0
        je      .e0
        cmp     al,0FFh
        jne     .used
.e0:    mov     cx,MSIZE
        repe    scasb
        jne     .used
.rt:    xor     di,di
        mov     cx,MSIZE
.t:     mov     al,[es:di]
        mov     ah,al
        not     al
        mov     [es:di],al
        mov     bl,[es:di]
        mov     [es:di],ah
        cmp     bl,al
        jne     .noram
        inc     di
        loop    .t
        mov     byte [mtyp],1
        jmp     short connect
.bad:   mov     dx,msg_badseg
        call    print
        jmp     exit_err
.used:  mov     dx,msg_used
        call    print
        jmp     exit_err
.noram: mov     dx,msg_noram
        call    print
        jmp     exit_err

; --- copia el m•dul, captura les interrupcions i el reinicia -----------------
connect:
        mov     es,[mseg]
        mov     si,mstart
        xor     di,di
        mov     cx,MSIZE
        rep     movsb
        mov     al,[mtyp]
        mov     [es:M(mtype)],al
        mov     al,[opt_a]
        cmp     al,0FFh
        je      .a
        mov     [es:M(alevel)],al
.a:     mov     ax,3508h
        int     21h
        mov     dx,es
        mov     es,[mseg]
        mov     [es:M(old08)],bx
        mov     [es:M(old08)+2],dx
        mov     ax,3509h
        int     21h
        mov     dx,es
        mov     es,[mseg]
        mov     [es:M(old09)],bx
        mov     [es:M(old09)+2],dx
        mov     ax,3533h
        int     21h
        mov     dx,es
        mov     es,[mseg]
        mov     [es:M(old33)],bx
        mov     [es:M(old33)+2],dx
        push    ds
        mov     ax,[mseg]
        mov     ds,ax
        mov     dx,M(int33)
        mov     ax,2533h
        int     21h
        mov     dx,M(int09)
        mov     ax,2509h
        int     21h
        mov     dx,M(int08)
        mov     ax,2508h
        int     21h
        pop     ds
        xor     ax,ax
        int     33h
        mov     dx,msg_inst
        call    print
        mov     ax,[mseg]
        mov     [resseg],ax
        call    pstatus
        jmp     exit_ok

; --- "Mem•ria convencional/alta, segment XXXX, acceleraci¢ n." ------------
pstatus:
        mov     es,[resseg]
        mov     dx,msg_conv
        mov     ax,es
        cmp     ax,[convtop]
        jb      .p
        mov     dx,msg_high
.p:     call    print
        mov     ax,[resseg]
        call    print_hex
        mov     dx,msg_acc
        call    print
        mov     es,[resseg]
        mov     dl,[es:M(alevel)]
        add     dl,'0'
        mov     ah,2
        int     21h
        mov     dx,msg_dot
        jmp     print

; --- busca el driver resident a partir del vector INT 33h ------------------
find_res:
        mov     ax,3533h
        int     21h
        mov     ax,es
        or      ax,ax
        jz      .no
        or      bx,bx                   ; el m•dul t‚ int33 > 0
        jz      .no
        mov     si,mstart
        xor     di,di
        mov     cx,4
        repe    cmpsw
        jne     .no
        mov     al,1
        ret
.no:    xor     al,al
        ret

first_mcb:
        push    es
        push    bx
        mov     ah,52h
        int     21h
        mov     ax,[es:bx-2]
        pop     bx
        pop     es
        ret

; --- bloc lliure de la cadena per sobre de la mem•ria convencional -> AX ---
find_umb:
        call    first_mcb
.walk:  mov     es,ax
        mov     cl,[es:0]
        cmp     cl,'M'
        je      .ok
        cmp     cl,'Z'
        jne     .fail
.ok:    mov     dx,[es:3]
        cmp     word [es:1],0
        jne     .next
        mov     bx,ax
        inc     bx
        cmp     bx,[convtop]
        jb      .next
        cmp     dx,MPARA
        jb      .next
        je      .take
        push    es                      ; parteix el bloc
        mov     ax,bx
        add     ax,MPARA
        mov     es,ax
        mov     [es:0],cl
        mov     word [es:1],0
        sub     dx,MPARA+1
        mov     [es:3],dx
        pop     es
        mov     byte [es:0],'M'
        mov     word [es:3],MPARA
.take:  mov     ax,bx
        clc
        ret
.next:  cmp     cl,'Z'
        je      .fail
        add     ax,dx
        inc     ax
        jmp     short .walk
.fail:  stc
        ret

; --- CF = 1 si [mseg, mseg+MPARA) toca algun bloc de la cadena -------------
in_chain:
        call    first_mcb
.walk:  mov     es,ax
        mov     cl,[es:0]
        cmp     cl,'M'
        je      .ok
        cmp     cl,'Z'
        jne     .no
.ok:    mov     dx,ax
        add     dx,[es:3]               ; dx = darrer par…graf del bloc
        mov     bx,[mseg]
        add     bx,MPARA-1
        cmp     ax,bx
        ja      .next
        cmp     dx,[mseg]
        jb      .next
        stc
        ret
.next:  cmp     cl,'Z'
        je      .no
        mov     ax,dx
        inc     ax
        jmp     short .walk
.no:    clc
        ret

; --- llegeix hex de DS:SI -> AX, CF si error --------------------------------
parse_hex:
        xor     dx,dx
        xor     cx,cx
.l:     mov     al,[si]
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
        shl     dx,cl
        pop     cx
        or      dl,al
        inc     si
        inc     cx
        cmp     cx,4
        jbe     .l
        stc
        ret
.e:     or      cx,cx
        jz      .bad
        cmp     cx,4
        ja      .bad
        mov     ax,dx
        clc
        ret
.bad:   stc
        ret

; --- sortides ---------------------------------------------------------------
print:  mov     ah,9
        int     21h
        ret

print_hex:                              ; AX en hex
        mov     cx,4
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
        mov     ah,2
        int     21h
        pop     ax
        loop    .l
        ret

help:   mov     dx,msg_help
        call    print
exit_ok:
        mov     ax,4C00h
        int     21h

bad_opt:
        mov     dx,msg_badopt
        call    print
exit_err:
        mov     ax,4C01h
        int     21h

; --- missatges --------------------------------------------------------------
msg_banner  db 'AMSMOUSE 0.3 - Driver de ratol¡ per a l',27h,'Amstrad PC1512',13,10,'$'
msg_help    db 13,10
            db 'Sintaxi: AMSMOUSE [/A:n] [/H | /H:ssss [/F]] | /U',13,10,13,10
            db '  (res)    Instalúla el driver a mem•ria convencional',13,10
            db '           (o a mem•ria alta si s',27h,'executa amb LOADHI)',13,10
            db '  /A:n     Acceleraci¢ n = 0 (cap), 1, 2 (per defecte) o 3;',13,10
            db '           amb el driver ja carregat, la canvia en calent',13,10
            db '  /H       En un bloc lliure de mem•ria alta de la cadena del DOS',13,10
            db '  /H:ssss  Al segment ssss (hex), en RAM fora de la cadena del DOS',13,10
            db '  /F       Amb /H:ssss, no comprova que la zona sigui buida',13,10
            db '  /U       Descarrega el driver',13,10,'$'
msg_inst    db 'Driver instalúlat. $'
msg_conv    db 'Mem•ria convencional, segment $'
msg_high    db 'Mem•ria alta, segment $'
msg_acc     db ', acceleraci¢ $'
msg_dot     db '.',13,10,'$'
msg_already db 'El driver ja ‚s instalúlat. $'
msg_notinst db 'El driver no ‚s instalúlat.',13,10,'$'
msg_cant    db 'No es pot descarregar: un altre programa resident ha',13,10
            db 'capturat les interrupcions despr‚s. Descarregueu-lo primer.',13,10,'$'
msg_unloaded db 'Driver descarregat.',13,10,'$'
msg_other   db 'Ja hi ha un altre driver de ratol¡ instalúlat.',13,10,'$'
msg_noumb   db 'No hi ha cap bloc lliure prou gran a la mem•ria alta',13,10
            db 'enlla‡ada. Proveu /H:ssss o LOADHI.',13,10,'$'
msg_nomem   db 'No hi ha prou mem•ria lliure.',13,10,'$'
msg_badseg  db 'Segment no v…lid: ha de ser per sobre de la mem•ria convencional.',13,10,'$'
msg_chain   db 'Aquesta zona ‚s dins la cadena de mem•ria del DOS: useu /H.',13,10,'$'
msg_used    db 'La zona no ‚s buida (useu /F si hi ha restes d',27h,'abans).',13,10,'$'
msg_noram   db 'No hi ha RAM a l',27h,'adre‡a indicada.',13,10,'$'
msg_badopt  db 'Opci¢ desconeguda. Useu /? per veure l',27h,'ajuda.',13,10,'$'

tend:
stktop      equ tend+200h
TRANSPARA   equ (stktop-start+100h+15)/16
