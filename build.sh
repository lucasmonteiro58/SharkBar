#!/bin/bash
# Compila SharkBar.app (barra de menu + janela) com widgets/controles e instala em ~/Applications.
#
#   ./build.sh                         compila para este Mac, instala em /Applications e abre
#   INSTALL=0 ./build.sh               só compila (em build/)
#   RELEASE=1 ./build.sh               binário universal (Apple Silicon + Intel) e instalador build/SharkBar.dmg
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

# Chaves que o Xcode sempre põe no Info.plist; sem elas o sistema pode ignorar
# a extensão de widget (galeria de widgets e Central de Controle).
xcode_keys() {
  local plist=$1
  local sdkver; sdkver=$(xcrun --sdk macosx --show-sdk-version)
  local sdkbuild; sdkbuild=$(xcrun --sdk macosx --show-sdk-build-version)
  local xv; xv=$(xcodebuild -version | awk '/^Xcode/{split($2,a,"."); printf "%d%d%d", a[1], a[2], (a[3]==""?0:a[3])}')
  local xb; xb=$(xcodebuild -version | awk '/Build version/{print $3}')
  /usr/libexec/PlistBuddy -c "Delete :CFBundleSupportedPlatforms" "$plist" 2>/dev/null || true
  /usr/libexec/PlistBuddy \
    -c "Add :CFBundleSupportedPlatforms array" -c "Add :CFBundleSupportedPlatforms:0 string MacOSX" \
    -c "Add :CFBundleInfoDictionaryVersion string 6.0" -c "Add :CFBundleDevelopmentRegion string pt-BR" \
    -c "Add :DTPlatformName string macosx" -c "Add :DTPlatformVersion string $sdkver" \
    -c "Add :DTSDKName string macosx$sdkver" -c "Add :DTSDKBuild string $sdkbuild" -c "Add :DTPlatformBuild string $sdkbuild" \
    -c "Add :DTXcode string $xv" -c "Add :DTXcodeBuild string $xb" \
    -c "Add :DTCompiler string com.apple.compilers.llvm.clang.1_0" \
    -c "Add :BuildMachineOSBuild string $(sw_vers -buildVersion)" "$plist" 2>/dev/null || true
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
xcode_keys "$APP/Contents/Info.plist"
cp Support/AppIcon.icns "$APP/Contents/Resources/"
intents_metadata SharkBar "$APP/Contents/MacOS/SharkBar" "$APP/Contents/Resources" "${APP_SOURCES[@]}"

WIDGET_SOURCES=(Shared/*.swift Widget/*.swift)
echo "▸ widgets + controles"
# Ponto de entrada = NSExtensionMain (como o Xcode faz em extensões): ele prepara o ambiente
# da extensão e depois chama o @main do WidgetKit. Com o `main` do Swift direto, o widget
# trava ao abrir (ExtensionMain.launchArguments vazio) e nunca aparece na galeria.
compile "$APPEX/Contents/MacOS/SharkBarWidget" -application-extension -module-name SharkBarWidget "${INTENT_FLAGS[@]}" \
  -Xlinker -e -Xlinker _NSExtensionMain \
  -emit-const-values-path "$TMP/SharkBarWidget.swiftconstvalues" -- "${WIDGET_SOURCES[@]}"
cp Support/Widget-Info.plist "$APPEX/Contents/Info.plist"
xcode_keys "$APPEX/Contents/Info.plist"
intents_metadata SharkBarWidget "$APPEX/Contents/MacOS/SharkBarWidget" "$APPEX/Contents/Resources" "${WIDGET_SOURCES[@]}"

echo "▸ assinatura ($SIGN_ID)"
codesign --force --options runtime --sign "$SIGN_ID" --entitlements Support/Widget.entitlements "$APPEX"
codesign --force --options runtime --sign "$SIGN_ID" --entitlements Support/App.entitlements "$APP"

if [[ "${RELEASE:-0}" == 1 ]]; then
  echo "▸ criando o instalador build/SharkBar.dmg"
  Support/DMG/make_dmg.sh "$APP" "$OUT/SharkBar.dmg"
fi

if [[ "${INSTALL:-1}" == 1 ]]; then
  DEST=/Applications
  echo "▸ instalando em $DEST"
  pkill -x SharkBar 2>/dev/null || true
  # versão antiga, quando o app se chamava "Fone"
  if [[ -d ~/Applications/Fone.app ]]; then pkill -x Fone 2>/dev/null || true; rm -rf ~/Applications/Fone.app; fi
  rm -rf ~/Applications/SharkBar.app   # cópias antigas em ~/Applications
  rm -rf "$DEST/SharkBar.app"
  cp -R "$APP" "$DEST/"
  touch "$DEST/SharkBar.app"   # força o Finder/Dock a recarregar o ícone
  /System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -f "$DEST/SharkBar.app"
  pluginkit -a "$DEST/SharkBar.app/Contents/PlugIns/SharkBarWidget.appex" 2>/dev/null || true
  open "$DEST/SharkBar.app"
fi
echo "✓ pronto"
