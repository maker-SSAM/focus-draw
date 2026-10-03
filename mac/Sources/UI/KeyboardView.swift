import AppKit
import SwiftUI

// "드로잉 모드 단축키 보기": 맥 자판 그림. 줄마다 역할이 같다 — 숫자 줄 = 색, Q 줄 = 칠판, A 줄 = 특수 펜, Z 줄 = 도형.
// 색은 늘 지금 설정의 색이다 (설정에서 3번을 바꾸고 다시 열면 새 색). 키 표(KeyMap)와 설정이 바뀌면 이 그림도 따라가도록
// 역할 글은 한곳(KeyboardLayout)에 모았다.
//
// [Windows 판에서 가져온 것] 기능 묶음마다 키 테두리 색을 달리하고(색 파랑·칠판 초록·도형 보라·굵기 주황·지우기 빨강·펜 분홍) 맨 위에
// 같은 색의 범례 띠를 둔 것, 아래 설명을 "키 → 하는 일" 두 칸 표로 묶은 것. (Windows는 키보드 그림이 고정 PNG라
// 키 위에는 기본 색을 그려 두고 "지금 설정된 색"은 그림 아래 띠로 따로 보여 준다. 맥은 키 위 색 막대가 지금 설정을 그대로 따라간다.)

enum KeyboardLayout {
    enum Group: CaseIterable {
        case color, board, shape, size, clear, pen
        var title: String { switch self { case .color: "색 바꾸기"; case .board: "칠판"; case .shape: "도형"; case .size: "선 굵기"; case .clear: "지우기"; case .pen: "특수 펜" } }
        var keys: String { switch self { case .color: "0 ~ 9"; case .board: "Q W E R"; case .shape: "Z X C · ⇧ ⌃"; case .size: "− ="; case .clear: "delete · esc · ⌥"; case .pen: "A S" } }
        var tint: Color { switch self {
            case .color: Color(red: 0.25, green: 0.56, blue: 0.95); case .board: Color(red: 0.2, green: 0.7, blue: 0.45)
            case .shape: Color(red: 0.62, green: 0.4, blue: 0.9); case .size: Color(red: 0.92, green: 0.62, blue: 0.2)
            case .clear: Color(red: 0.95, green: 0.38, blue: 0.33); case .pen: Color(red: 0.9, green: 0.4, blue: 0.65) } }
    }
    enum Bar { case checker, laser, rainbow, line, wave, arrow, rect, ellipse, eraser }
    struct Cap: Identifiable {
        let id = UUID()
        let label: String
        var role = ""
        var rgb: UInt32? = nil       // 색 칸 (숫자키·칠판)
        var alpha: Double = 1
        var bar: Bar? = nil          // 색이 아닌 펜·칠판의 모양 막대
        var width: CGFloat = 1       // 1 = 보통 키
        var active = true            // 드로잉에서 쓰는 키면 true
        var height: CGFloat = 1      // 1 = 보통 키 (기능 줄·위아래 화살표는 더 낮다)
        var subs: [Cap] = []         // 위아래 화살표처럼 세로로 쌓은 칸
        // 기능 묶음 (쓰는 키만): 테두리 색과 범례
        var group: Group? {
            guard active else { return nil }
            switch label {
            case "0", "1", "2", "3", "4", "5", "6", "7", "8", "9": return .color
            case "Q", "W", "E", "R": return .board
            case "Z", "X", "C", "shift", "control": return .shape
            case "−", "=": return .size
            case "delete", "esc", "option": return .clear
            case "A", "S": return .pen
            default: return nil
            }
        }
    }

