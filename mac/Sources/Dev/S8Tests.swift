import AppKit

// S8a의 글 점검: 설정 창 칸이 항목표를 빠짐없이 덮는지, 모두 초기화, 로그인 항목을 건드리지 않는지. 화면 없이 돈다(Golden.run).
@MainActor enum S8Tests {
    static func run(_ report: (String, Bool, String) -> Void) {
        func check(_ name: String, _ ok: Bool, _ detail: String = "") { report(name, ok, detail) }
        LoginItem.allowed = false // 점검은 로그인 항목을 건드리지 않는다
        let fm = FileManager.default

        // ---- 설정 창 칸 ----
        let schemaIDs = Set(SettingsSchema.keys.map(\.id))
        let ui = SettingsLayout.allIDs
        check("설정 창: 항목표의 모든 키(\(schemaIDs.count)개)에 칸이 있음", ui == schemaIDs,
              "칸 없음: \(schemaIDs.subtracting(ui).sorted()) / 표에 없음: \(ui.subtracting(schemaIDs).sorted())")
        let all = SettingsLayout.focus.flatMap(\.fields) + SettingsLayout.draw.fields + SettingsLayout.widget.fields
        let stepWrong = all.filter { f in
            switch f.suffix { case "%": return f.step != (f.id == "Common.WidgetScale" ? 10 : 5); case "px": return f.step != 5; default: return f.step != 1 }
        }.map(\.id)
        check("설정 창: 슬라이더 간격은 크기·진하기 5, 위젯 크기 10, 나머지 1", stepWrong.isEmpty, stepWrong.joined(separator: ", "))
        check("설정 창: 켬·끔 키는 모두 상자 제목이나 위젯 표시에 있음",
              SettingsLayout.focus.compactMap(\.toggle) == ["Highlight.ClickEffect", "Highlight.RClickEffect"]
              && SettingsLayout.widgetShow == "Common.ShowWidget" && SettingsLayout.trayShow == "Common.ShowTrayIcons"
              && SettingsSchema.keys.filter { if case .flag = $0.kind { return true } else { return false } }.count == 4)
        check("설정 창: 숫자키 9개와 칠판 W·E·R 12줄", SettingsLayout.drawKeys.count == 12)
        check("단축키 기호 표시: ^!1 → ⌃⌥1, F8 → F8, +F8 → ⇧F8, #!h → ⌥⌘H",
              HotkeyDisplay.symbols("^!1") == "⌃⌥1" && HotkeyDisplay.symbols("F8") == "F8"
              && HotkeyDisplay.symbols("+F8") == "⇧F8" && HotkeyDisplay.symbols("#!h") == "⌥⌘H")

        // ---- S8b: 단축키 규칙 (조합 25개) ----
        do {
            func combo(_ t: String) -> HotkeyNotation.Combo { HotkeyNotation.parse(t)! }
            let others: [String: HotkeyNotation.Combo] = ["Draw": combo("F9"), "DrawAlt": combo("^!2"), "SpotlightAlt": combo("^!1")]
            // (표기, 기대: nil = 허용 / 이유에 들어갈 글자, 설명)
            let cases: [(String, String?)] = [
                ("^!h", nil), ("^h", nil), ("^+h", nil), ("#!h", nil), ("#^h", nil), ("^!5", nil), ("F7", nil), ("+F7", nil), ("!F7", nil), ("^F7", nil), ("F19", nil),
                ("h", "보조 키"), ("+h", "보조 키"), ("!h", "⌥"), ("!+h", "⌥"), ("#h", "⌘"), ("#+h", "⌘"), ("5", "드로잉 중에 쓰는 키"),
                ("#F7", "⌘"), ("F20", "F1~F19"),
                ("#Space", "macOS"), ("^Space", "macOS"), ("#Tab", "macOS"), ("^Left", "macOS"), ("^Up", "macOS"), ("#+3", "화면 캡처"), ("#+4", "화면 캡처"),
                ("Space", "⌃ 또는 ⌥"), ("Tab", "⌃ 또는 ⌥"), ("Esc", "드로잉 중에 쓰는 키"),
                ("F9", "이미 '"), ("^!2", "이미 '"),     // 다른 기능이 쓰는 조합
                ("#z", "드로잉 중에 쓰는 키"), ("^z", "드로잉 중에 쓰는 키"), ("1", "드로잉 중에 쓰는 키"),
            ]
            var wrong: [String] = []
            for (t, expect) in cases {
                let v = HotkeyRules.check(combo(t), name: "Spotlight", others: others)
                switch (v, expect) {
                case (.ok, nil): break
                case (.rejected(let why), let e?) where why.contains(e): break
                default: wrong.append("\(t) → \(v) (기대 \(expect ?? "허용"))")
                }
            }
            check("단축키 규칙: 조합 \(cases.count)개의 허용·거절과 이유 (한국어)", wrong.isEmpty, wrong.joined(separator: "; "))
            let defs = SettingsSchema.hotkeys.allSatisfy { h in
                HotkeyRules.check(combo(h.def), name: h.name, others: [:]) == .ok
            }
            check("단축키 규칙: 기본값 F8·F9·⌃⌥1·⌃⌥2는 모두 허용", defs)
            let same = HotkeyRules.check(combo("F8"), name: "Spotlight", others: others) == .ok
            check("단축키 규칙: 자기 자신의 지금 키를 다시 누르는 것은 허용", same)
            let rt = ["F8", "^!h", "#^!+Space", "!F7", "^+Left"].map { HotkeyNotation.parse($0).flatMap(HotkeyNotation.format) ?? "nil" }
            check("단축키: Windows 표기 왕복 (바꾼 키가 [Hotkeys]에 AHK 표기로 남고 다시 읽힘)", rt == ["F8", "^!h", "#^!+Space", "!F7", "^+Left"], "\(rt)")
            // 바꾼 키가 저장되고 다시 읽힘
            let fm = FileManager.default
            let dir = fm.temporaryDirectory.appendingPathComponent("fd-s8b-\(getpid())", isDirectory: true)
            try? fm.removeItem(at: dir); try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
            defer { try? fm.removeItem(at: dir) }
            let path = dir.appendingPathComponent("settings.ini")
            let st = Settings(); st.hotkeys["Spotlight"] = "^!h"
            check("바꾼 단축키 저장", st.save(to: path) == nil)
            let back = Settings(); back.load(from: path)
            check("바꾼 단축키를 다시 읽음 (^!h) · 안 바꾼 것은 기본값", back.hotkeys["Spotlight"] == "^!h" && back.hotkeys["Draw"] == "F9", "\(back.hotkeys)")
        }

        // ---- S8b: 키보드 그림 ----
        do {
            let rows = KeyboardLayout.rows(Settings())
            let caps = rows.flatMap { $0 }
            let special: [String: Int] = ["−": 27, "=": 24, "delete": 51]
            func code(_ label: String) -> Int? {
                special[label] ?? HotkeyNotation.parse(label.lowercased()).map(\.code)
            }
            let drawCodes = Set(KeyMap.drawKeys.filter { $0.combo.mods == 0 }.map(\.combo.code))
            let activeBad = caps.filter { $0.active && !(code($0.label).map(drawCodes.contains) ?? false) }.map(\.label)
            let missing = KeyMap.digits.prefix(10).filter { c in !caps.contains { $0.active && code($0.label) == c } }
            check("키보드 그림: 쓰는 키로 표시한 칸은 모두 실제 드로잉 키 표에 있음", activeBad.isEmpty, activeBad.joined(separator: ", "))
            check("키보드 그림: 숫자 0~9·칠판 Q W E R·펜 A S·도형 Z X C가 모두 있음",
                  missing.isEmpty && ["Q", "W", "E", "R", "A", "S", "Z", "X", "C"].allSatisfy { l in caps.contains { $0.label == l && $0.active } })
            let s = Settings(); s.drawKeyColors[2] = 0x123456
            check("키보드 그림: 3번 색을 바꾸면 그림의 색도 바뀜", KeyboardLayout.rows(s).flatMap { $0 }.first { $0.label == "3" }?.rgb == 0x123456)
            let n = KeyboardLayout.natural
            check("키보드 그림 크기: 화면에 맞추되 원래보다 키우지 않음",
                  KeyboardWindowController.fitScale(screen: CGSize(width: 3000, height: 2000)) == 1
                  && KeyboardWindowController.fitScale(screen: CGSize(width: 800, height: 600)) < 1
                  && n.width * KeyboardWindowController.fitScale(screen: CGSize(width: 1000, height: 800)) <= 1000 * 0.9 + 0.001)
        }

        // ---- 설정 창 칸이 쓰는 값 쓰기 ----
        do {
            let saved = Settings.shared.widgetColor, savedKey = Settings.shared.drawKeyColors, savedA = Settings.shared.boardAlphas
            valueBinding("Common.WidgetColor").wrappedValue = Double(0x3366CC)
            valueBinding("DrawKeys.Color3").wrappedValue = Double(0x123456)
            valueBinding("Boards.OpacityW").wrappedValue = 42
            check("설정 창: 색을 고르면 그 색이 설정에 남음 (위젯 색·숫자키 색)",
                  Settings.shared.widgetColor == 0x3366CC && Settings.shared.drawKeyColors[2] == 0x123456,
                  String(Settings.shared.widgetColor, radix: 16))
            check("설정 창: 칠판 진하기 값도 남음", Settings.shared.boardAlphas[0] == 42)
            valueBinding("Common.WidgetColor").wrappedValue = 99_999_999
            check("설정 창: 범위 밖 색 숫자는 FFFFFF로 자름", Settings.shared.widgetColor == 0xFFFFFF)
            Settings.shared.widgetColor = saved; Settings.shared.drawKeyColors = savedKey; Settings.shared.boardAlphas = savedA
        }

        // ---- 모두 초기화 ----
        let dir = fm.temporaryDirectory.appendingPathComponent("fd-s8-\(getpid())", isDirectory: true)
        try? fm.removeItem(at: dir)
        try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
        defer {
            try? fm.setAttributes([.posixPermissions: 0o755], ofItemAtPath: dir.path)
            try? fm.removeItem(at: dir)
        }
        let path = dir.appendingPathComponent("settings.ini")
        do {
            let s = Settings()
            s.spotSize = 170; s.drawColor = 0x00FF00; s.clickEffect = false
            s.drawKeyColors[2] = 0x123456; s.drawKeyAlphas[2] = 40; s.boardAlphas[1] = 70
            s.hotkeys["Draw"] = "^!h"; s.saveWidgetPosition(NSPoint(x: 10, y: 20), to: path)
            check("초기화 준비: 값을 바꿔 저장", s.save(to: path) == nil && fm.fileExists(atPath: path.path))
            let err = s.resetAll(at: path)
            check("모두 초기화: 설정 파일이 지워짐", err == nil && !fm.fileExists(atPath: path.path))
            let d = Settings()
            check("모두 초기화: 값이 모두 기본값 (색·진하기·켬끔·숫자키·칠판)",
                  s.spotSize == d.spotSize && s.drawColor == d.drawColor && s.clickEffect == d.clickEffect
                  && s.drawKeyColors == Settings.defaultDrawKeys && s.drawKeyAlphas == d.drawKeyAlphas && s.boardAlphas == d.boardAlphas,
                  "size \(s.spotSize) color \(s.drawColor)")
            check("모두 초기화: 단축키는 F8·F9·⌃⌥1·⌃⌥2, 위젯 자리는 처음으로", s.hotkeys == SettingsSchema.hotkeyDefaults && s.widgetX == nil && s.widgetY == nil)
            check("모두 초기화: 지운 뒤에도 같은 파일에 다시 저장할 수 있음", s.save(to: path) == nil)
        }
        do { // 읽을 수 없는 파일: 지우면 막아 둔 저장이 풀린다
            try? Data([0x5B, 0xC3, 0x28, 0xFF, 0xFE, 0x0A]).write(to: path)
            let s = Settings(); s.load(from: path)
            check("초기화 준비: 읽을 수 없는 파일은 저장이 막힘", s.unreadable)
            check("모두 초기화: 읽을 수 없던 파일도 지우고 저장 막힘이 풀림", s.resetAll(at: path) == nil && !s.unreadable && !s.writeBlocked)
        }
        do { // 폴더가 읽기 전용이라 못 지우면: 값은 그대로, 오류를 돌려줌
            try? "[Highlight]\nSize=150\n".write(to: path, atomically: true, encoding: .utf8)
            let s = Settings(); s.load(from: path)
            try? fm.setAttributes([.posixPermissions: 0o555], ofItemAtPath: dir.path)
            let err = s.resetAll(at: path)
            try? fm.setAttributes([.posixPermissions: 0o755], ofItemAtPath: dir.path)
            check("모두 초기화: 지울 수 없으면 오류를 알리고 아무것도 바꾸지 않음", err != nil && s.spotSize == 150 && fm.fileExists(atPath: path.path),
                  "err \(String(describing: err)) size \(s.spotSize)")
            let note = Notice.resetFailed(err ?? NSError(domain: "x", code: 1))
            check("초기화 실패 안내: 원인·'아무것도 바뀌지 않았습니다'·설정 폴더 버튼", note.body.joined().contains("아무것도 바뀌지 않았습니다") && !note.buttons.isEmpty)
        }

        // ---- 로그인 항목 ----
        check("로그인 항목: 응용 프로그램 폴더 판정", LoginItem.isInstalledLocation("/Applications/Focus & Draw.app")
              && LoginItem.isInstalledLocation(NSHomeDirectory() + "/Applications/Focus & Draw.app")
              && !LoginItem.isInstalledLocation("/Users/x/Downloads/Focus & Draw.app")
              && !LoginItem.isInstalledLocation("/private/var/folders/x/AppTranslocation/A/d/Focus & Draw.app"))
        check("로그인 항목: 점검 중에는 상태를 읽어도 켜도 SMAppService를 부르지 않음 (0번)",
              LoginItem.state(path: "/Applications/Focus & Draw.app") == .off && LoginItem.set(true).state == .off && LoginItem.calls == 0,
              "calls \(LoginItem.calls)")
        check("로그인 항목 안내: 허용 필요·옮겨 달라는 글", Notice.loginNeedsApproval().body.joined().contains("로그인 항목")
              && Notice.loginNeedsInstall().body.joined().contains("응용 프로그램"))
    }
}
