#!/usr/bin/env bash
set -euo pipefail

FLUTTER_DIR="${HOME}/flutter"

if [ ! -d "${FLUTTER_DIR}" ]; then
  git clone https://github.com/flutter/flutter.git --depth 1 -b stable "${FLUTTER_DIR}"
fi

export PATH="${FLUTTER_DIR}/bin:${PATH}"

flutter config --enable-web
flutter pub get

: "${PARAGO_API_BASE_URL:?PARAGO_API_BASE_URL is required}"
PARAGO_ENABLE_REALTIME="${PARAGO_ENABLE_REALTIME:-false}"

flutter build web --release \
  --dart-define=PARAGO_API_BASE_URL="${PARAGO_API_BASE_URL}" \
  --dart-define=PARAGO_ENABLE_REALTIME="${PARAGO_ENABLE_REALTIME}"