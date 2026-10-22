#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"
bash scripts/build-app.sh
printf '\nНажмите Enter, чтобы закрыть окно сборки.'
read -r
