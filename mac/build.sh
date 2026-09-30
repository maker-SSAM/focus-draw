#!/bin/bash
# 맥용 Focus & Draw를 만든다: build/Focus & Draw.app (과 배포용 zip)
# Xcode 없이 명령줄 도구(xcode-select --install)만 있으면 된다.
#   build.sh            개발용: 애플 실리콘+인텔, "실험" 메뉴 포함, zip (Focus-Draw-<버전>[-test]-mac.zip, 0.x.x는 -test: 앱·맥용 읽어주세요·LICENSE)
#   build.sh --quick    고치는 동안: 이 맥의 칩만, 실험 메뉴 포함, zip 없음
#   build.sh --test     --quick으로 만든 뒤 그림 기준 점검(Tests/golden)과 자체 점검을 돌려 한 줄로 알려 준다 (커밋 전 한 번)
#                       FD_HEADLESS=1이면 화면이 필요한 자체 점검(--selftest)은 건너뛴다 (GitHub 자동 점검용)
#   build.sh --run      --quick으로 만든 뒤 켜져 있던 앱을 끄고 새 앱을 띄운다
#   build.sh --update-goldens  --quick으로 만든 뒤 기준 그림을 새로 저장한다 (선생님이 새 그림을 승인한 뒤에만)
#   build.sh --release  배포용: 애플 실리콘+인텔, 실험 메뉴 없음, zip + SHA-256
set -euo pipefail
cd "$(dirname "$0")"
ROOT=".."
MODE="${1:-dev}"
case "$MODE" in dev|--quick|--test|--run|--update-goldens|--release) ;; *) echo "모르는 옵션: $MODE"; exit 2 ;; esac
VERSION=$(/usr/libexec/PlistBuddy -c "Print CFBundleShortVersionString" Info.plist)
# OneDrive·iCloud 폴더 안에서는 파일마다 꼬리표(확장 속성)가 붙어 서명이 거부되므로,
# 임시 폴더에서 조립·서명한 뒤 결과만 build/로 옮겨 온다.
STAGE=$(mktemp -d)
trap 'rm -rf "$STAGE"' EXIT
APP="$STAGE/Focus & Draw.app"
# 1.0.0 전(0.x.x)은 시험 단계라 파일 이름에 test를 넣는다: Focus-Draw-0.2.0-test-mac.zip. 1.0.0부터는 test가 빠진다.
TAG=""
case "$VERSION" in 0.*) TAG="-test" ;; esac
ZIP="Focus-Draw-$VERSION$TAG-mac.zip"

ARCHS="arm64 x86_64"
FLAGS=(-D EXPERIMENTS)
case "$MODE" in
  --quick|--test|--run|--update-goldens) ARCHS=$(uname -m) ;;
  --release) FLAGS=() ;;
esac

# 빌드가 끝까지 성공했을 때만 build/의 앱을 바꾼다 (실패해도 지난 앱과 점검 기록이 남는다)
mkdir -p build "$APP/Contents/MacOS" "$APP/Contents/Resources"

# 애플 실리콘(M1~)과 인텔 맥 둘 다에서 돌도록 두 번 만들어 하나로 합친다
BINS=()
for arch in $ARCHS; do
  swiftc -O -swift-version 5 -target "$arch-apple-macos13.0" ${FLAGS[@]+"${FLAGS[@]}"} $(find Sources -name "*.swift" | sort) -o "$STAGE/FocusDraw-$arch"
  BINS+=("$STAGE/FocusDraw-$arch")
done
lipo -create -output "$APP/Contents/MacOS/FocusDraw" "${BINS[@]}"

cp Info.plist "$APP/Contents/"
for f in icon_spotlight_dark.png icon_draw_dark.png settings.png icon.png; do
  [ -f "$ROOT/$f" ] || { echo "빌드 실패: 그림 파일이 없음: $ROOT/$f"; exit 1; }
