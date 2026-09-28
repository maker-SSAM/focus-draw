#!/bin/bash
# 맥용 Focus & Draw를 만든다: build/Focus & Draw.app (과 배포용 zip)
# Xcode 없이 명령줄 도구(xcode-select --install)만 있으면 된다.
#   build.sh            개발용: 애플 실리콘+인텔, "실험" 메뉴 포함, zip
#   build.sh --quick    고치는 동안: 이 맥의 칩만, 실험 메뉴 포함, zip 없음
#   build.sh --test     --quick으로 만든 뒤 자체 점검을 돌려 한 줄로 알려 준다 (커밋 전 한 번)
#   build.sh --release  배포용: 애플 실리콘+인텔, 실험 메뉴 없음, zip + SHA-256
set -euo pipefail
cd "$(dirname "$0")"
ROOT=".."
MODE="${1:-dev}"
case "$MODE" in dev|--quick|--test|--release) ;; *) echo "모르는 옵션: $MODE"; exit 2 ;; esac
VERSION=$(/usr/libexec/PlistBuddy -c "Print CFBundleShortVersionString" Info.plist)
# OneDrive·iCloud 폴더 안에서는 파일마다 꼬리표(확장 속성)가 붙어 서명이 거부되므로,
# 임시 폴더에서 조립·서명한 뒤 결과만 build/로 옮겨 온다.
STAGE=$(mktemp -d)
trap 'rm -rf "$STAGE"' EXIT
APP="$STAGE/Focus & Draw.app"
ZIP="Focus-Draw-mac-$VERSION.zip"

ARCHS="arm64 x86_64"
FLAGS=(-D EXPERIMENTS)
case "$MODE" in
  --quick|--test) ARCHS=$(uname -m) ;;
  --release) FLAGS=() ;;
esac

rm -rf build
mkdir -p build "$APP/Contents/MacOS" "$APP/Contents/Resources"

# 애플 실리콘(M1~)과 인텔 맥 둘 다에서 돌도록 두 번 만들어 하나로 합친다
BINS=()
for arch in $ARCHS; do
  swiftc -O -swift-version 5 -target "$arch-apple-macos13.0" ${FLAGS[@]+"${FLAGS[@]}"} Sources/*.swift -o "$STAGE/FocusDraw-$arch"
  BINS+=("$STAGE/FocusDraw-$arch")
done
lipo -create -output "$APP/Contents/MacOS/FocusDraw" "${BINS[@]}"

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
ditto "$APP" "build/Focus & Draw.app"

if [ "$MODE" = dev ] || [ "$MODE" = --release ]; then
  ditto -c -k --keepParent "$APP" "$STAGE/$ZIP"
  cp "$STAGE/$ZIP" build/
  echo "완료: build/Focus & Draw.app"
  echo "배포용: build/$ZIP"
  if [ "$MODE" = --release ]; then
    (cd build && shasum -a 256 "$ZIP" | tee "$ZIP.sha256")
  fi
elif [ "$MODE" = --quick ]; then
  echo "완료: build/Focus & Draw.app ($ARCHS, 실험 메뉴 포함)"
fi

# 자체 점검: 가짜 입력으로 한 바퀴 돌고 log.txt의 OK/FAIL 줄을 센다. 60초 넘게 걸리면 멈춘 것으로 본다.
if [ "$MODE" = --test ]; then
  OUT="$STAGE/selftest"
  mkdir -p "$OUT"
  "build/Focus & Draw.app/Contents/MacOS/FocusDraw" --selftest "$OUT" >/dev/null 2>&1 &
  PID=$!
  for _ in $(seq 1 120); do kill -0 $PID 2>/dev/null || break; sleep 0.5; done
  if kill -0 $PID 2>/dev/null; then kill $PID; echo "자체 점검 실패: 60초 안에 끝나지 않음"; exit 1; fi
  if [ ! -f "$OUT/log.txt" ]; then echo "자체 점검 실패: 앱이 기록을 남기지 못하고 끝남 (죽었을 수 있음)"; exit 1; fi
  PASS=$(grep -c '^OK ' "$OUT/log.txt" || true)
  FAIL=$(grep -c '^FAIL ' "$OUT/log.txt" || true)
  if [ "$FAIL" -gt 0 ] || ! grep -q '^DONE' "$OUT/log.txt"; then
    echo "자체 점검 실패: 통과 $PASS, 실패 $FAIL"
    grep '^FAIL ' "$OUT/log.txt" || echo "(끝 표시 DONE이 없음 — 도중에 멈춤)"
    mkdir -p build/selftest && cp "$OUT"/* build/selftest/
    echo "기록: build/selftest/"
    exit 1
  fi
  mkdir -p build/selftest && cp "$OUT"/* build/selftest/
  echo "자체 점검 통과: $PASS개 (기록·그림: build/selftest/)"
fi
