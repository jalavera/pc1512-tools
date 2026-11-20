#!/bin/sh
# Assembla EINES.ACC (accessori del GEM: executable MZ amb la capçalera
# dins el codi) a la carpeta que es doni (per defecte, aquesta).
set -e
O=${1:-.}
nasm -f bin EINES.ASM -o "$O/EINES.ACC"
