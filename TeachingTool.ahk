#Requires AutoHotkey v2.0
#SingleInstance Force
Persistent()
SetWinDelay(-1)
CoordMode("Mouse", "Screen")

A_IconTip := "TeachingTool - 마우스 강조 / 화면 판서"
SETTINGS_PATH := A_ScriptDir "\settings.ini"

; 컴파일된 exe에도 아이콘 파일이 그대로 들어가도록 FileInstall로 함께 담고, 실행 시 임시 폴더로 꺼내 쓴다.
; (위젯/트레이 아이콘 둘 다 이 경로를 쓰므로 다른 UI보다 먼저 준비해둔다)
FileInstall("icon_spotlight.png", A_Temp "\tt_icon_spotlight.png", true)
FileInstall("icon_draw.png", A_Temp "\tt_icon_draw.png", true)
FileInstall("icon_spotlight_dark.png", A_Temp "\tt_icon_spotlight_dark.png", true)
FileInstall("icon_draw_dark.png", A_Temp "\tt_icon_draw_dark.png", true)
ICON_SPOT_PATH := A_Temp "\tt_icon_spotlight.png"
ICON_DRAW_PATH := A_Temp "\tt_icon_draw.png"
ICON_SPOT_DARK_PATH := A_Temp "\tt_icon_spotlight_dark.png"
ICON_DRAW_DARK_PATH := A_Temp "\tt_icon_draw_dark.png"

; ================= GDI+ 초기화 (PNG 아이콘 불러오기/색 입히기용) =================
gdipStartupInput := Buffer(24, 0)
NumPut("UInt", 1, gdipStartupInput, 0) ; GdiplusVersion = 1
gdipToken := 0
DllCall("gdiplus\GdiplusStartup", "ptr*", &gdipToken, "ptr", gdipStartupInput, "ptr", 0)

; ================= 설정값 (settings.ini에서 불러옴, 없으면 기본값) =================
; spotOpacity는 0~100(%)로 저장/표시하고, 실제 WinSetTransparent에 쓸 때만 0~255로 환산한다.
; clickSpeed는 "클수록 빠름"(1~30)으로 저장/표시하고, 타이머 간격(ms)으로 쓸 때만 뒤집어 계산한다.
LoadSettings() {
    global SETTINGS_PATH, SpotSize, spotOpacity, SpotThickness, DrawThickness, penColor
    global clickEffectEnabled, clickSpeed, CLICK_ANIM_INTERVAL
    SpotSize := Max(30, Min(200, IniRead(SETTINGS_PATH, "Highlight", "Size", 64)))
    ; 예전 버전은 투명도를 0~255로 저장했었다. 그 값이 남아있어도 안전하게 0~100으로 잘려 들어가도록 한다.
    spotOpacity := Max(0, Min(100, IniRead(SETTINGS_PATH, "Highlight", "Opacity", 43)))
    SpotThickness := Max(2, Min(12, IniRead(SETTINGS_PATH, "Highlight", "RingThickness", 5)))
    clickEffectEnabled := IniRead(SETTINGS_PATH, "Highlight", "ClickEffect", 1) = 1
    clickSpeed := Max(1, Min(30, IniRead(SETTINGS_PATH, "Highlight", "ClickSpeed", 16)))
    CLICK_ANIM_INTERVAL := 31 - clickSpeed
    DrawThickness := Max(1, Min(12, IniRead(SETTINGS_PATH, "Draw", "Thickness", 4)))
    penColor := Integer("0x" IniRead(SETTINGS_PATH, "Common", "Color", "FF3B30"))
}

SaveSettings() {
    global SETTINGS_PATH, SpotSize, spotOpacity, SpotThickness, DrawThickness, penColor, clickEffectEnabled, clickSpeed
    IniWrite(SpotSize, SETTINGS_PATH, "Highlight", "Size")
    IniWrite(spotOpacity, SETTINGS_PATH, "Highlight", "Opacity")
    IniWrite(SpotThickness, SETTINGS_PATH, "Highlight", "RingThickness")
    IniWrite(clickEffectEnabled ? 1 : 0, SETTINGS_PATH, "Highlight", "ClickEffect")
    IniWrite(clickSpeed, SETTINGS_PATH, "Highlight", "ClickSpeed")
    IniWrite(DrawThickness, SETTINGS_PATH, "Draw", "Thickness")
    IniWrite(HexColor(penColor), SETTINGS_PATH, "Common", "Color")
}