    // 맥북 자판(ANSI) 배열과 키 폭을 그대로 옮긴다. 한 줄은 폭 15칸.
    static func rows(_ s: Settings) -> [[Cap]] {
        func digit(_ i: Int) -> Cap { Cap(label: "\(i)", role: "색 \(i)", rgb: s.drawKeyColors[i - 1], alpha: s.drawKeyAlphas[i - 1] / 100) }
        func plain(_ chars: String) -> [Cap] { chars.map { Cap(label: String($0), active: false) } }
        func mod(_ label: String, _ w: CGFloat = 1) -> Cap { Cap(label: label, width: w, active: false) }
        let fn: [Cap] = [Cap(label: "esc", role: "지우고 끝내기", width: 1.5, height: 0.8)]
            + (1...12).map { Cap(label: "F\($0)", active: false, height: 0.8) } + [Cap(label: "", active: false, height: 0.8)]
        var r1: [Cap] = [Cap(label: "`", active: false)]
        r1 += (1...9).map(digit)
        r1 += [Cap(label: "0", role: "기본 색", rgb: s.drawColor, alpha: s.drawOpacity / 100),
               Cap(label: "−", role: "가늘게"), Cap(label: "=", role: "굵게"),
               Cap(label: "delete", role: "전부 지움", width: 2)]
        let r2: [Cap] = [mod("tab", 1.5),
            Cap(label: "Q", role: "투명 칠판", bar: .checker),
            Cap(label: "W", role: "흰 칠판", rgb: s.boardColors[0], alpha: s.boardAlphas[0] / 100),
            Cap(label: "E", role: "초록 칠판", rgb: s.boardColors[1], alpha: s.boardAlphas[1] / 100),
            Cap(label: "R", role: "검정 칠판", rgb: s.boardColors[2], alpha: s.boardAlphas[2] / 100),
        ] + plain("TYUIOP[]") + [mod("\\", 1.5)]
        let r3: [Cap] = [mod("caps lock", 1.75), Cap(label: "A", role: "레이저 펜", rgb: s.drawColor, bar: .laser), Cap(label: "S", role: "무지개 펜", bar: .rainbow)]
            + plain("DFGHJKL;'") + [mod("return", 2.25)]
        let shiftL = Cap(label: "shift", role: "사각형", bar: .rect, width: 2.25)
        let shiftR = Cap(label: "shift", role: "사각형", bar: .rect, width: 2.75)
        let r4: [Cap] = [shiftL, Cap(label: "Z", role: "직선", bar: .line), Cap(label: "X", role: "물결", bar: .wave), Cap(label: "C", role: "화살표", bar: .arrow)]
            + plain("VBNM,./") + [shiftR]
        // 맨 아래 줄: ⌃ = 원, ⌥ = 지우개 (끌면서 함께 누르는 키)
        let r5: [Cap] = [mod("fn"), Cap(label: "control", role: "원", bar: .ellipse), Cap(label: "option", role: "지우개", bar: .eraser), mod("command", 1.25),
                         mod("space", 5), mod("command", 1.25), Cap(label: "option", role: "지우개", bar: .eraser),
                         mod("←"), Cap(label: "", active: false, height: 1, subs: [Cap(label: "↑", active: false, height: 0.5), Cap(label: "↓", active: false, height: 0.5)]), mod("→")]
        return [fn, r1, r2, r3, r4, r5]
    }
    static let natural = CGSize(width: 980, height: 700)
}

// 투명 칠판 = 체크무늬, 레이저 펜 = 지금 펜 색이 꼬리처럼 사라지는 띠, 무지개 펜 = 무지개 띠
@ViewBuilder private func barView(_ bar: KeyboardLayout.Bar, _ cap: KeyboardLayout.Cap) -> some View {
    switch bar {
    case .checker:
        Canvas { ctx, size in
            let n: CGFloat = 4
            for yi in 0..<Int(ceil(size.height / n)) {
                for xi in 0..<Int(ceil(size.width / n)) {
                    let c = (xi + yi) % 2 == 0 ? Color(white: 0.85) : Color(white: 0.6)
                    ctx.fill(Path(CGRect(x: CGFloat(xi) * n, y: CGFloat(yi) * n, width: n, height: n)), with: .color(c))
                }
            }
        }
    case .laser:
        LinearGradient(colors: [Color(nsColor: color(cap.rgb ?? 0xFF0000)), Color(nsColor: color(cap.rgb ?? 0xFF0000)).opacity(0)],
                       startPoint: .leading, endPoint: .trailing)
    case .line, .wave, .arrow, .rect, .ellipse, .eraser:
        shapeGlyph(bar)
    case .rainbow:
        LinearGradient(colors: stride(from: 0.0, through: 1.0, by: 1.0 / 6).map { Color(hue: $0, saturation: 0.85, brightness: 1) },
                       startPoint: .leading, endPoint: .trailing)
    }
}

