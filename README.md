# Eines per a l'Amstrad PC1512 i MS-DOS 3.20

Programes per a MS-DOS 3.x escrits des de zero per a l'Amstrad PC1512
(provats a l'emulador [86Box](https://86box.net)). Cada programa té la
seva carpeta amb el codi font (`.ASM`, NASM) i el seu manual (`.TXT`).

| Programa | Versió | Què fa |
|---|---|---|
| [LOADHI](LOADHI/) | 0.22 | Crea memòria superior (UMB) enllaçada a la cadena del DOS 3.x i hi carrega residents, BUFFERS, FILES i COMMAND.COM |
| [MEM](MEM/) | 0.27 | El MEM del MS-DOS 6.22 refet per a DOS 3.x: memòria convencional i superior, blocs, mapa de B8000 a FFFFF, BUFFERS/FILES/FCBS; dins del GEM, separa accessoris, controladors i recursos |
| [GEMHI](GEMHI/) | 0.3 | Engega el GEM 2.0 amb GEMVDI, AMSTRAD.SYS, els accessoris i els recursos a la memòria superior (uns 120 KB més de convencional) |
| [CHARMAP](CHARMAP/) | 0.7 | Accessori del GEM 2.0: mapa de caràcters que escriu una cadena a l'aplicació del davant |
| [DOSSHELL](DOSSHELL/) | 0.2 | Accessori del GEM 2.0: Shell de DOS des de qualsevol aplicació GEM; per tornar, EXIT |
| [EINES](EINES/) | 0.3 | Accessori del GEM 2.0: CHARMAP i una Shell de DOS en un sol fitxer (el GEM 2.0 només carrega 3 accessoris) |
| [IOPATCH](IOPATCH/) | 5.0 | Pedaç de l'IO.SYS del MS-DOS 3.20: menú d'arrencada (MS-DOS / DOS Plus...) amb ratolí i compte enrere, i memòria convencional fins a 736 KB, sense FIXLDR; es desfà amb /U. Amb IOCONFIG per configurar el menú |
| [IOPATCH6](IOPATCH6/) | 1.0 | Pedaç de l'IO.SYS del MS-DOS 6.22: memòria convencional fins a 736 KB; es desfà amb /U |
| [HIDOS](HIDOS/) | 0.13 | Posa el nucli del MS-DOS 3.20 i les seves taules (FILES, BUFFERS, FCBS, unitats, DEVICEHIGH=) a la memòria superior; BUFFERSLOW=/FILESLOW=/FCBSLOW= i REM al CONFIG.SYS, intèrpret a baix amb /S-, només les ordres noves amb /N; es desfà amb /U |
| [XPATH](XPATH/) | 0.7 | PATH (i altres variables) a l'entorn del COMMAND.COM principal, amb %VAR%, comprovació dels camins i llistes desades |
| [KEYBX](KEYBX/) | 2.4 | Remapejador de teclat resident (MS-DOS 2.x a 6.xx): aprèn quina tecla fa cada símbol quan l'emulador envia codis que no quadren amb el teclat; amb driver de ratolí del PC1512 (/M). Porta el KEYBX.CFG configurat |
| [AMSMOUSE](AMSMOUSE/) | 0.3 | Controlador de ratolí mínim (INT 33h) per al ratolí de l'Amstrad PC1512 |
| [ATTRIB](ATTRIB/) | 1.0 | ATTRIB per al MS-DOS 3.20 amb els atributs S i H, com el del MS-DOS 5 |
| [SEARCH](SEARCH/) | 1.0 | Cerca un arxiu a totes les unitats i directoris, amb mida, data, atributs i CRC32 |
| [DIRCLEAN](DIRCLEAN/) | 1.1 | Neteja els directoris FAT12/FAT16: entrades LFN òrfenes, brossa de macOS i entrades invàlides |
| [WAIT](WAIT/) | 0.1 | Espera amb compte enrere per als .BAT, aturable amb una tecla |
| [ROWS25](ROWS25/) | 0.1 | Posa a la BIOS del PC1512 el nombre de files de la pantalla (perquè MEM /P i altres parin a cada pantalla) |
| [GEMPATCH](GEMPATCH/) | 0.1 | Canvia els temps de doble clic del GEM (GEM.EXE), per a l'avançament ràpid de 86Box |
| [SOLITARI](SOLITARI/) | 0.1 | Joc del GEM 2.0: solitari Klondike, tot amb el ratolí (`SOLITARI.APP`) |
| [VINTIU](VINTIU/) | 0.2 | Joc del GEM 2.0: el Vint-i-u Enhanced del VIC-20, amb cartes dibuixades, ratolí, so i accés als accessoris del GEM (`VINTIU.APP`) |

## Escenaris de memòria: HIDOS, LOADHI i CONFIG.SYS

Configuracions possibles del MS-DOS 3.20 (PC1512, 736 KB de
convencional i RAM superior a BE00-FBFF), de més memòria convencional
lliure a menys. Les xifres de *programa més extens* són de l'emulador
de proves, amb `FILES=5` i `BUFFERS=1`, sense residents. Amb altres
`FILES`/`BUFFERS`, controladors i residents, canvien.

Peces que es poden moure:

| Peça | Mida aproximada | Qui la mou |
|---|---|---|
| Nucli (MSDOS.SYS) i taules del DOS | ~30 KB | HIDOS |
| BIOS del DOS.SYS (CON, discs...) | 8,5 KB | HIDOS /B |
| COMMAND.COM resident i entorn | 3,6 KB | HIDOS (/S, /S-) o LOADHI /C |
| Part transitòria de COMMAND.COM | 22 KB | a baix no ocupa res; amb LOADHI /C queda reservada a dalt |
| LOADHI resident (si és el SHELL=) | 2,2 KB | va on vagi l'intèrpret |
| BUFFERS / FILES / FCBS | 530 / 53 / 53 bytes cadascun | HIDOS (a dalt), `...LOW=` o `/L` (a baix), LOADHI /B: /FILES: |
| Controladors | el que ocupin | `DEVICE=` (a baix) / `DEVICEHIGH=` (a dalt amb HIDOS) |

El CONFIG.SYS de base és el mateix per a tots els escenaris:

```
FILES=20
BUFFERS=10
FCBS=1,0
COUNTRY=034
LASTDRIVE=C
REM Comentaris permesos amb HIDOS (també amb /N)
DEVICEHIGH=C:\MSDOS\ANSI.SYS
SHELL=...                      (la línia que digui cada escenari)
```

### 1. Tot el DOS a la convencional, CONFIG.SYS ampliat sense errors

El DOS com sempre, però el CONFIG.SYS entén `REM`, `DEVICEHIGH=`
(que llavors carrega a baix), `BUFFERSLOW=`, `FILESLOW=` i `FCBSLOW=`,
sense dir *Comando irreconocible*.

```
HIDOS /N
```
```
SHELL=C:\COMMAND.COM C:\ /P
```

Programa més extens: ~694 KB (com el DOS original). Si vols memòria
superior per als programes (`LOADHI programa`) però el DOS a baix,
passa per LOADHI sense `/B`, `/FILES` ni `/C`:

```
SHELL=C:\UTILS\LOADHI.COM @C:\UTILS\LOADHI.CFG
```
```
LOADHI.CFG:  /H:BE00-FBFF
             C:\COMMAND.COM C:\ /P
```

### 2. COMMAND.COM a la convencional, la resta del DOS a la superior

```
HIDOS /B /S-
```
```
SHELL=C:\COMMAND.COM C:\ /P
```

Programa més extens: **731 KB**. A baix només hi queden COMMAND.COM
(3,6 KB) i els `DEVICE=`. És la configuració més segura amb el DOS a
dalt: la part transitòria de COMMAND.COM viu a la convencional, on es
pot trepitjar i tornar a llegir del disc sense problemes.

### 3. Tot el DOS a la memòria superior

```
HIDOS /B /S
```

(`/S` és el valor per defecte.) Hi ha dues maneres de posar l'intèrpret:

a) COMMAND.COM directe (programa més extens: **734 KB**; a baix només
queden 1,8 KB del DOS):
```
SHELL=C:\COMMAND.COM C:\ /P
```
COMMAND.COM ocupa 3,6 KB a dalt. La part transitòria (22 KB) queda al
capdamunt de la zona alta, sense reservar. Funciona mentre la zona
alta no s'ompli fins a dalt: si un programa carregat amb LOADHI hi
arribés, COMMAND.COM el trepitjaria en tornar-la a llegir.