LoadSettings()

; ================= 상태값 =================
spotlightOn := false
drawOn := false
drawing := false
lastX := 0
lastY := 0
dragStartX := 0
dragStartY := 0
dragShapeMode := ""

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

; 도형(직선/사각형/원) 미리보기를 그리기 전에 현재 그림을 스냅샷으로 저장해뒀다가,
; 드래그 중 매 프레임마다 스냅샷으로 되돌린 뒤 새 도형을 다시 그려서 "고무줄 미리보기" 효과를 낸다.
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
drawGui := Gui("+AlwaysOnTop -Caption +ToolWindow +E0x80000", "TeachingTool-Draw") ; E0x80000 = WS_EX_LAYERED
drawGui.Show("x" vx " y" vy " w" vw " h" vh " Hide")

UpdateOverlay() {
    global drawGui, memDC, vx, vy, vw, vh
    ptDst := Buffer(8, 0)
    NumPut("Int", vx, ptDst, 0)
    NumPut("Int", vy, ptDst, 4)
    sz := Buffer(8, 0)
    NumPut("Int", vw, sz, 0)
    NumPut("Int", vh, sz, 4)
    ptSrc := Buffer(8, 0)
    blend := Buffer(4, 0)
    NumPut("UChar", 0, blend, 0)   ; AC_SRC_OVER
    NumPut("UChar", 0, blend, 1)   ; flags
    NumPut("UChar", 255, blend, 2) ; SourceConstantAlpha
    NumPut("UChar", 1, blend, 3)   ; AC_SRC_ALPHA
    DllCall("UpdateLayeredWindow", "ptr", drawGui.Hwnd, "ptr", 0, "ptr", ptDst, "ptr", sz, "ptr", memDC, "ptr", ptSrc, "uint", 0, "ptr", blend, "uint", 2) ; ULW_ALPHA
}
UpdateOverlay()

; GDI로 그린 픽셀은 알파 값이 채워지지 않으므로, 그린 영역만 알파를 255로 채워준다.
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
            ; 배경 기본값(1,1,1,1)보다 큰 값이면 실제로 펜이 지나간 픽셀
            if (NumGet(px, 0, "UChar") > 1 || NumGet(px, 1, "UChar") > 1 || NumGet(px, 2, "UChar") > 1)
                NumPut("UChar", 255, px, 3)
        }
    }
}

DrawSegment(x1, y1, x2, y2) {
    global memDC, vx, vy, DrawThickness, penColor
    lx1 := x1 - vx, ly1 := y1 - vy, lx2 := x2 - vx, ly2 := y2 - vy
    pen := DllCall("CreatePen", "int", 0, "int", DrawThickness, "uint", ToBGR(penColor), "ptr")
    old := DllCall("SelectObject", "ptr", memDC, "ptr", pen, "ptr")
    DllCall("MoveToEx", "ptr", memDC, "int", lx1, "int", ly1, "ptr", 0)
    DllCall("LineTo", "ptr", memDC, "int", lx2, "int", ly2)
    DllCall("SelectObject", "ptr", memDC, "ptr", old)
    DllCall("DeleteObject", "ptr", pen)
    PatchAlpha(lx1, ly1, lx2, ly2)
    UpdateOverlay()
}

; mode: "line" | "rect" | "ellipse". 시작점~현재점 사이의 도형을 매 프레임 다시 그린다.
; (매번 스냅샷으로 되돌린 뒤 새로 그려서, 드래그 중인 미리보기가 쌓이지 않고 하나만 보이게 함)
DrawShapePreview(mode, x1, y1, x2, y2) {
    global memDC, vx, vy, DrawThickness, penColor
    RestoreSnapshot()
    lx1 := x1 - vx, ly1 := y1 - vy, lx2 := x2 - vx, ly2 := y2 - vy
    pen := DllCall("CreatePen", "int", 0, "int", DrawThickness, "uint", ToBGR(penColor), "ptr")
    oldPen := DllCall("SelectObject", "ptr", memDC, "ptr", pen, "ptr")
    nullBrush := DllCall("GetStockObject", "int", 5, "ptr") ; NULL_BRUSH (안쪽은 채우지 않음)
    oldBrush := DllCall("SelectObject", "ptr", memDC, "ptr", nullBrush, "ptr")
    if mode = "line" {
        DllCall("MoveToEx", "ptr", memDC, "int", lx1, "int", ly1, "ptr", 0)
        DllCall("LineTo", "ptr", memDC, "int", lx2, "int", ly2)
    } else if mode = "rect" {
        DllCall("Rectangle", "ptr", memDC, "int", Min(lx1, lx2), "int", Min(ly1, ly2), "int", Max(lx1, lx2), "int", Max(ly1, ly2))
    } else if mode = "ellipse" {
        DllCall("Ellipse", "ptr", memDC, "int", Min(lx1, lx2), "int", Min(ly1, ly2), "int", Max(lx1, lx2), "int", Max(ly1, ly2))
    }
    DllCall("SelectObject", "ptr", memDC, "ptr", oldPen)
    DllCall("SelectObject", "ptr", memDC, "ptr", oldBrush)
    DllCall("DeleteObject", "ptr", pen)
    PatchAlpha(lx1, ly1, lx2, ly2)
    UpdateOverlay()
}

