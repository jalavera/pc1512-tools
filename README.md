# Eines per a l'Amstrad PC1512 i MS-DOS 3.20

Programes per a MS-DOS 3.x escrits des de zero per a l'Amstrad PC1512
(provats a l'emulador [86Box](https://86box.net)). Cada programa té la
seva carpeta amb el codi font (`.ASM`, NASM) i el seu manual (`.TXT`).

| Programa | Versió | Què fa |
|---|---|---|
| [LOADHI](LOADHI/) | 0.18 | Crea memòria superior (UMB) enllaçada a la cadena del DOS 3.x i hi carrega residents, BUFFERS, FILES i COMMAND.COM |
| [MEM](MEM/) | 0.26 | El MEM del MS-DOS 6.22 refet per a DOS 3.x: memòria convencional i superior, blocs, mapa de B8000 a FFFFF, BUFFERS/FILES/FCBS; dins del GEM, separa accessoris, controladors i recursos |
| [GEMHI](GEMHI/) | 0.3 | Engega el GEM 2.0 amb GEMVDI, AMSTRAD.SYS, els accessoris i els recursos a la memòria superior (uns 120 KB més de convencional) |
| [CHARMAP](CHARMAP/) | 0.7 | Accessori del GEM 2.0: mapa de caràcters que escriu una cadena a l'aplicació del davant |
| [EINES](EINES/) | 0.3 | Accessori del GEM 2.0: CHARMAP i una Shell de DOS en un sol fitxer (el GEM 2.0 només carrega 3 accessoris) |
| [IOPATCH](IOPATCH/) | 5.0 | Pedaç de l'IO.SYS del MS-DOS 3.20: menú d'arrencada (MS-DOS / DOS Plus...) amb ratolí i compte enrere, i memòria convencional fins a 736 KB, sense FIXLDR; es desfà amb /U. Amb IOCONFIG per configurar el menú |
| [IOPATCH6](IOPATCH6/) | 1.0 | Pedaç de l'IO.SYS del MS-DOS 6.22: memòria convencional fins a 736 KB; es desfà amb /U |

## Descàrrega

Els executables (`.COM`) són a les
[Releases](../../releases). També es poden assemblar:

```
nasm -f bin LOADHI/LOADHI.ASM -o LOADHI.COM
nasm -f bin -DTRACE LOADHI/LOADHI.ASM -o LOADHIT.COM   (versió de prova)
nasm -f bin MEM/MEM.ASM -o MEM.COM
nasm -f bin GEMHI/GEMHI.ASM -o GEMHI.COM
nasm -f bin CHARMAP/CHARMAP.ASM -o CHARMAP.ACC   (accessori del GEM)
nasm -f bin EINES/EINES.ASM -o EINES.ACC         (accessori del GEM)
nasm -f bin IOPATCH6/IOPATCH6.ASM -o IOPATCH6.COM
cd IOPATCH && sh BUILD.SH                (IOPATCH.COM i IOCONFIG.COM)
```

Els programes de més d'un fitxer tenen un `BUILD.SH` a la seva carpeta,
que és el que fa servir GitHub Actions.

Cada push assembla tots els programes (GitHub Actions). Per publicar
una versió: *Actions > Build > Run workflow*, amb el nom
`programa-versió` (p. ex. `loadhi-0.18`) a *release*.

## Codificació

Els `.ASM`, `.TXT` i `.CFG` són en **CP850** amb finals de línia
**CRLF**, perquè són per llegir i fer servir al DOS. A GitHub els
accents es veuen malament; per llegir-los en un ordinador d'ara cal
obrir-los com a CP850 (o DOS Latin 1).

Els textos dels programes que surten per pantalla són en castellà, com
els del MS-DOS en castellà; els manuals i els comentaris del codi, en
català.

## Requisits

- MS-DOS 3.1 a 3.3 (provat amb el 3.20 de l'Amstrad PC1512).
  IOPATCH6 és per al MS-DOS 6.22.
- Per a la memòria superior: RAM entre 640 KB i 1 MB (per exemple les
  targetes de memòria *Generic PC/XT* de 86Box).
- GEMHI, CHARMAP i EINES: el GEM 2.0 de l'Amstrad PC1512. GEMHI
  necessita la zona alta de LOADHI.

## Codi d'altres

`IOPATCH/DRLDR.BIN` són els primers 2064 bytes del carregador de disc
dur de Digital Research (el que instal·la el FIXLDR del DOS Plus), sobre
el qual es munta el menú. No hi ha cap fitxer de Microsoft: l'IOPATCH
copia l'IO.SYS que ja hi ha al disc.

## Autoria

Programes fets per jalavera amb l'ajuda de Claude (IA d'Anthropic), que
n'ha escrit el codi seguint les seves indicacions i proves.

## Llicència

Pendent de triar.
