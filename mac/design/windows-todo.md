# Windows 세션이 이어받을 목록

맥 세션은 Windows 파일(`focus-draw.ahk` 등)을 고치지 않는다. 맥에서 먼저 한 것 중 Windows도 같게 해야 할 것을 여기에 한 줄씩 쌓는다.
Windows 세션 첫마디 예: "mac/design/windows-todo.md를 읽고 ○○ 줄을 Windows 판에 맞춰 줘." 끝나면 상태를 "완료"로 고친다.
시작하기 전에 OneDrive 동기화(초록 체크)와 `git pull`을 확인한다. 두 PC에서 동시에 작업하지 않는다.

| 항목 | 맥에서 한 것 | Windows가 할 것 | 설정 파일 이름·기본값 | 확인 방법 | 상태 |
|---|---|---|---|---|---|
| 단축키 그림 | 실제 맥북 배열, 기능 묶음 색 테두리·범례·카드, 숫자·칠판 키 위 색 막대가 설정 색을 따라감 | 색 막대를 설정값으로 칠하기([windows-shortcut-guide-idea.md](windows-shortcut-guide-idea.md)) | — | 설정에서 색을 바꾸고 안내를 다시 열어 키 위 색 확인 | 대기 |
| 레이저 모양 | 번짐을 계단 없는 9단계 빛으로(`LASER_GLOW_LAYERS`: 굵기 배율 3.0→1.0, 진하기 0.045+0.10·u², 그 위에 본체 0.75·1.0과 흰 심 0.3·0.9·흰빛 0.6), 점 사이를 Catmull-Rom 곡선으로 약 5pt 간격으로 채워 빨리 그어도 이어짐, 획을 점마다 굵기가 다른 한 줄 띠로 채움(겹쳐도 진해지지 않음), 굵기는 남은 수명을 smoothstep한 값(줄기 시작할 때 꺾이지 않게), 레이저 커서도 같은 빛. 머묾·사라짐 시간은 그대로 | 같은 모양으로 맞추기. 맥 코드 위치: `mac/Sources/Render/Renderer.swift`(`renderLaser`·`smoothLaser`·`LASER_GLOW_LAYERS`), `mac/Sources/UI/BrushCursor.swift`(`laserCursorImage`). 맥은 옛 `LASER_LAYERS`(Windows와 같은 값)를 점검용으로만 남겨 둠 | — | [images/laser-before.png](images/laser-before.png)와 [images/laser-after.png](images/laser-after.png) 비교(굵기 최대·빨리 긋기·위로 긋고 빨리 내리기 포함) | 대기 |
| 무지개 레이저·무지개 점·도형 무지개 | (묶음 A-2·3) | S 다음 A면 무지개 레이저, 숫자키로 풀림, 무지개펜 점 그라데이션 | — | 위 규칙대로 | 대기 |
| 레이저 옵션 3가지 | (묶음 B-4) | 같은 이름으로 설정 항목 추가 | `LaserHold`·`LaserFade`·`LaserGlow` 제안, 기본은 지금 값 | 값을 바꿔 레이저 확인 | 대기 |
| 숫자키별 두께 | (묶음 B-5, 나중에) | `[DrawKeys] Step1~9` | 없으면 현재 두께 유지 | 숫자키로 두께 변화 | 대기 |
| 단축키 그림 옵션 창 | (묶음 C, 나중에) | 키 클릭 영역·옵션 창(어려움) | — | — | 보류 |
| 레이저 시작 시점 | 레이저는 누르는 순간이 아니라 **첫 이동 때** 시작(시작점도 그 시각으로 기록), 클릭만 하면 아무것도 남지 않음. 이유: 맥북은 누른 뒤 움직이기까지 시간이 걸려 누른 점이 먼저 늙어 있으면 줄어드는 속도가 이어 그은 선과 달라 보임(선생님이 원인을 찾음) | Windows도 같게 (`ahk`의 레이저 시작 부분) | — | 클릭만 → 레이저 없음 / 클릭 후 천천히 시작해도 시작점이 먼저 줄지 않음 | 대기 |
