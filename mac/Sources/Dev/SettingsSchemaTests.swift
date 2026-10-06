import AppKit
import Carbon

// 설정 항목표(SettingsSchema)와 단축키 표기의 글 점검 (화면 없이 돈다). Golden.run이 부른다.
enum SettingsSchemaTests {
    static func run(_ report: (String, Bool, String) -> Void, ahk: String?) {
        func check(_ name: String, _ ok: Bool, _ detail: String = "") { report(name, ok, detail) }
        let fm = FileManager.default
        let dir = fm.temporaryDirectory.appendingPathComponent("fd-schema-\(getpid())", isDirectory: true)
        try? fm.removeItem(at: dir)
        try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: dir) }
        let keys = SettingsSchema.keys

        // ---- 표 자체 ----
        check("항목표: 키가 겹치지 않고 절·키가 모두 있음 (\(keys.count)개)",
              Set(keys.map(\.id)).count == keys.count && keys.count == 22 + 27 + 6 + 3 && keys.allSatisfy { !$0.section.isEmpty && !$0.key.isEmpty })
        do {
            let f = Settings()
            let bad = keys.filter { $0.read(f) != $0.defaultValue }.map(\.id)
            check("항목표의 기본값이 새 Settings의 값과 같음", bad.isEmpty && f.hotkeys == SettingsSchema.hotkeyDefaults, bad.joined(separator: ", "))
            let outside = keys.filter { k in
                if case .int(let r) = k.kind { return !r.contains(k.defaultValue) }
                return false
            }.map(\.id)
            check("항목표: 기본값이 범위 안에 있음", outside.isEmpty, outside.joined(separator: ", "))
        }

        // ---- 모든 키의 왕복: 값을 바꾸고 → 저장 → 새 Settings로 읽기 ----
        do {
            let a = Settings()
            for (i, k) in keys.enumerated() {
                switch k.kind {
                case .int(let r):
                    var v = (r.lowerBound + (r.upperBound - r.lowerBound) * 0.37).rounded()
                    if v == k.defaultValue { v = r.upperBound }
                    k.write(a, v)
                case .flag: k.write(a, k.defaultValue == 1 ? 0 : 1)
                case .color: k.write(a, Double(0x102030 + i * 0x010101))
                }
            }
            a.widgetX = 123; a.widgetY = 456
            a.hotkeys["Draw"] = "^!7"; a.hotkeys["SpotlightAlt"] = "+F8"
            let path = dir.appendingPathComponent("roundtrip.ini")
            check("모든 키를 바꿔 저장", a.save(to: path) == nil)
            let b = Settings(); b.load(from: path)
            let diff = keys.filter { $0.read(a) != $0.read(b) }.map(\.id)
            check("모든 키가 저장 → 읽기에서 그대로 돌아옴", diff.isEmpty && a.pairs().map { "\($0.0).\($0.1)=\($0.2)" } == b.pairs().map { "\($0.0).\($0.1)=\($0.2)" },
                  diff.joined(separator: ", "))
            check("위젯 자리와 [Hotkeys](AHK 표기)도 그대로 돌아옴", b.widgetX == 123 && b.widgetY == 456 && b.hotkeys["Draw"] == "^!7" && b.hotkeys["SpotlightAlt"] == "+F8"
                  && b.hotkeys["Spotlight"] == "F8", "\(b.hotkeys)")
            b.resetToDefaults()
            let left = keys.filter { $0.read(b) != $0.defaultValue }.map(\.id)
            check("모두 초기화: 표의 기본값으로, 위젯 자리는 비움", left.isEmpty && b.widgetX == nil && b.widgetY == nil && b.hotkeys == SettingsSchema.hotkeyDefaults,
                  left.joined(separator: ", "))
        }

        // ---- 잘못된 값 ----
        do {
            let path = dir.appendingPathComponent("bad.ini")
            let text = "[Highlight]\nSize=9999\nOpacity=abc\nColor=1000000\n[Hotkeys]\nDraw=h\nSpotlight=Ctrl+F8\nDrawAlt=^!9\n"
            try? text.write(to: path, atomically: true, encoding: .utf8)
            let s = Settings(); s.load(from: path)
            check("잘못된 값: 범위 밖은 끝값, 숫자가 아니면 기본값, 색이 범위 밖이면 기본값",
                  s.spotSize == 200 && s.spotOpacity == 40 && s.spotColor == 0xFF0000, "\(s.spotSize) \(s.spotOpacity) \(s.spotColor)")
            let steps = "[DrawKeys]\nStep1=0\nStep2=-3\nStep3=abc\nStep4=3.5\nStep5=99\nStep6=7\n"
            let sp = dir.appendingPathComponent("steps.ini")
            try? steps.write(to: sp, atomically: true, encoding: .utf8)
            let st = Settings(); st.load(from: sp)
            check("숫자키 굵기: 0 이하·글자·소수는 5단계, 10 넘으면 10, 맞는 값은 그대로 (ahk와 같음)",
                  Array(st.drawKeySteps.prefix(7)) == [5, 5, 5, 5, 10, 7, 5], "\(st.drawKeySteps)")
            check("잘못된 단축키(⌃·⌥ 없는 글자, 못 알아보는 표기)는 기본값, 올바른 것은 받아들임",
                  s.hotkeys["Draw"] == "F9" && s.hotkeys["Spotlight"] == "F8" && s.hotkeys["DrawAlt"] == "^!9", "\(s.hotkeys)")
        }

        // ---- 단축키 표기 ----
        do {
            let samples = ["F9", "^!1", "+F8", "#!h", "^!2", "F1", "^Space", "!Left"]
            let back = samples.map { HotkeyNotation.parse($0).flatMap(HotkeyNotation.format) ?? "nil" }
            check("단축키 표기 왕복 (F9, ^!1, +F8, #!h …)", back == samples, "\(back)")
            let f9 = HotkeyNotation.parse("F9"), c1 = HotkeyNotation.parse("^!1")
            check("단축키 표기의 뜻: F9 = 키 자리 101, ^!1 = ⌃⌥ + 18",
                  f9 == .init(code: kVK_F9, mods: 0) && c1 == .init(code: kVK_ANSI_1, mods: controlKey | optionKey))
            check("단축키 표기: 대문자·소문자를 같게 읽고 정해진 모양으로 다시 씀", HotkeyNotation.parse("f9").flatMap(HotkeyNotation.format) == "F9"
                  && HotkeyNotation.parse("^!H").flatMap(HotkeyNotation.format) == "^!h")
            let rejected = ["", "^", "abc", "F25", "^^1", "~F9", "*F9", "<^1", "Ctrl+F9"].filter { HotkeyNotation.parse($0) != nil }
            check("단축키 표기: 알아볼 수 없는 표기는 거절", rejected.isEmpty, rejected.joined(separator: ", "))
            let safe = ["F9": true, "+F8": true, "^h": true, "!1": true, "h": false, "#F9": false, "+h": false, "1": false]
            let wrong = safe.filter { HotkeyNotation.parse($0.key).map(HotkeyNotation.isSafe) != $0.value }.map(\.key)
            check("맥 단축키 규칙: ⌃ 또는 ⌥ 필수, F1~F20 단독은 허용, ⌘ 조합의 F키는 거절", wrong.isEmpty, wrong.joined(separator: ", "))
        }

        // ---- Windows(focus-draw.ahk)와 같은가 ----
        guard let ahk, let text = try? String(contentsOfFile: ahk, encoding: .utf8) else {
            check("Windows 항목 대조를 건너뜀 (--ahk 없음)", true, "INFO")
            return
        }
        func matches(_ pattern: String) -> [[String]] {
            guard let re = try? NSRegularExpression(pattern: pattern) else { return [] }
            return re.matches(in: text, range: NSRange(text.startIndex..., in: text)).map { m in
                (1..<m.numberOfRanges).map { String(text[Range(m.range(at: $0), in: text)!]) }
            }
        }
        let indexed: Set<String> = ["DrawKeys", "Boards"]
        var read = Set(matches("IniRead\\(SETTINGS_PATH, \"(\\w+)\", \"(\\w+)\"\\s*[,)]").map { "\($0[0]).\($0[1])" })
        read.formUnion(matches("ReadIniColor\\(\"(\\w+)\", \"(\\w+)\"[,)]").map { "\($0[0]).\($0[1])" })
        let positions = Set(SettingsSchema.positionKeys.map { "\($0.section).\($0.key)" })
        let known = Set(keys.filter { !indexed.contains($0.section) }.map(\.id))
        let missing = known.subtracting(read).sorted()
        let extra = read.subtracting(known).subtracting(positions).subtracting(SettingsSchema.windowsOnly).subtracting(SettingsSchema.windowsLegacy).sorted()
        check("Windows와 같은 키 목록: 표의 키가 모두 ahk에 있음", missing.isEmpty, missing.joined(separator: ", "))
        check("Windows와 같은 키 목록: ahk가 읽는 키가 모두 표·위젯 자리·Windows 전용 목록에 있음", extra.isEmpty, extra.joined(separator: ", "))
        check("Windows와 같은 키 목록: 숫자키 색·칠판 색 (DrawKeys Color/Opacity/Step + 번호, Boards Color/Opacity + W·E·R)",
              text.contains("\"DrawKeys\", \"Color\" A_Index") && text.contains("\"DrawKeys\", \"Opacity\" A_Index")
              && text.contains("\"DrawKeys\", \"Step\" A_Index")
              && text.contains("\"Boards\", \"Color\" key") && text.contains("\"Boards\", \"Opacity\" key"))

        var compared = 0, wrong: [String] = []
        for m in matches("Max\\((-?\\d+), Min\\((-?\\d+|STEP_MAX), IniRead\\(SETTINGS_PATH, \"(\\w+)\", \"(\\w+)\", (-?\\d+)\\)") {
            guard let k = SettingsSchema.key(m[2], m[3]), case .int(let r) = k.kind else { wrong.append("\(m[2]).\(m[3]) 표에 없음"); continue }
            compared += 1
            let hi = m[1] == "STEP_MAX" ? Double(STEP_MAX) : Double(m[1])!
            if r.lowerBound != Double(m[0]) || r.upperBound != hi || k.defaultValue != Double(m[4]) { wrong.append("\(k.id) ahk \(m[0])~\(m[1]) 기본 \(m[4])") }
        }
        for m in matches("IniRead\\(SETTINGS_PATH, \"(\\w+)\", \"(\\w+)\", (\\d)\\) = 1") {
            guard let k = SettingsSchema.key(m[0], m[1]), case .flag = k.kind else { if !SettingsSchema.windowsOnly.contains("\(m[0]).\(m[1])") { wrong.append("\(m[0]).\(m[1]) 켬/끔 표에 없음") }; continue }
            compared += 1
            if k.defaultValue != Double(m[2]) { wrong.append("\(k.id) 기본 \(m[2])") }
        }
        for m in matches("IniRead\\(SETTINGS_PATH, \"(\\w+)\", \"(\\w+)\", \"([0-9A-Fa-f]{6})\"\\)") {
            guard let k = SettingsSchema.key(m[0], m[1]), case .color = k.kind else { continue }
            compared += 1
            if k.defaultValue != Double(UInt32(m[2], radix: 16)!) { wrong.append("\(k.id) 기본색 \(m[2])") }
        }
        // 굵기 단계는 ahk에서 줄이 나뉘어 있고 기본값이 이름 붙은 상수(DEFAULT_*_STEP)다
        for (id, name) in [("Draw.ThicknessStep", "DEFAULT_DRAW_STEP"), ("Draw.EraserStep", "DEFAULT_ERASER_STEP"), ("DrawKeys.Step1", "DRAW_STEP_DEFAULT")] {
            guard let v = matches("\\b\(name) := (\\d+)").first.flatMap({ Double($0[0]) }), let k = SettingsSchema.keys.first(where: { $0.id == id }) else {
                wrong.append("\(id) 기본값을 못 찾음"); continue
            }
            compared += 1
            if k.defaultValue != v { wrong.append("\(id) 기본 \(v)") }
        }
        check("Windows와 같은 범위·기본값: 대조 \(compared)개가 모두 같음", wrong.isEmpty && compared >= 18, wrong.joined(separator: "; "))
        let hk = matches("HOTKEY_DEFAULTS := Map\\(\"(\\w+)\", \"(\\w+)\", \"(\\w+)\", \"(\\w+)\"\\)").first ?? []
        let winHK = SettingsSchema.hotkeys.filter { !$0.macOnly }.flatMap { [$0.name, $0.def] }
        check("Windows와 같은 단축키 기본값 (Spotlight=F8, Draw=F9)", hk == winHK, "\(hk)")
    }
}
