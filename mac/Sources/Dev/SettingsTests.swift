import AppKit

// 설정 보존·안내·기록·진단의 글 점검 (화면 없이 돈다). Golden.run이 부른다.
//   --fixtures <폴더>: windows-settings.ini.txt (선생님 실제 Windows 파일: UTF-16 LE, CRLF, [Hotkeys]·HideCursor 포함)
enum SettingsTests {
    static func run(_ report: (String, Bool, String) -> Void, fixtures: String?) {
        func check(_ name: String, _ ok: Bool, _ detail: String = "") { report(name, ok, detail) }
        let fm = FileManager.default
        let dir = fm.temporaryDirectory.appendingPathComponent("fd-settings-\(getpid())", isDirectory: true)
        try? fm.removeItem(at: dir)
        try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
        defer {
            // 읽기 전용으로 만든 폴더도 지울 수 있게 되돌린다
            for u in (try? fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)) ?? [] {
                try? fm.setAttributes([.posixPermissions: 0o755], ofItemAtPath: u.path)
            }
            try? fm.removeItem(at: dir)
        }
        func bytes(_ u: URL) -> Data? { try? Data(contentsOf: u) }
        func ini(_ u: URL) -> IniFile? { Settings.readIni(u).ini }
        func entries(_ f: IniFile?) -> [String] { (f?.entries ?? []).map { "\($0.section)|\($0.key)|\($0.value)" } }

        // ---- IniFile ----
        do {
            let text = "; 주석\r\n[Highlight]\r\n size = 10 \r\nHideCursor=1\r\n[Hotkeys]\r\nDraw=F9"  // 마지막 줄에 줄 끝 없음
            let f = try! IniFile(data: Data(text.utf8))
            check("IniFile: 절·키는 대소문자와 앞뒤 공백을 무시", f.value("highlight", "SIZE") == "10", f.value("highlight", "SIZE") ?? "nil")
            var g = f
            g.set("Highlight", "Size", "10")
            check("IniFile: 같은 값이면 줄을 건드리지 않음", g.serialized() == f.serialized())
            g.set("Highlight", "Size", "20")
            g.set("Highlight", "Opacity", "40")   // 없는 키: 그 절의 마지막 항목 뒤
            g.set("Draw", "Color", "00FF00")      // 없는 절: 끝에 새로 만듦
            let out = String(data: g.serialized(), encoding: .utf8)!
            check("IniFile: 값만 바꾸고 모양(공백·주석·줄 끝)은 그대로",
                  out == "; 주석\r\n[Highlight]\r\n size = 20\r\nHideCursor=1\r\nOpacity=40\r\n[Hotkeys]\r\nDraw=F9\r\n[Draw]\r\nColor=00FF00\r\n", out)
            check("IniFile: 새 키는 그 절의 끝, 새 절은 파일 끝에 (줄 끝 없는 마지막 줄도 안전)",
                  out.contains("HideCursor=1\r\nOpacity=40\r\n[Hotkeys]") && out.hasSuffix("Draw=F9\r\n[Draw]\r\nColor=00FF00\r\n"), out)
        }
        do {
            let text = "[A]\nK=1\n"
            for (name, data, fmt, bom) in [
                ("UTF-8 BOM", Data([0xEF, 0xBB, 0xBF]) + Data(text.utf8), IniFile.Format.utf8, true),
                ("UTF-16 LE BOM", Data([0xFF, 0xFE]) + text.data(using: .utf16LittleEndian)!, .utf16LE, true),
                ("UTF-16 BE BOM", Data([0xFE, 0xFF]) + text.data(using: .utf16BigEndian)!, .utf16BE, true),
                ("UTF-16 LE (BOM 없음)", text.data(using: .utf16LittleEndian)!, .utf16LE, false),
                ("UTF-16 BE (BOM 없음)", text.data(using: .utf16BigEndian)!, .utf16BE, false),
            ] {
                var f = try? IniFile(data: data)
                let ok = f?.value("A", "K") == "1" && f?.format == fmt && f?.hasBOM == bom && f?.serialized() == data
                f?.set("A", "K", "2")
                let round = (try? IniFile(data: f?.serialized() ?? Data()))?.value("A", "K") == "2"
                    && (f?.serialized().starts(with: data.prefix(bom ? 2 : 0)) ?? false)
                check("IniFile: \(name)를 읽고 같은 인코딩으로 다시 씀", ok && round)
            }
            check("IniFile: 잘못된 글자 코드는 읽기를 거절", (try? IniFile(data: Data([0xC3, 0x28]))) == nil
                  && (try? IniFile(data: Data([0xFF, 0xFF, 0x00, 0x81, 0x00]))) == nil)
        }