b) Amb LOADHI /C (programa més extens: ~734 KB; a dalt, LOADHI
2,2 KB i COMMAND.COM 25,9 KB, part transitòria reservada inclosa):
```
SHELL=C:\UTILS\LOADHI.COM @C:\UTILS\LOADHI.CFG
```
```
LOADHI.CFG:  /C
             C:\COMMAND.COM C:\ /P
```
Sense perill, però gasta 22 KB més de memòria superior.

### 4. Tot el DOS a la superior, excepte COMMAND.COM i el BIOS

```
HIDOS /B- /S-
```
```
SHELL=C:\COMMAND.COM C:\ /P
```

Programa més extens: **722 KB**. A baix: el BIOS del DOS.SYS (8,5 KB) i
COMMAND.COM (3,6 KB). Per si un controlador o un programa no s'entén
amb el BIOS a dalt (/B és el més arriscat: vegeu `HIDOS.TXT`).

### 5. Altres combinacions

**5a. El DOS a dalt, però una part de les taules a baix.** Per deixar
lloc a dalt a un programa que per poc no hi cap. Al CONFIG.SYS (amb
qualsevol dels escenaris 2-4):
```
BUFFERS=5
BUFFERSLOW=5        5 a dalt + 5 a baix
FILES=10
FILESLOW=10         10 a dalt + 10 a baix
FCBSLOW=1,0         els FCBS, tots a baix
```
O, sense tocar el CONFIG.SYS, `HIDOS /L:BFC` (B = BUFFERS, F = FILES,
C = FCBS) passa a baix les taules senceres; `HIDOS /L-` les torna a
dalt.

