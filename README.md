# Eines per a l'Amstrad PC1512 i MS-DOS 3.20

Programes per a MS-DOS 3.x escrits des de zero per a l'Amstrad PC1512
(provats a l'emulador [86Box](https://86box.net)). Cada programa té la
seva carpeta amb el codi font (`.ASM`, NASM) i el seu manual (`.TXT`).

| Programa | Versió | Què fa |
|---|---|---|
| [LOADHI](LOADHI/) | 0.18 | Crea memòria superior (UMB) enllaçada a la cadena del DOS 3.x i hi carrega residents, BUFFERS, FILES i COMMAND.COM |
| [MEM](MEM/) | 0.12 | El MEM del MS-DOS 6.22 refet per a DOS 3.x: memòria convencional i superior, blocs, mapa de B8000 a FFFFF, BUFFERS/FILES/FCBS |

## Descàrrega

Els executables (`.COM`) són a les
[Releases](../../releases). També es poden assemblar:

```
nasm -f bin LOADHI/LOADHI.ASM -o LOADHI.COM
nasm -f bin -DTRACE LOADHI/LOADHI.ASM -o LOADHIT.COM   (versió de prova)
nasm -f bin MEM/MEM.ASM -o MEM.COM
```

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
- Per a la memòria superior: RAM entre 640 KB i 1 MB (per exemple les
  targetes de memòria *Generic PC/XT* de 86Box).

## Autoria

Programes fets per jalavera amb l'ajuda de Claude (IA d'Anthropic), que
n'ha escrit el codi seguint les seves indicacions i proves.

## Llicència

Pendent de triar.
