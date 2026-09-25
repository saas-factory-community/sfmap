#!/bin/bash
# Arma los assets de una release pública a partir de dist/sfmap.app (hecho por package.sh).
# Resultado en dist/release-<versión>/: zip (app + plantillas + guía), plantillas sueltas y SHA256SUMS.
# No publica nada: subirlo es un paso explícito con `gh release create`.
set -euo pipefail
cd "$(dirname "$0")/.."
VER="$(/usr/libexec/PlistBuddy -c 'Print CFBundleShortVersionString' dist/sfmap.app/Contents/Info.plist)"
OUT="dist/release-$VER"
STAGE="$OUT/sfmap-$VER"
rm -rf "$OUT"; mkdir -p "$STAGE/Plantillas"
codesign --verify --deep --strict dist/sfmap.app
ditto dist/sfmap.app "$STAGE/sfmap.app"
cp templates/mapa-de-claridad/Mapa-de-Claridad.sfmap "$STAGE/Plantillas/"
cp templates/tu-negocio/Tu-negocio.sfmap "$STAGE/Plantillas/"
cp docs/instalacion.md "$STAGE/LEEME-Instalacion.md"
# Nada privado dentro: ni .env, ni bases, ni memorias.
if find "$STAGE" \( -name '.env*' -o -name '*.sqlite' -o -name '*.db' -o -name 'MEMORY*' \) | grep -q .; then
  echo "ERROR: archivo privado dentro del paquete"; exit 1
fi
( cd "$OUT" && ditto -c -k --keepParent "sfmap-$VER" "sfmap-$VER-macOS-arm64.zip" )
cp templates/mapa-de-claridad/Mapa-de-Claridad.sfmap "$OUT/"
cp templates/tu-negocio/Tu-negocio.sfmap "$OUT/"
cp docs/instalacion.md "$OUT/Instalacion.md"
( cd "$OUT" && shasum -a 256 "sfmap-$VER-macOS-arm64.zip" Mapa-de-Claridad.sfmap Tu-negocio.sfmap Instalacion.md > SHA256SUMS )
rm -rf "$STAGE"
cat "$OUT/SHA256SUMS"
echo "RELEASE_OK $OUT"