DrawPoll() {
    global drawOn, drawing, lastX, lastY, dragStartX, dragStartY, dragShapeMode, widget
    if !drawOn
        return
    if GetKeyState("LButton", "P") {
        MouseGetPos(&mx, &my, &winUnder)
        if (winUnder = widget.Hwnd) {
            drawing := false
            return
        }
        if !drawing {
            drawing := true
            lastX := mx
            lastY := my
            dragStartX := mx
            dragStartY := my
            ; 드래그를 시작하는 순간 눌려있던 키로 도형 종류를 정한다 (ZoomIt과 동일한 조합)
            dragShapeMode := GetKeyState("Ctrl", "P") && GetKeyState("Shift", "P") ? "ellipse"
                : GetKeyState("Ctrl", "P") ? "rect"
                : GetKeyState("Shift", "P") ? "line"
                : ""
            if dragShapeMode != ""
                SaveSnapshot()
        } else if dragShapeMode != "" {
            DrawShapePreview(dragShapeMode, dragStartX, dragStartY, mx, my)
        } else {
            DrawSegment(lastX, lastY, mx, my)
            lastX := mx
            lastY := my
        }
    } else {
        drawing := false
    }
}

; ================= 마우스 강조(스포트라이트) 창 =================
; 매 프레임 다시 그리는 대신, 창 모양 자체를 원 모양으로 SetWindowRgn으로 잘라내고
; WinSetTransparent로 반투명 처리 — 위치만 옮기면 되므로 훨씬 가볍다.
spotGui := Gui("+AlwaysOnTop -Caption +ToolWindow +E0x20", "TeachingTool-Spot") ; E0x20 = 클릭 통과
spotGui.Show("w" SpotSize " h" SpotSize " Hide")

InitSpotlightShape() {
    global spotGui, SpotSize, spotOpacity
    rgn := DllCall("CreateEllipticRgn", "int", 0, "int", 0, "int", SpotSize, "int", SpotSize, "ptr")
    DllCall("SetWindowRgn", "ptr", spotGui.Hwnd, "ptr", rgn, "int", true)
    WinSetTransparent(Max(0, Min(255, Round(spotOpacity * 255 / 100))), spotGui) ; spotOpacity는 0~100(%)
}
InitSpotlightShape()

; 설정 창에서 크기를 바꿀 때, 창 크기/모양/투명도/클릭 애니메이션 버퍼를 즉시 다시 적용한다.
ApplySpotlightAppearance() {
    global spotGui, clickGui, SpotSize
    spotGui.Move(,, SpotSize, SpotSize)
    clickGui.Move(,, SpotSize, SpotSize)
    InitSpotlightShape()
    SetupClickBuffer()
}

UpdateSpotlightColor() {
    global spotGui, penColor
    spotGui.BackColor := HexColor(penColor)
}
UpdateSpotlightColor()

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
CLICK_RING_KEY := "FF00FF"
CLICK_ANIM_FRAMES := 10 ; CLICK_ANIM_INTERVAL(빠르기)은 settings.ini에서 불러온 값을 그대로 씀

clickGui := Gui("+AlwaysOnTop -Caption +ToolWindow +E0x20", "TeachingTool-Click")
clickGui.BackColor := CLICK_RING_KEY
clickGui.Show("w" SpotSize " h" SpotSize " Hide")
WinSetTransColor(CLICK_RING_KEY, clickGui)

