; =====================================================================
;  CFG.INC - Format del bloc de configuraci¢ del men£ d'arrencada
;            (compartit per IOX.ASM i IOCONFIG.ASM)
; =====================================================================

XOFF     equ     0x0A00          ; on comen‡a l'extensi¢ dins l'IO.SYS
CFGOFF   equ     0x0A10          ; on comen‡a la configuraci¢ dins l'IO.SYS
XSIZE    equ     0x0A00          ; mida fixa de l'extensi¢ (A00h-13FFh)
CFGSZ    equ     160             ; mida del bloc de configuraci¢

C_MAGIC  equ     0               ; 'CF'
C_VER    equ     2               ; versi¢ del format (1)
C_ABG    equ     3               ; atribut del fons de pantalla
C_ATIT   equ     4               ; atribut de la barra del t¡tol
C_ATXT   equ     5               ; atribut de les opcions
C_ASEL   equ     6               ; atribut de l'opci¢ seleccionada
C_TIME   equ     7               ; segons d'espera (0..99, 255 = infinit)
C_DEF    equ     8               ; opci¢ per defecte: 0..4 (DOSPLUS, DOS,
                                 ;   CCPM, CPCDOS, CDOS286), 255 = primera
C_MOUSE  equ     9               ; 0 cap, 1 Amstrad, 2 Microsoft COM1,
                                 ;   3 Microsoft COM2
C_SINGLE equ     10              ; 1 = men£ encara que hi hagi un sol sistema
C_LAYOUT equ     11              ; 0 centrada, 1 cl…ssica (a dalt a l'esquerra)
CLW      equ     26              ; amplada de les barres en la cl…ssica
C_TITLE  equ     12              ; t¡tol (ASCIIZ, m…x. 39 car…cters)
TITLESZ  equ     40
C_LBL    equ     52              ; 5 noms (ASCIIZ, m…x. 19 car…cters cadascun)
LBLSZ    equ     20
C_MSPD   equ     152             ; ratol¡: velocitat 1..5 (0 = 3)
C_MCOL   equ     153             ; ratol¡: color del cursor (0 = invers,
                                 ;   1..8 = color de fons 0..7)
C_MPOS   equ     154             ; ratol¡: posici¢ inicial (0 opci¢ per
                                 ;   defecte, 1 centre, 2 a dalt a
                                 ;   l'esquerra, 3 a baix a la dreta)
C_CHK    equ     CFGSZ-1         ; suma de tots els bytes = 0 (mod 256)

T_INF    equ     255             ; temps d'espera infinit
NSYS     equ     5               ; entrades de la taula del carregador

MENUW    equ     40              ; amplada del men£ a la pantalla

; Suma dels car…cters d'una cadena (per calcular la suma de verificaci¢)
%macro STRSUM 1
  %strlen %%n %1
  %assign %%i 1
  %rep %%n
    %substr %%c %1 %%i
    %assign CSUM CSUM + %%c
    %assign %%i %%i+1
  %endrep
%endmacro

; Camp de text de mida fixa (cadena + zeros), sumant-ne els car…cters
%macro TXT 2
%%s:    db      %1
        times   %2-($-%%s) db 0
        STRSUM  %1
%endmacro

; Configuraci¢ per defecte, amb la suma de verificaci¢ calculada
%macro CFGDEFAULT 0
%assign CSUM 0
%%b:    db      'CF', 1
        db      0x07                    ; fons: gris clar sobre negre
        db      0x0F                    ; t¡tol: blanc sobre negre
        db      0x07                    ; opcions: gris clar sobre negre
        db      0x70                    ; seleccionada: negre sobre gris
        db      5                       ; 5 segons
        db      1                       ; per defecte: DOS.SYS (MS-DOS)
        db      0                       ; sense ratol¡
        db      0                       ; sense men£ si hi ha un sol sistema
        db      0                       ; disposici¢ centrada
%assign CSUM 'C'+'F'+1+0x07+0x0F+0x07+0x70+5+1
        TXT     'Escull sistema operatiu', TITLESZ
        TXT     'DOS Plus 1.2', LBLSZ
        TXT     'MS-DOS 3.20', LBLSZ
        TXT     'Concurrent CP/M', LBLSZ
        TXT     'Concurrent PC DOS', LBLSZ
        TXT     'Concurrent DOS 286', LBLSZ
        times   CFGSZ-1-($-%%b) db 0
        db      (256 - (CSUM & 0xFF)) & 0xFF
%endmacro
