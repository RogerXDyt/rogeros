#!/bin/bash
# Construye el paquete rogeros-base_<versión>_all.deb con TODO lo propio de RogerOS
# (programas, temas, sonidos, configuración). Es lo que se actualiza desde tu PC.
# Uso: hacer_paquete.sh <carpeta src> <carpeta de salida>
set -e
SRC="$1"; OUT="$2"
V=$(tr -d ' \r\n' < "$SRC/VERSION")
P=$(mktemp -d); R=$P/usr/share/rogeros/raiz
mkdir -p $P/DEBIAN $R/etc/skel "$OUT"

# --- Contenido: se instala primero en /usr/share/rogeros/raiz y postinst lo copia a /
cp -r "$SRC/sistema/." $R/
cp -r "$SRC/skel/." $R/etc/skel/
cp -r "$SRC/etc/." $R/etc/
mkdir -p $R/usr/share/rogeros $R/usr/share/backgrounds/rogeros $R/usr/share/sounds/rogeros \
         $R/usr/share/plymouth/themes/rogeros
# ---- Pack de fondos (/usr/share/backgrounds/rogeros/pack) + miniaturas + nombres
FP=$R/usr/share/backgrounds/rogeros/pack; mkdir -p $FP/mini
PACKW="${PACK_IA:-/mnt/c/Users/Administrador.RogerPCGamer/Desktop/RogerOS Linux/pack de imagenes ia}"
rsvg-convert -w 1920 -h 1080 "$SRC/wallpaper.svg" -o $FP/neon.png                 # Neón clásico
[ -f "$SRC/wallpaper.png" ] && cp "$SRC/wallpaper.png" $FP/lago.png || cp $FP/neon.png $FP/lago.png
declare -A RENOMBRAR=([Krea2_turbo_00006_]=valle [Krea2_turbo_00007_]=rio)
if [ -d "$PACKW" ]; then
  for f in "$PACKW"/*.png; do
    b=$(basename "$f" .png)
    case "$b" in RogerOS_lago_*) continue ;; esac                 # duplicado del lago principal
    cp "$f" "$FP/${RENOMBRAR[$b]:-$b}.png"
  done
fi
for f in $FP/*.png; do
  convert "$f" -resize 320x180^ -gravity center -extent 320x180 -quality 85 "$FP/mini/$(basename "$f" .png).jpg"
done
cat > $FP/nombres.json <<'EOF'
{"lago": "Lago al atardecer", "neon": "Neón clásico", "valle": "Valle soleado", "rio": "Río salvaje",
 "aurora": "Aurora boreal", "dunas": "Dunas y luna", "sakura": "Jardín de cerezos", "playa": "Playa tropical",
 "ciudad": "Ciudad neón", "galaxia": "Galaxia", "otono": "Bosque de otoño", "cabana": "Cabaña nevada",
 "coral": "Arrecife de coral", "cascada": "Cascada de Islandia"}
EOF
# El fondo "de serie" (pantalla de inicio de sesión, GRUB) sigue en la ruta de siempre
cp $FP/lago.png $R/usr/share/backgrounds/rogeros/wallpaper.png
rsvg-convert -w 256 -h 256 "$SRC/logo.svg" -o $R/usr/share/rogeros/logo.png
cp "$SRC/logo.svg" $R/usr/share/rogeros/logo.svg
python3 "$SRC/sonido.py" $R/usr/share/sounds/rogeros/inicio.wav
T=$R/usr/share/plymouth/themes/rogeros
cp $R/usr/share/rogeros/logo.png $T/logo.png
cp "$SRC/plymouth/rogeros.plymouth" "$SRC/plymouth/rogeros.script" $T/
rsvg-convert "$SRC/plymouth/marco.svg" -o $T/marco.png
rsvg-convert "$SRC/plymouth/relleno.svg" -o $T/relleno.png
echo "$V" > $R/etc/rogeros/version
# Lo que ve la gente ("RogerOS 1.0"); la versión interna de arriba es la que usan las actualizaciones
tr -d ' \r\n' < "$SRC/VERSION_PUBLICA" > $R/etc/rogeros/version-publica 2>/dev/null || echo "$V" > $R/etc/rogeros/version-publica
# Novedades de esta versión (las enseña el actualizador al terminar)
[ -f "$SRC/NOVEDADES.txt" ] && cp "$SRC/NOVEDADES.txt" $R/usr/share/rogeros/novedades.txt
find $R -name '__pycache__' -prune -exec rm -rf {} +
chmod 755 $R/usr/local/bin/* $R/usr/lib/rogeros/* $R/etc/initramfs-tools/hooks/* 2>/dev/null || true

# --- Metadatos del paquete
cat > $P/DEBIAN/control <<EOF
Package: rogeros-base
Version: $V
Architecture: all
Maintainer: Roger <rogeros@localhost>
Depends: python3, python3-gi, gir1.2-gtk-3.0, flatpak, zenity, wmctrl, pkexec, sudo, curl, libnotify-bin,
 imagemagick, blueman, tlp, flameshot
Section: misc
Priority: optional
Description: Programas, temas y ajustes de RogerOS Linux
 El Centro RogerOS, la tienda, el actualizador, el comando roger, el tema neón,
 los sonidos y la configuración del sistema. Se actualiza desde el servidor de RogerOS.
EOF

cat > $P/DEBIAN/postinst <<'EOF'
#!/bin/sh
set -e
R=/usr/share/rogeros/raiz
# El perfil de rendimiento elegido por el usuario no se pisa
[ -f /etc/rogeros/modo ] && cp /etc/rogeros/modo /tmp/.rogeros-modo
# tar respeta las carpetas que en Debian son enlaces (p. ej. /usr/lib/firefox-esr/distribution)
tar -C $R -cf - . | tar -C / -xf - --keep-directory-symlink --no-same-owner
[ -f /tmp/.rogeros-modo ] && mv /tmp/.rogeros-modo /etc/rogeros/modo
chmod 440 /etc/sudoers.d/rogeros* 2>/dev/null || true
chmod 755 /usr/local/bin/* /usr/lib/rogeros/* 2>/dev/null || true
if [ -d /run/systemd/system ]; then
  systemctl daemon-reload || true
  sysctl --system >/dev/null 2>&1 || true
fi
systemctl enable rogeros-modo.service >/dev/null 2>&1 || true
# Si cambia la pantalla de carga, regenerar el arranque (no en el sistema en vivo)
if [ ! -d /run/live ] && command -v plymouth-set-default-theme >/dev/null; then
  N=$(cat /usr/share/plymouth/themes/rogeros/* 2>/dev/null | md5sum | cut -c1-32)
  if [ "$N" != "$(cat /var/lib/rogeros/plymouth.md5 2>/dev/null)" ]; then
    plymouth-set-default-theme rogeros || true
    [ -d /run/systemd/system ] && update-initramfs -u >/dev/null 2>&1 || true
    mkdir -p /var/lib/rogeros; echo "$N" > /var/lib/rogeros/plymouth.md5
  fi
fi
exit 0
EOF
chmod 755 $P/DEBIAN/postinst

dpkg-deb --build --root-owner-group -Zxz $P "$OUT/rogeros-base_${V}_all.deb" >/dev/null
rm -rf $P
echo "$OUT/rogeros-base_${V}_all.deb"