        // ---- Windows 고정 파일 ----
        if let fixtures {
            let src = URL(fileURLWithPath: fixtures).appendingPathComponent("windows-settings.ini.txt")
            let original = bytes(src)
            check("고정 파일: windows-settings.ini.txt가 있고 UTF-16 LE (BOM, CRLF)",
                  original != nil && original!.starts(with: [0xFF, 0xFE]) && ini(src)?.format == .utf16LE)
            if let original {
                let path = dir.appendingPathComponent("settings.ini")
                try? original.write(to: path)
                let s = Settings()
                let r = s.load(from: path)
                var loaded = false; if case .loaded = r { loaded = true }
                check("Windows 파일을 제대로 읽음 (색·크기·위젯 자리·켜짐 표시)",
                      loaded && s.spotSize == 130 && s.spotOpacity == 40 && s.spotColor == 0xFF0000 && s.clickEffect && s.rclickEffect
                      && s.rclickColor == 0x0020FF && s.boardColors == [0xFFFFFF, 0x14472F, 0x000000] && s.widgetX == 1759 && s.widgetY == 992
                      && s.showWidget && s.drawKeyColors == Settings.defaultDrawKeys,
                      "size \(s.spotSize) x \(s.widgetX ?? -1) y \(s.widgetY ?? -1)")
                check("아무것도 안 바꾸고 저장하면 파일이 한 바이트도 안 바뀜", s.save(to: path) == nil && bytes(path) == original)

                s.spotSize = 150; s.drawColor = 0x00FF00
                check("설정을 바꿔 저장", s.save(to: path) == nil)
                let after = ini(path)
                let hot = after?.value("Hotkeys", "Draw") == "F9" && after?.value("Hotkeys", "Spotlight") == "F8"
                check("저장 뒤에도 [Hotkeys]·HideCursor·ShowTrayIcons가 남음", hot && after?.value("Highlight", "HideCursor") == "1"
                      && after?.value("Common", "ShowTrayIcons") == "0")
                check("저장 뒤 바뀐 값은 반영, 나머지 항목·순서는 그대로",
                      after?.value("Highlight", "Size") == "150" && after?.value("Draw", "Color") == "00FF00"
                      && entries(after).count == entries(ini(src)).count
                      && zip(entries(after), entries(ini(src))).filter { $0 != $1 }.count == 2)
                check("저장 뒤에도 UTF-16 LE·BOM·CRLF 그대로", after?.format == .utf16LE && after?.hasBOM == true
                      && !(String(data: bytes(path)!.dropFirst(2), encoding: .utf16LittleEndian) ?? "").replacingOccurrences(of: "\r\n", with: "").contains("\n"))

                // 위젯을 옮기면 WidgetX/Y 두 줄만 바뀐다
                try? original.write(to: path)
                let w = Settings(); w.load(from: path)
                w.saveWidgetPosition(NSPoint(x: 1759, y: 992), to: path)
                check("위젯이 안 움직였으면 파일을 안 씀", bytes(path) == original)
                w.spotSize = 77 // 저장하지 않은 값은 위젯 자리 저장에 섞여 들어가면 안 된다
                w.saveWidgetPosition(NSPoint(x: 100, y: 200), to: path)
                let moved = ini(path)
                check("위젯을 옮기면 WidgetX/Y만 바뀜 (저장 안 한 값은 안 섞임)",
                      moved?.value("Common", "WidgetX") == "100" && moved?.value("Common", "WidgetY") == "200"
                      && moved?.value("Highlight", "Size") == "130"
                      && zip(entries(moved), entries(ini(src))).filter { $0 != $1 }.count == 2
                      && moved?.value("Highlight", "HideCursor") == "1")
            }
        } else {
            check("Windows 고정 파일 점검을 건너뜀 (--fixtures 없음)", true, "INFO")
        }

