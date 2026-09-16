#Requires AutoHotkey v2.0
#SingleInstance Force

; ================= 컴파일(Ahk2Exe) 설정 =================
; 아래 줄들은 평범한 주석이라 .ahk로 그냥 실행할 때는 아무 영향이 없고, Ahk2Exe로 exe를
; 만들 때만 읽힌다. focus-draw.ico는 icon.png를 16~256px 여러 크기로 담아 변환한 파일이다
; (작업표시줄·바탕화면·파일 탐색기가 상황에 따라 다른 크기를 골라 쓰기 때문에 여러 크기가 필요).
; 컴파일된 exe는 이 아이콘을 파일 아이콘이자 트레이 아이콘으로 함께 사용한다.
;@Ahk2Exe-SetMainIcon focus-draw.ico
;@Ahk2Exe-SetName Focus & Draw
;@Ahk2Exe-SetDescription Focus & Draw - 마우스 강조 / 화면 판서
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

A_IconTip := "Focus & Draw v" APP_VERSION " - 마우스 강조 / 화면 판서"

; 컴파일된 exe는 위 SetMainIcon으로 넣은 아이콘을 트레이 아이콘으로도 그대로 쓰지만,
; .ahk 소스로 직접 실행할 때는 AutoHotkey 기본 아이콘(초록색 H)이 뜬다. 소스로 실행할 때도
; 같은 그림이 보이도록 같은 폴더의 ico 파일을 지정한다. (exe는 아이콘을 이미 품고 있어서
; 건드릴 필요가 없고, ico 파일을 exe에 또 넣으면 같은 그림이 두 번 들어가 크기만 커진다)
if !A_IsCompiled && FileExist(A_ScriptDir "\focus-draw.ico")
    TraySetIcon(A_ScriptDir "\focus-draw.ico")

SETTINGS_PATH := A_ScriptDir "\settings.ini"

; 컴파일된 exe에도 아이콘 파일이 그대로 들어가도록 FileInstall로 함께 담고, 실행 시 임시 폴더로 꺼내 쓴다.
; (위젯/트레이 아이콘 둘 다 이 경로를 쓰므로 다른 UI보다 먼저 준비해둔다)
FileInstall("icon_spotlight.png", A_Temp "\tt_icon_spotlight.png", true)
FileInstall("icon_draw.png", A_Temp "\tt_icon_draw.png", true)
FileInstall("icon_spotlight_dark.png", A_Temp "\tt_icon_spotlight_dark.png", true)
FileInstall("icon_draw_dark.png", A_Temp "\tt_icon_draw_dark.png", true)
FileInstall("Settings.png", A_Temp "\tt_icon_settings.png", true)
ICON_SPOT_PATH := A_Temp "\tt_icon_spotlight.png"
ICON_DRAW_PATH := A_Temp "\tt_icon_draw.png"
ICON_SPOT_DARK_PATH := A_Temp "\tt_icon_spotlight_dark.png"
ICON_DRAW_DARK_PATH := A_Temp "\tt_icon_draw_dark.png"
ICON_SETTINGS_PATH := A_Temp "\tt_icon_settings.png"

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
HOTKEY_DEFAULTS := Map("Spotlight", "^!h", "Draw", "^!d")
HOTKEY_LABELS := Map("Spotlight", "강조", "Draw", "드로잉")
hotkeyCombos := Map()     ; 지금 설정된 조합 (settings.ini에서 불러옴)
hotkeyRegistered := Map() ; 실제로 등록에 성공해 살아있는 조합 (해제할 때 필요)
hotkeyApplying := false   ; 값을 되돌리느라 Change가 다시 불려 무한히 반복되는 것을 막는 빗장

; ================= 설정값 (settings.ini에서 불러옴, 없으면 기본값) =================
; spotOpacity는 0~100(%)로 저장/표시하고, 실제 WinSetTransparent에 쓸 때만 0~255로 환산한다.
; clickSpeed는 "클수록 빠름"(1~30)으로 저장/표시하고, 타이머 간격(ms)으로 쓸 때만 뒤집어 계산한다.
LoadSettings() {
    global SETTINGS_PATH, SpotSize, spotOpacity, SpotThickness, DrawThickness, DrawOpacity, penColor
    global clickEffectEnabled, clickSpeed, clickOpacity, CLICK_ANIM_INTERVAL, showWidget, showTrayIcons, hideCursorOnHighlight
    global HOTKEY_DEFAULTS, hotkeyCombos
    SpotSize := Max(30, Min(200, IniRead(SETTINGS_PATH, "Highlight", "Size", 130)))
    ; 예전 버전은 투명도를 0~255로 저장했었다. 그 값이 남아있어도 안전하게 0~100으로 잘려 들어가도록 한다.
    spotOpacity := Max(0, Min(100, IniRead(SETTINGS_PATH, "Highlight", "Opacity", 30)))
    SpotThickness := Max(2, Min(12, IniRead(SETTINGS_PATH, "Highlight", "RingThickness", 7)))
    clickEffectEnabled := IniRead(SETTINGS_PATH, "Highlight", "ClickEffect", 1) = 1
    clickSpeed := Max(1, Min(30, IniRead(SETTINGS_PATH, "Highlight", "ClickSpeed", 24)))
    clickOpacity := Max(0, Min(100, IniRead(SETTINGS_PATH, "Highlight", "ClickOpacity", 50)))
    CLICK_ANIM_INTERVAL := 41 - clickSpeed ; 1(40ms, 예전보다 더 느린 옵션)~30(11ms, 예전 "20" 정도의 체감 속도가 새 최대)
    hideCursorOnHighlight := IniRead(SETTINGS_PATH, "Highlight", "HideCursor", 1) = 1
    DrawThickness := Max(1, Min(12, IniRead(SETTINGS_PATH, "Draw", "Thickness", 6)))
    DrawOpacity := Max(0, Min(100, IniRead(SETTINGS_PATH, "Draw", "Opacity", 70)))
    penColor := Integer("0x" IniRead(SETTINGS_PATH, "Common", "Color", "FF0000"))
    showWidget := IniRead(SETTINGS_PATH, "Common", "ShowWidget", 1) = 1
    showTrayIcons := IniRead(SETTINGS_PATH, "Common", "ShowTrayIcons", 0) = 1
    ; 저장된 단축키가 이상하면(사람이 ini를 잘못 고쳤다거나) 기본값으로 돌려서, 단축키가
    ; 하나도 안 먹는 상태로 시작하는 일이 없게 한다.
    for name, def in HOTKEY_DEFAULTS {
        combo := IniRead(SETTINGS_PATH, "Hotkeys", name, def)
        hotkeyCombos[name] := IsSafeHotkey(combo) ? combo : def
    }
}

