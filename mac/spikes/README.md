# S1 시험 자료 — S1c가 읽는 곳

S1c는 이 폴더와 진단 기록만 읽고 `mac/design/SPIKES.md`(D1~D8)를 쓴다.

| 자료 | 위치 | 누가 |
|---|---|---|
| 선생님 확인 결과 | [checklist.md](checklist.md)의 "결과:" 줄 | 선생님 (집 실습) |
| 진단 기록 | `~/Library/Logs/Focus & Draw/diag.log` (5MB 넘으면 `diag.1.log`) | 앱이 자동으로 |
| 속도 측정 | [bench-2026-09-28.txt](bench-2026-09-28.txt) (원자료), 아래 해석 | Claude (S1b) |

## 속도 측정 해석 (M4 맥북 프로 14형, macOS 15.7.3)

`FocusDraw --bench <파일>`로 다시 잴 수 있다(약 40초, 화면에 창을 띄우지 않음). 창이 화면에 합성되는 시간은 빠져 있으므로 실제는 조금 더 걸린다.

| 무엇 | 3024×1964 | 5120×2880 | D4 기준 (stages.md) |
|---|---|---|---|
| 긋는 중 p95 — 지금 방식, 밑줄 왕복 | 9.8ms | 9.8ms | ≤ 8ms → **넘음** |
| 긋는 중 p95 — 지금 방식, 넓게 칠하기 | 14.1ms | **31.3ms** | ≤ 8ms → **넘음** |
| 긋는 중 p95 — 획 전용 그림 방식 | 0.05ms | 0.07ms | 통과 |
| 손 뗄 때 확정 (3,000점 50% 획) | 13ms | 30ms | (한 번, 1~2 프레임) |
| 실행 취소 재구성 500 / 2,000 / 5,000개 | 70 / 247 / 669ms | 74 / 274 / 707ms | 2,000개 ≤ 50ms → **넘음** |
| 쉬는 동안 깨어남 (처음 / 레이저 쓴 뒤) | 0.38 / 0.19 회/초, CPU < 1ms/10초 | | "쉬는 동안 0" 지킴 |

- **긋는 중**: 지금 방식은 반투명 획이면 지나온 자리 전체를 매번 다시 그려서 획이 넓을수록 느려진다. "획 전용 그림"(긋는 획을 불투명하게 따로 쌓고 새 토막 자리만 50%로 합침)은 획 크기와 상관없이 0.1ms 아래. 측정은 같은 메모리를 가리키는 CGImage로 했으므로 실제 구현(IOSurface·CALayer 등)에서 다시 확인해야 한다.
- **실행 취소**: 해상도보다 **항목 수**에 비례한다(개당 약 0.13ms). 실행 취소는 30단계까지인데 목록은 "전부 지우기" 전까지 계속 쌓이므로, 긴 수업에서 느려진다. 30단계보다 오래된 것을 바닥 그림에 구우면 30개만 다시 그리면 된다(architecture.md 방향과 같음).
- **메모리**: 측정값(5K 캐시+그림 두 장 = 56MB)은 실제로 건드린 페이지만 센다. 최악은 5K 화면 하나에 캐시 56MB + 내보낸 그림 56MB + 창 버퍼 약 56MB.
- **결론 후보(S1c가 정함)**: CoreGraphics는 유지하고 "획 전용 그림 + 오래된 것 굽기" 두 가지만 고치면 D4 기준을 넘을 것으로 보인다. CALayer 교체는 필요 없어 보임.

## 진단 기록 읽는 법

한 줄 = `날짜 시각 꼬리표 내용`. 선생님이 메뉴에서 항목을 고를 때마다 `MARK 항목 N — …`이 찍히므로, MARK 사이를 한 항목으로 본다.

| 알고 싶은 것 | 볼 줄 |
|---|---|
| D1 판이 화면에 떴나 | `SAMPLE … ink=[#번호 on=1 L=1000 vis=1 space=1 (x,y,w,h)] inkOnscreenList=1 above=[…]` — `on=0`·`vis=0`·`inkOnscreenList=0`이면 안 보임. `above`에 다른 앱이 레벨 1000 이상으로 있으면 그 앱이 덮은 것 |
| D2 키가 어디로 갔나 | `KEY hk down code=…`(C안 단축키), `KEY view down …`(A·B안 판), `FRONT 번들ID`, `APP active/resign`, `DRAW 0.3s after on: active=… key=…`, `SPACE changed` |
| D2 단축키가 풀렸나 | `HK drawkeys off removed=47 errors=0 left=4` (left=4는 F8·F9·⌃⌥1·⌃⌥2), `DRAW off … left=0`. `HK STRAY`가 있으면 풀리지 않았던 것 |
| D2 + 길게 누르기 | `KEY repeat=system` 또는 `repeat=self` (시스템이 반복을 보내 주는지) |
| D2 한글·암호 칸 | `KEY inputSource=…Korean…`, `KEY secureInput=true` |
| D3·D5 커서 | `CURSOR SetsCursorInBackground err=0`, `CURSOR hide/show`, SAMPLE의 `cgCursorVisible`, `moves=`(1초 동안 판이 받은 마우스 이동 수 — C안에서 0이면 비활성 판이 이동을 못 받는 것) |
| D6 모니터 | `SCREEN changed`, `SCREEN #n … mirrorSet=… mirrors=…` |
| D7 단축키·잠자기 | `HK reg … status=`(0이 성공), `HK press F8`, `POWER willSleep/didWake/sessionActive` |

키는 키 자리 번호만 남는다(예: 18=1, 6=Z, 24==/+, 51=delete, 53=Esc). 창 제목·입력한 글자는 남기지 않는다.
