#Requires AutoHotkey v2.0
#SingleInstance Force
; ============================================================================
;  터치펜 확인 도구  —  Focus & Draw 부속
;
;  전자칠판이 Windows에 무엇을 알려주는지 재고, 그 칠판에 맞는 지우개 경계값을 알려줍니다.
;  아래 넓은 빈 곳에 세 가지를 충분히 해보세요.
;    1. 펜으로 긋기     2. 손가락으로 긋기     3. 손날로 넓게 문지르기
;  (두 손가락도 함께 대보시면 멀티터치 지원 여부까지 나옵니다)
;
;  Esc 를 누르면 닫히고, 같은 폴더에 "터치펜-확인-결과.txt" 가 만들어집니다.
; ============================================================================

sizes := Map()       ; 긴 쪽 길이 -> 횟수
kinds := Map()       ; 종류(펜정보/플래그) -> 횟수
live := Map()
maxSimul := 0
count := 0
lastLine := "아직 입력이 없습니다. 아래 빈 곳에 대보세요."

TypeName(t) {
    static names := Map(1, "일반", 2, "터치", 3, "펜", 4, "마우스", 5, "터치패드")
    return (names.Has(t) ? names[t] : "알수없음") "(" t ")"
}
FlagNames(pf) {
    if (pf = 0)
        return "없음"
    s := ""
    if (pf & 0x01)
        s .= "옆버튼 "
    if (pf & 0x02)
        s .= "뒤집힘 "
    if (pf & 0x04)
        s .= "지우개 "
    return Trim(s) "(0x" Format("{:02X}", pf) ")"
}
Sx(lp) {
    v := lp & 0xFFFF
    return (v > 0x7FFF) ? v - 0x10000 : v
}
Sy(lp) {
    v := (lp >> 16) & 0xFFFF
    return (v > 0x7FFF) ? v - 0x10000 : v
}
Prune() {
    global live
    info := Buffer(96, 0)
    for id in live.Clone()
        if !DllCall("GetPointerInfo", "UInt", id, "Ptr", info, "Int")
            live.Delete(id)
}
Describe(id) {
    t := 0
    DllCall("GetPointerType", "UInt", id, "UInt*", &t, "Int")
    info := Buffer(120, 0)
    hasPen := DllCall("GetPointerPenInfo", "UInt", id, "Ptr", info, "Int")
    pf := hasPen ? NumGet(info, 96, "UInt") : 0
    ti := Buffer(144, 0)
    w := 0, h := 0
    if DllCall("GetPointerTouchInfo", "UInt", id, "Ptr", ti, "Int") {
        w := NumGet(ti, 112, "Int") - NumGet(ti, 104, "Int")
        h := NumGet(ti, 116, "Int") - NumGet(ti, 108, "Int")
    }
    return {type: t, hasPen: hasPen, pf: pf, w: w, h: h, big: Max(w, h)}
}

OnDown(wp, lp, msg, hwnd) {
    global live, maxSimul
    Prune()
    live[wp & 0xFFFF] := true
    if (live.Count > maxSimul)
        maxSimul := live.Count
    OnContact(wp, lp, msg, hwnd)
}
OnUp(wp, lp, msg, hwnd) {
    global live
    id := wp & 0xFFFF
    if live.Has(id)
        live.Delete(id)
    Refresh()
}
OnContact(wp, lp, msg, hwnd) {
    global sizes, kinds, lastLine, count
    id := wp & 0xFFFF
    d := Describe(id)
    count += 1
    sizes[d.big] := (sizes.Has(d.big) ? sizes[d.big] : 0) + 1
    k := Format("종류 {1}  펜정보 {2}  플래그 {3}", TypeName(d.type), d.hasPen ? "있음" : "없음", FlagNames(d.pf))
    kinds[k] := (kinds.Has(k) ? kinds[k] : 0) + 1
    lastLine := Format("id {1}   {2}   접촉 {3}x{4}  (긴 쪽 {5})   위치 ({6}, {7})",
                       id, k, d.w, d.h, d.big, Sx(lp), Sy(lp))
    Refresh()
}

; 관찰된 크기들 사이에서 **가장 넓게 비어 있는 구간**을 찾아 그 한가운데를 권한다.
; 펜·손가락 덩어리와 손날 덩어리 사이가 보통 가장 크게 벌어진다.
Suggest() {
    global sizes
    if (sizes.Count < 2)
        return {ok: false}
    keys := []
    for s in sizes
        keys.Push(s)
    ; 오름차순 정렬 (개수가 적어 단순 정렬로 충분하다)
    n := keys.Length
    i := 1
    while (i < n) {
        j := i + 1
        while (j <= n) {
            if (keys[j] < keys[i]) {
                tmp := keys[i], keys[i] := keys[j], keys[j] := tmp
            }
            j += 1
        }
        i += 1
    }
    bestGap := 0, lo := 0, hi := 0
    i := 1
    while (i < n) {
        gap := keys[i + 1] - keys[i]
        if (gap > bestGap) {
            bestGap := gap
            lo := keys[i]
            hi := keys[i + 1]
        }
        i += 1
    }
    if (bestGap < 3)
        return {ok: false, lo: lo, hi: hi, gap: bestGap}
    return {ok: true, lo: lo, hi: hi, gap: bestGap, value: lo + Floor(bestGap / 2)}
}

