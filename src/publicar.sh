#!/bin/bash
# Publica una actualización de RogerOS en el servidor de tu PC:
#   1. (solo la primera vez) crea tu clave de firma
#   2. sube la versión (1.1.0 -> 1.1.1) si ya estaba publicada
#   3. empaqueta rogeros-base con lo que haya ahora en src/
#   4. lo mete en el repositorio y lo FIRMA
set -e
W="/mnt/c/Users/Administrador.RogerPCGamer/Desktop/RogerOS Linux"
SRCW="$W/src"; REPO="$W/servidor_actualizaciones/repo"; CLAVEW="$W/servidor_actualizaciones/clave"
export GNUPGHOME=/root/.rogeros-gpg
command -v apt-ftparchive >/dev/null || apt-get install -y -qq apt-utils >/dev/null
command -v gpg >/dev/null || apt-get install -y -qq gnupg >/dev/null
command -v rsvg-convert >/dev/null || apt-get install -y -qq librsvg2-bin >/dev/null

# ---- 1. clave de firma (se queda en tu PC; la pública va dentro de RogerOS)
mkdir -p -m 700 $GNUPGHOME
if ! gpg --list-secret-keys rogeros@localhost >/dev/null 2>&1; then
  echo "» Creando tu clave de firma de RogerOS (solo esta vez)"
  gpg --batch --passphrase '' --quick-gen-key "RogerOS Actualizaciones <rogeros@localhost>" ed25519 sign never
  mkdir -p "$CLAVEW"
  gpg --armor --export-secret-keys rogeros@localhost > "$CLAVEW/clave_privada_NO_COMPARTIR.asc"
  echo "  Copia de seguridad de la clave en servidor_actualizaciones/clave (¡no la compartas nunca!)"
fi
mkdir -p "$SRCW/sistema/usr/share/keyrings" "$REPO/pool/main" "$REPO/dists/estable/main/binary-amd64"
gpg --export rogeros@localhost > "$SRCW/sistema/usr/share/keyrings/rogeros.gpg"
cp "$SRCW/sistema/usr/share/keyrings/rogeros.gpg" "$REPO/rogeros.gpg"

# ---- 2. versión
V=$(tr -d ' \r\n' < "$SRCW/VERSION")
if [ -f "$REPO/pool/main/rogeros-base_${V}_all.deb" ]; then
  IFS=. read -r a b c <<< "$V"; V="$a.$b.$((c+1))"
  printf '%s\n' "$V" > "$SRCW/VERSION"
fi
echo "» Versión a publicar: $V"

# ---- 3. empaquetar (desde una copia limpia de src, sin finales de línea de Windows)
rm -rf /root/src-pub && cp -r "$SRCW" /root/src-pub
find /root/src-pub -type f ! -name '*.png' ! -name '*.gpg' ! -name '*.jpg' -exec sed -i 's/\r$//' {} +
bash /root/src-pub/hacer_paquete.sh /root/src-pub "$REPO/pool/main"
# quedarse solo con las 3 últimas versiones
ls -1t "$REPO"/pool/main/rogeros-base_*.deb | tail -n +4 | xargs -r rm -f

# ---- 4. índice del repositorio + firma
cd "$REPO"
apt-ftparchive packages pool/main > dists/estable/main/binary-amd64/Packages
gzip -kf dists/estable/main/binary-amd64/Packages
apt-ftparchive -o APT::FTPArchive::Release::Origin=RogerOS -o APT::FTPArchive::Release::Label=RogerOS \
  -o APT::FTPArchive::Release::Suite=estable -o APT::FTPArchive::Release::Codename=estable \
  -o APT::FTPArchive::Release::Components=main -o APT::FTPArchive::Release::Architectures="amd64 all" \
  release dists/estable > /tmp/Release
mv /tmp/Release dists/estable/Release
gpg --batch --yes --local-user rogeros@localhost --clearsign -o dists/estable/InRelease dists/estable/Release
gpg --batch --yes --local-user rogeros@localhost -abs -o dists/estable/Release.gpg dists/estable/Release
echo
echo "✔ Publicada la versión $V de RogerOS."
echo "  Con ARRANCAR_SERVIDOR.bat abierto, los RogerOS la verán al pulsar Actualizar."