; 화면에 바로 지우고 다시 그리면 그 찰나의 빈 순간이 보여서(깜빡임) 테두리가 두 개로 보일 때가
; 있었다. 오프스크린 버퍼에 한 프레임을 통째로 그린 뒤 한 번에 옮겨 붙여서(BitBlt) 해결한다.
clickMemDC := 0
clickMemBmp := 0
SetupClickBuffer() {
    global clickMemDC, clickMemBmp, SpotSize
    if clickMemDC {
        DllCall("DeleteDC", "ptr", clickMemDC)
        DllCall("DeleteObject", "ptr", clickMemBmp)
    }
    hdcScreen := DllCall("GetDC", "ptr", 0, "ptr")
    clickMemDC := DllCall("CreateCompatibleDC", "ptr", hdcScreen, "ptr")
    clickMemBmp := DllCall("CreateCompatibleBitmap", "ptr", hdcScreen, "int", SpotSize, "int", SpotSize, "ptr")
    DllCall("SelectObject", "ptr", clickMemDC, "ptr", clickMemBmp)
    DllCall("ReleaseDC", "ptr", 0, "ptr", hdcScreen)
}
SetupClickBuffer()

clickAnimFrame := 0

ClickAnimStep() {
    global clickAnimFrame, CLICK_ANIM_FRAMES, clickGui, clickMemDC, SpotSize, SpotThickness, penColor, CLICK_RING_KEY
    if clickAnimFrame >= CLICK_ANIM_FRAMES {
        SetTimer(ClickAnimStep, 0)
        clickGui.Hide()
        return
    }
    MouseGetPos(&mx, &my)
    WinMove(mx - SpotSize // 2, my - SpotSize // 2,,, clickGui)

    ; 1) 오프스크린 버퍼를 지우고
    bgBrush := DllCall("CreateSolidBrush", "uint", ToBGR("0x" CLICK_RING_KEY), "ptr")
    rc := Buffer(16, 0)
    NumPut("Int", 0, rc, 0)
    NumPut("Int", 0, rc, 4)
    NumPut("Int", SpotSize, rc, 8)
    NumPut("Int", SpotSize, rc, 12)
    DllCall("FillRect", "ptr", clickMemDC, "ptr", rc, "ptr", bgBrush)
    DllCall("DeleteObject", "ptr", bgBrush)

    ; 2) 오프스크린 버퍼에 현재 프레임의 링을 그린 뒤
    progress := clickAnimFrame / CLICK_ANIM_FRAMES
    radius := Round((SpotSize / 2) * (1 - progress))
    cx := SpotSize // 2, cy := SpotSize // 2
    pen := DllCall("CreatePen", "int", 0, "int", SpotThickness, "uint", ToBGR(penColor), "ptr")
    oldPen := DllCall("SelectObject", "ptr", clickMemDC, "ptr", pen, "ptr")
    nullBrush := DllCall("GetStockObject", "int", 5, "ptr") ; NULL_BRUSH
    oldBrush := DllCall("SelectObject", "ptr", clickMemDC, "ptr", nullBrush, "ptr")
    DllCall("Ellipse", "ptr", clickMemDC, "int", cx - radius, "int", cy - radius, "int", cx + radius, "int", cy + radius)
    DllCall("SelectObject", "ptr", clickMemDC, "ptr", oldPen)
    DllCall("SelectObject", "ptr", clickMemDC, "ptr", oldBrush)
    DllCall("DeleteObject", "ptr", pen)

    ; 3) 완성된 프레임을 창에 한 번에 옮겨 붙인다
    hdc := DllCall("GetDC", "ptr", clickGui.Hwnd, "ptr")
    DllCall("BitBlt", "ptr", hdc, "int", 0, "int", 0, "int", SpotSize, "int", SpotSize, "ptr", clickMemDC, "int", 0, "int", 0, "uint", 0x00CC0020)
    DllCall("ReleaseDC", "ptr", clickGui.Hwnd, "ptr", hdc)

    clickAnimFrame += 1
}

StartClickAnimation(*) {
    global spotlightOn, clickEffectEnabled, clickAnimFrame, clickGui, CLICK_ANIM_INTERVAL
    if !spotlightOn || !clickEffectEnabled
        return
    clickAnimFrame := 0
    clickGui.Show("NA")
    SetTimer(ClickAnimStep, CLICK_ANIM_INTERVAL)
}
~LButton::StartClickAnimation()