// 도형 키의 작은 그림: 직선·물결·화살표·사각형·원 (선 색은 글자색)
private func shapeGlyph(_ bar: KeyboardLayout.Bar) -> some View {
    Canvas { ctx, size in
        let w = size.width, h = size.height, m = h / 2
        var p = Path()
        switch bar {
        case .line:
            p.move(to: CGPoint(x: 2, y: m)); p.addLine(to: CGPoint(x: w - 2, y: m))
        case .wave:
            p.move(to: CGPoint(x: 2, y: m))
            var x: CGFloat = 2
            while x < w - 2 {
                let nx = min(x + 8, w - 2)
                p.addQuadCurve(to: CGPoint(x: nx, y: m), control: CGPoint(x: (x + nx) / 2, y: ((Int((x - 2) / 8) % 2) == 0) ? 0 : h))
                x = nx
            }
        case .arrow:
            p.move(to: CGPoint(x: 2, y: m)); p.addLine(to: CGPoint(x: w - 3, y: m))
            p.move(to: CGPoint(x: w - 9, y: 1)); p.addLine(to: CGPoint(x: w - 2, y: m)); p.addLine(to: CGPoint(x: w - 9, y: h - 1))
        case .rect:
            p.addRect(CGRect(x: w * 0.25, y: 1, width: w * 0.5, height: h - 2))
        case .eraser:
            // 기울어진 지우개: 몸통 사각형과 지우는 쪽을 가르는 선
            var q = Path()
            q.addRoundedRect(in: CGRect(x: w / 2 - 11, y: 2, width: 22, height: h - 4), cornerSize: CGSize(width: 2, height: 2))
            q.move(to: CGPoint(x: w / 2 - 3, y: 2)); q.addLine(to: CGPoint(x: w / 2 - 3, y: h - 2))
            p = q.applying(CGAffineTransform(translationX: w / 2, y: m).rotated(by: -0.5).translatedBy(x: -w / 2, y: -m))
        default:
            p.addEllipse(in: CGRect(x: w * 0.25, y: 1, width: w * 0.5, height: h - 2))
        }
        ctx.stroke(p, with: .color(.primary), style: StrokeStyle(lineWidth: 1.6, lineCap: .round, lineJoin: .round))
    }
}

private struct CapView: View {
    let cap: KeyboardLayout.Cap
    let unit: CGFloat
    var body: some View {
        let w = unit * cap.width + (cap.width - 1) * 6
        let h = unit * cap.height + (cap.height - 1) * 6
        if !cap.subs.isEmpty {
            VStack(spacing: 6) { ForEach(cap.subs) { CapView(cap: $0, unit: unit) } }
        } else {
        VStack(spacing: 2) {
            Text(cap.label).font(.system(size: cap.label.count > 1 && cap.label.first?.isASCII == true ? 12 : 15, weight: .semibold))
                .foregroundStyle(cap.active ? Color.primary : Color.secondary.opacity(0.6))
            if let bar = cap.bar {
                if [.line, .wave, .arrow, .rect, .ellipse, .eraser].contains(bar) {
                    barView(bar, cap).frame(width: w - 20, height: 16)
                } else {
                    barView(bar, cap).frame(width: w - 20, height: 8)
                        .clipShape(RoundedRectangle(cornerRadius: 3))
                        .overlay(RoundedRectangle(cornerRadius: 3).stroke(Color.primary.opacity(0.25), lineWidth: 0.5))
                }
            } else if let rgb = cap.rgb {
                RoundedRectangle(cornerRadius: 3).fill(Color(nsColor: color(rgb)).opacity(cap.alpha)).frame(width: w - 20, height: 8)
                    .overlay(RoundedRectangle(cornerRadius: 3).stroke(Color.primary.opacity(0.25), lineWidth: 0.5))
            }
            Text(cap.role).font(.system(size: 10)).foregroundStyle(.secondary).lineLimit(1).minimumScaleFactor(0.7)
        }
        .frame(width: w, height: cap.subs.isEmpty ? h : (unit - 6) / 2)
        .background(RoundedRectangle(cornerRadius: 8).fill(cap.group.map { $0.tint.opacity(0.14) } ?? Color.white.opacity(cap.active ? 0.14 : 0.04)))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(cap.group.map { $0.tint.opacity(0.9) } ?? Color.primary.opacity(cap.active ? 0.35 : 0.12), lineWidth: cap.group == nil ? 1 : 1.5))
        }
    }
}

// 설명 카드: "키 → 하는 일" 두 칸 표
private struct GuideCard: View {
    let title: String
    let dot: Color
    let rows: [(keys: [String], what: String)]
    var note = ""
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) { Circle().fill(dot).frame(width: 8, height: 8); Text(title).font(.system(size: 14, weight: .semibold)) }
            ForEach(Array(rows.enumerated()), id: \.offset) { _, r in
                HStack(spacing: 8) {
                    HStack(spacing: 4) {
                        ForEach(Array(r.keys.enumerated()), id: \.offset) { _, k in
                            if k == "+" || k == "·" { Text(k).foregroundStyle(.secondary) } else {
                                Text(k).font(.system(size: 12, weight: .medium))
                                    .padding(.horizontal, 6).padding(.vertical, 2)
                                    .background(RoundedRectangle(cornerRadius: 5).fill(Color.white.opacity(0.1)))
                                    .overlay(RoundedRectangle(cornerRadius: 5).stroke(Color.primary.opacity(0.3), lineWidth: 0.5))
                            }
                        }
                    }
                    .frame(width: 200, alignment: .leading)
                    Text("→").foregroundStyle(.tertiary)
                    Text(r.what).font(.system(size: 13, weight: .semibold))
                    Spacer(minLength: 0)
                }
            }
            if !note.isEmpty { Text(note).font(.system(size: 11)).foregroundStyle(.secondary) }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .background(RoundedRectangle(cornerRadius: 12).fill(Color.white.opacity(0.05)))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.primary.opacity(0.15)))
    }
}

