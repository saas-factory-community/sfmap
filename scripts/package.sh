#!/bin/bash
# Empaqueta sfmap como .app, firma con identidad ESTABLE e instala en ~/Applications.
set -euo pipefail
cd "$(dirname "$0")/.."
SFMAP_DO_INSTALL=1
case "${1:-}" in
  --no-install) SFMAP_DO_INSTALL=0 ;;
  "") ;;
  *) echo "Uso: $0 [--no-install]"; exit 2 ;;
esac
SFMAP_PACKAGE_STAMP="$(date +%Y%m%d-%H%M%S)-$$"
SFMAP_BACKUP_DIR="dist/previous/$SFMAP_PACKAGE_STAMP"
mkdir -p "$SFMAP_BACKUP_DIR"

# El icono se REGENERA en cada empaquetado y se VERIFICA. El 20 ago 2026 se
# instaló una app con un iconset donde cada PNG medía el doble de lo que su
# nombre decía, y macOS cayó al icono genérico sin decir nada.
if [ ! -f assets/icon.icns ] || [ assets/logo.svg -nt assets/icon.icns ]; then
  echo "· regenerando el icono desde assets/logo.svg"
  swiftc -O scripts/icono.swift -o /tmp/sfmap-icono
  if [ -d assets/sfmap.iconset ]; then mv assets/sfmap.iconset "$SFMAP_BACKUP_DIR/iconset"; fi
  /tmp/sfmap-icono .
  if [ -f .sfmap-icono.html ]; then mv .sfmap-icono.html "$SFMAP_BACKUP_DIR/icono.html"; fi
  iconutil -c icns assets/sfmap.iconset -o assets/icon.icns
fi

swift build -c release

APP="dist/sfmap.app"
if [ -d "$APP" ]; then mv "$APP" "$SFMAP_BACKUP_DIR/build.app"; fi
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

cp .build/release/SFMap "$APP/Contents/MacOS/sfmap"
cp assets/icon.icns "$APP/Contents/Resources/icon.icns"
# Las fuentes viajan DENTRO: una app que depende de un checkout del repo no es
# una app. Son las mismas .ttf que mide el compilador, no unas parecidas.
cp -R Resources/fuentes "$APP/Contents/Resources/fuentes"

cat > "$APP/Contents/Info.plist" <<'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleName</key><string>sfmap</string>
  <key>CFBundleDisplayName</key><string>sfmap</string>
  <key>CFBundleIdentifier</key><string>com.saasfactory.sfmap</string>
  <key>CFBundleVersion</key><string>0.2.0</string>
  <key>CFBundleShortVersionString</key><string>0.2.0</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleExecutable</key><string>sfmap</string>
  <key>CFBundleIconFile</key><string>icon</string>
  <key>LSMinimumSystemVersion</key><string>15.0</string>
  <key>CFBundleDocumentTypes</key><array><dict>
    <key>CFBundleTypeName</key><string>Lienzo sfmap</string>
    <key>CFBundleTypeRole</key><string>Editor</string>
    <key>LSItemContentTypes</key><array><string>com.saasfactory.sfmap.document</string></array>
  </dict></array>
  <key>UTExportedTypeDeclarations</key><array><dict>
    <key>UTTypeIdentifier</key><string>com.saasfactory.sfmap.document</string>
    <key>UTTypeConformsTo</key><array><string>public.json</string></array>
    <key>UTTypeDescription</key><string>Lienzo editable sfmap</string>
    <key>UTTypeTagSpecification</key><dict><key>public.filename-extension</key><array><string>sfmap</string></array></dict>
  </dict></array>
  <key>NSHighResolutionCapable</key><true/>
  <key>LSApplicationCategoryType</key><string>public.app-category.productivity</string>
</dict>
EOF
echo '</plist>' >> "$APP/Contents/Info.plist"

printf 'APPL????' > "$APP/Contents/PkgInfo"

# ⚠️ FIRMA ESTABLE, NO AD-HOC.
#
# La firma ad-hoc ancla los permisos del sistema al hash del binario, así que
# CADA rebuild los revoca — en silencio, con Ajustes mostrándolos concedidos
# igual. Costó permisos de SFlow, SFCast, SFTerm y SFPoint el 22 jul 2026.
# "SFlow Dev" es la identidad estable que ya existe en el llavero.
IDENT="${SFMAP_IDENTITY:-SFlow Dev}"
if security find-identity -v -p codesigning 2>/dev/null | grep -q "$IDENT"; then
  codesign --force --deep --sign "$IDENT" "$APP"
else
  echo "ERROR: falta identidad estable '$IDENT'; no se instala una firma ad-hoc"
  exit 1
fi

# ⚠️ LA CACHÉ DEL DOCK GUARDA EL ICONO VIEJO.
#
# LaunchServices cachea el icono por ruta de bundle, así que reinstalar con un
# icns nuevo NO cambia lo que se ve: seguiría el genérico de la primera vez.
# `touch` invalida la entrada y `lsregister` la vuelve a leer.
codesign --verify --deep --strict "$APP"
if [ "$SFMAP_DO_INSTALL" = 0 ]; then
  echo "PACKAGE_OK $APP"
  exit 0
fi
mkdir -p "$HOME/Applications"
SFMAP_INSTALL_STAGE="$HOME/Applications/.sfmap-install-$SFMAP_PACKAGE_STAMP.app"
cp -R "$APP" "$SFMAP_INSTALL_STAGE"
codesign --verify "$SFMAP_INSTALL_STAGE"
if [ -d "$HOME/Applications/sfmap.app" ]; then
  mv "$HOME/Applications/sfmap.app" "$SFMAP_BACKUP_DIR/installed.app"
fi
mv "$SFMAP_INSTALL_STAGE" "$HOME/Applications/sfmap.app"
codesign --verify "$HOME/Applications/sfmap.app"

touch "$HOME/Applications/sfmap.app"
LSREG=/System/Library/Frameworks/CoreServices.framework/Versions/A/Frameworks/LaunchServices.framework/Versions/A/Support/lsregister
[ -x "$LSREG" ] && "$LSREG" -f "$HOME/Applications/sfmap.app" || true

echo "INSTALL_OK $HOME/Applications/sfmap.app"
