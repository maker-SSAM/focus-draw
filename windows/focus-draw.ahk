#Requires AutoHotkey v2.0
#SingleInstance Force

; ================= 컴파일(Ahk2Exe) 설정 =================
; 아래 줄들은 평범한 주석이라 .ahk로 그냥 실행할 때는 아무 영향이 없고, Ahk2Exe로 exe를
; 만들 때만 읽힌다. focus-draw.ico는 ..\shared\icon.png를 16~256px 여러 크기로 담아 변환한 파일이다
; (작업표시줄·바탕화면·파일 탐색기가 상황에 따라 다른 크기를 골라 쓰기 때문에 여러 크기가 필요).
; 컴파일된 exe는 이 아이콘을 파일 아이콘이자 트레이 아이콘으로 함께 사용한다.
;@Ahk2Exe-SetMainIcon focus-draw.ico
;@Ahk2Exe-SetName Focus & Draw
;@Ahk2Exe-SetDescription Focus & Draw - 마우스 강조 / 화면 드로잉
;@Ahk2Exe-SetVersion 1.0.0
;@Ahk2Exe-SetCopyright (c) 2026 maker_SSAM (MIT License)

Persistent()
SetWinDelay(-1)
CoordMode("Mouse", "Screen")

; Windows 기본 타이머 정밀도(약 15~16ms)를 그대로 쓰면 클릭 애니메이션 속도를 세밀하게
; 조절해도 특정 구간에서 뭉뚱그려져 갑자기 튀어 보인다. 1ms 단위로 더 정밀하게 요청한다.
DllCall("winmm\timeBeginPeriod", "uint", 1)
OnExit((*) => DllCall("winmm\timeEndPeriod", "uint", 1))

; 배포한 베타에서 피드백을 받을 때 "어느 빌드인지"를 구분할 수 있어야 해서 버전을 표시한다.
; 위 SetVersion 지시문(exe 파일 속성용)과 여기 값을 항상 같이 고쳐야 한다 — 지시문은 주석이라
; 프로그램 안에서 읽을 수 없어서, 아쉽지만 두 곳에 같은 숫자를 적어두는 수밖에 없다.
APP_VERSION := "1.0.0"

A_IconTip := "Focus & Draw v" APP_VERSION " - 마우스 강조 / 화면 드로잉"

; 컴파일된 exe는 위 SetMainIcon으로 넣은 아이콘을 트레이 아이콘으로도 그대로 쓰지만,
; .ahk 소스로 직접 실행할 때는 AutoHotkey 기본 아이콘(초록색 H)이 뜬다. 소스로 실행할 때도
; 같은 그림이 보이도록 같은 폴더의 ico 파일을 지정한다. (exe는 아이콘을 이미 품고 있어서
; 건드릴 필요가 없고, ico 파일을 exe에 또 넣으면 같은 그림이 두 번 들어가 크기만 커진다)
if !A_IsCompiled && FileExist(A_ScriptDir "\focus-draw.ico")
    TraySetIcon(A_ScriptDir "\focus-draw.ico")

SETTINGS_PATH := A_ScriptDir "\settings.ini"

; 컴파일된 exe에도 아이콘 파일이 그대로 들어가도록 FileInstall로 함께 담고, 실행 시 임시 폴더로 꺼내 쓴다.
; (위젯/트레이 아이콘 둘 다 이 경로를 쓰므로 다른 UI보다 먼저 준비해둔다)
; 아이콘 그림은 맥 판과 같이 쓰므로 저장소의 shared 폴더에 있다 (이 스크립트 기준 ..\shared).
FileInstall("..\shared\icon_spotlight.png", A_Temp "\tt_icon_spotlight.png", true)
FileInstall("..\shared\icon_draw.png", A_Temp "\tt_icon_draw.png", true)
FileInstall("..\shared\icon_spotlight_dark.png", A_Temp "\tt_icon_spotlight_dark.png", true)
FileInstall("..\shared\icon_draw_dark.png", A_Temp "\tt_icon_draw_dark.png", true)
FileInstall("..\shared\settings.png", A_Temp "\tt_icon_settings.png", true)
; 설정 창의 "드로잉 모드 단축키 보기" 버튼이 띄우는 안내 그림. 아이콘과 달리 화면에 그대로 보여주기만
; 하므로 색을 입히거나 하지 않는다. (그림을 바꾸려면 shortcuts.png만 갈아끼우면 된다)
FileInstall("shortcuts.png", A_Temp "\tt_shortcuts.png", true)
ICON_SPOT_PATH := A_Temp "\tt_icon_spotlight.png"
ICON_DRAW_PATH := A_Temp "\tt_icon_draw.png"
ICON_SPOT_DARK_PATH := A_Temp "\tt_icon_spotlight_dark.png"
ICON_DRAW_DARK_PATH := A_Temp "\tt_icon_draw_dark.png"
ICON_SETTINGS_PATH := A_Temp "\tt_icon_settings.png"
SHORTCUT_IMAGE_PATH := A_Temp "\tt_shortcuts.png"

; ================= GDI+ 초기화 (PNG 아이콘 불러오기/색 입히기용) =================
gdipStartupInput := Buffer(24, 0)
NumPut("UInt", 1, gdipStartupInput, 0) ; GdiplusVersion = 1
gdipToken := 0
DllCall("gdiplus\GdiplusStartup", "ptr*", &gdipToken, "ptr", gdipStartupInput, "ptr", 0)

; ================= 사용자가 바꿀 수 있는 전역 단축키 =================
; `^!h::` 같은 문법은 프로그램이 켜질 때 고정으로 박혀서 실행 중에 바꿀 수 없다. 설정 창에서
; 단축키를 바꾸려면 Hotkey() 함수로 등록/해제해야 해서, 동작과 기본값을 이름으로 묶어둔다.
; 지우기는 전역 단축키로 두지 않는다. 드로잉 모드가 꺼져 있으면 그린 내용이 화면에 보이지도
; 않아서 그때 지울 일이 없고, 드로잉 중에는 Delete와 Esc가 같은 일을 한다. 전역 단축키는
; 하나 등록할 때마다 그 키를 Windows 전체에서 빼앗으므로, 값어치가 낮은 것은 두지 않는 게 낫다.
HOTKEY_DEFAULTS := Map("Spotlight", "F8", "Draw", "F9")
HOTKEY_LABELS := Map("Spotlight", "강조", "Draw", "드로잉")
hotkeyCombos := Map()     ; 지금 설정된 조합 (settings.ini에서 불러옴)
hotkeyRegistered := Map() ; 실제로 등록에 성공해 살아있는 조합 (해제할 때 필요)
hotkeyApplying := false   ; 값을 되돌리느라 Change가 다시 불려 무한히 반복되는 것을 막는 빗장

; ##########################################################################
; ## 손으로 고쳐가며 시험해보는 숫자들                                    ##
; ##                                                                      ##
; ## 여기 값을 고치고 저장한 뒤 **Ctrl+Alt+R**을 누르면 그 자리에서 바로  ##
; ## 새 값으로 다시 시작한다(소스로 실행 중일 때만. 트레이 메뉴에도 같은  ##
; ## 항목이 있다). 프로그램을 껐다 켜거나 exe로 다시 컴파일할 필요 없다.  ##
; ##                                                                      ##
; ## 이 블록 말고 자주 만지게 되는 곳:                                    ##
; ##   DRAW_COLORS  — 숫자키 1~9의 색     (아래쪽 "상태값" 절)            ##
; ##   BOARD_KEYS   — 칠판 Q/W/E/R의 색   (아래쪽 "칠판" 절)              ##
; ##   STEP_BADGE_* — 단계 숫자 배지 크기·거리 (아래쪽 "단계 숫자" 절)    ##
; ##########################################################################

; ================= 굵기·지우개 크기의 "단계" =================
; 굵기와 지우개 크기는 쓰는 사람에게 1~10단계로만 보여준다. 픽셀 숫자는 의미를 짐작하기
; 어렵고(6이 굵은 건지 가는 건지 알 수 없다) 폭도 넓어서, 단계로 나누면 "3단계쯤" 하고
; 고르기 쉬워진다. 실제 그릴 때 쓰는 픽셀값은 여기서 환산한다.
; 단계가 하나 오를 때마다 **직전 단계의 일정 배율**만큼 커진다. 일정한 픽셀씩 더하면 가는
; 쪽에서는 차이가 너무 크고 굵은 쪽에서는 거의 티가 안 나는데, 비율로 키우면 어느 구간에서나
; "한 단계 굵어졌다"는 느낌이 고르게 난다. 펜과 지우개는 쓰임이 달라서 배율을 따로 둔다 —
; 지우개는 넓게 쓸 일이 많아 더 가파르게 커진다.
STEP_MAX := 10
PEN_BASE_PX := 3,   PEN_STEP_RATIO := 1.3    ; 3 · 3.9 · 5.1 · 6.6 · 8.6 · 11.1 · 14.5 · 18.8 · 24.5 · 31.8px
ERASER_BASE_PX := 10, ERASER_STEP_RATIO := 1.5 ; 10 · 15 · 23 · 34 · 51 · 76 · 114 · 171 · 256 · 384px
; 처음 받아 쓰는 PC(= settings.ini가 없을 때)가 시작하는 단계
DEFAULT_DRAW_STEP := 5   ; 8.6px
DEFAULT_ERASER_STEP := 5 ; 51px

; ================= 전자칠판에서 "넓게 닿으면 지우개" =================
; 칠판이 Windows에 펜 앞뒤를 알려주면 그 정보를 그대로 쓴다. 안 알려주는 칠판에서는
; **닿는 면적**으로 가른다 — 이 값보다 크게 닿으면 지우개로 친다.
;
; 경계는 실제로 1789번 찍어보고 정했다(학교 전자칠판, 2026-09-21). 긴 쪽 길이 기준으로
; 세 덩어리가 또렷하게 갈린다:
;   펜      1~5      (3x3이 240회로 최다)
;   손가락  6~38     (7x7·8x8·16x16·18x18 등, 세게 누르면 20대까지 간다)
;   손날    53~91    (67x64, 71x58 …)
; 손가락 최대 38과 손날 최소 53 사이가 비어 있으므로 그 한가운데인 **45**를 쓴다.
;
; 여기까지 오는 데 두 번 틀렸고, 둘 다 같은 실수였다 — **재보면 값이 다르다는 것과 실제로
; 안정적으로 갈린다는 것은 다르다.**
;   5로 뒀을 때: 펜 앞쪽(3~4)과 뒤쪽(6~7)을 가르려 했는데 여유가 없어 글씨를 쓰다 지우개가
;                튀어나왔다. 펜의 앞뒤 굵기 차이는 애초에 판정을 걸 만한 크기가 아니었다
;   15로 뒀을 때: 손가락이 16~23을 예사로 넘는 줄 몰랐다. 손가락이 닿는 순간 "손날"로
;                판단되어 지우개 획이 시작되고, 그 바람에 **두 손가락 제스처가 영영 안 걸렸다**
;                (아래 OnPointerDown에서 지우는 중에는 제스처를 막아두기 때문이다)
; 경계를 사이에 끼울 수 있는지가 아니라, 경계 **양쪽에 여유가 얼마나 있는지**를 봐야 한다.
;
; 그래서 지금 배치는 이렇다: **펜도 손가락도 전부 글씨, 손날로 문질러야 지우개.**
;
; **칠판마다 숫자가 다르다.** 같은 폴더의 `터치펜-확인.ahk`를 실행해 펜·손가락·손날로 각각
; 대보면 그 칠판의 값과 함께 **권하는 경계값**까지 알려준다.
; **0으로 두면 이 판정을 아예 끈다.** 접촉 크기를 상수로 박아 보내는 칠판이라면(= 무엇으로
; 닿아도 같은 값이 나온다면) 0으로 꺼두는 것이 맞다. 안 그러면 그 상수가 경계를 넘어
; 모든 획이 지우개가 되어버린다.
ERASER_CONTACT_PX := 45

; 손날로 지울 때 폭을 설정값의 몇 배로 할지. 손이 덮는 면적이 마우스 커서보다 훨씬 넓어서
; 같은 폭으로 지우면 답답하다. 자세한 이유는 EraserThickness() 위의 설명 참고.
; (펜 뒤쪽으로 지울 때는 펜만 한 크기이므로 이 배율을 쓰지 않는다)
HAND_ERASER_SCALE := 2.0

StepToPx(step, basePx, ratio) {
    global STEP_MAX
    step := Max(1, Min(STEP_MAX, step))
    return basePx * (ratio ** (step - 1))
}

; 펜은 소수점 한 자리까지 쓴다. 정수로 반올림하면 2단계(3.6)와 3단계(4.3)가 둘 다 4가 되어
; 서로 다른 단계인데 굵기가 같아진다. GDI+ 펜은 실수 굵기를 그대로 받으므로 그럴 이유가 없다.
PenPx(step) {
    global PEN_BASE_PX, PEN_STEP_RATIO
    return Round(StepToPx(step, PEN_BASE_PX, PEN_STEP_RATIO), 1)
}

; 지우개는 GDI 펜으로 지우므로 정수여야 한다 (10·12·14·17·21·25·30·36·43·52 — 겹치지 않는다)
EraserPx(step) {
    global ERASER_BASE_PX, ERASER_STEP_RATIO
    return Round(StepToPx(step, ERASER_BASE_PX, ERASER_STEP_RATIO))
}

; 예전 설정(픽셀값)을 단계로 되돌릴 때 쓴다
PxToStep(px, basePx, ratio) {
    global STEP_MAX
    if (px <= basePx)
        return 1
    return Max(1, Min(STEP_MAX, Round(Log(px / basePx) / Log(ratio)) + 1))
}

; ================= 설정값 (settings.ini에서 불러옴, 없으면 기본값) =================
; spotOpacity는 0~100(%)로 저장/표시하고, 실제 WinSetTransparent에 쓸 때만 0~255로 환산한다.
; clickSpeed는 "클수록 빠름"(1~30)으로 저장/표시하고, 타이머 간격(ms)으로 쓸 때만 뒤집어 계산한다.
LoadSettings() {
    global SETTINGS_PATH, SpotSize, spotOpacity, SpotThickness, DrawOpacity, DrawStep, EraserStep
    global STEP_MAX, PEN_BASE_PX, PEN_STEP_RATIO, ERASER_BASE_PX, ERASER_STEP_RATIO
    global spotColor, clickColor, drawColor, laserHold, laserFade, laserGlow
    global clickEffectEnabled, clickSpeed, clickOpacity, CLICK_ANIM_INTERVAL, rclickEffectEnabled, rclickThickness, rclickSpeed, rclickOpacity, RCLICK_ANIM_INTERVAL, rclickColor, showWidget, showTrayIcons, hideCursorOnHighlight, widgetScale, widgetBgColor, widgetOpacity, widgetX, widgetY
    global HOTKEY_DEFAULTS, hotkeyCombos, DEFAULT_DRAW_STEP, DEFAULT_ERASER_STEP
    SpotSize := Max(30, Min(200, IniRead(SETTINGS_PATH, "Highlight", "Size", 130)))
    ; 예전 버전은 투명도를 0~255로 저장했었다. 그 값이 남아있어도 안전하게 0~100으로 잘려 들어가도록 한다.
    spotOpacity := Max(0, Min(100, IniRead(SETTINGS_PATH, "Highlight", "Opacity", 40)))
    SpotThickness := Max(2, Min(12, IniRead(SETTINGS_PATH, "Highlight", "RingThickness", 7)))
    clickEffectEnabled := IniRead(SETTINGS_PATH, "Highlight", "ClickEffect", 1) = 1
    clickSpeed := Max(1, Min(30, IniRead(SETTINGS_PATH, "Highlight", "ClickSpeed", 26)))
    clickOpacity := Max(0, Min(100, IniRead(SETTINGS_PATH, "Highlight", "ClickOpacity", 50)))
    CLICK_ANIM_INTERVAL := 41 - clickSpeed ; 1(40ms, 예전보다 더 느린 옵션)~30(11ms, 예전 "20" 정도의 체감 속도가 새 최대)
    hideCursorOnHighlight := IniRead(SETTINGS_PATH, "Highlight", "HideCursor", 1) = 1
    ; 오른쪽 클릭 효과는 나중에 붙인 기능이라 **기본은 꺼둔다** — 쓰던 분들 화면이 업데이트만으로
    ; 달라지면 안 된다. 나머지 값은 왼쪽 클릭의 기본값과 같게 맞춰, 켜는 순간 익숙한 모습이 되게 한다.
    rclickEffectEnabled := IniRead(SETTINGS_PATH, "Highlight", "RClickEffect", 0) = 1
    rclickThickness := Max(2, Min(12, IniRead(SETTINGS_PATH, "Highlight", "RClickThickness", 7)))
    rclickSpeed := Max(1, Min(30, IniRead(SETTINGS_PATH, "Highlight", "RClickSpeed", 26)))
    rclickOpacity := Max(0, Min(100, IniRead(SETTINGS_PATH, "Highlight", "RClickOpacity", 50)))
    RCLICK_ANIM_INTERVAL := 41 - rclickSpeed
    DrawOpacity := Max(0, Min(100, IniRead(SETTINGS_PATH, "Draw", "Opacity", 100)))
    ; 굵기와 지우개 크기는 1~10단계로 다룬다(위 StepToPx 참고). 읽는 순서는 세 단계다 —
    ; (1) 새 항목이 있으면 그대로, (2) 없고 옛 픽셀값이 남아 있으면 가장 가까운 단계로 변환,
    ; (3) 둘 다 없으면(= 처음 받아 쓰는 PC) 아래 기본 단계.
    legacyThickness := IniRead(SETTINGS_PATH, "Draw", "Thickness", "")
    legacyEraser := IniRead(SETTINGS_PATH, "Draw", "EraserSize", "")
    DrawStep := Max(1, Min(STEP_MAX, IniRead(SETTINGS_PATH, "Draw", "ThicknessStep"
        , legacyThickness != "" ? PxToStep(legacyThickness, PEN_BASE_PX, PEN_STEP_RATIO) : DEFAULT_DRAW_STEP)))
    EraserStep := Max(1, Min(STEP_MAX, IniRead(SETTINGS_PATH, "Draw", "EraserStep"
        , legacyEraser != "" ? PxToStep(legacyEraser, ERASER_BASE_PX, ERASER_STEP_RATIO) : DEFAULT_ERASER_STEP)))
    ; 레이저 펜(레이저): 그어진 뒤 그대로 있는 시간(ms), 그 뒤 사라지는 데 걸리는 시간(ms), 빛 번짐(%).
    ; 맥 판과 같은 이름·범위다 (기본값은 LASER_HOLD_MS·LASER_FADE_MS와 같다).
    laserHold := Max(0, Min(3000, IniRead(SETTINGS_PATH, "Draw", "LaserHold", 500)))
    laserFade := Max(100, Min(3000, IniRead(SETTINGS_PATH, "Draw", "LaserFade", 500)))
    laserGlow := Max(0, Min(200, IniRead(SETTINGS_PATH, "Draw", "LaserGlow", 100)))
    ; 색은 포인터/클릭효과/드로잉이 각각 따로 갖는다. 예전 버전은 셋이 같은 색([Common] Color)을
    ; 썼으므로, 새 항목이 아직 없으면 그 값을 세 곳의 기본값으로 쓴다 — 쓰던 사람이 업데이트해도
    ; 화면이 갑자기 달라지지 않는다.
    legacyColor := IniRead(SETTINGS_PATH, "Common", "Color", "FF0000")
    spotColor := Integer("0x" IniRead(SETTINGS_PATH, "Highlight", "Color", legacyColor))
    clickColor := Integer("0x" IniRead(SETTINGS_PATH, "Highlight", "ClickColor", legacyColor))
    ; 오른쪽은 기본을 **파랑**으로 둔다. 왼쪽(빨강)과 색이 달라야 어느 버튼을 눌렀는지
    ; 학생이 구분할 수 있고, 그게 좌·우를 따로 둔 이유이기도 하다.
    rclickColor := Integer("0x" IniRead(SETTINGS_PATH, "Highlight", "RClickColor", "0020FF"))
    drawColor := Integer("0x" IniRead(SETTINGS_PATH, "Draw", "Color", legacyColor))
    showWidget := IniRead(SETTINGS_PATH, "Common", "ShowWidget", 1) = 1
    showTrayIcons := IniRead(SETTINGS_PATH, "Common", "ShowTrayIcons", 0) = 1
    ; 위젯 크기는 100%가 기준. 빔프로젝터로 크게 띄우거나 고해상도 노트북에서 작게 보일 때 쓴다.
    widgetScale := Max(60, Min(250, IniRead(SETTINGS_PATH, "Common", "WidgetScale", 100)))
    widgetBgColor := Integer("0x" IniRead(SETTINGS_PATH, "Common", "WidgetColor", "F2F2F2"))
    ; 위젯이 수업 화면을 가리는 게 신경 쓰일 때 쓴다. 너무 낮추면 눌러야 할 버튼이 안 보여서 20%까지만.
    widgetOpacity := Max(20, Min(100, IniRead(SETTINGS_PATH, "Common", "WidgetOpacity", 100)))
    ; 위젯을 옮겨둔 자리. 한 번도 안 옮겼으면 빈 값이고, 그때는 화면 오른쪽 아래에서 시작한다.
    widgetX := IniRead(SETTINGS_PATH, "Common", "WidgetX", "")
    widgetY := IniRead(SETTINGS_PATH, "Common", "WidgetY", "")
    ; 저장된 단축키가 이상하면(사람이 ini를 잘못 고쳤다거나) 기본값으로 돌려서, 단축키가
    ; 하나도 안 먹는 상태로 시작하는 일이 없게 한다.
    for name, def in HOTKEY_DEFAULTS {
        combo := IniRead(SETTINGS_PATH, "Hotkeys", name, def)
        hotkeyCombos[name] := IsSafeHotkey(combo) ? combo : def
    }
}

; 저장에 성공하면 참을 돌려준다.
; **쓸 수 없는 곳에 두고 실행하는 경우가 실제로 있다** — 압축 파일 안에서 바로 실행했거나
; (임시 폴더에서 돌아간다), Program Files처럼 권한이 막힌 곳에 두었거나, 읽기 전용 USB인
; 경우다. 그냥 두면 IniWrite가 던진 오류가 그대로 튀어나와 수업 중에 오류 창이 뜨고 스크립트가
; 멈춘다. 무엇을 어떻게 하면 되는지 알려주고 계속 쓸 수 있게 한다(바꾼 값은 이번 실행 동안 유효).
SaveSettings() {
    global SETTINGS_PATH, SpotSize, spotOpacity, SpotThickness, DrawOpacity, DrawStep, EraserStep, spotColor, clickColor, drawColor, clickEffectEnabled, clickSpeed, clickOpacity, rclickEffectEnabled, rclickThickness, rclickSpeed, rclickOpacity, rclickColor, showWidget, showTrayIcons, hideCursorOnHighlight, hotkeyCombos, widgetScale, widgetBgColor, widgetOpacity, widgetX, widgetY
    try
        return WriteSettings()
    catch as err {
        MsgBox("설정을 저장하지 못했습니다.`n`n"
            . "이 폴더에 파일을 쓸 수 없습니다:`n" SETTINGS_PATH "`n`n"
            . "압축 파일 안에서 바로 실행했거나, 쓰기가 막힌 폴더에 두었을 때 생깁니다.`n"
            . "압축을 풀어 바탕화면이나 문서 폴더로 옮긴 뒤 다시 실행해 주세요.`n`n"
            . "방금 바꾼 설정은 프로그램을 끄기 전까지는 그대로 쓰실 수 있습니다.`n`n"
            . "(자세한 이유: " err.Message ")"
            , "Focus & Draw — 설정 저장 실패", "Icon!")
        return false
    }
}

WriteSettings() {
    global laserHold, laserFade, laserGlow
    global SETTINGS_PATH, SpotSize, spotOpacity, SpotThickness, DrawOpacity, DrawStep, EraserStep, spotColor, clickColor, drawColor, clickEffectEnabled, clickSpeed, clickOpacity, rclickEffectEnabled, rclickThickness, rclickSpeed, rclickOpacity, rclickColor, showWidget, showTrayIcons, hideCursorOnHighlight, hotkeyCombos, widgetScale, widgetBgColor, widgetOpacity, widgetX, widgetY
    IniWrite(SpotSize, SETTINGS_PATH, "Highlight", "Size")
    IniWrite(spotOpacity, SETTINGS_PATH, "Highlight", "Opacity")
    IniWrite(SpotThickness, SETTINGS_PATH, "Highlight", "RingThickness")
    IniWrite(clickEffectEnabled ? 1 : 0, SETTINGS_PATH, "Highlight", "ClickEffect")
    IniWrite(clickSpeed, SETTINGS_PATH, "Highlight", "ClickSpeed")
    IniWrite(clickOpacity, SETTINGS_PATH, "Highlight", "ClickOpacity")
    IniWrite(hideCursorOnHighlight ? 1 : 0, SETTINGS_PATH, "Highlight", "HideCursor")
    IniWrite(HexColor(spotColor), SETTINGS_PATH, "Highlight", "Color")
    IniWrite(HexColor(clickColor), SETTINGS_PATH, "Highlight", "ClickColor")
    IniWrite(rclickEffectEnabled ? 1 : 0, SETTINGS_PATH, "Highlight", "RClickEffect")
    IniWrite(rclickThickness, SETTINGS_PATH, "Highlight", "RClickThickness")
    IniWrite(rclickSpeed, SETTINGS_PATH, "Highlight", "RClickSpeed")
    IniWrite(rclickOpacity, SETTINGS_PATH, "Highlight", "RClickOpacity")
    IniWrite(HexColor(rclickColor), SETTINGS_PATH, "Highlight", "RClickColor")
    IniWrite(DrawStep, SETTINGS_PATH, "Draw", "ThicknessStep")
    IniWrite(DrawOpacity, SETTINGS_PATH, "Draw", "Opacity")
    IniWrite(EraserStep, SETTINGS_PATH, "Draw", "EraserStep")
    IniWrite(HexColor(drawColor), SETTINGS_PATH, "Draw", "Color")
    IniWrite(laserHold, SETTINGS_PATH, "Draw", "LaserHold")
    IniWrite(laserFade, SETTINGS_PATH, "Draw", "LaserFade")
    IniWrite(laserGlow, SETTINGS_PATH, "Draw", "LaserGlow")
    IniWrite(showWidget ? 1 : 0, SETTINGS_PATH, "Common", "ShowWidget")
    IniWrite(showTrayIcons ? 1 : 0, SETTINGS_PATH, "Common", "ShowTrayIcons")
    IniWrite(widgetScale, SETTINGS_PATH, "Common", "WidgetScale")
    IniWrite(HexColor(widgetBgColor), SETTINGS_PATH, "Common", "WidgetColor")
    IniWrite(widgetOpacity, SETTINGS_PATH, "Common", "WidgetOpacity")
    SaveWidgetPos() ; 위치는 옮길 때마다 따로 적지만, 저장을 누를 때도 지금 자리를 확실히 남긴다
    for name, combo in hotkeyCombos
        IniWrite(combo, SETTINGS_PATH, "Hotkeys", name)
    ; 예전 버전에 있던 전역 "지우기" 단축키의 잔재를 치운다. 안 읽히는 값이라 그냥 둬도
    ; 동작에는 문제가 없지만, 설정 파일을 열어본 사람이 헷갈리지 않도록 지운다.
    try IniDelete(SETTINGS_PATH, "Hotkeys", "Clear")
    ; 색이 세 곳으로 갈라지기 전에 쓰던 공용 색 항목도 같은 이유로 치운다. 위에서 세 색을
    ; 모두 적어둔 뒤라, 지워도 다음 실행 때 색이 달라지지 않는다.
    try IniDelete(SETTINGS_PATH, "Common", "Color")
    ; 굵기·지우개 크기를 픽셀로 저장하던 시절의 항목도 치운다(이제 단계로 저장한다)
    try IniDelete(SETTINGS_PATH, "Draw", "Thickness")
    try IniDelete(SETTINGS_PATH, "Draw", "EraserSize")
    SavePalette()
    return true
}

; 설정 파일에 적힌 색을 읽는다. 사람이 ini를 잘못 고쳐 색이 아닌 글자가 들어 있어도
; 프로그램이 멈추지 않고 기본값으로 넘어가게 한다.
ReadIniColor(section, key, fallback) {
    global SETTINGS_PATH
    raw := IniRead(SETTINGS_PATH, section, key, "")
    if (raw = "")
        return fallback
    try {
        v := Integer("0x" raw)
        if (v >= 0 && v <= 0xFFFFFF)
            return v
    }
    return fallback
}

; 숫자키 1~9의 색·투명도와 칠판 W/E/R의 색·투명도를 불러온다.
; **LoadSettings()와 따로 둔 이유는 순서 때문이다** — 이 값들이 담길 배열은 아래쪽 "색"과
; "칠판" 절에서 만들어지는데, LoadSettings()는 그보다 먼저 불린다. 그래서 배열을 만든 직후에
; 이 함수를 따로 부른다.
LoadPalette() {
    global SETTINGS_PATH, DRAW_COLORS, DRAW_ALPHAS, DRAW_COLOR_DEFAULTS, DRAW_STEPS, DRAW_STEP_DEFAULT, STEP_MAX
    global BOARD_COLORS, BOARD_ALPHAS, BOARD_COLOR_DEFAULTS, BOARD_KEYS
    loop DRAW_COLORS.Length {
        DRAW_COLORS[A_Index] := ReadIniColor("DrawKeys", "Color" A_Index, DRAW_COLOR_DEFAULTS[A_Index])
        ; 0%까지 내려가면 "안 그려지는 펜"이 되어 고장으로 보인다. 5%를 바닥으로 둔다.
        DRAW_ALPHAS[A_Index] := Max(5, Min(100, IniRead(SETTINGS_PATH, "DrawKeys", "Opacity" A_Index, 100)))
        ; 숫자가 아닌 글자가 들어 있으면 기본값(5단계)으로 본다.
        step := IniRead(SETTINGS_PATH, "DrawKeys", "Step" A_Index, DRAW_STEP_DEFAULT)
        DRAW_STEPS[A_Index] := (IsInteger(step) && step >= 1) ? Min(STEP_MAX, Integer(step)) : DRAW_STEP_DEFAULT ; 0 이하(시험판이 쓰던 값)도 기본값
    }
    loop BOARD_COLORS.Length {
        if (BOARD_COLOR_DEFAULTS[A_Index] < 0) ; Q(투명)는 칠판을 걷는 자리라 색이 없다
            continue
        key := StrUpper(BOARD_KEYS[A_Index][1])
        BOARD_COLORS[A_Index] := ReadIniColor("Boards", "Color" key, BOARD_COLOR_DEFAULTS[A_Index])
        BOARD_ALPHAS[A_Index] := Max(5, Min(100, IniRead(SETTINGS_PATH, "Boards", "Opacity" key, 100)))
    }
}

SavePalette() {
    global SETTINGS_PATH, DRAW_COLORS, DRAW_ALPHAS, DRAW_STEPS, BOARD_COLORS, BOARD_ALPHAS, BOARD_COLOR_DEFAULTS, BOARD_KEYS
    loop DRAW_COLORS.Length {
        IniWrite(HexColor(DRAW_COLORS[A_Index]), SETTINGS_PATH, "DrawKeys", "Color" A_Index)
        IniWrite(DRAW_ALPHAS[A_Index], SETTINGS_PATH, "DrawKeys", "Opacity" A_Index)
        IniWrite(DRAW_STEPS[A_Index], SETTINGS_PATH, "DrawKeys", "Step" A_Index) 
    }
    loop BOARD_COLORS.Length {
        if (BOARD_COLOR_DEFAULTS[A_Index] < 0)
            continue
        key := StrUpper(BOARD_KEYS[A_Index][1])
        IniWrite(HexColor(BOARD_COLORS[A_Index]), SETTINGS_PATH, "Boards", "Color" key)
        IniWrite(BOARD_ALPHAS[A_Index], SETTINGS_PATH, "Boards", "Opacity" key)
    }
}

LoadSettings()

; ================= Windows 시작 시 자동 실행 =================
; settings.ini가 아니라 실제 상태(레지스트리)를 그 자리에서 그대로 읽고 쓴다 — 다른 방법으로
; 시작프로그램에서 제거된 경우까지 항상 정확하게 보여주기 위해서다. 값에는 exe로
; 컴파일했을 때와 .ahk 소스로 실행할 때 모두 지금 실행 중인 파일의 실제 경로(A_ScriptFullPath)를
; 그대로 써서, 둘 중 어느 형태로 실행 중이든 그 형태로 다시 켜지게 한다.
STARTUP_RUN_KEY := "HKCU\Software\Microsoft\Windows\CurrentVersion\Run"
STARTUP_RUN_NAME := "FocusDraw"

IsRunAtStartup() {
    global STARTUP_RUN_KEY, STARTUP_RUN_NAME
    try
        return RegRead(STARTUP_RUN_KEY, STARTUP_RUN_NAME, "") != ""
    catch
        return false
}

SetRunAtStartup(enable) {
    global STARTUP_RUN_KEY, STARTUP_RUN_NAME
    if enable
        RegWrite('"' A_ScriptFullPath '"', "REG_SZ", STARTUP_RUN_KEY, STARTUP_RUN_NAME)
    else
        try RegDelete(STARTUP_RUN_KEY, STARTUP_RUN_NAME)
}

; ================= 상태값 =================
spotlightOn := false
drawOn := false
drawing := false
lastX := 0
lastY := 0
dragStartX := 0
dragStartY := 0
dragShapeMode := ""
dragPenKind := "" ; 도형이 아닌 특수 펜: "laser"(레이저 펜) | "rainbow"(무지개 펜) | ""(보통 펜)
dragOnOtherWindow := false ; 현재 드래그가 판서 오버레이가 아닌 다른 창(위젯/캡처 도구 등) 위에서 시작돼 판서를 건너뛰어야 하는지
erasing := false ; 오른쪽 버튼으로 지우는 중인지
lastShapeBox := [] ; 직전 미리보기 프레임이 그린 범위 (그 자리만 되돌리고 다시 합성하면 된다)

; 드로잉 중 숫자키 1~9로 바로 바꿀 수 있는 색 (무지개 순서: 빨주노초파남보 + 검정 + 흰색).
; **표준 무지개값을 그대로 쓴다.** 한때 노랑과 초록을 "흰 배경에서 잘 안 보인다"는 이유로
; 조금 진하게 바꿔뒀었는데, 어떤 배경에 어떤 색이 잘 보이는지는 쓰는 사람이 그 자리에서
; 판단할 문제지 프로그램이 대신 정할 일이 아니다(빨간 바탕화면을 쓰는 사람에게는 빨강도
; 안 보인다 — 그렇다고 빨강을 손볼 수는 없다). 안 보이면 숫자키 한 번으로 바꾸면 된다.
; **여기 있는 것은 기본값이고, 실제로 쓰이는 값은 아래 DRAW_COLORS다.** 설정 창에서 숫자키마다
; 색과 투명도를 따로 정할 수 있고(settings.ini의 [DrawKeys]), 정한 값이 없으면 이 기본값으로
; 시작한다. "기본값으로 되돌리기"도 이 배열을 그대로 다시 넣는다.
DRAW_COLOR_DEFAULTS := [0xFF0000, 0xFF7F00, 0xFFFF00, 0x00FF00, 0x0000FF, 0x4B0082, 0x9400D3, 0x000000, 0xFFFFFF]
DRAW_COLOR_NAMES := ["빨강", "주황", "노랑", "초록", "파랑", "남색", "보라", "검정", "흰색"]
DRAW_COLORS := DRAW_COLOR_DEFAULTS.Clone()
; 숫자키마다의 불투명도(%). 100이면 지금까지와 똑같고, 낮추면 그 색이 형광펜처럼 비쳐 보인다.
; (설정 창 "드로잉" 탭의 투명도는 **그려둔 것 전체**에 곱해지는 값이고, 이쪽은 **그 색으로 긋는
;  선 하나하나**의 값이다. 둘 다 낮추면 둘이 곱해져 더 옅어진다)
DRAW_ALPHA_DEFAULT := 100
DRAW_ALPHAS := [100, 100, 100, 100, 100, 100, 100, 100, 100]
; 숫자키마다의 굵기 단계(1~STEP_MAX). 그 숫자키를 누르면 색·투명도와 함께 굵기도 이 단계로 바뀐다.
; 기본값은 설정 창의 기본 드로잉 굵기와 같은 5단계다.
DRAW_STEP_DEFAULT := 5
DRAW_STEPS := [5, 5, 5, 5, 5, 5, 5, 5, 5]

; 드로잉 중 "누른 채 드래그"로 도형을 고르는 키 (위에 있는 것이 우선).
; 수식키(Shift/Ctrl)만 쓰면 자리가 네 개뿐이라 도형을 늘릴 수 없는데, 드로잉 모드에서는
; 글자키도 다른 용도가 없으므로 그냥 쓸 수 있다. 다만 판서 오버레이는 포커스를 가져가지
; 않아서(drawGui.Show("NA")) 그냥 두면 누른 글자가 뒤에 있는 프로그램에 그대로 입력된다 —
; 그래서 드로잉 모드일 때만 이 키들을 핫키로 잡아 삼킨다(SetDrawModeHotkeys).
SHAPE_HOLD_KEYS := [["z", "line"], ["x", "wave"], ["c", "arrow"]]
; A·S는 도형이 아니라 **펜의 종류**를 바꾼다. 도형 키와 달리 **한 번 누르면 계속 그 펜**이고,
; 숫자키(1~9, 0)로 색을 고르면 보통 펜으로 돌아온다(사용자 결정 — 전자칠판 앞에서는 키를 쥔 채
; 칠판을 그을 수 없다). 드로잉을 껐다 켜도 보통 펜으로 돌아온다(색·굵기와 같다).
PEN_KIND_KEYS := [["a", "laser"], ["s", "rainbow"]]
penKind := "" ; 지금 고른 특수 펜: "laser" | "rainbow" | ""(보통 펜)
; 도형 키를 누른 채로 Shift를 더하면(직선 각도 맞추기) 그 조합도 잡아야 한다. 수식키 없는 핫키는
; Shift가 함께 눌리면 발동하지 않아서, Shift를 먼저 누르면 글자가 뒤의 프로그램으로 새고 뗀 것도
; 못 봐 "계속 눌림"으로 남는다. 그래서 두 가지(맨 키 / Shift+키)를 모두 등록한다. (A·S도 같은
; 이유로 두 가지를 등록한다 — Shift와 함께 눌러도 글자가 뒤로 새지 않게)
; (별표 * 로 한 번에 잡는 방법도 있지만, 그러면 Ctrl+Z까지 가로챌 수 있어 피했다)
HOLD_KEY_PREFIXES := ["", "+"]
; 지금 눌려 있는 도형 키. 핫키에 삼켜진 키는 GetKeyState(..., "P")로 읽히리라 기대할 수 없어서
; (흉내낸 입력으로 확인해보면 0으로 나온다) 누를 때와 뗄 때를 직접 받아 여기에 기록한다.
shapeKeyHeld := Map()
; 실제로 선을 그릴 때 쓰는 색과 굵기. 설정에 저장된 값(drawColor / DrawStep / EraserStep)을
; 기본으로 하되 드로잉 중에 숫자키와 +/-로 잠깐 바꿀 수 있고, 드로잉 모드를 켜고 끌 때마다
; 설정값으로 되돌아간다. 설정값을 직접 바꾸지 않는 이유는, 그랬다가 "저장"까지 눌리면 수업 중에
; 잠깐 쓰려고 바꾼 값이 그대로 굳어버리고, 설정 창의 슬라이더 표시와도 어긋나기 때문이다.
; activeDrawStep/activeEraserStep이 실제 값이고, ...Thickness/...Size는 거기서 환산한 픽셀값이다.
activeDrawColor := drawColor
activeDrawAlpha := StartAlpha(100) ; 지금 긋는 선의 불투명도(%, 절대값) — 숫자키로 색을 고를 때 그 색의 값으로 바뀐다
activeDrawStep := DrawStep
activeEraserStep := EraserStep
activeDrawThickness := PenPx(DrawStep)
activeEraserSize := EraserPx(EraserStep)

; 실행 취소용 기록. 단계 수(UNDO_LIMIT)는 화면 크기를 알아야 정할 수 있어서 아래쪽
; 백버퍼를 만드는 곳에서 함께 계산한다.
undoStack := []
chkWidgetCtrl := "" ; 설정 창의 "위젯 활성화" 체크박스 (창을 아직 한 번도 안 열었으면 비어 있음)
settingsHiddenByDraw := false ; 판서를 켜느라 설정 창을 잠시 감췄는지 (판서를 끄면 다시 띄운다)

; ================= 가상 화면(전체 모니터) 크기 =================
vx := SysGet(76)
vy := SysGet(77)
vw := SysGet(78)
vh := SysGet(79)

; ================= 색상 변환 (RGB -> COLORREF/BGR) =================
ToBGR(rgb) {
    r := (rgb >> 16) & 0xFF
    g := (rgb >> 8) & 0xFF
    b := rgb & 0xFF
    return (b << 16) | (g << 8) | r
}
HexColor(rgb) => Format("{:06X}", rgb)

; ================= 판서용 백버퍼 (32bpp, 픽셀 단위 투명도) =================
bi := Buffer(40, 0)
NumPut("UInt", 40, bi, 0)   ; biSize
NumPut("Int", vw, bi, 4)    ; biWidth
NumPut("Int", -vh, bi, 8)   ; biHeight (음수 = top-down)
NumPut("UShort", 1, bi, 12) ; biPlanes
NumPut("UShort", 32, bi, 14) ; biBitCount
NumPut("UInt", 0, bi, 16)   ; biCompression = BI_RGB

ppvBits := 0
hScreenDC := DllCall("GetDC", "ptr", 0, "ptr")
memDC := DllCall("CreateCompatibleDC", "ptr", hScreenDC, "ptr")
memBmp := DllCall("CreateDIBSection", "ptr", hScreenDC, "ptr", bi, "uint", 0, "ptr*", &ppvBits, "ptr", 0, "uint", 0, "ptr")
DllCall("SelectObject", "ptr", memDC, "ptr", memBmp)
DllCall("ReleaseDC", "ptr", 0, "ptr", hScreenDC)

; 도형 미리보기는 GDI가 아니라 GDI+로 그린다. GDI는 알파 채널을 건드리지 않아서, 그린 자리를
; 픽셀 단위로 훑어 알파를 255로 올려줘야 했다 — 큰 사각형이나 원은 그 훑는 양이 수십만 픽셀이라
; 한 프레임에 수백 밀리초가 걸렸고, 그래서 크게 그릴수록 드래그가 뚝뚝 끊겼다. GDI+는 알파까지
; 제대로 써주므로 훑는 작업 자체가 없어진다. 같은 DIB 메모리를 가리키게 만들어 두 방식이 같은
; 그림을 공유한다. (0xE200B = 미리 곱해진 32비트 ARGB — 레이어드 윈도우가 기대하는 형식)
pShapeBitmap := 0, pShapeGraphics := 0
DllCall("gdiplus\GdipCreateBitmapFromScan0", "int", vw, "int", vh, "int", vw * 4, "int", 0xE200B, "ptr", ppvBits, "ptr*", &pShapeBitmap)
if pShapeBitmap {
    DllCall("gdiplus\GdipGetImageGraphicsContext", "ptr", pShapeBitmap, "ptr*", &pShapeGraphics)
    if pShapeGraphics
        DllCall("gdiplus\GdipSetSmoothingMode", "ptr", pShapeGraphics, "int", 4) ; 계단 없이 매끄럽게
}

; ================= 반투명 획 전용 판 =================
; 반투명한 색으로 그을 때는 판서 그림에 바로 긋지 않고, 이 판에 **불투명하게** 그린 다음
; 그 판을 획을 긋기 전 모습(스냅샷) 위에 정해둔 투명도로 **겹쳐 얹는다.** 그림판·포토샵과 같은 방식이다.
; 예전에는 판서 그림에 "덮어쓰기"(SourceCopy)로 바로 그었다. 자유선은 10ms마다 짧은 토막을 이어
; 붙이는 것이라 보통으로 겹쳐 그리면 이음매가 두 번 칠해져 진해지기 때문이었는데, 대신 **먼저
; 그어둔 다른 선 위를 지나가면 그 선까지 반투명한 색으로 바꿔버렸다** — 불투명한 빨간 선 위로
; 50% 파란 선을 그으면 겹친 자리가 보라가 아니라 옅은 파랑이 됐다. 이 판에서는 한 획 안의 이음매가
; 아무리 겹쳐도 불투명한 색 그대로라 진해지지 않고, 겹쳐 얹을 때 아래 그림이 비쳐 보인다.
; 가장자리 부드럽게도 다시 켤 수 있게 됐다(덮어쓰기에서는 이음매마다 초승달 자국이 남아 꺼뒀었다).
; 도형도 같은 판을 쓴다 — 화살표는 몸통과 머리를 따로 그려서 만나는 자리가 두 번 칠해졌다.
;
; **판은 반투명한 색을 처음 쓸 때 만들고, 드로잉을 끄면 돌려준다**(EnsureInkLayer / FreeInkLayer).
; 화면 크기만 한 판이라(1920x1080에서 7.9MB) 늘 들고 있으면 반투명 색을 한 번도 안 쓰는 날에도
; 그만큼 메모리를 차지한다 — 가만히 있을 때 메모리를 재보니 전용 메모리 38MB 중 32MB가 이런
; 화면 크기의 판들이었다. 드로잉을 켤 때마다 한 번 만드는 비용은 눈에 띄지 않는다.
inkLayerBuf := 0
pInkLayer := 0, pInkGraphics := 0, pInkAttr := 0
inkAttrAlpha := -1 ; pInkAttr에 지금 걸려 있는 투명도(%) — 바뀔 때만 다시 건다
inkDirty := []     ; 판에서 아직 비우지 않은 범위 (다음 획을 시작할 때 이 자리만 비운다)
inkStrokeAlpha := 0 ; 지금 긋는 획이 이 판을 거치면 그 투명도(%), 판서 그림에 바로 그으면 0

; 판이 없으면 만든다. 만들 수 있으면(또는 이미 있으면) true.
EnsureInkLayer() {
    global inkLayerBuf, pInkLayer, pInkGraphics, pInkAttr, inkAttrAlpha, inkDirty, pShapeGraphics, vw, vh
    if (pInkGraphics && pInkAttr)
        return true
    if !pShapeGraphics
        return false
    FreeInkLayer() ; 반쯤 만들어진 것이 남아 있으면 치우고 처음부터
    try inkLayerBuf := Buffer(vw * vh * 4, 0)
    catch
        return false ; 메모리가 모자라면 예전 방식(덮어쓰기)으로 그린다
    DllCall("gdiplus\GdipCreateBitmapFromScan0", "int", vw, "int", vh, "int", vw * 4, "int", 0xE200B, "ptr", inkLayerBuf.Ptr, "ptr*", &pInkLayer)
    if pInkLayer {
        DllCall("gdiplus\GdipGetImageGraphicsContext", "ptr", pInkLayer, "ptr*", &pInkGraphics)
        if pInkGraphics
            DllCall("gdiplus\GdipSetSmoothingMode", "ptr", pInkGraphics, "int", 4)
    }
    DllCall("gdiplus\GdipCreateImageAttributes", "ptr*", &pInkAttr)
    inkAttrAlpha := -1
    inkDirty := []
    return (pInkGraphics && pInkAttr) ? true : false
}

; 판을 돌려준다. 드로잉을 끌 때 부른다.
FreeInkLayer() {
    global inkLayerBuf, pInkLayer, pInkGraphics, pInkAttr, inkAttrAlpha, inkDirty, inkStrokeAlpha
    if pInkGraphics
        DllCall("gdiplus\GdipDeleteGraphics", "ptr", pInkGraphics)
    if pInkLayer
        DllCall("gdiplus\GdipDisposeImage", "ptr", pInkLayer) ; 비트맵이 버퍼를 가리키므로 버퍼보다 먼저 치운다
    if pInkAttr
        DllCall("gdiplus\GdipDisposeImageAttributes", "ptr", pInkAttr)
    pInkGraphics := 0, pInkLayer := 0, pInkAttr := 0
    inkLayerBuf := 0
    inkAttrAlpha := -1
    inkDirty := []
    inkStrokeAlpha := 0
}

; 도형(직선/사각형/원) 미리보기를 그리기 전에 현재 그림을 스냅샷으로 저장해뒀다가,
; 드래그 중 매 프레임마다 스냅샷으로 되돌린 뒤 새 도형을 다시 그려서 "고무줄 미리보기" 효과를 낸다.
; ================= 실행 취소 =================
; 예전에는 획을 긋기 직전에 화면 전체(가로x세로x4바이트)를 통째로 복사해 한 단계로 쌓았다.
; 모니터를 두 대 늘어놓으면 한 단계가 20MB를 넘어가서, 메모리 상한에 걸려 두 단계밖에
; 쌓지 못했다. 실제로 바뀌는 건 펜이 지나간 자리뿐인데 화면 전체를 뜨는 게 과했던 것이다.
;
; 그래서 화면을 가로 띠로 나눠 **그 획이 실제로 건드린 띠만** 떠둔다. 띠 하나는 메모리에서
; 연속이라 한 번의 복사로 끝나고(세로로도 자르면 줄마다 따로 복사해야 해서 훨씬 느리다),
; 밑줄 하나 긋는 정도면 띠 한두 개(1MB 안팎)면 충분하다. 덕분에 같은 메모리로 단계 수를
; 열 배 이상 늘릴 수 있다. 전부 지우기처럼 화면 전체를 건드리는 동작은 예전과 같은 크기가
; 되지만, 그건 자주 하는 일이 아니다.
UNDO_BAND := 32          ; 띠 하나의 높이(픽셀)
UNDO_LIMIT := 30         ; 단계 수 상한
UNDO_BYTES_LIMIT := 80000000 ; 전체 메모리 상한 (이 둘 중 먼저 걸리는 쪽이 적용된다)
undoBytes := 0           ; 지금 쌓아둔 전체 크기

; 한 단계가 차지하는 크기
UndoStepBytes(step) {
    total := 0
    for , buf in step
        total += buf.Size
    return total
}

; 오래된 단계부터 버려서 상한을 지킨다. 단계가 하나뿐이면 아무리 커도 남겨둔다 —
; 화면을 다 지운 직후처럼 "되돌릴 게 이것 하나뿐"인 순간에 그걸 버리면 안 되기 때문이다.
TrimUndo() {
    global undoStack, undoBytes, UNDO_LIMIT, UNDO_BYTES_LIMIT
    while (undoStack.Length > UNDO_LIMIT
        || (undoBytes > UNDO_BYTES_LIMIT && undoStack.Length > 1))
        undoBytes -= UndoStepBytes(undoStack.RemoveAt(1))
}

; 새 단계를 연다. 획 하나를 긋기 직전, 지우개를 대기 직전, 전부 지우기 직전에 부른다.
; 여기서는 빈 단계만 열어두고, 실제 내용은 그리면서 건드린 띠만 담긴다(CaptureUndoBands).
PushUndo() {
    global undoStack
    undoStack.Push(Map())
    TrimUndo()
}

; y1~y2 줄에 걸친 띠들의 "바뀌기 전" 모습을 지금 열린 단계에 담아둔다. 그리기 직전에
; 부른다. 이미 담아둔 띠는 건너뛴다 — 한 획 안에서 같은 자리를 여러 번 덧그려도 처음 한 번만
; 떠야 그 획을 긋기 전 상태로 돌아간다.
; (획 밖에서 부르면 엉뚱한 단계에 담기므로, 반드시 PushUndo로 단계를 연 뒤에만 부를 것)
CaptureUndoBands(y1, y2) {
    global undoStack, undoBytes, ppvBits, vw, vh, UNDO_BAND
    if (undoStack.Length = 0)
        return
    step := undoStack[undoStack.Length]
    rowBytes := vw * 4
    first := Integer(Max(0, Min(y1, y2))) // UNDO_BAND
    last := Integer(Min(vh - 1, Max(y1, y2))) // UNDO_BAND
    band := first
    while (band <= last) {
        if !step.Has(band) {
            y0 := band * UNDO_BAND
            size := Min(UNDO_BAND, vh - y0) * rowBytes
            buf := Buffer(size)
            DllCall("RtlCopyMemory", "ptr", buf, "ptr", ppvBits + y0 * rowBytes, "uptr", size)
            step[band] := buf
            undoBytes += size
        }
        band += 1
    }
    TrimUndo()
}

; 드로잉을 끈 채로 UNDO_KEEP_MS가 지나면 실행 취소 기록을 비운다(사용자 결정 — 30초).
; 기록은 최대 30단계·80MB까지 쌓이는데, 끈 뒤에도 그대로 들고 있으면 가만히 있는 동안에도
; 메모리를 붙들고 있게 된다(재보니 한 번 쓰고 끈 뒤 전용 메모리가 14MB가 아니라 62MB였다).
; "실수로 Esc를 눌렀다 → 다시 켜고 Ctrl+Z"는 대개 곧바로 하는 일이라 30초면 충분하다고 봤다.
; 드로잉을 다시 켜면 타이머를 취소하므로, 30초 안에 켜기만 하면 기록은 그대로 남는다.
UNDO_KEEP_MS := 30000
DiscardUndoHistory() {
    global undoStack, undoBytes, drawOn
    if drawOn
        return
    undoStack := []
    undoBytes := 0
}

UndoDrawing(*) {
    global ppvBits, undoStack, undoBytes, vw, UNDO_BAND
    ; 누르기만 하고 끝난 드래그는 아무것도 안 담긴 빈 단계로 남는다. 그런 단계에서 멈추면
    ; Ctrl+Z가 먹지 않는 것처럼 보이므로 건너뛴다.
    while (undoStack.Length > 0 && undoStack[undoStack.Length].Count = 0)
        undoStack.Pop()
    if (undoStack.Length = 0)
        return
    step := undoStack.Pop()
    rowBytes := vw * 4
    for band, buf in step {
        DllCall("RtlCopyMemory", "ptr", ppvBits + band * UNDO_BAND * rowBytes, "ptr", buf, "uptr", buf.Size)
        undoBytes -= buf.Size
    }
    UpdateOverlay()
}

; 드래그를 시작하는 순간의 판서 전체를 떠두는 복사본. 도형의 고무줄 미리보기(매 프레임 직전 도형
; 자리를 이것으로 되돌린다)와 반투명 선(긋기 전 모습 위에 겹쳐 얹는다)이 쓴다.
; **처음 쓸 때 만들고 드로잉을 끄면 돌려준다**(반투명 획 전용 판과 같은 이유 — 화면 크기라
; 드로잉을 안 쓰는 동안 8MB를 붙들고 있을 까닭이 없다). 못 만들면 SaveSnapshot이 false를 돌려주고,
; 부른 쪽은 도형을 건너뛰거나 반투명 선을 예전 방식으로 긋는다.
snapshotBuf := 0
SaveSnapshot() {
    global ppvBits, snapshotBuf, vw, vh
    if !IsObject(snapshotBuf) {
        try snapshotBuf := Buffer(vw * vh * 4) ; 바로 아래에서 통째로 덮어쓰므로 0으로 채울 필요가 없다
        catch
            return false
    }
    DllCall("RtlCopyMemory", "ptr", snapshotBuf, "ptr", ppvBits, "uptr", vw * vh * 4)
    return true
}
RestoreSnapshot() {
    global ppvBits, snapshotBuf, vw, vh
    if IsObject(snapshotBuf)
        DllCall("RtlCopyMemory", "ptr", ppvBits, "ptr", snapshotBuf, "uptr", vw * vh * 4)
}
FreeSnapshot() {
    global snapshotBuf
    snapshotBuf := 0
}

; 알파값 0(완전 투명)인 픽셀은 Windows가 자동으로 클릭을 통과시켜버리므로,
; 안 그려진 배경도 눈에 안 보이는 최소 알파값(1/255)로 채워서 창 전체가 클릭을 받게 한다.
ClearBackBuffer() {
    global ppvBits, vw, vh
    DllCall("RtlFillMemory", "ptr", ppvBits, "uptr", vw * vh * 4, "uchar", 1)
}
ClearBackBuffer()

; ================= 판서 오버레이 창 (레이어드 윈도우 + 픽셀 단위 알파) =================
; 색상 키(투명색) 방식 대신 진짜 픽셀 알파를 쓰면, 안 그려진 빈 공간도 창이 그대로
; 마우스 입력을 받아서 아래 화면(링크 클릭, 텍스트 드래그 등)으로 클릭이 새지 않는다.
; E0x80000 = WS_EX_LAYERED, E0x8000000 = WS_EX_NOACTIVATE.
; **NOACTIVATE가 꼭 필요하다.** 이게 없으면 그림을 그리려고 오버레이를 클릭하는 순간 오버레이가
; 활성화되면서 "항상 위" 무리의 맨 앞으로 올라가고, 그 위에 있어야 할 위젯이 뒤로 밀린다.
; 그러면 판서 중에 위젯을 눌러도 클릭이 오버레이에 막혀 아무 일도 일어나지 않는다
; (한 획 긋고 나면 위젯으로 끄지 못하던 원인이 이것이었다). 오버레이는 포커스를 받을 일이
; 없으므로(단축키는 전역이고 그리기는 마우스 상태를 직접 읽는다) 활성화를 막아도 손해가 없다.
drawGui := Gui("+AlwaysOnTop -Caption +ToolWindow +E0x8080000", "FocusDraw-Draw")
drawGui.Show("x" vx " y" vy " w" vw " h" vh " Hide")

; ================= 레이저 펜 (A를 누르고 긋기) =================
; 파워포인트의 "레이저 포인터"처럼 보이게 한다 — 설명하면서 잠깐 가리키는 선이다.
;   - 선은 **밝은 심지 + 둘레의 빛 번짐** 세 겹으로 그려 빛나 보이게 한다
;   - **점마다 따로 나이를 먹는다.** 그어진 지 laserHold가 지나면 laserFade에 걸쳐
;     가늘어지며 사라진다. 그래서 움직이는 동안에는 혜성처럼 꼬리가 뒤따라오고,
;     멈추면 꼬리가 커서 쪽으로 줄어들며 없어진다
;   - 레이저 펜을 고른 동안에는 커서 자리에 **빛나는 점**이 뜬다 (레이저 점)
; 판서 그림과는 **다른 창**에 그린다 — 같은 그림에 그으면 사라질 때 그 아래 있던 글씨를
; 되살려야 하고, 실행 취소 기록도 엉킨다. 이 창은 판서 층 바로 위에 뜨고, 클릭은 그대로
; 통과시킨다(E0x20). 색은 지금 쓰는 펜을 따른다(기본 빨강이 파워포인트와 같다).
;   - **무지개 레이저**: 무지개 펜(S)을 고른 뒤 A를 누르면 레이저도 무지개가 된다(rainbowColor).
;     숫자키로 색을 고르면 풀린다. 본체는 그은 거리만큼 색이 돌고, 둘레 빛은 그 획을 시작한 색 한 가지다.
; 머무는·사라지는 시간과 빛 번짐은 설정 창(드로잉 탭)에서 바꾼다 — laserHold·laserFade·laserGlow.
LASER_HOLD_MS := 500     ; 그어진 뒤 그대로 있는 시간 (기본값. 실제로는 설정값 laserHold)
LASER_FADE_MS := 500     ; 그 뒤 사라지는 데 걸리는 시간 (기본값. 실제로는 설정값 laserFade)
LASER_MIN_WIDTH := 8     ; 펜을 가늘게 해둬도 레이저는 이만큼은 굵게 (너무 가늘면 빛나 보이지 않는다)
laserGui := Gui("+AlwaysOnTop -Caption +ToolWindow +E0x8080020", "FocusDraw-Laser")
laserGui.Show("x" vx " y" vy " w" vw " h" vh " Hide")
; 그림판은 A를 처음 누를 때 만들고 드로잉을 끄면 돌려준다 — 반투명 획 전용 판과 같은 이유다
; (EnsureLaserCanvas / LaserClearAll).
laserCanvas := 0
; 화면에 남아 있는 획들 {pts: [[x, y, 그은 시각(, 무지개 색)]...], color, width, ended, rainbow, glow}
; glow: 무지개 레이저의 둘레 빛 색(획을 시작한 색). 줄어드는 동안 앞쪽 점을 지워도 빛 색이 바뀌지 않게
; 첫 점에서 읽지 않고 획이 따로 들고 있는다(첫 점에서 읽으면 줄어들며 빛이 번쩍이며 바뀐다).
laserStrokes := []
laserCur := 0      ; 지금 긋고 있는 획 (첫 이동 전에는 아직 laserStrokes에 없다 — LaserBegin 참고)
rainbowColor := false ; S(무지개 펜)를 고른 뒤로 숫자키를 누르기 전까지 참 — 이때 A는 무지개 레이저
laserLastBox := 0  ; 직전 프레임이 그린 범위 (다음 프레임에 이 자리를 비운다)

; 캔버스의 box 범위(로컬 좌표)를 창에 반영한다. 생략하면 전체.
LaserPush(box := 0) {
    global laserGui, laserCanvas, vx, vy, vw, vh
    static info := 0, ptDst := 0, size := 0, ptSrc := 0, blend := 0, dirty := 0
    if !IsObject(laserCanvas)
        return
    if !info {
        ptDst := Buffer(8), NumPut("Int", vx, "Int", vy, ptDst)
        size := Buffer(8), NumPut("Int", vw, "Int", vh, size)
        ptSrc := Buffer(8, 0)
        blend := Buffer(4), NumPut("UChar", 0, "UChar", 0, "UChar", 255, "UChar", 1, blend) ; AC_SRC_OVER, 픽셀 알파
        dirty := Buffer(16, 0)
        info := Buffer(80, 0) ; UPDATELAYEREDWINDOWINFO (x64)
        NumPut("UInt", 80, info, 0)
        NumPut("Ptr", ptDst.Ptr, info, 16)
        NumPut("Ptr", size.Ptr, info, 24)
        NumPut("Ptr", ptSrc.Ptr, info, 40)
        NumPut("Ptr", blend.Ptr, info, 56)
        NumPut("UInt", 2, info, 64) ; ULW_ALPHA
    }
    NumPut("Ptr", laserCanvas.dc, info, 32) ; 그림판은 드로잉을 켤 때마다 새로 만들어질 수 있다
    if IsObject(box) {
        NumPut("Int", Max(0, box[1]), "Int", Max(0, box[2]), "Int", Min(vw, box[3]), "Int", Min(vh, box[4]), dirty)
        NumPut("Ptr", dirty.Ptr, info, 72)
    } else {
        NumPut("Ptr", 0, info, 72)
    }
    DllCall("UpdateLayeredWindowIndirect", "ptr", laserGui.Hwnd, "ptr", info)
}

; 그림판이 없으면 만든다. 만들 수 있으면(또는 이미 있으면) true.
EnsureLaserCanvas() {
    global laserCanvas, vw, vh
    if IsObject(laserCanvas)
        return true
    c := CreateAlphaCanvas(vw, vh)
    if !c.graphics {
        DestroyAlphaCanvas(c)
        return false
    }
    laserCanvas := c
    LaserPush() ; 새 그림판은 한 번 통째로 올려둔다 (그 뒤로는 바뀐 범위만 보낸다)
    return true
}

; 캔버스의 box 범위를 완전히 투명하게 비운다
LaserClearBox(box) {
    global laserCanvas
    if !IsObject(laserCanvas)
        return
    g := laserCanvas.graphics
    pBrush := 0
    DllCall("gdiplus\GdipCreateSolidFill", "uint", 0, "ptr*", &pBrush)
    DllCall("gdiplus\GdipSetCompositingMode", "ptr", g, "int", 1) ; SourceCopy — 투명한 색으로 덮어써야 지워진다
    DllCall("gdiplus\GdipFillRectangleI", "ptr", g, "ptr", pBrush, "int", box[1], "int", box[2], "int", box[3] - box[1], "int", box[4] - box[2])
    DllCall("gdiplus\GdipSetCompositingMode", "ptr", g, "int", 0)
    DllCall("gdiplus\GdipDeleteBrush", "ptr", pBrush)
}

; 옛 네 겹 [굵기 배율, 진하기 배율, 흰색을 섞는 비율] — 이제 그리는 데는 쓰지 않는다. 맥 판의 점검이
; 이 값과 맥의 옛 LASER_LAYERS를 견주므로 남겨 둔다. 실제 겹은 LaserLayers()가 만든다.
LASER_LAYERS := [[3.0, 0.16, 0], [1.7, 0.40, 0], [0.75, 1.0, 0], [0.3, 0.9, 0.6]]
pLaserAttr := 0
DllCall("gdiplus\GdipCreateImageAttributes", "ptr*", &pLaserAttr)

; 빛나는 선의 겹: [굵기 배율, 진하기, 흰색을 섞는 비율]. 바깥에서 안쪽 순서다.
; 번짐은 굵은 겹 두 장이 아니라 **촘촘한 아홉 장**이라 가장자리가 계단 없이 부드럽게 옅어진다 — 굵기
; 배율 3.0 → 1.0, 진하기는 안쪽으로 갈수록 0.045 + 0.10·u²로 완만하게 진해진다(u: 0 = 가장 바깥).
; 그 위에 심지(펜 색 그대로, 흰 바탕에서도 또렷하게)와 가운데 흰빛 줄기(어두운 바탕에서 빛나 보이게).
; 빛 번짐 설정(laserGlow, %)은 번짐 겹만 바꾼다: 굵기 배율 1 + 2·(1 − u)·g, g가 1보다 작으면 진하기도
; g배, 0이면 번짐 없이 심지와 흰빛만, 200%면 가장 바깥 빛이 두 배 넓다(3.0 → 5.0).
; 맥 makeLaserGlowLayers와 같은 값이다.
LaserLayers() {
    global laserGlow
    static cacheGlow := "", cache := 0
    if (cacheGlow != laserGlow) {
        g := laserGlow / 100
        cache := []
        if (g > 0) {
            loop 9 {
                u := (A_Index - 1) / 8
                cache.Push([1 + 2 * (1 - u) * g, (0.045 + 0.10 * u * u) * Min(1, g), 0])
            }
        }
        cache.Push([0.75, 1.0, 0])  ; 심지
        cache.Push([0.3, 0.9, 0.6]) ; 가운데 흰빛 줄기
        cacheGlow := laserGlow
    }
    return cache
}

; 가장 바깥 겹의 굵기 배율 (다시 그릴 범위를 잡을 때 쓴다)
LaserMaxMul() {
    m := 1
    for layer in LaserLayers()
        m := Max(m, layer[1])
    return m
}

; 무지개 원판: 위에서 시작해 시계 방향으로 색상환을 한 바퀴 돈다 (무지개 펜의 커서 원, 무지개 레이저의 점).
; 72조각을 작은 판에 덮어쓰기로 칠한 뒤(조각끼리 겹쳐도 진해지지 않게) 그 판을 무늬로 삼아 원을
; 한 번 채운다 — 그래야 가장자리가 매끄럽고 조각 사이에 실금이 생기지 않는다.
; (x, y)는 원을 감싼 사각형의 왼쪽 위, alpha는 0~255, mix는 흰색을 섞는 비율.
FillRainbowDisc(g, x, y, d, alpha := 255, mix := 0) {
    n := Ceil(d) + 2
    pBmp := 0, gB := 0, pBrush := 0, pTex := 0
    DllCall("gdiplus\GdipCreateBitmapFromScan0", "int", n, "int", n, "int", 0, "int", 0x26200A, "ptr", 0, "ptr*", &pBmp) ; 32bppARGB
    if !pBmp
        return
    DllCall("gdiplus\GdipGetImageGraphicsContext", "ptr", pBmp, "ptr*", &gB)
    DllCall("gdiplus\GdipSetCompositingMode", "ptr", gB, "int", 1) ; SourceCopy
    DllCall("gdiplus\GdipCreateSolidFill", "uint", 0, "ptr*", &pBrush)
    loop 72 {
        DllCall("gdiplus\GdipSetSolidFillColor", "ptr", pBrush, "uint", (alpha << 24) | LaserTint(HueToRGB((A_Index - 1) * 5), mix))
        DllCall("gdiplus\GdipFillPie", "ptr", gB, "ptr", pBrush, "float", -1, "float", -1, "float", n + 2, "float", n + 2
            , "float", -90 + (A_Index - 1) * 5, "float", 6)
    }
    DllCall("gdiplus\GdipDeleteBrush", "ptr", pBrush)
    DllCall("gdiplus\GdipDeleteGraphics", "ptr", gB)
    DllCall("gdiplus\GdipCreateTexture", "ptr", pBmp, "int", 0, "ptr*", &pTex)
    if pTex {
        DllCall("gdiplus\GdipTranslateTextureTransform", "ptr", pTex, "float", x + d / 2 - n / 2, "float", y + d / 2 - n / 2, "int", 0)
        DllCall("gdiplus\GdipFillEllipse", "ptr", g, "ptr", pTex, "float", x, "float", y, "float", d, "float", d)
        DllCall("gdiplus\GdipDeleteBrush", "ptr", pTex)
    }
    DllCall("gdiplus\GdipDisposeImage", "ptr", pBmp)
}

; rgb에 흰색을 mix(0~1)만큼 섞는다
LaserTint(rgb, mix) {
    r := (rgb >> 16) & 0xFF, g := (rgb >> 8) & 0xFF, b := rgb & 0xFF
    return (Round(r + (255 - r) * mix) << 16) | (Round(g + (255 - g) * mix) << 8) | Round(b + (255 - b) * mix)
}

; 점이 얼마나 남아 있는지 (1 = 그대로, 0 = 다 사라짐)
LaserLife(t, now) {
    global laserHold, laserFade
    age := now - t
    return (age <= laserHold) ? 1.0 : Max(0, 1 - (age - laserHold) / laserFade)
}

; box 범위에 남은 꼬리들과 레이저 점을 그린다. 차례: 둘레 번짐 → 심지 → 가운데 흰빛 줄기.
; 반투명한 겹을 토막마다 따로 그으면 이음매마다 두 번 칠해져 구슬을 꿴 것처럼 얼룩진다. 그래서
; **임시 판에 불투명하게** 그린 뒤(불투명끼리는 겹쳐도 달라지지 않는다) 그 판을 한 번에 얹는다 —
; 반투명 획 전용 판(inkLayerBuf)과 같은 생각이다. 덕분에 토막마다 굵기를 따로 줄 수 있어서, 사라져
; 가는 쪽이 매끄럽게 가늘어지는 혜성 꼬리가 된다.
; **번짐 아홉 겹은 한 판에 함께** 그린다. 겹마다 판을 얹으면 판 합치기가 아홉 번이라 무겁다(큰 획에서
; 한 프레임 60ms 넘게 걸렸다). 대신 바깥 겹부터 안쪽 겹까지 "여기까지 쌓인 진하기"(1 − Π(1 − 진하기))를
; 회색 밝기로 덮어 그린 뒤, 그 밝기를 투명도로 바꾸고 색을 입혀 한 번에 얹는다(LaserBlendGlow). 겹마다
; 따로 얹은 것과 같은 결과이고, 겹의 가장자리는 앞 겹의 밝기와 매끄럽게 섞인다. 다른 획과 겹치는 곳은
; 더 진한 쪽을 따르므로 겹쳐 그어도 빛이 진해지지 않는다(맥과 같다). 색이 다른 획은 색마다 따로 얹는다.
; 심지는 불투명이라 임시 판 없이 바로 긋는다.
; 임시 판은 box 크기로 그때그때 만든다(화면 크기로 들고 있기에는 메모리가 아깝다).
; 무지개 레이저(점마다 색이 다른 획)는 심지와 가운데 빛줄기를 토막마다 그 점의 색으로, 번짐은 획을 시작한
; 색(st.glow) 한 가지로 칠한다 — 번짐까지 점마다 색을 바꾸면 겹치거나 되돌아오는 곳에서 나중 색이 앞 빛을
; 덮어 경계가 잘려 보인다(맥에서 확인). dotGlow가 있으면 레이저 점도 무지개다: 번짐은 그 색, 가운데는 무지개 원판.
LaserRender(box, now, dotX, dotY, dotColor, dotW, dotGlow := "") {
    global laserCanvas, laserStrokes, pLaserAttr, LASER_MIN_WIDTH, vw, vh
    x0 := Max(0, box[1]), y0 := Max(0, box[2]), x1 := Min(vw, box[3]), y1 := Min(vh, box[4])
    bw := x1 - x0, bh := y1 - y0
    if (bw <= 0 || bh <= 0)
        return
    glows := [], body := 0, core := 0
    for layer in LaserLayers() {
        if (layer[3] = 0 && layer[2] < 1)
            glows.Push(layer)
        else if (layer[3] = 0)
            body := layer
        else
            core := layer
    }
    ; 획마다 한 번만 준비한다: 점 좌표(GDI+에 한 번에 넘길 버퍼)와 굵기에 쓸 남은 수명.
    ; 굵기는 남은 수명을 부드럽게(smoothstep) 바꾼 값을 쓴다 — 머무는 시간이 끝나는 순간 일정한 비율로
    ; 줄기 시작하면 그 자리에서 굵기가 꺾여 뚝 끊기는 느낌이 난다 (맥과 같다).
    preps := Map()
    for st in laserStrokes {
        n := st.pts.Length
        if (n < 2)
            continue
        buf := Buffer(n * 8), s := []
        for p in st.pts {
            NumPut("float", p[1], "float", p[2], buf, (A_Index - 1) * 8)
            l := LaserLife(p[3], now)
            s.Push(l * l * (3 - 2 * l))
        }
        preps[st] := {buf: buf, s: s, w: Max(st.width, LASER_MIN_WIDTH)}
    }
    dotGlowColor := (dotGlow != "") ? dotGlow : dotColor

    pTmp := 0, gTmp := 0, pPen := 0
    DllCall("gdiplus\GdipCreateBitmapFromScan0", "int", bw, "int", bh, "int", 0, "int", 0xE200B, "ptr", 0, "ptr*", &pTmp)
    if !pTmp
        return
    DllCall("gdiplus\GdipGetImageGraphicsContext", "ptr", pTmp, "ptr*", &gTmp)
    DllCall("gdiplus\GdipSetSmoothingMode", "ptr", gTmp, "int", 4)
    DllCall("gdiplus\GdipTranslateWorldTransform", "ptr", gTmp, "float", -x0, "float", -y0, "int", 0)
    DllCall("gdiplus\GdipCreatePen1", "uint", 0xFF000000, "float", 1, "int", 2, "ptr*", &pPen)
    DllCall("gdiplus\GdipSetPenStartCap", "ptr", pPen, "int", 2) ; 둥근 끝·이음 — 토막끼리 빈틈 없이 이어진다
    DllCall("gdiplus\GdipSetPenEndCap", "ptr", pPen, "int", 2)
    DllCall("gdiplus\GdipSetPenLineJoin", "ptr", pPen, "int", 2)

    ; ---- 둘레 번짐 ----
    if glows.Length {
        levels := [], keep := 1
        for layer in glows {
            keep *= 1 - layer[2]
            levels.Push(Round((1 - keep) * 255)) ; 이 겹까지 쌓인 진하기 (0~255)
        }
        groups := Map() ; 번짐 색 → 그 색의 획들
        for st in preps {
            c := st.rainbow ? st.glow : st.color
            if !groups.Has(c)
                groups[c] := []
            groups[c].Push(st)
        }
        if (dotW && !groups.Has(dotGlowColor))
            groups[dotGlowColor] := []
        for c, list in groups {
            DllCall("gdiplus\GdipGraphicsClear", "ptr", gTmp, "uint", 0xFF000000) ; 검정 = 진하기 0
            for k, layer in glows {
                gray := 0xFF000000 | (levels[k] << 16) | (levels[k] << 8) | levels[k]
                DllCall("gdiplus\GdipSetPenColor", "ptr", pPen, "uint", gray)
                for st in list
                    LaserDrawStroke(gTmp, pPen, st, preps[st], layer[1], false, 0)
                if (dotW && c = dotGlowColor)
                    LaserFillDot(gTmp, dotX, dotY, dotW * layer[1] * 0.6, gray)
            }
            LaserBlendGlow(pTmp, x0, y0, bw, bh, c)
        }
    }

    ; ---- 심지 (불투명이라 바로 긋는다) ----
    g := laserCanvas.graphics
    for st, prep in preps {
        DllCall("gdiplus\GdipSetPenColor", "ptr", pPen, "uint", 0xFF000000 | (st.rainbow ? st.glow : st.color))
        LaserDrawStroke(g, pPen, st, prep, body[1], st.rainbow, 0)
    }
    if dotW {
        r := dotW * body[1] * 0.6
        if (dotGlow != "")
            FillRainbowDisc(g, dotX - r, dotY - r, r * 2, 255, 0)
        else
            LaserFillDot(g, dotX, dotY, r, 0xFF000000 | dotColor)
    }

    ; ---- 가운데 흰빛 줄기 ----
    DllCall("gdiplus\GdipGraphicsClear", "ptr", gTmp, "uint", 0)
    for st, prep in preps {
        DllCall("gdiplus\GdipSetPenColor", "ptr", pPen, "uint", 0xFF000000 | LaserTint(st.rainbow ? st.glow : st.color, core[3]))
        LaserDrawStroke(gTmp, pPen, st, prep, core[1], st.rainbow, core[3])
    }
    if dotW {
        r := dotW * core[1] * 0.6
        if (dotGlow != "")
            FillRainbowDisc(gTmp, dotX - r, dotY - r, r * 2, 255, core[3])
        else
            LaserFillDot(gTmp, dotX, dotY, r, 0xFF000000 | LaserTint(dotColor, core[3]))
    }
    m := Buffer(100, 0) ; 5x5 색 행렬 — "그대로"에서 투명도 칸만 이 겹의 진하기로
    loop 5
        NumPut("float", 1.0, m, ((A_Index - 1) * 5 + (A_Index - 1)) * 4)
    NumPut("float", core[2], m, (3 * 5 + 3) * 4)
    DllCall("gdiplus\GdipSetImageAttributesColorMatrix", "ptr", pLaserAttr, "int", 0, "int", 1, "ptr", m, "ptr", 0, "int", 0)
    DllCall("gdiplus\GdipDrawImageRectRectI", "ptr", g, "ptr", pTmp
        , "int", x0, "int", y0, "int", bw, "int", bh, "int", 0, "int", 0, "int", bw, "int", bh
        , "int", 2, "ptr", pLaserAttr, "ptr", 0, "ptr", 0) ; 2 = UnitPixel

    DllCall("gdiplus\GdipDeletePen", "ptr", pPen)
    DllCall("gdiplus\GdipDeleteGraphics", "ptr", gTmp)
    DllCall("gdiplus\GdipDisposeImage", "ptr", pTmp)
}

; 한 획을 한 겹으로 긋는다(펜 색은 미리 정해 둔다). 굵기가 반 픽셀 단위로 같은 구간은 한 번에 이어
; 긋는다 — 토막마다 따로 그으면 겹마다 수백 번 불러야 해서 무겁다. perPoint면(무지개 심지·흰빛) 토막마다
; 그 점의 색이라 하나씩 긋는다. 꼬리 끝은 거의 점이 될 때까지 가늘어진다(최소 0.5px).
LaserDrawStroke(g, pPen, st, prep, mul, perPoint, mix) {
    n := st.pts.Length, s := prep.s, w := prep.w * mul
    i := 1
    while (i < n) {
        wq := Max(1, Round(w * (s[i] + s[i + 1]))) ; 반 픽셀 단위 굵기 (두 끝 평균 × 2)
        j := i + 1
        if perPoint
            DllCall("gdiplus\GdipSetPenColor", "ptr", pPen, "uint", 0xFF000000 | LaserTint(st.pts[j][4], mix))
        else
            while (j < n && Max(1, Round(w * (s[j] + s[j + 1]))) = wq)
                j++
        DllCall("gdiplus\GdipSetPenWidth", "ptr", pPen, "float", wq / 2)
        DllCall("gdiplus\GdipDrawLines", "ptr", g, "ptr", pPen, "ptr", prep.buf.Ptr + (i - 1) * 8, "int", j - i + 1)
        i := j
    }
}

LaserFillDot(g, x, y, r, argb) {
    pBrush := 0
    DllCall("gdiplus\GdipCreateSolidFill", "uint", argb, "ptr*", &pBrush)
    if pBrush {
        DllCall("gdiplus\GdipFillEllipse", "ptr", g, "ptr", pBrush, "float", x - r, "float", y - r, "float", r * 2, "float", r * 2)
        DllCall("gdiplus\GdipDeleteBrush", "ptr", pBrush)
    }
}

; 회색 밝기로 쌓아 둔 번짐 판을 색 rgb의 빛으로 얹는다: 투명도 = 밝기(빨강 칸), 색 = rgb.
LaserBlendGlow(pTmp, x0, y0, bw, bh, rgb) {
    global laserCanvas, pLaserAttr
    m := Buffer(100, 0)
    NumPut("float", 1.0, m, (0 * 5 + 3) * 4) ; 빨강(=밝기) → 투명도
    NumPut("float", ((rgb >> 16) & 0xFF) / 255, "float", ((rgb >> 8) & 0xFF) / 255, "float", (rgb & 0xFF) / 255, m, (4 * 5 + 0) * 4)
    NumPut("float", 1.0, m, (4 * 5 + 4) * 4)
    DllCall("gdiplus\GdipSetImageAttributesColorMatrix", "ptr", pLaserAttr, "int", 0, "int", 1, "ptr", m, "ptr", 0, "int", 0)
    DllCall("gdiplus\GdipDrawImageRectRectI", "ptr", laserCanvas.graphics, "ptr", pTmp
        , "int", x0, "int", y0, "int", bw, "int", bh, "int", 0, "int", 0, "int", bw, "int", bh
        , "int", 2, "ptr", pLaserAttr, "ptr", 0, "ptr", 0) ; 2 = UnitPixel
}

; 누르기만 해서는 레이저를 시작하지 않는다 — **첫 이동 때** 누른 자리부터 함께 시작한다(LaserAdd·
; LaserSetShape). 누른 순간의 시각으로 찍어두면 누른 뒤 움직이기까지 걸린 시간만큼 시작점이 먼저 늙어서,
; 그 점만 이어 그은 선보다 먼저 줄어들어 보였다(맥에서 선생님이 찾은 원인). 클릭만 하면 아무것도 안 남는다.
; 무지개 레이저인지는 누르는 순간에 정한다 — 긋는 도중에 키를 바꿔도 이번 획은 그대로다.
LaserBegin(x, y) {
    global laserCur, vx, vy, activeDrawColor, activeDrawThickness, rainbowColor
    if !EnsureLaserCanvas()
        return
    laserCur := {pts: [], raw: [], sx: x - vx, sy: y - vy, color: activeDrawColor, width: activeDrawThickness
        , ended: false, shown: false, rainbow: rainbowColor, glow: ""}
}

; ---- 레이저 곡선 ----
; 점은 10ms마다 하나라 빨리 그으면 점 사이가 멀어, 꺾인 직선을 이은 것처럼 울퉁불퉁해 보이고 무지개
; 색도 토막마다 뚝뚝 바뀐다. 점 사이를 Catmull-Rom 곡선으로 약 LASER_STEP_PX 간격의 점으로 채우고,
; 시각과 색조도 양 끝 점 사이에서 이어 준다(맥 smoothLaser와 같은 곡선).
; 한 토막의 곡선은 그 다음 점이 와야 정해지므로, 마지막 토막은 직선으로 두었다가 다음 점이 오거나
; 손을 떼면 곡선으로 바꾼다. raw에는 곡선을 만들 때 쓸 최근 실제 점 네 개만 둔다.
LASER_STEP_PX := 4

; 실제 점 하나를 더한다. 점: [x, y, 시각] 또는 무지개면 [x, y, 시각, 색, 색조]
LaserPushRaw(st, pt) {
    r := st.raw
    r.Push(pt)
    if (r.Length > 4)
        r.RemoveAt(1)
    L := r.Length
    if (L >= 3)
        LaserCurveLast(st, r[L >= 4 ? L - 3 : L - 2], r[L - 2], r[L - 1], r[L])
    st.pts.Push(pt)
}

; 손을 뗄 때 마지막 토막도 곡선으로 (다음 점이 없으니 끝점을 한 번 더 쓴다)
LaserFinishCurve(st) {
    r := st.raw
    L := r.Length
    if (L >= 2)
        LaserCurveLast(st, r[L >= 3 ? L - 2 : L - 1], r[L - 1], r[L], r[L])
}

; st.pts의 마지막 토막(p1 → p2, p2가 맨 끝 점)을 곡선으로 바꾼다. p0·p3은 앞뒤 점.
LaserCurveLast(st, p0, p1, p2, p3) {
    global LASER_STEP_PX
    pts := st.pts
    if !(pts.Length && pts[pts.Length] == p2) ; 그새 다 사라져 목록에서 빠졌으면 그대로 둔다
        return
    dist := Sqrt((p2[1] - p1[1]) ** 2 + (p2[2] - p1[2]) ** 2)
    n := Min(40, Ceil(dist / LASER_STEP_PX))
    if (n < 2)
        return
    pts.Pop()
    hasHue := (p1.Length >= 5 && p2.Length >= 5)
    if hasHue {
        dh := p2[5] - p1[5] ; 359° → 1°는 2°만 간다 (한 바퀴 거꾸로 돌지 않게)
        if (dh > 180)
            dh -= 360
        else if (dh < -180)
            dh += 360
    }
    loop n - 1 {
        t := A_Index / n, t2 := t * t, t3 := t2 * t
        x := 0.5 * (2 * p1[1] + (p2[1] - p0[1]) * t + (2 * p0[1] - 5 * p1[1] + 4 * p2[1] - p3[1]) * t2 + (3 * p1[1] - p0[1] - 3 * p2[1] + p3[1]) * t3)
        y := 0.5 * (2 * p1[2] + (p2[2] - p0[2]) * t + (2 * p0[2] - 5 * p1[2] + 4 * p2[2] - p3[2]) * t2 + (3 * p1[2] - p0[2] - 3 * p2[2] + p3[2]) * t3)
        tm := p1[3] + (p2[3] - p1[3]) * t
        if hasHue {
            h := Mod(p1[5] + dh * t + 360, 360)
            pts.Push([x, y, tm, HueToRGB(h), h])
        } else {
            pts.Push([x, y, tm])
        }
    }
    pts.Push(p2)
}

; 지금 획을 화면에 올린다 (첫 이동 때 한 번)
LaserShow() {
    global laserCur, laserStrokes
    if laserCur.shown
        return
    laserCur.shown := true
    laserStrokes.Push(laserCur)
    SetTimer(LaserTick, 16)
}

; 지금 획이 이미 시작했는가 (도형은 움직이기 전까지 시작하지 않는다 — StrokeMove)
LaserStarted() {
    global laserCur
    return laserCur && laserCur.shown
}

; 점만 더해두면 다음 프레임(LaserTick)이 그린다. 무지개 레이저는 무지개 펜과 같은 빠르기로 색이 돈다.
LaserAdd(x, y) {
    global laserCur, vx, vy, rainbowHue
    if !laserCur
        return
    now := A_TickCount
    x -= vx, y -= vy
    if !laserCur.shown {
        ; 시작점을 첫 이동 시각으로 찍는다 (LaserBegin 설명 참고)
        if laserCur.rainbow {
            laserCur.glow := HueToRGB(rainbowHue)
            LaserPushRaw(laserCur, [laserCur.sx, laserCur.sy, now, laserCur.glow, rainbowHue])
        } else {
            LaserPushRaw(laserCur, [laserCur.sx, laserCur.sy, now])
        }
        LaserShow()
    }
    if laserCur.rainbow {
        q := laserCur.raw[laserCur.raw.Length]
        rgb := NextRainbowColor(Sqrt((x - q[1]) ** 2 + (y - q[2]) ** 2))
        LaserPushRaw(laserCur, [x, y, now, rgb, rainbowHue])
    } else {
        LaserPushRaw(laserCur, [x, y, now])
    }
}

; 레이저로 긋는 도형 — 지금 획의 점들을 도형 테두리(화면 좌표)로 통째로 바꾼다. 끄는 동안 매번
; 지금 시각으로 찍으므로 사라지지 않고, 손을 떼면 도형 전체가 한꺼번에 나이를 먹어 함께 사라진다.
LaserSetShape(pts) {
    global laserCur, vx, vy, rainbowShapeHue, RAINBOW_CYCLE_PX
    if !laserCur
        return
    now := A_TickCount
    local_ := []
    if laserCur.rainbow {
        ; 무지개 레이저 도형: 처음 점부터 그은 거리만큼 색이 돈다(무지개 펜 도형과 같은 빠르기). 사각형·
        ; 직선·화살표는 꼭짓점만 있어 변 하나가 한 색이 되고 모서리에서 색이 뚝 바뀌므로, 변을 따라
        ; 약 5px마다 점을 채워 색이 고르게 돌게 한다. 물결처럼 촘촘한 점은 5px 간격으로 솎는다.
        hue := rainbowShapeHue
        for i, p in pts {
            x := p[1] - vx, y := p[2] - vy
            if !local_.Length {
                local_.Push([x, y, now, HueToRGB(hue)])
                continue
            }
            q := local_[local_.Length]
            dist := Sqrt((x - q[1]) ** 2 + (y - q[2]) ** 2)
            if (dist < 5 && i < pts.Length)
                continue
            k := Max(1, Floor(dist / 5))
            loop k {
                t := A_Index / k
                hue := Mod(hue + dist / k * 360 / RAINBOW_CYCLE_PX, 360)
                local_.Push([q[1] + (x - q[1]) * t, q[2] + (y - q[2]) * t, now, HueToRGB(hue)])
            }
        }
        laserCur.glow := HueToRGB(rainbowShapeHue)
        laserCur.endHue := hue ; 손을 떼면 다음 획이 이 색에서 이어진다 (LaserEnd)
    } else {
        ; 물결은 2px마다 점이 있는데, 레이저는 16ms마다 토막마다 네 겹을 다시 그리므로 그대로 쓰면
        ; 무겁다. 앞 점과 5px보다 가까운 점은 건너뛴다(끝점은 꼭 남긴다).
        for i, p in pts {
            if (local_.Length && i < pts.Length) {
                q := local_[local_.Length]
                if ((p[1] - vx - q[1]) ** 2 + (p[2] - vy - q[2]) ** 2 < 25)
                    continue
            }
            local_.Push([p[1] - vx, p[2] - vy, now])
        }
    }
    laserCur.pts := local_
    LaserShow()
}

; 손을 뗐다 — 남은 꼬리는 제 시간에 맞춰 사라진다. 움직이지 않았으면(클릭만) 아무것도 남지 않는다.
LaserEnd() {
    global laserCur, rainbowHue
    if laserCur {
        laserCur.ended := true
        if laserCur.shown
            LaserFinishCurve(laserCur) ; 도형은 raw가 비어 있어 그대로다
        if (laserCur.shown && laserCur.HasOwnProp("endHue"))
            rainbowHue := laserCur.endHue ; 무지개 도형 다음 획은 이어지는 색에서 (무지개 펜 도형과 같다)
        laserCur := 0
    }
}

; 레이저 펜을 고르면 레이저 점을 띄우기 시작한다 (SetPenKind에서 부른다)
LaserKeyDown() {
    global drawOn
    if (drawOn && EnsureLaserCanvas())
        SetTimer(LaserTick, 16)
}

; 한 프레임: 다 사라진 점을 버리고, 직전 프레임 자리를 비운 뒤 남은 꼬리와 레이저 점을 다시 그린다.
; 그릴 것이 하나도 없으면 멈춘다(마지막으로 비운 자리까지 창에 반영한 다음에).
LaserTick() {
    global laserStrokes, laserLastBox, penKind, drawOn, vx, vy, activeDrawColor, activeDrawThickness
    global laserHold, laserFade, LASER_MIN_WIDTH, laserCanvas, laserCur, rainbowColor, rainbowHue
    global penStroke, penLastX, penLastY
    static lastDot := ""
    Critical ; 그리는 도중에 드로잉 끄기가 끼어들지 않게 — LaserRender 도중에 그림판을 돌려주면 오류가 난다 (DrawPoll 설명 참고)
    if !IsObject(laserCanvas) {
        SetTimer(LaserTick, 0)
        return
    }
    dotOn := drawOn && penKind = "laser"
    mx := 0, my := 0, dotW := 0, dotGlow := ""
    if dotOn {
        ; 무지개 레이저의 점: 둘레 빛은 다음 획이 시작할 색. 긋는 동안에는 지금 획의 빛 색 그대로 두고
        ; 손을 떼면 바뀐다 (긋는 동안 색이 계속 돌면 점의 빛이 깜빡이는 것처럼 보인다).
        if rainbowColor
            dotGlow := (laserCur && laserCur.rainbow && laserCur.glow != "") ? laserCur.glow : HueToRGB(rainbowHue)
        ; 터치·펜으로 긋는 중이면 포인터 좌표를 쓴다 — 진짜 커서는 변환이 늦어 뒤처진다
        if penStroke
            mx := penLastX, my := penLastY
        else
            MouseGetPos(&mx, &my)
        dotW := Max(activeDrawThickness, LASER_MIN_WIDTH)
    }
    ; 레이저 펜을 고른 동안에는 이 타이머가 계속 돈다. 남은 꼬리가 없고 점도 그대로면 다시
    ; 그릴 것이 없으므로 바로 돌아간다 — 가만히 두는 동안 16ms마다 같은 그림을 그리지 않게.
    dotKey := dotOn ? mx "," my "," dotW "," activeDrawColor "," dotGlow : ""
    if (laserStrokes.Length = 0 && dotOn && dotKey = lastDot && IsObject(laserLastBox))
        return
    lastDot := dotKey
    now := A_TickCount
    life := laserHold + laserFade
    maxMul := LaserMaxMul()
    i := laserStrokes.Length
    while (i >= 1) {
        st := laserStrokes[i]
        while (st.pts.Length && now - st.pts[1][3] >= life)
            st.pts.RemoveAt(1)
        if (st.ended && st.pts.Length = 0)
            laserStrokes.RemoveAt(i)
        i -= 1
    }

    ; 이번 프레임에 그릴 범위 (가장 바깥 번짐의 반지름만큼 여유를 둔다)
    box := 0
    for st in laserStrokes {
        pad := Max(st.width, LASER_MIN_WIDTH) * maxMul / 2 + 3
        for p in st.pts
            box := LaserBoxAdd(box, p[1], p[2], pad)
    }
    if dotOn
        box := LaserBoxAdd(box, mx - vx, my - vy, dotW * maxMul * 0.6 + 3)

    if IsObject(laserLastBox)
        LaserClearBox(laserLastBox)
    if IsObject(box)
        LaserRender(box, now, mx - vx, my - vy, activeDrawColor, dotOn ? dotW : 0, dotGlow)

    dirty := laserLastBox
    if IsObject(box)
        dirty := IsObject(dirty) ? [Min(dirty[1], box[1]), Min(dirty[2], box[2]), Max(dirty[3], box[3]), Max(dirty[4], box[4])] : box
    if IsObject(dirty)
        LaserPush(dirty)
    laserLastBox := box
    if !IsObject(box)
        SetTimer(LaserTick, 0)
}

LaserBoxAdd(box, x, y, pad) {
    x1 := Floor(x - pad), y1 := Floor(y - pad), x2 := Ceil(x + pad), y2 := Ceil(y + pad)
    return IsObject(box) ? [Min(box[1], x1), Min(box[2], y1), Max(box[3], x2), Max(box[4], y2)] : [x1, y1, x2, y2]
}

; 드로잉을 끌 때 — 남은 것을 모두 걷는다
LaserClearAll() {
    global laserStrokes, laserCur, laserLastBox, laserCanvas, vw, vh
    SetTimer(LaserTick, 0)
    laserStrokes := []
    laserCur := 0
    laserLastBox := 0
    if !IsObject(laserCanvas)
        return
    ; 비운 모습을 창에 한 번 올려두고 그림판을 돌려준다. 그래야 다음에 창을 띄웠을 때 지난 레이저가
    ; 남아 있지 않다.
    LaserClearBox([0, 0, vw, vh])
    LaserPush()
    DestroyAlphaCanvas(laserCanvas)
    laserCanvas := 0
}

; 시작점에서 끝점 쪽으로 가는 방향을 가장 가까운 0°·45°·90°(와 그 반대쪽)로 맞춘 끝점. 길이는 그대로 둔다.
SnapTo45(x1, y1, x2, y2) {
    dx := x2 - x1, dy := y2 - y1
    len := Sqrt(dx * dx + dy * dy)
    if (len < 1)
        return [x2, y2]
    step := 0.7853981633974483 ; 45도
    a := Round(DllCall("msvcrt\atan2", "double", dy, "double", dx, "double") / step) * step
    return [x1 + Round(len * Cos(a)), y1 + Round(len * Sin(a))]
}

; ================= 칠판 (판서 층 아래에 까는 단색 판) =================
; 화면을 가리고 칠판처럼 쓰고 싶을 때를 위한 층이다. **판서 오버레이 아래에** 깔기 때문에
; 그려둔 내용을 건드리지 않고 배경색만 갈아끼울 수 있고, 지우개도 손볼 필요가 없다 —
; 지우개는 그 자리를 도로 투명하게 만드는 방식이라, 지우면 아래의 칠판이 드러난다.
; (배경을 판서 층 자체에 칠하는 방법도 있지만, 그러면 색을 바꿀 때마다 그림이 지워지고
;  지우개가 "투명하게"가 아니라 "칠판색으로" 칠하도록 고쳐야 해서 훨씬 번거로워진다)
;
; 단색이라 픽셀 단위 투명도가 필요 없어서, 판서 오버레이처럼 화면 크기의 그림판을 들고 있을
; 필요가 없다. 창 배경색만 칠하면 되므로 메모리를 거의 쓰지 않는다.
; 키와 이름은 고정이고, **색과 불투명도는 설정 창에서 바꿀 수 있다**(settings.ini의 [Boards]).
; Q(투명)는 칠판을 걷어내는 자리라 바꿀 것이 없어서 목록에서 색을 갖지 않는다.
BOARD_KEYS := [["q", -1, "투명"], ["w", 0xFFFFFF, "흰색"], ["e", 0x14472F, "초록"], ["r", 0x000000, "검정"]]
BOARD_COLOR_DEFAULTS := [-1, 0xFFFFFF, 0x14472F, 0x000000]
BOARD_COLORS := BOARD_COLOR_DEFAULTS.Clone()
; 칠판의 불투명도(%). 100이면 뒤가 완전히 가려지고, 낮추면 화면이 비쳐 보인다 — 예를 들어
; 흰 칠판을 70%로 두면 아래 자료가 희미하게 비쳐서 그 위에 필기하듯 쓸 수 있다.
BOARD_ALPHAS := [100, 100, 100, 100]
boardColor := -1 ; -1 = 칠판 없음(화면이 그대로 비침)
boardAlpha := 100 ; 지금 깔린 칠판의 불투명도(%)

; 색 배열이 모두 준비된 지금 설정 파일의 값을 덮어씌운다 (위 LoadPalette 설명 참고)
LoadPalette()
boardGui := Gui("+AlwaysOnTop -Caption +ToolWindow +E0x80020", "FocusDraw-Board")
boardGui.Show("x" vx " y" vy " w" vw " h" vh " Hide")
WinSetTransparent(255, boardGui) ; 레이어드 창이지만 불투명하게 — 클릭 통과만 쓴다

; alpha는 불투명도(%)다. 칠판 창은 이미 레이어드 창이라, 창 전체의 투명도만 바꾸면 된다 —
; 판서 층은 **이 창 위에** 따로 있으므로 칠판을 옅게 해도 그려둔 글씨는 그대로 진하게 남는다.
SetBoardColor(color, alpha := 100) {
    global boardColor, boardAlpha, boardGui, drawGui, brushGui, widget, drawOn, brushMode, vx, vy, vw, vh
    boardColor := color
    boardAlpha := Max(5, Min(100, alpha))
    if (!drawOn || color < 0) {
        boardGui.Hide()
        return
    }
    boardGui.BackColor := HexColor(color)
    WinSetTransparent(Round(boardAlpha * 255 / 100), boardGui)
    boardGui.Show("NA x" vx " y" vy " w" vw " h" vh)
    ; 판서 층 **바로 아래**에 끼워 넣는다. 그냥 띄우면 판서 층 위로 올라와 그림을 덮어버린다.
    ; (hWndInsertAfter에 판서 창을 주면 그 뒤에 놓인다 / 0x1 = 크기 유지, 0x2 = 위치 유지,
    ;  0x10 = 활성화하지 않음)
    DllCall("SetWindowPos", "ptr", boardGui.Hwnd, "ptr", drawGui.Hwnd
        , "int", 0, "int", 0, "int", 0, "int", 0, "uint", 0x1 | 0x2 | 0x10)
    ; 칠판을 띄우면서 창 순서가 흔들려 커서 원이 칠판 뒤로 밀리는 일이 없도록, 원과 위젯을
    ; 다시 위로 올려둔다. (칠판은 불투명해서 뒤로 밀리면 커서가 통째로 안 보이게 된다)
    if DllCall("IsWindowVisible", "ptr", widget.Hwnd)
        WinSetAlwaysOnTop(true, widget)
    if DllCall("IsWindowVisible", "ptr", brushGui.Hwnd)
        brushGui.Show("NA")
    ; 지우개 테두리는 칠판의 보색이라, 칠판이 바뀌면 테두리 색도 따라가야 한다
    if (brushMode = "eraser")
        RedrawBrushCursor()
}

; 숫자키 색과 같은 이유로(반복문 안에서 화살표 함수를 바로 쓰면 마지막 값 하나만 남는다) 가둬둔다.
; 색이 아니라 **몇 번째 칠판인지**를 가둬야 한다 — 색은 설정 창에서 바뀔 수 있으므로,
; 누르는 그 순간의 값을 봐야 방금 바꾼 색이 바로 반영된다.
MakeBoardSetter(index) => (*) => SetBoardColor(BOARD_COLORS[index], BOARD_ALPHAS[index])

; ================= +/- 로 크기를 바꿀 때 뜨는 단계 숫자 =================
; 커서 원만으로는 "몇 단계인지"를 알 수 없다 — 특히 굵기 7과 8처럼 두 픽셀 차이는 눈으로
; 구분되지 않는다. 그래서 바꾼 순간에만 커서 옆에 숫자를 띄우고 1초 뒤 사라지게 한다.
; 커서 원 옆(원의 가장자리 바깥)에 붙여서, 지우개처럼 원이 커져도 숫자가 원 안에 묻히지 않는다.
; 모양은 Windows 풍선 도움말(작업표시줄 아이콘에 마우스를 올리면 뜨는 그것)에 맞춘다 —
; 흰 바탕에 가는 회색 테두리, 둥근 모서리, 진한 글자. 처음엔 검은 알약 모양으로 만들었는데
; 화면 위에 혼자 튀어서, 시스템이 쓰는 모양을 그대로 따르는 쪽이 눈에 덜 걸린다.
; 창 배경색으로는 테두리를 만들 수 없어서(테마 적용된 창에서는 Text 컨트롤 배경색이 안 먹는다)
; 다른 창들과 같은 방식으로 알파 캔버스에 GDI+로 직접 그린다.
STEP_BADGE_W := 30, STEP_BADGE_H := 24 ; 배지 크기
STEP_BADGE_MS := 500 ; 화면에 머무는 시간(ms)
STEP_BADGE_GAP := 22 ; 커서 중심에서 배지 왼쪽 위까지의 거리 — **굵기와 무관하게 늘 같다**
stepGui := Gui("+AlwaysOnTop -Caption +ToolWindow +E0x80020", "FocusDraw-Step")
stepGui.Show("w" STEP_BADGE_W " h" STEP_BADGE_H " Hide")
stepCanvas := ""
stepFontFamily := 0, stepFont := 0, stepFormat := 0

; 글꼴과 정렬은 한 번만 만들어 두고 계속 쓴다 (누를 때마다 만들면 낭비다)
InitStepBadgeFont() {
    global stepFontFamily, stepFont, stepFormat
    if stepFont
        return
    DllCall("gdiplus\GdipCreateFontFamilyFromName", "wstr", "Segoe UI", "ptr", 0, "ptr*", &stepFontFamily)
    if !stepFontFamily ; 없는 PC를 대비한 대체 글꼴
        DllCall("gdiplus\GdipCreateFontFamilyFromName", "wstr", "Malgun Gothic", "ptr", 0, "ptr*", &stepFontFamily)
    if stepFontFamily
        DllCall("gdiplus\GdipCreateFont", "ptr", stepFontFamily, "float", 12, "int", 0, "int", 2, "ptr*", &stepFont) ; 2 = 픽셀 단위
    DllCall("gdiplus\GdipCreateStringFormat", "int", 0, "int", 0, "ptr*", &stepFormat)
    if stepFormat {
        DllCall("gdiplus\GdipSetStringFormatAlign", "ptr", stepFormat, "int", 1)     ; 가로 가운데
        DllCall("gdiplus\GdipSetStringFormatLineAlign", "ptr", stepFormat, "int", 1) ; 세로 가운데
    }
}

; 모서리가 둥근 사각형 경로. 네 귀퉁이를 90도 호로 잇는다.
RoundedRectPath(x, y, w, h, r) {
    path := 0
    DllCall("gdiplus\GdipCreatePath", "int", 0, "ptr*", &path)
    if !path
        return 0
    d := r * 2
    DllCall("gdiplus\GdipAddPathArc", "ptr", path, "float", x, "float", y, "float", d, "float", d, "float", 180, "float", 90)
    DllCall("gdiplus\GdipAddPathArc", "ptr", path, "float", x + w - d, "float", y, "float", d, "float", d, "float", 270, "float", 90)
    DllCall("gdiplus\GdipAddPathArc", "ptr", path, "float", x + w - d, "float", y + h - d, "float", d, "float", d, "float", 0, "float", 90)
    DllCall("gdiplus\GdipAddPathArc", "ptr", path, "float", x, "float", y + h - d, "float", d, "float", d, "float", 90, "float", 90)
    DllCall("gdiplus\GdipClosePathFigure", "ptr", path)
    return path
}

; 글자가 들어갈 만큼의 배지 너비. 단계는 한두 글자지만 투명도는 "100%"까지 가므로,
; 늘 같은 폭으로 두면 글자가 테두리에 닿는다.
StepBadgeWidth(text) {
    global STEP_BADGE_W
    return Max(STEP_BADGE_W, 12 + StrLen(String(text)) * 9)
}

DrawStepBadge(text, w) {
    global stepCanvas, stepFont, stepFormat, STEP_BADGE_H
    InitStepBadgeFont()
    h := STEP_BADGE_H
    DestroyAlphaCanvas(stepCanvas)
    stepCanvas := CreateAlphaCanvas(w, h)
    if !stepCanvas.graphics
        return false
    g := stepCanvas.graphics
    DllCall("gdiplus\GdipGraphicsClear", "ptr", g, "uint", 0x00000000)
    ; 테두리가 잘리지 않도록 반 픽셀 안쪽에 그린다
    path := RoundedRectPath(0.5, 0.5, w - 1, h - 1, 5)
    if path {
        fill := 0
        DllCall("gdiplus\GdipCreateSolidFill", "uint", 0xFFFFFFFF, "ptr*", &fill)
        if fill {
            DllCall("gdiplus\GdipFillPath", "ptr", g, "ptr", fill, "ptr", path)
            DllCall("gdiplus\GdipDeleteBrush", "ptr", fill)
        }
        border := 0
        DllCall("gdiplus\GdipCreatePen1", "uint", 0xFFA0A0A0, "float", 1, "int", 2, "ptr*", &border)
        if border {
            DllCall("gdiplus\GdipDrawPath", "ptr", g, "ptr", border, "ptr", path)
            DllCall("gdiplus\GdipDeletePen", "ptr", border)
        }
        DllCall("gdiplus\GdipDeletePath", "ptr", path)
    }
    if (stepFont && stepFormat) {
        rect := Buffer(16, 0)
        NumPut("Float", 0, rect, 0), NumPut("Float", 0, rect, 4)
        NumPut("Float", w, rect, 8), NumPut("Float", h, rect, 12)
        ink := 0
        DllCall("gdiplus\GdipCreateSolidFill", "uint", 0xFF1A1A1A, "ptr*", &ink)
        if ink {
            DllCall("gdiplus\GdipDrawString", "ptr", g, "wstr", String(text), "int", -1
                , "ptr", stepFont, "ptr", rect, "ptr", stepFormat, "ptr", ink)
            DllCall("gdiplus\GdipDeleteBrush", "ptr", ink)
        }
    }
    DllCall("gdiplus\GdipFlush", "ptr", g, "int", 0)
    return true
}

ShowStepNumber(step) {
    global stepGui, stepCanvas, drawOn, STEP_BADGE_H, STEP_BADGE_GAP, STEP_BADGE_MS
    if !drawOn
        return
    badgeW := StepBadgeWidth(step)
    if !DrawStepBadge(step, badgeW)
        return
    MouseGetPos(&mx, &my)
    ; **커서 중심에서 늘 같은 거리**에 둔다. 예전에는 커서 원 가장자리에 붙여서, 굵기를 바꿀
    ; 때마다 숫자가 조금씩 움직여 눈이 따라가야 했다.
    x := mx + STEP_BADGE_GAP, y := my + STEP_BADGE_GAP
    if (x + badgeW > A_ScreenWidth)
        x := mx - STEP_BADGE_GAP - badgeW
    if (y + STEP_BADGE_H > A_ScreenHeight)
        y := my - STEP_BADGE_GAP - STEP_BADGE_H
    stepGui.Show("NA")
    PushCanvasToWindow(stepGui.Hwnd, stepCanvas, x, y)
    SetTimer(HideStepNumber, -STEP_BADGE_MS) ; 잠깐 보였다가 사라짐 (다시 누르면 시계가 새로 시작된다)
}

HideStepNumber() {
    global stepGui
    stepGui.Hide()
}

; ================= 드로잉 커서 (그어질 선을 미리 보여주는 원) =================
; 이 원은 **Windows 커서가 아니라 우리가 직접 띄우는 작은 창**이다. 커서로 만들면 Windows가
; "마우스 포인터 크기" 설정(CursorBaseSize) 배율을 마지막에 한 번 더 곱해서 그리기 때문에,
; 지름을 아무리 정확히 계산해 넘겨도 화면에서는 그만큼 커지고 늘어나느라 흐려진다. 넘기는
; 비트맵 크기를 시스템 크기에 맞춰봐도 배율은 그 위에 또 걸려서 소용이 없었다.
; 창으로 그리면 선을 그리는 것과 **같은 GDI+ 경로**를 타므로, 크기·색·투명도·가장자리 처리가
; 계산으로 맞추는 게 아니라 구조적으로 같아진다. 대신 진짜 커서는 완전히 투명하게 만들어 감춘다.
;
; E0x20(WS_EX_TRANSPARENT)을 준 창은 MouseGetPos와 WindowFromPoint 양쪽에서 건너뛴다(직접
; 확인함). 그래서 이 창이 커서 밑에 깔려 있어도 DrawPoll의 "커서 아래 창이 판서 오버레이인가"
; 판정을 가리지 않는다 — 위젯 클릭이나 캡처 도구 감지가 그대로 동작한다.
brushGui := Gui("+AlwaysOnTop -Caption +ToolWindow +E0x80020", "FocusDraw-Brush")
brushGui.Show("w16 h16 Hide")
brushCanvas := ""
brushPad := 0 ; 원의 중심이 창 왼쪽 위에서 얼마나 떨어져 있는지 (창을 놓을 위치 계산에 쓴다)
brushMode := "pen" ; "pen" = 그어질 선을 담은 원 / "eraser" = 지워질 범위를 보여주는 테두리 원

; 지우개 테두리 원의 색 — **지금 깔려 있는 칠판의 보색**으로 정한다. 칠판 색을 R·G·B 채널마다
; 255에서 뺀 값이라, 흰 칠판이면 검정 / 검정 칠판이면 흰색 / 초록 칠판(14472F)이면 연분홍
; (EBB8D0)이 되어 어느 칠판에서도 테두리가 배경에 묻히지 않는다.
; 칠판이 없을 때(투명)는 아래로 무엇이 비칠지 알 수 없으므로 검정을 기본으로 쓴다.
EraserRingColor() {
    global boardColor
    if (boardColor < 0)
        return 0x000000
    r := 255 - ((boardColor >> 16) & 0xFF)
    g := 255 - ((boardColor >> 8) & 0xFF)
    b := 255 - (boardColor & 0xFF)
    return (r << 16) | (g << 8) | b
}

; 오른쪽 버튼을 누르면 지우개 범위를, 떼면 다시 펜을 보여준다. 바뀔 때만 다시 그린다.
SetBrushMode(mode) {
    global brushMode, drawOn
    if (!drawOn || brushMode = mode)
        return
    brushMode := mode
    RedrawBrushCursor()
}

; 판서 중에는 진짜 마우스 커서를 완전히 감추고 우리가 그리는 원으로 대신한다. 그런데 판서
; 오버레이 위로 다른 창이 올라오면(Win+Shift+S 캡처 도구, 위젯 등) 그 창이 우리 원보다 위에
; 그려져서, 커서가 아예 없는 것처럼 보인다 — 캡처 범위를 끌 수가 없다.
; 그래서 커서 아래 창이 판서 오버레이가 아닐 때는 진짜 커서를 잠시 돌려주고 원을 감춘다.
; 판정은 이미 드래그를 걸러낼 때 쓰던 것과 같은 것(winUnder)을 그대로 쓴다. 우리 원은 클릭
; 통과 창이라 MouseGetPos가 건너뛰므로 스스로를 "다른 창"으로 착각할 일이 없다.
; **지금 어떤 상태인지는 따로 기억하지 않고 화면에서 직접 읽는다.**
; 예전에는 "위젯 위인가"를 변수에 적어두고 값이 바뀔 때만 손댔는데, 그 변수와 실제 화면이
; 한 번 어긋나면(드로잉을 켜는 순간 커서가 이미 위젯 위에 있는 경우 등) 영영 복구되지 않았다 —
; 겉으로는 화살표가 떠 있는데 기록은 "오버레이 위"라서, 오버레이로 돌아가도 아무 일도 하지
; 않는 상태로 굳었다. 원이 떠 있는지를 그대로 물어보면 어긋날 수가 없다.
UpdateDrawCursorForWindow(winUnder) {
    global drawOn, drawGui, brushGui
    if !drawOn
        return
    wantCircle := (winUnder = drawGui.Hwnd) ; 오버레이 위에서만 원을 쓴다
    hasCircle := DllCall("IsWindowVisible", "ptr", brushGui.Hwnd) ? true : false
    if (wantCircle = hasCircle)
        return ; 이미 맞다 (10ms마다 커서를 다시 씌우면 낭비다)
    if wantCircle {
        UpdateCursorHiddenState() ; 진짜 커서를 다시 감추고
        brushGui.Show("NA")       ; 원을 도로 띄운다
    } else {
        RestoreSystemCursor()     ; 위젯·캡처 도구 위에서는 평소 화살표를 돌려준다
        brushGui.Hide()
    }
}

; 지름은 선 굵기 그대로, 색과 투명도도 그어질 선 그대로 보여준다.
RedrawBrushCursor() {
    global brushGui, brushCanvas, brushPad, brushMode, activeDrawColor, activeDrawThickness, rainbowColor
    ; 펜은 그어질 선 그대로, 지우개는 지워질 범위 그대로 — 둘 다 실제 크기를 보여준다.
    d := (brushMode = "eraser") ? EraserThickness() : activeDrawThickness
    ; 창을 놓는 위치는 정수여야 하는데 지름이 홀수면 중심이 반 픽셀에 걸린다. 그래서 중심을
    ; 정수 자리(brushPad)에 두고, 원 쪽을 반 픽셀 밀어 그린다 — 그래야 실제 자리와 정확히 겹친다.
    brushPad := Ceil(d / 2) + 2 ; 창 위치·크기는 정수여야 한다
    size := brushPad * 2
    DestroyAlphaCanvas(brushCanvas)
    brushCanvas := CreateAlphaCanvas(size, size)
    if !brushCanvas.graphics
        return
    DllCall("gdiplus\GdipGraphicsClear", "ptr", brushCanvas.graphics, "uint", 0x00000000)
    if (brushMode = "eraser") {
        ; 지우개는 안쪽이 비치는 가느다란 테두리 원 — 지울 범위를 가리지 않으면서
        ; 어디까지 지워지는지 보여준다. 색은 칠판의 보색이라 어느 칠판에서도 또렷하다.
        pen := 0
        DllCall("gdiplus\GdipCreatePen1", "uint", 0xFF000000 | EraserRingColor(), "float", 1, "int", 2, "ptr*", &pen)
        if pen {
            DllCall("gdiplus\GdipDrawEllipse", "ptr", brushCanvas.graphics, "ptr", pen
                , "float", brushPad - d / 2, "float", brushPad - d / 2, "float", d, "float", d)
            DllCall("gdiplus\GdipDeletePen", "ptr", pen)
        }
    } else if rainbowColor {
        ; 무지개 펜·무지개 레이저는 색이 정해져 있지 않으므로 무지개 원판으로 보여준다
        FillRainbowDisc(brushCanvas.graphics, brushPad - d / 2, brushPad - d / 2, d, ActiveARGB() >> 24)
    } else {
        brush := 0
        DllCall("gdiplus\GdipCreateSolidFill", "uint", ActiveARGB(), "ptr*", &brush)
        if brush {
            DllCall("gdiplus\GdipFillEllipse", "ptr", brushCanvas.graphics, "ptr", brush
                , "float", brushPad - d / 2, "float", brushPad - d / 2, "float", d, "float", d)
            DllCall("gdiplus\GdipDeleteBrush", "ptr", brush)
        }
    }
    DllCall("gdiplus\GdipFlush", "ptr", brushCanvas.graphics, "int", 0)
    MoveBrushCursor()
}

; 선은 마우스 위치를 중심으로 그려지므로(그 점은 해당 픽셀의 좌상단 모서리다) 원의 중심도
; 같은 점에 둔다. 창 위치와 그림을 한 번에 올려서 따라다녀도 깜빡이지 않는다.
; 좌표를 주면 그 자리로, 안 주면 마우스 커서 자리로 옮긴다. 터치·펜은 진짜 커서가 늦게
; 따라오므로 포인터 메시지에서 받은 좌표를 직접 넘겨준다.
MoveBrushCursor(px := "", py := "") {
    global drawOn, brushGui, brushCanvas, brushPad, brushMode
    if (!drawOn || !IsObject(brushCanvas) || !brushCanvas.graphics)
        return
    if (px = "" || py = "")
        MouseGetPos(&mx, &my)
    else
        mx := px, my := py
    ; 펜의 투명도는 원을 그릴 때 이미 색에 담겨 있다(ActiveARGB). 지우개 테두리는 안내선이라 또렷하게 둔다.
    PushCanvasToWindow(brushGui.Hwnd, brushCanvas, mx - brushPad, my - brushPad, 255)
}

; UpdateLayeredWindow은 부를 때마다 창 전체(가상 화면 전체 크기)를 합성하기 때문에,
; 판서 중 10ms마다 호출하면 그만큼 CPU를 많이 먹는다. UpdateLayeredWindowIndirect는
; "실제로 바뀐 영역(prcDirty)"만 알려줄 수 있어서, 선 하나 그릴 때 화면 전체가 아니라
; 그 선 주변 작은 사각형만 다시 합성하면 되므로 훨씬 가볍다.
ulwPtDst := Buffer(8, 0)
NumPut("Int", vx, ulwPtDst, 0)
NumPut("Int", vy, ulwPtDst, 4)
ulwSize := Buffer(8, 0)
NumPut("Int", vw, ulwSize, 0)
NumPut("Int", vh, ulwSize, 4)
ulwPtSrc := Buffer(8, 0) ; 항상 (0,0) — memDC 전체가 소스
ulwBlend := Buffer(4, 0)
NumPut("UChar", 0, ulwBlend, 0)   ; AC_SRC_OVER
NumPut("UChar", 0, ulwBlend, 1)   ; flags
NumPut("UChar", 255, ulwBlend, 2) ; SourceConstantAlpha — 판 전체에는 곱하지 않는다(투명도는 획마다 — StartAlpha 참고)
NumPut("UChar", 1, ulwBlend, 3)   ; AC_SRC_ALPHA
ulwDirtyRect := Buffer(16, 0)
ulwInfo := Buffer(80, 0) ; UPDATELAYEREDWINDOWINFO (x64)
NumPut("UInt", 80, ulwInfo, 0)            ; cbSize
NumPut("Ptr", ulwPtDst.Ptr, ulwInfo, 16)  ; pptDst
NumPut("Ptr", ulwSize.Ptr, ulwInfo, 24)   ; psize
NumPut("Ptr", memDC, ulwInfo, 32)         ; hdcSrc
NumPut("Ptr", ulwPtSrc.Ptr, ulwInfo, 40)  ; pptSrc
NumPut("Ptr", ulwBlend.Ptr, ulwInfo, 56)  ; pblend
NumPut("UInt", 2, ulwInfo, 64)            ; dwFlags = ULW_ALPHA

; minX~maxY(로컬 좌표)를 생략하면 화면 전체를, 지정하면 그 영역만 다시 합성한다.
UpdateOverlay(minX := -1, minY := -1, maxX := -1, maxY := -1) {
    global drawGui, ulwInfo, ulwDirtyRect, vw, vh
    if minX = -1 {
        NumPut("Ptr", 0, ulwInfo, 72) ; prcDirty = NULL → 전체 갱신
    } else {
        NumPut("Int", Max(0, minX), ulwDirtyRect, 0)
        NumPut("Int", Max(0, minY), ulwDirtyRect, 4)
        NumPut("Int", Min(vw, maxX), ulwDirtyRect, 8)
        NumPut("Int", Min(vh, maxY), ulwDirtyRect, 12)
        NumPut("Ptr", ulwDirtyRect.Ptr, ulwInfo, 72)
    }
    DllCall("UpdateLayeredWindowIndirect", "ptr", drawGui.Hwnd, "ptr", ulwInfo)
}
UpdateOverlay()

; 설정 창의 드로잉 "투명도"(DrawOpacity)는 **긋기 시작할 때의 선 투명도**다. 예전에는 판서 전체에 곱했는데,
; 그러면 50%로 두고 마우스 휠을 100%까지 올려도 결과는 여전히 50%였다. 휠 숫자는 **절대값**이어야 하므로
; 판에는 곱하지 않고, 드로잉을 켜거나 숫자키를 누를 때 이 값을 그 색의 투명도(keyAlpha, %)에 곱한
; 값으로 시작한다. 휠은 그 뒤 숫자를 그대로 바꾼다. 5% 아래로는 내리지 않는다(AdjustDrawAlpha와 같다).
StartAlpha(keyAlpha) {
    global DrawOpacity
    return Max(5, Min(100, Round(DrawOpacity * keyAlpha / 100)))
}

; GDI로 그린 픽셀은 알파 값이 채워지지 않으므로, 그린 영역만 알파를 255로 채워준다.
; 실제로 훑은 사각형 범위를 돌려줘서, 호출한 쪽이 그 부분만 화면에 다시 합성하면 되게 한다.
PatchAlpha(x1, y1, x2, y2) {
    global ppvBits, vw, vh, activeDrawThickness
    pad := Ceil(activeDrawThickness) + 2 ; 굵기는 실수일 수 있는데 여기 계산은 픽셀 단위라 올림한다
    minX := Max(0, Min(x1, x2) - pad)
    maxX := Min(vw - 1, Max(x1, x2) + pad)
    minY := Max(0, Min(y1, y2) - pad)
    maxY := Min(vh - 1, Max(y1, y2) + pad)
    stride := vw * 4
    loop (maxY - minY + 1) {
        yy := minY + A_Index - 1
        rowBase := ppvBits + yy * stride
        loop (maxX - minX + 1) {
            px := rowBase + (minX + A_Index - 1) * 4
            ; 배경값(1,1,1)과 조금이라도 다르면 펜이 지나간 픽셀이다. 예전에는 "채널 하나라도
            ; 1보다 크면"으로 봤는데, 그러면 검정(0,0,0)으로 그은 선이 조건에 걸리지 않아
            ; 알파가 1로 남고 화면에 아예 안 보이는 문제가 있었다.
            if (NumGet(px, 0, "UChar") != 1 || NumGet(px, 1, "UChar") != 1 || NumGet(px, 2, "UChar") != 1)
                NumPut("UChar", 255, px, 3)
        }
    }
    return [minX, minY, maxX + 1, maxY + 1]
}

; ================= 도형 테두리만 훑기 =================
; 도형 미리보기가 느렸던 이유는 알파를 채울 때 도형을 감싸는 네모 "전체"를 픽셀 하나씩
; 훑었기 때문이다. 테두리만 그리는데도 빈 안쪽까지 훑다 보니, 큰 사각형이나 원은 한 프레임에
; 수십만 픽셀이 되어 드래그가 뚝뚝 끊겼다. (자유선이 멀쩡했던 건 방금 지나간 짧은 구간만
; 훑기 때문) 테두리를 짧은 토막으로 나눠 각 토막 둘레의 작은 네모만 훑으면, 훑는 양이
; 네모 넓이가 아니라 테두리 넓이로 줄어든다.
PatchAlphaPolyline(pts, segLen := 24) {
    global vw, vh
    uMinX := vw, uMinY := vh, uMaxX := 0, uMaxY := 0
    loop pts.Length - 1 {
        ax := pts[A_Index][1], ay := pts[A_Index][2]
        bx := pts[A_Index + 1][1], by := pts[A_Index + 1][2]
        dx := bx - ax, dy := by - ay
        parts := Max(1, Ceil(Sqrt(dx * dx + dy * dy) / segLen))
        loop parts {
            t0 := (A_Index - 1) / parts, t1 := A_Index / parts
            box := PatchAlpha(Round(ax + dx * t0), Round(ay + dy * t0), Round(ax + dx * t1), Round(ay + dy * t1))
            uMinX := Min(uMinX, box[1]), uMinY := Min(uMinY, box[2])
            uMaxX := Max(uMaxX, box[3]), uMaxY := Max(uMaxY, box[4])
        }
    }
    return [uMinX, uMinY, uMaxX, uMaxY]
}

; 펜이 지나간 범위(굵기만큼 여유를 둔다). GDI+로 그릴 때는 픽셀을 훑을 필요가 없으므로,
; 되돌리기와 화면 갱신에 쓸 범위만 이렇게 계산해서 쓴다. 자유선과 도형이 함께 쓴다.
PenDirtyBox(x1, y1, x2, y2, thickness := 0) {
    global vw, vh, activeDrawThickness
    if !thickness
        thickness := activeDrawThickness
    pad := Ceil(thickness / 2) + 6 ; 펜 굵기의 절반 + 부드럽게 처리한 가장자리만큼 여유 (굵기가 실수라 올림)
    return [Max(0, Min(x1, x2) - pad), Max(0, Min(y1, y2) - pad)
        , Min(vw, Max(x1, x2) + pad + 1), Min(vh, Max(y1, y2) + pad + 1)]
}

; ================= 화살표·물결의 모양 계산 =================
; 그리는 쪽과 "되돌릴 범위를 계산하는 쪽"이 반드시 같은 값을 써야 해서, 계산은 여기 한 곳에만 둔다.

; 화살표 머리의 기준점들. 머리 밑변의 중심(bx, by)과 좌우 끝점, 그리고 머리가 몸통 선
; 바깥으로 삐져나가는 폭(halfW)을 돌려준다. 길이가 거의 0이면 방향을 정할 수 없어 0을 돌려준다.
ArrowGeometry(x1, y1, x2, y2) {
    global activeDrawThickness
    dx := x2 - x1, dy := y2 - y1
    len := Sqrt(dx * dx + dy * dy)
    if (len < 1)
        return 0
    ux := dx / len, uy := dy / len ; 진행 방향
    px := -uy, py := ux            ; 그에 수직인 방향
    ; 머리는 선 굵기에 비례해야 한다 — 굵은 펜에 작은 머리가 붙으면 화살표로 보이지 않는다.
    ; 다만 짧게 끌었을 때 머리가 전체를 잡아먹지 않도록 길이의 절반으로 제한한다.
    head := Min(Max(activeDrawThickness * 4, 14), len * 0.5)
    halfW := head * 0.45 ; 머리 끝 각도가 약 48도가 되는 폭
    bx := x2 - ux * head, by := y2 - uy * head
    return {bx: bx, by: by, halfW: halfW
        , lx: bx + px * halfW, ly: by + py * halfW
        , rx: bx - px * halfW, ry: by - py * halfW}
}

; 물결의 진폭(굽이 높이). 끈 높이가 아니라 선 굵기에 매어 둔 이유는, 글 밑에 밑줄 긋듯
; 가로로 곧게 끌었을 때도 물결이 나와야 하기 때문이다(높이에 매면 곧게 끌 때 0이라 직선이 된다).
WaveAmplitude() {
    global activeDrawThickness
    return Max(activeDrawThickness * 0.75, 3)
}

; 한 굽이의 길이. 진폭과 따로 두었다 — 진폭만 줄이면 물결이 더 완만해지고, 둘을 같이 줄이면
; 같은 모양이 작아진다. 지금은 굵기 6에서 높이 4.5, 굽이 길이 33 — 글 밑에 치는 물결 밑줄에
; 가까운, 작고 촘촘한 물결이다.
WaveLength() {
    global activeDrawThickness
    return Max(activeDrawThickness * 5.5, 18)
}

; 시작점에서 끝점으로 가는 선 위에 사인파를 얹은 점들.
WavePoints(x1, y1, x2, y2) {
    dx := x2 - x1, dy := y2 - y1
    len := Sqrt(dx * dx + dy * dy)
    amp := WaveAmplitude()
    if (len < amp) ; 한 굽이도 안 되게 짧으면 그냥 직선
        return [[x1, y1], [x2, y2]]
    ux := dx / len, uy := dy / len
    px := -uy, py := ux
    ; 굽이가 반 토막으로 끝나면 끝이 어중간해 보이므로, 굽이 수를 정수로 맞춰 딱 떨어지게 한다
    cycles := Max(1, Round(len / WaveLength()))
    ; 굽이가 짧아질수록 점을 촘촘히 찍어야 각져 보이지 않는다. 2px 간격이면 한 굽이(33px)에
    ; 열일곱 점이라 부드럽게 처리한 뒤 곡선과 구분되지 않는다.
    count := Max(2, Ceil(len / 2) + 1)
    pts := []
    loop count {
        t := (A_Index - 1) / (count - 1)
        d := t * len
        off := amp * Sin(t * cycles * 6.283185307179586)
        pts.Push([x1 + ux * d + px * off, y1 + uy * d + py * off])
    }
    return pts
}

; 도형 테두리를 따라가는 점들. 원은 크기에 맞춰 잘게 쪼개야 토막마다 훑는 네모가 작게 유지된다.
; fine: 레이저용 — 원을 약 5px 간격으로 찍어 큰 원도 각져 보이지 않게 한다 (맥 레이저 도형과 같은 매끄러움)
ShapeOutlinePoints(mode, x1, y1, x2, y2, fine := false) {
    if (mode = "line")
        return [[x1, y1], [x2, y2]]
    if (mode = "wave")
        return WavePoints(x1, y1, x2, y2)
    if (mode = "arrow") {
        g := ArrowGeometry(x1, y1, x2, y2)
        if !g
            return [[x1, y1], [x2, y2]]
        ; 몸통 → 머리 한쪽 → 꼭짓점 → 반대쪽 → 다시 밑변 (한붓그리기로 이어지는 순서)
        return [[x1, y1], [g.bx, g.by], [g.lx, g.ly], [x2, y2], [g.rx, g.ry], [g.bx, g.by]]
    }
    lx := Min(x1, x2), rx := Max(x1, x2), ty := Min(y1, y2), by := Max(y1, y2)
    if (mode = "rect")
        return [[lx, ty], [rx, ty], [rx, by], [lx, by], [lx, ty]]
    cx := (lx + rx) / 2, cy := (ty + by) / 2
    ax := (rx - lx) / 2, ay := (by - ty) / 2
    steps := Max(16, Min(160, Round((ax + ay) / 6)))
    if fine
        steps := Max(steps, Min(600, Ceil(6.283185307179586 * Sqrt((ax * ax + ay * ay) / 2) / 5)))
    pts := []
    loop steps + 1 {
        t := (A_Index - 1) * 6.283185307179586 / steps
        pts.Push([cx + ax * Cos(t), cy + ay * Sin(t)])
    }
    return pts
}

; 스냅샷에서 지정한 네모만 되돌린다. 미리보기는 직전 프레임이 그린 자리만 지우면 되므로
; 화면 전체(수 MB)를 매 프레임 복사할 필요가 없다.
RestoreSnapshotBox(box) {
    global ppvBits, snapshotBuf, vw, vh
    if !IsObject(snapshotBuf)
        return
    minX := Max(0, box[1]), minY := Max(0, box[2])
    maxX := Min(vw, box[3]), maxY := Min(vh, box[4])
    if (maxX <= minX || maxY <= minY)
        return
    stride := vw * 4
    rowBytes := (maxX - minX) * 4
    loop (maxY - minY) {
        off := (minY + A_Index - 1) * stride + minX * 4
        DllCall("RtlCopyMemory", "ptr", ppvBits + off, "ptr", snapshotBuf.Ptr + off, "uptr", rowBytes)
    }
}

; ---- 반투명 획 전용 판 (위 inkLayerBuf 설명 참고) ----
; 판을 쓸 수 있으면 true(없으면 이때 만든다). 만들지 못하면 예전 방식(덮어쓰기)으로 그린다.
InkLayerReady() => EnsureInkLayer()

; 판의 box 범위를 완전히 투명하게 비운다.
InkClearBox(box) {
    global inkLayerBuf, vw, vh
    minX := Max(0, box[1]), minY := Max(0, box[2])
    maxX := Min(vw, box[3]), maxY := Min(vh, box[4])
    if (maxX <= minX || maxY <= minY)
        return
    stride := vw * 4
    rowBytes := (maxX - minX) * 4
    loop (maxY - minY)
        DllCall("RtlZeroMemory", "ptr", inkLayerBuf.Ptr + (minY + A_Index - 1) * stride + minX * 4, "uptr", rowBytes)
}

; 새 획이나 도형을 시작할 때 부른다. 지난번에 쓴 자리를 비우고, 겹쳐 얹을 바탕으로 지금 그림을 떠둔다.
; alpha가 100이면 판을 거칠 필요가 없어서 아무것도 하지 않는다.
BeginInkStroke(alpha) {
    global inkDirty, inkStrokeAlpha
    inkStrokeAlpha := 0
    if (alpha >= 100 || !InkLayerReady())
        return
    if (inkDirty.Length = 4)
        InkClearBox(inkDirty)
    inkDirty := []
    if !SaveSnapshot()
        return ; 복사본을 못 만들면 겹쳐 얹을 바탕이 없으니 예전 방식(덮어쓰기)으로 긋는다
    inkStrokeAlpha := alpha
}

; 판에 그린 범위를 기록해둔다 (다음 획을 시작할 때 이 자리만 비우면 된다)
InkMarkDirty(box) {
    global inkDirty
    if (inkDirty.Length != 4) {
        inkDirty := box.Clone()
        return
    }
    inkDirty[1] := Min(inkDirty[1], box[1]), inkDirty[2] := Min(inkDirty[2], box[2])
    inkDirty[3] := Max(inkDirty[3], box[3]), inkDirty[4] := Max(inkDirty[4], box[4])
}

; box 범위를 "획을 긋기 전 모습 + 판을 inkStrokeAlpha로 겹쳐 얹은 것"으로 다시 만든다.
; 판에는 이 획 전체가 들어 있으므로, 범위 안이 몇 번 다시 만들어져도 결과는 늘 같다.
InkCompose(box) {
    global pShapeGraphics, pInkLayer, pInkAttr, inkAttrAlpha, inkStrokeAlpha, vw, vh
    minX := Max(0, box[1]), minY := Max(0, box[2])
    maxX := Min(vw, box[3]), maxY := Min(vh, box[4])
    if (maxX <= minX || maxY <= minY)
        return
    RestoreSnapshotBox([minX, minY, maxX, maxY])
    if (inkAttrAlpha != inkStrokeAlpha) {
        ; 5x5 색 행렬 — 대각선이 1인 "그대로" 행렬에서 투명도 칸만 원하는 값으로 둔다
        m := Buffer(100, 0)
        loop 5
            NumPut("float", 1.0, m, ((A_Index - 1) * 5 + (A_Index - 1)) * 4)
        NumPut("float", inkStrokeAlpha / 100, m, (3 * 5 + 3) * 4)
        DllCall("gdiplus\GdipSetImageAttributesColorMatrix", "ptr", pInkAttr, "int", 0, "int", 1, "ptr", m, "ptr", 0, "int", 0)
        inkAttrAlpha := inkStrokeAlpha
    }
    w := maxX - minX, h := maxY - minY
    DllCall("gdiplus\GdipDrawImageRectRectI", "ptr", pShapeGraphics, "ptr", pInkLayer
        , "int", minX, "int", minY, "int", w, "int", h
        , "int", minX, "int", minY, "int", w, "int", h
        , "int", 2, "ptr", pInkAttr, "ptr", 0, "ptr", 0) ; 2 = UnitPixel
}

; ================= 지우개 (오른쪽 버튼 드래그 / 전자칠판 손날) =================
; 굵기는 펜보다 넉넉하게 — 지우개는 대충 문질러도 지워져야 쓸 만하다.
;
; **손날로 지울 때는 설정값의 HAND_ERASER_SCALE배로 넓어진다.** 손이 덮는 면적이 마우스
; 커서보다 훨씬 넓어서, 같은 폭으로 지우면 손보다 좁게 지워져 답답하다.
; 닿은 면적에 **비례**시키는 방법도 있었지만 일부러 **고정 배율**로 했다(사용자 결정) —
; 손날 면적은 프레임마다 53~91로 출렁여서, 그대로 따라가면 지워지는 띠가 울렁거린다.
; 고정 배율이면 설정 창의 "지우개 크기" 슬라이더가 그대로 기준으로 살아 있으면서
; (칠판에 가기 전에 미리 맞춰둘 수 있다) 손날일 때만 일정하게 넓어진다.
;
; 이 함수는 지워지는 폭과 **커서 테두리 원**을 함께 정한다. 그래서 손날일 때는 원도 같이
; 커져 어디까지 지워질지 그대로 보인다.
EraserThickness() {
    global activeEraserSize, penEraserWide, HAND_ERASER_SCALE
    return penEraserWide ? Round(activeEraserSize * HAND_ERASER_SCALE) : activeEraserSize
}

; 지나간 자리를 배경과 똑같은 값(1,1,1)으로 덧칠한 뒤, 그 픽셀들의 알파를 1로 낮춰 도로
; 투명하게 만든다. GDI는 알파를 건드리지 않으므로 알파는 직접 손봐야 한다.
EraseSegment(x1, y1, x2, y2) {
    global memDC, vx, vy, pShapeGraphics
    thickness := EraserThickness()
    lx1 := x1 - vx, ly1 := y1 - vy, lx2 := x2 - vx, ly2 := y2 - vy
    ; 지우기 전 모습을 먼저 담아둬야 Ctrl+Z로 되살릴 수 있다
    CaptureUndoBands(Min(ly1, ly2) - thickness, Max(ly1, ly2) + thickness)
    if pShapeGraphics {
        DllCall("gdi32\GdiFlush")
        ; 지우개는 "덮어쓰기"(SourceCopy)로 그려야 한다. 보통의 겹쳐 그리기로는 이미 칠해진
        ; 투명도를 되돌릴 수 없어서 아무리 칠해도 지워지지 않는다.
        ; 부드럽게 처리하는 것도 여기서는 꺼야 한다 — 가장자리가 배경과 정확히 같은 값이
        ; 되지 않아 흐린 자국이 남기 때문이다.
        DllCall("gdiplus\GdipSetCompositingMode", "ptr", pShapeGraphics, "int", 1) ; SourceCopy
        DllCall("gdiplus\GdipSetSmoothingMode", "ptr", pShapeGraphics, "int", 3)   ; 끄기
        pPen := 0
        ; 0x01FFFFFF는 GDI+가 투명도를 미리 곱하면서 배경값(1,1,1,1)과 정확히 같아진다.
        ; 0x01010101로 주면 (0,0,0,1)이 되어 배경과 달라진다 — 시험해서 확인한 값이다.
        DllCall("gdiplus\GdipCreatePen1", "uint", 0x01FFFFFF, "float", thickness, "int", 2, "ptr*", &pPen)
        if pPen {
            DllCall("gdiplus\GdipSetPenStartCap", "ptr", pPen, "int", 2) ; 자유선과 같게 둥근 끝
            DllCall("gdiplus\GdipSetPenEndCap", "ptr", pPen, "int", 2)
            DllCall("gdiplus\GdipSetPenLineJoin", "ptr", pPen, "int", 2)
            DllCall("gdiplus\GdipDrawLine", "ptr", pShapeGraphics, "ptr", pPen, "float", lx1, "float", ly1, "float", lx2, "float", ly2)
            DllCall("gdiplus\GdipDeletePen", "ptr", pPen)
        }
        ; 그리기용 기본 설정으로 되돌려 놓는다 (겹쳐 그리기 + 부드럽게)
        DllCall("gdiplus\GdipSetCompositingMode", "ptr", pShapeGraphics, "int", 0)
        DllCall("gdiplus\GdipSetSmoothingMode", "ptr", pShapeGraphics, "int", 4)
        box := PenDirtyBox(lx1, ly1, lx2, ly2, thickness)
    } else {
        ; GDI+ 준비에 실패한 경우를 위한 대비책 (예전 방식: 배경색으로 덮고 투명도는 직접 내리기)
        pen := DllCall("CreatePen", "int", 0, "int", thickness, "uint", 0x010101, "ptr")
        old := DllCall("SelectObject", "ptr", memDC, "ptr", pen, "ptr")
        DllCall("MoveToEx", "ptr", memDC, "int", lx1, "int", ly1, "ptr", 0)
        DllCall("LineTo", "ptr", memDC, "int", lx2, "int", ly2)
        DllCall("SelectObject", "ptr", memDC, "ptr", old)
        DllCall("DeleteObject", "ptr", pen)
        box := ClearAlpha(lx1, ly1, lx2, ly2, thickness)
    }
    UpdateOverlay(box[1], box[2], box[3], box[4])
}

; 방금 배경색으로 덮인 픽셀만 골라 알파를 1로 되돌린다. 배경값과 "정확히" 같은 픽셀만
; 건드리기 때문에, 근처에 있던 검정(0,0,0) 선까지 휩쓸어 지우는 일이 없다.
ClearAlpha(x1, y1, x2, y2, pad) {
    global ppvBits, vw, vh
    pad += 2
    minX := Max(0, Min(x1, x2) - pad)
    maxX := Min(vw - 1, Max(x1, x2) + pad)
    minY := Max(0, Min(y1, y2) - pad)
    maxY := Min(vh - 1, Max(y1, y2) + pad)
    stride := vw * 4
    loop (maxY - minY + 1) {
        yy := minY + A_Index - 1
        rowBase := ppvBits + yy * stride
        loop (maxX - minX + 1) {
            px := rowBase + (minX + A_Index - 1) * 4
            if (NumGet(px, 0, "UChar") = 1 && NumGet(px, 1, "UChar") = 1 && NumGet(px, 2, "UChar") = 1)
                NumPut("UChar", 1, px, 3)
        }
    }
    return [minX, minY, maxX + 1, maxY + 1]
}

; 자유선용 GDI+ 펜. (변수 freehandPen과 이름이 겹치면 안 된다 — AutoHotkey는 대소문자를 구분하지 않는다)
; 10ms마다 짧은 선을 긋는 작업이라 매번 새로 만들면 낭비여서, 색이나
; 굵기가 바뀔 때만 다시 만들고 그 외에는 만들어둔 것을 재사용한다.
freehandPen := 0, freehandPenColor := -1, freehandPenWidth := -1
GetFreehandPen(argb) {
    global freehandPen, freehandPenColor, freehandPenWidth, activeDrawThickness
    ; 색과 투명도를 한 값(argb)으로 같이 본다 — 투명도만 바뀌어도 펜을 새로 만들어야 한다
    if (freehandPen && freehandPenColor = argb && freehandPenWidth = activeDrawThickness)
        return freehandPen
    if freehandPen
        DllCall("gdiplus\GdipDeletePen", "ptr", freehandPen)
    freehandPen := 0
    DllCall("gdiplus\GdipCreatePen1", "uint", argb, "float", activeDrawThickness, "int", 2, "ptr*", &freehandPen)
    if freehandPen {
        ; 자유선은 10ms마다 짧은 선을 이어 붙여 만드는 것이라, 선 끝이 평평하면 이음매마다
        ; 모난 자국이 남아 획이 끊겨 보인다. 끝과 이음매를 둥글게 해야 한 획처럼 이어진다.
        ; (GDI의 굵은 펜은 원래 끝이 둥글어서 이 문제가 없었다)
        DllCall("gdiplus\GdipSetPenStartCap", "ptr", freehandPen, "int", 2) ; LineCapRound
        DllCall("gdiplus\GdipSetPenEndCap", "ptr", freehandPen, "int", 2)
        DllCall("gdiplus\GdipSetPenLineJoin", "ptr", freehandPen, "int", 2) ; LineJoinRound
    }
    freehandPenColor := argb
    freehandPenWidth := activeDrawThickness
    return freehandPen
}

; ---- 무지개 펜 (S를 누르고 긋기) ----
; 긋는 동안 지나간 거리만큼 색상환을 돌아 색이 저절로 바뀐다. RAINBOW_CYCLE_PX만큼 그으면 한 바퀴.
; 획이 끝나도 색상을 이어 가서, 다음 획은 앞 획이 끝난 색에서 시작한다.
RAINBOW_CYCLE_PX := 700
rainbowHue := 0

NextRainbowColor(dist) {
    global rainbowHue, RAINBOW_CYCLE_PX
    rainbowHue := Mod(rainbowHue + dist * 360 / RAINBOW_CYCLE_PX, 360)
    return HueToRGB(rainbowHue)
}

; 채도·명도가 가장 높은 색 (색상환의 가장자리)
HueToRGB(h) {
    x := 1 - Abs(Mod(h / 60, 2) - 1)
    rgb := (h < 60) ? [1, x, 0] : (h < 120) ? [x, 1, 0] : (h < 180) ? [0, 1, x]
        : (h < 240) ? [0, x, 1] : (h < 300) ? [x, 0, 1] : [1, 0, x]
    return (Round(rgb[1] * 255) << 16) | (Round(rgb[2] * 255) << 8) | Round(rgb[3] * 255)
}

; 지금 긋는 획이 무지개 펜인가. 드래그를 시작할 때 정해져 획이 끝날 때까지 유지된다.
; 도형도 따른다 — 무지개 펜을 고른 채 도형을 그리면 테두리를 따라 색이 바뀐다.
strokeRainbow := false
; 무지개 도형을 그리기 시작할 때의 색상. 미리보기는 매 프레임 처음부터 다시 그리므로, 늘 이 색에서
; 출발하고 다 그린 길이만큼 돌아간 색을 rainbowHue에 남긴다(다음 획이 거기서 이어진다).
rainbowShapeHue := 0
RAINBOW_PIECE_PX := 12 ; 무지개 도형을 이만큼씩 끊어 색을 바꿔 칠한다 (색상으로 약 6도)
RAINBOW_INK_STEP_PX := 4 ; 무지개 펜 자유선은 이만큼씩 끊어 색을 바꾼다 (색상으로 약 2도, DrawSegment)

; 점들을 이은 선을 무지개 색으로 긋는다. 선을 따라 RAINBOW_PIECE_PX 남짓씩 끊어 토막마다 색을
; 바꾼다. 끝과 이음매를 둥글게 해 토막 사이가 끊겨 보이지 않게 한다. 다 그은 뒤의 색상을 돌려준다.
DrawRainbowPolyline(gr, pPen, alphaMask, pts, hue) {
    global RAINBOW_CYCLE_PX, RAINBOW_PIECE_PX
    DllCall("gdiplus\GdipSetPenStartCap", "ptr", pPen, "int", 2)
    DllCall("gdiplus\GdipSetPenEndCap", "ptr", pPen, "int", 2)
    DllCall("gdiplus\GdipSetPenLineJoin", "ptr", pPen, "int", 2)
    ; 긴 변(사각형·직선)은 한 토막 안에서도 색이 바뀌어야 하므로 먼저 잘게 나눈다
    fine := [pts[1]]
    loop pts.Length - 1 {
        p := pts[A_Index], q := pts[A_Index + 1]
        seg := Sqrt((q[1] - p[1]) ** 2 + (q[2] - p[2]) ** 2)
        n := Max(1, Ceil(seg / RAINBOW_PIECE_PX))
        loop n
            fine.Push([p[1] + (q[1] - p[1]) * A_Index / n, p[2] + (q[2] - p[2]) * A_Index / n])
    }
    ; 가까운 점들(물결)은 한 토막으로 묶어 한 번에 긋는다
    buf := Buffer(fine.Length * 8)
    i := 1
    while (i < fine.Length) {
        start := i, run := 0
        while (i < fine.Length && (run < RAINBOW_PIECE_PX || i = start)) {
            run += Sqrt((fine[i + 1][1] - fine[i][1]) ** 2 + (fine[i + 1][2] - fine[i][2]) ** 2)
            i += 1
        }
        loop i - start + 1
            NumPut("float", fine[start + A_Index - 1][1], "float", fine[start + A_Index - 1][2], buf, (A_Index - 1) * 8)
        DllCall("gdiplus\GdipSetPenColor", "ptr", pPen, "uint", alphaMask | HueToRGB(Mod(hue + run * 180 / RAINBOW_CYCLE_PX, 360)))
        DllCall("gdiplus\GdipDrawLines", "ptr", gr, "ptr", pPen, "ptr", buf, "int", i - start + 1)
        hue := Mod(hue + run * 360 / RAINBOW_CYCLE_PX, 360)
    }
    return hue
}

; 자유선 곡선: 10ms마다 받은 점을 직선으로 이으면 빨리 그을 때 꺾인 선처럼 보인다. 앞 토막이 끝난
; 방향으로 출발해 이 토막의 방향으로 닿는 곡선(에르미트)으로 이으면 이음매가 꺾이지 않는다.
; 다음 점을 기다리지 않으므로 선 끝이 늦지 않고, 토막마다 호출 한 번이라 가볍다.
freeDirX := 0, freeDirY := 0 ; 앞 토막의 방향(단위벡터). 0이면 이어받을 방향이 없다 (StrokeBegin에서 비움)
FREE_CURVE_MIN_PX := 5 ; 이보다 짧은 토막은 곡선으로 해도 달라 보이지 않아 직선으로 둔다
FREE_CURVE_STEP_PX := 4 ; 곡선을 이만큼씩 끊은 직선으로 그린다

; 곡선 위의 점들 [[x, y], ...] (화면 좌표). 곡선으로 할 수 없으면 두 점만 돌려준다.
FreehandCurve(x1, y1, x2, y2) {
    global freeDirX, freeDirY, FREE_CURVE_MIN_PX, FREE_CURVE_STEP_PX
    dx := x2 - x1, dy := y2 - y1
    L := Sqrt(dx * dx + dy * dy)
    if (L < 2)
        return [[x1, y1], [x2, y2]] ; 떨림 같은 아주 작은 움직임은 방향을 갱신하지 않는다
    cx := dx / L, cy := dy / L
    px := freeDirX, py := freeDirY
    freeDirX := cx, freeDirY := cy
    ; 방향이 90°넘게 꺾이면(되돌아 긋기) 곡선이 고리를 만들 수 있어 직선으로 둔다
    if (L < FREE_CURVE_MIN_PX || (px = 0 && py = 0) || px * cx + py * cy < 0)
        return [[x1, y1], [x2, y2]]
    k := L / 3
    ax := x1 + px * k, ay := y1 + py * k   ; 출발 조절점
    bx := x2 - cx * k, by := y2 - cy * k   ; 도착 조절점
    n := Min(24, Ceil(L / FREE_CURVE_STEP_PX))
    pts := [[x1, y1]]
    loop n {
        t := A_Index / n, u := 1 - t
        w0 := u * u * u, w1 := 3 * u * u * t, w2 := 3 * u * t * t, w3 := t * t * t
        pts.Push([w0 * x1 + w1 * ax + w2 * bx + w3 * x2, w0 * y1 + w1 * ay + w2 * by + w3 * y2])
    }
    return pts
}

; 점 목록을 GDI+가 받는 float 쌍 버퍼로
PointsBuffer(pts) {
    buf := Buffer(pts.Length * 8)
    for i, p in pts
        NumPut("float", p[1], "float", p[2], buf, (i - 1) * 8)
    return buf
}

DrawSegment(x1, y1, x2, y2) {
    global memDC, vx, vy, activeDrawThickness, activeDrawColor, activeDrawAlpha, pShapeGraphics
    global pInkGraphics, inkStrokeAlpha, strokeRainbow, RAINBOW_INK_STEP_PX
    lx1 := x1 - vx, ly1 := y1 - vy, lx2 := x2 - vx, ly2 := y2 - vy
    rgb := activeDrawColor
    ; 이번에 그을 조각들 [색, x1, y1, x2, y2]. 무지개 펜은 한 토막(10ms 동안 움직인 거리)을 한 색으로
    ; 칠하면 빨리 그을 때 색이 계단처럼 뚝뚝 바뀌므로, 약 RAINBOW_INK_STEP_PX씩 나눠 색을 조금씩 돌린다.
    curve := FreehandCurve(lx1, ly1, lx2, ly2)
    pieces := [[rgb, PointsBuffer(curve), curve.Length]]
    if strokeRainbow {
        dist := Sqrt((lx2 - lx1) ** 2 + (ly2 - ly1) ** 2)
        k := Max(1, Ceil(dist / RAINBOW_INK_STEP_PX))
        pieces := []
        loop k {
            a := (A_Index - 1) / k, b := A_Index / k
            rgb := NextRainbowColor(dist / k)
            pieces.Push([rgb, PointsBuffer([[lx1 + (lx2 - lx1) * a, ly1 + (ly2 - ly1) * a], [lx1 + (lx2 - lx1) * b, ly1 + (ly2 - ly1) * b]]), 2])
        }
    }
    if pShapeGraphics {
        ; 도형과 같은 방식. GDI+가 투명도까지 채워주므로 그린 자리를 훑을 필요가 없고,
        ; 테두리도 도형과 똑같이 매끄럽게 나온다.
        DllCall("gdi32\GdiFlush") ; 지우개는 아직 GDI를 쓰므로 밀린 작업을 먼저 반영시킨다
        ; 곡선이 두 점이 이루는 네모 밖으로 부풀 수 있어, 곡선 점 전체를 감싸는 범위로 잡는다
        cx1 := Min(lx1, lx2), cy1 := Min(ly1, ly2), cx2 := Max(lx1, lx2), cy2 := Max(ly1, ly2)
        for cp in curve
            cx1 := Min(cx1, cp[1]), cy1 := Min(cy1, cp[2]), cx2 := Max(cx2, cp[1]), cy2 := Max(cy2, cp[2])
        box := PenDirtyBox(cx1, cy1, cx2, cy2)
        ; 그리기 전 모습을 먼저 담아둔다. 한 획 안에서 같은 띠를 여러 번 지나가도 처음 한 번만 뜬다.
        CaptureUndoBands(box[2], box[4])
        if inkStrokeAlpha {
            ; 반투명한 획은 전용 판에 불투명하게 긋고 겹쳐 얹는다 (inkLayerBuf 설명 참고)
            for pc in pieces {
                pPen := GetFreehandPen(0xFF000000 | pc[1])
                if pPen
                    DllCall("gdiplus\GdipDrawLines", "ptr", pInkGraphics, "ptr", pPen, "ptr", pc[2], "int", pc[3])
            }
            InkMarkDirty(box)
            InkCompose(box)
        } else {
            ; 판을 쓸 수 없는데 반투명하면 예전처럼 덮어쓰기로 긋는다. 이음매가 진해지지는 않지만
            ; 먼저 그은 선 위를 지나가면 그 선을 덮는다. (불투명한 색은 겹쳐 칠해도 달라질 것이 없다)
            translucent := (activeDrawAlpha < 100)
            if translucent {
                DllCall("gdiplus\GdipSetCompositingMode", "ptr", pShapeGraphics, "int", 1) ; SourceCopy
                DllCall("gdiplus\GdipSetSmoothingMode", "ptr", pShapeGraphics, "int", 3)   ; 끄기
            }
            for pc in pieces {
                pPen := GetFreehandPen((ActiveARGB() & 0xFF000000) | pc[1])
                if pPen
                    DllCall("gdiplus\GdipDrawLines", "ptr", pShapeGraphics, "ptr", pPen, "ptr", pc[2], "int", pc[3])
            }
            if translucent {
                DllCall("gdiplus\GdipSetCompositingMode", "ptr", pShapeGraphics, "int", 0) ; 다시 겹쳐 그리기
                DllCall("gdiplus\GdipSetSmoothingMode", "ptr", pShapeGraphics, "int", 4)   ; 다시 부드럽게
            }
        }
    } else {
        CaptureUndoBands(Min(ly1, ly2) - activeDrawThickness, Max(ly1, ly2) + activeDrawThickness)
        ; GDI+ 준비에 실패한 경우를 위한 대비책 (예전 방식: GDI로 긋고 투명도는 직접 채우기)
        pen := DllCall("CreatePen", "int", 0, "int", Round(activeDrawThickness), "uint", ToBGR(rgb), "ptr") ; GDI 펜은 정수만 받는다
        old := DllCall("SelectObject", "ptr", memDC, "ptr", pen, "ptr")
        DllCall("MoveToEx", "ptr", memDC, "int", lx1, "int", ly1, "ptr", 0)
        DllCall("LineTo", "ptr", memDC, "int", lx2, "int", ly2)
        DllCall("SelectObject", "ptr", memDC, "ptr", old)
        DllCall("DeleteObject", "ptr", pen)
        box := PatchAlpha(lx1, ly1, lx2, ly2)
    }
    UpdateOverlay(box[1], box[2], box[3], box[4])
}

; mode: "line" | "rect" | "ellipse". 시작점~현재점 사이의 도형을 매 프레임 다시 그린다.
; (매번 스냅샷으로 되돌린 뒤 새로 그려서, 드래그 중인 미리보기가 쌓이지 않고 하나만 보이게 함)
DrawShapePreview(mode, x1, y1, x2, y2) {
    global memDC, vx, vy, activeDrawThickness, activeDrawColor, lastShapeBox, pShapeGraphics
    global pInkGraphics, inkStrokeAlpha, strokeRainbow, rainbowShapeHue, rainbowHue
    ; 직전 프레임이 그린 자리만 되돌리면 된다. 첫 프레임은 되돌릴 것이 없다(스냅샷을 방금 떴다).
    if (lastShapeBox.Length = 4) {
        RestoreSnapshotBox(lastShapeBox)
        if inkStrokeAlpha
            InkClearBox(lastShapeBox) ; 반투명 도형은 전용 판에도 직전 프레임이 남아 있다
    }
    lx1 := x1 - vx, ly1 := y1 - vy, lx2 := x2 - vx, ly2 := y2 - vy
    bx := Min(lx1, lx2), by := Min(ly1, ly2)
    bw := Abs(lx2 - lx1), bh := Abs(ly2 - ly1)
    overhang := ShapeOverhang(mode, lx1, ly1, lx2, ly2)
    ; 그리기 전 모습을 담아둔다. 미리보기는 매 프레임 스냅샷으로 되돌렸다 다시 그리는데,
    ; 그 되돌리기는 드래그 시작 시점(= 이 단계의 기준 모습)으로 돌리는 것이라 따로 담을 필요가 없다.
    ; 다시 합성할 범위(아래 box)보다 좁게 담으면, 그 가장자리가 되돌린 뒤에 남을 수 있어서 같은 범위로 담는다.
    capBox := PenDirtyBox(lx1, ly1, lx2, ly2, activeDrawThickness + 2 * overhang)
    CaptureUndoBands(Min(capBox[2], Min(ly1, ly2) - activeDrawThickness - overhang)
        , Max(capBox[4], Max(ly1, ly2) + activeDrawThickness + overhang))

    if pShapeGraphics {
        ; GDI가 아직 버퍼에 반영하지 않은 작업이 남아 있을 수 있으므로 먼저 밀어 넣는다
        DllCall("gdi32\GdiFlush")
        ; 반투명하면 전용 판에 불투명하게 그려서 겹쳐 얹는다 (inkLayerBuf 설명 참고)
        gr := inkStrokeAlpha ? pInkGraphics : pShapeGraphics
        argb := inkStrokeAlpha ? (0xFF000000 | activeDrawColor) : ActiveARGB()
        pPen := 0
        ; GDI+ 색은 0xAARRGGBB — GDI처럼 BGR로 뒤집지 않는다
        DllCall("gdiplus\GdipCreatePen1", "uint", argb, "float", activeDrawThickness, "int", 2, "ptr*", &pPen)
        if strokeRainbow {
            ; 무지개 펜: 테두리를 따라 색이 바뀐다. 화살표는 몸통만 무지개로 긋고, 머리는 몸통이
            ; 끝난 색으로 채운다(테두리를 따라 그으면 채운 삼각형이 아니라 빈 삼각형이 된다).
            alphaMask := argb & 0xFF000000
            if (mode = "arrow") {
                g := ArrowGeometry(lx1, ly1, lx2, ly2)
                endHue := g ? DrawRainbowPolyline(gr, pPen, alphaMask, [[lx1, ly1], [g.bx, g.by]], rainbowShapeHue) : rainbowShapeHue
                if g
                    DrawArrowGdip(gr, 0, alphaMask | HueToRGB(endHue), lx1, ly1, lx2, ly2)
            } else if (mode = "line") {
                endHue := DrawRainbowPolyline(gr, pPen, alphaMask, [[lx1, ly1], [lx2, ly2]], rainbowShapeHue)
            } else {
                endHue := DrawRainbowPolyline(gr, pPen, alphaMask, ShapeOutlinePoints(mode, lx1, ly1, lx2, ly2), rainbowShapeHue)
            }
            rainbowHue := endHue ; 다음 획은 이 도형이 끝난 색에서 이어진다
        } else if mode = "line"
            DllCall("gdiplus\GdipDrawLine", "ptr", gr, "ptr", pPen, "float", lx1, "float", ly1, "float", lx2, "float", ly2)
        else if mode = "rect"
            DllCall("gdiplus\GdipDrawRectangle", "ptr", gr, "ptr", pPen, "float", bx, "float", by, "float", bw, "float", bh)
        else if mode = "ellipse"
            DllCall("gdiplus\GdipDrawEllipse", "ptr", gr, "ptr", pPen, "float", bx, "float", by, "float", bw, "float", bh)
        else if mode = "arrow"
            DrawArrowGdip(gr, pPen, argb, lx1, ly1, lx2, ly2)
        else if mode = "wave"
            DrawWaveGdip(gr, pPen, lx1, ly1, lx2, ly2)
        DllCall("gdiplus\GdipDeletePen", "ptr", pPen)
        ; 화살표 머리와 물결의 굽이는 두 끝점을 잇는 선 바깥으로 나가므로, 그만큼 여유를 더 준다.
        ; (여유가 모자라면 되돌릴 때 지워지지 않은 자국이 화면에 남는다)
        box := PenDirtyBox(lx1, ly1, lx2, ly2, activeDrawThickness + 2 * overhang)
        if inkStrokeAlpha {
            InkMarkDirty(box)
            InkCompose(box)
        }
    } else {
        ; GDI+ 준비에 실패한 경우를 위한 대비책 — 예전 방식(GDI로 그리고 알파는 직접 채우기).
        ; 테두리를 따라가며 훑어서, 도형을 감싸는 네모 전체를 훑던 때보다는 훨씬 가볍다.
        pen := DllCall("CreatePen", "int", 0, "int", Round(activeDrawThickness), "uint", ToBGR(activeDrawColor), "ptr") ; GDI 펜은 정수만 받는다
        oldPen := DllCall("SelectObject", "ptr", memDC, "ptr", pen, "ptr")
        nullBrush := DllCall("GetStockObject", "int", 5, "ptr") ; NULL_BRUSH (안쪽은 채우지 않음)
        oldBrush := DllCall("SelectObject", "ptr", memDC, "ptr", nullBrush, "ptr")
        if mode = "line" {
            DllCall("MoveToEx", "ptr", memDC, "int", lx1, "int", ly1, "ptr", 0)
            DllCall("LineTo", "ptr", memDC, "int", lx2, "int", ly2)
        } else if mode = "rect" {
            DllCall("Rectangle", "ptr", memDC, "int", bx, "int", by, "int", bx + bw, "int", by + bh)
        } else if mode = "ellipse" {
            DllCall("Ellipse", "ptr", memDC, "int", bx, "int", by, "int", bx + bw, "int", by + bh)
        } else {
            ; 화살표와 물결은 전용 GDI 함수가 없으므로 점을 이어 그린다. 화살표 머리는 채워지지
            ; 않고 테두리만 나오지만, GDI+를 못 쓰는 상황에서의 대비책이라 이 정도로 충분하다.
            outline := ShapeOutlinePoints(mode, lx1, ly1, lx2, ly2)
            DllCall("MoveToEx", "ptr", memDC, "int", Round(outline[1][1]), "int", Round(outline[1][2]), "ptr", 0)
            loop outline.Length - 1
                DllCall("LineTo", "ptr", memDC, "int", Round(outline[A_Index + 1][1]), "int", Round(outline[A_Index + 1][2]))
        }
        DllCall("SelectObject", "ptr", memDC, "ptr", oldPen)
        DllCall("SelectObject", "ptr", memDC, "ptr", oldBrush)
        DllCall("DeleteObject", "ptr", pen)
        box := PatchAlphaPolyline(ShapeOutlinePoints(mode, lx1, ly1, lx2, ly2))
    }

    ; 이전 프레임에 그렸던 자리도 화면에서 지워져야 하므로, 두 범위를 합친 만큼만 다시 합성한다.
    dirty := box.Clone()
    if (lastShapeBox.Length = 4) {
        dirty[1] := Min(dirty[1], lastShapeBox[1])
        dirty[2] := Min(dirty[2], lastShapeBox[2])
        dirty[3] := Max(dirty[3], lastShapeBox[3])
        dirty[4] := Max(dirty[4], lastShapeBox[4])
    }
    lastShapeBox := box
    UpdateOverlay(dirty[1], dirty[2], dirty[3], dirty[4])
}

; 도형이 두 끝점을 잇는 선 바깥으로 얼마나 나가는지. 화살표 머리와 물결 굽이가 여기 해당하며,
; 되돌릴 범위와 실행 취소에 담을 범위를 정하는 데 쓴다(그리는 쪽과 값이 어긋나면 안 되므로 한 곳에 둔다).
ShapeOverhang(mode, x1, y1, x2, y2) {
    if (mode = "arrow") {
        g := ArrowGeometry(x1, y1, x2, y2)
        return g ? Ceil(g.halfW) : 0
    }
    if (mode = "wave")
        return Ceil(WaveAmplitude())
    return 0
}

; 화살표: 몸통 선 + 끝에 채운 삼각형 머리.
; gr은 그릴 곳(판서 그림 또는 반투명 전용 판), argb는 머리를 채울 색이다.
DrawArrowGdip(gr, pPen, argb, x1, y1, x2, y2) {
    g := ArrowGeometry(x1, y1, x2, y2)
    if !g
        return
    ; 몸통은 머리 밑변까지만 그린다 — 끝까지 그으면 머리 꼭짓점 밖으로 삐져나갈 수 있다.
    ; 끝을 둥글게 해야 삼각형과 만나는 자리가 매끄럽게 이어진다.
    ; pPen이 0이면 머리만 그린다 (무지개 화살표는 몸통을 따로 긋는다)
    if pPen {
        DllCall("gdiplus\GdipSetPenStartCap", "ptr", pPen, "int", 2) ; LineCapRound
        DllCall("gdiplus\GdipSetPenEndCap", "ptr", pPen, "int", 2)
        DllCall("gdiplus\GdipDrawLine", "ptr", gr, "ptr", pPen, "float", x1, "float", y1, "float", g.bx, "float", g.by)
    }

    ; 머리는 테두리가 아니라 채워야 화살표처럼 보인다 — 펜이 아니라 브러시로 삼각형을 채운다.
    pts := Buffer(24) ; PointF 3개 (실수 x, y)
    NumPut("float", x2, "float", y2, "float", g.lx, "float", g.ly, "float", g.rx, "float", g.ry, pts)
    pBrush := 0
    DllCall("gdiplus\GdipCreateSolidFill", "uint", argb, "ptr*", &pBrush)
    if pBrush {
        DllCall("gdiplus\GdipFillPolygon", "ptr", gr, "ptr", pBrush, "ptr", pts, "int", 3, "int", 0)
        DllCall("gdiplus\GdipDeleteBrush", "ptr", pBrush)
    }
}

; 물결: 사인파 위의 점들을 이어 그린다.
DrawWaveGdip(gr, pPen, x1, y1, x2, y2) {
    pts := WavePoints(x1, y1, x2, y2)
    buf := Buffer(pts.Length * 8)
    for i, p in pts
        NumPut("float", p[1], "float", p[2], buf, (i - 1) * 8)
    ; 짧은 선을 잇대어 만드는 것이라 자유선과 같은 함정이 있다 — 끝과 이음매를 둥글게 하지
    ; 않으면 굽이마다 모난 자국이 남는다.
    DllCall("gdiplus\GdipSetPenStartCap", "ptr", pPen, "int", 2)
    DllCall("gdiplus\GdipSetPenEndCap", "ptr", pPen, "int", 2)
    DllCall("gdiplus\GdipSetPenLineJoin", "ptr", pPen, "int", 2)
    DllCall("gdiplus\GdipDrawLines", "ptr", gr, "ptr", pPen, "ptr", buf, "int", pts.Length)
}

; 지금 눌려 있는 키로 그릴 도형을 정한다. 도형 키(글자)를 먼저 보기 때문에, 글자키를 쥔 채로
; Shift나 Ctrl이 함께 눌려 있어도 사용자가 고른 도형이 그려진다.
CurrentShapeMode() {
    global SHAPE_HOLD_KEYS, shapeKeyHeld
    for pair in SHAPE_HOLD_KEYS
        if shapeKeyHeld.Has(pair[1]) && shapeKeyHeld[pair[1]]
            return pair[2]
    ; 수식키 둘은 "무언가를 네모나 동그라미로 둘러 강조하는" 쓰임이라 가장 누르기 쉬운 자리에 뒀다.
    ; (ZoomIt과 여러 그림 도구는 Shift를 직선에 쓰지만, 여기서는 직선을 Z로 옮겼다 — 사용자 결정)
    return GetKeyState("Ctrl", "P") ? "ellipse"
        : GetKeyState("Shift", "P") ? "rect"
        : ""
}

; 마우스 버튼이 눌려 있는지 본다. **"P"(물리) 판정을 쓰지 않는 것이 핵심이다.**
; 전자칠판 터치펜·펜 태블릿·원격 제어의 입력은 Windows가 마우스 입력을 "흉내내어" 만들어
; 보내는데(injected), 이런 입력은 물리 판정에서 눌리지 않은 것으로 나온다. 실제로 측정한 값:
;   흉내낸 클릭이 눌려 있는 동안 → GetKeyState("LButton","P")=0 / GetAsyncKeyState=1
; 그래서 "P"로 판정하면 터치펜으로는 **커서만 움직이고 선이 안 그려진다**(2026-09-21 제보).
; 반대로 하이라이트 모드의 클릭 효과는 멀쩡했는데, 그쪽은 핫키(~LButton)라서 흉내낸 입력에도
; 정상적으로 걸리기 때문이다 — 같은 터치인데 한쪽만 되던 이유가 이것이다.
;
; 고르는 김에 AHK의 논리 판정(GetKeyState에 "P"를 빼는 것)이 아니라 GetAsyncKeyState를 쓴다.
; 논리 판정은 "우리 스레드의 메시지 큐가 받아본 상태"라, 오른쪽 드래그가 다른 창 위에서
; 시작되는 경우처럼 입력이 남의 프로세스로 가는 상황에서 뒤처질 수 있다. GetAsyncKeyState는
; 큐와 무관한 시스템 전역 상태라 그런 구멍이 없다.
VK_LBUTTON := 0x01
VK_RBUTTON := 0x02
MouseDown(vk) => (DllCall("GetAsyncKeyState", "int", vk, "short") & 0x8000) != 0

; ================= 전자칠판·터치펜 입력 =================
; 터치와 펜은 Windows가 마우스 입력으로 바꿔서 보내주는데(promotion), 그 변환이 **늦다.**
; 탭인지, 길게 누르기인지, 드래그인지 판별할 때까지 붙들고 있다가 접촉점이 일정 거리를
; 움직인 뒤에야 내보낸다. 합성 터치로 재현해 실제로 측정한 값:
;   +0ms   WM_POINTERDOWN (700,700)  ← 닿는 즉시, 정확한 접촉 위치
;   +46ms  WM_LBUTTONDOWN            ← 12px 움직인 뒤에야 도착
; 게다가 우리는 폴링으로 MouseGetPos를 읽으므로, 뒤늦게 알아챈 그 시점의 커서 자리에서 획이
; 시작된다 — 처음 구간이 통째로 날아간다. "터치한 뒤 좀 움직여야 선이 나온다"는 제보가 이것이다.
;
; 그래서 마우스 변환을 기다리지 않고 **포인터 메시지를 직접 받아** 획을 긋는다. 닿는 순간의
; 좌표가 그대로 획의 시작점이 된다.
;
; **마우스(포인터 종류 4)는 건드리지 않고 기존 폴링 경로가 그대로 처리한다.** 어떤 기기에서
; 이 경로가 안 먹더라도 최소한 지금처럼은 동작하게 남겨두려는 것이다 — 교실에서 쓰는
; 물건이라 "더 좋아지거나, 아니면 그대로"여야지 "안 되거나"는 곤란하다.
PT_TOUCH := 2
PT_PEN := 3
penStroke := false      ; 터치·펜으로 획을 긋고 있는 중인가
penErasing := false     ; 그 획이 지우개인가 (펜 뒤쪽이든 손날이든)
penEraserWide := false  ; 그 지우개가 **손날**인가 (설정값의 HAND_ERASER_SCALE배로 넓게 지운다)
penLastX := 0
penLastY := 0
penIgnoreMouse := false ; 터치 뒤에 따라 들어오는 마우스 입력을 흘려보내는 중인가
penContacts := Map()    ; 지금 화면에 닿아 있는 접촉들 (두 손가락 판정용)
penGesture := false     ; 두 손가락 제스처가 걸려 이번 터치는 그리지 않는 상태

; 접촉이 끝났는데 POINTERUP을 놓치는 일이 생기면 목록에 유령이 남고, 그때부터 **한 손가락
; 터치가 전부 "두 손가락"으로 보인다.** 그러면 그릴 때마다 실행 취소가 걸리는 최악의 상태가
; 되므로, 새로 닿을 때마다 이미 끝난 id를 걸러낸다.
PrunePenContacts() {
    global penContacts
    info := Buffer(96, 0)
    for id in penContacts.Clone()
        if !DllCall("GetPointerInfo", "UInt", id, "Ptr", info, "Int")
            penContacts.Delete(id)
}

; 두 손가락으로 톡 = 실행 취소. 칠판 앞에서는 Ctrl+Z를 누르러 키보드까지 갈 수가 없다.
TwoFingerUndo() {
    global penStroke, penErasing, penEraserWide, undoStack
    ; 두 손가락이 정확히 동시에 닿지는 않으므로, 먼저 닿은 손가락이 이미 짧은 자국을
    ; 그려놓았을 수 있다. 그 자국부터 없던 일로 하고 나서 진짜 실행 취소를 한다.
    ; (아무것도 안 그렸으면 그 단계는 비어 있고, UndoDrawing이 빈 단계를 건너뛴다)
    abortedInk := penStroke && undoStack.Length > 0 && undoStack[undoStack.Length].Count > 0
    if penStroke {
        penStroke := false
        LaserEnd() ; 레이저 펜이었으면 그 자국은 저절로 사라진다 (실행 취소 기록에도 없다)
        if penErasing {
            penErasing := false
            penEraserWide := false
            SetBrushMode("pen")
        }
    }
    if abortedInk
        UndoDrawing() ; 두 손가락을 대다 생긴 자국 지우기
    UndoDrawing()     ; 사용자가 의도한 실행 취소
}

; 전자칠판 터치펜의 **앞뒤 구분**. Windows가 표준으로 알려준다 — 펜 입력에는 POINTER_PEN_INFO가
; 딸려오고, 그 안의 penFlags에 "뒤집힘"과 "지우개" 표시가 들어 있다.
;   PEN_FLAG_BARREL   0x01  옆면 버튼을 누르고 있음
;   PEN_FLAG_INVERTED 0x02  펜을 뒤집어 **뒤쪽이 화면을 향하고 있음**
;   PEN_FLAG_ERASER   0x04  뒤쪽(지우개)이 화면에 닿아 있음
; 앞/뒤만 쓰기로 했으므로 INVERTED와 ERASER만 본다. 옆면 버튼(BARREL)까지 지우개로 치면
; 펜을 고쳐 쥐다 버튼이 눌렸을 때 의도치 않게 지워지므로 일부러 뺐다.
;
; **모든 전자칠판이 이 정보를 주는 것은 아니다.** 적외선 방식 보드의 "펜"은 그냥 막대라서
; Windows에는 손가락 터치와 구분이 안 되고, 순정 앱이 접촉 면적 같은 걸로 자체 판별하기도
; 한다. 그래서 정보를 못 얻으면 조용히 "앞쪽(펜)"으로 본다 — 못 알아들었다고 안 그려지는
; 것보다는 평소대로 그려지는 쪽이 낫다.
PEN_FLAG_INVERTED := 0x02
PEN_FLAG_ERASER := 0x04

; 이 접촉이 무엇으로 지우려는 것인지 가린다.
;   ""      글씨 (펜이든 손가락이든)
;   "pen"   펜 뒤쪽 지우개 — 펜만 한 크기라 설정값 그대로 지운다
;   "hand"  손날 지우개 — 설정값의 HAND_ERASER_SCALE배로 넓게 지운다
EraserKind(id) {
    global PEN_FLAG_INVERTED, PEN_FLAG_ERASER
    ; POINTER_PEN_INFO = POINTER_INFO(x64에서 96바이트) + penFlags + penMask + ...
    info := Buffer(120, 0)
    if DllCall("GetPointerPenInfo", "UInt", id, "Ptr", info, "Int") {
        penFlags := NumGet(info, 96, "UInt")
        ; 펜으로 보고하는 기기다 — 플래그를 믿고 면적은 안 본다
        return (penFlags & (PEN_FLAG_INVERTED | PEN_FLAG_ERASER)) ? "pen" : ""
    }
    ; 펜 정보를 안 주는 칠판이면 접촉 면적으로 가른다 (ERASER_CONTACT_PX 설명 참고)
    return IsWideContact(id) ? "hand" : ""
}

; 닿은 면적이 경계보다 크면(= 손날처럼 넓게 대면) 지우개로 본다. 가로·세로 중 **긴 쪽**을
; 보는 이유는 손날이 한쪽으로 길쭉하게 닿기 때문이다 — 면적으로 재면 긴 쪽이 희석된다.
; 면적을 못 읽거나 경계가 0이면 언제나 펜이다 — 못 알아들었다고 안 그려지는 것보다
; 평소대로 그려지는 쪽이 낫다.
IsWideContact(id) {
    global ERASER_CONTACT_PX
    if (ERASER_CONTACT_PX <= 0)
        return false
    ; POINTER_TOUCH_INFO = POINTER_INFO(96) + touchFlags + touchMask + rcContact(104~)
    ti := Buffer(144, 0)
    if !DllCall("GetPointerTouchInfo", "UInt", id, "Ptr", ti, "Int")
        return false
    w := NumGet(ti, 112, "Int") - NumGet(ti, 104, "Int")
    h := NumGet(ti, 116, "Int") - NumGet(ti, 108, "Int")
    return (Max(w, h) >= ERASER_CONTACT_PX)
}

; 포인터 메시지의 좌표는 lParam에 화면 좌표로 실려온다. **보조 모니터는 좌표가 음수라
; 부호를 살려야 한다** — 그냥 읽으면 왼쪽 모니터가 65000 언저리의 엉뚱한 자리가 된다.
PointerXY(lp) {
    x := lp & 0xFFFF
    y := (lp >> 16) & 0xFFFF
    return [(x > 0x7FFF) ? x - 0x10000 : x, (y > 0x7FFF) ? y - 0x10000 : y]
}

IsPenOrTouch(wp) {
    global PT_TOUCH, PT_PEN
    t := 0
    if !DllCall("GetPointerType", "UInt", wp & 0xFFFF, "UInt*", &t, "Int")
        return false
    return (t = PT_TOUCH || t = PT_PEN)
}

OnPointerDown(wp, lp, msg, hwnd) {
    global drawOn, drawGui, penStroke, penErasing, penEraserWide, penLastX, penLastY, penIgnoreMouse
    global drawing, erasing, dragOnOtherWindow, dragShapeMode, dragPenKind, penContacts, penGesture
    global strokeRainbow
    Critical ; 그리는 도중에 드로잉 끄기가 끼어들지 않게 (DrawPoll 설명 참고)
    if (!drawOn || hwnd != drawGui.Hwnd || !IsPenOrTouch(wp))
        return
    id := wp & 0xFFFF
    PrunePenContacts()
    penContacts[id] := true
    ; ---- 두 손가락으로 톡 = 실행 취소 ----
    if (penContacts.Count >= 2) {
        penIgnoreMouse := true
        ; **손날로 지우는 중이면 건드리지 않는다.** 칠판에 따라 손날 하나가 여러 접촉으로
        ; 잡히기도 하는데, 그걸 "두 손가락"으로 오해하면 문지를 때마다 실행 취소가 걸린다.
        ; 새로 닿은 것이 넓은 접촉일 때도 손의 일부로 보고 넘긴다.
        ; 한 번 걸리면 손을 다 뗄 때까지 다시 걸리지 않는다(penGesture).
        if (!penErasing && !penGesture && !IsWideContact(id)) {
            penGesture := true
            TwoFingerUndo()
        }
        return
    }
    ; 제스처가 걸린 동안에는 손을 다 뗄 때까지 아무것도 그리지 않는다
    if penGesture
        return
    ; **도형(Shift·Ctrl·Z·X·C)과 특수 펜(A·S)도 여기서 직접 긋는다.** 예전에는 이것들을 마우스
    ; 경로에 맡겼는데, 그러면 Windows의 터치→마우스 변환을 기다려야 해서 칠판에서 **닿고 한참
    ; 뒤에야 반응했다**(2026-09-28 제보). 마우스와 같은 함수(StrokeBegin/StrokeMove)를 쓰므로
    ; 어느 쪽으로 그어도 결과가 같다.
    pt := PointerXY(lp)
    penStroke := true
    ; **닿는 순간 한 번만** 앞뒤를 판단하고 획이 끝날 때까지 유지한다. 긋는 도중에 계속
    ; 물어보면, 펜이 기울어져 플래그가 한 프레임 흔들릴 때 한 획이 반은 글씨 반은 지우개가 된다.
    ; 손날인지 펜 뒤쪽인지는 **지우는 폭이 달라지므로** 함께 기억해둔다.
    ; SetBrushMode보다 먼저 정해야 커서 테두리 원도 같은 폭으로 그려진다.
    eraseKind := EraserKind(id)
    penErasing := (eraseKind != "")
    penEraserWide := (eraseKind = "hand")
    penIgnoreMouse := true
    drawing := false
    erasing := false
    dragOnOtherWindow := false ; 포인터 메시지는 판서 층을 직접 닿았을 때만 온다
    penLastX := pt[1]
    penLastY := pt[2]
    if penErasing {
        dragShapeMode := ""
        dragPenKind := ""
        strokeRainbow := false
        PushUndo() ; 이 지우기 한 번만 Ctrl+Z로 되돌릴 수 있도록
        BeginInkStroke(100)
    } else {
        StrokeBegin(pt[1], pt[2])
    }
    ; 뒤쪽으로 대면 커서도 지우개 테두리 원으로 바뀌어, 어디까지 지워지는지 보인다
    SetBrushMode(penErasing ? "eraser" : "pen")
    ; 여기서 점을 찍지는 않는다 — 마우스로 그냥 클릭만 했을 때 점이 안 남는 것과 맞춘다
    MoveBrushCursor(penLastX, penLastY)
}

OnPointerUpdate(wp, lp, msg, hwnd) {
    global drawOn, drawGui, penStroke, penErasing, penLastX, penLastY, dragShapeMode, dragPenKind
    Critical ; 그리는 도중에 드로잉 끄기가 끼어들지 않게 (DrawPoll 설명 참고)
    if (!penStroke || !drawOn || hwnd != drawGui.Hwnd)
        return
    pt := PointerXY(lp)
    if (pt[1] = penLastX && pt[2] = penLastY)
        return
    if penErasing
        EraseSegment(penLastX, penLastY, pt[1], pt[2])
    else if (dragShapeMode = "") {
        ; 일반·무지개 펜은 메시지 사이에 합쳐진 중간 점도 이어서 긋는다 (PointerTrail 설명 참고)
        if (dragPenKind != "laser")
            for tp in PointerTrail(wp & 0xFFFF, pt[1], pt[2])
                StrokeMove(tp[1], tp[2])
        StrokeMove(pt[1], pt[2]) ; 자유선·레이저 펜·무지개 펜은 오는 대로 바로 긋는다
    }
    ; 도형은 여기서 그리지 않고 자리만 적어둔다 — DrawPoll이 10ms마다 마지막 자리로 다시 그린다.
    ; 도형은 한 번 그릴 때마다 전체를 다시 그리는데, 칠판은 포인터 메시지를 마우스보다 훨씬
    ; 자주 보내서 오는 대로 다 그리면 밀린 메시지가 쌓여 도형이 손을 늦게 따라온다.
    penLastX := pt[1]
    penLastY := pt[2]
    ; 커서 노릇을 하는 원도 포인터 좌표로 옮긴다. 진짜 마우스 커서는 변환이 늦어 뒤처지므로
    ; MouseGetPos로 옮기면 원만 따로 놀게 된다.
    MoveBrushCursor(penLastX, penLastY)
}

; 터치·펜 메시지 하나에는 마지막 점만 실려 오는데, 시스템이 메시지를 합쳐 보내면 그 사이 점이
; 사라져 선이 각진다. 합쳐진 점들은 포인터 이력으로 가져올 수 있다 (마우스의 MouseTrail과 같은 역할).
; 지난 자리(penLastX, penLastY)부터 지금 자리 앞까지의 점을 오래된 순으로, 4px 이상 떨어진 것만 돌려준다.
; POINTER_INFO의 크기를 확신할 수 없어, 항목마다 pointerId가 같은지 확인해 어긋나면 아무것도 돌려주지 않는다.
POINTER_INFO_SIZE := 96 ; 64비트
PointerTrail(id, x, y) {
    global penLastX, penLastY, POINTER_INFO_SIZE, MOUSE_TRAIL_STEP_PX
    static buf := Buffer(128 * 32, 0)
    cnt := 32
    if !DllCall("GetPointerInfoHistory", "uint", id, "uint*", &cnt, "ptr", buf, "int")
        return []
    if (cnt < 3)
        return []
    sz := POINTER_INFO_SIZE
    pts := []
    loop cnt {
        o := (A_Index - 1) * sz
        if (NumGet(buf, o + 4, "uint") != id)
            return [] ; 구조체 크기가 다르다
        px := NumGet(buf, o + 32, "int"), py := NumGet(buf, o + 36, "int") ; ptPixelLocation
        if (A_Index = 1) {
            if (px != x || py != y)
                return []
            continue
        }
        if (px = penLastX && py = penLastY)
            break
        pts.Push([px, py])
    }
    out := []
    qx := penLastX, qy := penLastY
    step2 := MOUSE_TRAIL_STEP_PX ** 2
    loop pts.Length {
        p := pts[pts.Length - A_Index + 1]
        if ((p[1] - qx) ** 2 + (p[2] - qy) ** 2 >= step2 && (p[1] - x) ** 2 + (p[2] - y) ** 2 >= step2) {
            out.Push(p)
            qx := p[1], qy := p[2]
        }
    }
    return out
}

OnPointerUp(wp, lp, msg, hwnd) {
    global penStroke, penErasing, penEraserWide, penContacts, penGesture, penLastX, penLastY
    global dragShapeMode, drawOn
    Critical ; 도형의 마지막 모습을 그리는 도중에 드로잉 끄기가 끼어들지 않게
    id := wp & 0xFFFF
    if penContacts.Has(id)
        penContacts.Delete(id)
    ; 손을 전부 떼야 제스처가 풀린다. 두 손가락 중 하나만 떼었을 때 바로 풀어버리면,
    ; 남은 손가락이 이어서 선을 긋기 시작한다.
    if (penContacts.Count = 0)
        penGesture := false
    if (penStroke && !penErasing && drawOn) {
        ; 도형은 10ms마다 그리므로, 손을 뗀 자리가 아직 안 그려졌을 수 있다
        if (dragShapeMode != "")
            StrokeMove(penLastX, penLastY)
        LaserEnd() ; 레이저 펜으로 긋던 중이면 이제부터 사라지기 시작한다
    }
    penStroke := false
    if penErasing {
        penErasing := false
        penEraserWide := false
        SetBrushMode("pen") ; 펜을 떼면 커서는 다시 펜 원으로
    }
}

OnMessage(0x0246, OnPointerDown)   ; WM_POINTERDOWN
OnMessage(0x0245, OnPointerUpdate) ; WM_POINTERUPDATE
OnMessage(0x0247, OnPointerUp)     ; WM_POINTERUP

; 왼쪽 드래그(마우스)나 터치·펜 획을 시작한다. 두 경로가 이 함수와 StrokeMove를 함께 써야 도형과
; 특수 펜이 어느 쪽으로 그어도 똑같이 나온다. 부르기 전에 dragOnOtherWindow를 정해둬야 한다.
StrokeBegin(x, y) {
    global lastX, lastY, dragStartX, dragStartY, dragShapeMode, dragPenKind, penKind
    global dragOnOtherWindow, lastShapeBox, strokeRainbow, activeDrawAlpha, inkStrokeAlpha
    global rainbowShapeHue, rainbowHue, freeDirX, freeDirY
    lastX := x, lastY := y
    freeDirX := 0, freeDirY := 0 ; 새 획은 이어받을 방향이 없다 (FreehandCurve)
    dragStartX := x, dragStartY := y
    ; 도형은 긋기 시작하는 순간 눌려 있던 키로 정한다. **특수 펜은 도형에도 그대로 적용된다**
    ; (사용자 요청) — 무지개 펜이면 테두리를 따라 색이 바뀌고, 레이저 펜이면 빛나는 도형이
    ; 손을 뗀 뒤 저절로 사라진다(LaserSetShape).
    dragShapeMode := CurrentShapeMode()
    dragPenKind := penKind
    strokeRainbow := (penKind = "rainbow")
    rainbowShapeHue := rainbowHue
    if dragOnOtherWindow
        return ; 다른 창 위에서 시작된 드래그 — 아무것도 그리지 않는다
    if (dragPenKind = "laser") {
        ; 레이저 펜은 판서 그림을 건드리지 않으므로 실행 취소에 남기지 않는다
        LaserBegin(x, y)
        return
    }
    ; 획을 긋기 전 상태를 기록해둬야 Ctrl+Z로 이 한 획만 되돌릴 수 있다
    PushUndo()
    BeginInkStroke(activeDrawAlpha)
    if (dragShapeMode != "") {
        ; 반투명이면 BeginInkStroke가 이미 떠뒀다. 복사본을 못 만들면 고무줄 미리보기를 할 수
        ; 없으므로 이 도형은 그리지 않는다(다른 창 위의 드래그처럼 흘려보낸다).
        if (!inkStrokeAlpha && !SaveSnapshot())
            dragOnOtherWindow := true
        lastShapeBox := [] ; 새 도형이므로 지울 이전 프레임이 없다
    }
}

; 시작한 획을 (x, y)까지 잇는다. 도형은 시작점부터 이 자리까지를 다시 그린다.
StrokeMove(x, y) {
    global lastX, lastY, dragStartX, dragStartY, dragShapeMode, dragPenKind, dragOnOtherWindow
    if dragOnOtherWindow
        return
    if (dragShapeMode != "") {
        ex := x, ey := y
        ; 선 종류(직선·화살표·물결)는 Shift를 함께 누르면 0°·45°·90° 방향으로 맞춘다.
        ; 드래그 도중에 눌러도 바로 따라온다.
        if (GetKeyState("Shift", "P") && (dragShapeMode = "line" || dragShapeMode = "arrow" || dragShapeMode = "wave")) {
            snapped := SnapTo45(dragStartX, dragStartY, x, y)
            ex := snapped[1], ey := snapped[2]
        }
        if (dragPenKind = "laser") {
            ; 레이저 도형도 움직이기 전까지는 시작하지 않는다 (LaserBegin 설명 참고)
            if (LaserStarted() || x != dragStartX || y != dragStartY)
                LaserSetShape(ShapeOutlinePoints(dragShapeMode, dragStartX, dragStartY, ex, ey, true))
        } else
            DrawShapePreview(dragShapeMode, dragStartX, dragStartY, ex, ey)
        return
    } else if (dragPenKind = "laser") {
        if (x != lastX || y != lastY)
            LaserAdd(x, y)
    } else {
        DrawSegment(lastX, lastY, x, y)
    }
    lastX := x
    lastY := y
}

DrawPoll() {
    global drawOn, drawing, erasing, lastX, lastY, dragShapeMode, drawGui
    global dragOnOtherWindow, VK_LBUTTON, VK_RBUTTON, penStroke, penIgnoreMouse, penErasing
    global penLastX, penLastY
    ; **끼어들 수 없게 한다(Critical).** 드로잉을 끌 때(F9 등) 화면 크기의 판들을 돌려주는데, 그리던
    ; 도중에 단축키가 끼어들어 판을 돌려주면 돌아와서 없는 판에 그리다 오류가 난다(실제로 났다).
    ; 한 번 도는 데 몇 ms라, 단축키는 그만큼만 기다렸다 처리된다.
    Critical
    if !drawOn
        return
    MouseGetPos(&mx, &my, &winUnder)
    ; 판서 오버레이 위에 다른 창이 올라와 있으면(캡처 도구, 위젯 등) 진짜 마우스 커서를
    ; 돌려준다. 안 그러면 그 창 위에서 커서가 아예 안 보인다 — 판서 중에는 진짜 커서를
    ; 완전히 감추고 우리가 그리는 원으로 대신하는데, 그 원은 저 창들 아래에 깔리기 때문이다.
    UpdateDrawCursorForWindow(winUnder)
    ; 터치·펜으로 긋는 중이면 마우스 판정은 쳐다보지 않는다. 뒤늦게 따라 들어오는 마우스
    ; 입력까지 같이 그리면 **한 획이 두 번 그려지고 실행 취소도 두 칸**이 된다.
    ; 커서 원도 여기서 옮기지 않는다 — 포인터 메시지가 닿은 자리로 옮기고 있는데, 뒤처진 진짜
    ; 커서 자리로 되돌려 놓으면 원이 두 자리를 오가며 떨린다.
    if penStroke {
        penIgnoreMouse := true
        ; 터치로 긋는 도형은 여기서 마지막 자리까지 다시 그린다 (OnPointerUpdate 설명 참고)
        if (!penErasing && dragShapeMode != "")
            StrokeMove(penLastX, penLastY)
        return
    }
    ; 커서 노릇을 하는 원을 옮긴다. 버튼을 안 누르고 있어도 따라와야 하므로 아래
    ; "아무 버튼도 안 눌림 → 그냥 빠져나감"보다 앞에 둔다.
    MoveBrushCursor()

    leftDown := MouseDown(VK_LBUTTON)
    rightDown := MouseDown(VK_RBUTTON)
    ; 획이 끝난 뒤에도 마우스 쪽은 아직 "눌림"으로 남아 있다. 그게 풀릴 때까지 흘려보내야
    ; 손을 뗀 자리에 짧은 획이 하나 더 그려지지 않는다.
    if penIgnoreMouse {
        if (!leftDown && !rightDown)
            penIgnoreMouse := false
        drawing := false
        erasing := false
        LaserEnd()
        return
    }
    ; 오른쪽 버튼을 누르고 있는 동안에는 커서가 지우개 범위를 보여주는 원으로 바뀐다
    SetBrushMode(rightDown && !drawing ? "eraser" : "pen")
    if (!leftDown && !rightDown) {
        drawing := false
        erasing := false
        LaserEnd() ; 레이저 펜으로 긋던 중이면 이제부터 사라지기 시작한다
        return
    }

    ; 오른쪽 버튼 드래그는 지우개. 왼쪽으로 이미 그리는 중이면 그 획을 방해하지 않는다.
    if (rightDown && !drawing) {
        if !erasing {
            erasing := true
            lastX := mx
            lastY := my
            dragOnOtherWindow := winUnder != drawGui.Hwnd
            if !dragOnOtherWindow
                PushUndo()
        } else if !dragOnOtherWindow {
            EraseSegment(lastX, lastY, mx, my)
            lastX := mx
            lastY := my
        }
        return
    }
    if !leftDown
        return
    erasing := false

    if !drawing {
        drawing := true
            ; 마우스를 누른 순간 커서 아래에 있는 창이 판서 오버레이가 아니면, 그 위에 다른 창이
            ; 떠 있다는 뜻이다 — 위젯이나 Win+Shift+S 캡처 도구 오버레이처럼 위로 올라온 창
            ; 등. 그 창이 클릭을 받는 드래그이므로 판서로 그리지 않는다. 드래그를 시작한 시점에
            ; 한 번만 판단하고 마우스를 뗄 때까지 유지하므로, 설정 창 슬라이더를 끌다 커서가 창
            ; 밖으로 벗어나도 선이 그려지지 않는다. (예전엔 Win+Shift+S 뒤 드래그 "횟수"를
            ; 세어 건너뛰었는데, 캡처 도구가 툴바 클릭을 요구하는지가 Windows 버전마다 달라
            ; 첫 판서 한 획을 삼키거나 캡처 드래그가 그려지는 일이 있었다.)
        dragOnOtherWindow := winUnder != drawGui.Hwnd
        StrokeBegin(mx, my)
    } else {
        ; 일반·무지개 펜은 10ms 사이에 마우스가 실제로 지나간 점들도 이어서 긋는다 (MouseTrail 설명 참고)
        if (dragShapeMode = "" && dragPenKind != "laser" && !dragOnOtherWindow)
            for pt in MouseTrail(mx, my)
                StrokeMove(pt[1], pt[2])
        StrokeMove(mx, my)
    }
}

; 지난번 확인한 자리(lastX, lastY)에서 지금 자리(mx, my)까지 마우스가 지나간 중간 점들(오래된 순,
; 앞뒤 점은 빼고). 10ms마다 지금 자리만 보면 빨리 그을 때 점 사이가 멀어 선이 울퉁불퉁해진다.
; 타이머를 더 짧게 돌리면 CPU만 더 쓰므로, Windows가 기록해 둔 마우스 이동 이력을 가져온다.
; 가까운 점은 솎아(MOUSE_TRAIL_STEP_PX) 토막이 너무 잘아지지 않게 한다. 이력에서 지난 자리를 못
; 찾으면(좌표 단위가 다르거나 이력이 모자랄 때) 아무것도 돌려주지 않아 예전처럼 직선으로 잇는다.
MOUSE_TRAIL_STEP_PX := 4
MouseTrail(mx, my) {
    global lastX, lastY, MOUSE_TRAIL_STEP_PX
    static cur := Buffer(24, 0), buf := Buffer(24 * 64, 0) ; MOUSEMOVEPOINT: x, y, time, extra (64비트에서 24바이트)
    NumPut("int", mx, "int", my, "uint", 0, cur)
    n := DllCall("GetMouseMovePointsEx", "uint", 24, "ptr", cur, "ptr", buf, "int", 64, "uint", 1, "int") ; 1 = 화면 좌표
    if (n < 3)
        return []
    pts := []
    found := false
    loop n {
        x := NumGet(buf, (A_Index - 1) * 24, "int"), y := NumGet(buf, (A_Index - 1) * 24 + 4, "int")
        if (x > 32767) ; 이력의 좌표는 16비트라 왼쪽·위 모니터의 음수가 큰 양수로 온다
            x -= 65536
        if (y > 32767)
            y -= 65536
        if (A_Index = 1) {
            if (x != mx || y != my)
                return []
            continue
        }
        if (x = lastX && y = lastY) {
            found := true
            break
        }
        pts.Push([x, y])
    }
    if !found
        return []
    ; pts는 새것부터라 거꾸로 훑으며, 앞 점에서 STEP 이상 떨어진 것만 남긴다 (지금 자리와도 그만큼 떨어지게)
    out := []
    px := lastX, py := lastY
    loop pts.Length {
        p := pts[pts.Length - A_Index + 1]
        if ((p[1] - px) ** 2 + (p[2] - py) ** 2 >= MOUSE_TRAIL_STEP_PX ** 2
            && (p[1] - mx) ** 2 + (p[2] - my) ** 2 >= MOUSE_TRAIL_STEP_PX ** 2) {
            out.Push(p)
            px := p[1], py := p[2]
        }
    }
    return out
}

; ================= 픽셀 단위 투명도를 가진 작은 그림판 =================
; 강조 원과 클릭 링이 함께 쓴다. 예전에는 창을 원 모양으로 잘라내거나(강조) 특정 색을
; 투명색으로 지정하는(클릭 링) 방식이었는데, 둘 다 가장자리가 계단처럼 각져 보였다.
; 픽셀마다 투명도를 담을 수 있는 그림판에 GDI+로 그리면 테두리가 매끄럽게 나온다.
CreateAlphaCanvas(w, h) {
    bi := Buffer(40, 0)
    NumPut("UInt", 40, bi, 0), NumPut("Int", w, bi, 4), NumPut("Int", -h, bi, 8) ; 음수 = 위에서 아래로
    NumPut("UShort", 1, bi, 12), NumPut("UShort", 32, bi, 14), NumPut("UInt", 0, bi, 16)
    bits := 0
    screenDC := DllCall("GetDC", "ptr", 0, "ptr")
    dc := DllCall("CreateCompatibleDC", "ptr", screenDC, "ptr")
    bmp := DllCall("CreateDIBSection", "ptr", screenDC, "ptr", bi, "uint", 0, "ptr*", &bits, "ptr", 0, "uint", 0, "ptr")
    DllCall("SelectObject", "ptr", dc, "ptr", bmp)
    DllCall("ReleaseDC", "ptr", 0, "ptr", screenDC)
    pBitmap := 0, pGraphics := 0
    DllCall("gdiplus\GdipCreateBitmapFromScan0", "int", w, "int", h, "int", w * 4, "int", 0xE200B, "ptr", bits, "ptr*", &pBitmap)
    if pBitmap {
        DllCall("gdiplus\GdipGetImageGraphicsContext", "ptr", pBitmap, "ptr*", &pGraphics)
        if pGraphics
            DllCall("gdiplus\GdipSetSmoothingMode", "ptr", pGraphics, "int", 4) ; 매끄럽게
    }
    return {w: w, h: h, dc: dc, bmp: bmp, bitmap: pBitmap, graphics: pGraphics}
}

DestroyAlphaCanvas(c) {
    if !IsObject(c)
        return
    if c.graphics
        DllCall("gdiplus\GdipDeleteGraphics", "ptr", c.graphics)
    if c.bitmap
        DllCall("gdiplus\GdipDisposeImage", "ptr", c.bitmap)
    if c.dc
        DllCall("DeleteDC", "ptr", c.dc)
    if c.bmp
        DllCall("DeleteObject", "ptr", c.bmp)
}

; 그림판 내용을 창에 올린다. 위치와 그림을 한 번에 바꾸기 때문에, 지우고 다시 그리는 찰나가
; 없어 깜빡이지 않는다. constAlpha는 그림 전체에 한 번 더 곱해지는 불투명도다.
PushCanvasToWindow(hwnd, c, x, y, constAlpha := 255) {
    static ptDst := Buffer(8, 0), size := Buffer(8, 0), ptSrc := Buffer(8, 0), blend := Buffer(4, 0)
    NumPut("Int", x, ptDst, 0), NumPut("Int", y, ptDst, 4)
    NumPut("Int", c.w, size, 0), NumPut("Int", c.h, size, 4)
    NumPut("UChar", 0, blend, 0), NumPut("UChar", 0, blend, 1)
    NumPut("UChar", constAlpha, blend, 2), NumPut("UChar", 1, blend, 3) ; AC_SRC_ALPHA
    DllCall("UpdateLayeredWindow", "ptr", hwnd, "ptr", 0, "ptr", ptDst, "ptr", size
        , "ptr", c.dc, "ptr", ptSrc, "uint", 0, "ptr", blend, "uint", 2) ; ULW_ALPHA
}

; ================= 마우스 강조(스포트라이트) 창 =================
; 그림은 크기·색·투명도가 바뀔 때만 다시 그리고, 마우스를 따라다닐 때는 위치만 옮긴다.
spotGui := Gui("+AlwaysOnTop -Caption +ToolWindow +E0x80020", "FocusDraw-Spot") ; 0x80000 = 레이어드, 0x20 = 클릭 통과
spotGui.Show("w" SpotSize " h" SpotSize " Hide")
spotCanvas := ""

RedrawSpotlight() {
    global spotGui, spotCanvas, SpotSize, spotOpacity, spotColor
    DestroyAlphaCanvas(spotCanvas)
    spotCanvas := CreateAlphaCanvas(SpotSize, SpotSize)
    if !spotCanvas.graphics
        return
    DllCall("gdiplus\GdipGraphicsClear", "ptr", spotCanvas.graphics, "uint", 0x00000000)
    ; 투명도를 픽셀 자체에 담는다. 예전처럼 창 전체 투명도를 따로 지정하는 방식은 픽셀 단위
    ; 투명도와 같이 쓸 수 없다.
    alpha := Max(0, Min(255, Round(spotOpacity * 255 / 100)))
    brush := 0
    DllCall("gdiplus\GdipCreateSolidFill", "uint", (alpha << 24) | spotColor, "ptr*", &brush)
    if brush {
        ; 매끄럽게 처리한 가장자리가 잘리지 않도록 반 픽셀씩 안쪽으로 채운다
        DllCall("gdiplus\GdipFillEllipse", "ptr", spotCanvas.graphics, "ptr", brush
            , "float", 0.5, "float", 0.5, "float", SpotSize - 1, "float", SpotSize - 1)
        DllCall("gdiplus\GdipDeleteBrush", "ptr", brush)
    }
    DllCall("gdiplus\GdipFlush", "ptr", spotCanvas.graphics, "int", 0)
    x := 0, y := 0
    try WinGetPos(&x, &y, , , spotGui)
    PushCanvasToWindow(spotGui.Hwnd, spotCanvas, x, y)
}
RedrawSpotlight()

; 설정 창에서 크기를 바꿀 때, 강조 원과 클릭 링 그림판을 즉시 다시 만든다.
ApplySpotlightAppearance() {
    RedrawSpotlight()
    SetupClickCanvas()
}

UpdateSpotlightColor() {
    RedrawSpotlight()
}

SpotFollow() {
    global spotlightOn, spotGui, SpotSize
    if !spotlightOn
        return
    MouseGetPos(&mx, &my)
    WinMove(mx - SpotSize // 2, my - SpotSize // 2,,, spotGui)
}

; ================= 클릭 시 원이 오므라드는 애니메이션 =================
; spotGui와 별개의 작은 창을 하나 더 써서, 클릭한 순간에만 진한 테두리 원을 그려
; 바깥쪽에서 중심으로 줄어들게 만든 뒤 사라지게 한다.
; 프레임 수를 늘릴수록 한 프레임이 담당하는 반경 변화폭이 작아져서 더 부드럽게 보인다.
; 클릭할 때만 잠깐 실행되고 끝나는 애니메이션이라(계속 다시 그리는 판서 오버레이와 달리),
; 프레임을 늘려도 체감될 정도의 성능 부담은 없다.
CLICK_ANIM_FRAMES := 30 ; 빠르기(간격 ms)는 좌·우 버튼이 각각 settings.ini에서 불러온 값을 쓴다

; 왼쪽 버튼과 오른쪽 버튼이 **서로 다른 색·굵기·투명도·빠르기**를 가질 수 있어야 하고,
; 두 애니메이션이 겹쳐 돌 수도 있어서 창과 진행 상태를 각각 하나씩 둔다.
; 그리는 방법은 똑같으므로 함수는 하나로 두고 어느 쪽인지만 넘긴다("L" / "R").
clickAnim := Map(
    "L", {gui: 0, canvas: "", frame: 0},
    "R", {gui: 0, canvas: "", frame: 0})
for side in ["L", "R"] {
    g := Gui("+AlwaysOnTop -Caption +ToolWindow +E0x80020", "FocusDraw-Click" side) ; 0x80000 = 레이어드, 0x20 = 클릭 통과
    g.Show("w" SpotSize " h" SpotSize " Hide")
    clickAnim[side].gui := g
}

SetupClickCanvas() {
    global clickAnim, SpotSize
    for side, a in clickAnim {
        DestroyAlphaCanvas(a.canvas)
        a.canvas := CreateAlphaCanvas(SpotSize, SpotSize)
    }
}
SetupClickCanvas()

; 어느 쪽 버튼의 설정을 쓸지 한곳에서 고른다 — 아래 그리기·시작 코드가 둘을 구분하지 않아도 된다.
ClickStyle(side) {
    global clickColor, SpotThickness, clickOpacity, CLICK_ANIM_INTERVAL, clickEffectEnabled
    global rclickColor, rclickThickness, rclickOpacity, RCLICK_ANIM_INTERVAL, rclickEffectEnabled
    if (side = "R")
        return {color: rclickColor, thickness: rclickThickness, opacity: rclickOpacity
            , interval: RCLICK_ANIM_INTERVAL, enabled: rclickEffectEnabled}
    return {color: clickColor, thickness: SpotThickness, opacity: clickOpacity
        , interval: CLICK_ANIM_INTERVAL, enabled: clickEffectEnabled}
}

ClickAnimStepFor(side) {
    global clickAnim, CLICK_ANIM_FRAMES, SpotSize
    a := clickAnim[side]
    st := ClickStyle(side)
    if (a.frame >= CLICK_ANIM_FRAMES) {
        SetTimer(side = "R" ? RClickAnimStep : ClickAnimStep, 0)
        a.gui.Hide()
        return
    }
    MouseGetPos(&mx, &my)
    if a.canvas.graphics {
        DllCall("gdiplus\GdipGraphicsClear", "ptr", a.canvas.graphics, "uint", 0x00000000)

        ; 등속 대신 감속(ease-out) 곡선을 써서, 처음엔 빠르게 줄어들다가 중심 근처에서
        ; 서서히 멈추는 것처럼 보이게 한다 — 등속보다 훨씬 자연스럽게 느껴진다.
        t := a.frame / CLICK_ANIM_FRAMES
        eased := 1 - (1 - t) ** 3
        radius := (SpotSize / 2 - st.thickness / 2 - 1) * (1 - eased)
        ; 감속 곡선이라 마지막 4분의 1가량은 반지름이 몇 픽셀밖에 안 된다. 그때도 테두리를 설정한
        ; 굵기 그대로 그리면 테두리가 반지름보다 두꺼워져서, 원이 마름모·삼각형처럼 찌그러진
        ; 덩어리로 보였다(그림으로 뽑아 확인). 그래서 **테두리는 반지름을 넘지 않게 가늘어져 끝까지
        ; 속이 빈 고리로 남고**, 반지름이 굵기의 1.5배보다 작아지면 그만큼 옅어지며 사라진다.
        ; 1픽셀보다 작아지면 더 보여줄 것이 없으므로 거기서 끝낸다.
        if (radius < 1) {
            a.frame := CLICK_ANIM_FRAMES
            SetTimer(side = "R" ? RClickAnimStep : ClickAnimStep, 0)
            a.gui.Hide()
            return
        }
        width := Min(st.thickness, radius)
        fade := Min(1, radius / (st.thickness * 1.5))
        cx := SpotSize / 2, cy := SpotSize / 2
        pen := 0
        DllCall("gdiplus\GdipCreatePen1", "uint", (Round(255 * fade) << 24) | st.color, "float", width, "int", 2, "ptr*", &pen)
        if pen {
            DllCall("gdiplus\GdipDrawEllipse", "ptr", a.canvas.graphics, "ptr", pen
                , "float", cx - radius, "float", cy - radius, "float", radius * 2, "float", radius * 2)
            DllCall("gdiplus\GdipDeletePen", "ptr", pen)
        }
        DllCall("gdiplus\GdipFlush", "ptr", a.canvas.graphics, "int", 0)

        ; 위치와 그림을 한 번에 올린다. 예전에는 화면에 지우고 다시 그리는 찰나가 보여서
        ; 테두리가 두 개로 보이는 깜빡임이 있었는데, 이 방식은 그 틈이 아예 없다.
        PushCanvasToWindow(a.gui.Hwnd, a.canvas, mx - SpotSize // 2, my - SpotSize // 2
            , Max(0, Min(255, Round(st.opacity * 255 / 100))))
    }
    a.frame += 1
}
; 타이머는 함수를 이름으로 구분하므로 쪽마다 하나씩 필요하다
ClickAnimStep() => ClickAnimStepFor("L")
RClickAnimStep() => ClickAnimStepFor("R")

StartClickAnimation(side) {
    global spotlightOn, drawOn, clickAnim
    st := ClickStyle(side)
    ; 판서 중에는 강조 하이라이트 자체를 감춰두므로, 클릭 링 효과도 같이 쉰다
    if (!spotlightOn || drawOn || !st.enabled)
        return
    a := clickAnim[side]
    a.frame := 0
    a.gui.Show("NA")
    SetTimer(side = "R" ? RClickAnimStep : ClickAnimStep, st.interval)
}
~LButton::StartClickAnimation("L")
~RButton::StartClickAnimation("R")

; ================= 마우스 커서 바꿔치기 (강조 중 십자선 / 드로잉 중 원) =================
; 마우스 커서는 각 창이 스스로 그리기 때문에, 단순히 "커서 숨김" API 하나로는 다른 프로그램
; 창 위로 마우스가 지나가는 순간 커서가 다시 나타난다. 대신 시스템 커서 전체(화살표, 손,
; 입력창의 I자 등 전부)를 작은 십자선 모양의 커서로 통째로 바꿔치기해서, 어떤 창 위에 있든
; 일관되게 위치를 알 수 있게 한다. (완전히 투명하게 만들면 클릭 지점을 눈으로 짚기 어려워서
; 십자선으로 대신함) SystemParametersInfo(SPI_SETCURSORS)로 한 번에 기본값으로 되돌릴 수 있다.
CURSOR_IDS := [32512, 32513, 32514, 32515, 32516, 32642, 32643, 32644, 32645, 32646, 32648, 32649, 32650, 32651]
; OCR_NORMAL, OCR_IBEAM, OCR_WAIT, OCR_CROSS, OCR_UP, OCR_SIZENWSE, OCR_SIZENESW, OCR_SIZEWE,
; OCR_SIZENS, OCR_SIZEALL, OCR_NO, OCR_HAND, OCR_APPSTARTING, OCR_HELP
systemCursorHidden := false

; 1비트(흑백) 커서 마스크에서 (x,y) 픽셀 하나를 켜고 끈다. 32x32 커서는 한 줄이 정확히
; 4바이트(32비트)이고, 한 바이트 안에서는 왼쪽 픽셀이 상위 비트(MSB)에 대응한다.
SetMonoBit(mask, x, y, bit) {
    byteIndex := y * 4 + (x // 8)
    bitPos := 7 - Mod(x, 8)
    b := NumGet(mask, byteIndex, "UChar")
    b := bit ? (b | (1 << bitPos)) : (b & ~(1 << bitPos) & 0xFF)
    NumPut("UChar", b, mask, byteIndex)
}

; 참고: Windows는 여기서 넘긴 커서에 "마우스 포인터 크기" 설정 배율을 한 번 더 곱해서 그린다.
; 비트맵을 그 크기로 키워 넘겨봐도 배율은 그 위에 또 걸려서 소용이 없었다(실제로 해봄).
; 그래서 커서로는 화면 픽셀과 정확히 맞아떨어지는 그림을 그릴 수 없다 — 드로잉 모드의 원을
; 커서가 아니라 별도의 창(brushGui)으로 만든 이유다. 십자선은 "커서를 눈에 안 띄게 한다"가
; 목적이라 배율이 걸려도 상관없으므로 예전처럼 32x32로 둔다.
CreateCrosshairCursor() {
    size := 32, center := 16, armLen := 2 ; 중심에서 양쪽으로 2px — 가늘고 작은 십자선
    andMask := Buffer(128, 0xFF) ; 기본은 전부 투명(원래 화면 그대로 통과)
    xorMask := Buffer(128, 0x00) ; AND=0인 자리는 XOR 그대로(0=검정)가 표시됨
    loop (armLen * 2 + 1)
        SetMonoBit(andMask, center - armLen + (A_Index - 1), center, 0)
    loop (armLen * 2 + 1)
        SetMonoBit(andMask, center, center - armLen + (A_Index - 1), 0)
    return DllCall("CreateCursor", "ptr", 0, "int", center, "int", center, "int", size, "int", size, "ptr", andMask, "ptr", xorMask, "ptr")
}

; 드로잉 모드용 — 아무것도 그리지 않는 완전히 투명한 커서. 드로잉 중에는 그어질 선을 그대로
; 보여주는 원(brushGui)이 커서 노릇을 하므로, Windows가 그리는 커서는 완전히 치운다.
; 마스크 전체가 AND=1, XOR=0이면 화면이 그대로 통과해 아무것도 보이지 않는다.
; 아무것도 안 그리는 커서라 포인터 크기 배율이 걸려도 상관없어서 크기는 32로 둔다.
CreateBlankCursor() {
    size := 32, stride := 4
    andMask := Buffer(stride * size, 0xFF)
    xorMask := Buffer(stride * size, 0x00)
    return DllCall("CreateCursor", "ptr", 0, "int", 0, "int", 0, "int", size, "int", size, "ptr", andMask, "ptr", xorMask, "ptr")
}

; 지금 어떤 커서를 씌워두었는지 — 같은 커서를 다시 씌우는 헛수고를 피하려고 기억해둔다.
; "" = 시스템 기본 커서.
currentCursorKind := ""

ApplySystemCursor(kind) {
    global CURSOR_IDS, systemCursorHidden, currentCursorKind
    for id in CURSOR_IDS {
        ; 넘긴 커서는 시스템이 소유/해제하므로 ID마다 따로 만들어 넘겨야 한다
        hCursor := (kind = "blank") ? CreateBlankCursor() : CreateCrosshairCursor()
        if hCursor
            DllCall("SetSystemCursor", "ptr", hCursor, "uint", id)
    }
    systemCursorHidden := true
    currentCursorKind := kind
}

RestoreSystemCursor(*) {
    global systemCursorHidden, currentCursorKind
    if !systemCursorHidden
        return
    DllCall("SystemParametersInfo", "uint", 0x57, "uint", 0, "ptr", 0, "uint", 0) ; SPI_SETCURSORS
    systemCursorHidden := false
    currentCursorKind := ""
}
OnExit(RestoreSystemCursor) ; 커서가 숨겨진 채로 프로그램이 종료되는 일이 없도록 보험

; 커서를 바꿔야 하는 이유가 두 가지(강조 중 커서 숨기기 설정 + 판서 모드)이고 모양도 서로
; 달라서, 매번 따로 켜고 끄는 대신 "지금 상태를 종합하면 어떤 커서여야 하나?"를 한곳에서
; 판단한다. 판서 중에는 그어질 선을 보여주는 원(brushGui)이 커서 노릇을 하므로 진짜 커서는
; 완전히 감추고("blank"), 강조 중 커서 숨기기는 예전처럼 작은 십자선("cross")을 쓴다.
UpdateCursorHiddenState() {
    global spotlightOn, hideCursorOnHighlight, drawOn, systemCursorHidden, currentCursorKind
    kind := drawOn ? "blank" : ((spotlightOn && hideCursorOnHighlight) ? "cross" : "")
    if (kind = "") {
        if systemCursorHidden
            RestoreSystemCursor()
        return
    }
    if (!systemCursorHidden || currentCursorKind != kind)
        ApplySystemCursor(kind)
}

; SetSystemCursor로 바꾼 커서는 이 프로그램이 아니라 Windows 세션 전체에 적용되는
; 상태라서, 작업 관리자로 강제 종료되는 등 OnExit이 실행되지 못하고 죽으면 커서가 숨겨진
; 채로 계속 남는다. 그런 경우를 대비해 시작할 때 한 번 무조건 기본 커서로 되돌려둔다.
DllCall("SystemParametersInfo", "uint", 0x57, "uint", 0, "ptr", 0, "uint", 0) ; SPI_SETCURSORS

; ================= 토글 / 동작 함수 =================
; 강조 하이라이트는 "강조가 켜져 있고 + 판서 모드가 아닐 때"만 화면에 보인다. 판서 중에는
; 그림 그리는 데 방해만 되므로 화면 표시만 잠깐 멈춘다(강조 자체를 끄는 게 아니라, 판서를
; 끄면 다시 보임). 강조/판서 어느 쪽을 토글하든 여기서 한 번에 판단하므로, 판서 중에
; 단축키나 트레이 아이콘으로 강조를 켜도 하이라이트가 튀어나오지 않는다.
UpdateSpotlightVisibility() {
    global spotlightOn, drawOn, spotGui
    if spotlightOn && !drawOn {
        spotGui.Show("NA")
        SetTimer(SpotFollow, 15)
    } else {
        SetTimer(SpotFollow, 0)
        spotGui.Hide()
    }
}

ToggleSpotlight(*) {
    global spotlightOn
    spotlightOn := !spotlightOn
    UpdateSpotlightVisibility()
    UpdateCursorHiddenState()
    UpdateWidgetState()
}

ToggleDraw(*) {
    global drawOn, drawGui, brushGui, widget, settingsGui, settingsHiddenByDraw, activeDrawColor, drawColor
    global activeDrawThickness, activeDrawStep, DrawStep, activeEraserSize, activeEraserStep, EraserStep
    global PEN_BASE_PX, PEN_STEP_RATIO, ERASER_BASE_PX, ERASER_STEP_RATIO
    global erasing, brushMode, boardGui, stepGui, laserGui, penKind, activeDrawAlpha, rainbowColor
    drawOn := !drawOn
    ; 숫자키와 +/-로 잠깐 바꿔둔 색·굵기·지우개 크기는 여기서 초기화한다. 드로잉을 켤 때마다
    ; 설정에 저장된 값으로 시작하고, Esc 등으로 끄면 그 자리에서 되돌아간다. A·S로 고른 특수 펜도.
    penKind := ""
    rainbowColor := false
    activeDrawColor := drawColor
    activeDrawAlpha := StartAlpha(100)
    activeDrawStep := DrawStep
    activeEraserStep := EraserStep
    activeDrawThickness := PenPx(DrawStep)
    activeEraserSize := EraserPx(EraserStep)
    SetTimer(HideStepNumber, 0)
    stepGui.Hide() ; 단계 숫자가 떠 있는 채로 모드가 바뀌면 화면에 남는다
    brushMode := "pen"
    erasing := false
    if drawOn {
        drawGui.Show("NA")
        ; 레이저 펜의 창은 판서 층 **바로 위**에 둔다 (그래서 판서 층 다음에 띄운다)
        laserGui.Show("NA")
        ; 오버레이가 화면 전체를 덮지만, 판서를 끌 수단은 남아 있어야 하므로 위젯만 위로 올린다
        WinSetAlwaysOnTop(true, widget)
        ; 커서 노릇을 할 원은 위젯보다도 위에 띄운다 — 판서 중에는 진짜 커서가 완전히 감춰져
        ; 있어서, 위젯 위에서도 이 원이 보여야 어디를 누르는지 알 수 있다. 클릭 통과 창이라
        ; 위에 있어도 위젯 클릭이나 판서 입력을 가로채지 않는다(MouseGetPos가 건너뛴다).
        brushGui.Show("NA")
        ; **마지막에 쓰던 칠판을 그대로 다시 깐다.** 단축키로 끄면 그려둔 글씨가 남아 있는데,
        ; 칠판만 걷혀 있으면 흰 칠판에 쓴 글씨가 바탕화면 위에 떠 있는 꼴이 되어 못 알아본다.
        ; (Esc나 위젯 버튼으로 끄면 글씨와 함께 칠판도 걷힌다 — ExitDrawMode 참고)
        ; 판서 층을 띄운 **뒤에** 깔아야 그 아래로 정확히 들어간다.
        SetBoardColor(boardColor, boardAlpha)
        ; 오버레이는 그린 자국 말고는 거의 투명해서, 설정 창이 열려 있으면 눈에는 보이는데
        ; 클릭은 오버레이가 가로채는 이상한 상태가 된다. 아예 잠시 감춰서 헷갈리지 않게 한다.
        settingsHiddenByDraw := false
        if SettingsWindowExists() {
            settingsGui.Hide()
            settingsHiddenByDraw := true
        }
        SetTimer(DiscardUndoHistory, 0) ; 30초 안에 다시 켰으면 실행 취소 기록을 그대로 둔다
        SetTimer(DrawPoll, 10)
        SetDrawModeHotkeys("On")
    } else {
        SetTimer(DrawPoll, 0)
        SetTimer(DiscardUndoHistory, -UNDO_KEEP_MS) ; 끈 채로 30초 지나면 실행 취소 기록을 비운다
        SetDrawModeHotkeys("Off")
        brushGui.Hide()
        LaserClearAll()   ; 레이저 그림판도 함께 돌려준다
        laserGui.Hide()
        FreeInkLayer()    ; 반투명 획 전용 판도 다음에 쓸 때 다시 만든다
        FreeSnapshot()    ; 드래그 시작 때 뜨는 복사본도
        drawGui.Hide()
        ; 칠판은 감추기만 하고 무슨 색이었는지는 기억해둔다 (다시 켤 때 그대로 깔린다)
        SetBoardColor(boardColor, boardAlpha)
        ; 판서를 켜느라 감췄던 설정 창이라면 하던 작업을 이어갈 수 있게 다시 띄운다
        if settingsHiddenByDraw {
            settingsHiddenByDraw := false
            if IsSet(settingsGui)
                try settingsGui.Show()
        }
    }
    UpdateSpotlightVisibility()
    UpdateCursorHiddenState() ; 판서 중에는 진짜 커서를 완전히 감춘다 (원이 커서 노릇을 한다)
    if drawOn
        RedrawBrushCursor() ; 이번에 쓸 색·굵기로 원을 그려둔다
    ; 드로잉을 켤 때만이 아니라 **끌 때도** 위젯을 맨 앞으로 올려야 한다. 켤 때 올려둔 순서가
    ; 끄면서 풀려, 작업표시줄 위에 둔 위젯이 작업표시줄 뒤로 밀려 사라진 것처럼 보였다.
    ; 여기서 한 번 올리고, **조금 있다가 한 번 더** 올린다 — 오버레이를 감추고 나면 Windows가
    ; 뒤늦게 작업표시줄을 앞으로 올리기 때문에, 지금 올려둔 것만으로는 도로 밀린다.
    RaiseWidget()
    SetTimer(RaiseWidget, -150)
    UpdateWidgetState()
}

ClearDrawing(*) {
    global vh
    ; 실수로 다 지웠을 때 Ctrl+Z로 되살릴 수 있게 한다. 이때는 화면 전체가 바뀌므로 전부 담는다
    ; — 실행 취소 한 단계로는 가장 큰 경우지만, 자주 하는 동작이 아니라 이대로 둔다.
    PushUndo()
    CaptureUndoBands(0, vh - 1)
    ClearBackBuffer()
    UpdateOverlay()
}

; 드로잉 중 숫자키로 선 색을 바로 바꾼다. 설정에 저장된 색(drawColor)은 건드리지 않아서,
; 드로잉을 껐다 켜면 원래 색으로 돌아온다. 커서 원도 바뀐 색으로 다시 그린다.
; **0은 설정 창의 기본 색으로 되돌아오는 자리다** — 그 색은 투명도를 따로 갖지 않으므로 100%로 본다.
; 숫자키는 **보통 펜으로 돌아오는 키**이기도 하다 — A·S로 고른 특수 펜을 여기서 푼다(SetPenKind 참고).
SetDrawColor(index) {
    global DRAW_COLORS, DRAW_ALPHAS, DRAW_STEPS, activeDrawColor, activeDrawAlpha, drawColor, penKind, rainbowColor
    global activeDrawStep, activeDrawThickness
    penKind := "" ; 레이저 점은 LaserTick이 다음 프레임에 걷는다
    rainbowColor := false ; 무지개도 풀린다 — 그 뒤 A는 이 색의 레이저
    if (index = 0) {
        activeDrawColor := drawColor
        activeDrawAlpha := StartAlpha(100)
        RedrawBrushCursor()
        return
    }
    if (index >= 1 && index <= DRAW_COLORS.Length) {
        activeDrawColor := DRAW_COLORS[index]
        activeDrawAlpha := StartAlpha(DRAW_ALPHAS[index])
        activeDrawStep := DRAW_STEPS[index] ; 굵기도 그 숫자키의 단계로
        activeDrawThickness := PenPx(activeDrawStep)
        RedrawBrushCursor()
    }
}

; 지금 긋는 선의 색을 GDI+가 받는 형식(알파가 앞에 붙은 32비트)으로 돌려준다.
; 펜을 만드는 곳이 여러 군데라(자유선 / 도형 / 화살촉 / 커서 원) 한곳에 모아둔다.
ActiveARGB() {
    global activeDrawColor, activeDrawAlpha
    return (Round(Max(5, Min(100, activeDrawAlpha)) * 255 / 100) << 24) | activeDrawColor
}

; 드로잉 중 +(크게) / -(작게). 그냥 누르면 **펜 굵기**를, **오른쪽 버튼을 누른 채로** 누르면
; **지우개 크기**를 바꾼다. 오른쪽 버튼을 누르고 있는 동안에는 커서가 지우개 테두리 원으로
; 바뀌어 있으므로, 바뀌는 크기가 그 자리에서 눈에 보인다.
; 색과 마찬가지로 설정값(DrawThickness / EraserSize)은 건드리지 않아, 드로잉을 껐다 켜면
; 되돌아온다.
AdjustDrawThickness(delta) {
    global activeDrawThickness, activeDrawStep, activeEraserSize, activeEraserStep
    global STEP_MAX, PEN_BASE_PX, PEN_STEP_RATIO, ERASER_BASE_PX, ERASER_STEP_RATIO, VK_RBUTTON
    ; 여기도 물리 판정을 쓰지 않는다 — 이유는 MouseDown() 위의 설명 참고
    if MouseDown(VK_RBUTTON) {
        newStep := Max(1, Min(STEP_MAX, activeEraserStep + delta))
        activeEraserStep := newStep
        activeEraserSize := EraserPx(newStep)
        RedrawBrushCursor()
        ShowStepNumber(newStep) ; 상·하한에 걸려 안 바뀌어도 보여준다 — 끝에 닿았다는 신호가 된다
        return
    }
    newStep := Max(1, Min(STEP_MAX, activeDrawStep + delta))
    activeDrawStep := newStep
    activeDrawThickness := PenPx(newStep)
    RedrawBrushCursor()
    ShowStepNumber(newStep)
}

; 숫자키와 같은 이유로(반복문 안에서 화살표 함수를 바로 쓰면 마지막 값 하나만 남는다) 가둬둔다.
MakeThicknessSetter(delta) => (*) => AdjustDrawThickness(delta)

; 드로잉 중 **마우스 휠**로 지금 긋는 색의 투명도를 바꾼다. 위로 굴리면 진하게, 아래로
; 굴리면 연하게. 굵기를 +/-로 바꿀 때처럼 바뀐 값을 커서 옆에 잠깐 띄운다.
; 휠을 고른 이유는 손이 이미 마우스에 있기 때문이다 — 칠판 앞에서 키보드까지 가지 않아도 된다.
; 색·굵기와 마찬가지로 **설정값(DRAW_ALPHAS)은 건드리지 않는다.** 드로잉을 껐다 켜거나 다른
; 숫자키를 누르면 그 색에 정해둔 투명도로 돌아온다.
ALPHA_WHEEL_STEP := 5 ; 한 틱에 바뀌는 양(%)
AdjustDrawAlpha(delta) {
    global activeDrawAlpha, ALPHA_WHEEL_STEP
    ; 0%까지 내려가면 "안 그려지는 펜"이 되어 고장으로 보인다. 설정 창과 같이 5%를 바닥으로 둔다.
    newAlpha := Max(5, Min(100, activeDrawAlpha + delta * ALPHA_WHEEL_STEP))
    activeDrawAlpha := newAlpha
    RedrawBrushCursor() ; 커서 원도 바뀐 진하기로 보여준다
    ShowStepNumber(newAlpha "%") ; 끝에 닿아 값이 안 바뀌어도 보여준다 — 끝이라는 신호가 된다
}

MakeAlphaSetter(delta) => (*) => AdjustDrawAlpha(delta)

; 숫자키마다 서로 다른 색을 기억한 함수를 만들어준다. 반복문 안에서 화살표 함수를 바로 쓰면
; 모두 같은 변수를 붙들어 마지막 색 하나만 적용되므로, 이렇게 매개변수로 가둬야 한다.
MakeColorSetter(index) => (*) => SetDrawColor(index)

; 도형 키가 지금 눌려 있는지 기록한다. 키를 삼키는 핫키라 눌린 상태를 나중에 물어볼 수 없어서
; (흉내낸 입력으로 확인해보면 GetKeyState(..., "P")가 0으로 나온다) 누를 때와 뗄 때 직접 적어둔다.
SetShapeKeyHeld(key, down) {
    global shapeKeyHeld
    shapeKeyHeld[key] := down
}

; 색 설정과 같은 이유로 함수를 만들어 쓴다 — 반복문 안에서 화살표 함수를 바로 쓰면 모두 같은
; 변수를 붙들어 마지막 키 하나만 제대로 동작한다.
MakeShapeKeyTracker(key, down) => (*) => SetShapeKeyHeld(key, down)

; A·S: 특수 펜을 고른다. **한 번 누르면 계속 그 펜이다** — 전자칠판 앞에서는 키를 쥔 채로 칠판에
; 그을 수 없어서 "누른 채로 긋기"를 바꿨다(2026-09-28 사용자 요청). 숫자키로 색을 고르면 보통
; 펜으로 돌아온다(SetDrawColor). 긋는 중에 바꿔도 지금 획은 그대로이고 다음 획부터 바뀐다.
; S를 고르면 숫자키를 누를 때까지 무지개가 이어진다(rainbowColor) — 그 사이 A는 무지개 레이저다.
SetPenKind(kind) {
    global penKind, rainbowColor
    penKind := kind
    if (kind = "rainbow")
        rainbowColor := true
    if (kind = "laser")
        LaserKeyDown() ; 커서 자리에 레이저 점을 띄운다
    RedrawBrushCursor() ; 무지개면 커서 원이 무지개 원판이 된다
}

MakePenKindSetter(kind) => (*) => SetPenKind(kind)

; Esc: 판서 내용을 지우고 판서 모드까지 종료
; **칠판도 함께 걷는다.** 이쪽은 "이제 다 썼으니 정리한다"는 뜻이라, 다음에 켤 때는 아무것도
; 없는 상태에서 시작하는 게 맞다. (단축키로 끌 때는 글씨도 칠판도 그대로 둔다 — ToggleDraw 참고)
ExitDrawMode(*) {
    ClearDrawing()
    SetBoardColor(-1)
    ToggleDraw()
}

; 위젯의 판서 버튼. **끌 때는 그려둔 내용까지 지운다 — Esc와 같은 효과다.**
; 단축키로 끌 때는 일부러 그대로 남긴다. 그쪽은 "잠시 다른 걸 만졌다가 이어서 쓴다"는 흐름이고,
; 버튼은 "이제 다 썼으니 정리한다"는 흐름이기 때문이다. Esc를 쓰기 어려워하는 분들에게는
; 이 버튼이 사실상 유일한 "지우고 나가기" 수단이 된다.
; (실수로 지웠더라도 30초 안에 판서를 다시 켜고 Ctrl+Z를 누르면 돌아온다 — DiscardUndoHistory 참고)
ToggleDrawFromWidget(*) {
    global drawOn
    if drawOn
        ExitDrawMode()
    else
        ToggleDraw()
}

; 포인터(강조 원) / 클릭효과(링) / 드로잉(선)은 각각 자기 색을 갖는다. 셋을 한 색으로 묶어두면
; 예컨대 "강조는 은은한 노랑, 판서는 진한 빨강"처럼 쓰임새가 다른 조합을 만들 수 없다.
; 어느 색을 가리키는지는 문자열 하나로 넘기고, 읽고 쓰는 곳을 이 두 함수에만 모아둔다.
GetColorOf(target) {
    global spotColor, clickColor, rclickColor, drawColor, widgetBgColor
    return (target = "Spot") ? spotColor : (target = "Click") ? clickColor
        : (target = "RClick") ? rclickColor
        : (target = "Widget") ? widgetBgColor : drawColor
}

; Windows 기본 색상 선택 대화상자(ChooseColor)를 띄워 색 하나를 고르게 하고, 고른
; 색(0xRRGGBB)을 돌려준다. 취소하면 -1.
; 고른 색을 어디에 넣을지는 부르는 쪽이 정한다 — 쓰는 곳이 여럿이라 여기서 갈래를 치지 않는다.
; ownerHwnd는 대화상자를 띄운 창의 Hwnd다. 안 주면 대화상자가 그 창 뒤로 가려질 수 있다.
ChooseColorDialog(initial, ownerHwnd) {
    cc := Buffer(72, 0)
    custColors := Buffer(16 * 4, 0)
    NumPut("UInt", 72, cc, 0)          ; lStructSize
    NumPut("Ptr", ownerHwnd, cc, 8)    ; hwndOwner
    NumPut("UInt", ToBGR(initial), cc, 24)  ; rgbResult (초기값)
    NumPut("Ptr", custColors.Ptr, cc, 32)   ; lpCustColors
    NumPut("UInt", 0x1 | 0x2, cc, 40)  ; CC_RGBINIT | CC_FULLOPEN
    if !DllCall("comdlg32\ChooseColorW", "ptr", cc, "int")
        return -1
    bgr := NumGet(cc, 24, "UInt")
    r := bgr & 0xFF
    g := (bgr >> 8) & 0xFF
    b := (bgr >> 16) & 0xFF
    return (r << 16) | (g << 8) | b
}

PickColor(target := "Spot", ownerHwnd := 0, *) {
    global spotColor, clickColor, rclickColor, drawColor, widgetBgColor, showWidget, activeDrawColor, widget
    if !ownerHwnd
        ownerHwnd := widget.Hwnd
    picked := ChooseColorDialog(GetColorOf(target), ownerHwnd)
    if (picked >= 0) {
        if (target = "Spot") {
            spotColor := picked
            UpdateSpotlightColor()
        } else if (target = "Widget") {
            widgetBgColor := picked
            ; 버튼 그림이 배경색에 합성되어 있어서 위젯을 다시 만들어야 한다
            BuildWidget()
            SetWidgetVisible(showWidget)
        } else if (target = "Click") {
            clickColor := picked ; 클릭 링은 다음 클릭 때 그려지므로 값만 바꿔두면 된다
        } else if (target = "RClick") {
            rclickColor := picked
        } else {
            drawColor := picked
            ; 지금 쓰는 색까지 같이 맞춰둔다. 설정 창을 열면 드로잉 모드가 꺼지긴 하지만,
            ; 그래도 "고른 색이 곧바로 반영된다"는 쪽이 헷갈리지 않는다.
            activeDrawColor := picked
            RedrawBrushCursor()
        }
    }
}

; ================= 설정 창 =================
; 숫자 입력칸에서 Enter를 눌렀을 때만 값을 적용하기 위한 전역 키 감지.
; (매 글자마다 적용해버리면 입력 도중 값이 강제로 재조정되면서 타이핑을 방해한다)
sliderEditHandlers := Map()
OnMessage(0x100, OnSliderEditKeyDown) ; WM_KEYDOWN
OnMessage(0x115, OnPaletteScroll)     ; WM_VSCROLL — 색 목록의 스크롤 막대
OnMessage(0x20A, OnPaletteWheel)      ; WM_MOUSEWHEEL — 색 목록 위에서 휠을 굴릴 때
OnSliderEditKeyDown(wParam, lParam, msg, hwnd) {
    global sliderEditHandlers
    if wParam = 13 && sliderEditHandlers.Has(hwnd) { ; VK_RETURN
        sliderEditHandlers[hwnd]()
        return 0
    }
}

; 라벨 + "-"버튼 + 슬라이더 + "+"버튼 + 숫자 직접입력 칸을 한 줄로 만들어주는 공용 함수.
; onChange(새값)은 슬라이더/버튼/입력칸(Enter 또는 포커스 이동 시) 중 무엇으로 바꾸든 동일하게 호출된다.
; step은 슬라이더와 -/+ 버튼이 한 번에 움직이는 크기다. 위젯 크기(%)처럼 1씩 움직여봐야
; 차이가 안 보이는 값에 쓴다. **숫자칸에 직접 적을 때는 step을 무시한다** — 굳이 105%를
; 적어 넣겠다는 사람을 100이나 110으로 되돌릴 이유가 없다.
AddSliderRow(gui, y, labelText, rangeMin, rangeMax, initial, suffixText, onChange, step := 1) {
    global sliderEditHandlers
    gui.AddText("x30 y" (y + 4) " w70", labelText)
    btnMinus := gui.AddButton("x100 y" y " w24 h24", "-")
    sl := gui.AddSlider("x126 y" (y + 2) " w204 Range" rangeMin "-" rangeMax, initial)
    btnPlus := gui.AddButton("x332 y" y " w24 h24", "+")
    ed := gui.AddEdit("x360 y" y " w44 h24 Center Number", initial)
    if suffixText != ""
        gui.AddText("x410 y" (y + 4) " w40", suffixText)

    apply := (v) => (v := Max(rangeMin, Min(rangeMax, Round(v))), sl.Value := v, ed.Text := v, onChange(v))
    snap := (v) => (step > 1) ? Round(v / step) * step : v
    applyFromEdit := () => apply(ed.Text = "" ? rangeMin : Integer(ed.Text))
    sl.OnEvent("Change", (ctrl, *) => apply(snap(ctrl.Value)))
    btnMinus.OnEvent("Click", (*) => apply(sl.Value - step))
    btnPlus.OnEvent("Click", (*) => apply(sl.Value + step))
    ed.OnEvent("LoseFocus", (*) => applyFromEdit())
    sliderEditHandlers[ed.Hwnd] := applyFromEdit
    ; 묶어서 돌려준다 — 체크박스로 이 줄 전체를 켜고 끌 수 있게 하려면 컨트롤이 다 필요하다
    return [btnMinus, sl, btnPlus, ed]
}

; 컨트롤 묶음을 한꺼번에 켜고 끈다. 끄면 회색으로 흐려져서 "지금은 해당 없음"이 눈에 보인다.
SetRowEnabled(controls, on) {
    for c in controls
        try c.Enabled := on ? true : false
}

; 여러 줄에서 돌려받은 컨트롤들을 한 바구니에 모은다 (묶음째 켜고 끄려면 한 배열이어야 한다)
AddAll(basket, items) {
    for it in items
        basket.Push(it)
}

; ================= 드로잉 탭의 "색 목록" (스크롤되는 칸) =================
; 숫자키 1~9와 칠판 W/E/R까지 열두 줄이라, 탭에 그냥 늘어놓으면 설정 창이 두 배로 길어진다.
; 그래서 정해진 크기의 **창문(palettePanel)**을 하나 두고, 그 안에서 내용(paletteBody)을
; 위아래로 밀어 보여준다. 창문이 자식 창이라 삐져나온 부분은 Windows가 알아서 잘라준다.
;
; 스크롤 막대는 설정 창 자신의 컨트롤로 둔다 — 그래야 탭을 옮길 때 AutoHotkey가 다른 탭의
; 컨트롤처럼 알아서 감춰준다. 반면 창문은 별도의 창이라 탭이 바뀔 때 직접 감춰야 한다
; (OpenSettingsWindow의 tabs.OnEvent("Change") 참고).
PALETTE_X := 22
PALETTE_Y := 348
PALETTE_W := 418
PALETTE_H := 188
PALETTE_ROW_H := 34
palettePanel := ""     ; 창문 (이 크기만큼만 보인다)
paletteBody := ""      ; 내용 (위아래로 밀린다)
paletteBar := ""       ; 오른쪽 스크롤 막대
paletteScroll := 0     ; 지금 밀려 있는 양(px)
paletteMax := 0        ; 밀 수 있는 최대치(px)
paletteContentH := 0   ; 내용 전체 높이(px)
palettePageX := 0      ; 창문의 자리 ("탭 안쪽 창" 기준 — BuildPalettePanel에서 환산한다)
palettePageY := 0

PaletteColor(kind, index) {
    global DRAW_COLORS, BOARD_COLORS
    return (kind = "board") ? BOARD_COLORS[index] : DRAW_COLORS[index]
}

PaletteAlpha(kind, index) {
    global DRAW_ALPHAS, BOARD_ALPHAS
    return (kind = "board") ? BOARD_ALPHAS[index] : DRAW_ALPHAS[index]
}

SetPaletteColor(kind, index, color) {
    global DRAW_COLORS, BOARD_COLORS
    if (kind = "board")
        BOARD_COLORS[index] := color
    else
        DRAW_COLORS[index] := color
}

SetPaletteAlpha(kind, index, value) {
    global DRAW_ALPHAS, BOARD_ALPHAS
    if (kind = "board")
        BOARD_ALPHAS[index] := value
    else
        DRAW_ALPHAS[index] := value
}

; 색 한 줄: [키] [견본] [색 고르기] [투명도 슬라이더] [숫자] %
AddPaletteRow(gui, y, label, kind, index) {
    global sliderEditHandlers, DRAW_STEPS, STEP_MAX
    lbl := gui.AddText("x6 y" (y + 4) " w24 h22", label)
    lbl.SetFont("s11 Bold")
    ; 견본은 AddColorRow와 같은 방식 — 색이 확실히 반영되는 Progress 컨트롤을 꽉 채워 쓰고,
    ; 한 겹 큰 회색 막대를 뒤에 깔아 테두리로 삼는다 (흰색 견본도 보이게 하려고)
    gui.AddProgress("x32 y" (y - 2) " w48 h28 Range0-100 -Smooth c808080", 100)
    swatch := gui.AddProgress("x34 y" y " w44 h24 Range0-100 -Smooth c" HexColor(PaletteColor(kind, index)), 100)
    isDraw := (kind = "draw") ; 숫자키 줄에는 오른쪽에 두께 칸이 더 있어 앞의 칸들을 좁힌다
    btn := gui.AddButton("x86 y" (y - 2) (isDraw ? " w72" : " w80") " h28", "색 고르기")
    btn.OnEvent("Click", (*) => (
        picked := ChooseColorDialog(PaletteColor(kind, index), gui.Hwnd),
        (picked >= 0) ? (SetPaletteColor(kind, index, picked), swatch.Opt("c" HexColor(picked))) : ""
    ))
    sl := gui.AddSlider((isDraw ? "x162" : "x174") " y" (y + 2) (isDraw ? " w98" : " w142") " Range5-100", PaletteAlpha(kind, index))
    ed := gui.AddEdit((isDraw ? "x264" : "x322") " y" y " w44 h24 Center Number", PaletteAlpha(kind, index))
    gui.AddText((isDraw ? "x312" : "x370") " y" (y + 4) " w20", "%")
    apply := (v) => (v := Max(5, Min(100, Round(v))), sl.Value := v, ed.Text := v, SetPaletteAlpha(kind, index, v))
    sl.OnEvent("Change", (ctrl, *) => apply(Round(ctrl.Value / 5) * 5))
    ed.OnEvent("LoseFocus", (*) => apply(ed.Text = "" ? 5 : Integer(ed.Text)))
    sliderEditHandlers[ed.Hwnd] := () => apply(ed.Text = "" ? 5 : Integer(ed.Text))
    if isDraw {
        ; 두께 단계(1~STEP_MAX). 위아래 화살표로도 바꾼다.
        edStep := gui.AddEdit("x342 y" y " w52 h24 Center Number", DRAW_STEPS[index])
        gui.AddUpDown("Range1-" STEP_MAX, DRAW_STEPS[index])
        applyStep := (*) => (edStep.Text = "" ? "" : DRAW_STEPS[index] := Max(1, Min(STEP_MAX, Integer(edStep.Text)))) ; 비워 둔 채로는 이전 값 유지
        edStep.OnEvent("Change", applyStep)
        edStep.OnEvent("LoseFocus", (*) => (applyStep(), edStep.Text := DRAW_STEPS[index]))
    }
}

; 열두 줄을 만들고 창문에 끼운다. 설정 창을 만들 때 한 번만 부른다.
; **창문은 설정 창이 아니라 "탭 안쪽 창"의 자식으로 만들어야 한다.** AutoHotkey는 탭에 놓인
; 컨트롤들을 설정 창에 직접 붙이지 않고 별도의 대화상자 창(클래스 #32770) 하나를 만들어 그
; 안에 담는다. 설정 창에 바로 붙이면 그 대화상자가 위를 덧칠해서, 창이 분명히 있고 보이기
; 상태인데도 화면에는 아무것도 안 나온다(실제로 그랬다 — 자식 창들을 z순서대로 찍어보고서야
; 알았다). 그 창의 핸들은 같은 탭에 만들어둔 스크롤 막대의 부모를 물어보면 얻을 수 있다.
BuildPalettePanel(parentGui) {
    global palettePanel, paletteBody, paletteContentH, paletteMax, paletteScroll
    global PALETTE_X, PALETTE_Y, PALETTE_W, PALETTE_H, PALETTE_ROW_H
    global DRAW_COLORS, BOARD_KEYS, BOARD_COLOR_DEFAULTS, paletteBar, palettePageX, palettePageY
    pageHwnd := DllCall("GetParent", "ptr", paletteBar.Hwnd, "ptr")
    ; 설정 창 기준으로 잡아둔 자리(PALETTE_X/Y)를 그 창 기준으로 옮긴다
    pt := Buffer(8, 0)
    NumPut("Int", PALETTE_X, pt, 0)
    NumPut("Int", PALETTE_Y, pt, 4)
    DllCall("ClientToScreen", "ptr", parentGui.Hwnd, "ptr", pt)
    DllCall("ScreenToClient", "ptr", pageHwnd, "ptr", pt)
    palettePageX := NumGet(pt, 0, "Int")
    palettePageY := NumGet(pt, 4, "Int")
    ; 0x4000000 = WS_CLIPSIBLINGS — 옆에 있는 컨트롤들과 서로의 자리를 침범하지 않게 한다
    palettePanel := Gui("+Parent" pageHwnd " -Caption +0x4000000")
    palettePanel.BackColor := "F2F2F2"
    paletteBody := Gui("+Parent" palettePanel.Hwnd " -Caption")
    paletteBody.BackColor := "F2F2F2"
    paletteBody.SetFont("s10", "Malgun Gothic")

    y := 6
    head := paletteBody.AddText("x6 y" y " w400", "단축키(드로잉)               투명도                          두께(1~10)")
    head.SetFont("s9 c666666")
    y += 24
    loop DRAW_COLORS.Length {
        AddPaletteRow(paletteBody, y, String(A_Index), "draw", A_Index)
        y += PALETTE_ROW_H
    }
    y += 10
    head2 := paletteBody.AddText("x6 y" y " w400", "단축키(칠판)")
    head2.SetFont("s9 c666666")
    y += 24
    for index, pair in BOARD_KEYS {
        if (BOARD_COLOR_DEFAULTS[index] < 0) ; Q(투명)는 바꿀 것이 없다
            continue
        AddPaletteRow(paletteBody, y, StrUpper(pair[1]), "board", index)
        y += PALETTE_ROW_H
    }
    paletteContentH := y + 6
    paletteScroll := 0
    paletteMax := Max(0, paletteContentH - PALETTE_H)
    paletteBody.Show("NA x0 y0 w" PALETTE_W " h" paletteContentH)
    palettePanel.Show("NA x" palettePageX " y" palettePageY " w" PALETTE_W " h" PALETTE_H)
    palettePanel.Hide() ; 설정 창은 "일반" 탭에서 열리므로 일단 감춰둔다
}

; 탭을 옮길 때 창문을 같이 보이고 감춘다 (별도의 창이라 탭 컨트롤이 대신 해주지 않는다)
ShowPalettePanel(on) {
    global palettePanel, palettePageX, palettePageY, PALETTE_W, PALETTE_H
    if !palettePanel
        return
    if on {
        palettePanel.Show("NA x" palettePageX " y" palettePageY " w" PALETTE_W " h" PALETTE_H)
        ; 옆에 있는 컨트롤들보다 위로 올린다 (0 = HWND_TOP / 0x1 = 크기 유지, 0x2 = 위치 유지, 0x10 = 활성화 안 함)
        DllCall("SetWindowPos", "ptr", palettePanel.Hwnd, "ptr", 0
            , "int", 0, "int", 0, "int", 0, "int", 0, "uint", 0x1 | 0x2 | 0x10)
    } else
        palettePanel.Hide()
}

; 스크롤 막대에 "전체 길이 / 한 화면 크기 / 지금 위치"를 알려준다. 이 셋을 줘야 막대 손잡이가
; 내용 길이에 맞는 크기로 나오고, 다 보이는 경우엔 막대가 알아서 비활성으로 흐려진다.
UpdatePaletteScrollBar() {
    global paletteBar, paletteScroll, paletteContentH, PALETTE_H
    if !paletteBar
        return
    si := Buffer(28, 0)
    NumPut("UInt", 28, si, 0)              ; cbSize
    NumPut("UInt", 0x1 | 0x2 | 0x4, si, 4) ; SIF_RANGE | SIF_PAGE | SIF_POS
    NumPut("Int", 0, si, 8)                ; nMin
    NumPut("Int", paletteContentH - 1, si, 12) ; nMax
    NumPut("UInt", PALETTE_H, si, 16)      ; nPage (한 번에 보이는 높이)
    NumPut("Int", paletteScroll, si, 20)   ; nPos
    DllCall("SetScrollInfo", "ptr", paletteBar.Hwnd, "int", 2, "ptr", si, "int", true) ; SB_CTL
}

ScrollPaletteTo(pos) {
    global paletteScroll, paletteMax, paletteBody
    pos := Max(0, Min(paletteMax, Round(pos)))
    if (pos = paletteScroll || !paletteBody)
        return
    paletteScroll := pos
    paletteBody.Move(0, -pos) ; 내용을 위로 밀면 아래쪽 줄이 창문에 들어온다
    UpdatePaletteScrollBar()
}

OnPaletteScroll(wParam, lParam, msg, hwnd) {
    global paletteBar, paletteScroll, paletteMax, PALETTE_ROW_H, PALETTE_H
    if (!paletteBar || lParam != paletteBar.Hwnd)
        return
    pos := paletteScroll
    switch (wParam & 0xFFFF) {
        case 0: pos -= PALETTE_ROW_H          ; SB_LINEUP
        case 1: pos += PALETTE_ROW_H          ; SB_LINEDOWN
        case 2: pos -= PALETTE_H              ; SB_PAGEUP
        case 3: pos += PALETTE_H              ; SB_PAGEDOWN
        case 4, 5:                            ; SB_THUMBPOSITION / SB_THUMBTRACK
            ; 손잡이를 끄는 중에는 진행 위치를 따로 물어봐야 한다 (wParam에 실려오는 값은
            ; 16비트라 내용이 길어지면 잘린다)
            si := Buffer(28, 0)
            NumPut("UInt", 28, si, 0)
            NumPut("UInt", 0x10, si, 4)       ; SIF_TRACKPOS
            DllCall("GetScrollInfo", "ptr", paletteBar.Hwnd, "int", 2, "ptr", si)
            pos := NumGet(si, 24, "Int")
        case 6: pos := 0                      ; SB_TOP
        case 7: pos := paletteMax             ; SB_BOTTOM
        default: return 0
    }
    ScrollPaletteTo(pos)
    return 0
}

; 마우스 휠로도 굴러가게 한다. 휠 메시지는 "지금 입력 포커스를 가진 컨트롤"에게 가므로,
; 슬라이더를 한 번 만진 뒤 휠을 굴리면 그 슬라이더 값이 바뀌어버린다. 커서가 이 칸 위에
; 있으면 우리가 먼저 받아 스크롤로 쓰고 0을 돌려줘서, 아래로 내려가지 않게 막는다.
OnPaletteWheel(wParam, lParam, msg, hwnd) {
    global palettePanel, paletteScroll
    if (!palettePanel || !DllCall("IsWindowVisible", "ptr", palettePanel.Hwnd))
        return
    pt := Buffer(8, 0)
    DllCall("GetCursorPos", "ptr", pt)
    mx := NumGet(pt, 0, "Int"), my := NumGet(pt, 4, "Int")
    rc := Buffer(16, 0)
    DllCall("GetWindowRect", "ptr", palettePanel.Hwnd, "ptr", rc)
    if (mx < NumGet(rc, 0, "Int") || mx > NumGet(rc, 8, "Int")
        || my < NumGet(rc, 4, "Int") || my > NumGet(rc, 12, "Int"))
        return
    delta := (wParam >> 16) & 0xFFFF
    if (delta > 0x7FFF)
        delta -= 0x10000 ; 위로 굴리면 음수로 와야 한다 (16비트 부호값)
    ScrollPaletteTo(paletteScroll - Round(delta / 120) * 46)
    return 0
}

; 설정 창이 지금 살아 있는지. **"모든 설정값 초기화"는 창을 통째로 없애고 다시 만들기 때문에**,
; 변수에는 이미 없어진 창이 담겨 있을 수 있다 — 그 상태에서 `.Hwnd`를 읽으면 "Gui has no window"
; 오류가 난다(실제로 그렇게 멈췄다). 그래서 확인을 이 한 곳에 모아두고 오류까지 받아낸다.
SettingsWindowExists() {
    global settingsGui
    if !IsSet(settingsGui) || !settingsGui
        return false
    try return WinExist("ahk_id " settingsGui.Hwnd) ? true : false
    return false
}

; ================= 모든 설정값 초기화 =================
; settings.ini를 지우고 처음 값으로 다시 읽어들인 뒤, 지금 화면에 보이는 것들을 전부 새 값으로
; 맞춘다. **되돌릴 수 없는 일이라 먼저 물어본다.**
;
; 값을 하나하나 기본값으로 되돌리는 대신 **파일을 지우고 다시 읽는 방식**을 쓴다. 그래야
; 나중에 설정 항목을 늘려도 여기를 같이 고치는 것을 잊어 한두 개가 안 돌아가는 일이 없다.
;
; "Windows 시작 시 자동 실행"은 건드리지 않는다 — 그건 settings.ini가 아니라 레지스트리에 있는
; Windows 쪽 설정이고, 설정을 되돌리려다 시작프로그램에서 빠지면 놀랄 일이다. 체크 한 번으로
; 끌 수 있으므로 안내문에 그렇게 적어둔다.
ResetAllSettings() {
    global SETTINGS_PATH, settingsGui, palettePanel, paletteBody, chkWidgetCtrl
    global showWidget, showTrayIcons, hotkeyCombos, sliderEditHandlers, drawColor, activeDrawColor, activeDrawAlpha

    answer := MsgBox("모든 설정값을 처음 상태로 되돌립니다.`n`n"
        . "색과 굵기, 숫자키·칠판 색, 위젯 자리와 크기, 단축키까지 전부 처음 값으로 돌아가며 "
        . "되돌릴 수 없습니다.`n`n"
        . "(Windows 시작 시 자동 실행은 그대로 둡니다)"
        , "Focus & Draw - 모든 설정값 초기화", "YesNo Icon? Default2")
    if (answer != "Yes")
        return

    ; 파일이 없으면 FileDelete가 오류를 내지만, 그건 이미 원하는 상태다
    try FileDelete(SETTINGS_PATH)
    if FileExist(SETTINGS_PATH) {
        MsgBox("설정 파일을 지우지 못했습니다.`n`n" SETTINGS_PATH "`n`n"
            . "쓰기가 막힌 폴더에 두었을 때 생깁니다. 압축을 풀어 바탕화면이나 문서 폴더로 "
            . "옮긴 뒤 다시 시도해 주세요."
            , "Focus & Draw - 모든 설정값 초기화", "Icon!")
        return
    }

    LoadSettings()
    LoadPalette()

    ; 지금 화면에 떠 있는 것들을 새 값으로 다시 맞춘다
    for name, combo in hotkeyCombos
        RegisterHotkey(name, combo) ; 옛 조합은 RegisterHotkey가 알아서 해제한다
    ApplySpotlightAppearance()
    UpdateSpotlightColor()
    RedrawSpotlight()
    UpdateCursorHiddenState()
    activeDrawColor := drawColor
    activeDrawAlpha := StartAlpha(100)
    BuildWidget() ; 크기·배경색이 그림에 합성되어 있어 다시 만들어야 한다
    SetWidgetVisible(showWidget)
    MoveWidgetToDefaultPos()
    SetTrayIconsVisible(showTrayIcons)

    ; 설정 창은 값을 열 때 한 번만 읽어 컨트롤에 넣으므로, 통째로 다시 만들어야 새 값이 보인다.
    ; 색 목록은 설정 창에 딸린 별도의 창이라 먼저 없앤다(안쪽부터).
    if paletteBody
        try paletteBody.Destroy()
    if palettePanel
        try palettePanel.Destroy()
    palettePanel := "", paletteBody := ""
    chkWidgetCtrl := ""
    sliderEditHandlers := Map() ; 없어진 컨트롤의 핸들이 남지 않게 비운다
    try settingsGui.Destroy()
    settingsGui := "" ; 없어진 창을 가리킨 채로 두면 다음에 .Hwnd를 읽다가 멈춘다
    OpenSettingsWindow()
}

; 라벨 + 색상 견본 + "색상 선택..." 버튼을 한 줄로 만든다. 포인터·클릭효과·드로잉 세 탭이
; 같은 모양으로 쓰므로, 탭마다 따로 적지 않고 여기 한 번만 적어둔다.
AddColorRow(gui, y, target, labelText := "색상") {
    gui.AddText("x30 y" (y + 4) " w70", labelText)
    ; Text 컨트롤의 배경색 지정은 이 창(테마 적용된 일반 창)에서 반영되지 않는 문제가 있어서,
    ; 항상 확실하게 색이 반영되는 진행 막대(Progress) 컨트롤을 꽉 채운 색상 견본으로 쓴다.
    ; Progress 컨트롤은 안쪽 채움 영역이 테두리보다 살짝 안으로 들어가 있어서, 모서리를
    ; 둥글게 잘라내면 그 여백 부분이 직선 자국으로 비쳐 보인다 — 그냥 사각형으로 둔다.
    ; 견본 색이 설정 창 배경과 비슷하면(위젯 기본색 F2F2F2가 딱 그렇다) 견본이 아예 안 보여서
    ; 고장난 것처럼 보인다. 한 겹 큰 회색 막대를 뒤에 깔아 테두리처럼 쓴다.
    ; **여백을 1px만 주면 안 된다** — Progress는 자기 테두리 안쪽으로 색을 채우기 때문에,
    ; 바깥 1px은 그 컨트롤 자신의 테두리에 먹힌다. 그래서 보이는 회색 두께는 "여백 - 1px"이다.
    ; 여기서는 2px을 줘서 1px 테두리로 보이게 한다(화면을 찍어 픽셀을 세어 맞췄다).
    gui.AddProgress("x98 y" (y - 2) " w44 h28 Range0-100 -Smooth c808080", 100)
    swatch := gui.AddProgress("x100 y" y " w40 h24 Range0-100 -Smooth c" HexColor(GetColorOf(target)), 100)
    btnPick := gui.AddButton("x150 y" (y - 2) " w110 h28", "색상 선택...")
    btnPick.OnEvent("Click", (*) => (PickColor(target, gui.Hwnd), swatch.Opt("c" HexColor(GetColorOf(target)))))
    return [btnPick]
}

; 라벨 + 단축키 입력칸 + "기본값" 버튼을 한 줄로 만든다. 입력칸은 사용자가 누른 키 조합을
; 그대로 받아주는 전용 컨트롤이라, 직접 문자열을 타이핑하게 하는 것보다 훨씬 덜 헷갈린다.
; (이 컨트롤은 윈도우 키 조합을 담지 못한다 — 어차피 Windows 자체 단축키와 겹쳐서 권하지 않는다)
AddHotkeyRow(gui, y, name) {
    global hotkeyCombos, HOTKEY_DEFAULTS, HOTKEY_LABELS
    gui.AddText("x30 y" (y + 4) " w70", HOTKEY_LABELS[name])
    hk := gui.AddHotkey("x100 y" y " w130 h24")
    hk.Value := hotkeyCombos[name]
    btnDefault := gui.AddButton("x238 y" y " w72 h24", "기본값")
    ; 이 컨트롤은 LoseFocus 이벤트가 없어서 Change로만 받는다. 조합키만 누르고 있는 중간
    ; 상태에서는 빈 값이 오는데, 그건 ChangeHotkey가 걸러낸다.
    hk.OnEvent("Change", (ctrl, *) => ChangeHotkey(name, ctrl.Value, ctrl))
    btnDefault.OnEvent("Click", (*) => ChangeHotkey(name, HOTKEY_DEFAULTS[name], hk))
    return hk
}

OpenSettingsWindow(*) {
    global laserHold, laserFade, laserGlow
    global SpotSize, spotOpacity, SpotThickness, DrawOpacity, DrawStep, EraserStep, clickEffectEnabled, clickSpeed, clickOpacity, CLICK_ANIM_INTERVAL, rclickEffectEnabled, rclickThickness, rclickSpeed, rclickOpacity, RCLICK_ANIM_INTERVAL, rclickColor, showWidget, showTrayIcons, widget, settingsGui, hideCursorOnHighlight, spotlightOn, APP_VERSION, drawOn, chkWidgetCtrl, widgetScale, widgetOpacity
    global paletteBar, PALETTE_X, PALETTE_Y, PALETTE_W, PALETTE_H

    ; 판서 모드는 화면 전체를 오버레이로 덮어서 "그리기 말고는 아무것도 클릭되지 않는" 상태로
    ; 만드는 게 목적이라, 설정 창도 그 아래에 깔려 조작할 수 없다. 설정 창을 띄우려고 했다는
    ; 것은 판서를 잠시 멈추겠다는 뜻이므로 판서 모드를 먼저 끈다. 그려둔 내용은 지우지 않아서
    ; 판서를 다시 켜면 그대로 남아 있다.
    ; (설정 창을 항상 위로 올리는 방법도 써봤지만, 그러면 강조 하이라이트가 설정 창 밑으로
    ;  숨어버려서 크기·투명도를 보면서 맞출 수 없었다 — 그래서 이 방식으로 되돌렸다)
    if drawOn
        ToggleDraw()

    if SettingsWindowExists() {
        settingsGui.Show()
        return
    }

    ; ToolWindow를 안 써야 작업표시줄/Alt+Tab에 정상적으로 뜬다. AlwaysOnTop은 일부러 쓰지
    ; 않는다 — 항상 위로 올리면 강조 하이라이트(이 창도 AlwaysOnTop이다)가 설정 창 뒤로
    ; 가려져서, 크기와 투명도를 눈으로 보면서 맞출 수 없다.
    settingsGui := Gui(, "Focus & Draw 설정")
    ; 숫자칸(Edit)은 흰 배경이라, 창 배경을 살짝 다른 톤으로 두어야 둥근 모서리 바깥으로
    ; 비치는 색이 또렷하게 구분되어 보인다.
    settingsGui.BackColor := "F2F2F2"
    settingsGui.SetFont("s10", "Malgun Gothic")

    ; 탭은 번호가 아니라 이름으로 고른다 — 나중에 순서를 바꿔도 아래 코드를 손볼 필요가 없다.
    ; (여섯 개까지는 이 너비에서 한 줄에 들어가는 것을 확인했다. 더 늘리면 두 줄로 접히면서
    ;  안쪽 내용이 아래로 밀리므로, 탭을 추가할 때는 창 너비도 같이 넓혀야 한다)
    ; 높이는 가장 내용이 많은 "드로잉" 탭에 맞춰져 있다. 색 목록(스크롤되는 칸)이 아래쪽
    ; y536까지 내려오므로, 그보다 줄이면 잘린다 — 여기와 아래 버튼 위치, 창 높이를 같이 봐야 한다.
    ; "포인터"와 "클릭효과"를 **"포커스" 한 탭으로 합쳤다.** 셋 다 마우스 자리를 짚어주는
    ; 같은 목적의 기능이라 나눠 둘 이유가 없었고, 나뉘어 있으면 클릭효과의 색이 하이라이트와
    ; 다른 색이라는 것도 눈에 안 들어온다. 대신 탭 안에서 테두리 상자로 셋을 갈라둔다.
    tabs := settingsGui.AddTab3("x10 y10 w460 h552", ["일반", "포커스", "드로잉", "위젯", "단축키"])

    tabs.UseTab("포커스")
    ; --- 하이라이트 ---
    settingsGui.AddGroupBox("x22 y42 w436 h158", "포커스 하이라이트")
    ; 체크박스 라벨 텍스트까지 클릭 영역에 포함되면 실수로 누르기 쉬워서, 네모 칸만 클릭
    ; 가능하게 하고 글자는 옆에 별도의(클릭 안 되는) 텍스트로 둔다.
    chkHideCursor := settingsGui.AddCheckbox("x36 y70 w20 h20 " (hideCursorOnHighlight ? "Checked" : ""), "")
    settingsGui.AddText("x60 y71 w300", "활성화 시 마우스 커서 숨기기")
    chkHideCursor.OnEvent("Click", (ctrl, *) => (hideCursorOnHighlight := ctrl.Value, UpdateCursorHiddenState()))
    AddColorRow(settingsGui, 102, "Spot")
    AddSliderRow(settingsGui, 134, "크기", 30, 200, SpotSize, "", (v) => (SpotSize := v, ApplySpotlightAppearance()), 5)
    AddSliderRow(settingsGui, 166, "투명도", 0, 100, spotOpacity, "%", (v) => (spotOpacity := v, RedrawSpotlight()), 5)

    ; --- 왼쪽 클릭 효과 --- (켜고 끄는 체크박스를 상자 제목 자리에 얹는다)
    settingsGui.AddGroupBox("x22 y212 w436 h164", "")
    chkClick := settingsGui.AddCheckbox("x36 y204 w20 h20 " (clickEffectEnabled ? "Checked" : ""), "")
    settingsGui.AddText("x60 y205 w300", "포커스 클릭효과 (좌클릭)")
    lClickRows := []
    AddAll(lClickRows, AddColorRow(settingsGui, 240, "Click"))
    AddAll(lClickRows, AddSliderRow(settingsGui, 272, "테두리 굵기", 2, 12, SpotThickness, "", (v) => SpotThickness := v))
    ; 클릭 링은 클릭할 때만 잠깐 나타나므로, 투명도는 값만 바꿔두면 다음 클릭부터 적용된다
    AddAll(lClickRows, AddSliderRow(settingsGui, 304, "투명도", 0, 100, clickOpacity, "%", (v) => clickOpacity := v, 5))
    ; clickSpeed는 클수록 빠름(1~30) — 실제 타이머 간격(ms)은 반대로 계산한다
    AddAll(lClickRows, AddSliderRow(settingsGui, 336, "빠르기", 1, 30, clickSpeed, ""
        , (v) => (clickSpeed := v, CLICK_ANIM_INTERVAL := 41 - v)))
    chkClick.OnEvent("Click", (ctrl, *) => (clickEffectEnabled := ctrl.Value, SetRowEnabled(lClickRows, ctrl.Value)))
    SetRowEnabled(lClickRows, clickEffectEnabled) ; 꺼져 있으면 처음부터 흐리게

    ; --- 오른쪽 클릭 효과 ---
    settingsGui.AddGroupBox("x22 y388 w436 h164", "")
    chkRClick := settingsGui.AddCheckbox("x36 y380 w20 h20 " (rclickEffectEnabled ? "Checked" : ""), "")
    settingsGui.AddText("x60 y381 w300", "포커스 클릭효과 (우클릭)")
    rClickRows := []
    AddAll(rClickRows, AddColorRow(settingsGui, 416, "RClick"))
    AddAll(rClickRows, AddSliderRow(settingsGui, 448, "테두리 굵기", 2, 12, rclickThickness, "", (v) => rclickThickness := v))
    AddAll(rClickRows, AddSliderRow(settingsGui, 480, "투명도", 0, 100, rclickOpacity, "%", (v) => rclickOpacity := v, 5))
    AddAll(rClickRows, AddSliderRow(settingsGui, 512, "빠르기", 1, 30, rclickSpeed, ""
        , (v) => (rclickSpeed := v, RCLICK_ANIM_INTERVAL := 41 - v)))
    chkRClick.OnEvent("Click", (ctrl, *) => (rclickEffectEnabled := ctrl.Value, SetRowEnabled(rClickRows, ctrl.Value)))
    SetRowEnabled(rClickRows, rclickEffectEnabled)

    tabs.UseTab("드로잉")
    ; 설정 창이 열려 있다는 것은 드로잉 모드가 꺼져 있다는 뜻이라(OpenSettingsWindow에서 끈다)
    ; 여기서 바꾼 값은 다음에 드로잉을 켤 때부터 쓰인다. 드로잉 중에 쓰는 값(activeDrawThickness)은
    ; 켤 때마다 이 값으로 초기화된다.
    AddColorRow(settingsGui, 52, "Draw", "기본 색상")
    AddSliderRow(settingsGui, 86, "드로잉 굵기", 1, 10, DrawStep, "단계", (v) => DrawStep := v)
    AddSliderRow(settingsGui, 118, "투명도", 0, 100, DrawOpacity, "%", (v) => DrawOpacity := v, 5)
    AddSliderRow(settingsGui, 150, "지우개 크기", 1, 10, EraserStep, "단계", (v) => EraserStep := v)

    ; --- 레이저 펜 (레이저, A) --- 맥 판과 같은 설정 항목이다([Draw] LaserHold·LaserFade·LaserGlow).
    ; 줄 이름이 왼쪽 칸(70px)에 들어가도록 "레이저"는 상자 제목으로 올린다.
    settingsGui.AddGroupBox("x22 y184 w436 h124", "레이저 펜 (A)")
    AddSliderRow(settingsGui, 206, "유지됨", 0, 3000, laserHold, "ms", (v) => laserHold := v, 100)
    AddSliderRow(settingsGui, 240, "사라짐", 100, 3000, laserFade, "ms", (v) => laserFade := v, 100)
    AddSliderRow(settingsGui, 274, "빛 번짐", 0, 200, laserGlow, "%", (v) => laserGlow := v, 10)

    ; --- 숫자키 1~9와 칠판 W/E/R의 색 (스크롤되는 칸) ---
    ; 위의 기본값들과 아래 키별 목록을 가르는 선 (0x10 = SS_ETCHEDHORZ, 가로로 파인 선)
    settingsGui.AddText("x30 y318 w420 h2 0x10")
    settingsGui.AddText("x30 y326 w200", "단축키별 설정")
    paletteBar := settingsGui.AddCustom("ClassScrollBar +0x1 x" (PALETTE_X + PALETTE_W + 2) " y" PALETTE_Y " w16 h" PALETTE_H)

    tabs.UseTab("위젯")
    chkWidget := settingsGui.AddCheckbox("x30 y52 w20 h20 " (showWidget ? "Checked" : ""), "")
    settingsGui.AddText("x54 y53 w300", "위젯 활성화")
    chkWidget.OnEvent("Click", (ctrl, *) => SetWidgetVisible(ctrl.Value))
    ; 위젯의 ✕나 트레이 메뉴로 상태가 바뀌어도 이 체크박스가 따라오도록 참조를 남겨둔다
    chkWidgetCtrl := chkWidget

    chkTray := settingsGui.AddCheckbox("x30 y92 w20 h20 " (showTrayIcons ? "Checked" : ""), "")
    settingsGui.AddText("x54 y93 w300", "작업표시줄 아이콘 활성화")
    chkTray.OnEvent("Click", (ctrl, *) => SetTrayIconsVisible(ctrl.Value))

    AddColorRow(settingsGui, 132, "Widget")
    ; 크기를 바꾸면 위젯을 통째로 다시 만든다(버튼 그림이 크기에 맞춰 다시 그려져야 한다).
    ; 슬라이더를 끄는 동안 매번 다시 만들면 깜빡이므로, 손을 뗀 뒤 잠깐 있다가 한 번만 만든다.
    ; 1%씩 움직여봐야 차이가 안 보여서 슬라이더와 -/+는 10%씩 간다. 숫자칸에 직접 적으면 1% 단위.
    AddSliderRow(settingsGui, 172, "크기", 60, 250, widgetScale, "%"
        , (v) => (widgetScale := v, SetTimer(RebuildWidgetSoon, -200)), 10)
    ; 투명도는 창 속성만 바꾸면 되므로 슬라이더를 끄는 대로 바로 반영된다(다시 만들 필요 없음)
    AddSliderRow(settingsGui, 212, "투명도", 20, 100, widgetOpacity, "%"
        , (v) => (widgetOpacity := v, ApplyWidgetOpacity()), 5)

    settingsGui.AddText("x30 y256 w70", "위치")
    btnResetPos := settingsGui.AddButton("x100 y252 w160 h28", "처음 자리로 되돌리기")
    btnResetPos.OnEvent("Click", (*) => MoveWidgetToDefaultPos())
    lblResetPos := settingsGui.AddText("x100 y286 w340", "어디 뒀는지 모를 때 화면 오른쪽 아래로 가져옵니다.")
    lblResetPos.SetFont("s9 c999999")

    tabs.UseTab("일반")
    ; 항목이 적은 탭이라 왼쪽 위에 붙여두면 허전하고 잘못 만든 것처럼 보인다.
    ; 탭 한가운데에 모아 둔다.
    ; "자동 실행"은 저장/불러오기 없이 그 자리에서 바로 레지스트리에 반영되므로, 체크 표시는
    ; 항상 IsRunAtStartup()으로 실제 상태를 다시 읽어서 보여준다.
    chkStartup := settingsGui.AddCheckbox("x133 y240 w20 h20 " (IsRunAtStartup() ? "Checked" : ""), "")
    settingsGui.AddText("x157 y241 w220", "Windows 시작 시 자동 실행")
    chkStartup.OnEvent("Click", (ctrl, *) => SetRunAtStartup(ctrl.Value))

    ; 자주 누를 버튼이 아니고 되돌릴 수도 없어서, 다른 항목과 떨어뜨려 놓고 글자색만 연하게 한다
    ; (배경색은 테마 버튼이라 바꿀 수 없다 — "프로그램 종료" 버튼과 같은 처지다).
    btnResetAll := settingsGui.AddButton("x140 y312 w200 h32", "모든 설정값 초기화")
    btnResetAll.SetFont("c999999")
    btnResetAll.OnEvent("Click", (*) => ResetAllSettings())
    lblResetAll := settingsGui.AddText("x22 y352 w436 Center", "색·굵기·위젯·단축키를 모두 처음 상태로 되돌립니다.")
    lblResetAll.SetFont("s9 c999999")

    ; 문제를 알려줄 때 어느 버전인지 바로 말할 수 있도록, 눈에 띄지 않는 연한 글씨로 적어둔다.
    ; 제작자 표시도 같이 둔다 — 수업 화면을 가리지 않으면서 찾으려는 사람은 확실히 볼 수 있는
    ; 자리가 여기라서, 위젯이나 트레이 툴팁 대신 이곳을 골랐다. 탭 아래 가운데에 둔다.
    ; +0x80 = SS_NOPREFIX. 이게 없으면 Text 컨트롤이 &를 단축키 표시용 기호로 삼아 먹어버려서
    ; "Focus & Draw"가 "Focus  Draw"로 나온다 (뒤 글자에 밑줄만 그어진다).
    lblVersion := settingsGui.AddText("x22 y500 w436 Center +0x80", "Focus & Draw 버전 " APP_VERSION)
    lblVersion.SetFont("s9 c999999")
    lblAuthor := settingsGui.AddText("x22 y520 w436 Center", "제작자: maker_SSAM")
    lblAuthor.SetFont("s9 c999999")

    tabs.UseTab("단축키")
    AddHotkeyRow(settingsGui, 50, "Spotlight")
    AddHotkeyRow(settingsGui, 90, "Draw")
    lblHotkeyHelp := settingsGui.AddText("x30 y126 w420 h32", "단축키를 직접 눌러 지정할 수 있습니다.  Ctrl이나 Alt키가 포함되어야 합니다.")
    lblHotkeyHelp.SetFont("s9 c999999")

    ; 드로잉 중에만 쓰는 키(도형·색·굵기·지우기)는 여기 글로 늘어놓지 않는다. **키보드 그림
    ; 한 장이 그 일을 더 잘한다** — 어느 키를 눌러야 하는지 자리로 바로 보이고, 지금 설정된
    ; 색까지 그림 아래에 함께 뜬다. 예전에는 열네 줄짜리 목록이 이 자리에 있었는데, 같은 내용을
    ; 두 군데 적어두면 한쪽만 고쳐져 어긋나기 마련이라 그림 쪽으로 몰았다.
    btnShortcutGuide := settingsGui.AddButton("x130 y178 w220 h36", "드로잉 모드 단축키 보기")
    btnShortcutGuide.OnEvent("Click", ShowShortcutGuide)

    tabs.UseTab()

    ; 배경색은 테마가 적용된 버튼이라 바꿀 수 없어서, 대신 글자색을 연하게 해 일반
    ; 버튼과 다르다는 느낌만 은은하게 준다.
    btnExit := settingsGui.AddButton("x25 y576 w130 h30", "프로그램 종료")
    btnExit.SetFont("c999999")
    btnExit.OnEvent("Click", (*) => ExitApp())
    btnSave := settingsGui.AddButton("x265 y576 w90 h30", "저장")
    ; 저장에 실패하면 안내 창이 뜨므로, 버튼 글자를 "저장됨"으로 바꾸지 않는다 —
    ; 실패했는데 됐다고 보이면 그게 제일 나쁘다.
    btnSave.OnEvent("Click", (*) => SaveSettings() && (btnSave.Text := "저장됨", SetTimer(() => btnSave.Text := "저장", -1000)))
    btnCloseSettings := settingsGui.AddButton("x365 y576 w90 h30", "닫기")
    btnCloseSettings.OnEvent("Click", (*) => settingsGui.Hide())
    settingsGui.OnEvent("Close", (*) => settingsGui.Hide())

    ; 색 목록은 탭 컨트롤 위에 얹는 별도의 창이라, 탭을 옮길 때 직접 감추고 보여야 한다.
    BuildPalettePanel(settingsGui)
    UpdatePaletteScrollBar()
    tabs.OnEvent("Change", (ctrl, *) => ShowPalettePanel(ctrl.Text = "드로잉"))

    settingsGui.Show("w480 h628")
}

; ================= 단축키 안내 그림 =================
; 설정 창 "단축키" 탭의 "드로잉 모드 단축키 보기" 버튼이 띄우는 창. 키보드 그림 한 장(shortcuts.png)을
; 그대로 보여주기만 한다.
;
; 그림은 **줄이기만 하고 키우지는 않는다.** 화면보다 큰 그림은 화면에 맞게 줄여야 하지만,
; 작은 그림을 억지로 키우면 흐려지기만 하고 얻는 게 없다.
;
; 줄일 때는 GDI+로 **미리 줄인 그림을 만들어** 넣는다. Picture 컨트롤에 큰 그림을 그대로
; 넣고 w/h만 작게 주면 Windows가 픽셀을 솎아내는 식으로 거칠게 줄여서 글자가 뭉개진다.
;
; 창은 `-DPIScale`로 만든다. 그래야 여기서 계산한 픽셀 수가 화면의 실제 픽셀과 1:1로
; 맞아서, 배율 125%/150%로 쓰는 화면에서도 그림이 부풀려지지 않고 또렷하게 나온다.
shortcutGui := ""
hShortcutBmp := 0
; 그림은 파일이라 설정 창에서 바꾼 색을 알 수 없다. 그래서 **창을 열 때마다 키 위 색 막대만 지금 설정
; 색으로 다시 칠한다** (맥 판의 키 위 막대와 같다). 그림을 새로 만들지 않아도 키 위 색은 늘 실제와 맞는다.
;
; 막대는 키 위쪽 둥근 모서리에 맞게 잘려 있어 사각형으로 덮으면 모서리가 번진다. 그래서 1번 키의
; 막대(빨강)를 본보기로 삼아 픽셀마다 "막대가 차지한 비율 a"를 구하고(막대 색 D와 테두리·바탕색 B의
; 섞임으로 본다), 다른 키는 p + a·(새 색 − D)로 고쳐 가장자리의 테두리와 겹친 부분도 자연스럽게 한다.
; 막대 맨 아랫줄은 12% 어두운 선이라 새 색도 같은 비율로 어둡게 한다.
; 좌표는 shortcuts.png(1200×860)에 맞춘 값이다. 그림을 바꾸면 크기가 달라져 이 칠하기는 건너뛴다
; (안내 그림은 그대로 보이고, 색 막대만 그림에 있는 기본 색으로 남는다).
GUIDE_IMG_W := 1200
GUIDE_IMG_H := 860
GUIDE_BAR_W := 62 ; 키 바깥 테두리부터 오른쪽 테두리까지
GUIDE_BAR_H := 9  ; 키 맨 위 테두리 줄(1)부터 막대 맨 아랫줄(8)까지
; 숫자키 1~9, 0이 놓인 줄의 왼쪽 x (맨 위 y=127)
GUIDE_DIGIT_X := [145, 212, 279, 346, 412, 479, 546, 613, 679, 746]
; 칠판 W·E·R이 놓인 줄 (맨 위 y=207)
GUIDE_BOARD_X := Map("W", 213, "E", 280, "R", 347)

PaintGuideBars(pBmp, imgW, imgH) {
    global GUIDE_IMG_W, GUIDE_IMG_H, GUIDE_BAR_W, GUIDE_BAR_H, GUIDE_DIGIT_X, GUIDE_BOARD_X
    global DRAW_COLORS, DRAW_ALPHAS, DRAW_COLOR_DEFAULTS, drawColor
    global BOARD_KEYS, BOARD_COLORS, BOARD_ALPHAS, BOARD_COLOR_DEFAULTS
    if (imgW != GUIDE_IMG_W || imgH != GUIDE_IMG_H)
        return
    rect := Buffer(16, 0)
    NumPut("int", 0, "int", 0, "int", imgW, "int", imgH, rect)
    data := Buffer(32, 0) ; BitmapData: Width, Height, Stride, PixelFormat, Scan0, Reserved
    if DllCall("gdiplus\GdipBitmapLockBits", "ptr", pBmp, "ptr", rect, "uint", 3, "int", 0x26200A, "ptr", data) ; 3 = 읽기+쓰기
        return
    scan0 := NumGet(data, 16, "ptr")
    stride := NumGet(data, 8, "int")

    ; 1번 키(빨강 막대)에서 픽셀마다의 막대 비율 a를 구한다
    bw := GUIDE_BAR_W, bh := GUIDE_BAR_H
    tplA := []
    border := [0x7F, 0xB4, 0xE8], bg := [0xF4, 0xF4, 0xF6]
    tplB := [] ; 섞여 있는 상대(테두리 또는 바탕)의 색
    loop bh {
        dy := A_Index - 1
        sh := (dy = bh - 1) ? 0.88 : 1
        loop bw {
            dx := A_Index - 1
            o := scan0 + (127 + dy) * stride + (145 + dx) * 4
            pr := NumGet(o, 2, "uchar"), pg := NumGet(o, 1, "uchar"), pb := NumGet(o, 0, "uchar")
            bestErr := 1e18, bestA := 0, bestB := bg
            for B in [border, bg] {
                ; 픽셀 = a·D + (1−a)·B 가 되는 a (D는 빨강 255,0,0)
                dr := 255 * sh - B[1], dg := 0 - B[2], db := 0 - B[3]
                den := dr * dr + dg * dg + db * db
                a := Max(0, Min(1, ((pr - B[1]) * dr + (pg - B[2]) * dg + (pb - B[3]) * db) / den))
                er := pr - (a * 255 * sh + (1 - a) * B[1]), eg := pg - (1 - a) * B[2], eb := pb - (1 - a) * B[3]
                err := er * er + eg * eg + eb * eb
                if (err < bestErr)
                    bestErr := err, bestA := a, bestB := B
            }
            tplA.Push(bestA), tplB.Push(bestB)
        }
    }

    ; 칠할 키들: [x, y, 옛 색(그림에 그려진 기본 색, -1이면 바탕과 섞어 칠함), 새 색, 투명도%]
    jobs := []
    loop 9
        jobs.Push([GUIDE_DIGIT_X[A_Index], 127, DRAW_COLOR_DEFAULTS[A_Index], DRAW_COLORS[A_Index], DRAW_ALPHAS[A_Index]])
    jobs.Push([GUIDE_DIGIT_X[10], 127, -1, drawColor, 100]) ; 0번은 기본 색 — 그림에는 줄무늬로 그려져 있다
    for index, pair in BOARD_KEYS {
        k := StrUpper(pair[1])
        if (BOARD_COLOR_DEFAULTS[index] >= 0 && GUIDE_BOARD_X.Has(k))
            jobs.Push([GUIDE_BOARD_X[k], 207, BOARD_COLOR_DEFAULTS[index], BOARD_COLORS[index], BOARD_ALPHAS[index]])
    }
    for job in jobs {
        x0 := job[1], y0 := job[2], oldC := job[3], newC := job[4], al := job[5] / 100
        ; 투명도를 낮춘 색은 흰 키 위에서 옅게 보인다 (맥 판과 같다)
        nr := ((newC >> 16) & 255) * al + 255 * (1 - al)
        ng := ((newC >> 8) & 255) * al + 255 * (1 - al)
        nb := (newC & 255) * al + 255 * (1 - al)
        orr := (oldC >= 0) ? (oldC >> 16) & 255 : 0, og := (oldC >= 0) ? (oldC >> 8) & 255 : 0, ob := (oldC >= 0) ? oldC & 255 : 0
        loop bh {
            dy := A_Index - 1
            sh := (dy = bh - 1) ? 0.88 : 1
            loop bw {
                dx := A_Index - 1
                n := dy * bw + dx + 1
                a := tplA[n]
                if (a = 0)
                    continue
                o := scan0 + (y0 + dy) * stride + (x0 + dx) * 4
                if (oldC >= 0) {
                    r := NumGet(o, 2, "uchar") + a * (nr - orr) * sh
                    g := NumGet(o, 1, "uchar") + a * (ng - og) * sh
                    b := NumGet(o, 0, "uchar") + a * (nb - ob) * sh
                } else {
                    B := tplB[n]
                    r := a * nr * sh + (1 - a) * B[1]
                    g := a * ng * sh + (1 - a) * B[2]
                    b := a * nb * sh + (1 - a) * B[3]
                }
                NumPut("uchar", Max(0, Min(255, Round(b))), o, 0)
                NumPut("uchar", Max(0, Min(255, Round(g))), o, 1)
                NumPut("uchar", Max(0, Min(255, Round(r))), o, 2)
            }
        }
    }
    DllCall("gdiplus\GdipBitmapUnlockBits", "ptr", pBmp, "ptr", data)
}

; 그림(GDI+ 비트맵)을 dstW×dstH 크기로 곱게 줄여 HBITMAP으로 돌려준다. 실패하면 0.
ScaledHBitmapFromImage(pSrc, dstW, dstH) {
    pDst := 0
    DllCall("gdiplus\GdipCreateBitmapFromScan0", "int", dstW, "int", dstH, "int", 0, "int", 0x26200A, "ptr", 0, "ptr*", &pDst) ; 32bppARGB
    pGraphics := 0
    DllCall("gdiplus\GdipGetImageGraphicsContext", "ptr", pDst, "ptr*", &pGraphics)
    DllCall("gdiplus\GdipSetInterpolationMode", "ptr", pGraphics, "int", 7) ; HighQualityBicubic — 글자가 뭉개지지 않는다
    DllCall("gdiplus\GdipSetPixelOffsetMode", "ptr", pGraphics, "int", 2)   ; HighQuality — 가장자리 한 줄이 잘리는 것을 막는다
    DllCall("gdiplus\GdipDrawImageRectI", "ptr", pGraphics, "ptr", pSrc, "int", 0, "int", 0, "int", dstW, "int", dstH)
    DllCall("gdiplus\GdipDeleteGraphics", "ptr", pGraphics)

    hBmp := 0
    DllCall("gdiplus\GdipCreateHBITMAPFromBitmap", "ptr", pDst, "ptr*", &hBmp, "uint", 0xFFFFFFFF) ; 배경 흰색(알파 있는 그림용)
    DllCall("gdiplus\GdipDisposeImage", "ptr", pDst)
    return hBmp
}

ShowShortcutGuide(*) {
    global shortcutGui, hShortcutBmp, SHORTCUT_IMAGE_PATH

    ; 이미 떠 있으면 앞으로 가져오기만 한다.
    if shortcutGui && WinExist("ahk_id " shortcutGui.Hwnd) {
        shortcutGui.Show()
        return
    }

    pImg := 0
    DllCall("gdiplus\GdipLoadImageFromFile", "wstr", SHORTCUT_IMAGE_PATH, "ptr*", &pImg)
    if !pImg {
        MsgBox("단축키 안내 그림을 열지 못했습니다.`n`n" SHORTCUT_IMAGE_PATH, "Focus & Draw - 단축키", "Icon!")
        return
    }
    imgW := 0, imgH := 0
    DllCall("gdiplus\GdipGetImageWidth", "ptr", pImg, "uint*", &imgW)
    DllCall("gdiplus\GdipGetImageHeight", "ptr", pImg, "uint*", &imgH)
    ; 창 바탕은 그림 왼쪽 아래 구석 색으로 둔다 (어떤 그림을 넣든 가장자리가 어울린다).
    stripBg := 0xFFFFFF
    argb := 0
    if !DllCall("gdiplus\GdipBitmapGetPixel", "ptr", pImg, "int", 2, "int", Max(0, imgH - 3), "uint*", &argb)
        stripBg := argb & 0xFFFFFF
    ; 픽셀을 고칠 수 있게 32비트 사본을 만들고, 키 위 색 막대를 지금 설정 색으로 칠한다
    pBase := 0
    DllCall("gdiplus\GdipCloneBitmapAreaI", "int", 0, "int", 0, "int", imgW, "int", imgH, "int", 0x26200A, "ptr", pImg, "ptr*", &pBase)
    DllCall("gdiplus\GdipDisposeImage", "ptr", pImg)
    if !pBase {
        MsgBox("단축키 안내 그림을 불러오지 못했습니다.`n`n" SHORTCUT_IMAGE_PATH, "Focus & Draw - 단축키", "Icon!")
        return
    }
    PaintGuideBars(pBase, imgW, imgH)

    ; 작업표시줄을 뺀 화면 안에 창틀까지 들어가도록, 여백을 조금 두고 비율을 구한다.
    ; (1보다 크면 1로 — 원본보다 키우지 않는다)
    MonitorGetWorkArea(, &waL, &waT, &waR, &waB)
    maxW := (waR - waL) - 60
    maxH := (waB - waT) - 80
    scale := Min(1.0, maxW / imgW, maxH / imgH)
    dstW := Max(1, Round(imgW * scale))
    dstH := Max(1, Round(imgH * scale))

    hShortcutBmp := ScaledHBitmapFromImage(pBase, dstW, dstH)
    DllCall("gdiplus\GdipDisposeImage", "ptr", pBase)
    if !hShortcutBmp {
        MsgBox("단축키 안내 그림을 불러오지 못했습니다.`n`n" SHORTCUT_IMAGE_PATH, "Focus & Draw - 단축키", "Icon!")
        return
    }

    ; 설정 창 뒤로 숨지 않도록 항상 위에 둔다. 읽기만 하는 창이라 다른 작업을 가릴 일이 없고,
    ; Esc나 창 닫기로 바로 닫힌다. (설정 창과 달리 화면을 보면서 맞출 값이 없으므로
    ;  AlwaysOnTop이 걸림돌이 되지 않는다)
    shortcutGui := Gui("-DPIScale -MaximizeBox -MinimizeBox +AlwaysOnTop", "Focus & Draw - 단축키")
    shortcutGui.MarginX := 0
    shortcutGui.MarginY := 0
    shortcutGui.BackColor := HexColor(stripBg)
    shortcutGui.SetFont("s10", "Malgun Gothic")
    shortcutGui.AddPicture("x0 y0 w" dstW " h" dstH, "HBITMAP:" hShortcutBmp)
    shortcutGui.OnEvent("Close", (*) => CloseShortcutGuide())
    shortcutGui.OnEvent("Escape", (*) => CloseShortcutGuide())
    shortcutGui.Show("w" dstW " h" dstH " Center")
}

; 창을 없애고 그림 자원도 함께 돌려준다. 다시 열 때는 처음부터 새로 만든다 — 자주 있는
; 일이 아니고, 그 사이에 화면 크기가 바뀌었더라도 알아서 새 크기에 맞춰진다.
CloseShortcutGuide() {
    global shortcutGui, hShortcutBmp
    if shortcutGui {
        shortcutGui.Destroy()
        shortcutGui := ""
    }
    if hShortcutBmp {
        DllCall("DeleteObject", "ptr", hShortcutBmp)
        hShortcutBmp := 0
    }
}

; ================= 컨트롤 위젯(화면 구석 미니 툴바) =================
; 좌우 여백(6px)을 "눈에 보이는 글자/아이콘 기준"으로 동일하게 맞춘다. 그립(⋮)은 글자 폭에
; 딱 맞는 좁은 칸이라 닫기(✕)도 같은 폭(14)으로 줄여야 양쪽 여백이 실제로 같아 보인다.
widgetW := 152
widgetH := 40

; 버튼 네모(강조/판서/설정)를 둥근 테두리+아이콘까지 한 장으로 미리 그려둔다.
; 처음엔 "둥근 칩 Picture" 위에 "아이콘 Picture"를 따로 겹쳤었는데, Picture 컨트롤의
; PNG 투명 처리가 항상 배경과 다시 합성되는 게 아니라서 색 있는 배경에서 아이콘 가장자리에
; 흰 테두리가 비치거나(작은 네모 자국) 심하면 아이콘이 통째로 안 보이는 문제가 있었다.
; 그래서 배경(위젯 바탕색)+둥근 사각형(채우기)+아이콘을 GDI/GDI+로 직접 한 비트맵에
; 합성해서 하나의 완성된 그림만 컨트롤에 넣는다 — 별도 겹침이 없으니 항상 정확하게 보인다.
CHIP_SIZE := 32
CHIP_CORNER := 12
CHIP_ICON_SIZE := 22
WIDGET_BG_COLOR := 0xF2F2F2
ICON_OFF_COLOR := 0x000000
; 켜짐 상태를 표시할 색 — 위젯 버튼과 트레이 바로가기 아이콘이 같은 색을 쓴다.
TRAY_ON_COLOR := 0x0A84FF

RenderButtonBitmap(fillColor, bgColor, size, corner, iconPath, iconSize, iconColor) {
    hdcScreen := DllCall("GetDC", "ptr", 0, "ptr")
    hdc := DllCall("CreateCompatibleDC", "ptr", hdcScreen, "ptr")
    hBmp := DllCall("CreateCompatibleBitmap", "ptr", hdcScreen, "int", size, "int", size, "ptr")
    DllCall("ReleaseDC", "ptr", 0, "ptr", hdcScreen)
    old := DllCall("SelectObject", "ptr", hdc, "ptr", hBmp, "ptr")

    bgBrush := DllCall("CreateSolidBrush", "uint", ToBGR(bgColor), "ptr")
    rc := Buffer(16, 0)
    NumPut("Int", size, rc, 8)
    NumPut("Int", size, rc, 12)
    DllCall("FillRect", "ptr", hdc, "ptr", rc, "ptr", bgBrush)
    DllCall("DeleteObject", "ptr", bgBrush)

    ; NULL_PEN(테두리 없음)으로 채우기만 한다. RoundRect는 펜의 두께만큼 안쪽만 채우는
    ; 버릇이 있어서, 펜이 없을 때 가장자리에 1px 틈이 남지 않도록 사각형을 1px 더 크게 잡는다.
    nullPen := DllCall("GetStockObject", "int", 8, "ptr") ; NULL_PEN
    brush := DllCall("CreateSolidBrush", "uint", ToBGR(fillColor), "ptr")
    oldPen := DllCall("SelectObject", "ptr", hdc, "ptr", nullPen, "ptr")
    oldBrush := DllCall("SelectObject", "ptr", hdc, "ptr", brush, "ptr")
    DllCall("RoundRect", "ptr", hdc, "int", 0, "int", 0, "int", size + 1, "int", size + 1, "int", corner, "int", corner)
    DllCall("SelectObject", "ptr", hdc, "ptr", oldPen)
    DllCall("SelectObject", "ptr", hdc, "ptr", oldBrush)
    DllCall("DeleteObject", "ptr", brush)

    ; 아이콘을 불러와 지정된 색으로 다시 칠한다 (트레이 바로가기 아이콘과 같은 방식 —
    ; 켜짐 상태는 배경이 아니라 아이콘 자체의 색이 파랗게 바뀐다). 알파는 그대로 둬서
    ; 모양은 유지한다.
    pIcon := 0
    DllCall("gdiplus\GdipLoadImageFromFile", "wstr", iconPath, "ptr*", &pIcon)
    iw := 0, ih := 0
    DllCall("gdiplus\GdipGetImageWidth", "ptr", pIcon, "uint*", &iw)
    DllCall("gdiplus\GdipGetImageHeight", "ptr", pIcon, "uint*", &ih)
    lockRect := Buffer(16, 0)
    NumPut("Int", iw, lockRect, 8)
    NumPut("Int", ih, lockRect, 12)
    bmd := Buffer(32, 0)
    DllCall("gdiplus\GdipBitmapLockBits", "ptr", pIcon, "ptr", lockRect, "uint", 3, "int", 0x26200A, "ptr", bmd) ; ReadWrite, 32bppARGB
    stride := NumGet(bmd, 8, "Int")
    scan0 := NumGet(bmd, 16, "Ptr")
    itr := (iconColor >> 16) & 0xFF
    itg := (iconColor >> 8) & 0xFF
    itb := iconColor & 0xFF
    loop ih {
        rowPtr := scan0 + (A_Index - 1) * stride
        loop iw {
            px := rowPtr + (A_Index - 1) * 4
            NumPut("UChar", itb, px, 0) ; B
            NumPut("UChar", itg, px, 1) ; G
            NumPut("UChar", itr, px, 2) ; R (알파는 그대로 유지)
        }
    }
    DllCall("gdiplus\GdipBitmapUnlockBits", "ptr", pIcon, "ptr", bmd)

    ; GDI+로 같은 hdc 위에 다시 칠한 아이콘을 알파값 그대로 합성해 그린다.
    pGraphics := 0
    DllCall("gdiplus\GdipCreateFromHDC", "ptr", hdc, "ptr*", &pGraphics)
    off := (size - iconSize) // 2
    DllCall("gdiplus\GdipDrawImageRectI", "ptr", pGraphics, "ptr", pIcon, "int", off, "int", off, "int", iconSize, "int", iconSize)
    DllCall("gdiplus\GdipDisposeImage", "ptr", pIcon)
    DllCall("gdiplus\GdipDeleteGraphics", "ptr", pGraphics)

    DllCall("SelectObject", "ptr", hdc, "ptr", old)
    DllCall("DeleteDC", "ptr", hdc)
    return hBmp
}

; 위젯 창 자체의 바깥 테두리도 둥글게 잘라낸다 (칩과 달리 배경이 단색 하나뿐이라
; SetWindowRgn만으로 충분히 자연스럽게 보인다).
RoundRegion(hwnd, w, h, corner) {
    rgn := DllCall("CreateRoundRectRgn", "int", 0, "int", 0, "int", w, "int", h, "int", corner, "int", corner, "ptr")
    DllCall("SetWindowRgn", "ptr", hwnd, "ptr", rgn, "int", true)
}

; 위젯은 크기·배경색이 바뀔 때마다 **통째로 다시 만든다.** 버튼 그림이 배경색에 미리
; 합성된 비트맵이라 배경색이 바뀌면 그림도 다시 그려야 하고, 만들어둔 Picture 컨트롤에
; 비트맵을 나중에 바꿔 넣는(STM_SETIMAGE) 방식은 예전에 간헐적으로 안 보이는 문제가 있었다
; (그래서 꺼짐/켜짐 그림도 컨트롤을 둘 만들어 보이기/숨기기로 전환한다). 다시 만드는 편이
; 훨씬 확실하고, 자주 일어나는 일도 아니다.
; 위치는 유지한다 — 크기를 조절하는 동안 위젯이 구석으로 튀면 곤란하다.
WidgetPx(base) {
    global widgetScale
    return Max(1, Round(base * widgetScale / 100))
}

BuildWidget() {
    global widget, grip, btnSpotOff, btnSpotOn, btnDrawOff, btnDrawOn, btnSettings, btnClose
    global hBtnSpotOff, hBtnSpotOn, hBtnDrawOff, hBtnDrawOn, hBtnSettings
    global widgetW, widgetH, widgetScale, widgetBgColor, widgetX, widgetY
    global CHIP_SIZE, CHIP_CORNER, CHIP_ICON_SIZE, ICON_OFF_COLOR, TRAY_ON_COLOR
    global ICON_SPOT_DARK_PATH, ICON_DRAW_DARK_PATH, ICON_SETTINGS_PATH

    ; 이전 위젯이 있으면 자리를 기억해두고 치운다 (비트맵도 함께 — 안 지우면 조절할 때마다 샌다)
    keepX := "", keepY := ""
    if IsSet(widget) && widget {
        try WinGetPos(&keepX, &keepY, , , widget)
        for h in [hBtnSpotOff, hBtnSpotOn, hBtnDrawOff, hBtnDrawOn, hBtnSettings]
            try DllCall("DeleteObject", "ptr", h)
        try widget.Destroy()
        ; 없앤 창을 가리키는 채로 두면, 다시 만들기 전에 들어온 클릭이 죽은 창을 건드린다.
        ; 비워둬야 그 사이에 온 메시지가 "지금은 위젯이 없다"를 알아볼 수 있다.
        widget := "", grip := ""
    }

    chip := WidgetPx(CHIP_SIZE)
    corner := WidgetPx(CHIP_CORNER)
    icon := WidgetPx(CHIP_ICON_SIZE)
    pad := WidgetPx(6)   ; 좌우 여백
    top := WidgetPx(4)   ; 위아래 여백
    narrow := WidgetPx(14) ; 그립(⋮)·닫기(✕)처럼 글자 폭에 맞춘 좁은 칸
    gap := WidgetPx(4)   ; 칩 사이 간격
    widgetH := chip + top * 2
    widgetW := pad * 2 + narrow * 2 + chip * 3 + gap * 4

    hBtnSpotOff := RenderButtonBitmap(0xFFFFFF, widgetBgColor, chip, corner, ICON_SPOT_DARK_PATH, icon, ICON_OFF_COLOR)
    hBtnSpotOn := RenderButtonBitmap(0xFFFFFF, widgetBgColor, chip, corner, ICON_SPOT_DARK_PATH, icon, TRAY_ON_COLOR)
    hBtnDrawOff := RenderButtonBitmap(0xFFFFFF, widgetBgColor, chip, corner, ICON_DRAW_DARK_PATH, icon, ICON_OFF_COLOR)
    hBtnDrawOn := RenderButtonBitmap(0xFFFFFF, widgetBgColor, chip, corner, ICON_DRAW_DARK_PATH, icon, TRAY_ON_COLOR)
    hBtnSettings := RenderButtonBitmap(0xFFFFFF, widgetBgColor, chip, corner, ICON_SETTINGS_PATH, icon, ICON_OFF_COLOR)

    widget := Gui("+AlwaysOnTop -Caption +ToolWindow", "FocusDraw")
    widget.BackColor := HexColor(widgetBgColor)
    ; 배경이 어두우면 ⋮와 ✕가 묻히므로 글자색을 뒤집는다 (밝기 기준은 사람 눈의 민감도 가중치)
    widget.SetFont("s" Max(6, WidgetPx(10)) " c" (WidgetIsDark() ? "E6E6E6" : "000000"), "Malgun Gothic")

    x := pad
    grip := widget.AddText("x" x " y" top " w" narrow " h" chip " Center +0x200", "⋮")
    x += narrow + gap
    btnSpotOff := widget.AddPicture("x" x " y" top " w" chip " h" chip, "HBITMAP:" hBtnSpotOff)
    btnSpotOn := widget.AddPicture("x" x " y" top " w" chip " h" chip " Hidden", "HBITMAP:" hBtnSpotOn)
    x += chip + gap
    btnDrawOff := widget.AddPicture("x" x " y" top " w" chip " h" chip, "HBITMAP:" hBtnDrawOff)
    btnDrawOn := widget.AddPicture("x" x " y" top " w" chip " h" chip " Hidden", "HBITMAP:" hBtnDrawOn)
    x += chip + gap
    btnSettings := widget.AddPicture("x" x " y" top " w" chip " h" chip, "HBITMAP:" hBtnSettings)
    x += chip + gap
    btnClose := widget.AddText("x" x " y" top " w" narrow " h" chip " Center +0x200", "✕")

    for ctrl in [btnSpotOff, btnSpotOn]
        ctrl.OnEvent("Click", ToggleSpotlight)
    for ctrl in [btnDrawOff, btnDrawOn]
        ctrl.OnEvent("Click", ToggleDrawFromWidget) ; 끌 때는 그려둔 것도 지운다 (Esc와 같은 효과)
    btnSettings.OnEvent("Click", OpenSettingsWindow)
    ; 위젯의 ✕는 프로그램 종료가 아니라 위젯만 숨김 (트레이 메뉴의 "위젯 표시"나 설정 창의
    ; "위젯" 탭에서 다시 켤 수 있음)
    ; 주의: 여기서 (*) => (showWidget := false, ...) 처럼 화살표 함수 안에서 전역 변수에 값을
    ; 넣으면 안 된다. AutoHotkey v2에서 함수 안의 대입은 global 선언이 없으면 같은 이름의
    ; 지역 변수를 새로 만들 뿐이라 전역값이 그대로 남는다. 실제로 그 탓에 ✕로 위젯을 숨겨도
    ; showWidget은 계속 참이어서, 설정 창의 "위젯 활성화"가 체크된 채로 보이고 한 번 눌러도
    ; 다시 나타나지 않는 버그가 있었다. 그래서 global을 선언할 수 있는 보통 함수로 둔다.
    btnClose.OnEvent("Click", (*) => SetWidgetVisible(false))

    ; 이전 위젯이 없었으면(= 프로그램을 막 켠 것) 지난번에 옮겨둔 자리부터 찾는다.
    ; 그마저 없으면(처음 쓰는 PC) 화면 오른쪽 아래에서 시작한다.
    ; 저장된 자리가 지금 모니터 구성에서 화면 밖이더라도, 아래 ClampWidgetIntoScreen이 들여놓는다.
    if (keepX = "" || keepY = "") {
        keepX := widgetX, keepY := widgetY
    }
    if (keepX = "" || keepY = "") {
        DefaultWidgetPos(&keepX, &keepY)
    }
    widget.Show("x" keepX " y" keepY " w" widgetW " h" widgetH " Hide")
    RoundRegion(widget.Hwnd, widgetW, widgetH, WidgetPx(16))
    ApplyWidgetOpacity() ; 새로 만든 창이라 투명도를 다시 걸어줘야 한다
    ClampWidgetIntoScreen() ; 커진 뒤 화면 밖으로 밀려나 있으면 도로 들여놓는다
}

; 슬라이더를 끄는 동안 매 칸마다 위젯을 다시 만들면 깜빡인다. 마지막 움직임에서 조금 있다가
; 한 번만 만들도록 미뤄둔다 (SetTimer의 음수 간격 = 한 번만 실행, 다시 부르면 시계가 새로 시작).
RebuildWidgetSoon() {
    global showWidget
    BuildWidget()
    SetWidgetVisible(showWidget)
}

; 위젯을 처음 자리(오른쪽 아래)로. 크기를 키우면 폭·높이가 달라지므로 그때그때 계산한다.
DefaultWidgetPos(&x, &y) {
    global widgetW, widgetH
    x := A_ScreenWidth - widgetW - 20
    y := A_ScreenHeight - widgetH - 60
}

; 위젯을 어디 뒀는지 잊었거나 화면 밖 어딘가로 보내버렸을 때를 위한 탈출구.
; **늘 처음 자리(오른쪽 아래)로 간다** — 저장해둔 자리가 아니라 계산한 기본 자리다.
MoveWidgetToDefaultPos() {
    global widget
    if (!IsSet(widget) || !widget)
        return
    DefaultWidgetPos(&x, &y)
    try {
        WinMove(x, y, , , widget)
        RaiseWidget()
    }
    SaveWidgetPos() ; 되돌린 자리도 기억한다 — 다시 켰을 때 또 엉뚱한 곳에 있으면 곤란하다
}

; 위젯을 옮긴 자리를 settings.ini에 바로 적는다.
; **다른 설정과 달리 "저장" 버튼을 기다리지 않는다.** 위젯 위치는 눈금으로 맞추는 설정이
; 아니라 손으로 끌어다 놓는 상태라, 옮겨두면 그 자리에 있는 것이 당연하게 느껴진다.
; 옮길 때마다 설정 창을 열어 저장을 누르라고 할 수는 없다(자동 실행 체크도 같은 이유로
; 저장 버튼과 무관하게 바로 반영된다).
; 쓰기가 막힌 폴더에서는 조용히 넘어간다 — 위치가 안 남을 뿐이고, 여기서 오류 창을 띄우면
; 위젯을 옮길 때마다 창이 뜨는 꼴이 된다(저장 버튼 쪽은 안내를 띄운다).
SaveWidgetPos() {
    global widget, widgetX, widgetY, SETTINGS_PATH
    if (!IsSet(widget) || !widget)
        return
    try {
        WinGetPos(&x, &y, , , widget)
        widgetX := x, widgetY := y
        IniWrite(x, SETTINGS_PATH, "Common", "WidgetX")
        IniWrite(y, SETTINGS_PATH, "Common", "WidgetY")
    }
}

; 위젯 투명도. 100%면 레이어드 속성 자체를 떼어내 평소와 똑같이 그려지게 한다 —
; 굳이 반투명 처리를 거칠 이유가 없다.
ApplyWidgetOpacity() {
    global widget, widgetOpacity
    if (!IsSet(widget) || !widget)
        return
    try {
        if (widgetOpacity >= 100)
            WinSetTransparent("Off", widget)
        else
            WinSetTransparent(Max(0, Min(255, Round(widgetOpacity * 255 / 100))), widget)
    }
}

; 배경색이 어두운 편인지 (글자색을 뒤집을지 판단)
WidgetIsDark() {
    global widgetBgColor
    r := (widgetBgColor >> 16) & 0xFF, g := (widgetBgColor >> 8) & 0xFF, b := widgetBgColor & 0xFF
    return (r * 299 + g * 587 + b * 114) / 1000 < 128
}

; ================= 위젯이 화면 밖으로 나가지 않게 =================
; 옮기는 동안 Windows가 보내주는 WM_MOVING을 받아 목적지를 고쳐 쓴다. 위젯을 끄는 드래그는
; 우리가 직접 좌표를 계산하는 게 아니라 Windows에 맡기는 방식(WM_NCLBUTTONDOWN + HTCAPTION)
; 이라, 놓은 뒤에 되돌리는 것보다 이렇게 옮겨지는 중에 잡아주는 쪽이 자연스럽다.
;
; **모니터가 둘 이상일 때가 문제다.** 가상 화면(모든 모니터를 감싼 사각형) 안으로만 묶으면,
; 크기가 다른 모니터를 나란히 쓸 때 생기는 빈 구역(어느 모니터에도 안 걸리는 자리)에 위젯을
; 놓을 수 있어 그대로 사라져 보인다. 그래서 **커서가 지금 있는 모니터**의 작업 영역 안으로
; 묶는다 — 커서를 옆 모니터로 옮기면 기준도 같이 넘어가므로 모니터 사이 이동은 그대로 되고,
; 빈 구역에는 애초에 놓일 수 없다. 작업 영역을 쓰므로 작업표시줄 아래로도 숨지 않는다.
;
; **못 가게 막는 선과 자석이 붙는 선은 다르다.**
;  - 막는 선: 모니터의 실제 가장자리. 여기까지는 갈 수 있으므로 **작업표시줄 위에도 놓을 수 있다**
;    (수업 중 작업표시줄 자리에 위젯을 두고 싶다는 요구가 있었다). 화면 밖으로만 못 나간다.
;  - 자석이 붙는 선: **작업표시줄 안쪽 선 하나뿐**이다. 작업표시줄 바로 위에 반듯하게 세우기
;    쉬우면서, 더 밀면 작업표시줄 위로 넘어간다. **화면 테두리에는 자석을 걸지 않는다** —
;    거기는 어차피 더 갈 수 없어 저절로 멈추므로, 자석까지 있으면 안 떨어지는 느낌만 준다.
; 붙는 거리 15px. 예전에 "붙으면 안 떨어진다"고 느껴졌던 것은 이 거리 탓이 아니라 기준값이
; 자석에 끌려다니던 버그 탓이었다(아래 widgetGrabX 설명 참고). 그것을 고친 뒤로는 넉넉히
; 잡아도 밀면 그냥 지나간다.
WIDGET_SNAP_PX := 15

; 화면 좌표 (x, y)가 속한 모니터. 전체 영역과 작업 영역을 함께 돌려준다.
; 어디에도 안 속하면 가장 가까운 모니터를 준다.
GetMonitorAt(x, y, &ml, &mt, &mr, &mb, &wl, &wt, &wr, &wb) {
    pt := (x & 0xFFFFFFFF) | (y << 32)
    hMon := DllCall("MonitorFromPoint", "int64", pt, "uint", 2, "ptr") ; MONITOR_DEFAULTTONEAREST
    if !hMon
        return false
    mi := Buffer(40, 0)
    NumPut("UInt", 40, mi, 0) ; cbSize
    if !DllCall("GetMonitorInfo", "ptr", hMon, "ptr", mi)
        return false
    ml := NumGet(mi, 4, "Int"), mt := NumGet(mi, 8, "Int")            ; rcMonitor
    mr := NumGet(mi, 12, "Int"), mb := NumGet(mi, 16, "Int")
    wl := NumGet(mi, 20, "Int"), wt := NumGet(mi, 24, "Int")          ; rcWork
    wr := NumGet(mi, 28, "Int"), wb := NumGet(mi, 32, "Int")
    return true
}

; 후보 선들 중 가장 가까운 것에 붙인다. 못 붙이면 원래 값 그대로.
SnapEdge(pos, size, nearEdges, farEdges, threshold) {
    for e in nearEdges
        if (Abs(pos - e) <= threshold)
            return e
    for e in farEdges
        if (Abs(pos + size - e) <= threshold)
            return e - size
    return pos
}

; **커서와 위젯의 거리를 우리가 직접 들고 있어야 한다.**
; Windows가 알려주는 "옮겨질 자리"를 그대로 믿고 거기서 자석을 계산하면, 붙은 순간 위젯이
; 선 위로 당겨지고 **다음 계산의 기준도 그 당겨진 자리가 된다.** 그러면 1px씩 천천히 끌 때
; 매번 "1px 이동 → 자석 범위 안 → 도로 선 위로"가 반복되어 **영원히 못 벗어난다**
; (빠르게 흔들면 한 번에 범위를 넘겨서 빠져나가는 것이 그 증거였다).
; 그래서 진짜 위치는 늘 커서에서 다시 계산하고, 자석은 **보이는 자리에만** 적용한다.
widgetDragging := false
widgetGrabX := 0, widgetGrabY := 0 ; 잡은 지점이 위젯 왼쪽 위에서 얼마나 떨어져 있는지

OnWidgetEnterMove(wParam, lParam, msg, hwnd) {
    global widget, widgetDragging, widgetGrabX, widgetGrabY
    if (!IsSet(widget) || !widget || hwnd != widget.Hwnd)
        return
    MouseGetPos(&mx, &my)
    try {
        WinGetPos(&x, &y, , , widget)
        widgetGrabX := mx - x, widgetGrabY := my - y
        widgetDragging := true
    }
}
OnMessage(0x0231, OnWidgetEnterMove) ; WM_ENTERSIZEMOVE

OnWidgetExitMove(wParam, lParam, msg, hwnd) {
    global widget, widgetDragging
    if (IsSet(widget) && widget && hwnd = widget.Hwnd) {
        widgetDragging := false
        RaiseWidget()
        SaveWidgetPos() ; 옮긴 자리를 바로 기억한다 (다음에 켤 때 그 자리에서 시작)
    }
}
OnMessage(0x0232, OnWidgetExitMove) ; WM_EXITSIZEMOVE

; 위젯을 "항상 위" 무리의 맨 앞으로 다시 올린다.
; 작업표시줄도 "항상 위" 창이라, 위젯을 그 위에 얹어두면 상황에 따라 작업표시줄에 가려
; 아래로 들어간 것처럼 보일 수 있다. 자리를 옮긴 뒤나 다시 보여줄 때 한 번씩 올려둔다.
; (-1 = HWND_TOPMOST / 0x1 = 크기 유지, 0x2 = 위치 유지, 0x10 = 활성화하지 않음)
RaiseWidget() {
    global widget
    if (!IsSet(widget) || !widget)
        return
    try DllCall("SetWindowPos", "ptr", widget.Hwnd, "ptr", -1
        , "int", 0, "int", 0, "int", 0, "int", 0, "uint", 0x1 | 0x2 | 0x10)
}

; 판서 오버레이를 클릭해도 그 창이 앞으로 올라오지 않게 한다.
; WS_EX_NOACTIVATE는 "활성화"만 막을 뿐, 클릭했을 때 창을 앞으로 끌어올리는 것까지는 막지
; 못한다. 그 단계는 여기서 MA_NOACTIVATE(3)를 돌려줘야 멈춘다 — 안 그러면 한 획 긋는 순간
; 오버레이가 위젯 위로 올라가서, 그 뒤로는 위젯을 눌러도 클릭이 오버레이에 막힌다.
OnDrawGuiMouseActivate(wParam, lParam, msg, hwnd) {
    global drawGui
    if (IsSet(drawGui) && drawGui && hwnd = drawGui.Hwnd)
        return 3 ; MA_NOACTIVATE — 활성화도 앞으로 올리기도 하지 않고 클릭은 그대로 전달
}
OnMessage(0x0021, OnDrawGuiMouseActivate) ; WM_MOUSEACTIVATE

OnWidgetMoving(wParam, lParam, msg, hwnd) {
    global widget, WIDGET_SNAP_PX, widgetDragging, widgetGrabX, widgetGrabY
    if (!IsSet(widget) || !widget || hwnd != widget.Hwnd)
        return
    l := NumGet(lParam, 0, "Int"), t := NumGet(lParam, 4, "Int")
    w := NumGet(lParam, 8, "Int") - l, h := NumGet(lParam, 12, "Int") - t
    MouseGetPos(&mx, &my)
    if !GetMonitorAt(mx, my, &ml, &mt, &mr, &mb, &wl, &wt, &wr, &wb)
        return
    if widgetDragging {
        ; 붙어 있든 말든 커서를 기준으로 다시 잡는다 — 자석이 기준을 흔들지 못한다
        l := mx - widgetGrabX, t := my - widgetGrabY
    }
    ; 막는 것은 모니터 가장자리까지만 — 작업표시줄 위로는 갈 수 있다.
    ; 벽에 부딪혀 멈췄으면 잡은 지점을 다시 맞춘다. 안 그러면 커서가 벽 너머로 간 만큼
    ; 되돌아와야 위젯이 움직이기 시작하는 고무줄 느낌이 된다.
    cl := Max(ml, Min(mr - w, l)), ct := Max(mt, Min(mb - h, t))
    if widgetDragging {
        if (cl != l)
            widgetGrabX := mx - cl
        if (ct != t)
            widgetGrabY := my - ct
    }
    ; 자석은 **맨 마지막에, 보이는 자리에만** 건다 (위의 기준값은 건드리지 않는다).
    ; **붙는 곳은 작업표시줄 안쪽 선뿐이다.** 화면 테두리에는 자석을 걸지 않는다 — 거기는
    ; 어차피 더 갈 수 없어서 저절로 멈추므로, 자석까지 있으면 "왜 안 떨어지지" 하게 된다.
    ; 작업 영역 가장자리가 모니터 가장자리와 다른 쪽이 곧 작업표시줄이 있는 쪽이다.
    sl := SnapEdge(cl, w, (wl != ml) ? [wl] : [], (wr != mr) ? [wr] : [], WIDGET_SNAP_PX)
    st := SnapEdge(ct, h, (wt != mt) ? [wt] : [], (wb != mb) ? [wb] : [], WIDGET_SNAP_PX)
    NumPut("Int", sl, lParam, 0), NumPut("Int", st, lParam, 4)
    NumPut("Int", sl + w, lParam, 8), NumPut("Int", st + h, lParam, 12)
    return true
}
OnMessage(0x0216, OnWidgetMoving) ; WM_MOVING

; 크기를 키웠거나 모니터 구성이 바뀌어 위젯이 화면 밖에 걸쳐 있으면 안으로 들여놓는다.
; 여기서도 기준은 모니터 가장자리다 — 작업표시줄 위에 일부러 둔 위젯을 멋대로 끌어올리지 않는다.
ClampWidgetIntoScreen() {
    global widget
    if (!IsSet(widget) || !widget)
        return
    try WinGetPos(&x, &y, &w, &h, widget)
    catch
        return
    if !GetMonitorAt(x + w // 2, y + h // 2, &ml, &mt, &mr, &mb, &wl, &wt, &wr, &wb)
        return
    nx := Max(ml, Min(mr - w, x)), ny := Max(mt, Min(mb - h, y))
    if (nx != x || ny != y)
        try WinMove(nx, ny, , , widget)
}

UpdateWidgetState() {
    global spotlightOn, drawOn, btnSpotOff, btnSpotOn, btnDrawOff, btnDrawOn
    global hIconSpotOn, hIconSpotOff, hIconDrawOn, hIconDrawOff, showTrayIcons
    btnSpotOff.Visible := !spotlightOn
    btnSpotOn.Visible := spotlightOn
    btnDrawOff.Visible := !drawOn
    btnDrawOn.Visible := drawOn

    if showTrayIcons {
        SetQuickTrayIcon(1, spotlightOn ? hIconSpotOn : hIconSpotOff)
        SetQuickTrayIcon(2, drawOn ? hIconDrawOn : hIconDrawOff)
    }
}

; ================= 트레이 아이콘 메뉴 (작업표시줄 알림 영역) =================
; 기본 AutoHotkey 개발용 메뉴(Window Spy, Reload Script 등)를 포함해 전부 지우고,
; 설정/종료 두 개만 남긴다. 강조·판서·색상은 위젯의 ⚙(설정) 또는 트레이 바로가기 아이콘으로 접근.
; 위젯을 ✕로 숨기고 나면 화면에 남는 단추가 하나도 없어서, 트레이 메뉴에서 바로 다시 켤 수
; 있도록 체크 항목을 둔다. (설정 창의 "위젯" 탭에서도 켤 수 있다)
TRAY_WIDGET_ITEM := "위젯 표시"

; 위젯 표시 여부를 바꾸는 유일한 통로. 트레이 메뉴 체크 표시와 설정 창 체크박스까지 같이
; 맞춰줘야 세 곳(위젯 ✕, 트레이 메뉴, 설정 창)이 서로 어긋나지 않는다.
SetWidgetVisible(show) {
    global showWidget, widget, TRAY_WIDGET_ITEM, chkWidgetCtrl
    showWidget := show ? true : false
    if showWidget {
        widget.Show()
        RaiseWidget() ; 작업표시줄 위에 둔 경우 가려지지 않도록 맨 앞으로
    } else
        widget.Hide()
    if showWidget
        A_TrayMenu.Check(TRAY_WIDGET_ITEM)
    else
        A_TrayMenu.Uncheck(TRAY_WIDGET_ITEM)
    ; 설정 창은 닫아도 없애지 않고 숨겨뒀다가 다시 쓰기 때문에, 열려 있지 않더라도 체크
    ; 상태를 지금 맞춰둬야 다음에 열었을 때 옛 상태가 보이지 않는다.
    if IsSet(chkWidgetCtrl) && chkWidgetCtrl
        try chkWidgetCtrl.Value := showWidget
}

A_TrayMenu.Delete()
A_TrayMenu.Add("설정...", OpenSettingsWindow)
A_TrayMenu.Add(TRAY_WIDGET_ITEM, (*) => SetWidgetVisible(!showWidget))
A_TrayMenu.Add("종료", (*) => ExitApp())
A_TrayMenu.Default := "설정..."

; ================= 작업표시줄 바로가기 아이콘 (강조/판서 2개, 클릭 한 번으로 토글) =================
; 메뉴를 거치지 않고 바로 누를 수 있는 전용 트레이 아이콘 2개를 추가로 만든다.
WM_TRAYBTN := 0x8014

; PNG 아이콘 파일을 불러와서, 투명도는 그대로 두고 색상만 원하는 색으로 새로 칠해 트레이 아이콘으로 변환한다.
LoadIconFromPng(path, rgb) {
    tr := (rgb >> 16) & 0xFF
    tg := (rgb >> 8) & 0xFF
    tb := rgb & 0xFF
    pBitmap := 0
    DllCall("gdiplus\GdipLoadImageFromFile", "wstr", path, "ptr*", &pBitmap)
    if !pBitmap
        return 0

    w := 0, h := 0
    DllCall("gdiplus\GdipGetImageWidth", "ptr", pBitmap, "uint*", &w)
    DllCall("gdiplus\GdipGetImageHeight", "ptr", pBitmap, "uint*", &h)

    rect := Buffer(16, 0)
    NumPut("Int", w, rect, 8)
    NumPut("Int", h, rect, 12)

    bmd := Buffer(32, 0)
    DllCall("gdiplus\GdipBitmapLockBits", "ptr", pBitmap, "ptr", rect, "uint", 3, "int", 0x26200A, "ptr", bmd) ; ReadWrite, 32bppARGB
    stride := NumGet(bmd, 8, "Int")
    scan0 := NumGet(bmd, 16, "Ptr")

    loop h {
        rowPtr := scan0 + (A_Index - 1) * stride
        loop w {
            px := rowPtr + (A_Index - 1) * 4
            NumPut("UChar", tb, px, 0) ; B
            NumPut("UChar", tg, px, 1) ; G
            NumPut("UChar", tr, px, 2) ; R (알파는 건드리지 않아 원래 모양 그대로 유지)
        }
    }
    DllCall("gdiplus\GdipBitmapUnlockBits", "ptr", pBitmap, "ptr", bmd)

    hIcon := 0
    DllCall("gdiplus\GdipCreateHICONFromBitmap", "ptr", pBitmap, "ptr*", &hIcon)
    DllCall("gdiplus\GdipDisposeImage", "ptr", pBitmap)
    return hIcon
}

AddQuickTrayIcon(uid, hIcon, tip) {
    global trayHelper, WM_TRAYBTN
    nid := Buffer(976, 0) ; NOTIFYICONDATAW (x64)
    NumPut("UInt", 976, nid, 0)              ; cbSize
    NumPut("Ptr", trayHelper.Hwnd, nid, 8)    ; hWnd
    NumPut("UInt", uid, nid, 16)              ; uID
    NumPut("UInt", 0x1 | 0x2 | 0x4, nid, 20)  ; uFlags: NIF_MESSAGE|NIF_ICON|NIF_TIP
    NumPut("UInt", WM_TRAYBTN, nid, 24)       ; uCallbackMessage
    NumPut("Ptr", hIcon, nid, 32)             ; hIcon
    StrPut(tip, nid.Ptr + 40, 128, "UTF-16")  ; szTip
    DllCall("shell32\Shell_NotifyIconW", "uint", 0, "ptr", nid) ; NIM_ADD
}

; 켜짐/꺼짐에 따라 트레이 아이콘의 색만 바꿔 끼운다.
SetQuickTrayIcon(uid, hIcon) {
    global trayHelper
    nid := Buffer(976, 0)
    NumPut("UInt", 976, nid, 0)
    NumPut("Ptr", trayHelper.Hwnd, nid, 8)
    NumPut("UInt", uid, nid, 16)
    NumPut("UInt", 0x2, nid, 20) ; NIF_ICON
    NumPut("Ptr", hIcon, nid, 32)
    DllCall("shell32\Shell_NotifyIconW", "uint", 1, "ptr", nid) ; NIM_MODIFY
}

RemoveQuickTrayIcon(uid) {
    global trayHelper
    nid := Buffer(24, 0)
    NumPut("UInt", 24, nid, 0)
    NumPut("Ptr", trayHelper.Hwnd, nid, 8)
    NumPut("UInt", uid, nid, 16)
    DllCall("shell32\Shell_NotifyIconW", "uint", 2, "ptr", nid) ; NIM_DELETE
}

OnQuickTrayClick(wParam, lParam, msg, hwnd) {
    global trayHelper
    if (hwnd != trayHelper.Hwnd)
        return
    if (lParam = 0x202) { ; WM_LBUTTONUP
        if (wParam = 1)
            ToggleSpotlight()
        else if (wParam = 2)
            ToggleDraw()
    }
}

; 작업표시줄이 라이트 모드면 흰색 "꺼짐" 아이콘이 밝은 배경에 묻혀 안 보이므로,
; Windows 시스템 테마를 읽어서 밝은 테마일 때는 어두운 색으로 대신 칠한다.
IsLightTaskbar() {
    try
        return RegRead("HKCU\Software\Microsoft\Windows\CurrentVersion\Themes\Personalize", "SystemUsesLightTheme") = 1
    catch
        return false
}
TRAY_OFF_COLOR := IsLightTaskbar() ? 0x1A1A1A : 0xFFFFFF

hIconSpotOff := LoadIconFromPng(ICON_SPOT_PATH, TRAY_OFF_COLOR)
hIconSpotOn := LoadIconFromPng(ICON_SPOT_PATH, TRAY_ON_COLOR)
hIconDrawOff := LoadIconFromPng(ICON_DRAW_PATH, TRAY_OFF_COLOR)
hIconDrawOn := LoadIconFromPng(ICON_DRAW_PATH, TRAY_ON_COLOR)

trayHelper := Gui("+ToolWindow", "FocusDraw-TrayHelper")
trayHelper.Show("Hide")
OnMessage(WM_TRAYBTN, OnQuickTrayClick)

; 강조/판서 바로가기 트레이 아이콘 2개를 켜고 끈다. (트레이 메뉴가 있는 기본 아이콘은 항상 유지됨)
SetTrayIconsVisible(show) {
    global showTrayIcons, hIconSpotOff, hIconSpotOn, hIconDrawOff, hIconDrawOn, spotlightOn, drawOn
    showTrayIcons := show
    if show {
        AddQuickTrayIcon(1, spotlightOn ? hIconSpotOn : hIconSpotOff, "강조 켜기/끄기")
        AddQuickTrayIcon(2, drawOn ? hIconDrawOn : hIconDrawOff, "드로잉 켜기/끄기")
    } else {
        RemoveQuickTrayIcon(1)
        RemoveQuickTrayIcon(2)
    }
}
if showTrayIcons
    SetTrayIconsVisible(true)
; GdiplusShutdown은 일부러 부르지 않는다 — 종료 시점에는 위젯/트레이 아이콘 등 GDI+로 만든
; 리소스를 쓰던 창들이 아직 완전히 정리되지 않은 상태라, 여기서 GDI+를 먼저 꺼버리면 그
; 창들이 뒤이어 정리되면서 이미 죽은 GDI+를 건드려 접근 위반(0xC0000005)으로 죽는 경우가
; 있었다(배포한 exe에서 종료 시 에러 팝업으로 보고됨). 프로세스가 끝나면 GDI+ 리소스는
; 어차피 OS가 정리해주므로, 굳이 직접 종료하지 않는 편이 더 안전하다.
OnExit((*) => (RemoveQuickTrayIcon(1), RemoveQuickTrayIcon(2)))

; 시작 시점의 위젯 버튼 상태(꺼짐/켜짐 중 어느 쪽을 보여줄지)는 생성 시 Hidden 옵션으로
; 이미 맞춰뒀고, 트레이 아이콘도 SetTrayIconsVisible(true)에서 이미 맞춰졌으므로 여기서
; 다시 UpdateWidgetState()를 부를 필요는 없다.

; 위젯을 제목 표시줄 없이도 마우스로 끌어서 옮길 수 있게 함
OnMessage(0x0201, OnWidgetDrag) ; WM_LBUTTONDOWN
; **위젯이 없는 순간이 실제로 있다.** 크기나 배경색을 바꾸면 위젯을 통째로 다시 만드는데,
; 그 사이(옛 창을 없앤 뒤 새 창을 만들기 전)에도 Windows는 메시지를 계속 보낸다. 슬라이더를
; 끌면서 클릭이 이어지는 상황이 딱 그래서, 그냥 두면 "Gui has no window" 오류 창이 떴다.
; 창이 없으면 조용히 넘어간다 — 그 찰나의 클릭 하나를 놓치는 것은 아무 문제가 없다.
OnWidgetDrag(wParam, lParam, msg, hwnd) {
    global widget, grip
    if (!IsSet(widget) || !widget || !IsSet(grip) || !grip)
        return
    try {
        if (hwnd = widget.Hwnd || hwnd = grip.Hwnd)
            PostMessage(0xA1, 2, , , widget.Hwnd) ; WM_NCLBUTTONDOWN, HTCAPTION
    }
}

BuildWidget() ; 위젯을 처음 만든다 (크기·배경색 설정에 맞춰 그려진다)
SetWidgetVisible(showWidget) ; 트레이 메뉴 체크 표시까지 시작 상태에 맞춰준다

; ================= 단축키 =================
; 이름 → 실제로 실행할 동작. 설정 창에서 조합을 바꿔도 동작은 그대로이므로 여기서 한 번만 묶는다.
HOTKEY_ACTIONS := Map("Spotlight", ToggleSpotlight, "Draw", ToggleDraw)

; 저장해둔 조합으로 전역 단축키를 켠다. 다른 프로그램이 이미 쓰는 조합이면 등록에 실패하는데,
; 시작하자마자 오류 창을 띄우면 수업 중에 곤란하므로 조용히 건너뛴다(위젯과 트레이는 그대로 동작).
for name, combo in hotkeyCombos
    RegisterHotkey(name, combo)

; ================= 개발용: 소스를 고치고 바로 확인하기 =================
; 소스(.ahk)로 실행 중일 때만 켜지는 단축키다. 파일을 고쳐 저장한 뒤 Ctrl+Alt+R을 누르면
; 프로그램이 그 자리에서 새 코드로 다시 시작한다 — 트레이에서 종료하고 다시 여는 과정이
; 필요 없고, exe로 다시 컴파일할 필요도 없다. 위쪽 "조절용 숫자"들을 시험할 때 쓰라고 둔 것.
; 컴파일된 exe에서는 등록하지 않는다 — 받아 쓰는 분의 Ctrl+Alt+R을 빼앗을 이유가 없다.
; (Reload는 OnExit을 거치므로 숨겨둔 커서도 정상적으로 복구되고, 새 인스턴스가 시작할 때
;  한 번 더 기본 커서로 되돌리므로 이중으로 안전하다)
if !A_IsCompiled {
    try Hotkey("^!r", (*) => Reload(), "On")
    A_TrayMenu.Insert("종료", "소스 다시 불러오기 (Ctrl+Alt+R)", (*) => Reload()) ; "종료" 바로 위에 둔다
}

; (Win+Shift+S 캡처 도구 드래그가 판서로 그려지는 문제는 DrawPoll에서 "드래그를 시작한 창이
; 판서 오버레이인지"를 보고 걸러내므로, 별도 핫키 감지가 필요 없다.)
; 아래 두 단축키는 판서 모드 중에만 켜짐 (ToggleDraw에서 On/Off 제어). 판서 모드 중엔 이 키가
; 다른 프로그램으로 전달되지 않으므로, 흔히 쓰는 키(Backspace 등)는 일부러 넣지 않았다.
Hotkey("Esc", ExitDrawMode, "Off")    ; 내용 지우고 드로잉 모드 종료
Hotkey("Delete", ClearDrawing, "Off") ; 드로잉 모드 유지한 채 내용만 지움
Hotkey("^z", UndoDrawing, "Off")      ; 직전 획/지우기/전체 지우기 한 단계 되돌리기
loop DRAW_COLORS.Length
    Hotkey(String(A_Index), MakeColorSetter(A_Index), "Off") ; 1~9 = 설정 창에서 정한 아홉 가지 색
; 0은 **설정 창 "드로잉" 탭의 기본 색**을 도로 집는 자리다. 숫자키로 잠깐 다른 색을 쓰다가
; 원래 쓰던 색으로 돌아올 방법이 없어서(드로잉을 껐다 켜야 했다) 0에 붙여뒀다. 기본 색을
; 바꾸면 0번도 따라 바뀐다 — 0은 색을 기억하는 게 아니라 그때의 기본 색을 보고 집는다.
Hotkey("0", MakeColorSetter(0), "Off")

; 선 굵기 조절. "+"는 키보드에서 Shift를 함께 눌러야 나오는 글자라, 굵게 하려고 Shift 없이
; 그 키를 눌러도(=) 되도록 둘 다 잡는다. 숫자 키패드가 있는 키보드도 함께 챙긴다.
THICKNESS_KEYS := [["=", 1], ["+=", 1], ["NumpadAdd", 1], ["-", -1], ["NumpadSub", -1]]
for pair in THICKNESS_KEYS
    Hotkey(pair[1], MakeThicknessSetter(pair[2]), "Off")

; 마우스 휠 = 지금 긋는 색의 투명도. 드로잉 중에만 잡으므로 평소 스크롤은 그대로다.
ALPHA_WHEEL_KEYS := [["WheelUp", 1], ["WheelDown", -1]]
for pair in ALPHA_WHEEL_KEYS
    Hotkey(pair[1], MakeAlphaSetter(pair[2]), "Off")

; 칠판 색 (Q/W/E/R). 도형 키(Z·X·C)와 마찬가지로 드로잉 모드일 때만 잡으므로, 모드를 끄면
; 평소대로 글자 키로 돌아간다.
for index, pair in BOARD_KEYS
    Hotkey(pair[1], MakeBoardSetter(index), "Off")

; 도형 키(Z/X/C)는 "누르고 있는 동안"만 뜻이 있어서 눌렀을 때 할 일이 따로 없다. 그런데도
; 핫키로 잡아두는 이유는 두 가지다 — (1) 키를 삼켜서 뒤에 있는 프로그램에 글자가 입력되지
; 않게 하고, (2) 누를 때와 뗄 때를 받아 지금 눌려 있는지를 직접 기록하기 위해서다.
; Z를 잡아도 Ctrl+Z(실행 취소)는 그대로 동작한다 — 수식키 없는 핫키는 Ctrl이 함께 눌리면
; 발동하지 않고, 더 구체적인 ^z 쪽이 잡는다. (실제로 눌러 확인함)
for pair in SHAPE_HOLD_KEYS {
    shapeKeyHeld[pair[1]] := false
    for prefix in HOLD_KEY_PREFIXES {
        Hotkey(prefix pair[1], MakeShapeKeyTracker(pair[1], true), "Off")
        Hotkey(prefix pair[1] " up", MakeShapeKeyTracker(pair[1], false), "Off")
    }
}
; 특수 펜 키(A/S)는 한 번 누르면 고른 것이 유지되므로 누를 때만 받는다
for pair in PEN_KIND_KEYS
    for prefix in HOLD_KEY_PREFIXES
        Hotkey(prefix pair[1], MakePenKindSetter(pair[2]), "Off")

; 위 키들은 드로잉 모드일 때만 켠다. 그래야 평소에 숫자나 Ctrl+Z를 다른 프로그램에서
; 그대로 쓸 수 있다.
SetDrawModeHotkeys(state) {
    global DRAW_COLORS, SHAPE_HOLD_KEYS, shapeKeyHeld, THICKNESS_KEYS, BOARD_KEYS, ALPHA_WHEEL_KEYS
    global PEN_KIND_KEYS, HOLD_KEY_PREFIXES
    for pair in PEN_KIND_KEYS
        for prefix in HOLD_KEY_PREFIXES
            Hotkey(prefix pair[1], state)
    Hotkey("Esc", state)
    Hotkey("Delete", state)
    Hotkey("^z", state)
    loop DRAW_COLORS.Length
        Hotkey(String(A_Index), state)
    Hotkey("0", state)
    for pair in THICKNESS_KEYS
        Hotkey(pair[1], state)
    for pair in ALPHA_WHEEL_KEYS
        Hotkey(pair[1], state)
    for pair in BOARD_KEYS
        Hotkey(pair[1], state)
    for pair in SHAPE_HOLD_KEYS {
        for prefix in HOLD_KEY_PREFIXES {
            Hotkey(prefix pair[1], state)
            Hotkey(prefix pair[1] " up", state)
        }
        ; 도형 키를 누른 채로 드로잉이 꺼지면(Esc 등) 뗀 것을 못 보고 지나가 "계속 눌림"으로
        ; 남는다. 켜고 끌 때마다 초기화해서 그런 유령 상태가 생기지 않게 한다.
        shapeKeyHeld[pair[1]] := false
    }
}

; ================= 전역 단축키 등록/검증 =================
; 글자 키 하나만 단축키로 잡으면 글을 쓰는 동안 그 글자를 칠 때마다 강조·드로잉이 켜지고 꺼진다
; (키는 앞 프로그램에도 넘어가므로 글자 자체는 쳐진다 — RegisterHotkey 참고). Shift만 더해도
; 마찬가지(대문자를 칠 때마다)라, Ctrl이나 Alt를 반드시 포함하게 한다. 기능키(F1~F24)는 글을 쓸 때
; 쓰지 않으니 단독으로도 허용한다.
IsSafeHotkey(combo) {
    if (combo = "")
        return false
    if (InStr(combo, "^") || InStr(combo, "!"))
        return true
    return RegExMatch(combo, "i)^\+?F([1-9]|1[0-9]|2[0-4])$") > 0
}

; combo를 name 동작의 전역 단축키로 등록한다. 성공하면 true.
; 이미 등록돼 있던 조합은 먼저 해제해서, 옛 조합이 계속 살아있는 일이 없게 한다.
;
; **키를 삼키지 않고 앞에 있는 프로그램에도 그대로 넘긴다(~).** 예전에는 가로채기만 해서,
; 한글에서 F8(맞춤법 검사)이 아예 안 먹었다(2026-09-28 제보). 같은 키를 쓰는 프로그램은 셀 수 없이
; 많아 목록으로 골라낼 수 없으므로, 어디서든 넘겨주고 우리도 함께 동작하게 했다(사용자 결정) —
; 한글에서 F8을 누르면 맞춤법 검사와 강조 켜기가 함께 일어난다. 강조는 다시 누르면 꺼지니 큰 문제가 아니다.
; 설정 창과 settings.ini에는 ~ 없이 적고, 실제로 등록할 때만 붙인다.
RegisterHotkey(name, combo) {
    global HOTKEY_ACTIONS, hotkeyRegistered
    if hotkeyRegistered.Has(name) {
        try Hotkey(hotkeyRegistered[name], , "Off")
        hotkeyRegistered.Delete(name)
    }
    if (combo = "")
        return false
    try {
        Hotkey("~" combo, HOTKEY_ACTIONS[name], "On")
        hotkeyRegistered[name] := "~" combo
        return true
    }
    return false ; 키 이름을 알아볼 수 없는 경우 등
}

; 설정 창의 단축키 칸에서 값이 바뀌었을 때 불린다. 문제가 있으면 원래 조합으로 되돌리고
; 이유를 알려준다 — 조용히 무시하면 왜 안 바뀌는지 알 수 없다.
ChangeHotkey(name, combo, ctrl) {
    global hotkeyCombos, hotkeyApplying, HOTKEY_LABELS
    if hotkeyApplying
        return
    ; 조합키만 누르고 있는 동안에는 아직 키가 안 정해져 빈 값이 온다 — 입력 중이므로 그냥 둔다
    if (combo = "" || combo = hotkeyCombos[name])
        return

    old := hotkeyCombos[name]
    reason := ""
    if !IsSafeHotkey(combo)
        reason := "Ctrl이나 Alt를 함께 누르는 조합으로 정해주세요.`n`n글자 키 하나만 지정하면 글을 쓰는 동안 그 글자를 칠 때마다 기능이 켜지고 꺼집니다. (F1~F12 같은 기능키는 단독으로도 됩니다)"
    else {
        for otherName, otherCombo in hotkeyCombos {
            if (otherName != name && otherCombo = combo) {
                reason := "이미 " HOTKEY_LABELS[otherName] " 기능에 쓰고 있는 조합입니다.`n다른 조합으로 정해주세요."
                break
            }
        }
    }
    if (reason = "" && !RegisterHotkey(name, combo)) {
        reason := "이 조합은 단축키로 등록할 수 없습니다.`n다른 조합으로 정해주세요."
        RegisterHotkey(name, old) ; 원래 단축키를 되살려서 아무것도 안 먹는 상태를 피한다
    }

    hotkeyApplying := true ; 아래에서 Value를 바꿀 때 Change가 다시 불려도 무시되게 한다
    if (reason != "") {
        ctrl.Value := old
        MsgBox(reason, "Focus & Draw - 단축키", "Icon!")
    } else {
        hotkeyCombos[name] := combo
        ctrl.Value := combo
    }
    hotkeyApplying := false
}

