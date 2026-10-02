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
              && SettingsLayout.widgetShow == "Common.ShowWidget"
              && SettingsSchema.keys.filter { if case .flag = $0.kind { return true } else { return false } }.count == 3)
        check("설정 창: 숫자키 9개와 칠판 W·E·R 12줄", SettingsLayout.drawKeys.count == 12)
        check("단축키 기호 표시: ^!1 → ⌃⌥1, F8 → F8, +F8 → ⇧F8, #!h → ⌥⌘H",
              HotkeyDisplay.symbols("^!1") == "⌃⌥1" && HotkeyDisplay.symbols("F8") == "F8"
              && HotkeyDisplay.symbols("+F8") == "⇧F8" && HotkeyDisplay.symbols("#!h") == "⌥⌘H")

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