; ================= 토글 / 동작 함수 =================
ToggleSpotlight(*) {
    global spotlightOn, spotGui
    spotlightOn := !spotlightOn
    if spotlightOn {
        spotGui.Show("NA")
        SetTimer(SpotFollow, 15)
    } else {
        SetTimer(SpotFollow, 0)
        spotGui.Hide()
    }
    UpdateWidgetState()
}

ToggleDraw(*) {
    global drawOn, drawGui, widget, spotlightOn, spotGui
    drawOn := !drawOn
    if drawOn {
        drawGui.Show("NA")
        if spotlightOn
            WinSetAlwaysOnTop(true, spotGui)
        WinSetAlwaysOnTop(true, widget)
        SetTimer(DrawPoll, 10)
        Hotkey("Esc", "On")
        Hotkey("Backspace", "On")
        Hotkey("Delete", "On")
    } else {
        SetTimer(DrawPoll, 0)
        Hotkey("Esc", "Off")
        Hotkey("Backspace", "Off")
        Hotkey("Delete", "Off")
        drawGui.Hide()
    }
    UpdateWidgetState()
}

ClearDrawing(*) {
    ClearBackBuffer()
    UpdateOverlay()
}

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
; 라벨 + "-"버튼 + 슬라이더 + "+"버튼 + 숫자 직접입력 칸을 한 줄로 만들어주는 공용 함수.
; onChange(새값)은 슬라이더/버튼/입력칸 중 무엇으로 바꾸든 동일하게 호출된다.
AddSliderRow(gui, y, labelText, rangeMin, rangeMax, initial, suffixText, onChange) {
    gui.AddText("x30 y" (y + 4) " w70", labelText)
    btnMinus := gui.AddButton("x100 y" y " w24 h24", "-")
    sl := gui.AddSlider("x126 y" (y + 2) " w104 Range" rangeMin "-" rangeMax, initial)
    btnPlus := gui.AddButton("x232 y" y " w24 h24", "+")
    ed := gui.AddEdit("x260 y" y " w40 h24 Number", initial)
    if suffixText != ""
        gui.AddText("x302 y" (y + 4) " w30", suffixText)

    apply := (v) => (v := Max(rangeMin, Min(rangeMax, v)), sl.Value := v, ed.Text := v, onChange(v))
    sl.OnEvent("Change", (ctrl, *) => apply(ctrl.Value))
    btnMinus.OnEvent("Click", (*) => apply(sl.Value - 1))
    btnPlus.OnEvent("Click", (*) => apply(sl.Value + 1))
    ed.OnEvent("Change", (ctrl, *) => apply(ctrl.Text = "" ? rangeMin : Integer(ctrl.Text)))
}

