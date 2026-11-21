#!/usr/bin/env python3
# build.py prog.asm SORTIDA.APP [pila_bytes]
# Assembla amb nasm (imatge pura, org 0) i hi afegeix una capcalera MZ
# estandard: un sol segment, CS=SS=segment de carrega, IP=0, sense reubicacions.
# La zona BSS (mida a l'offset 3, vegeu exe.inc) no va al fitxer: DOS la
# reserva amb la memoria minima de la capcalera, juntament amb la pila.
import struct, subprocess, sys, os, tempfile
src, out = sys.argv[1], sys.argv[2]
pila = int(sys.argv[3]) if len(sys.argv) > 3 else 4096
tmp = tempfile.mktemp(suffix='.bin')
subprocess.run(['nasm', '-f', 'bin', src, '-o', tmp], check=True)
img = open(tmp, 'rb').read(); os.remove(tmp)
bss = struct.unpack('<H', img[3:5])[0] if img[0] == 0xE9 else 0
img += b'\0' * (-len(img) % 16)               # imatge en paragrafs sencers
total = 32 + len(img)
extra = (bss + pila) // 16 + 1
sp = len(img) + bss + pila
assert sp < 0x10000, 'programa massa gran per un sol segment'
hdr = struct.pack('<2s13H', b'MZ', total % 512, (total + 511) // 512,
                  0, 2, extra, extra, 0, sp, 0, 0, 0, 0x1C, 0)
hdr += b'\0' * (32 - len(hdr))
open(out, 'wb').write(hdr + img)
print(f'{out}: {total} bytes (+{bss} de BSS), pila {pila}, SS:SP=0000:{sp:04X}')
