#!/bin/sh
# Assembla SOLITARI.APP (aplicació del GEM 2.0) a la carpeta que es doni
# (per defecte, aquesta). Cal nasm i python3.
set -e
O=${1:-.}
python3 build.py SOLITARI.ASM "$O/SOLITARI.APP"
