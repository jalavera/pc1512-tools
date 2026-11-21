#!/bin/sh
# Assembla HIDOS.COM a la carpeta que es doni (per defecte, aquesta).
# HIDOS porta a dins el codi que afegeix al DOS.SYS (HIDOSK), que
# s'ha d'assemblar abans.
set -e
O=${1:-.}
nasm -f bin HIDOSK.ASM -o HIDOSK.BIN
nasm -f bin HIDOS.ASM -o "$O/HIDOS.COM"
rm -f HIDOSK.BIN
