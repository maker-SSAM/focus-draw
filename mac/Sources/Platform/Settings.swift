import AppKit
import SwiftUI

// Windows 판의 settings.ini와 같은 이름·같은 모양으로 저장한다.
// 다만 자리는 다르다 — 맥에서는 내려받은 앱이 읽기 전용 자리에서 실행되는 일이 많아서
// (격리된 다운로드는 임시 위치로 옮겨져 실행된다) 앱 옆이 아니라 사용자 폴더에 둔다.
//   ~/Library/Application Support/Focus & Draw/settings.ini

enum AppInfo {
    // 버전은 Info.plist 한 곳에서만 읽는다
    static var version: String { (Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String) ?? "?" }
    static var displayVersion: String { "\(version) (시험판)" }
}

final class Settings: ObservableObject {
    static let shared = Settings()

    // [Highlight]
    @Published var spotSize: Double = 130
    @Published var spotOpacity: Double = 40
    @Published var spotColor: UInt32 = 0xFF0000
    @Published var clickEffect = true
    @Published var clickThickness: Double = 7
    @Published var clickSpeed: Double = 26
    @Published var clickOpacity: Double = 50
    @Published var clickColor: UInt32 = 0xFF0000
    @Published var rclickEffect = false
    @Published var rclickThickness: Double = 7
    @Published var rclickSpeed: Double = 26
    @Published var rclickOpacity: Double = 50
    @Published var rclickColor: UInt32 = 0x0020FF
    // [Draw]
    @Published var drawOpacity: Double = 100
    @Published var drawColor: UInt32 = 0xFF0000
    @Published var drawStep: Double = 5
    @Published var eraserStep: Double = 5
    // [Common]
    @Published var showWidget = true
    @Published var widgetScale: Double = 100
    @Published var widgetColor: UInt32 = 0xF2F2F2
    @Published var widgetOpacity: Double = 100
    var widgetX: Double? = nil
    var widgetY: Double? = nil
    // [Hotkeys]: AHK 표기 그대로 든다 (Platform/HotkeyNotation.swift가 읽는다)
    var hotkeys: [String: String] = SettingsSchema.hotkeyDefaults
    // [DrawKeys] 1~9, [Boards] W/E/R
    var drawKeyColors: [UInt32] = Settings.defaultDrawKeys
    var drawKeyAlphas: [Double] = Array(repeating: 100, count: 9)
    var boardColors: [UInt32] = Settings.defaultBoardColors
    var boardAlphas: [Double] = [100, 100, 100]

    static let defaultBoardColors: [UInt32] = BOARD_COLORS
    static let defaultDrawKeys: [UInt32] = DRAW_COLORS

