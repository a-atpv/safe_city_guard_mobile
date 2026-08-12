#!/usr/bin/env bash
#
# Релизная сборка приложения охранника.
#
# Зачем скрипт: ключ подложки 2ГИС попадает в приложение только через
# --dart-define, и собранная без него сборка выглядит точно так же — до дня,
# когда 2ГИС перестаёт отдавать бесплатные тайлы и карта у охранника становится
# серым прямоугольником. Ровно это и уехало в TestFlight. Поэтому ключи лежат в
# dart_defines.json (gitignored), а скрипт отказывается собирать релиз без них.
#
#   ./scripts/build_release.sh ipa      # iOS → build/ios/ipa (TestFlight/App Store)
#   ./scripts/build_release.sh apk      # Android APK
#   ./scripts/build_release.sh appbundle
#   ./scripts/build_release.sh config   # только записать ключи в Generated.xcconfig,
#                                       # если архив делается из Xcode
#
# Всё, что идёт после цели, уезжает в flutter build как есть:
#
#   ./scripts/build_release.sh appbundle --build-number=123
#   ./scripts/build_release.sh ios --no-codesign --build-number=123
#
# Этим пользуется CI (.github/workflows/release.yml) — чтобы релизная сборка
# и на раннере шла через ту же проверку ключей, а не в обход неё.
#
set -euo pipefail

cd "$(dirname "$0")/.."

TARGET="${1:-ipa}"
if [[ $# -gt 0 ]]; then
  shift
fi
EXTRA="$*"
DEFINES_FILE="dart_defines.json"

if [[ ! -f "$DEFINES_FILE" ]]; then
  echo "✗ Нет $DEFINES_FILE — скопируйте dart_defines.example.json и впишите ключи." >&2
  exit 1
fi

# Ключ подложки обязателен: без него сборка молча уходит на неоплаченные тайлы.
if ! grep -q '"SAFECITY_DGIS_TILES_KEY"[[:space:]]*:[[:space:]]*"[^"]\+"' "$DEFINES_FILE"; then
  echo "✗ В $DEFINES_FILE не задан SAFECITY_DGIS_TILES_KEY (ключ Raster Tiles API 2ГИС)." >&2
  echo "  Без него подложка не покрыта подпиской и в любой момент может перестать грузиться." >&2
  exit 1
fi

echo "→ flutter build $TARGET --release --dart-define-from-file=$DEFINES_FILE $EXTRA"

case "$TARGET" in
  config)
    # Xcode-архив читает ключи из ios/Flutter/Generated.xcconfig, который
    # пишет вот этот вызов. Запускать перед каждым Product → Archive.
    flutter build ios --config-only --release --dart-define-from-file="$DEFINES_FILE" $EXTRA
    echo "✓ Ключи записаны в ios/Flutter/Generated.xcconfig — можно архивировать из Xcode."
    ;;
  ipa | apk | appbundle | ios)
    flutter build "$TARGET" --release --dart-define-from-file="$DEFINES_FILE" $EXTRA
    ;;
  *)
    echo "✗ Неизвестная цель: $TARGET (ipa | apk | appbundle | ios | config)" >&2
    exit 1
    ;;
esac

echo "✓ Готово. Подложка собрана с ключом 2ГИС."
