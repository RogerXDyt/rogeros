#!/bin/bash
# Construye RogerOS Linux (Debian 13 muy modificado) dentro de WSL.
set -e
SRC="$(cd "$(dirname "$0")" && pwd)"
W=/root/rogeros
mkdir -p $W && cd $W
lb clean 2>/dev/null || true      # sin --purge: conserva los paquetes ya descargados
rm -rf config

lb config \
  --distribution trixie \
  --archive-areas "main contrib non-free non-free-firmware" \
  --debian-installer none \
  --iso-application "RogerOS Linux" --iso-publisher "Roger" --iso-volume "RogerOS" \
  --image-name RogerOS \
  --bootappend-live "boot=live components quiet splash hostname=rogeros username=roger locales=es_ES.UTF-8 keyboard-layouts=es timezone=Europe/Madrid"

# ---------- Paquetes ----------
cat > config/package-lists/rogeros.list.chroot <<'EOF'
xfce4 xfce4-goodies xfce4-whiskermenu-plugin lightdm lightdm-gtk-greeter
arc-theme papirus-icon-theme fonts-dejavu fonts-noto-core fonts-noto-color-emoji
plymouth plymouth-themes plymouth-label
firefox-esr firefox-esr-l10n-es-es
network-manager network-manager-gnome pipewire-audio pavucontrol pulseaudio-utils
calamares calamares-settings-debian
python3 python3-gi gir1.2-gtk-3.0 pkexec pciutils zstd zenity wmctrl
flatpak zram-tools ufw gamemode linux-cpupower unattended-upgrades apt-listchanges curl libnotify-bin
fastfetch htop mousepad ristretto thunar-archive-plugin file-roller vlc
locales keyboard-configuration console-setup sudo
EOF

# Paquetes que el instalador necesita SIN internet: van dentro de la ISO (carpeta pool)
# y el instalador los usa como repositorio. Sin esto no se instala el arranque (GRUB).
# grub-pc (BIOS) y grub-efi (UEFI) chocan entre sí: se descargan en dos tandas separadas.
# Con ellos se monta un repositorio apt dentro de la ISO (/pool + /dists/trixie), que es
# lo que el instalador (calamares-sources-media) añade como fuente al instalar.
command -v apt-ftparchive >/dev/null || apt-get install -y -qq apt-utils >/dev/null
REPO=config/includes.binary
POOL=$REPO/pool/main
mkdir -p $POOL $REPO/dists/trixie/main/binary-amd64 /tmp/debs-bios /tmp/debs-efi
apt-get update -qq
for grupo in "bios:grub-pc cryptsetup cryptsetup-initramfs keyutils os-prober" \
             "efi:grub-efi grub-efi-amd64 grub-efi-amd64-signed shim-signed efibootmgr mokutil"; do
  dir=/tmp/debs-${grupo%%:*}; rm -f $dir/*.deb
  apt-get install -y -qq --download-only --reinstall -o Dir::Cache::archives=$dir ${grupo#*:} >/dev/null
  cp $dir/*.deb $POOL/
done
ls $POOL | grep -E '^(grub-pc|grub-efi-amd64|shim-signed)_' || { echo "FALTAN PAQUETES DE GRUB"; exit 1; }
( cd $REPO
  apt-ftparchive packages pool/main > dists/trixie/main/binary-amd64/Packages
  gzip -kf dists/trixie/main/binary-amd64/Packages
  apt-ftparchive -o APT::FTPArchive::Release::Suite=trixie -o APT::FTPArchive::Release::Codename=trixie \
    -o APT::FTPArchive::Release::Components=main -o APT::FTPArchive::Release::Architectures=amd64 \
    release dists/trixie > /tmp/Release && mv /tmp/Release dists/trixie/Release )
# Y las herramientas de GRUB ya instaladas en el sistema en vivo, por si acaso
echo "grub-pc-bin grub-efi-amd64-bin grub2-common efibootmgr os-prober" > config/package-lists/grub.list.chroot

# ---------- Todo lo de RogerOS, como paquete ACTUALIZABLE (rogeros-base) ----------
# Programas, temas, sonidos y ajustes van en un .deb: así se actualizan desde el servidor
# de tu PC sin reinstalar. live-build instala los .deb de config/packages.chroot.
[ -f "$SRC/sistema/usr/share/keyrings/rogeros.gpg" ] || { echo "FALTA la clave: ejecuta antes PUBLICAR_ACTUALIZACION.bat"; exit 1; }
mkdir -p config/packages.chroot
bash "$SRC/hacer_paquete.sh" "$SRC" config/packages.chroot
# initramfs ligero: el hook tiene que estar ANTES de que se genere el initrd en el chroot
mkdir -p config/includes.chroot/etc/initramfs-tools/hooks config/includes.chroot/etc/initramfs-tools/conf.d
cp "$SRC/sistema/etc/initramfs-tools/hooks/"* config/includes.chroot/etc/initramfs-tools/hooks/
cp "$SRC/sistema/etc/initramfs-tools/conf.d/"* config/includes.chroot/etc/initramfs-tools/conf.d/
chmod 755 config/includes.chroot/etc/initramfs-tools/hooks/*

# ---------- Hook de personalización (se ejecuta dentro del sistema) ----------
cat > config/hooks/normal/9000-rogeros.hook.chroot <<'EOF'
#!/bin/sh
set -e
# Identidad
V=$(cat /etc/rogeros/version-publica 2>/dev/null || cat /etc/rogeros/version)
cat > /etc/os-release <<X
PRETTY_NAME="RogerOS Linux $V"
NAME="RogerOS Linux"
VERSION_ID="$V"
VERSION="$V (Neón)"
VERSION_CODENAME=trixie
ID=rogeros
ID_LIKE=debian
HOME_URL="https://www.debian.org/"
X
cp /etc/os-release /usr/lib/os-release
echo "RogerOS Linux $V \\n \\l" > /etc/issue
echo "RogerOS Linux $V" > /etc/issue.net
echo "rogeros" > /etc/hostname
echo '. /etc/profile.d/rogeros.sh' >> /etc/bash.bashrc

# Fondo por defecto en cualquier ruta de XFCE
for f in /usr/share/backgrounds/xfce/*; do [ -e "$f" ] && ln -sf /usr/share/backgrounds/rogeros/wallpaper.png "$f"; done

# GRUB del sistema instalado
if [ -f /etc/default/grub ]; then
  sed -i 's/^GRUB_DISTRIBUTOR=.*/GRUB_DISTRIBUTOR="RogerOS"/; s/^GRUB_CMDLINE_LINUX_DEFAULT=.*/GRUB_CMDLINE_LINUX_DEFAULT="quiet splash loglevel=3"/; s/^GRUB_TIMEOUT=.*/GRUB_TIMEOUT=2/' /etc/default/grub
  echo 'GRUB_BACKGROUND="/usr/share/backgrounds/rogeros/wallpaper.png"' >> /etc/default/grub
