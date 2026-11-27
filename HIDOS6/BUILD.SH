#!/bin/sh
# Assembla HIDOS6.COM a la carpeta que es doni (per defecte, aquesta).
# HIDOS6 porta a dins el codi que afegeix a l'IO.SYS (HIDOS6K), un per a
# cada IO.SYS conegut (castellà i anglès), que s'ha d'assemblar abans.
set -e
O=${1:-.}
nasm -f bin -DSZ=5A20h -DA79=0A79h -DP36E=36Eh -DP2AF=2AFh -DP2A9=2A9h -DP372=372h -DP36A=36Ah -DP27B=27Bh HIDOS6K.ASM -o K_ES.BIN
nasm -f bin -DSZ=5970h -DA79=0A64h -DP36E=364h -DP2AF=2A5h -DP2A9=29Fh -DP372=368h -DP36A=360h -DP27B=271h HIDOS6K.ASM -o K_EN.BIN
nasm -f bin HIDOS6.ASM -o "$O/HIDOS6.COM"
nasm -f bin UMBPC.ASM -o "$O/UMBPC.SYS"
rm -f K_ES.BIN K_EN.BIN
