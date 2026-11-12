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

echo "▸ widget"
compile "$APPEX/Contents/MacOS/FoneWidget" -application-extension -- Shared/*.swift Widget/*.swift
cp Support/Widget-Info.plist "$APPEX/Contents/Info.plist"

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
