#!/bin/sh
set -eu

ROOT="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
SOURCE_PNG="$ROOT/assets/brand/fknotes_logo_source.png"
TMP="$(mktemp -d "${TMPDIR:-/tmp}/fknotes-icons.XXXXXX")"
trap 'rm -rf "$TMP"' EXIT INT TERM

command -v sips >/dev/null 2>&1 || {
  echo "需要 macOS sips 才能生成平台尺寸" >&2
  exit 1
}

test -f "$SOURCE_PNG" || {
  echo "缺少品牌母版：$SOURCE_PNG" >&2
  exit 1
}

ICON_PNG="$TMP/fknotes_icon.png"
MARK_CROP_PNG="$TMP/fknotes_mark_crop.png"
MARK_PNG="$TMP/fknotes_mark.png"

# 启动器使用用户提供的完整方形画布。应用内与启动页版本裁掉外围留白，
# 让小尺寸下的小象和便签仍然清晰可辨。
sips -s format png -z 1024 1024 "$SOURCE_PNG" --out "$ICON_PNG" >/dev/null
sips -c 360 360 "$SOURCE_PNG" --out "$MARK_CROP_PNG" >/dev/null
sips -s format png -z 1024 1024 "$MARK_CROP_PNG" --out "$MARK_PNG" >/dev/null

resize() {
  size="$1"
  source="$2"
  destination="$3"
  sips -z "$size" "$size" "$source" --out "$destination" >/dev/null
}

cp "$ICON_PNG" "$ROOT/assets/brand/fknotes_icon.png"
cp "$MARK_PNG" "$ROOT/assets/brand/fknotes_mark.png"

resize 432 "$ICON_PNG" \
  "$ROOT/android/app/src/main/res/drawable-nodpi/ic_launcher_foreground_image.png"
resize 240 "$MARK_PNG" \
  "$ROOT/android/app/src/main/res/drawable-nodpi/splash_mark.png"

resize 48  "$ICON_PNG" "$ROOT/android/app/src/main/res/mipmap-mdpi/ic_launcher.png"
resize 72  "$ICON_PNG" "$ROOT/android/app/src/main/res/mipmap-hdpi/ic_launcher.png"
resize 96  "$ICON_PNG" "$ROOT/android/app/src/main/res/mipmap-xhdpi/ic_launcher.png"
resize 144 "$ICON_PNG" "$ROOT/android/app/src/main/res/mipmap-xxhdpi/ic_launcher.png"
resize 192 "$ICON_PNG" "$ROOT/android/app/src/main/res/mipmap-xxxhdpi/ic_launcher.png"

IOS="$ROOT/ios/Runner/Assets.xcassets/AppIcon.appiconset"
resize 20   "$ICON_PNG" "$IOS/Icon-App-20x20@1x.png"
resize 40   "$ICON_PNG" "$IOS/Icon-App-20x20@2x.png"
resize 60   "$ICON_PNG" "$IOS/Icon-App-20x20@3x.png"
resize 29   "$ICON_PNG" "$IOS/Icon-App-29x29@1x.png"
resize 58   "$ICON_PNG" "$IOS/Icon-App-29x29@2x.png"
resize 87   "$ICON_PNG" "$IOS/Icon-App-29x29@3x.png"
resize 40   "$ICON_PNG" "$IOS/Icon-App-40x40@1x.png"
resize 80   "$ICON_PNG" "$IOS/Icon-App-40x40@2x.png"
resize 120  "$ICON_PNG" "$IOS/Icon-App-40x40@3x.png"
resize 120  "$ICON_PNG" "$IOS/Icon-App-60x60@2x.png"
resize 180  "$ICON_PNG" "$IOS/Icon-App-60x60@3x.png"
resize 76   "$ICON_PNG" "$IOS/Icon-App-76x76@1x.png"
resize 152  "$ICON_PNG" "$IOS/Icon-App-76x76@2x.png"
resize 167  "$ICON_PNG" "$IOS/Icon-App-83.5x83.5@2x.png"
resize 1024 "$ICON_PNG" "$IOS/Icon-App-1024x1024@1x.png"

LAUNCH="$ROOT/ios/Runner/Assets.xcassets/LaunchImage.imageset"
resize 88  "$MARK_PNG" "$LAUNCH/LaunchImage.png"
resize 176 "$MARK_PNG" "$LAUNCH/LaunchImage@2x.png"
resize 264 "$MARK_PNG" "$LAUNCH/LaunchImage@3x.png"

MAC="$ROOT/macos/Runner/Assets.xcassets/AppIcon.appiconset"
for size in 16 32 64 128 256 512 1024; do
  resize "$size" "$ICON_PNG" "$MAC/app_icon_$size.png"
done
cp "$ICON_PNG" "$MAC/fknotes_icon.svg.png"

resize 32  "$ICON_PNG" "$ROOT/web/favicon.png"
resize 192 "$ICON_PNG" "$ROOT/web/icons/Icon-192.png"
resize 512 "$ICON_PNG" "$ROOT/web/icons/Icon-512.png"
resize 192 "$ICON_PNG" "$ROOT/web/icons/Icon-maskable-192.png"
resize 512 "$ICON_PNG" "$ROOT/web/icons/Icon-maskable-512.png"

resize 256 "$ICON_PNG" "$TMP/windows-icon.png"
sips -s format ico "$TMP/windows-icon.png" \
  --out "$ROOT/windows/runner/resources/app_icon.ico" >/dev/null

echo "已从 assets/brand/fknotes_logo_source.png 生成全平台应用图标与启动标志"