Histogram() {
    global sizes
    buckets := Map()
    for s, c in sizes {
        b := Floor(s / 10) * 10
        buckets[b] := (buckets.Has(b) ? buckets[b] : 0) + c
    }
    keys := []
    for b in buckets
        keys.Push(b)
    n := keys.Length
    i := 1
    while (i < n) {
        j := i + 1
        while (j <= n) {
            if (keys[j] < keys[i]) {
                tmp := keys[i], keys[i] := keys[j], keys[j] := tmp
            }
            j += 1
        }
        i += 1
    }
    out := ""
    for , b in keys {
        c := buckets[b]
        bars := Min(40, Max(1, Round(c / 5)))
        out .= Format("  {1:3}~{2:-3} : {3:5}회  {4}`n", b, b + 9, c, StrReplace(Format("{: " bars "}", ""), " ", "|"))
    }
    return out
}

Summary() {
    global sizes, kinds, count, maxSimul
    out := "동시에 닿은 최대 개수: " maxSimul " 개"
        . (maxSimul >= 2 ? "  (멀티터치 됨 - 두 손가락 제스처 사용 가능)" : "  (단일 터치 - 두 손가락이 안 잡힘)") "`n`n"
    out .= "▣ 나온 입력 종류`n"
    for k, c in kinds
        out .= "  " k "   [" c "회]`n"
    out .= "`n▣ 접촉 크기 분포 (긴 쪽 기준, 총 " count "회)`n" Histogram()
    s := Suggest()
    out .= "`n▣ 권하는 지우개 경계값`n"
    if s.ok
        out .= "  관찰된 크기 " s.lo " 과 " s.hi " 사이가 가장 넓게 비어 있습니다 (" s.gap "만큼).`n"
            . "  => focus-draw.ahk 의  ERASER_CONTACT_PX := " s.value "  을 권합니다.`n"
            . "     (" s.lo " 이하 = 펜·손가락으로 글씨,  " s.hi " 이상 = 손날로 지우기)`n"
    else
        out .= "  크기가 뚜렷하게 갈리지 않습니다. 펜·손가락·손날을 각각 충분히 대보셨는지 확인하시고,`n"
            . "  그래도 갈리지 않으면 ERASER_CONTACT_PX := 0 으로 두어 이 판정을 끄세요.`n"
    return out
}

Refresh() {
    global txt, big, lastLine, live, maxSimul
    Prune()
    big.Value := "지금 닿아 있는 접촉: " live.Count " 개        여태 동시 최대: " maxSimul " 개"
        . (maxSimul >= 2 ? "   =>  멀티터치 OK" : "   =>  아직 1개 (두 손가락을 함께 대보세요)")
    txt.Value := lastLine "`n`n" Summary()
}

vx := DllCall("GetSystemMetrics", "Int", 76, "Int")
vy := DllCall("GetSystemMetrics", "Int", 77, "Int")
vw := DllCall("GetSystemMetrics", "Int", 78, "Int")
vh := DllCall("GetSystemMetrics", "Int", 79, "Int")
tw := vw - 80

g := Gui("+AlwaysOnTop -Caption", "PenCheck")
g.BackColor := "101820"
g.SetFont("s15 cWhite", "맑은 고딕")
g.Add("Text", "x40 y26 w" tw, "터치펜 확인 —  ① 펜  ② 손가락  ③ 손날  로 각각 충분히 그어보세요        닫기: Esc")
g.SetFont("s19 cFFE9A0", "맑은 고딕")
big := g.Add("Text", "x40 y66 w" tw " h36", "지금 닿아 있는 접촉: 0 개")
g.SetFont("s11 cCCE0FF", "Consolas")
txt := g.Add("Text", "x40 y115 w" tw " h" (vh - 175), "아직 입력이 없습니다. 아래 빈 곳에 대보세요.")
g.Show("x" vx " y" vy " w" vw " h" vh)

OnMessage(0x0246, OnDown)      ; WM_POINTERDOWN
OnMessage(0x0245, OnContact)   ; WM_POINTERUPDATE
OnMessage(0x0247, OnUp)        ; WM_POINTERUP

Esc:: {
    out := "터치펜 확인 결과  (" FormatTime(, "yyyy-MM-dd HH:mm") ")`n`n" Summary()
    try FileDelete(A_ScriptDir "\터치펜-확인-결과.txt")
    FileAppend(out, A_ScriptDir "\터치펜-확인-결과.txt", "UTF-8")
    MsgBox(out, "터치펜 확인 결과", "Iconi")
    ExitApp
}