    static var folder: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Focus & Draw", isDirectory: true)
    }
    static var overridePath: URL? // --settings <파일>: 자체 점검이 고정 파일만 읽게
    static var path: URL { overridePath ?? folder.appendingPathComponent("settings.ini") }

    // ---------- 읽기 ----------
    enum LoadResult {
        case missing                                   // 설정 파일이 아직 없음 (첫 실행)
        case loaded
        case unreadable(reason: String, backup: URL?)  // 읽을 수 없음: 기본값으로 시작, 원본은 그대로 두고 복사본을 남김
    }
    // 읽을 수 없는 파일이 있는 동안에는 위젯 자리 같은 자동 저장이 그 파일을 덮어쓰지 않는다 (설정 창의 "저장"만 덮어쓴다)
    private(set) var unreadable = false
    private(set) var writeBlocked = false // 복사본조차 못 만들었으면 "저장"도 덮어쓰지 않는다

    static func parseColor(_ s: String?) -> UInt32? {
        guard var t = s?.trimmingCharacters(in: .whitespaces), !t.isEmpty else { return nil }
        if t.hasPrefix("#") { t.removeFirst() } else if t.lowercased().hasPrefix("0x") { t.removeFirst(2) }
        guard t.count <= 6, let v = UInt32(t, radix: 16) else { return nil } // 000000~FFFFFF 밖은 기본값으로
        return v
    }

    // 파일 → IniFile. 없으면 (nil, missing), 읽을 수 없으면 (nil, 이유)
    static func readIni(_ url: URL) -> (ini: IniFile?, problem: String?, missing: Bool) {
        guard FileManager.default.fileExists(atPath: url.path) else { return (nil, nil, true) }
        do {
            let data = try Data(contentsOf: url)
            return (try IniFile(data: data), nil, false)
        } catch {
            return (nil, "\(error)", false)
        }
    }

    @discardableResult
    func load(from url: URL = Settings.path) -> LoadResult {
        unreadable = false; writeBlocked = false
        let r = Settings.readIni(url)
        if r.missing { return .missing }
        guard let ini = r.ini else {
            unreadable = true
            let backup = Settings.keepBackup(of: url)
            writeBlocked = backup == nil
            AppLog.write("SETTINGS", "unreadable: \(r.problem ?? "?") backup=\(backup?.lastPathComponent ?? "failed")")
            return .unreadable(reason: r.problem ?? "알 수 없음", backup: backup)
        }
        // 항목표(SettingsSchema)대로 읽는다: 못 읽는 값은 기본값, 범위 밖 숫자는 끝값
        for k in SettingsSchema.keys { k.write(self, k.parse(ini.value(k.section, k.key)) ?? k.defaultValue) }
        widgetX = ini.value("Common", "WidgetX").flatMap(Double.init).flatMap { $0.isFinite ? $0 : nil }
        widgetY = ini.value("Common", "WidgetY").flatMap(Double.init).flatMap { $0.isFinite ? $0 : nil }
        // 단축키: 알아볼 수 없거나 ⌃·⌥ 없이 위험한 조합이면 기본값으로 (단축키가 하나도 안 먹는 채로 시작하지 않게)
        for h in SettingsSchema.hotkeys {
            let text = ini.value("Hotkeys", h.name) ?? h.def
            hotkeys[h.name] = HotkeyNotation.parse(text).map(HotkeyNotation.isSafe) == true ? text : h.def
        }
        return .loaded
    }

    // 읽을 수 없는 파일을 settings.ini.bak(이미 있으면 .bak2, .bak3 …)으로 복사해 둔다
    static func keepBackup(of url: URL) -> URL? {
        let fm = FileManager.default
        for n in 1...20 {
            let dest = url.deletingLastPathComponent()
                .appendingPathComponent(url.lastPathComponent + (n == 1 ? ".bak" : ".bak\(n)"))
            if fm.fileExists(atPath: dest.path) { continue }
            do { try fm.copyItem(at: url, to: dest); return dest } catch { return nil }
        }
        return nil
    }

    // ---------- 쓰기 ----------
    enum SaveError: Error {
        case blocked                 // 읽을 수 없는 파일의 복사본을 못 만들어서, 원본을 지키려고 저장하지 않음
        case folder(Error)
        case write(Error)
        var underlying: Error? {
            switch self { case .blocked: return nil; case .folder(let e), .write(let e): return e }
        }
    }

    // 지금 값들 (절, 키, 문자열). 저장과 진단이 함께 쓴다.
    func pairs() -> [(String, String, String)] {
        var p = SettingsSchema.keys.map { ($0.section, $0.key, $0.format($0.read(self))) }
        for h in SettingsSchema.hotkeys { p.append(("Hotkeys", h.name, hotkeys[h.name] ?? h.def)) }
        return p
    }

    // "모두 초기화": 표의 기본값으로 돌린다. 위젯 자리는 비운다(다시 오른쪽 아래에서 시작).
    func resetToDefaults() {
        for k in SettingsSchema.keys { k.write(self, k.defaultValue) }
        widgetX = nil; widgetY = nil
        hotkeys = SettingsSchema.hotkeyDefaults
    }

    // "모든 설정 초기화": 설정 파일을 지우고(없으면 그대로) 기본값으로 돌린다. 지우지 못하면 아무것도 바꾸지 않고 오류를 돌려준다.
    // 읽을 수 없어서 막아 두었던 저장도 풀린다 (파일이 사라졌으므로). 로그인 항목은 건드리지 않는다.
    func resetAll(at url: URL = Settings.path) -> Error? {
        if FileManager.default.fileExists(atPath: url.path) {
            do { try FileManager.default.removeItem(at: url) } catch {
                AppLog.write("SETTINGS", "reset failed: \(error)")
                return error
            }
        }
        load(from: url)
        resetToDefaults()
        objectWillChange.send() // 배열·단축키처럼 @Published가 아닌 값도 화면이 다시 읽게
        return nil
    }

    // 지금 디스크의 파일을 다시 읽어 아는 값만 바꿔 쓴다: 모르는 항목·주석·순서·인코딩은 그대로.
    // 성공하면 nil, 실패하면 이유.
    @discardableResult
    func save(to url: URL = Settings.path) -> SaveError? {
        if writeBlocked { return .blocked }
        var f = Settings.readIni(url).ini ?? IniFile()
        for (s, k, v) in pairs() {
            // [Hotkeys]는 기본값이고 파일에도 없으면 쓰지 않는다 (Windows 파일에 맥 전용 줄을 공연히 늘리지 않는다)
            if s == "Hotkeys", f.value(s, k) == nil, v == SettingsSchema.hotkeyDefaults[k] { continue }
            f.set(s, k, v)
        }
        if let x = widgetX, let y = widgetY {
            f.set("Common", "WidgetX", String(Int(x.rounded()))); f.set("Common", "WidgetY", String(Int(y.rounded())))
        }
        return Settings.write(f, to: url)
    }

    static func write(_ f: IniFile, to url: URL) -> SaveError? {
        do {
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        } catch {
            AppLog.write("SETTINGS", "save failed (folder): \(error)")
            return .folder(error)
        }
        do {
            try f.serialized().write(to: url, options: .atomic) // 실패해도 지난 파일은 그대로 남는다
            return nil
        } catch {
            AppLog.write("SETTINGS", "save failed (write): \(error)")
            return .write(error)
        }
    }

    // 위젯 자리는 옮기는 즉시 기록한다 (Windows 판과 같음). 다른 값은 "저장"을 눌러야 남으므로
    // 파일을 다시 읽어 WidgetX/Y 두 줄만 바꿔 쓴다. 실제로 자리가 달라졌을 때만 쓴다.
    func saveWidgetPosition(_ p: NSPoint, to url: URL = Settings.path) {
        let x = Double(p.x), y = Double(p.y)
        if let ox = widgetX, let oy = widgetY, Int(ox.rounded()) == Int(x.rounded()), Int(oy.rounded()) == Int(y.rounded()) { return }
        widgetX = x; widgetY = y
        if unreadable { return } // 읽을 수 없는 파일은 "저장"을 누를 때까지 건드리지 않는다
        var f = Settings.readIni(url).ini ?? IniFile()
        f.set("Common", "WidgetX", String(Int(x.rounded()))); f.set("Common", "WidgetY", String(Int(y.rounded())))
        _ = Settings.write(f, to: url) // 실패는 기록만 남긴다 (드래그할 때마다 안내 창을 띄우지 않는다)
    }
}

// 그리기 코드에 넘기는 복사본 (그리기 코드는 Settings.shared를 읽지 않는다)
extension DrawConfig {
    init(_ s: Settings) {
        self.init(drawOpacity: s.drawOpacity, drawColor: s.drawColor, drawStep: Int(s.drawStep), eraserStep: Int(s.eraserStep),
                  drawKeyColors: s.drawKeyColors, drawKeyAlphas: s.drawKeyAlphas,
                  boardColors: s.boardColors, boardAlphas: s.boardAlphas)
    }
}
