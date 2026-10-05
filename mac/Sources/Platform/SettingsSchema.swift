import Foundation

// 설정 항목표. 읽기·쓰기·"모두 초기화"·"Windows 키 목록과 같은가" 점검이 모두 이 표 하나를 쓴다.
// 칸: 절, 키, 형식(범위 포함), 기본값, Windows 뜻, 맥 뜻, 그리고 Settings의 어느 값에 닿는지(read/write).
// 기본값과 범위는 focus-draw.ahk의 LoadSettings와 같아야 한다 — Dev/SettingsSchemaTests.swift가 ahk를 읽어 견준다.
// 값은 모두 Double로 다룬다: 켬/끔은 0/1, 색은 0x000000~0xFFFFFF.

struct SettingKey {
    enum Kind {
        case int(ClosedRange<Double>)  // 정수로 저장, 범위 밖은 끝값으로
        case flag                      // 1이면 켬 (그 밖의 값은 끔)
        case color                     // 000000~FFFFFF (16진 6자리, #·0x 허용). 밖이면 기본값
    }
    let section: String
    let key: String
    let kind: Kind
    let defaultValue: Double
    let windows: String   // Windows 판에서의 뜻
    let mac: String       // 맥 판에서의 뜻
    let read: (Settings) -> Double
    let write: (Settings, Double) -> Void

    var id: String { "\(section).\(key)" }

    // 파일의 글자 → 값. 못 읽으면 nil (부르는 쪽이 기본값을 쓴다). 범위 밖 숫자는 끝값으로 자른다.
    func parse(_ text: String?) -> Double? {
        switch kind {
        case .int(let r):
            guard let v = text.flatMap({ Double($0.trimmingCharacters(in: .whitespaces)) }), v.isFinite else { return nil }
            return max(r.lowerBound, min(r.upperBound, v))
        case .flag:
            return text.map { $0.trimmingCharacters(in: .whitespaces) == "1" ? 1 : 0 }
        case .color:
            return Settings.parseColor(text).map(Double.init)
        }
    }

    // 값 → 파일에 쓰는 글자 (Windows 판과 같은 모양)
    func format(_ v: Double) -> String {
        switch kind {
        case .int: return String(Int(v.rounded()))
        case .flag: return v >= 1 ? "1" : "0"
        case .color: return String(format: "%06X", UInt32(max(0, min(16_777_215, v))))
        }
    }
}

enum SettingsSchema {
    // ---- 행을 만드는 도우미 ----
    private static func num(_ s: String, _ k: String, _ kp: ReferenceWritableKeyPath<Settings, Double>, _ d: Double,
                            _ r: ClosedRange<Double>, win: String = "같음", mac: String = "같음") -> SettingKey {
        SettingKey(section: s, key: k, kind: .int(r), defaultValue: d, windows: win, mac: mac,
                   read: { $0[keyPath: kp] }, write: { $0[keyPath: kp] = $1 })
    }
    private static func flag(_ s: String, _ k: String, _ kp: ReferenceWritableKeyPath<Settings, Bool>, _ d: Bool,
                             win: String = "같음", mac: String = "같음") -> SettingKey {
        SettingKey(section: s, key: k, kind: .flag, defaultValue: d ? 1 : 0, windows: win, mac: mac,
                   read: { $0[keyPath: kp] ? 1 : 0 }, write: { $0[keyPath: kp] = $1 >= 1 })
    }
    private static func color(_ s: String, _ k: String, _ kp: ReferenceWritableKeyPath<Settings, UInt32>, _ d: UInt32,
                              win: String = "같음", mac: String = "같음") -> SettingKey {
        SettingKey(section: s, key: k, kind: .color, defaultValue: Double(d), windows: win, mac: mac,
                   read: { Double($0[keyPath: kp]) }, write: { $0[keyPath: kp] = UInt32($1) })
    }