done
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
# 점검: 만들어진 .icns를 다시 풀어 16~512(@1x·@2x) 열 장이 모두 들어 있는지 (1024는 512@2x)
iconutil -c iconset "$APP/Contents/Resources/AppIcon.icns" -o "$STAGE/check.iconset"
[ "$(ls "$STAGE/check.iconset" | wc -l | tr -d ' ')" = 10 ] || { echo "빌드 실패: AppIcon.icns에 크기 10장이 다 들어 있지 않음"; exit 1; }
rm -rf "$STAGE/check.iconset"

# 개발자 인증서 없이 "자체 서명"만 한다. 받는 쪽에서 처음 한 번 "그래도 열기"가 필요하다.
xattr -cr "$APP"
codesign --force --deep --sign - "$APP"
codesign --verify --deep --strict "$APP"
rm -rf "build/Focus & Draw.app"
ditto "$APP" "build/Focus & Draw.app"

if [ "$MODE" = dev ] || [ "$MODE" = --release ]; then
  # 배포 폴더: 앱 + 맥용 읽어주세요 + LICENSE 만. 서명이 끝난 앱을 ditto로 묶는다(서명·확장 속성 보존).
  for f in "맥용 읽어주세요.txt" "$ROOT/LICENSE"; do
    [ -f "$f" ] || { echo "빌드 실패: 배포 파일이 없음: $f"; exit 1; }
  done
  PKGNAME="Focus-Draw-$VERSION$TAG-mac"
  mkdir -p "$STAGE/pkg/$PKGNAME"
  ditto "$APP" "$STAGE/pkg/$PKGNAME/Focus & Draw.app"
  cp "맥용 읽어주세요.txt" "$STAGE/pkg/$PKGNAME/"
  cp "$ROOT/LICENSE" "$STAGE/pkg/$PKGNAME/"
  ditto -c -k --norsrc --keepParent "$STAGE/pkg/$PKGNAME" "$STAGE/$ZIP"
  # 점검: 담긴 것이 앱·읽어주세요·LICENSE뿐인지(settings*.ini 없음), 풀어낸 앱의 서명이 살아 있는지
  LISTING=$(LC_ALL=en_US.UTF-8 unzip -Z1 "$STAGE/$ZIP")
  if echo "$LISTING" | grep -qi 'settings.*\.ini'; then echo "빌드 실패: zip에 settings*.ini가 들어 있음"; exit 1; fi
  if echo "$LISTING" | grep -v -e "^$PKGNAME/Focus & Draw.app/" -e "^$PKGNAME/[^/]*\.txt$" -e "^$PKGNAME/LICENSE$" -e "^$PKGNAME/$" | grep -q .; then
    echo "빌드 실패: zip에 예상 밖의 파일이 있음"; echo "$LISTING" | head -20; exit 1
  fi
  [ "$(echo "$LISTING" | grep -c "^$PKGNAME/[^/]*\.txt$")" = 1 ] || { echo "빌드 실패: zip에 읽어주세요 한 개가 있어야 함"; exit 1; }
  mkdir -p "$STAGE/unzipped"
  ditto -x -k "$STAGE/$ZIP" "$STAGE/unzipped"
  codesign --verify --deep --strict "$STAGE/unzipped/$PKGNAME/Focus & Draw.app"
  # 풀어낸 앱에 아이콘이 있고 Info.plist가 그것을 가리키는지
  UAPP="$STAGE/unzipped/$PKGNAME/Focus & Draw.app"
  [ -s "$UAPP/Contents/Resources/AppIcon.icns" ] || { echo "빌드 실패: zip 안의 앱에 AppIcon.icns가 없음"; exit 1; }
  [ "$(/usr/libexec/PlistBuddy -c "Print CFBundleIconFile" "$UAPP/Contents/Info.plist")" = AppIcon ] || { echo "빌드 실패: Info.plist의 CFBundleIconFile이 AppIcon이 아님"; exit 1; }
  rm -f build/Focus-Draw-*.zip build/Focus-Draw-*.zip.sha256
  cp "$STAGE/$ZIP" build/
  echo "완료: build/Focus & Draw.app"
  echo "배포용: build/$ZIP"
  if [ "$MODE" = --release ]; then
    (cd build && shasum -a 256 "$ZIP" | tee "$ZIP.sha256")
  fi
