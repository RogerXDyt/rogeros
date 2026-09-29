#!/bin/bash
# Copia src a WSL, construye la ISO y la deja verificada en el escritorio
S="/mnt/c/Users/Administrador.RogerPCGamer/Desktop/RogerOS Linux/src"
D="/mnt/c/Users/Administrador.RogerPCGamer/Desktop/RogerOS Linux/RogerOS.iso"
rm -rf /root/src && cp -r "$S" /root/src
find /root/src -type f ! -name '*.gpg' ! -name '*.png' ! -name '*.deb' -exec sed -i 's/\r$//' {} +
cp /root/src/herramientas/pct.sh /root/src/herramientas/mon.sh /root/
rm -f /root/rogeros/build.log /root/rogeros/*.iso /root/copia-ok
bash /root/src/construir.sh > /root/construir.out 2>&1 < /dev/null
ISO=$(ls /root/rogeros/*.iso) || exit 1
cp "$ISO" "$D.tmp" && [ "$(md5sum < "$ISO")" = "$(md5sum < "$D.tmp")" ] && mv -f "$D.tmp" "$D" && touch /root/copia-ok
