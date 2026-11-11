#!/bin/bash
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$root"

if ! xcode-select -p >/dev/null 2>&1; then
    echo 'Установите инструменты Apple командой xcode-select --install и повторите сборку.' >&2
    exit 1
fi

build="$root/.build"
stage="$build/staging"
app="$stage/Snezhno.app"
iconset="$stage/Snezhno.iconset"
destination="$root/dist"
target="${1:---native}"
case "$target" in
    --native) architectures=("$(uname -m)") ;;
    --universal) architectures=(arm64 x86_64) ;;
    *) echo 'Использование: bash scripts/build.sh [--native | --universal]' >&2; exit 2 ;;
esac

mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources" "$iconset" "$destination"
sdk="$(xcrun --sdk macosx --show-sdk-path)"
sources=("$root"/Sources/*.swift)

for architecture in "${architectures[@]}"; do
    xcrun --sdk macosx swiftc -swift-version 5 -O -whole-module-optimization -sdk "$sdk" \
        -module-cache-path "$build/modules" -target "$architecture-apple-macosx13.0" \
        -module-name Snezhno "${sources[@]}" -o "$stage/Snezhno-$architecture"
done

if [[ "$target" == "--universal" ]]; then
    xcrun lipo -create "$stage/Snezhno-arm64" "$stage/Snezhno-x86_64" -output "$app/Contents/MacOS/Snezhno"
else
    cp "$stage/Snezhno-${architectures[0]}" "$app/Contents/MacOS/Snezhno"
fi

xcrun --sdk macosx swiftc -module-cache-path "$build/modules" \
    "$root/scripts/icon.swift" -o "$stage/draw-icon"
"$stage/draw-icon" "$stage/icon.png"
for points in 16 32 128 256 512; do
    sips -z "$points" "$points" "$stage/icon.png" --out "$iconset/icon_${points}x${points}.png" >/dev/null
    pixels=$((points * 2))
    sips -z "$pixels" "$pixels" "$stage/icon.png" --out "$iconset/icon_${points}x${points}@2x.png" >/dev/null
done
iconutil -c icns "$iconset" -o "$app/Contents/Resources/Snezhno.icns"
cp "$root/Resources/Info.plist" "$app/Contents/Info.plist"
codesign --force --sign - "$app"
codesign --verify --strict "$app"

rm -rf "$destination/Snezhno.app"
mv "$app" "$destination/Snezhno.app"
printf '%s\n' "$destination/Snezhno.app"
