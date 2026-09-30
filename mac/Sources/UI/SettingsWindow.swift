import AppKit
import SwiftUI

// 시험판의 설정 창: 자주 바꾸는 값만 모았다. 움직이면 바로 화면에 반영되고,
// "저장"을 눌러야 다음 실행에도 남는다 (Windows 판과 같음).

private func hexBinding(_ kp: ReferenceWritableKeyPath<Settings, UInt32>) -> Binding<Color> {
    Binding(get: { Color(nsColor: color(Settings.shared[keyPath: kp])) },
            set: { Settings.shared[keyPath: kp] = rgbOf(NSColor($0)) })
}

private struct Row: View {
    let label: String
    @Binding var value: Double
    let range: ClosedRange<Double>
    var suffix = ""
    var body: some View {
        HStack {
            Text(label).frame(width: 110, alignment: .leading)
            Slider(value: $value, in: range, step: 1)
            Text("\(Int(value))\(suffix)").monospacedDigit().frame(width: 48, alignment: .trailing)
        }
    }
}

struct SettingsView: View {
    @ObservedObject var s = Settings.shared
    var onSave: () -> Bool
    var onResetWidget: () -> Void
    var onQuit: () -> Void
    @State private var saved = false

    var body: some View {
        VStack(spacing: 0) {
            TabView {
                Form {
                    Section("포커스 하이라이트") {
                        ColorPicker("색상", selection: hexBinding(\.spotColor), supportsOpacity: false)
                        Row(label: "크기", value: $s.spotSize, range: 30...200, suffix: "px")
                        Row(label: "투명도", value: $s.spotOpacity, range: 0...100, suffix: "%")
                    }
                    Section {
                        Toggle("포커스 클릭효과 (좌클릭)", isOn: $s.clickEffect)
                        Group {
                            ColorPicker("색상", selection: hexBinding(\.clickColor), supportsOpacity: false)
                            Row(label: "테두리 굵기", value: $s.clickThickness, range: 2...12)
                            Row(label: "투명도", value: $s.clickOpacity, range: 0...100, suffix: "%")
                            Row(label: "빠르기", value: $s.clickSpeed, range: 1...30)
                        }.disabled(!s.clickEffect)
                    }
                    Section {
                        Toggle("포커스 클릭효과 (우클릭)", isOn: $s.rclickEffect)
                        Group {
                            ColorPicker("색상", selection: hexBinding(\.rclickColor), supportsOpacity: false)
                            Row(label: "테두리 굵기", value: $s.rclickThickness, range: 2...12)
                            Row(label: "투명도", value: $s.rclickOpacity, range: 0...100, suffix: "%")
                            Row(label: "빠르기", value: $s.rclickSpeed, range: 1...30)
                        }.disabled(!s.rclickEffect)
                    }
                }
                .formStyle(.grouped)
                .tabItem { Text("포커스") }

                Form {
                    Section("드로잉") {
                        ColorPicker("기본 색상", selection: hexBinding(\.drawColor), supportsOpacity: false)
                        Row(label: "드로잉 굵기", value: $s.drawStep, range: 1...10, suffix: "단계")
                        Row(label: "투명도", value: $s.drawOpacity, range: 0...100, suffix: "%")
                        Row(label: "지우개 크기", value: $s.eraserStep, range: 1...10, suffix: "단계")
                    }
                    Section("드로잉 중에 쓰는 키") {
                        Text(Self.keyHelp).font(.callout).foregroundStyle(.secondary)
                    }
                }
                .formStyle(.grouped)
                .tabItem { Text("드로잉") }

                Form {
                    Section("위젯") {
                        Toggle("위젯 표시", isOn: $s.showWidget)
                        Row(label: "크기", value: $s.widgetScale, range: 60...250, suffix: "%")
                        ColorPicker("배경색", selection: hexBinding(\.widgetColor), supportsOpacity: false)
                        Row(label: "투명도", value: $s.widgetOpacity, range: 20...100, suffix: "%")
                        Button("처음 자리로 되돌리기", action: onResetWidget)
                    }
                    Section("단축키") {
                        Text("강조 켜기/끄기: F8 또는 ⌃⌥1\n드로잉 켜기/끄기: F9 또는 ⌃⌥2")
                        Text("맥북 키보드에서는 F8·F9를 fn 키와 함께 누르세요. fn 없이 누르면 음악 재생·건너뛰기가 먼저 동작합니다.")
                            .font(.callout).foregroundStyle(.secondary)
                    }
                    Section("정보") {
                        Text("Focus & Draw \(AppInfo.displayVersion) · 제작 maker_SSAM · MIT 라이선스")
                        Text("설정 파일: \(Settings.path.path)").font(.caption).foregroundStyle(.secondary).textSelection(.enabled)
                    }
                }
                .formStyle(.grouped)
                .tabItem { Text("위젯·일반") }
            }
            .padding([.top, .horizontal], 12)

            HStack {
                Button("프로그램 종료", action: onQuit)
                Spacer()
                Button(saved ? "저장됨" : "저장") { saved = onSave() }
                    .keyboardShortcut(.defaultAction)
            }
            .padding(12)
        }
        .frame(width: 480, height: 560)
        .onReceive(s.objectWillChange) { _ in saved = false }
    }

    static let keyHelp = """
    드래그: 자유선 · Shift+드래그: 사각형 · Control+드래그: 원
    Z / X / C 누른 채 드래그: 직선 / 물결 / 화살표 (Shift를 더하면 0°·45°·90°)
    A: 사라지는 펜 · S: 무지개 펜 · 1~9: 색 · 0: 기본 색
    Q / W / E / R: 칠판 (투명 / 흰색 / 초록 / 검정)
    + / −: 굵게 / 가늘게 · 휠(두 손가락 스크롤): 진하게 / 연하게
    오른쪽 버튼 드래그 또는 ⌥ Option+드래그: 지우개 (⌥ +/−: 지우개 크기)
    ⌘Z: 실행 취소 · delete: 전부 지우기 · Esc: 지우고 끝내기
    """
}

@MainActor final class SettingsWindowController {
    private var window: NSWindow?
    var onSave: () -> Bool = { true }
    var onResetWidget: () -> Void = {}
    var onQuit: () -> Void = {}

    func show() {
        if window == nil {
            let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 480, height: 560),
                             styleMask: [.titled, .closable], backing: .buffered, defer: false)
            w.title = "Focus & Draw 설정"
            w.isReleasedWhenClosed = false
            w.contentView = NSHostingView(rootView: SettingsView(onSave: { self.onSave() },
                                                                 onResetWidget: { self.onResetWidget() },
                                                                 onQuit: { self.onQuit() }))
            w.center()
            window = w
        }
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }

    // 드로잉 판이 설정 창을 덮는 동안 창을 치워 둔다. 보이던 창이었으면 true.
    // 색 고르는 패널도 함께 치운다 — 판 아래에 갇혀 눌리지 않기 때문이다.
    private var colorPanelHidden = false
    func hideForDraw() -> Bool {
        if NSColorPanel.shared.isVisible { colorPanelHidden = true; NSColorPanel.shared.orderOut(nil) }
        var hid = colorPanelHidden
        if let w = window, w.isVisible { w.orderOut(nil); hid = true }
        return hid
    }

    // 드로잉이 끝나면 앱을 앞으로 부르지 않고 창만 되돌린다
    func restoreAfterDraw() {
        window?.orderFront(nil)
        if colorPanelHidden { NSColorPanel.shared.orderFront(nil); colorPanelHidden = false }
    }
}
