#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
KOKORO_PATH="${JARVIS_KOKORO_DIR:-$HOME/Library/Application Support/Jarvis/Kokoro}"
JARVIS_PYTHON="${JARVIS_PYTHON:-python3.13}"
mkdir -p "$KOKORO_PATH"
"$JARVIS_PYTHON" -m venv "$KOKORO_PATH/venv"
"$KOKORO_PATH/venv/bin/python" -m pip install --disable-pip-version-check 'kokoro-onnx==0.6.1' 'soundfile==0.13.1'
for filename in kokoro-v1.0.onnx voices-v1.0.bin; do
    if [[ ! -s "$KOKORO_PATH/$filename" ]]; then
        /usr/bin/curl --fail --location --retry 3 --connect-timeout 20 --max-time 900 \
          "https://github.com/thewh1teagle/kokoro-onnx/releases/download/model-files-v1.1/$filename" \
          -o "$KOKORO_PATH/$filename.partial"
        mv "$KOKORO_PATH/$filename.partial" "$KOKORO_PATH/$filename"
    fi
done
printf '\nKokoro установлен: %s\n' "$KOKORO_PATH"
