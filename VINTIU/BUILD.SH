#!/bin/sh
# Assembla VINTIU.APP (aplicació del GEM 2.0) a la carpeta que es doni
# (per defecte, aquesta). Cal nasm i python3.
set -e
O=${1:-.}
python3 build.py VINTIU.ASM "$O/VINTIU.APP"
