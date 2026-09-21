#Requires AutoHotkey v2.0
#SingleInstance Force
; ============================================================================
;  터치펜 확인 도구  —  Focus & Draw 부속
;
;  전자칠판의 터치펜을 화면에 대면, Windows가 그 입력을 어떻게 알려주는지 보여줍니다.
;  펜 "앞쪽"과 "뒤쪽"을 각각 몇 번 그어보세요. 아래 표시가 서로 다르면 구분이 가능한
;  기기이고, 똑같으면 Windows 수준에서는 구분할 방법이 없는 기기입니다.
;
;  Esc 를 누르면 닫히고, 같은 폴더에 "터치펜-확인-결과.txt" 가 만들어집니다.
; ============================================================================

seen := Map()
lastLine := "아직 입력이 없습니다. 화면에 펜을 대고 그어보세요."
count := 0

PEN_BARREL := 0x01, PEN_INVERTED := 0x02, PEN_ERASER := 0x04

TypeName(t) {
    names := Map(1, "일반", 2, "터치", 3, "펜", 4, "마우스", 5, "터치패드")
    return (names.Has(t) ? names[t] : "알 수 없음") " (" t ")"
}
FlagNames(pf) {
    global PEN_BARREL, PEN_INVERTED, PEN_ERASER
    if (pf = 0)
        return "없음 (앞쪽/보통)"
    s := ""
    if (pf & PEN_BARREL)
        s .= "옆버튼 "
    if (pf & PEN_INVERTED)
        s .= "뒤집힘 "
    if (pf & PEN_ERASER)
        s .= "지우개 "
    return Trim(s) " (0x" Format("{:02X}", pf) ")"
}
Sx(lp) {
    v := lp & 0xFFFF
    return (v > 0x7FFF) ? v - 0x10000 : v
}
Sy(lp) {
    v := (lp >> 16) & 0xFFFF
    return (v > 0x7FFF) ? v - 0x10000 : v
}

OnContact(wp, lp, msg, hwnd) {
    global seen, lastLine, count, txt
    id := wp & 0xFFFF
    t := 0
    DllCall("GetPointerType", "UInt", id, "UInt*", &t, "Int")
    info := Buffer(120, 0)
    hasPen := DllCall("GetPointerPenInfo", "UInt", id, "Ptr", info, "Int")
    pf := hasPen ? NumGet(info, 96, "UInt") : 0
    pressure := hasPen ? NumGet(info, 112, "UInt") : 0
    ; 접촉 면적도 같이 본다. 앞뒤 플래그를 안 주는 기기라도 뒤쪽(지우개)이 더 굵게 닿으면
    ; 그것으로 구분할 수 있을지 모른다 — 칠판에 한 번 갈 때 같이 재두는 값이다.
    ti := Buffer(144, 0)
    hasTouch := DllCall("GetPointerTouchInfo", "UInt", id, "Ptr", ti, "Int")
    area := "-"
    if hasTouch {
        cw := NumGet(ti, 112, "Int") - NumGet(ti, 104, "Int")
        ch := NumGet(ti, 116, "Int") - NumGet(ti, 108, "Int")
        area := cw "x" ch
    }
    count += 1

    key := t "/" (hasPen ? 1 : 0) "/" pf
    if !seen.Has(key)
        seen[key] := Format("종류 {1}   펜정보 {2}   플래그 {3}   접촉크기 {4}", TypeName(t), hasPen ? "있음" : "없음", FlagNames(pf), area)

    lastLine := Format("종류: {1}`n펜 정보: {2}`n펜 플래그: {3}`n필압: {4}`n접촉 크기: {5}`n위치: ({6}, {7})",
                       TypeName(t), hasPen ? "있음" : "없음 (이 기기는 펜 정보를 안 줍니다)",
                       FlagNames(pf), hasPen ? pressure : "-", area, Sx(lp), Sy(lp))
    Refresh()
}

Refresh() {
    global txt, lastLine, seen, count
    body := "▣ 지금 닿은 입력`n" lastLine "`n`n▣ 지금까지 나온 종류 (" seen.Count "가지 / 접촉 " count "회)`n"
    i := 0
    for k, v in seen
        body .= "  " (++i) ". " v "`n"
    if (seen.Count >= 2)
        body .= "`n=> 두 가지 이상 나왔습니다. 앞뒤 구분이 가능한 기기일 가능성이 높습니다."
    else if (seen.Count = 1)
        body .= "`n=> 아직 한 가지뿐입니다. 펜을 뒤집어서도 그어보세요."
    txt.Value := body
}

; 전자칠판이 주 모니터가 아닐 수 있으므로 **모든 모니터를 덮는다.** 어느 화면에 펜을 대든
; 이 창이 받는다. (SM_*VIRTUALSCREEN = 76,77,78,79)
vx := DllCall("GetSystemMetrics", "Int", 76, "Int")
vy := DllCall("GetSystemMetrics", "Int", 77, "Int")
vw := DllCall("GetSystemMetrics", "Int", 78, "Int")
vh := DllCall("GetSystemMetrics", "Int", 79, "Int")
tw := vw - 80

g := Gui("+AlwaysOnTop -Caption", "PenCheck")
g.BackColor := "101820"
g.SetFont("s16 cWhite", "맑은 고딕")
g.Add("Text", "x40 y30 w" tw, "터치펜 확인 —  펜 앞쪽으로 몇 번, 뒤집어서 뒤쪽으로 몇 번 그어보세요.    닫기: Esc")
g.SetFont("s14 cCCE0FF", "맑은 고딕")
txt := g.Add("Text", "x40 y90 w" tw " h420", "아직 입력이 없습니다. 화면에 펜을 대고 그어보세요.")
g.SetFont("s12 c88AABB", "맑은 고딕")
g.Add("Text", "x40 y530 w" tw, "이 아래 넓은 빈 공간에 그어주세요. (글자 위가 아니라 빈 곳이어야 정확합니다)")
g.Show("x" vx " y" vy " w" vw " h" vh)

OnMessage(0x0246, OnContact) ; WM_POINTERDOWN
OnMessage(0x0245, OnContact) ; WM_POINTERUPDATE

Esc:: {
    global seen, count
    out := "터치펜 확인 결과  (" FormatTime(, "yyyy-MM-dd HH:mm") ")`n"
    out .= "접촉 " count "회, 서로 다른 종류 " seen.Count "가지`n`n"
    for k, v in seen
        out .= v "`n"
    out .= "`n[키] 종류/펜정보/플래그 = " 
    for k, v in seen
        out .= k "  "
    try FileDelete(A_ScriptDir "\터치펜-확인-결과.txt")
    FileAppend(out, A_ScriptDir "\터치펜-확인-결과.txt", "UTF-8")
    MsgBox(out, "터치펜 확인 결과", "Iconi")
    ExitApp
}
