; =====================================================================
;  NOTE.INC  -  Estructura de la part resident de NOTE (compartida amb
;  FREENOTE). Despla‡aments dins del segment del PSP de NOTE.
; =====================================================================

N_SIG       equ 0103h           ; "NOTE01" (6 bytes)
N_HO21      equ 0109h           ; word: despla‡ament del gestor INT 21h
N_HO27      equ 010Bh           ; word: despla‡ament del gestor INT 27h
N_OLD21     equ 010Dh           ; dword: INT 21h anterior
N_OLD27     equ 0111h           ; dword: INT 27h anterior
N_NREC      equ 0115h           ; byte: registres usats
N_NDIFF     equ 0116h           ; byte: canvis de vector usats
N_FLAGS     equ 0117h           ; byte: bit 0 = taula de registres plena
N_TMP       equ 0118h           ; 6 bytes de treball del gestor
N_EXP       equ 0120h           ; 1024 bytes: vectors coneguts (estat esperat)

MAXREC      equ 24              ; marques + residents
RECSZ       equ 16
N_RECS      equ N_EXP+1024

MAXDIFF     equ 48              ; vectors canviats (en total)
DIFFSZ      equ 10
N_DIFFS     equ N_RECS+MAXREC*RECSZ
N_CODE      equ N_DIFFS+MAXDIFF*DIFFSZ

; Registre (RECSZ bytes)
R_TYPE      equ 0               ; 'M' = marca, 'T' = resident
R_NDIFF     equ 1               ; vectors canviats per aquest resident
R_PSP       equ 2               ; PSP del resident
R_DIDX      equ 4               ; primer canvi a la taula de canvis
R_SIZE      equ 5               ; par…grafs demanats en quedar-se resident
R_NAME      equ 7               ; nom (8 bytes, amb espais)
R_FLAGS     equ 15              ; bit 0 = canvis incomplets (taula plena)

; Canvi de vector (DIFFSZ bytes)
D_VEC       equ 0               ; n£mero d'interrupci¢
D_FLAGS     equ 1               ; bit 0 = el vector nou apunta al resident
D_OLD       equ 2               ; dword: valor anterior
D_NEW       equ 6               ; dword: valor que hi va posar
