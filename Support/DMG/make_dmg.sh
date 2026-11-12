#!/bin/bash
# Cria build/SharkBar.dmg: janela com o app, atalho para Aplicativos e fundo com instruções.
# Uso: Support/DMG/make_dmg.sh build/SharkBar.app build/SharkBar.dmg
set -euo pipefail
APP=$1; OUTDMG=$2
NAME=SharkBar
HERE=$(cd "$(dirname "$0")" && pwd)
WORK=$(mktemp -d)
trap 'hdiutil detach -quiet "/Volumes/$NAME" 2>/dev/null || true; rm -rf "$WORK"' EXIT

# Fundo (1x + 2x num TIFF só, para telas Retina)
xcrun swift "$HERE/make_background.swift" "$WORK/bg1.png" 1 >/dev/null
xcrun swift "$HERE/make_background.swift" "$WORK/bg2.png" 2 >/dev/null
mkdir -p "$WORK/stage/.background"
tiffutil -cathidpicheck "$WORK/bg1.png" "$WORK/bg2.png" -out "$WORK/stage/.background/background.tiff" >/dev/null 2>&1

ditto "$APP" "$WORK/stage/$NAME.app"
ln -s /Applications "$WORK/stage/Aplicativos"
cp "$HERE/../AppIcon.icns" "$WORK/stage/.VolumeIcon.icns"

hdiutil detach -quiet "/Volumes/$NAME" 2>/dev/null || true
hdiutil create -quiet -volname "$NAME" -srcfolder "$WORK/stage" -fs HFS+ -format UDRW -ov "$WORK/rw.dmg"
hdiutil attach -quiet -noautoopen -readwrite "$WORK/rw.dmg"
xcrun SetFile -a C "/Volumes/$NAME" 2>/dev/null || true   # usa o ícone do volume

# Layout da janela pelo Finder (se o macOS negar a automação, o DMG funciona igual, só sem o layout).
osascript <<OSA || echo "  (layout da janela pulado: permita Automação do Terminal → Finder para aplicar)"
tell application "Finder"
  tell disk "$NAME"
    open
    set current view of container window to icon view
    set toolbar visible of container window to false
    set statusbar visible of container window to false
    set the bounds of container window to {200, 120, 840, 548}
    set opts to the icon view options of container window
    set arrangement of opts to not arranged
    set icon size of opts to 112
    set text size of opts to 13
    set background picture of opts to file ".background:background.tiff"
    set position of item "$NAME.app" of container window to {170, 200}
    set position of item "Aplicativos" of container window to {470, 200}
    update without registering applications
    delay 1
    close
  end tell
end tell
OSA
sync
hdiutil detach -quiet "/Volumes/$NAME"
rm -f "$OUTDMG"
hdiutil convert -quiet "$WORK/rw.dmg" -format UDZO -imagekey zlib-level=9 -o "$OUTDMG"
echo "  $(du -h "$OUTDMG" | cut -f1) $OUTDMG"
