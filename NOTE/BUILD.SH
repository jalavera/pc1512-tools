#!/bin/sh
# Assembla NOTE.COM i FREENOTE.COM (comparteixen NOTE.INC)
OUT=${1:-.}
nasm -f bin NOTE.ASM -o "$OUT/NOTE.COM" &&
nasm -f bin FREENOTE.ASM -o "$OUT/FREENOTE.COM"
