; EXE.INC - el programa comenca a l'offset 0 del segment.
; La capcalera MZ la posa build.py (CS=SS=segment del programa, IP=0).
; Just despres del salt hi ha la mida de la zona BSS (dades a zero que
; no es guarden al fitxer): va de fi_imatge a fi_bss i el programa
; l'ha de posar a zero en arrencar.
        cpu 8086
        org 0
        jmp near inici
        dw fi_bss - fi_imatge
