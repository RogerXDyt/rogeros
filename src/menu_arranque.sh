#!/bin/bash
# Traduce y renombra el menú de arranque de la ISO (BIOS y UEFI)
B="$1"
S=$B/syslinux_common
sed -i -e 's/menu label ^Live system (@FLAVOUR@)/menu label ^Iniciar RogerOS Linux/' \
       -e 's/menu label Live system (@FLAVOUR@ fail-safe mode)/menu label RogerOS Linux (modo seguro)/' $S/live.cfg.in
sed -i -e 's/menu label ^Utilities/menu label ^Herramientas/' -e 's/menu title Utilities/menu title Herramientas/' \
       -e 's/menu label ^Back../menu label ^Volver/' $S/menu.cfg
grep -q 'menu title RogerOS' $S/stdmenu.cfg || cat >> $S/stdmenu.cfg <<'X'
menu title RogerOS Linux
menu tabmsg Pulsa ENTER para arrancar o TAB para editar
menu autoboot Arrancando RogerOS en # segundos
X
sed -i "s/'Utilities...'/'Herramientas...'/" $B/grub-pc/grub.cfg

# Menú UEFI: 800x600 fijo sale negro en muchos portátiles (ThinkPad X230...).
# Probar varias resoluciones y cargar todos los drivers de vídeo. Sin pitidos.
C=$B/grub-pc/config.cfg
sed -i -e 's/set gfxmode=800x600/set gfxmode=1024x768,800x600,640x480,auto/' \
       -e 's/insmod video_cirrus/insmod video_cirrus\n    insmod all_video/' \
       -e '/^insmod play/d' -e '/^play /d' $C

# Entrada "modo compatible": imagen básica y mensajes visibles (para PCs donde se queda en negro)
COMPAT="boot=live components nomodeset noplymouth systemd.show_status=1 hostname=rogeros username=roger locales=es_ES.UTF-8 keyboard-layouts=es timezone=Europe/Madrid"
grep -q 'modo compatible' $S/live.cfg.in || cat >> $S/live.cfg.in <<X

label live-compat
	menu label RogerOS Linux (modo compatible)
	linux @LINUX@
	initrd @INITRD@
	append $COMPAT
X
grep -q 'modo compatible' $B/grub-pc/grub.cfg || sed -i "/^submenu 'Herramientas/i menuentry \"RogerOS Linux (modo compatible)\" {\n\tlinux /live/vmlinuz $COMPAT\n\tinitrd /live/initrd.img\n}\n" $B/grub-pc/grub.cfg
# live-build genera las entradas de GRUB (UEFI) desde este script del sistema anfitrión
G=/usr/lib/live/build/binary_grub_cfg
sed -i -e 's/"Live system (autodetect) (fail-safe mode)"/"RogerOS Linux (modo seguro)"/' \
       -e 's/"Live system (autodetect)"/"Iniciar RogerOS Linux"/' \
       -e 's/"Live system (${_FLAVOUR} fail-safe mode)"/"RogerOS Linux (modo seguro)"/' \
       -e 's/"Live system (${_FLAVOUR})"/"Iniciar RogerOS Linux"/' \
       -e 's/"RogerOS Linux (autodetect) (fail-safe mode)"/"RogerOS Linux (modo seguro)"/' \
       -e 's/"RogerOS Linux (autodetect)"/"Iniciar RogerOS Linux"/' \
       -e 's/"RogerOS Linux (${_FLAVOUR} fail-safe mode)"/"RogerOS Linux (modo seguro)"/' \
       -e 's/"RogerOS Linux (${_FLAVOUR})"/"Iniciar RogerOS Linux"/' $G