SaveSettings() {
    global SETTINGS_PATH, SpotSize, spotOpacity, SpotThickness, DrawThickness, DrawOpacity, penColor, clickEffectEnabled, clickSpeed, clickOpacity, showWidget, showTrayIcons, hideCursorOnHighlight, hotkeyCombos
    IniWrite(SpotSize, SETTINGS_PATH, "Highlight", "Size")
    IniWrite(spotOpacity, SETTINGS_PATH, "Highlight", "Opacity")
    IniWrite(SpotThickness, SETTINGS_PATH, "Highlight", "RingThickness")
    IniWrite(clickEffectEnabled ? 1 : 0, SETTINGS_PATH, "Highlight", "ClickEffect")
    IniWrite(clickSpeed, SETTINGS_PATH, "Highlight", "ClickSpeed")
    IniWrite(clickOpacity, SETTINGS_PATH, "Highlight", "ClickOpacity")
    IniWrite(hideCursorOnHighlight ? 1 : 0, SETTINGS_PATH, "Highlight", "HideCursor")
    IniWrite(DrawThickness, SETTINGS_PATH, "Draw", "Thickness")
    IniWrite(DrawOpacity, SETTINGS_PATH, "Draw", "Opacity")
    IniWrite(HexColor(penColor), SETTINGS_PATH, "Common", "Color")
    IniWrite(showWidget ? 1 : 0, SETTINGS_PATH, "Common", "ShowWidget")
    IniWrite(showTrayIcons ? 1 : 0, SETTINGS_PATH, "Common", "ShowTrayIcons")
    for name, combo in hotkeyCombos
        IniWrite(combo, SETTINGS_PATH, "Hotkeys", name)
    ; 예전 버전에 있던 전역 "지우기" 단축키의 잔재를 치운다. 안 읽히는 값이라 그냥 둬도
    ; 동작에는 문제가 없지만, 설정 파일을 열어본 사람이 헷갈리지 않도록 지운다.
    try IniDelete(SETTINGS_PATH, "Hotkeys", "Clear")
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
dragOnOtherWindow := false ; 현재 드래그가 판서 오버레이가 아닌 다른 창(위젯/캡처 도구 등) 위에서 시작돼 판서를 건너뛰어야 하는지
erasing := false ; 오른쪽 버튼으로 지우는 중인지
lastShapeBox := [] ; 직전 미리보기 프레임이 그린 범위 (그 자리만 되돌리고 다시 합성하면 된다)

; 드로잉 중 숫자키 1~7로 바로 바꿀 수 있는 색 (무지개 순서: 빨주노초파남보).
; 노랑과 초록은 표준 무지개값(FFFF00, 00FF00)을 그대로 쓰면 흰 배경에서 잘 안 보이고
; 판서 투명도까지 겹치면 더 흐려져서, 색감은 유지하되 조금 진한 값으로 골랐다.
DRAW_COLORS := [0xFF0000, 0xFF7F00, 0xFFC800, 0x00A000, 0x0000FF, 0x4B0082, 0x9400D3]
DRAW_COLOR_NAMES := ["빨강", "주황", "노랑", "초록", "파랑", "남색", "보라"]
; 실제로 선을 그릴 때 쓰는 색. 설정에 저장된 penColor를 기본으로 하되 숫자키로 잠깐 바꿀 수
; 있고, 드로잉 모드를 켜고 끌 때마다 설정값으로 되돌아간다. (penColor를 직접 바꾸면 강조
; 하이라이트와 클릭 효과 색까지 같이 변하고, 저장까지 눌리면 임시 색이 굳어버린다)
activeDrawColor := penColor

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

; 도형(직선/사각형/원) 미리보기를 그리기 전에 현재 그림을 스냅샷으로 저장해뒀다가,
; 드래그 중 매 프레임마다 스냅샷으로 되돌린 뒤 새 도형을 다시 그려서 "고무줄 미리보기" 효과를 낸다.
; 실행 취소 한 단계가 화면 전체 크기(가로x세로x4바이트)만큼 메모리를 쓴다. 모니터 하나면
; 한 단계에 8MB 남짓이지만 두 대를 늘어놓으면 두 배가 되므로, 넓을수록 단계 수를 줄여
; 전체 사용량이 50MB 선을 넘지 않게 맞춘다.
UNDO_LIMIT := Max(2, Min(8, 50000000 // (vw * vh * 4)))

; 되돌릴 수 있도록 지금 화면을 기록해둔다. 획 하나를 긋기 직전, 지우개를 대기 직전,
; 전체를 지우기 직전에 부른다.
PushUndo() {
    global ppvBits, undoStack, UNDO_LIMIT, vw, vh
    buf := Buffer(vw * vh * 4)
    DllCall("RtlCopyMemory", "ptr", buf, "ptr", ppvBits, "uptr", vw * vh * 4)
    undoStack.Push(buf)
    while (undoStack.Length > UNDO_LIMIT)
        undoStack.RemoveAt(1) ; 가장 오래된 기록부터 버린다
}

UndoDrawing(*) {
    global ppvBits, undoStack, vw, vh
    if (undoStack.Length = 0)
        return
    buf := undoStack.Pop()
    DllCall("RtlCopyMemory", "ptr", ppvBits, "ptr", buf, "uptr", vw * vh * 4)
    UpdateOverlay()
}

snapshotBuf := Buffer(vw * vh * 4, 0)
SaveSnapshot() {
    global ppvBits, snapshotBuf, vw, vh
    DllCall("RtlCopyMemory", "ptr", snapshotBuf, "ptr", ppvBits, "uptr", vw * vh * 4)
}
RestoreSnapshot() {
    global ppvBits, snapshotBuf, vw, vh
    DllCall("RtlCopyMemory", "ptr", ppvBits, "ptr", snapshotBuf, "uptr", vw * vh * 4)
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
drawGui := Gui("+AlwaysOnTop -Caption +ToolWindow +E0x80000", "FocusDraw-Draw") ; E0x80000 = WS_EX_LAYERED
drawGui.Show("x" vx " y" vy " w" vw " h" vh " Hide")

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
NumPut("UChar", Round(DrawOpacity * 255 / 100), ulwBlend, 2) ; SourceConstantAlpha — 판서 전체 불투명도
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

; 판서 전체의 불투명도를 바꾼다. UpdateLayeredWindow의 SourceConstantAlpha는 이미 그려둔
; 그림 전체에 곱해지는 값이라, 픽셀을 다시 그리지 않고 이 값만 바꿔도 화면에 바로 반영된다.
UpdateDrawOpacity() {
    global ulwBlend, DrawOpacity
    NumPut("UChar", Round(DrawOpacity * 255 / 100), ulwBlend, 2)
    UpdateOverlay()
}

; GDI로 그린 픽셀은 알파 값이 채워지지 않으므로, 그린 영역만 알파를 255로 채워준다.
; 실제로 훑은 사각형 범위를 돌려줘서, 호출한 쪽이 그 부분만 화면에 다시 합성하면 되게 한다.
PatchAlpha(x1, y1, x2, y2) {
    global ppvBits, vw, vh, DrawThickness
    pad := DrawThickness + 2
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
    global vw, vh, DrawThickness
    if !thickness
        thickness := DrawThickness
    pad := thickness // 2 + 6 ; 펜 굵기의 절반 + 부드럽게 처리한 가장자리만큼 여유
    return [Max(0, Min(x1, x2) - pad), Max(0, Min(y1, y2) - pad)
        , Min(vw, Max(x1, x2) + pad + 1), Min(vh, Max(y1, y2) + pad + 1)]
}

; 도형 테두리를 따라가는 점들. 원은 크기에 맞춰 잘게 쪼개야 토막마다 훑는 네모가 작게 유지된다.
ShapeOutlinePoints(mode, x1, y1, x2, y2) {
    if (mode = "line")
        return [[x1, y1], [x2, y2]]
    lx := Min(x1, x2), rx := Max(x1, x2), ty := Min(y1, y2), by := Max(y1, y2)
    if (mode = "rect")
        return [[lx, ty], [rx, ty], [rx, by], [lx, by], [lx, ty]]
    cx := (lx + rx) / 2, cy := (ty + by) / 2
    ax := (rx - lx) / 2, ay := (by - ty) / 2
    steps := Max(16, Min(160, Round((ax + ay) / 6)))
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

; ================= 지우개 (오른쪽 버튼 드래그) =================
; 굵기는 펜보다 넉넉하게 — 지우개는 대충 문질러도 지워져야 쓸 만하다.
EraserThickness() {
    global DrawThickness
    return Max(24, DrawThickness * 4)
}

; 지나간 자리를 배경과 똑같은 값(1,1,1)으로 덧칠한 뒤, 그 픽셀들의 알파를 1로 낮춰 도로
; 투명하게 만든다. GDI는 알파를 건드리지 않으므로 알파는 직접 손봐야 한다.
EraseSegment(x1, y1, x2, y2) {
    global memDC, vx, vy, pShapeGraphics
    thickness := EraserThickness()
    lx1 := x1 - vx, ly1 := y1 - vy, lx2 := x2 - vx, ly2 := y2 - vy
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
GetFreehandPen() {
    global freehandPen, freehandPenColor, freehandPenWidth, activeDrawColor, DrawThickness
    if (freehandPen && freehandPenColor = activeDrawColor && freehandPenWidth = DrawThickness)
        return freehandPen
    if freehandPen
        DllCall("gdiplus\GdipDeletePen", "ptr", freehandPen)
    freehandPen := 0
    DllCall("gdiplus\GdipCreatePen1", "uint", 0xFF000000 | activeDrawColor, "float", DrawThickness, "int", 2, "ptr*", &freehandPen)
    if freehandPen {
        ; 자유선은 10ms마다 짧은 선을 이어 붙여 만드는 것이라, 선 끝이 평평하면 이음매마다
        ; 모난 자국이 남아 획이 끊겨 보인다. 끝과 이음매를 둥글게 해야 한 획처럼 이어진다.
        ; (GDI의 굵은 펜은 원래 끝이 둥글어서 이 문제가 없었다)
        DllCall("gdiplus\GdipSetPenStartCap", "ptr", freehandPen, "int", 2) ; LineCapRound
        DllCall("gdiplus\GdipSetPenEndCap", "ptr", freehandPen, "int", 2)
        DllCall("gdiplus\GdipSetPenLineJoin", "ptr", freehandPen, "int", 2) ; LineJoinRound
    }
    freehandPenColor := activeDrawColor
    freehandPenWidth := DrawThickness
    return freehandPen
}

DrawSegment(x1, y1, x2, y2) {
    global memDC, vx, vy, DrawThickness, activeDrawColor, pShapeGraphics
    lx1 := x1 - vx, ly1 := y1 - vy, lx2 := x2 - vx, ly2 := y2 - vy
    if pShapeGraphics {
        ; 도형과 같은 방식. GDI+가 투명도까지 채워주므로 그린 자리를 훑을 필요가 없고,
        ; 테두리도 도형과 똑같이 매끄럽게 나온다.
        DllCall("gdi32\GdiFlush") ; 지우개는 아직 GDI를 쓰므로 밀린 작업을 먼저 반영시킨다
        pPen := GetFreehandPen()
        if pPen
            DllCall("gdiplus\GdipDrawLine", "ptr", pShapeGraphics, "ptr", pPen, "float", lx1, "float", ly1, "float", lx2, "float", ly2)
        box := PenDirtyBox(lx1, ly1, lx2, ly2)
    } else {
        ; GDI+ 준비에 실패한 경우를 위한 대비책 (예전 방식: GDI로 긋고 투명도는 직접 채우기)
        pen := DllCall("CreatePen", "int", 0, "int", DrawThickness, "uint", ToBGR(activeDrawColor), "ptr")
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
    global memDC, vx, vy, DrawThickness, activeDrawColor, lastShapeBox, pShapeGraphics
    ; 직전 프레임이 그린 자리만 되돌리면 된다. 첫 프레임은 되돌릴 것이 없다(스냅샷을 방금 떴다).
    if (lastShapeBox.Length = 4)
        RestoreSnapshotBox(lastShapeBox)
    lx1 := x1 - vx, ly1 := y1 - vy, lx2 := x2 - vx, ly2 := y2 - vy
    bx := Min(lx1, lx2), by := Min(ly1, ly2)
    bw := Abs(lx2 - lx1), bh := Abs(ly2 - ly1)

    if pShapeGraphics {
        ; GDI가 아직 버퍼에 반영하지 않은 작업이 남아 있을 수 있으므로 먼저 밀어 넣는다
        DllCall("gdi32\GdiFlush")
        pPen := 0
        ; GDI+ 색은 0xAARRGGBB — GDI처럼 BGR로 뒤집지 않는다
        DllCall("gdiplus\GdipCreatePen1", "uint", 0xFF000000 | activeDrawColor, "float", DrawThickness, "int", 2, "ptr*", &pPen)
        if mode = "line"
            DllCall("gdiplus\GdipDrawLine", "ptr", pShapeGraphics, "ptr", pPen, "float", lx1, "float", ly1, "float", lx2, "float", ly2)
        else if mode = "rect"
            DllCall("gdiplus\GdipDrawRectangle", "ptr", pShapeGraphics, "ptr", pPen, "float", bx, "float", by, "float", bw, "float", bh)
        else if mode = "ellipse"
            DllCall("gdiplus\GdipDrawEllipse", "ptr", pShapeGraphics, "ptr", pPen, "float", bx, "float", by, "float", bw, "float", bh)
        DllCall("gdiplus\GdipDeletePen", "ptr", pPen)
        box := PenDirtyBox(lx1, ly1, lx2, ly2)
    } else {
        ; GDI+ 준비에 실패한 경우를 위한 대비책 — 예전 방식(GDI로 그리고 알파는 직접 채우기).
        ; 테두리를 따라가며 훑어서, 도형을 감싸는 네모 전체를 훑던 때보다는 훨씬 가볍다.
        pen := DllCall("CreatePen", "int", 0, "int", DrawThickness, "uint", ToBGR(activeDrawColor), "ptr")
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

DrawPoll() {
    global drawOn, drawing, erasing, lastX, lastY, dragStartX, dragStartY, dragShapeMode, drawGui
    global dragOnOtherWindow, lastShapeBox
    if !drawOn
        return

    leftDown := GetKeyState("LButton", "P")
    rightDown := GetKeyState("RButton", "P")
    if (!leftDown && !rightDown) {
        drawing := false
        erasing := false
        return
    }
    MouseGetPos(&mx, &my, &winUnder)

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
        lastX := mx
        lastY := my
        dragStartX := mx
        dragStartY := my
            ; 마우스를 누른 순간 커서 아래에 있는 창이 판서 오버레이가 아니면, 그 위에 다른 창이
            ; 떠 있다는 뜻이다 — 위젯이나 Win+Shift+S 캡처 도구 오버레이처럼 위로 올라온 창
            ; 등. 그 창이 클릭을 받는 드래그이므로 판서로 그리지 않는다. 드래그를 시작한 시점에
            ; 한 번만 판단하고 마우스를 뗄 때까지 유지하므로, 설정 창 슬라이더를 끌다 커서가 창
            ; 밖으로 벗어나도 선이 그려지지 않는다. (예전엔 Win+Shift+S 뒤 드래그 "횟수"를
            ; 세어 건너뛰었는데, 캡처 도구가 툴바 클릭을 요구하는지가 Windows 버전마다 달라
            ; 첫 판서 한 획을 삼키거나 캡처 드래그가 그려지는 일이 있었다.)
        dragOnOtherWindow := winUnder != drawGui.Hwnd
        ; 획을 긋기 전 상태를 기록해둬야 Ctrl+Z로 이 한 획만 되돌릴 수 있다
        if !dragOnOtherWindow
            PushUndo()
        ; 드래그를 시작하는 순간 눌려있던 키로 도형 종류를 정한다 (ZoomIt과 동일한 조합)
        dragShapeMode := GetKeyState("Ctrl", "P") && GetKeyState("Shift", "P") ? "ellipse"
            : GetKeyState("Ctrl", "P") ? "rect"
            : GetKeyState("Shift", "P") ? "line"
            : ""
        if (dragShapeMode != "" && !dragOnOtherWindow) {
            SaveSnapshot()
            lastShapeBox := [] ; 새 도형이므로 지울 이전 프레임이 없다
        }
    } else if dragOnOtherWindow {
        ; 다른 창 위에서 시작된 드래그 — 아무것도 그리지 않는다
    } else if dragShapeMode != "" {
        DrawShapePreview(dragShapeMode, dragStartX, dragStartY, mx, my)
    } else {
        DrawSegment(lastX, lastY, mx, my)
        lastX := mx
        lastY := my
    }
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
    global spotGui, spotCanvas, SpotSize, spotOpacity, penColor
    DestroyAlphaCanvas(spotCanvas)
    spotCanvas := CreateAlphaCanvas(SpotSize, SpotSize)
    if !spotCanvas.graphics
        return
    DllCall("gdiplus\GdipGraphicsClear", "ptr", spotCanvas.graphics, "uint", 0x00000000)
    ; 투명도를 픽셀 자체에 담는다. 예전처럼 창 전체 투명도를 따로 지정하는 방식은 픽셀 단위
    ; 투명도와 같이 쓸 수 없다.
    alpha := Max(0, Min(255, Round(spotOpacity * 255 / 100)))
    brush := 0
    DllCall("gdiplus\GdipCreateSolidFill", "uint", (alpha << 24) | penColor, "ptr*", &brush)
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
CLICK_ANIM_FRAMES := 30 ; CLICK_ANIM_INTERVAL(빠르기)은 settings.ini에서 불러온 값을 그대로 씀

clickGui := Gui("+AlwaysOnTop -Caption +ToolWindow +E0x80020", "FocusDraw-Click") ; 0x80000 = 레이어드, 0x20 = 클릭 통과
clickGui.Show("w" SpotSize " h" SpotSize " Hide")
clickCanvas := ""

SetupClickCanvas() {
    global clickCanvas, SpotSize
    DestroyAlphaCanvas(clickCanvas)
    clickCanvas := CreateAlphaCanvas(SpotSize, SpotSize)
}
SetupClickCanvas()

clickAnimFrame := 0

ClickAnimStep() {
    global clickAnimFrame, CLICK_ANIM_FRAMES, clickGui, clickCanvas, SpotSize, SpotThickness, penColor, clickOpacity
    if clickAnimFrame >= CLICK_ANIM_FRAMES {
        SetTimer(ClickAnimStep, 0)
        clickGui.Hide()
        return
    }
    MouseGetPos(&mx, &my)
    if clickCanvas.graphics {
        DllCall("gdiplus\GdipGraphicsClear", "ptr", clickCanvas.graphics, "uint", 0x00000000)

        ; 등속 대신 감속(ease-out) 곡선을 써서, 처음엔 빠르게 줄어들다가 중심 근처에서
        ; 서서히 멈추는 것처럼 보이게 한다 — 등속보다 훨씬 자연스럽게 느껴진다.
        t := clickAnimFrame / CLICK_ANIM_FRAMES
        eased := 1 - (1 - t) ** 3
        radius := (SpotSize / 2 - SpotThickness / 2 - 1) * (1 - eased)
        cx := SpotSize / 2, cy := SpotSize / 2
        pen := 0
        DllCall("gdiplus\GdipCreatePen1", "uint", 0xFF000000 | penColor, "float", SpotThickness, "int", 2, "ptr*", &pen)
        if pen {
            DllCall("gdiplus\GdipDrawEllipse", "ptr", clickCanvas.graphics, "ptr", pen
                , "float", cx - radius, "float", cy - radius, "float", radius * 2, "float", radius * 2)
            DllCall("gdiplus\GdipDeletePen", "ptr", pen)
        }
        DllCall("gdiplus\GdipFlush", "ptr", clickCanvas.graphics, "int", 0)

        ; 위치와 그림을 한 번에 올린다. 예전에는 화면에 지우고 다시 그리는 찰나가 보여서
        ; 테두리가 두 개로 보이는 깜빡임이 있었는데, 이 방식은 그 틈이 아예 없다.
        PushCanvasToWindow(clickGui.Hwnd, clickCanvas, mx - SpotSize // 2, my - SpotSize // 2
            , Max(0, Min(255, Round(clickOpacity * 255 / 100))))
    }
    clickAnimFrame += 1
}

StartClickAnimation(*) {
    global spotlightOn, drawOn, clickEffectEnabled, clickAnimFrame, clickGui, CLICK_ANIM_INTERVAL
    ; 판서 중에는 강조 하이라이트 자체를 감춰두므로, 클릭 링 효과도 같이 쉰다
    if !spotlightOn || drawOn || !clickEffectEnabled
        return
    clickAnimFrame := 0
    clickGui.Show("NA")
    SetTimer(ClickAnimStep, CLICK_ANIM_INTERVAL)
}
~LButton::StartClickAnimation()

; ================= 강조 중 마우스 커서를 작은 십자선으로 바꾸기 =================
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

HideSystemCursor() {
    global CURSOR_IDS, systemCursorHidden
    for id in CURSOR_IDS
        DllCall("SetSystemCursor", "ptr", CreateCrosshairCursor(), "uint", id) ; 넘긴 커서는 시스템이 소유/해제함
    systemCursorHidden := true
}

RestoreSystemCursor(*) {
    global systemCursorHidden
    if !systemCursorHidden
        return
    DllCall("SystemParametersInfo", "uint", 0x57, "uint", 0, "ptr", 0, "uint", 0) ; SPI_SETCURSORS
    systemCursorHidden := false
}
OnExit(RestoreSystemCursor) ; 커서가 숨겨진 채로 프로그램이 종료되는 일이 없도록 보험

; 커서를 십자선으로 바꿔야 하는 이유가 두 가지(강조 중 커서 숨기기 설정 + 판서 모드)라서,
; 매번 따로 켜고 끄는 대신 "지금 상태 종합해서 켜져 있어야 하나?"를 한곳에서 판단한다.
UpdateCursorHiddenState() {
    global spotlightOn, hideCursorOnHighlight, drawOn, systemCursorHidden
    shouldHide := (spotlightOn && hideCursorOnHighlight) || drawOn
    if shouldHide && !systemCursorHidden
        HideSystemCursor()
    else if !shouldHide && systemCursorHidden
        RestoreSystemCursor()
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
    global drawOn, drawGui, widget, settingsGui, settingsHiddenByDraw, activeDrawColor, penColor, erasing
    drawOn := !drawOn
    ; 숫자키로 잠깐 바꿔둔 색은 여기서 초기화한다. 드로잉을 켤 때마다 설정에 저장된 색으로
    ; 시작하고, Esc 등으로 끄면 그 자리에서 되돌아간다.
    activeDrawColor := penColor
    erasing := false
    if drawOn {
        drawGui.Show("NA")
        ; 오버레이가 화면 전체를 덮지만, 판서를 끌 수단은 남아 있어야 하므로 위젯만 위로 올린다
        WinSetAlwaysOnTop(true, widget)
        ; 오버레이는 그린 자국 말고는 거의 투명해서, 설정 창이 열려 있으면 눈에는 보이는데
        ; 클릭은 오버레이가 가로채는 이상한 상태가 된다. 아예 잠시 감춰서 헷갈리지 않게 한다.
        settingsHiddenByDraw := false
        if IsSet(settingsGui) && WinExist("ahk_id " settingsGui.Hwnd) {
            settingsGui.Hide()
            settingsHiddenByDraw := true
        }
        SetTimer(DrawPoll, 10)
        SetDrawModeHotkeys("On")
    } else {
        SetTimer(DrawPoll, 0)
        SetDrawModeHotkeys("Off")
        drawGui.Hide()
        ; 판서를 켜느라 감췄던 설정 창이라면 하던 작업을 이어갈 수 있게 다시 띄운다
        if settingsHiddenByDraw {
            settingsHiddenByDraw := false
            if IsSet(settingsGui)
                try settingsGui.Show()
        }
    }
    UpdateSpotlightVisibility()
    UpdateCursorHiddenState() ; 판서 모드에서도 십자선 커서를 쓴다 (그림 도구다운 커서)
    UpdateWidgetState()
}

ClearDrawing(*) {
    PushUndo() ; 실수로 다 지웠을 때 Ctrl+Z로 되살릴 수 있게 한다
    ClearBackBuffer()
    UpdateOverlay()
}

; 드로잉 중 숫자키 1~7로 선 색을 바로 바꾼다. 설정에 저장된 색(penColor)은 건드리지 않아서,
; 드로잉을 껐다 켜면 원래 색으로 돌아온다.
SetDrawColor(index) {
    global DRAW_COLORS, activeDrawColor
    if (index >= 1 && index <= DRAW_COLORS.Length)
        activeDrawColor := DRAW_COLORS[index]
}

; 숫자키마다 서로 다른 색을 기억한 함수를 만들어준다. 반복문 안에서 화살표 함수를 바로 쓰면
; 모두 같은 변수를 붙들어 마지막 색 하나만 적용되므로, 이렇게 매개변수로 가둬야 한다.
MakeColorSetter(index) => (*) => SetDrawColor(index)

; Esc: 판서 내용을 지우고 판서 모드까지 종료
ExitDrawMode(*) {
    ClearDrawing()
    ToggleDraw()
}

; Windows 기본 색상 선택 대화상자(ChooseColor)를 띄워서 강조/판서 색을 자유롭게 고른다.
; ownerHwnd를 지정하지 않으면 위젯을 소유 창으로 쓴다 — 설정 창 등 다른 창에서 호출할 때는
; 그 창의 Hwnd를 넘겨줘야 대화상자가 그 창 뒤에 가려지지 않는다.
PickColor(ownerHwnd := 0, *) {
    global penColor, widget
    if !ownerHwnd
        ownerHwnd := widget.Hwnd
    cc := Buffer(72, 0)
    custColors := Buffer(16 * 4, 0)
    NumPut("UInt", 72, cc, 0)          ; lStructSize
    NumPut("Ptr", ownerHwnd, cc, 8)    ; hwndOwner
    NumPut("UInt", ToBGR(penColor), cc, 24) ; rgbResult (초기값)
    NumPut("Ptr", custColors.Ptr, cc, 32)   ; lpCustColors
    NumPut("UInt", 0x1 | 0x2, cc, 40)  ; CC_RGBINIT | CC_FULLOPEN
    if DllCall("comdlg32\ChooseColorW", "ptr", cc, "int") {
        bgr := NumGet(cc, 24, "UInt")
        r := bgr & 0xFF
        g := (bgr >> 8) & 0xFF
        b := (bgr >> 16) & 0xFF
        penColor := (r << 16) | (g << 8) | b
        UpdateSpotlightColor()
        UpdateWidgetState()
    }
}

; ================= 설정 창 =================
; 숫자 입력칸에서 Enter를 눌렀을 때만 값을 적용하기 위한 전역 키 감지.
; (매 글자마다 적용해버리면 입력 도중 값이 강제로 재조정되면서 타이핑을 방해한다)
sliderEditHandlers := Map()
OnMessage(0x100, OnSliderEditKeyDown) ; WM_KEYDOWN
OnSliderEditKeyDown(wParam, lParam, msg, hwnd) {
    global sliderEditHandlers
    if wParam = 13 && sliderEditHandlers.Has(hwnd) { ; VK_RETURN
        sliderEditHandlers[hwnd]()
        return 0
    }
}

; 라벨 + "-"버튼 + 슬라이더 + "+"버튼 + 숫자 직접입력 칸을 한 줄로 만들어주는 공용 함수.
; onChange(새값)은 슬라이더/버튼/입력칸(Enter 또는 포커스 이동 시) 중 무엇으로 바꾸든 동일하게 호출된다.
AddSliderRow(gui, y, labelText, rangeMin, rangeMax, initial, suffixText, onChange) {
    global sliderEditHandlers
    gui.AddText("x30 y" (y + 4) " w70", labelText)
    btnMinus := gui.AddButton("x100 y" y " w24 h24", "-")
    sl := gui.AddSlider("x126 y" (y + 2) " w104 Range" rangeMin "-" rangeMax, initial)
    btnPlus := gui.AddButton("x232 y" y " w24 h24", "+")
    ed := gui.AddEdit("x260 y" y " w40 h24 Center Number", initial)
    RoundRegion(ed.Hwnd, 40, 24, 12) ; 숫자칸 모서리를 둥글게
    if suffixText != ""
        gui.AddText("x302 y" (y + 4) " w30", suffixText)

    apply := (v) => (v := Max(rangeMin, Min(rangeMax, v)), sl.Value := v, ed.Text := v, onChange(v))
    applyFromEdit := () => apply(ed.Text = "" ? rangeMin : Integer(ed.Text))
    sl.OnEvent("Change", (ctrl, *) => apply(ctrl.Value))
    btnMinus.OnEvent("Click", (*) => apply(sl.Value - 1))
    btnPlus.OnEvent("Click", (*) => apply(sl.Value + 1))
    ed.OnEvent("LoseFocus", (*) => applyFromEdit())
    sliderEditHandlers[ed.Hwnd] := applyFromEdit
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
    global SpotSize, spotOpacity, SpotThickness, DrawThickness, DrawOpacity, clickEffectEnabled, clickSpeed, clickOpacity, CLICK_ANIM_INTERVAL, penColor, showWidget, showTrayIcons, widget, settingsGui, hideCursorOnHighlight, spotlightOn, APP_VERSION, drawOn, chkWidgetCtrl

    ; 판서 모드는 화면 전체를 오버레이로 덮어서 "그리기 말고는 아무것도 클릭되지 않는" 상태로
    ; 만드는 게 목적이라, 설정 창도 그 아래에 깔려 조작할 수 없다. 설정 창을 띄우려고 했다는
    ; 것은 판서를 잠시 멈추겠다는 뜻이므로 판서 모드를 먼저 끈다. 그려둔 내용은 지우지 않아서
    ; 판서를 다시 켜면 그대로 남아 있다.
    ; (설정 창을 항상 위로 올리는 방법도 써봤지만, 그러면 강조 하이라이트가 설정 창 밑으로
    ;  숨어버려서 크기·투명도를 보면서 맞출 수 없었다 — 그래서 이 방식으로 되돌렸다)
    if drawOn
        ToggleDraw()

    if IsSet(settingsGui) && WinExist("ahk_id " settingsGui.Hwnd) {
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
    ; 높이는 가장 내용이 많은 "단축키" 탭(드로잉 키 안내까지 들어간다)에 맞춰져 있다.
    tabs := settingsGui.AddTab3("x10 y10 w320 h345", ["일반", "포인터", "클릭효과", "드로잉", "위젯", "단축키"])

    tabs.UseTab("포인터")
    AddSliderRow(settingsGui, 50, "크기", 30, 200, SpotSize, "", (v) => (SpotSize := v, ApplySpotlightAppearance()))
    AddSliderRow(settingsGui, 90, "투명도", 0, 100, spotOpacity, "%", (v) => (spotOpacity := v, RedrawSpotlight()))

    chkHideCursor := settingsGui.AddCheckbox("x30 y132 w20 h20 " (hideCursorOnHighlight ? "Checked" : ""), "")
    settingsGui.AddText("x54 y133 w220", "활성화 시 마우스 커서 숨기기")
    chkHideCursor.OnEvent("Click", (ctrl, *) => (hideCursorOnHighlight := ctrl.Value, UpdateCursorHiddenState()))

    tabs.UseTab("클릭효과")
    ; 체크박스 라벨 텍스트까지 클릭 영역에 포함되면 실수로 누르기 쉬워서, 네모 칸만 클릭
    ; 가능하게 하고 글자는 옆에 별도의(클릭 안 되는) 텍스트로 둔다.
    chkClick := settingsGui.AddCheckbox("x30 y52 w20 h20 " (clickEffectEnabled ? "Checked" : ""), "")
    settingsGui.AddText("x54 y53 w200", "애니메이션 효과")
    chkClick.OnEvent("Click", (ctrl, *) => clickEffectEnabled := ctrl.Value)

    AddSliderRow(settingsGui, 90, "테두리 굵기", 2, 12, SpotThickness, "", (v) => SpotThickness := v)
    ; clickSpeed는 클수록 빠름(1~30) — 실제 타이머 간격(ms)은 반대로 계산한다
    AddSliderRow(settingsGui, 130, "빠르기", 1, 30, clickSpeed, "", (v) => (clickSpeed := v, CLICK_ANIM_INTERVAL := 41 - v))
    ; 클릭 링은 클릭할 때만 잠깐 나타나므로, 투명도는 값만 바꿔두면 다음 클릭부터 적용된다
    AddSliderRow(settingsGui, 170, "투명도", 0, 100, clickOpacity, "%", (v) => clickOpacity := v)

    tabs.UseTab("드로잉")
    AddSliderRow(settingsGui, 50, "선 굵기", 1, 12, DrawThickness, "", (v) => DrawThickness := v)
    AddSliderRow(settingsGui, 90, "투명도", 0, 100, DrawOpacity, "%", (v) => (DrawOpacity := v, UpdateDrawOpacity()))

    tabs.UseTab("위젯")
    chkWidget := settingsGui.AddCheckbox("x30 y52 w20 h20 " (showWidget ? "Checked" : ""), "")
    settingsGui.AddText("x54 y53 w200", "위젯 활성화")
    chkWidget.OnEvent("Click", (ctrl, *) => SetWidgetVisible(ctrl.Value))
    ; 위젯의 ✕나 트레이 메뉴로 상태가 바뀌어도 이 체크박스가 따라오도록 참조를 남겨둔다
    chkWidgetCtrl := chkWidget

    chkTray := settingsGui.AddCheckbox("x30 y92 w20 h20 " (showTrayIcons ? "Checked" : ""), "")
    settingsGui.AddText("x54 y93 w200", "작업표시줄 아이콘 활성화")
    chkTray.OnEvent("Click", (ctrl, *) => SetTrayIconsVisible(ctrl.Value))

    tabs.UseTab("일반")
    ; 저장/불러오기 없이 그 자리에서 바로 레지스트리에 반영되므로, 체크 표시는 항상
    ; IsRunAtStartup()으로 실제 상태를 다시 읽어서 보여준다.
    chkStartup := settingsGui.AddCheckbox("x30 y52 w20 h20 " (IsRunAtStartup() ? "Checked" : ""), "")
    settingsGui.AddText("x54 y53 w220", "Windows 시작 시 자동 실행")
    chkStartup.OnEvent("Click", (ctrl, *) => SetRunAtStartup(ctrl.Value))

    settingsGui.AddText("x30 y98 w70", "색상")
    ; Text 컨트롤의 배경색 지정은 이 창(테마 적용된 일반 창)에서 반영되지 않는 문제가 있어서,
    ; 항상 확실하게 색이 반영되는 진행 막대(Progress) 컨트롤을 꽉 채운 색상 견본으로 쓴다.
    ; Progress 컨트롤은 안쪽 채움 영역이 테두리보다 살짝 안으로 들어가 있어서, 모서리를
    ; 둥글게 잘라내면 그 여백 부분이 직선 자국으로 비쳐 보인다 — 그냥 사각형으로 둔다.
    swatch := settingsGui.AddProgress("x100 y94 w40 h24 Range0-100 -Smooth c" HexColor(penColor), 100)
    btnPick := settingsGui.AddButton("x150 y92 w110 h28", "색상 선택...")
    btnPick.OnEvent("Click", (*) => (PickColor(settingsGui.Hwnd), swatch.Opt("c" HexColor(penColor))))

    ; 문제를 알려줄 때 어느 버전인지 바로 말할 수 있도록, 눈에 띄지 않는 연한 글씨로 적어둔다.
    ; 제작자 표시도 같이 둔다 — 수업 화면을 가리지 않으면서 찾으려는 사람은 확실히 볼 수 있는
    ; 자리가 여기라서, 위젯이나 트레이 툴팁 대신 이곳을 골랐다.
    ; +0x80 = SS_NOPREFIX. 이게 없으면 Text 컨트롤이 &를 단축키 표시용 기호로 삼아 먹어버려서
    ; "Focus & Draw"가 "Focus  Draw"로 나온다 (뒤 글자에 밑줄만 그어진다).
    ; 탭 아래쪽에 붙여둔다. 프로그램 정보는 보통 이 자리에 있고, 위쪽 설정 항목들과 섞이지
    ; 않아 눈에 걸리지도 않는다.
    lblVersion := settingsGui.AddText("x30 y302 w270 +0x80", "Focus & Draw 버전 " APP_VERSION)
    lblVersion.SetFont("s9 c999999")
    lblAuthor := settingsGui.AddText("x30 y322 w270", "제작자: maker_SSAM")
    lblAuthor.SetFont("s9 c999999")

    tabs.UseTab("단축키")
    AddHotkeyRow(settingsGui, 50, "Spotlight")
    AddHotkeyRow(settingsGui, 90, "Draw")
    lblHotkeyHelp := settingsGui.AddText("x30 y126 w280 h32", "칸을 누른 뒤 원하는 키를 그대로 누르면 됩니다. Ctrl이나 Alt를 함께 눌러야 합니다.")
    lblHotkeyHelp.SetFont("s9 c999999")

    ; 드로잉 중에만 쓰는 키들은 바꿀 수 없지만, 모르면 못 쓰는 기능이라 여기에 같이 적어둔다.
    ; ("단축키" 탭을 연 사람은 쓸 수 있는 키 전체를 보고 싶은 것이지, 바꿀 수 있는 것만
    ;  보고 싶은 게 아니다) 두 개의 여러 줄 Text를 나란히 놓아 좌우 칸을 맞춘다.
    settingsGui.AddText("x30 y164 w280", "드로잉 모드에서 쓰는 키 (변경 불가)")
    keyNames := settingsGui.AddText("x38 y188 w130 h160",
        "드래그`nShift + 드래그`nCtrl + 드래그`nCtrl+Shift + 드래그`n오른쪽 드래그`nCtrl + Z`n1 ~ 7`nDelete`nEsc")
    keyNames.SetFont("s9")
    ; 오른쪽 칸 글자가 한 줄을 넘기면 그 아래 줄들이 왼쪽 칸과 어긋나 보인다. 색 설명은
    ; "1 ~ 7"과 나란히 읽히므로 순서만 짧게 적어도 뜻이 통한다.
    keyMeans := settingsGui.AddText("x176 y188 w140 h160",
        "자유선 그리기`n직선`n사각형`n원(타원)`n지우개`n실행 취소`n색: 빨주노초파남보`n전부 지우기`n지우고 드로잉 끄기")
    keyMeans.SetFont("s9 c666666")

    tabs.UseTab()

    ; 배경색은 테마가 적용된 버튼이라 바꿀 수 없어서, 대신 글자색을 연하게 해 일반
    ; 버튼과 다르다는 느낌만 은은하게 준다.
    btnExit := settingsGui.AddButton("x25 y365 w90 h30", "프로그램 종료")
    btnExit.SetFont("c999999")
    btnExit.OnEvent("Click", (*) => ExitApp())
    btnSave := settingsGui.AddButton("x125 y365 w90 h30", "저장")
    btnSave.OnEvent("Click", (*) => (SaveSettings(), btnSave.Text := "저장됨", SetTimer(() => btnSave.Text := "저장", -1000)))
    btnCloseSettings := settingsGui.AddButton("x225 y365 w90 h30", "닫기")
    btnCloseSettings.OnEvent("Click", (*) => settingsGui.Hide())
    settingsGui.OnEvent("Close", (*) => settingsGui.Hide())

    settingsGui.Show("w340 h412")
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

hBtnSpotOff := RenderButtonBitmap(0xFFFFFF, WIDGET_BG_COLOR, CHIP_SIZE, CHIP_CORNER, ICON_SPOT_DARK_PATH, CHIP_ICON_SIZE, ICON_OFF_COLOR)
hBtnSpotOn := RenderButtonBitmap(0xFFFFFF, WIDGET_BG_COLOR, CHIP_SIZE, CHIP_CORNER, ICON_SPOT_DARK_PATH, CHIP_ICON_SIZE, TRAY_ON_COLOR)
hBtnDrawOff := RenderButtonBitmap(0xFFFFFF, WIDGET_BG_COLOR, CHIP_SIZE, CHIP_CORNER, ICON_DRAW_DARK_PATH, CHIP_ICON_SIZE, ICON_OFF_COLOR)
hBtnDrawOn := RenderButtonBitmap(0xFFFFFF, WIDGET_BG_COLOR, CHIP_SIZE, CHIP_CORNER, ICON_DRAW_DARK_PATH, CHIP_ICON_SIZE, TRAY_ON_COLOR)
hBtnSettings := RenderButtonBitmap(0xFFFFFF, WIDGET_BG_COLOR, CHIP_SIZE, CHIP_CORNER, ICON_SETTINGS_PATH, CHIP_ICON_SIZE, ICON_OFF_COLOR)

widget := Gui("+AlwaysOnTop -Caption +ToolWindow", "FocusDraw")
widget.BackColor := "F2F2F2"
widget.SetFont("s10", "Malgun Gothic")

; 강조/판서 버튼은 "꺼짐/켜짐" 그림을 한 컨트롤에서 바꿔치기(STM_SETIMAGE)하는 대신,
; 같은 자리에 꺼짐용/켜짐용 Picture 컨트롤을 각각 만들어두고 보이기/숨기기만 전환한다.
; (STM_SETIMAGE로 비트맵을 다시 넣으면, 그 핸들이 이미 한 번 다른 곳에 쓰였는지 여부에
; 따라 안 보이게 되는 경우가 있어서 — Show/Hide 전환이 훨씬 안정적이다)
grip := widget.AddText("x6 y4 w14 h32 Center +0x200", "⋮")
btnSpotOff := widget.AddPicture("x24 y4 w32 h32", "HBITMAP:" hBtnSpotOff)
btnSpotOn := widget.AddPicture("x24 y4 w32 h32 Hidden", "HBITMAP:" hBtnSpotOn)
btnDrawOff := widget.AddPicture("x60 y4 w32 h32", "HBITMAP:" hBtnDrawOff)
btnDrawOn := widget.AddPicture("x60 y4 w32 h32 Hidden", "HBITMAP:" hBtnDrawOn)
btnSettings := widget.AddPicture("x96 y4 w32 h32", "HBITMAP:" hBtnSettings)
btnClose := widget.AddText("x132 y4 w14 h32 Center +0x200", "✕")

for ctrl in [btnSpotOff, btnSpotOn]
    ctrl.OnEvent("Click", ToggleSpotlight)
for ctrl in [btnDrawOff, btnDrawOn]
    ctrl.OnEvent("Click", ToggleDraw)
btnSettings.OnEvent("Click", OpenSettingsWindow)
; 위젯의 ✕는 프로그램 종료가 아니라 위젯만 숨김 (트레이 메뉴의 "위젯 표시"나 설정 창의
; "위젯" 탭에서 다시 켤 수 있음)
; 주의: 여기서 (*) => (showWidget := false, ...) 처럼 화살표 함수 안에서 전역 변수에 값을
; 넣으면 안 된다. AutoHotkey v2에서 함수 안의 대입은 global 선언이 없으면 같은 이름의
; 지역 변수를 새로 만들 뿐이라 전역값이 그대로 남는다. 실제로 그 탓에 ✕로 위젯을 숨겨도
; showWidget은 계속 참이어서, 설정 창의 "위젯 활성화"가 체크된 채로 보이고 한 번 눌러도
; 다시 나타나지 않는 버그가 있었다. 그래서 global을 선언할 수 있는 보통 함수로 둔다.
btnClose.OnEvent("Click", (*) => SetWidgetVisible(false))

; 위젯 창 자체의 바깥 테두리도 둥글게 잘라낸다 (칩과 달리 배경이 단색 하나뿐이라
; SetWindowRgn만으로 충분히 자연스럽게 보인다).
RoundRegion(hwnd, w, h, corner) {
    rgn := DllCall("CreateRoundRectRgn", "int", 0, "int", 0, "int", w, "int", h, "int", corner, "int", corner, "ptr")
    DllCall("SetWindowRgn", "ptr", hwnd, "ptr", rgn, "int", true)
}
RoundRegion(widget.Hwnd, widgetW, widgetH, 16)

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
    if showWidget
        widget.Show()
    else
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
        AddQuickTrayIcon(2, drawOn ? hIconDrawOn : hIconDrawOff, "판서 켜기/끄기")
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
OnWidgetDrag(wParam, lParam, msg, hwnd) {
    global widget, grip
    if (hwnd = widget.Hwnd || hwnd = grip.Hwnd)
        PostMessage(0xA1, 2, , , widget.Hwnd) ; WM_NCLBUTTONDOWN, HTCAPTION
}

widget.Show("x" (A_ScreenWidth - widgetW - 20) " y" (A_ScreenHeight - widgetH - 60) " w" widgetW " h" widgetH " Hide")
SetWidgetVisible(showWidget) ; 트레이 메뉴 체크 표시까지 시작 상태에 맞춰준다

; ================= 단축키 =================
; 이름 → 실제로 실행할 동작. 설정 창에서 조합을 바꿔도 동작은 그대로이므로 여기서 한 번만 묶는다.
HOTKEY_ACTIONS := Map("Spotlight", ToggleSpotlight, "Draw", ToggleDraw)

; 저장해둔 조합으로 전역 단축키를 켠다. 다른 프로그램이 이미 쓰는 조합이면 등록에 실패하는데,
; 시작하자마자 오류 창을 띄우면 수업 중에 곤란하므로 조용히 건너뛴다(위젯과 트레이는 그대로 동작).
for name, combo in hotkeyCombos
    RegisterHotkey(name, combo)

; (Win+Shift+S 캡처 도구 드래그가 판서로 그려지는 문제는 DrawPoll에서 "드래그를 시작한 창이
; 판서 오버레이인지"를 보고 걸러내므로, 별도 핫키 감지가 필요 없다.)
; 아래 두 단축키는 판서 모드 중에만 켜짐 (ToggleDraw에서 On/Off 제어). 판서 모드 중엔 이 키가
; 다른 프로그램으로 전달되지 않으므로, 흔히 쓰는 키(Backspace 등)는 일부러 넣지 않았다.
Hotkey("Esc", ExitDrawMode, "Off")    ; 내용 지우고 드로잉 모드 종료
Hotkey("Delete", ClearDrawing, "Off") ; 드로잉 모드 유지한 채 내용만 지움
Hotkey("^z", UndoDrawing, "Off")      ; 직전 획/지우기/전체 지우기 한 단계 되돌리기
loop DRAW_COLORS.Length
    Hotkey(String(A_Index), MakeColorSetter(A_Index), "Off") ; 1~7 = 빨주노초파남보

; 위 키들은 드로잉 모드일 때만 켠다. 그래야 평소에 숫자나 Ctrl+Z를 다른 프로그램에서
; 그대로 쓸 수 있다.
SetDrawModeHotkeys(state) {
    global DRAW_COLORS
    Hotkey("Esc", state)
    Hotkey("Delete", state)
    Hotkey("^z", state)
    loop DRAW_COLORS.Length
        Hotkey(String(A_Index), state)
}

; ================= 전역 단축키 등록/검증 =================
; 글자 키 하나만 단축키로 잡으면 그 글자를 어느 프로그램에서도 칠 수 없게 된다. Shift만 더해도
; 마찬가지(대문자를 못 침)라, Ctrl이나 Alt를 반드시 포함하게 한다. 기능키(F1~F24)는 글을 쓸 때
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
RegisterHotkey(name, combo) {
    global HOTKEY_ACTIONS, hotkeyRegistered
    if hotkeyRegistered.Has(name) {
        try Hotkey(hotkeyRegistered[name], , "Off")
        hotkeyRegistered.Delete(name)
    }
    if (combo = "")
        return false
    try {
        Hotkey(combo, HOTKEY_ACTIONS[name], "On")
        hotkeyRegistered[name] := combo
        return true
    }
    return false ; 다른 프로그램이 선점한 조합 등
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
        reason := "Ctrl이나 Alt를 함께 누르는 조합으로 정해주세요.`n`n글자 키 하나만 지정하면 그 글자를 어느 프로그램에서도 칠 수 없게 됩니다. (F1~F12 같은 기능키는 단독으로도 됩니다)"
    else {
        for otherName, otherCombo in hotkeyCombos {
            if (otherName != name && otherCombo = combo) {
                reason := "이미 " HOTKEY_LABELS[otherName] " 기능에 쓰고 있는 조합입니다.`n다른 조합으로 정해주세요."
                break
            }
        }
    }
    if (reason = "" && !RegisterHotkey(name, combo)) {
        reason := "다른 프로그램이 이미 쓰고 있어 이 조합은 등록할 수 없습니다.`n다른 조합으로 정해주세요."
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