elif [ "$MODE" = --quick ]; then
  echo "완료: build/Focus & Draw.app ($ARCHS, 실험 메뉴 포함)"
fi

# 실행 중인 앱을 끄고 새 앱을 띄운다 (SMAppService는 개발 실행에서 부르지 않으므로 로그인 항목은 그대로다)
if [ "$MODE" = --run ]; then
  pkill -x FocusDraw 2>/dev/null && sleep 0.5 || true
  open -n "build/Focus & Draw.app"
  echo "실행함: build/Focus & Draw.app"
fi

# 그림 기준 점검: Tests/golden의 기준 그림과 견주고 글 점검(단언)을 돈다. 창이 필요 없다.
# 인자: 앱 경로, 결과 폴더, (선택) --update-goldens
run_golden() {
  "$1/Contents/MacOS/FocusDraw" --golden "$2" --goldens Tests/golden --ahk "$ROOT/focus-draw.ahk" --fixtures Tests/fixtures ${3:+"$3"}
}
if [ "$MODE" = --update-goldens ]; then
  run_golden "build/Focus & Draw.app" build/test-out --update-goldens
  echo "기준 그림을 Tests/golden에 저장함. 축소 모음: build/test-out/contact-sheet.png (선생님께 보이고 승인받은 뒤 커밋)"
fi

# 자체 점검: 가짜 입력으로 한 바퀴 돌고 log.txt의 OK/FAIL 줄을 센다. 60초 넘게 걸리면 멈춘 것으로 본다.
if [ "$MODE" = --test ]; then
  set +e
  GOLDEN_OUT=$(run_golden "build/Focus & Draw.app" build/test-out 2>&1)
  GOLDEN_RC=$?
  set -e
  if [ $GOLDEN_RC -ne 0 ]; then echo "$GOLDEN_OUT"; exit 1; fi

  # 인텔 조각은 Rosetta가 이미 깔려 있을 때만 (Rosetta 설치는 선생님 결정)
  INTEL="건너뜀"
  if [ -z "${FD_HEADLESS:-}" ] && [ "$(uname -m)" = arm64 ] && arch -x86_64 /usr/bin/true 2>/dev/null; then
    swiftc -O -swift-version 5 -target "x86_64-apple-macos13.0" -D EXPERIMENTS $(find Sources -name "*.swift" | sort) -o "$STAGE/FocusDraw-intel"
    IAPP="$STAGE/intel/Focus & Draw.app"
    mkdir -p "$STAGE/intel" && ditto "$APP" "$IAPP"
    cp "$STAGE/FocusDraw-intel" "$IAPP/Contents/MacOS/FocusDraw"
    codesign --force --deep --sign - "$IAPP"
    set +e
    IOUT=$(arch -x86_64 "$IAPP/Contents/MacOS/FocusDraw" --golden build/test-out-intel --goldens Tests/golden --ahk "$ROOT/focus-draw.ahk" --fixtures Tests/fixtures 2>&1)
    IRC=$?
    set -e
    if [ $IRC -ne 0 ]; then echo "인텔(Rosetta) 그림 점검 실패:"; echo "$IOUT"; exit 1; fi
    INTEL="통과"
  fi

  if [ -n "${FD_HEADLESS:-}" ]; then
    echo "$GOLDEN_OUT (자체 점검 --selftest는 화면이 없어 건너뜀)"
    exit 0
  fi

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
  echo "$GOLDEN_OUT · 자체 점검 통과: $PASS개 · 인텔(Rosetta) $INTEL (기록: build/test-out/, build/selftest/)"
fi