        // ---- S11: 빈 파일, 잘린 파일, 아주 큰 파일 ----
        do {
            func tryLoad(_ name: String, _ data: Data) -> (Settings, Settings.LoadResult, URL) {
                let path = dir.appendingPathComponent("s11-\(name)/settings.ini")
                try? fm.createDirectory(at: path.deletingLastPathComponent(), withIntermediateDirectories: true)
                try? data.write(to: path)
                let s = Settings()
                return (s, s.load(from: path), path)
            }
            let (e, er, ep) = tryLoad("empty", Data())
            var emptyOK = false; if case .loaded = er { emptyOK = true }
            check("빈 파일: 기본값으로 시작하고 저장하면 정상 파일이 됨", emptyOK && e.spotSize == 130 && e.save(to: ep) == nil && (bytes(ep)?.isEmpty == false))
            let (_, tr, tp) = tryLoad("trunc16", Data([0xFF, 0xFE, 0x5B, 0x00, 0x43])) // UTF-16이 홀수 바이트에서 잘림
            var truncUnreadable = false; if case .unreadable = tr { truncUnreadable = true }
            check("잘린 UTF-16 파일: 읽을 수 없는 파일로 다루고 원본은 그대로", truncUnreadable && bytes(tp) == Data([0xFF, 0xFE, 0x5B, 0x00, 0x43]))
            let big = Data(repeating: 0x41, count: Settings.maxIniBytes + 1)
            let (bs, br, bp) = tryLoad("huge", big)
            var hugeUnreadable = false; if case .unreadable = br { hugeUnreadable = true }
            check("아주 큰 파일: 통째로 읽지 않고 읽을 수 없는 파일로 다루며 원본은 그대로", hugeUnreadable && bs.spotSize == 130 && bytes(bp) == big)
        }

        // ---- 읽을 수 없는 파일은 덮어쓰지 않는다 ----
        do {
            let path = dir.appendingPathComponent("broken/settings.ini")
            try? fm.createDirectory(at: path.deletingLastPathComponent(), withIntermediateDirectories: true)
            let junk = Data([0x5B, 0x44, 0x72, 0xC3, 0x28, 0xFF, 0xFE, 0x0A])
            try? junk.write(to: path)
            let s = Settings()
            let r = s.load(from: path)
            var bak: URL?, reason = ""
            if case .unreadable(let why, let b) = r { bak = b; reason = why }
            check("읽을 수 없는 파일: 기본값으로 시작하고 .bak 복사본을 남김", bak != nil && bytes(bak!) == junk && s.spotSize == 130, reason)
            check("읽을 수 없는 파일: 원본은 그대로", bytes(path) == junk)
            s.saveWidgetPosition(NSPoint(x: 5, y: 6), to: path)
            check("읽을 수 없는 파일: 위젯을 옮겨도 덮어쓰지 않음", bytes(path) == junk)
            let s2 = Settings()
            var bak2: URL?
            if case .unreadable(_, let b) = s2.load(from: path) { bak2 = b }
            check("읽을 수 없는 파일: 두 번째 복사본은 .bak2 (앞 복사본을 지우지 않음)",
                  bak2?.lastPathComponent == "settings.ini.bak2" && bytes(bak!) == junk)
            check("읽을 수 없는 파일: 안내 문구에 .bak과 '덮어쓰지 않' 설명이 있음",
                  Notice.unreadable(reason: reason, backup: bak).body.joined().contains("settings.ini.bak")
                  && Notice.unreadable(reason: reason, backup: bak).body.joined().contains("건드리지 않습니다"))
        }

