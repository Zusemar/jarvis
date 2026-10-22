#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
source scripts/compiler.sh
BUILD_PATH="$PWD/.build/native"
APP_PATH="$PWD/dist/Jarvis.app"
mkdir -p "$BUILD_PATH" "$APP_PATH/Contents/MacOS" "$APP_PATH/Contents/Helpers" "$APP_PATH/Contents/Resources"
TARGET_ARCH="$(uname -m)"
TARGET="$TARGET_ARCH-apple-macosx13.0"
"$JARVIS_COMPILER" "${JARVIS_COMPILER_ARGS[@]}" -O -target "$TARGET" \
  -parse-as-library -emit-module -emit-library -static -module-name JarvisCore \
  Sources/JarvisCore/*.swift -emit-module-path "$BUILD_PATH/JarvisCore.swiftmodule" \
  -o "$BUILD_PATH/libJarvisCore.a"
"$JARVIS_COMPILER" "${JARVIS_COMPILER_ARGS[@]}" -O -target "$TARGET" \
  -I "$BUILD_PATH" -L "$BUILD_PATH" -lJarvisCore Sources/Jarvis/*.swift \
  -o "$APP_PATH/Contents/MacOS/Jarvis"
cp packaging/Info.plist "$APP_PATH/Contents/Info.plist"
cp packaging/kokoro_worker.py "$APP_PATH/Contents/Resources/kokoro_worker.py"
"$JARVIS_COMPILER" "${JARVIS_COMPILER_ARGS[@]}" -O -target "$TARGET" \
  Sources/JarvisSupervisor/main.swift -o "$APP_PATH/Contents/Helpers/JarvisSupervisor"
codesign --force --sign - --identifier com.zusemar.jarvis.supervisor "$APP_PATH/Contents/Helpers/JarvisSupervisor"
# Local signature; distribution to other Macs needs Developer ID signing and notarization.
codesign --force --sign - "$APP_PATH"
printf '\nГотово: %s\nОткройте Jarvis.app и разрешите доступы macOS.\n' "$APP_PATH"