fi

# Servicios: memoria comprimida, cortafuegos, perfil de rendimiento
sed -i 's/^ENABLED=.*/ENABLED=yes/' /etc/ufw/ufw.conf
systemctl enable ufw zramswap rogeros-modo.service || true

# Flathub listo para usar
flatpak remote-add --if-not-exists flathub https://dl.flathub.org/repo/flathub.flatpakrepo || true

# Instalador Calamares con marca RogerOS
if [ -d /etc/calamares/branding/debian ]; then
  cp -r /etc/calamares/branding/debian /etc/calamares/branding/rogeros
  B=/etc/calamares/branding/rogeros/branding.desc
  sed -i -E 's/^componentName:.*/componentName:  rogeros/' $B
  sed -i -E 's/^( *)(productName|shortProductName|bootloaderEntryName):.*/\1\2: RogerOS/' $B
  sed -i -E "s/^( *)(versionedName|shortVersionedName):.*/\1\2: RogerOS Linux $V/" $B
  sed -i -E "s/^( *)(version|shortVersion):.*/\1\2: $V/" $B
  for img in $(grep -E '^ *(productLogo|productIcon|productWelcome):' $B | awk '{print $2}' | tr -d '"'); do
    cp /usr/share/rogeros/logo.png /etc/calamares/branding/rogeros/$img
  done
  sed -i -E 's/^( *)(sidebarBackground|sidebarBackgroundCurrent):.*/\1\2: "#12042a"/; s/^( *)(sidebarText|sidebarTextCurrent|sidebarTextSelect):.*/\1\2: "#00e5ff"/' $B
  sed -i 's/^branding: .*/branding: rogeros/' /etc/calamares/settings.conf
fi
# Espacio mínimo para instalar: 8 GB (RogerOS ocupa ~6 GB), RAM mínima 1 GB
for f in /etc/calamares/modules/welcome.conf /usr/share/calamares/modules/welcome.conf; do
  [ -f "$f" ] && sed -i -E 's/^( *requiredStorage:).*/\1 8.0/; s/^( *requiredRam:).*/\1 1.0/' "$f"
done
# El lanzador del menú usa nuestra barra de carga
for d in /usr/share/applications/calamares-install-debian.desktop /usr/share/applications/calamares.desktop; do
  [ -f "$d" ] && sed -i 's|^Exec=.*|Exec=rogeros-instalar|; s|^Name=.*|Name=Instalar RogerOS|; s|^Name\[es\]=.*|Name[es]=Instalar RogerOS|; s|^Icon=.*|Icon=/usr/share/rogeros/logo.png|' "$d"
done

# Plymouth
plymouth-set-default-theme rogeros || true
# Español
sed -i 's/^# *es_ES.UTF-8/es_ES.UTF-8/' /etc/locale.gen && locale-gen
update-initramfs -u -k all
EOF
chmod +x config/hooks/normal/9000-rogeros.hook.chroot
cp "$SRC/marca.hook.chroot" config/hooks/normal/9100-marca.hook.chroot
chmod +x config/hooks/normal/9100-marca.hook.chroot

# ---------- Menú de arranque neón ----------
mkdir -p config/bootloaders
cp -r /usr/share/live/build/bootloaders/grub-pc config/bootloaders/
cp -r /usr/share/live/build/bootloaders/isolinux config/bootloaders/
cp -r /usr/share/live/build/bootloaders/syslinux_common config/bootloaders/
rsvg-convert -w 800 -h 600 "$SRC/splash.svg" -o config/bootloaders/grub-pc/splash.png
rsvg-convert -w 640 -h 480 "$SRC/splash.svg" -o config/bootloaders/syslinux_common/splash.png
cp "$SRC/grub-theme.txt" config/bootloaders/grub-pc/live-theme/theme.txt
bash "$SRC/menu_arranque.sh" config/bootloaders

lb build > build.log 2>&1
ls -lh $W/*.iso
