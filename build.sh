#!/bin/bash
# Compila Fone.app (menu bar + janela) com o widget embutido e instala em ~/Applications.
#
#   ./build.sh                         compila para este Mac, instala e abre
#   INSTALL=0 ./build.sh               só compila (em build/)
#   RELEASE=1 ./build.sh               binário universal (Apple Silicon + Intel) e build/Fone.zip
#   SIGN_ID="Apple Development: …" ./build.sh   assina com sua conta Apple (padrão: ad-hoc)
set -euo pipefail
cd "$(dirname "$0")"

SDK=$(xcrun --sdk macosx --show-sdk-path)
SIGN_ID="${SIGN_ID:--}"
OUT=build
APP="$OUT/Fone.app"
APPEX="$APP/Contents/PlugIns/FoneWidget.appex"
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
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources" "$APPEX/Contents/MacOS"

echo "▸ app (${ARCHS[*]})"
compile "$APP/Contents/MacOS/Fone" -- Shared/*.swift App/*.swift
cp Support/App-Info.plist "$APP/Contents/Info.plist"
cp Support/AppIcon.icns "$APP/Contents/Resources/"

echo "▸ widget + controles"
TMP="$OUT/tmp"; mkdir -p "$TMP" "$APPEX/Contents/Resources"
compile "$APPEX/Contents/MacOS/FoneWidget" -application-extension -wmo -module-name FoneWidget \
  -emit-const-values-path "$TMP/FoneWidget.swiftconstvalues" \
  -Xfrontend -const-gather-protocols-file -Xfrontend Support/appintents-protocols.json \
  -- Shared/*.swift Widget/*.swift
cp Support/Widget-Info.plist "$APPEX/Contents/Info.plist"

# Metadados de App Intents (o que o Xcode faz em "Extract App Intents Metadata"):
# sem isto os botões dos widgets e os controles da Central de Controle não funcionam.
echo "▸ metadados App Intents"
ls "$PWD"/Shared/*.swift "$PWD"/Widget/*.swift > "$TMP/sources.txt"
echo "$TMP/FoneWidget.swiftconstvalues" > "$TMP/consts.txt"
xcrun appintentsmetadataprocessor --output "$APPEX/Contents/Resources" \
  --toolchain-dir "$(dirname "$(dirname "$(dirname "$(xcrun --find swiftc)")")")" \
  --module-name FoneWidget --sdk-root "$SDK" \
  --xcode-version "$(xcodebuild -version | awk '/Build version/{print $3}')" \
  --platform-family macOS --deployment-target 14.0 --target-triple "${ARCHS[0]}-apple-macos14.0" \
  --source-file-list "$TMP/sources.txt" --swift-const-vals-list "$TMP/consts.txt" \
  --binary-file "$APPEX/Contents/MacOS/FoneWidget" --compile-time-extraction --deployment-aware-processing \
  2>&1 | grep -i -E "error|warning" || true
test -f "$APPEX/Contents/Resources/Metadata.appintents/extract.actionsdata" || { echo "✗ metadados não gerados"; exit 1; }

echo "▸ assinatura ($SIGN_ID)"
codesign --force --options runtime --sign "$SIGN_ID" --entitlements Support/Widget.entitlements "$APPEX"
codesign --force --options runtime --sign "$SIGN_ID" --entitlements Support/App.entitlements "$APP"

if [[ "${RELEASE:-0}" == 1 ]]; then
  echo "▸ empacotando build/Fone.zip"
  rm -f "$OUT/Fone.zip"
  ditto -c -k --keepParent "$APP" "$OUT/Fone.zip"
fi

if [[ "${INSTALL:-1}" == 1 ]]; then
  echo "▸ instalando em ~/Applications"
  pkill -x Fone 2>/dev/null || true
  mkdir -p ~/Applications
  rm -rf ~/Applications/Fone.app
  cp -R "$APP" ~/Applications/
  touch ~/Applications/Fone.app   # força o Finder/Dock a recarregar o ícone
  pluginkit -a ~/Applications/Fone.app/Contents/PlugIns/FoneWidget.appex 2>/dev/null || true
  open ~/Applications/Fone.app
fi
echo "✓ pronto"
