#!/bin/bash
# Compila SharkBar.app (barra de menu + janela) com widgets/controles e instala em ~/Applications.
#
#   ./build.sh                         compila para este Mac, instala e abre
#   INSTALL=0 ./build.sh               só compila (em build/)
#   RELEASE=1 ./build.sh               binário universal (Apple Silicon + Intel) e build/SharkBar.zip
#   SIGN_ID="Apple Development: …" ./build.sh   assina com sua conta Apple (padrão: ad-hoc)
set -euo pipefail
cd "$(dirname "$0")"

SDK=$(xcrun --sdk macosx --show-sdk-path)
SIGN_ID="${SIGN_ID:--}"
OUT=build
APP="$OUT/SharkBar.app"
APPEX="$APP/Contents/PlugIns/SharkBarWidget.appex"
if [[ "${RELEASE:-0}" == 1 ]]; then ARCHS=(arm64 x86_64); INSTALL=${INSTALL:-0}; else ARCHS=("$(uname -m)"); fi

# compile <saída> <flags extras…> -- <fontes…>
compile() {
  local out=$1; shift
  local extra=(); while [[ $1 != "--" ]]; do extra+=("$1"); shift; done; shift
  local slices=()
  for arch in "${ARCHS[@]}"; do
    xcrun swiftc -sdk "$SDK" -target "$arch-apple-macos14.0" -swift-version 5 -O -parse-as-library \
      ${extra[@]+"${extra[@]}"} -o "$out.$arch" "$@"
    slices+=("$out.$arch")
  done
  lipo -create "${slices[@]}" -output "$out"
  rm -f "${slices[@]}"
}

rm -rf "$APP"
TMP="$OUT/tmp"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources" "$APPEX/Contents/MacOS" "$APPEX/Contents/Resources" "$TMP"
INTENT_FLAGS=(-wmo -Xfrontend -const-gather-protocols-file -Xfrontend Support/appintents-protocols.json)

# Metadados de App Intents (o que o Xcode faz em "Extract App Intents Metadata"):
# sem isto os botões dos widgets, os controles e as ações do app Atalhos não aparecem.
# intents_metadata <módulo> <binário> <pasta Resources> <fontes…>
intents_metadata() {
  local module=$1 binary=$2 resources=$3; shift 3
  ls "$@" | sed "s|^|$PWD/|" > "$TMP/$module-sources.txt"
  echo "$TMP/$module.swiftconstvalues" > "$TMP/$module-consts.txt"
  xcrun appintentsmetadataprocessor --output "$resources" \
    --toolchain-dir "$(dirname "$(dirname "$(dirname "$(xcrun --find swiftc)")")")" \
    --module-name "$module" --sdk-root "$SDK" \
    --xcode-version "$(xcodebuild -version | awk '/Build version/{print $3}')" \
    --platform-family macOS --deployment-target 14.0 --target-triple "${ARCHS[0]}-apple-macos14.0" \
    --source-file-list "$TMP/$module-sources.txt" --swift-const-vals-list "$TMP/$module-consts.txt" \
    --binary-file "$binary" --compile-time-extraction --deployment-aware-processing \
    2>&1 | grep -i -E "error|warning" || true
  test -f "$resources/Metadata.appintents/extract.actionsdata" || { echo "✗ metadados de $module não gerados"; exit 1; }
}

APP_SOURCES=(Shared/*.swift App/*.swift App/UI/*.swift)
echo "▸ app (${ARCHS[*]})"
compile "$APP/Contents/MacOS/SharkBar" -module-name SharkBar "${INTENT_FLAGS[@]}" \
  -emit-const-values-path "$TMP/SharkBar.swiftconstvalues" -- "${APP_SOURCES[@]}"
cp Support/App-Info.plist "$APP/Contents/Info.plist"
cp Support/AppIcon.icns "$APP/Contents/Resources/"
intents_metadata SharkBar "$APP/Contents/MacOS/SharkBar" "$APP/Contents/Resources" "${APP_SOURCES[@]}"

WIDGET_SOURCES=(Shared/*.swift Widget/*.swift)
echo "▸ widgets + controles"
compile "$APPEX/Contents/MacOS/SharkBarWidget" -application-extension -module-name SharkBarWidget "${INTENT_FLAGS[@]}" \
  -emit-const-values-path "$TMP/SharkBarWidget.swiftconstvalues" -- "${WIDGET_SOURCES[@]}"
cp Support/Widget-Info.plist "$APPEX/Contents/Info.plist"
intents_metadata SharkBarWidget "$APPEX/Contents/MacOS/SharkBarWidget" "$APPEX/Contents/Resources" "${WIDGET_SOURCES[@]}"

echo "▸ assinatura ($SIGN_ID)"
codesign --force --options runtime --sign "$SIGN_ID" --entitlements Support/Widget.entitlements "$APPEX"
codesign --force --options runtime --sign "$SIGN_ID" --entitlements Support/App.entitlements "$APP"

if [[ "${RELEASE:-0}" == 1 ]]; then
  echo "▸ empacotando build/SharkBar.zip"
  rm -f "$OUT/SharkBar.zip"
  ditto -c -k --keepParent "$APP" "$OUT/SharkBar.zip"
fi

if [[ "${INSTALL:-1}" == 1 ]]; then
  echo "▸ instalando em ~/Applications"
  pkill -x SharkBar 2>/dev/null || true
  # versão antiga, quando o app se chamava "Fone"
  if [[ -d ~/Applications/Fone.app ]]; then pkill -x Fone 2>/dev/null || true; rm -rf ~/Applications/Fone.app; fi
  mkdir -p ~/Applications
  rm -rf ~/Applications/SharkBar.app
  cp -R "$APP" ~/Applications/
  touch ~/Applications/SharkBar.app   # força o Finder/Dock a recarregar o ícone
  pluginkit -a ~/Applications/SharkBar.app/Contents/PlugIns/SharkBarWidget.appex 2>/dev/null || true
  open ~/Applications/SharkBar.app
fi
echo "✓ pronto"
