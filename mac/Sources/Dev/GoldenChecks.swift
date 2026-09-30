import AppKit

// 그림 기준 점검의 글 점검(단언) (Golden.swift의 일부)
extension Golden {
    // ---------- 글 점검 ----------
    static func assertions(_ report: (String, Bool, String) -> Void, ahk: String?) {
        func check(_ name: String, _ ok: Bool, _ detail: String = "") { report(name, ok, detail) }
        resetSettings()
        func strokes(_ s: Sim, _ n: Int) {
            for i in 0..<n { s.stroke([s.P(20 + CGFloat(i) * 5, 40), s.P(60 + CGFloat(i) * 5, 80)]) }
        }

        // 실행 취소
        do {
            let s = Sim(); strokes(s, 31)
            for _ in 0..<40 { s.key(K.z, .command) }
            check("실행 취소: 31획 중 30개만 취소됨", s.d.items.count == 1, "남은 획 \(s.d.items.count)")
        }
        do {
            let s = Sim(); var now = Date(timeIntervalSince1970: 1_000_000)
            s.d.clock = { now }
            strokes(s, 3)
            s.d.finishSession(clear: false)
            now.addTimeInterval(UNDO_KEEP_S - 1); s.d.expireUndoIfNeeded()
            s.key(K.z, .command)
            check("끈 뒤 \(Int(UNDO_KEEP_S) - 1)초: 아직 되돌릴 수 있음", s.d.items.count == 2, "획 \(s.d.items.count)")

            let t = Sim(); var now2 = Date(timeIntervalSince1970: 1_000_000)
            t.d.clock = { now2 }
            strokes(t, 3)
            t.d.finishSession(clear: false)
            now2.addTimeInterval(UNDO_KEEP_S + 1); t.d.expireUndoIfNeeded()
            t.key(K.z, .command)
            check("끈 뒤 \(Int(UNDO_KEEP_S) + 1)초: 되돌리기 기록이 비워짐", t.d.items.count == 3, "획 \(t.d.items.count)")
        }
        do {
            let s = Sim(); strokes(s, 3)
            s.key(K.delete)
            let cleared = s.d.items.last?.kind == .clear
            s.key(K.z, .command)
            check("전부 지우기도 한 단계로 되돌림", cleared && s.d.items.count == 3 && s.d.items.last?.kind == .stroke,
                  "획 \(s.d.items.count)")
        }
        do {
            let s = Sim(); strokes(s, 2)
            s.d.down(s.P(300, 300), s.ev(.rightMouseDown, s.P(300, 300)), right: true); s.d.up(s.P(300, 300))
            check("제자리 오른쪽 클릭은 아무것도 남기지 않음", s.d.items.count == 2)
            s.key(K.z, [.command, .shift])
            check("⌘⇧Z는 실행 취소가 아님", s.d.items.count == 2)
        }

        // 켜고 끄기
        do {
            let s = Sim()
            s.key(K.n3); s.key(K.plus); s.key(K.plus); s.key(K.a)
            s.d.resetTemporaries()
            let st = s.d.penState, f = Settings()
            check("켤 때마다 임시 색·굵기·펜이 설정값으로 돌아옴",
                  st.rgb == f.drawColor && st.alpha == 1 && st.penStep == Int(f.drawStep) && st.eraserStep == Int(f.eraserStep) && st.pen == .normal,
                  "\(st)")
        }
        do {
            let s = Sim(); strokes(s, 2); s.key(K.w)
            s.d.finishSession(clear: false)
            check("F9(끄기 그대로): 잉크와 칠판을 남김", s.d.items.count == 2 && s.d.penState.board == 1,
                  "획 \(s.d.items.count) 칠판 \(s.d.penState.board)")
            s.d.finishSession(clear: true)
            check("Esc·위젯 버튼: 잉크와 칠판을 둘 다 지움", s.d.items.last?.kind == .clear && s.d.penState.board == 0,
                  "칠판 \(s.d.penState.board)")
        }
        do {
            let s = Sim(); s.key(K.w); s.key(K.s); strokes(s, 2); s.key(K.delete)
            let st = s.d.penState
            check("Delete는 지우기만 하고 칠판·펜 모드를 유지", st.board == 1 && st.pen == .rainbow && s.d.items.last?.kind == .clear,
                  "칠판 \(st.board) 펜 \(st.pen)")
        }

        // 키
        do {
            let s = Sim(); Settings.shared.drawColor = 0x00FF00
            s.key(K.n3); let yellow = s.d.penState.rgb
            s.key(K.n0)
            check("0은 그 순간의 기본색", yellow == Settings.shared.drawKeyColors[2] && s.d.penState.rgb == 0x00FF00 && s.d.penState.alpha == 1,
                  "rgb=\(String(s.d.penState.rgb, radix: 16))")
            resetSettings()
        }
        do {
            let s = Sim(); s.key(K.a); s.key(K.n4); let a = s.d.penState.pen
            s.key(K.s); s.key(K.n4); let b = s.d.penState.pen
            check("숫자키는 레이저(A)·무지개(S)를 끄고 보통 펜으로", a == .normal && b == .normal, "\(a) \(b)")
        }
        do {
            let s = Sim(); s.key(K.s)
            s.d.down(s.P(80, 100), s.ev(.leftMouseDown, s.P(80, 100)), right: false)
            s.d.drag(s.P(120, 100), s.ev(.leftMouseDragged, s.P(120, 100)))
            s.key(K.n3)                                                          // 긋는 도중 색 키
            s.d.drag(s.P(200, 100), s.ev(.leftMouseDragged, s.P(200, 100)))
            s.key(K.a)                                                           // 긋는 도중 레이저 키
            s.d.drag(s.P(280, 100), s.ev(.leftMouseDragged, s.P(280, 100)))
            s.d.up(s.P(280, 100))
            let last = s.d.items.last
            check("긋는 도중 색·펜 키를 눌러도 색 개수 = 점 개수", last != nil && last?.points.count == last?.hues?.count,
                  "점 \(last?.points.count ?? -1) 색 \(last?.hues?.count ?? -1)")
            let before = s.d.items.count
            s.key(K.a)
            s.d.down(s.P(80, 200), s.ev(.leftMouseDown, s.P(80, 200)), right: false)
            s.d.drag(s.P(150, 200), s.ev(.leftMouseDragged, s.P(150, 200)))
            s.key(K.s)
            s.d.drag(s.P(220, 200), s.ev(.leftMouseDragged, s.P(220, 200)))
            s.d.up(s.P(220, 200))
            check("레이저 획은 목록에 쌓이지 않음", s.d.items.count == before)
            s.stroke([s.P(80, 300), s.P(200, 300)])
            check("다음 획부터 새 펜(무지개)이 적용됨", s.d.items.last?.hues != nil)
        }
        do {
            let s = Sim()
            s.key(18); let a = s.d.penState.rgb
            s.key(19); let b = s.d.penState.rgb
            check("키 코드 표: 1·2는 입력 소스와 상관없이 자리 번호로 동작", a == Settings.shared.drawKeyColors[0] && b == Settings.shared.drawKeyColors[1])
        }

        // Windows와 같은 값인지
        let penExpect: [Double] = [3, 3.9, 5.1, 6.6, 8.6, 11.1, 14.5, 18.8, 24.5, 31.8]
        let eraserExpect: [Double] = [10, 15, 23, 34, 51, 76, 114, 171, 256, 384]
        let penNow = (1...10).map { (Double(penPx($0)) * 10).rounded() / 10 }
        let eraserNow = (1...10).map { Double(eraserPx($0)).rounded() }
        check("펜 굵기 표가 README와 같음 (3 … 31.8)", penNow == penExpect, "\(penNow)")
        check("지우개 굵기 표가 README와 같음 (10 … 384)", eraserNow == eraserExpect, "\(eraserNow)")
        do {
            let f = Settings()
            check("펜·지우개 기준값과 단계 수", STEP_MAX == 10 && abs(Double(penPx(2) / penPx(1)) - 1.3) < 1e-9 && abs(Double(eraserPx(2) / eraserPx(1)) - 1.5) < 1e-9)
            check("기본 숫자키 색 9개가 README 표와 같음",
                  f.drawKeyColors == [0xFF0000, 0xFF7F00, 0xFFFF00, 0x00FF00, 0x0000FF, 0x4B0082, 0x9400D3, 0x000000, 0xFFFFFF])
            check("칠판 W/E/R 기본색", f.boardColors == [0xFFFFFF, 0x14472F, 0x000000])
        }
        if let ahk, let text = try? String(contentsOfFile: ahk, encoding: .utf8) {
            func numbers(_ s: String) -> [Double] {
                guard let re = try? NSRegularExpression(pattern: "-?(?:0x[0-9A-Fa-f]+|[0-9]+(?:\\.[0-9]+)?)") else { return [] }
                return re.matches(in: s, range: NSRange(s.startIndex..., in: s)).compactMap { m in
                    let t = String(s[Range(m.range, in: s)!])
                    return t.contains("0x") ? Double(Int(t.replacingOccurrences(of: "0x", with: ""), radix: 16) ?? 0) : Double(t)
                }
            }
            func ahkArray(_ name: String) -> [Double]? {
                guard let re = try? NSRegularExpression(pattern: "^\(name)\\s*:=\\s*\\[(.*)\\]", options: .anchorsMatchLines),
                      let m = re.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
                      let r = Range(m.range(at: 1), in: text) else { return nil }
                return numbers(String(text[r]))
            }
            func ahkNumber(_ name: String) -> Double? {
                guard let re = try? NSRegularExpression(pattern: "\\b\(name)\\s*:=\\s*(-?[0-9]+(?:\\.[0-9]+)?)"),
                      let m = re.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
                      let r = Range(m.range(at: 1), in: text) else { return nil }
                return Double(text[r])
            }
            let f = Settings()
            check("ahk와 같음: DRAW_COLOR_DEFAULTS", ahkArray("DRAW_COLOR_DEFAULTS") == f.drawKeyColors.map(Double.init),
                  "\(ahkArray("DRAW_COLOR_DEFAULTS") ?? [])")
            check("ahk와 같음: BOARD_COLOR_DEFAULTS (Q는 -1)", ahkArray("BOARD_COLOR_DEFAULTS") == [-1] + f.boardColors.map(Double.init),
                  "\(ahkArray("BOARD_COLOR_DEFAULTS") ?? [])")
            check("ahk와 같음: BOARD_KEYS의 칠판 색", ahkArray("BOARD_KEYS") == [-1] + f.boardColors.map(Double.init),
                  "\(ahkArray("BOARD_KEYS") ?? [])")
            check("ahk와 같음: LASER_HOLD·FADE·MIN_WIDTH",
                  ahkNumber("LASER_HOLD_MS") == LASER_HOLD * 1000 && ahkNumber("LASER_FADE_MS") == LASER_FADE * 1000
                  && ahkNumber("LASER_MIN_WIDTH") == Double(LASER_MIN_WIDTH))
            check("ahk와 같음: LASER_LAYERS", ahkArray("LASER_LAYERS") == LASER_LAYERS.flatMap { [Double($0.0), Double($0.1), Double($0.2)] },
                  "\(ahkArray("LASER_LAYERS") ?? [])")
            check("ahk와 같음: 펜·지우개 기준값·단계·무지개 한 바퀴",
                  ahkNumber("PEN_BASE_PX") == 3 && ahkNumber("PEN_STEP_RATIO") == 1.3 && ahkNumber("ERASER_BASE_PX") == 10
                  && ahkNumber("ERASER_STEP_RATIO") == 1.5 && ahkNumber("STEP_MAX") == Double(STEP_MAX)
                  && ahkNumber("RAINBOW_CYCLE_PX") == Double(RAINBOW_CYCLE_PX))
        } else {
            check("ahk와 같은 값 점검을 건너뜀 (--ahk 없음)", true, "INFO")
        }

        // 그림 만드는 길
        do {
            let s = Sim(); s.stroke(s.wiggle(40, 100, 300)); s.key(K.n3)
            Settings.shared.drawKeyAlphas[2] = 50
            s.key(K.n3); s.stroke(s.wiggle(40, 200, 300))
            let a = s.image().flatMap(rgba), b = s.image().flatMap(rgba)
            check("같은 목록은 늘 같은 그림 (renderScene은 순수함)", a != nil && a == b)
            resetSettings()
        }
    }
}
