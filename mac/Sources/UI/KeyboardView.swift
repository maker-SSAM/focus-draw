import AppKit
import SwiftUI

// "드로잉 모드 단축키 보기": 맥 자판 그림. 줄마다 역할이 같다 — 숫자 줄 = 색, Q 줄 = 칠판, A 줄 = 특수 펜, Z 줄 = 도형.
// 색은 늘 지금 설정의 색이다 (설정에서 3번을 바꾸고 다시 열면 새 색). 키 표(KeyMap)와 설정이 바뀌면 이 그림도 따라가도록
// 역할 글은 한곳(KeyboardLayout)에 모았다.

enum KeyboardLayout {
    enum Bar { case checker, laser, rainbow }
    struct Cap: Identifiable {
        let id = UUID()
        let label: String
        var role = ""
        var rgb: UInt32? = nil       // 색 칸 (숫자키·칠판)
        var alpha: Double = 1
        var bar: Bar? = nil          // 색이 아닌 펜·칠판의 모양 막대
        var width: CGFloat = 1       // 1 = 보통 키
        var active = true            // 드로잉에서 쓰는 키면 true
    }

    static func rows(_ s: Settings) -> [[Cap]] {
        func digit(_ i: Int) -> Cap { Cap(label: "\(i)", role: "색 \(i)", rgb: s.drawKeyColors[i - 1], alpha: s.drawKeyAlphas[i - 1] / 100) }
        var r1: [Cap] = [Cap(label: "`", active: false)]
        r1 += (1...9).map(digit)
        r1 += [Cap(label: "0", role: "기본 색", rgb: s.drawColor, alpha: s.drawOpacity / 100),
               Cap(label: "−", role: "가늘게"), Cap(label: "=", role: "굵게"),
               Cap(label: "delete", role: "전부 지움", width: 1.7)]
        let r2: [Cap] = [
            Cap(label: "Q", role: "투명 칠판", bar: .checker),
            Cap(label: "W", role: "흰 칠판", rgb: s.boardColors[0], alpha: s.boardAlphas[0] / 100),
            Cap(label: "E", role: "초록 칠판", rgb: s.boardColors[1], alpha: s.boardAlphas[1] / 100),
            Cap(label: "R", role: "검정 칠판", rgb: s.boardColors[2], alpha: s.boardAlphas[2] / 100),
        ] + "TYUIOP[]".map { Cap(label: String($0), active: false) }
        let r3: [Cap] = [Cap(label: "A", role: "레이저 펜", rgb: s.drawColor, bar: .laser), Cap(label: "S", role: "무지개 펜", bar: .rainbow)]
            + "DFGHJKL;'".map { Cap(label: String($0), active: false) }
        let r4: [Cap] = [Cap(label: "Z", role: "직선"), Cap(label: "X", role: "물결"), Cap(label: "C", role: "화살표")]
            + "VBNM,./".map { Cap(label: String($0), active: false) }
        return [r1, r2, r3, r4]
    }
    static let indents: [CGFloat] = [0, 0.5, 0.75, 1.25]
    static let natural = CGSize(width: 980, height: 440)
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
    case .rainbow:
        LinearGradient(colors: stride(from: 0.0, through: 1.0, by: 1.0 / 6).map { Color(hue: $0, saturation: 0.85, brightness: 1) },
                       startPoint: .leading, endPoint: .trailing)
    }
}

private struct CapView: View {
    let cap: KeyboardLayout.Cap
    let unit: CGFloat
    var body: some View {
        let w = unit * cap.width + (cap.width - 1) * 6
        VStack(spacing: 2) {
            Text(cap.label).font(.system(size: 15, weight: .semibold)).foregroundStyle(cap.active ? Color.primary : Color.secondary.opacity(0.6))
            if let bar = cap.bar {
                barView(bar, cap).frame(width: w - 20, height: 8)
                    .clipShape(RoundedRectangle(cornerRadius: 3))
                    .overlay(RoundedRectangle(cornerRadius: 3).stroke(Color.primary.opacity(0.25), lineWidth: 0.5))
            } else if let rgb = cap.rgb {
                RoundedRectangle(cornerRadius: 3).fill(Color(nsColor: color(rgb)).opacity(cap.alpha)).frame(width: w - 20, height: 8)
                    .overlay(RoundedRectangle(cornerRadius: 3).stroke(Color.primary.opacity(0.25), lineWidth: 0.5))
            }
            Text(cap.role).font(.system(size: 10)).foregroundStyle(.secondary).lineLimit(1).minimumScaleFactor(0.7)
        }
        .frame(width: w, height: unit)
        .background(RoundedRectangle(cornerRadius: 8).fill(Color.white.opacity(cap.active ? 0.14 : 0.04)))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.primary.opacity(cap.active ? 0.35 : 0.12)))
    }
}

struct KeyboardView: View {
    let settings: Settings
    var body: some View {
        let unit: CGFloat = 56
        VStack(alignment: .leading, spacing: 14) {
            Text("드로잉 모드 단축키").font(.title3.weight(.semibold))
            VStack(alignment: .leading, spacing: 6) {
                ForEach(Array(KeyboardLayout.rows(settings).enumerated()), id: \.offset) { i, row in
                    HStack(spacing: 6) {
                        Spacer().frame(width: (unit + 6) * KeyboardLayout.indents[i])
                        ForEach(row) { CapView(cap: $0, unit: unit) }
                    }
                }
            }
            VStack(alignment: .leading, spacing: 4) {
                Text("마우스: 드래그 = 자유선 · ⇧ + 드래그 = 사각형 · ⌃ + 드래그 = 원 · Z/X/C를 누른 채 드래그 = 직선/물결/화살표 (⇧를 더하면 0°·45°·90°)")
                Text("지우개: 오른쪽 버튼 드래그 또는 ⌥ + 드래그 · ⌥ + (+/−) = 지우개 크기 · 두 손가락 스크롤 = 진하게/연하게")
                Text("⌘Z = 실행 취소 · Esc = 지우고 끝내기 · 글자 숫자 키 중 쓰지 않는 키는 눌러도 아무 일도 하지 않습니다")
            }
            .font(.callout).foregroundStyle(.secondary)
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

@MainActor final class KeyboardWindowController: NSObject, NSWindowDelegate {
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
        w.delegate = self
        w.contentView = NSHostingView(rootView: Self.makeView(settings: Settings.shared, scale: scale, onClick: { [weak w] in w?.close() }))
        w.center()
        window = w
        NSApp.activate(ignoringOtherApps: true)
        w.makeKeyAndOrderFront(nil)
    }
}
