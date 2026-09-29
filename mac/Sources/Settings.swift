import AppKit
import SwiftUI

// Windows 판의 settings.ini와 같은 이름·같은 모양으로 저장한다.
// 다만 자리는 다르다 — 맥에서는 내려받은 앱이 읽기 전용 자리에서 실행되는 일이 많아서
// (격리된 다운로드는 임시 위치로 옮겨져 실행된다) 앱 옆이 아니라 사용자 폴더에 둔다.
//   ~/Library/Application Support/Focus & Draw/settings.ini

let APP_VERSION = "mac 0.1 (시험판)"

// 펜·지우개 굵기 단계 (Windows 판과 같은 표)
let STEP_MAX = 10
func penPx(_ step: Int) -> CGFloat { 3.0 * pow(1.3, CGFloat(max(1, min(STEP_MAX, step)) - 1)) }
func eraserPx(_ step: Int) -> CGFloat { 10.0 * pow(1.5, CGFloat(max(1, min(STEP_MAX, step)) - 1)) }

func color(_ rgb: UInt32, _ alpha: CGFloat = 1) -> NSColor {
    NSColor(srgbRed: CGFloat((rgb >> 16) & 0xFF) / 255, green: CGFloat((rgb >> 8) & 0xFF) / 255,
            blue: CGFloat(rgb & 0xFF) / 255, alpha: alpha)
}

func rgbOf(_ c: NSColor) -> UInt32 {
    guard let s = c.usingColorSpace(.sRGB) else { return 0 }
    func b(_ v: CGFloat) -> UInt32 { UInt32(max(0, min(255, (v * 255).rounded()))) }
    return (b(s.redComponent) << 16) | (b(s.greenComponent) << 8) | b(s.blueComponent)
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
    var boardColors: [UInt32] = [0xFFFFFF, 0x14472F, 0x000000]
    var boardAlphas: [Double] = [100, 100, 100]

    static let defaultDrawKeys: [UInt32] = [0xFF0000, 0xFF7F00, 0xFFFF00, 0x00FF00, 0x0000FF,
                                            0x4B0082, 0x9400D3, 0x000000, 0xFFFFFF]

    static var folder: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Focus & Draw", isDirectory: true)
    }
    static var overridePath: URL? // --settings <파일>: 자체 점검이 고정 파일만 읽게
    static var path: URL { overridePath ?? folder.appendingPathComponent("settings.ini") }

    // ---------- 읽기 ----------
    func load() {
        guard let text = try? String(contentsOf: Settings.path, encoding: .utf8) else { return }
        var ini: [String: [String: String]] = [:]
        var section = ""
        for raw in text.components(separatedBy: .newlines) {
            let line = raw.trimmingCharacters(in: .whitespaces)
            if line.hasPrefix("[") && line.hasSuffix("]") {
                section = String(line.dropFirst().dropLast())
            } else if let eq = line.firstIndex(of: "=") {
                ini[section, default: [:]][String(line[..<eq])] = String(line[line.index(after: eq)...])
            }
        }
        func num(_ s: String, _ k: String, _ d: Double, _ lo: Double, _ hi: Double) -> Double {
            guard let v = ini[s]?[k].flatMap(Double.init) else { return d }
            return max(lo, min(hi, v))
        }
        func hex(_ s: String, _ k: String, _ d: UInt32) -> UInt32 {
            ini[s]?[k].flatMap { UInt32($0, radix: 16) } ?? d
        }
        func flag(_ s: String, _ k: String, _ d: Bool) -> Bool {
            ini[s]?[k].map { $0 == "1" } ?? d
        }
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
        widgetX = ini["Common"]?["WidgetX"].flatMap(Double.init)
        widgetY = ini["Common"]?["WidgetY"].flatMap(Double.init)
        for i in 0..<9 {
            drawKeyColors[i] = hex("DrawKeys", "Color\(i + 1)", Settings.defaultDrawKeys[i])
            drawKeyAlphas[i] = num("DrawKeys", "Opacity\(i + 1)", 100, 5, 100)
        }
        for (i, k) in ["W", "E", "R"].enumerated() {
            boardColors[i] = hex("Boards", "Color\(k)", boardColors[i])
            boardAlphas[i] = num("Boards", "Opacity\(k)", 100, 5, 100)
        }
    }

    // ---------- 쓰기 ----------
    @discardableResult
    func save() -> Bool {
        func h(_ v: UInt32) -> String { String(format: "%06X", v) }
        func n(_ v: Double) -> String { String(Int(v.rounded())) }
        func b(_ v: Bool) -> String { v ? "1" : "0" }
        var s = "[Highlight]\n"
        s += "Size=\(n(spotSize))\nOpacity=\(n(spotOpacity))\nColor=\(h(spotColor))\n"
        s += "ClickEffect=\(b(clickEffect))\nRingThickness=\(n(clickThickness))\nClickSpeed=\(n(clickSpeed))\n"
        s += "ClickOpacity=\(n(clickOpacity))\nClickColor=\(h(clickColor))\n"
        s += "RClickEffect=\(b(rclickEffect))\nRClickThickness=\(n(rclickThickness))\nRClickSpeed=\(n(rclickSpeed))\n"
        s += "RClickOpacity=\(n(rclickOpacity))\nRClickColor=\(h(rclickColor))\n"
        s += "[Draw]\nOpacity=\(n(drawOpacity))\nColor=\(h(drawColor))\n"
        s += "ThicknessStep=\(n(drawStep))\nEraserStep=\(n(eraserStep))\n"
        s += "[Common]\nShowWidget=\(b(showWidget))\nWidgetScale=\(n(widgetScale))\n"
        s += "WidgetColor=\(h(widgetColor))\nWidgetOpacity=\(n(widgetOpacity))\n"
        if let x = widgetX, let y = widgetY { s += "WidgetX=\(n(x))\nWidgetY=\(n(y))\n" }
        s += "[DrawKeys]\n"
        for i in 0..<9 { s += "Color\(i + 1)=\(h(drawKeyColors[i]))\nOpacity\(i + 1)=\(n(drawKeyAlphas[i]))\n" }
        s += "[Boards]\n"
        for (i, k) in ["W", "E", "R"].enumerated() { s += "Color\(k)=\(h(boardColors[i]))\nOpacity\(k)=\(n(boardAlphas[i]))\n" }
        do {
            try FileManager.default.createDirectory(at: Settings.folder, withIntermediateDirectories: true)
            try s.write(to: Settings.path, atomically: true, encoding: .utf8)
            return true
        } catch {
            NSLog("settings save failed: \(error)")
            return false
        }
    }

    // 위젯 자리는 옮기는 즉시 기록한다 (Windows 판과 같음). 다른 값은 "저장"을 눌러야 남으므로,
    // 파일에 이미 적힌 값을 읽어와 자리만 바꿔 쓴다.
    func saveWidgetPosition(_ p: NSPoint) {
        let unsaved = Settings()
        unsaved.load()
        unsaved.widgetX = Double(p.x); unsaved.widgetY = Double(p.y)
        unsaved.save()
        widgetX = Double(p.x); widgetY = Double(p.y)
    }
}