struct KeyboardView: View {
    let settings: Settings
    var body: some View {
        let unit: CGFloat = 56
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                Text("드로잉 모드 단축키").font(.title3.weight(.semibold))
                Text("드로잉을 켜 둔 동안에만 동작합니다. 끄면 모든 키가 평소대로 돌아갑니다.").font(.callout).foregroundStyle(.secondary)
            }
            HStack(spacing: 8) {
                ForEach(KeyboardLayout.Group.allCases, id: \.self) { g in
                    HStack(spacing: 5) {
                        Text(g.title).font(.system(size: 12, weight: .semibold)).foregroundStyle(g.tint)
                        Text(g.keys).font(.system(size: 10)).foregroundStyle(.secondary)
                    }
                    .padding(.horizontal, 10).padding(.vertical, 4)
                    .background(Capsule().fill(g.tint.opacity(0.14)))
                    .overlay(Capsule().stroke(g.tint.opacity(0.7), lineWidth: 1))
                }
            }
            VStack(alignment: .leading, spacing: 6) {
                ForEach(Array(KeyboardLayout.rows(settings).enumerated()), id: \.offset) { _, row in
                    HStack(spacing: 6) {
                        ForEach(row) { CapView(cap: $0, unit: unit) }
                    }
                }
            }
            HStack(alignment: .top, spacing: 12) {
                GuideCard(title: "마우스로 그리기", dot: Color(red: 0.25, green: 0.56, blue: 0.95), rows: [
                    (["드래그"], "자유선 그리기"),
                    (["⇧", "+", "드래그"], "사각형"),
                    (["⌃", "+", "드래그"], "원"),
                    (["Z X C", "+", "드래그"], "직선 · 물결 · 화살표"),
                    (["Z X C", "+", "⇧", "+", "드래그"], "0° · 45° · 90°로 맞춤"),
                    (["두 손가락 스크롤"], "진하게 · 연하게"),
                ])
                GuideCard(title: "되돌리기 · 지우기", dot: Color(red: 0.95, green: 0.38, blue: 0.33), rows: [
                    (["⌥", "+", "드래그"], "지우개 (오른쪽 버튼 드래그도 같음)"),
                    (["⌥", "+", "− ="], "지우개 크기"),
                    (["⌘", "+", "Z"], "실행 취소"),
                    (["delete"], "그린 것 전부 지우기"),
                    (["esc"], "지우고 드로잉 끄기"),
                ])
            }
            Text("Esc나 클릭으로 닫기").font(.caption).foregroundStyle(.tertiary)
        }
        .padding(24)
        .frame(width: KeyboardLayout.natural.width, height: KeyboardLayout.natural.height, alignment: .topLeading)
    }
}

private final class KeyboardWindow: NSWindow {
    override func cancelOperation(_ sender: Any?) { close() } // Esc
    override var canBecomeKey: Bool { true }
}

@MainActor final class KeyboardWindowController: NSObject {
    private var window: NSWindow?

    // 화면에 맞추되 원래 크기보다 키우지 않는다
    static func fitScale(screen: CGSize) -> CGFloat {
        min(1, screen.width * 0.9 / KeyboardLayout.natural.width, screen.height * 0.9 / KeyboardLayout.natural.height)
    }

    static func makeView(settings: Settings, scale: CGFloat, onClick: @escaping () -> Void) -> some View {
        KeyboardView(settings: settings)
            .scaleEffect(scale, anchor: .topLeading)
            .frame(width: KeyboardLayout.natural.width * scale, height: KeyboardLayout.natural.height * scale, alignment: .topLeading)
            .background(Color(nsColor: .windowBackgroundColor))
            .contentShape(Rectangle())
            .onTapGesture(perform: onClick)
    }

    func show() {
        window?.close()
        let screen = (NSScreen.main ?? NSScreen.screens.first)?.visibleFrame.size ?? KeyboardLayout.natural
        let scale = Self.fitScale(screen: screen)
        let w = KeyboardWindow(contentRect: NSRect(origin: .zero, size: CGSize(width: KeyboardLayout.natural.width * scale, height: KeyboardLayout.natural.height * scale)),
                               styleMask: [.titled, .closable], backing: .buffered, defer: false)
        w.title = "드로잉 단축키"
        w.isReleasedWhenClosed = false
        w.contentView = NSHostingView(rootView: Self.makeView(settings: Settings.shared, scale: scale, onClick: { [weak w] in w?.close() }))
        w.center()
        window = w
        NSApp.activate(ignoringOtherApps: true)
        w.makeKeyAndOrderFront(nil)
    }
}
