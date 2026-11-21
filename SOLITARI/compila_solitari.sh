#!/bin/sh
# Compila SOLITARI.APP a partir de SOLITARI.ASM.
# Cal tenir a la mateixa carpeta que aquest script:
#   SOLITARI.ASM  SOLITARI.INC  exe.inc  build.py
# Funciona sigui quina sigui la carpeta (i des d'on s'executi).
# Requisits al Mac: python3 i nasm (brew install nasm)

# Anar a la carpeta on hi ha aquest script
cd "$(dirname "$0")" || exit 1

for f in SOLITARI.ASM SOLITARI.INC exe.inc build.py; do
  if [ ! -f "$f" ]; then
    echo "Falta el fitxer $f a $(pwd)"
    exit 1
  fi
done

if ! command -v nasm >/dev/null 2>&1; then
  echo "No trobo nasm. Instal·la'l amb: brew install nasm"
  exit 1
fi
if ! command -v python3 >/dev/null 2>&1; then
  echo "No trobo python3."
  exit 1
fi

python3 build.py SOLITARI.ASM SOLITARI.APP || exit 1
echo "Fet: $(pwd)/SOLITARI.APP"
