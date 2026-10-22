#!/usr/bin/env bash
# Build ClickKey.app (ad-hoc signed).
#   scripts/build.sh                 -> build/ClickKey.app
#   scripts/build.sh /Applications   -> also copy there (or set DEST=...)
#   ARCH=x86_64 scripts/build.sh     -> other arch; ARCH=universal for arm64+x86_64
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ARCH="${ARCH:-arm64}"
DEST="${1:-${DEST:-}}"

if [[ "$ARCH" == "universal" ]]; then
  ARCH_ARGS=(--arch arm64 --arch x86_64)
else
  ARCH_ARGS=(--arch "$ARCH")
fi

cd "$ROOT"
swift build -c release "${ARCH_ARGS[@]}"
BIN_DIR="$(swift build -c release "${ARCH_ARGS[@]}" --show-bin-path)"

APP="$ROOT/build/ClickKey.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN_DIR/ClickKey" "$APP/Contents/MacOS/ClickKey"
cp "$ROOT/Resources/Info.plist" "$APP/Contents/Info.plist"
printf 'APPL????' > "$APP/Contents/PkgInfo"

codesign --force --deep -s - "$APP"
echo "Built: $APP"

if [[ -n "$DEST" ]]; then
  mkdir -p "$DEST"
  rm -rf "$DEST/ClickKey.app"
  ditto "$APP" "$DEST/ClickKey.app"
  echo "Copied: $DEST/ClickKey.app"
fi
