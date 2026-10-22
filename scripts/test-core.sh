#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
source scripts/compiler.sh
BUILD_PATH="$PWD/.build/tests"
mkdir -p "$BUILD_PATH"
"$JARVIS_COMPILER" "${JARVIS_COMPILER_ARGS[@]}" -target "$(uname -m)-apple-macosx13.0" \
  -parse-as-library -emit-module -emit-library -static -module-name JarvisCore \
  Sources/JarvisCore/*.swift -emit-module-path "$BUILD_PATH/JarvisCore.swiftmodule" \
  -o "$BUILD_PATH/libJarvisCore.a"
"$JARVIS_COMPILER" "${JARVIS_COMPILER_ARGS[@]}" -target "$(uname -m)-apple-macosx13.0" \
  -I "$BUILD_PATH" -L "$BUILD_PATH" -lJarvisCore \
  Tests/JarvisCoreTests/*.swift Tests/Assertions.swift Tests/Main.swift -o "$BUILD_PATH/JarvisTests"
"$BUILD_PATH/JarvisTests"