        // ---- 값 검사 ----
        do {
            let path = dir.appendingPathComponent("bad-values.ini")
            let text = "[Highlight]\nSize=9999\nOpacity=nan\nColor=1FFFFFF\nClickColor=-1\nRClickColor=zzzzzz\n[DrawKeys]\nColor1=FFFFFF\nColor2= 0x00ff00 \n"
            try? Data(text.utf8).write(to: path)
            let s = Settings(); s.load(from: path)
            check("000000~FFFFFF 밖의 색과 글자는 기본값으로", s.spotColor == 0xFF0000 && s.clickColor == 0xFF0000 && s.rclickColor == 0x0020FF
                  && s.drawKeyColors[0] == 0xFFFFFF && s.drawKeyColors[1] == 0x00FF00, String(s.spotColor, radix: 16))
            check("범위를 벗어난 숫자는 끝값으로, 숫자가 아니면 기본값으로", s.spotSize == 200 && s.spotOpacity == 40, "\(s.spotSize) \(s.spotOpacity)")
        }

        // ---- 저장 실패 안내 ----
        do {
            let blocker = dir.appendingPathComponent("a-file")
            try? Data("x".utf8).write(to: blocker)
            let s = Settings()
            let e1 = s.save(to: blocker.appendingPathComponent("sub/settings.ini"))
            check("저장 실패(폴더를 못 만듦)를 알려 줌", e1 != nil)

            let ro = dir.appendingPathComponent("readonly", isDirectory: true)
            try? fm.createDirectory(at: ro, withIntermediateDirectories: true)
            let f = ro.appendingPathComponent("settings.ini")
            let good = Data("[Highlight]\nSize=111\n".utf8)
            try? good.write(to: f)
            try? fm.setAttributes([.posixPermissions: 0o500], ofItemAtPath: ro.path)
            let e2 = s.save(to: f)
            try? fm.setAttributes([.posixPermissions: 0o755], ofItemAtPath: ro.path)
            check("저장 실패(쓰기 거절)를 알려 주고 지난 파일은 그대로", e2 != nil && bytes(f) == good, "\(String(describing: e2))")
            if let e = e2 ?? e1 {
                let n = Notice.saveFailed(e)
                check("저장 실패 안내: 원인 → 할 일 → 안심 문구 → 맨 끝에 경로·오류",
                      n.body.count == 3 && n.body[1].contains("[저장]") && n.body[2].contains("바뀌지 않았습니다") && (n.detail ?? "").hasPrefix("설정 파일:")
                      && (n.detail ?? "").contains("오류:"))
            }
            let blocked = Settings()
            let junk = dir.appendingPathComponent("nobackup/settings.ini")
            try? fm.createDirectory(at: junk.deletingLastPathComponent(), withIntermediateDirectories: true)
            try? Data([0xC3, 0x28]).write(to: junk)
            try? fm.setAttributes([.posixPermissions: 0o500], ofItemAtPath: junk.deletingLastPathComponent().path) // .bak을 못 만드는 폴더
            var res = ""
            if case .unreadable(_, let b) = blocked.load(from: junk) { res = b == nil ? "nobackup" : "backup" }
            var saved: Settings.SaveError?; saved = blocked.save(to: junk)
            try? fm.setAttributes([.posixPermissions: 0o755], ofItemAtPath: junk.deletingLastPathComponent().path)
            var isBlocked = false; if case .blocked? = saved { isBlocked = true }
            check("복사본을 못 만들면 저장도 막아 원본을 지킴", res == "nobackup" && isBlocked && bytes(junk) == Data([0xC3, 0x28]), res)
        }

