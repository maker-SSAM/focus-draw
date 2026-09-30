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
        func num(_ s: String, _ k: String, _ d: Double, _ lo: Double, _ hi: Double) -> Double {
            guard let v = ini.value(s, k).flatMap(Double.init), v.isFinite else { return d }
            return max(lo, min(hi, v))
        }
        func hex(_ s: String, _ k: String, _ d: UInt32) -> UInt32 { Settings.parseColor(ini.value(s, k)) ?? d }
        func flag(_ s: String, _ k: String, _ d: Bool) -> Bool { ini.value(s, k).map { $0 == "1" } ?? d }
        spotSize = num("Highlight", "Size", 130, 30, 200)
        spotOpacity = num("Highlight", "Opacity", 40, 0, 100)
        spotColor = hex("Highlight", "Color", 0xFF0000)
        clickEffect = flag("Highlight", "ClickEffect", true)
        clickThickness = num("Highlight", "RingThickness", 7, 2, 12)
        clickSpeed = num("Highlight", "ClickSpeed", 26, 1, 30)
        clickOpacity = num("Highlight", "ClickOpacity", 50, 0, 100)
        clickColor = hex("Highlight", "ClickColor", 0xFF0000)
        rclickEffect = flag("Highlight", "RClickEffect", false)
        rclickThickness = num("Highlight", "RClickThickness", 7, 2, 12)
        rclickSpeed = num("Highlight", "RClickSpeed", 26, 1, 30)
        rclickOpacity = num("Highlight", "RClickOpacity", 50, 0, 100)
        rclickColor = hex("Highlight", "RClickColor", 0x0020FF)
        drawOpacity = num("Draw", "Opacity", 100, 0, 100)
        drawColor = hex("Draw", "Color", 0xFF0000)
        drawStep = num("Draw", "ThicknessStep", 5, 1, 10)
        eraserStep = num("Draw", "EraserStep", 5, 1, 10)
        showWidget = flag("Common", "ShowWidget", true)
        widgetScale = num("Common", "WidgetScale", 100, 60, 250)
        widgetColor = hex("Common", "WidgetColor", 0xF2F2F2)
        widgetOpacity = num("Common", "WidgetOpacity", 100, 20, 100)
        widgetX = ini.value("Common", "WidgetX").flatMap(Double.init).flatMap { $0.isFinite ? $0 : nil }
        widgetY = ini.value("Common", "WidgetY").flatMap(Double.init).flatMap { $0.isFinite ? $0 : nil }
        for i in 0..<9 {
            drawKeyColors[i] = hex("DrawKeys", "Color\(i + 1)", Settings.defaultDrawKeys[i])
            drawKeyAlphas[i] = num("DrawKeys", "Opacity\(i + 1)", 100, 5, 100)
        }
        for (i, k) in ["W", "E", "R"].enumerated() {
            boardColors[i] = hex("Boards", "Color\(k)", Settings.defaultBoardColors[i])
            boardAlphas[i] = num("Boards", "Opacity\(k)", 100, 5, 100)
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
        func h(_ v: UInt32) -> String { String(format: "%06X", v) }
        func n(_ v: Double) -> String { String(Int(v.rounded())) }
        func b(_ v: Bool) -> String { v ? "1" : "0" }
        var p: [(String, String, String)] = [
            ("Highlight", "Size", n(spotSize)), ("Highlight", "Opacity", n(spotOpacity)), ("Highlight", "Color", h(spotColor)),
            ("Highlight", "ClickEffect", b(clickEffect)), ("Highlight", "RingThickness", n(clickThickness)),
            ("Highlight", "ClickSpeed", n(clickSpeed)), ("Highlight", "ClickOpacity", n(clickOpacity)),
            ("Highlight", "ClickColor", h(clickColor)),
            ("Highlight", "RClickEffect", b(rclickEffect)), ("Highlight", "RClickThickness", n(rclickThickness)),
            ("Highlight", "RClickSpeed", n(rclickSpeed)), ("Highlight", "RClickOpacity", n(rclickOpacity)),
            ("Highlight", "RClickColor", h(rclickColor)),
            ("Draw", "Opacity", n(drawOpacity)), ("Draw", "Color", h(drawColor)),
            ("Draw", "ThicknessStep", n(drawStep)), ("Draw", "EraserStep", n(eraserStep)),
            ("Common", "ShowWidget", b(showWidget)), ("Common", "WidgetScale", n(widgetScale)),
            ("Common", "WidgetColor", h(widgetColor)), ("Common", "WidgetOpacity", n(widgetOpacity)),
        ]
        for i in 0..<9 {
            p.append(("DrawKeys", "Color\(i + 1)", h(drawKeyColors[i])))
            p.append(("DrawKeys", "Opacity\(i + 1)", n(drawKeyAlphas[i])))
        }
        for (i, k) in ["W", "E", "R"].enumerated() {
            p.append(("Boards", "Color\(k)", h(boardColors[i])))
            p.append(("Boards", "Opacity\(k)", n(boardAlphas[i])))
        }
        return p
    }

    // 지금 디스크의 파일을 다시 읽어 아는 값만 바꿔 쓴다: 모르는 항목·주석·순서·인코딩은 그대로.
    // 성공하면 nil, 실패하면 이유.
    @discardableResult
    func save(to url: URL = Settings.path) -> SaveError? {
        if writeBlocked { return .blocked }
        var f = Settings.readIni(url).ini ?? IniFile()
        for (s, k, v) in pairs() { f.set(s, k, v) }
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