OpenSettingsWindow(*) {
    global SpotSize, spotOpacity, SpotThickness, DrawThickness, clickEffectEnabled, clickSpeed, CLICK_ANIM_INTERVAL, penColor, settingsGui

    if IsSet(settingsGui) && WinExist("ahk_id " settingsGui.Hwnd) {
        settingsGui.Show()
        return
    }

    settingsGui := Gui(, "TeachingTool 설정") ; ToolWindow를 안 써야 작업표시줄/Alt+Tab에 정상적으로 뜬다
    settingsGui.SetFont("s10", "Malgun Gothic")

    tabs := settingsGui.AddTab3("x10 y10 w320 h190", ["포인터", "왼쪽 클릭 효과", "판서"])

    tabs.UseTab(1)
    AddSliderRow(settingsGui, 50, "크기", 30, 200, SpotSize, "", (v) => (SpotSize := v, ApplySpotlightAppearance()))
    AddSliderRow(settingsGui, 90, "투명도", 0, 100, spotOpacity, "%", (v) => (spotOpacity := v, InitSpotlightShape()))

    settingsGui.AddText("x30 y134 w70", "색상")
    ; Text 컨트롤의 배경색 지정은 이 창(테마 적용된 일반 창)에서 반영되지 않는 문제가 있어서,
    ; 항상 확실하게 색이 반영되는 진행 막대(Progress) 컨트롤을 꽉 채운 색상 견본으로 쓴다.
    swatch := settingsGui.AddProgress("x100 y130 w40 h24 Range0-100 -Smooth c" HexColor(penColor), 100)
    btnPick := settingsGui.AddButton("x150 y128 w110 h28", "색상 선택...")
    btnPick.OnEvent("Click", (*) => (PickColor(settingsGui.Hwnd), swatch.Opt("c" HexColor(penColor))))

    tabs.UseTab(2)
    chkClick := settingsGui.AddCheckbox("x30 y50 w250 " (clickEffectEnabled ? "Checked" : ""), "애니메이션 효과")
    chkClick.OnEvent("Click", (ctrl, *) => clickEffectEnabled := ctrl.Value)

    AddSliderRow(settingsGui, 90, "테두리 굵기", 2, 12, SpotThickness, "", (v) => SpotThickness := v)
    ; clickSpeed는 클수록 빠름(1~30) — 실제 타이머 간격(ms)은 반대로 계산한다
    AddSliderRow(settingsGui, 130, "빠르기", 1, 30, clickSpeed, "", (v) => (clickSpeed := v, CLICK_ANIM_INTERVAL := 31 - v))

    tabs.UseTab(3)
    AddSliderRow(settingsGui, 50, "선 굵기", 1, 12, DrawThickness, "", (v) => DrawThickness := v)

    tabs.UseTab()

    btnSave := settingsGui.AddButton("x130 y210 w95 h30", "저장")
    btnSave.OnEvent("Click", (*) => (SaveSettings(), btnSave.Text := "저장됨", SetTimer(() => btnSave.Text := "저장", -1000)))
    btnCloseSettings := settingsGui.AddButton("x235 y210 w95 h30", "닫기")
    btnCloseSettings.OnEvent("Click", (*) => settingsGui.Hide())
    settingsGui.OnEvent("Close", (*) => settingsGui.Hide())

    settingsGui.Show("w340 h256")
}

; ================= 컨트롤 위젯(화면 구석 미니 툴바) =================
; 좌우 여백(6px)을 "눈에 보이는 글자/아이콘 기준"으로 동일하게 맞춘다. 그립(⋮)은 글자 폭에
; 딱 맞는 좁은 칸이라 닫기(✕)도 같은 폭(14)으로 줄여야 양쪽 여백이 실제로 같아 보인다.
widgetW := 152
widgetH := 40
widget := Gui("+AlwaysOnTop -Caption +ToolWindow", "TeachingTool")
widget.BackColor := "F2F2F2"
widget.SetFont("s10", "Malgun Gothic")

grip := widget.AddText("x6 y4 w14 h32 Center +0x200", "⋮")
btnSpot := widget.AddText("x24 y4 w32 h32 Center Border", "")
btnDraw := widget.AddText("x60 y4 w32 h32 Center Border", "")
btnColor := widget.AddText("x96 y4 w32 h32 Center Border", " ")
btnClose := widget.AddText("x132 y4 w14 h32 Center +0x200", "✕")

; 버튼 배경(btnSpot/btnDraw) 위에 트레이와 같은 아이콘 그림을 겹쳐서, 텍스트 대신 아이콘으로 보여준다.
; 위젯 배경이 밝은 색(흰색/연파랑)이라 트레이용 흰색 아이콘 대신 어두운 색 버전을 쓴다.
icoSpot := widget.AddPicture("x29 y9 w22 h22", ICON_SPOT_DARK_PATH)
icoDraw := widget.AddPicture("x65 y9 w22 h22", ICON_DRAW_DARK_PATH)

btnSpot.OnEvent("Click", ToggleSpotlight)
btnDraw.OnEvent("Click", ToggleDraw)
icoSpot.OnEvent("Click", ToggleSpotlight)
icoDraw.OnEvent("Click", ToggleDraw)
btnColor.OnEvent("Click", (*) => PickColor())
btnClose.OnEvent("Click", (*) => ExitApp())