**5b. Només LOADHI, amb el CONFIG.SYS ampliat** (com abans de HIDOS:
el nucli a baix, però BUFFERS, FILES i COMMAND.COM a dalt):
```
HIDOS /N
```
```
SHELL=C:\UTILS\LOADHI.COM @C:\UTILS\LOADHI.CFG
```
```
LOADHI.CFG:  /H:BE00-FBFF /B:10 /FILES:15 /F /C
             C:\COMMAND.COM C:\ /P
```
Programa més extens: ~693 KB. Al CONFIG.SYS, deixa `BUFFERS=1` i
`FILES=5`: els de més els posa LOADHI (/B: i /FILES:) a dalt.

**5c. DOS.SYS original (`HIDOS /U`) amb LOADHI.** Igual que 5b, però
el CONFIG.SYS no ha de tenir `REM` (dona *Comando irreconocible*) i
el DOS pren `BUFFERSLOW=` per `BUFFERS=`, `FILESLOW=` per `FILES=` i
`DEVICEHIGH=` per `DEVICE=` (val l'últim de cada).

**5d. L'intèrpret a dalt, però el BIOS a baix:** `HIDOS /B- /S` amb
l'escenari 3a o 3b (~726 KB amb 3b).

### Resum

| Escenari | HIDOS | SHELL= | LOADHI.CFG | Programa més extens |
|---|---|---|---|---|
| 1 | `/N` | COMMAND.COM | — | ~694 KB |
| 2 | `/B /S-` | COMMAND.COM | — | 731 KB |
| 3a | `/B /S` | COMMAND.COM | — | 734 KB |
| 3b | `/B /S` | LOADHI | `/C` | ~734 KB |
| 4 | `/B- /S-` | COMMAND.COM | — | 722 KB |
| 5b | `/N` | LOADHI | `/H:BE00-FBFF /B:10 /FILES:15 /F /C` | ~693 KB |
| 5d | `/B- /S` | LOADHI | `/C` | 726 KB |

Després de cada canvi amb HIDOS, reinicia. `HIDOS` sense res diu la
configuració que hi ha, i `MEM /C` o `MEM /D` (0.27 o posterior) on és
cada cosa. Qualsevol combinació es desfà amb `HIDOS /U`.

## Descàrrega

Els executables (`.COM`) són a les
[Releases](../../releases). També es poden assemblar:

```
nasm -f bin LOADHI/LOADHI.ASM -o LOADHI.COM
nasm -f bin -DTRACE LOADHI/LOADHI.ASM -o LOADHIT.COM   (versió de prova)
nasm -f bin MEM/MEM.ASM -o MEM.COM
nasm -f bin GEMHI/GEMHI.ASM -o GEMHI.COM
nasm -f bin CHARMAP/CHARMAP.ASM -o CHARMAP.ACC   (accessori del GEM)
nasm -f bin DOSSHELL/DOSSHELL.ASM -o DOSSHELL.ACC (accessori del GEM)
nasm -f bin EINES/EINES.ASM -o EINES.ACC         (accessori del GEM)
nasm -f bin IOPATCH6/IOPATCH6.ASM -o IOPATCH6.COM
cd IOPATCH && sh BUILD.SH                (IOPATCH.COM i IOCONFIG.COM)
cd HIDOS && sh BUILD.SH                  (HIDOS.COM)
cd SOLITARI && sh BUILD.SH               (SOLITARI.APP; cal python3)
cd VINTIU && sh BUILD.SH                 (VINTIU.APP; cal python3)
nasm -f bin XPATH/XPATH.ASM -o XPATH.COM          (i igual WAIT, SEARCH,
                                                    DIRCLEAN, ATTRIB, ROWS25,
                                                    AMSMOUSE, GEMPATCH, KEYBX)
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
  IOPATCH6 és per al MS-DOS 6.22. XPATH, SEARCH i DIRCLEAN funcionen
  del 3.x al 6.x; WAIT, AMSMOUSE i GEMPATCH, des del 2.0. HIDOS és per
  al MS-DOS 3.20 de l'Amstrad.
- Per a la memòria superior: RAM entre 640 KB i 1 MB (per exemple les
  targetes de memòria *Generic PC/XT* de 86Box).
- GEMHI, CHARMAP, DOSSHELL i EINES: el GEM 2.0 de l'Amstrad PC1512. GEMHI
  necessita la zona alta de LOADHI.

## Codi d'altres

`IOPATCH/DRLDR.BIN` són els primers 2064 bytes del carregador de disc
dur de Digital Research (el que instal·la el FIXLDR del DOS Plus), sobre
el qual es munta el menú. No hi ha cap fitxer de Microsoft: l'IOPATCH
copia l'IO.SYS que ja hi ha al disc, i l'HIDOS modifica el DOS.SYS que
ja hi ha (i el desfà amb /U). GEMPATCH modifica el GEM.EXE de l'usuari
i en desa l'original com a GEM.ORI.

## Autoria

Programes fets per jalavera amb l'ajuda de Claude (IA d'Anthropic), que
n'ha escrit el codi seguint les seves indicacions i proves.

## Llicència

Pendent de triar.
