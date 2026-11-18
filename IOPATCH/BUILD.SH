#!/bin/sh
# Assembla IOPATCH.COM i IOCONFIG.COM a la carpeta que es doni (per
# defecte, aquesta). L'IOPATCH porta a dins la capçalera nova de l'IO.SYS
# (carregador de DR + IOX), que s'ha d'assemblar abans.
set -e
O=${1:-.}
nasm -f bin IOX.ASM -o IOX.BIN
nasm -f bin IOMENU.ASM -o IO_NOU.SYS
nasm -f bin IOPATCH.ASM -o "$O/IOPATCH.COM"
nasm -f bin IOCONFIG.ASM -o "$O/IOCONFIG.COM"
rm -f IOX.BIN IO_NOU.SYS