UpdateWidgetState() {
    global spotlightOn, drawOn, btnSpot, btnDraw, btnColor, penColor
    global hIconSpotOn, hIconSpotOff, hIconDrawOn, hIconDrawOff
    activeBg := "85C2FF" ; 0A84FF를 50% 연하게 (흰색과 혼합)
    btnSpot.SetFont(spotlightOn ? "c000000 Bold" : "c000000 Norm")
    btnSpot.Opt(spotlightOn ? "Background" activeBg : "BackgroundFFFFFF")
    btnDraw.SetFont(drawOn ? "c000000 Bold" : "c000000 Norm")
    btnDraw.Opt(drawOn ? "Background" activeBg : "BackgroundFFFFFF")
    btnColor.Opt("Background" HexColor(penColor))
    ; 임의 색상으로 바뀔 때는 자동 다시 그리기가 안 될 때가 있어 강제로 다시 그린다.
    DllCall("InvalidateRect", "ptr", btnColor.Hwnd, "ptr", 0, "int", 1)
    DllCall("UpdateWindow", "ptr", btnColor.Hwnd)

    spotlightOn ? A_TrayMenu.Check("강조 켜기/끄기") : A_TrayMenu.Uncheck("강조 켜기/끄기")
    drawOn ? A_TrayMenu.Check("판서 켜기/끄기") : A_TrayMenu.Uncheck("판서 켜기/끄기")

    SetQuickTrayIcon(1, spotlightOn ? hIconSpotOn : hIconSpotOff)
    SetQuickTrayIcon(2, drawOn ? hIconDrawOn : hIconDrawOff)
}

; ================= 트레이 아이콘 메뉴 (작업표시줄 알림 영역) =================
; 위젯과 동일한 기능을 트레이 메뉴에서도 쓸 수 있도록 구성. 기본 AutoHotkey 개발용 메뉴는
; 구분선 아래에 남겨둔다(스크립트 편집/재실행이 필요할 때 대비).
A_TrayMenu.Insert("1&", "강조 켜기/끄기", (*) => ToggleSpotlight())
A_TrayMenu.Insert("2&", "판서 켜기/끄기", (*) => ToggleDraw())
A_TrayMenu.Insert("3&", "색상 선택", (*) => PickColor())
A_TrayMenu.Insert("4&", "설정...", OpenSettingsWindow)
A_TrayMenu.Insert("5&", "종료", (*) => ExitApp())
A_TrayMenu.Insert("6&")
A_TrayMenu.Default := "강조 켜기/끄기"

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

; 켜짐 상태를 표시할 색(위젯의 활성 색과 통일)
TRAY_ON_COLOR := 0x0A84FF

hIconSpotOff := LoadIconFromPng(ICON_SPOT_PATH, 0xFFFFFF)
hIconSpotOn := LoadIconFromPng(ICON_SPOT_PATH, TRAY_ON_COLOR)
hIconDrawOff := LoadIconFromPng(ICON_DRAW_PATH, 0xFFFFFF)
hIconDrawOn := LoadIconFromPng(ICON_DRAW_PATH, TRAY_ON_COLOR)

trayHelper := Gui("+ToolWindow", "TeachingTool-TrayHelper")
trayHelper.Show("Hide")
OnMessage(WM_TRAYBTN, OnQuickTrayClick)
AddQuickTrayIcon(1, hIconSpotOff, "강조 켜기/끄기")
AddQuickTrayIcon(2, hIconDrawOff, "판서 켜기/끄기")
OnExit((*) => (RemoveQuickTrayIcon(1), RemoveQuickTrayIcon(2), DllCall("gdiplus\GdiplusShutdown", "ptr", gdipToken)))

UpdateWidgetState()

; 위젯을 제목 표시줄 없이도 마우스로 끌어서 옮길 수 있게 함
OnMessage(0x0201, OnWidgetDrag) ; WM_LBUTTONDOWN
OnWidgetDrag(wParam, lParam, msg, hwnd) {
    global widget, grip
    if (hwnd = widget.Hwnd || hwnd = grip.Hwnd)
        PostMessage(0xA1, 2, , , widget.Hwnd) ; WM_NCLBUTTONDOWN, HTCAPTION
}

widget.Show("x" (A_ScreenWidth - widgetW - 20) " y" (A_ScreenHeight - widgetH - 60) " w" widgetW " h" widgetH)

; ================= 단축키 =================
^!h::ToggleSpotlight()
^!d::ToggleDraw()
^!c::ClearDrawing()
; 아래 세 단축키는 판서 모드 중에만 켜짐 (ToggleDraw에서 On/Off 제어)
Hotkey("Esc", ExitDrawMode, "Off")   ; 내용 지우고 판서 모드 종료
Hotkey("Backspace", ClearDrawing, "Off") ; 판서 모드 유지한 채 내용만 지움
Hotkey("Delete", ClearDrawing, "Off")    ; 판서 모드 유지한 채 내용만 지움