    // ---- 표 ----
    static let keys: [SettingKey] = {
        var t: [SettingKey] = [
            num("Highlight", "Size", \.spotSize, 130, 30...200, win: "강조 원 지름(px)", mac: "강조 원 지름(pt)"),
            num("Highlight", "Opacity", \.spotOpacity, 40, 0...100),
            color("Highlight", "Color", \.spotColor, 0xFF0000),
            flag("Highlight", "ClickEffect", \.clickEffect, true),
            num("Highlight", "RingThickness", \.clickThickness, 7, 2...12),
            num("Highlight", "ClickSpeed", \.clickSpeed, 26, 1...30),
            num("Highlight", "ClickOpacity", \.clickOpacity, 50, 0...100),
            color("Highlight", "ClickColor", \.clickColor, 0xFF0000),
            flag("Highlight", "RClickEffect", \.rclickEffect, false),
            num("Highlight", "RClickThickness", \.rclickThickness, 7, 2...12),
            num("Highlight", "RClickSpeed", \.rclickSpeed, 26, 1...30),
            num("Highlight", "RClickOpacity", \.rclickOpacity, 50, 0...100),
            color("Highlight", "RClickColor", \.rclickColor, 0x0020FF),
            num("Draw", "Opacity", \.drawOpacity, 100, 0...100),
            color("Draw", "Color", \.drawColor, 0xFF0000),
            num("Draw", "ThicknessStep", \.drawStep, 5, 1...Double(STEP_MAX)),
            num("Draw", "EraserStep", \.eraserStep, 5, 1...Double(STEP_MAX)),
            num("Draw", "LaserHold", \.laserHold, LASER_HOLD * 1000, 0...3000),
            num("Draw", "LaserFade", \.laserFade, LASER_FADE * 1000, 100...3000),
            num("Draw", "LaserGlow", \.laserGlow, 100, 0...200),
            flag("Common", "ShowWidget", \.showWidget, true),
            flag("Common", "ShowTrayIcons", \.showTrayIcons, false),
            num("Common", "WidgetScale", \.widgetScale, 100, 60...250),
            color("Common", "WidgetColor", \.widgetColor, 0xF2F2F2),
            num("Common", "WidgetOpacity", \.widgetOpacity, 100, 20...100),
        ]
        for i in 0..<9 {
            t.append(color("DrawKeys", "Color\(i + 1)", \.drawKeyColors[i], DRAW_COLORS[i]))
            t.append(num("DrawKeys", "Opacity\(i + 1)", \.drawKeyAlphas[i], 100, 5...100))
        }
        for (i, k) in ["W", "E", "R"].enumerated() {
            t.append(color("Boards", "Color\(k)", \.boardColors[i], BOARD_COLORS[i]))
            t.append(num("Boards", "Opacity\(k)", \.boardAlphas[i], 100, 5...100))
        }
        return t
    }()

    // 위젯 자리: 한 번도 안 옮겼으면 빈 값 (표의 숫자 행이 아니라 Settings.widgetX/Y가 따로 든다)
    //   Windows: 화면 왼쪽 위 기준 px. 맥: 왼쪽 아래 기준 pt를 그대로 적는다 (같은 파일을 두 판이 쓰면 자리가 서로 어긋날 수 있다).
    static let positionKeys: [(section: String, key: String)] = [("Common", "WidgetX"), ("Common", "WidgetY")]

    // Windows 판만 쓰는 키: 맥은 읽지도 지우지도 않는다(IniFile이 그대로 보존한다)
    // 맥에서 먼저 넣은 키 (Windows 판은 mac/design/windows-todo.md를 보고 같은 이름으로 따라온다).
    // 파일에 없고 기본값이면 쓰지 않는다 — Windows 파일에 맥 전용 줄을 공연히 늘리지 않는다 ([Hotkeys]와 같은 규칙).
    static let macFirst: Set<String> = ["Draw.LaserHold", "Draw.LaserFade", "Draw.LaserGlow"]
    static let windowsOnly: Set<String> = ["Highlight.HideCursor"]
    // ahk가 예전 파일을 읽으려고 받아 주는 옛 키
    static let windowsLegacy: Set<String> = ["Common.Color", "Draw.Thickness", "Draw.EraserSize"]

    // [Hotkeys]: AHK 표기로 읽고 쓴다. (이름, 기본값, 맥에서만 쓰는가)
    static let hotkeys: [(name: String, def: String, macOnly: Bool)] = [
        ("Spotlight", "F8", false), ("Draw", "F9", false),
        ("SpotlightAlt", "^!1", true), ("DrawAlt", "^!2", true),
    ]
    static var hotkeyDefaults: [String: String] { Dictionary(uniqueKeysWithValues: hotkeys.map { ($0.name, $0.def) }) }

    static func key(_ section: String, _ key: String) -> SettingKey? { keys.first { $0.section == section && $0.key == key } }
}
