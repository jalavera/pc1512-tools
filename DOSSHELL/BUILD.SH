#!/bin/sh
# Assembla DOSSHELL.ACC (accessori del GEM: executable MZ amb la capçalera
# dins el codi) a la carpeta que es doni (per defecte, aquesta).
set -e
O=${1:-.}
nasm -f bin DOSSHELL.ASM -o "$O/DOSSHELL.ACC"
