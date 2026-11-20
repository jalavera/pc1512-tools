#!/bin/sh
# Assembla CHARMAP.ACC (accessori del GEM: executable MZ amb la capçalera
# dins el codi) a la carpeta que es doni (per defecte, aquesta).
set -e
O=${1:-.}
nasm -f bin CHARMAP.ASM -o "$O/CHARMAP.ACC"