        // ---- 기록 (2 × 256KB) ----
        do {
            AppLog.folder = dir.appendingPathComponent("logs")
            let line = String(repeating: "가", count: 100)
            var t = Date(timeIntervalSince1970: 1_800_000_000)
            for i in 0..<3000 { AppLog.write("TEST", "\(i) \(line)", now: t); t.addTimeInterval(1) }
            let a = (try? fm.attributesOfItem(atPath: AppLog.url!.path))?[.size] as? Int ?? -1
            let b = (try? fm.attributesOfItem(atPath: AppLog.folder!.appendingPathComponent("app.1.log").path))?[.size] as? Int ?? -1
            let files = ((try? fm.contentsOfDirectory(atPath: AppLog.folder!.path)) ?? []).sorted()
            let tail = AppLog.tail(30)
            AppLog.folder = nil
            check("기록은 app.log·app.1.log 두 개, 각 256KB 이하", files == ["app.1.log", "app.log"] && a > 0 && a <= 256 * 1024 && b > 0 && b <= 256 * 1024,
                  "\(files) \(a) \(b)")
            check("기록 꼬리 30줄이 마지막 줄로 끝남", tail.count == 30 && tail.last?.contains("TEST 2999 ") == true, "\(tail.count)")
        }

        // ---- 진단 정보 ----
        do {
            let home = NSHomeDirectory(), user = NSUserName()
            let raw = "path \(home)/Library/x user \(user) file \(home)"
            let clean = DiagReport.sanitize(raw)
            check("진단: 홈 경로는 ~로, 사용자 이름은 가려짐", !clean.contains(home) && (user.count < 3 || !clean.lowercased().contains(user.lowercased())), clean)
            let custom = Settings(); custom.spotSize = 150; custom.drawColor = 0x00FF00
            let diffs = DiagReport.nonDefaultSettings(custom)
            check("진단: 기본값과 다른 설정만 나열", diffs.sorted() == ["Draw.Color=00FF00", "Highlight.Size=150"] && DiagReport.nonDefaultSettings(Settings()).isEmpty, "\(diffs)")
            let text = DiagReport.build(settings: custom, screens: [])
            let host = Host.current().localizedName ?? ""
            let leaks = [home, user, host].filter { $0.count >= 3 && text.lowercased().contains($0.lowercased()) }
            check("진단 글에 사용자·컴퓨터 이름과 전체 홈 경로가 없음", leaks.isEmpty, leaks.joined(separator: ", "))
            check("진단 글에 버전·macOS·모델·아키텍처·설정 경로가 있음",
                  text.contains("Focus & Draw \(AppInfo.version)") && text.contains("macOS:") && text.contains("모델:") && text.contains("아키텍처:")
                  && text.contains("설정 파일: ~"), String(text.prefix(200)))
        }

        // ---- 버전·안내 ----
        do {
            let v = AppInfo.version
            let parts = v.split(separator: ".")
            check("버전은 Info.plist 한 곳에서 읽음 (x.y.z)", parts.count == 3 && parts.allSatisfy { Int($0) != nil }, v)
            check("임시 자리(AppTranslocation) 실행을 알아봄",
                  Notice.isTranslocated("/private/var/folders/x/AppTranslocation/ABCD/d/Focus & Draw.app")
                  && !Notice.isTranslocated("/Applications/Focus & Draw.app"))
            let first = Notice.firstRun().body.joined()
            check("첫 실행 안내: 위젯 자리·메뉴 막대·fn+F8/F9·⌃⌥1·2", first.contains("오른쪽 아래") && first.contains("메뉴 막대") && first.contains("fn+F8")
                  && first.contains("fn+F9") && first.contains("⌃⌥1") && first.contains("⌃⌥2"))
        }
    }
}
