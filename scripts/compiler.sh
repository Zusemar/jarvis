#!/bin/bash
# Sourced by the build and test scripts. Does not modify the installed toolchain.
JARVIS_COMPILER="$(xcrun --find swiftc)"
JARVIS_COMPILER_ARGS=(-sdk "$(xcrun --show-sdk-path)" -swift-version 5 -module-cache-path "$PWD/.build/compiler-cache")
JARVIS_INCLUDE="$(dirname "$(dirname "$JARVIS_COMPILER")")/include/swift"
# Some upgraded Command Line Tools retain both module maps for SwiftBridging.
# Hide only the stale duplicate from this compiler invocation using a VFS overlay.
if [[ -f "$JARVIS_INCLUDE/module.modulemap" && -f "$JARVIS_INCLUDE/bridging.modulemap" ]] && \
   /usr/bin/grep -q '^module SwiftBridging' "$JARVIS_INCLUDE/module.modulemap" && \
   /usr/bin/grep -q '^module SwiftBridging' "$JARVIS_INCLUDE/bridging.modulemap"; then
    mkdir -p .build/compiler
    : > .build/compiler/empty.modulemap
    json_escape() {
        local value="$1"
        value="${value//\\/\\\\}"
        value="${value//\"/\\\"}"
        value="${value//$'\n'/\\n}"
        value="${value//$'\r'/\\r}"
        value="${value//$'\t'/\\t}"
        printf '%s' "$value"
    }
    printf '{"version":0,"roots":[{"type":"file","name":"%s","external-contents":"%s"},{"type":"file","name":"%s","external-contents":"%s"}]}\n' \
      "$(json_escape "$JARVIS_INCLUDE/module.modulemap")" \
      "$(json_escape "$PWD/.build/compiler/empty.modulemap")" \
      "$(json_escape "$(dirname "$JARVIS_INCLUDE")/Swift/module.modulemap")" \
      "$(json_escape "$PWD/.build/compiler/empty.modulemap")" > .build/compiler/overlay.json
    JARVIS_COMPILER_ARGS+=(-vfsoverlay "$PWD/.build/compiler/overlay.json")
fi
