#!/bin/bash
# 맥용 Focus & Draw를 만든다: build/Focus & Draw.app 과 배포용 zip
# Xcode 없이 명령줄 도구(xcode-select --install)만 있으면 된다.
set -euo pipefail
cd "$(dirname "$0")"
ROOT=".."
VERSION=$(/usr/libexec/PlistBuddy -c "Print CFBundleShortVersionString" Info.plist)
# OneDrive·iCloud 폴더 안에서는 파일마다 꼬리표(확장 속성)가 붙어 서명이 거부되므로,
# 임시 폴더에서 조립·서명한 뒤 결과만 build/로 옮겨 온다.
STAGE=$(mktemp -d)
trap 'rm -rf "$STAGE"' EXIT
APP="$STAGE/Focus & Draw.app"
ZIP="Focus-Draw-mac-$VERSION.zip"

rm -rf build
mkdir -p build "$APP/Contents/MacOS" "$APP/Contents/Resources"

# 애플 실리콘(M1~)과 인텔 맥 둘 다에서 돌도록 두 번 만들어 하나로 합친다
for arch in arm64 x86_64; do
  swiftc -O -swift-version 5 -target "$arch-apple-macos13.0" Sources/*.swift -o "$STAGE/FocusDraw-$arch"
done
lipo -create -output "$APP/Contents/MacOS/FocusDraw" "$STAGE/FocusDraw-arm64" "$STAGE/FocusDraw-x86_64"

cp Info.plist "$APP/Contents/"
cp "$ROOT/icon_spotlight_dark.png" "$ROOT/icon_draw_dark.png" "$ROOT/settings.png" "$APP/Contents/Resources/"

# 앱 아이콘 (icon.png → AppIcon.icns)
ICONSET="$STAGE/AppIcon.iconset"
mkdir -p "$ICONSET"
for s in 16 32 128 256 512; do
  sips -z $s $s "$ROOT/icon.png" --out "$ICONSET/icon_${s}x${s}.png" >/dev/null
  sips -z $((s*2)) $((s*2)) "$ROOT/icon.png" --out "$ICONSET/icon_${s}x${s}@2x.png" >/dev/null
done
iconutil -c icns "$ICONSET" -o "$APP/Contents/Resources/AppIcon.icns"
rm -rf "$ICONSET"

# 개발자 인증서 없이 "자체 서명"만 한다. 받는 쪽에서 처음 한 번 "그래도 열기"가 필요하다.
xattr -cr "$APP"
codesign --force --deep --sign - "$APP"
codesign --verify --deep --strict "$APP"

ditto -c -k --keepParent "$APP" "$STAGE/$ZIP"
ditto "$APP" "build/Focus & Draw.app"
cp "$STAGE/$ZIP" build/
echo "완료: build/Focus & Draw.app"
echo "배포용: build/$ZIP"
