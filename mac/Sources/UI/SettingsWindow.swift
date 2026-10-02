import AppKit
import SwiftUI

// 설정 창: 일반·포커스·드로잉·위젯·단축키 5개 탭. 움직이면 바로 화면에 반영되고,
// "저장"을 눌러야 다음 실행에도 남는다 (Windows 판과 같음).
// 칸은 SettingsLayout 표에서 만든다 — 항목표(SettingsSchema)의 모든 키가 여기에 칸이 있는지 자체 점검이 확인한다.

enum SettingsLayout {
    struct Field {
        let id: String          // 항목표의 "절.키"
        let label: String
        var suffix = ""
        var step: Double = 1    // 슬라이더 간격 (직접 입력한 숫자는 따르지 않는다)
    }
    struct Panel {
        let title: String
        var toggle: String? = nil   // 켬·끔 키: 상자 제목에 두고, 끄면 안쪽을 흐리게
        var note: String? = nil
        let fields: [Field]
    }
    struct KeyRow { let label: String; let color: String; let opacity: String }

    static let focus: [Panel] = [
        Panel(title: "포커스 하이라이트", fields: [
            Field(id: "Highlight.Color", label: "색상"),
            Field(id: "Highlight.Size", label: "크기", suffix: "px", step: 5),
            Field(id: "Highlight.Opacity", label: "투명도", suffix: "%", step: 5)]),
        Panel(title: "포커스 클릭효과 (좌클릭)", toggle: "Highlight.ClickEffect", fields: [
            Field(id: "Highlight.ClickColor", label: "색상"),
            Field(id: "Highlight.RingThickness", label: "테두리 굵기"),
            Field(id: "Highlight.ClickOpacity", label: "투명도", suffix: "%", step: 5),
            Field(id: "Highlight.ClickSpeed", label: "빠르기")]),
        Panel(title: "포커스 클릭효과 (우클릭)", toggle: "Highlight.RClickEffect", fields: [
            Field(id: "Highlight.RClickColor", label: "색상"),
            Field(id: "Highlight.RClickThickness", label: "테두리 굵기"),
            Field(id: "Highlight.RClickOpacity", label: "투명도", suffix: "%", step: 5),
            Field(id: "Highlight.RClickSpeed", label: "빠르기")]),
    ]

    static let draw = Panel(title: "드로잉", fields: [
        Field(id: "Draw.Color", label: "기본 색상"),
        Field(id: "Draw.ThicknessStep", label: "드로잉 굵기", suffix: "단계"),
        Field(id: "Draw.Opacity", label: "전체 진하기", suffix: "%", step: 5),
        Field(id: "Draw.EraserStep", label: "지우개 크기", suffix: "단계")])

    static let drawKeys: [KeyRow] =
        (1...9).map { KeyRow(label: "\($0)", color: "DrawKeys.Color\($0)", opacity: "DrawKeys.Opacity\($0)") }
        + ["W", "E", "R"].map { KeyRow(label: "\($0) 칠판", color: "Boards.Color\($0)", opacity: "Boards.Opacity\($0)") }

    static let widget = Panel(title: "위젯", toggle: nil, fields: [
        Field(id: "Common.WidgetScale", label: "크기", suffix: "%", step: 10),
        Field(id: "Common.WidgetColor", label: "배경색"),
        Field(id: "Common.WidgetOpacity", label: "진하기", suffix: "%", step: 5)])
    static let widgetShow = "Common.ShowWidget"

    // 칸이 있는 모든 키 (자체 점검: 표의 키와 같아야 한다)
    static var allIDs: Set<String> {
        var ids = Set<String>()
        for g in focus { ids.formUnion(g.fields.map(\.id)); if let t = g.toggle { ids.insert(t) } }
        ids.formUnion(draw.fields.map(\.id))
        for r in drawKeys { ids.insert(r.color); ids.insert(r.opacity) }
        ids.formUnion(widget.fields.map(\.id)); ids.insert(widgetShow)
        return ids
    }
}

// ---------- 칸 하나하나 ----------

private let settingKeys: [String: SettingKey] = Dictionary(uniqueKeysWithValues: SettingsSchema.keys.map { ($0.id, $0) })

func valueBinding(_ id: String) -> Binding<Double> {
    let k = settingKeys[id]!
    return Binding(get: { k.read(Settings.shared) },
                   set: { v in
                       Settings.shared.objectWillChange.send() // 배열에 든 값(숫자키 색 등)도 화면과 저장 표시가 알게
                       k.write(Settings.shared, k.parse(String(v.rounded())) ?? k.defaultValue)
                       DispatchQueue.main.async { Settings.shared.objectWillChange.send() } // 바뀐 뒤에도 한 번 더: 칸이 새 값을 읽도록
                   })
}

private func flagBinding(_ id: String) -> Binding<Bool> {
    let b = valueBinding(id)
    return Binding(get: { b.wrappedValue >= 1 }, set: { b.wrappedValue = $0 ? 1 : 0 })
}

// 슬라이더 + −/+ + 숫자 입력. 입력은 Enter나 칸을 떠날 때 적용되고 스키마 범위로 잘린다.
private extension Double {
    func clamped(to r: ClosedRange<Double>) -> Double { Swift.max(r.lowerBound, Swift.min(r.upperBound, self)) }
}

// SwiftUI의 Slider는 Form 안에서 −와 + 사이를 채우지 않고 가운데로 쪼그라들어서, 맥 기본 슬라이더(NSSlider)를 직접 쓴다
private struct SliderBar: NSViewRepresentable {
    @Binding var value: Double
    let range: ClosedRange<Double>

    final class Coordinator: NSObject {
        var parent: SliderBar
        init(_ p: SliderBar) { parent = p }
        @objc func changed(_ s: NSSlider) { parent.value = s.doubleValue }
    }
    func makeCoordinator() -> Coordinator { Coordinator(self) }
    func makeNSView(context: Context) -> NSSlider {
        let s = NSSlider(value: value, minValue: range.lowerBound, maxValue: range.upperBound,
                         target: context.coordinator, action: #selector(Coordinator.changed(_:)))
        s.isContinuous = true
        s.setContentHuggingPriority(.defaultLow, for: .horizontal)
        s.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        return s
    }
    func updateNSView(_ s: NSSlider, context: Context) {
        context.coordinator.parent = self
        if s.doubleValue != value { s.doubleValue = value }
    }
}

struct NumberRow: View {
    let f: SettingsLayout.Field
    var labelWidth: CGFloat = 96
    @ObservedObject private var settings = Settings.shared // 값이 바뀌면 이 칸을 다시 그린다 (슬라이더·−/+·숫자 칸이 서로 따라가게)
    @Binding var value: Double
    let range: ClosedRange<Double>

    init(_ f: SettingsLayout.Field, labelWidth: CGFloat = 96) {
        self.f = f
        self.labelWidth = labelWidth
        _value = valueBinding(f.id)
        if case .int(let r) = settingKeys[f.id]!.kind { range = r } else { range = 0...100 }
    }

    var body: some View {
        // 이름·−·슬라이더·+·숫자·단위를 한 줄에. 간격과 안쪽 여백은 4의 배수(4·8·16)로 맞춘다.
        HStack(spacing: 8) {
            if !f.label.isEmpty { Text(f.label).frame(width: labelWidth, alignment: .leading) }
            StepButton(symbol: "−") { value = max(range.lowerBound, value - 1) }
            SliderBar(value: Binding(get: { value },
                                     set: { value = (f.step > 1 ? ($0 / f.step).rounded() * f.step : $0).clamped(to: range) }),
                      range: range)
            StepButton(symbol: "+") { value = min(range.upperBound, value + 1) }
            NumberBox(value: $value)
                .frame(width: 60, height: 28)
                .background(RoundedRectangle(cornerRadius: 8).fill(Color(nsColor: .textBackgroundColor)))
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.secondary.opacity(0.4)))
            Text(f.suffix).frame(width: 32, alignment: .leading).foregroundStyle(.secondary)
        }
        .padding(.vertical, 4)
    }
}

// 숫자 입력칸: 가운데 정렬. Enter를 누르거나 칸을 떠날 때 값이 적용된다 (범위로 자르는 일은 바인딩이 한다).
// SwiftUI TextField는 맥에서 가운데 정렬이 먹지 않아 NSTextField를 쓴다.
private struct NumberBox: NSViewRepresentable {
    @Binding var value: Double

    final class Coordinator: NSObject, NSTextFieldDelegate {
        var parent: NumberBox
        init(_ p: NumberBox) { parent = p }
        func controlTextDidEndEditing(_ n: Notification) {
            guard let f = n.object as? NSTextField else { return }
            if let v = Double(f.stringValue.trimmingCharacters(in: .whitespaces)), v.isFinite { parent.value = v.rounded() }
            f.stringValue = String(Int(parent.value.rounded())) // 못 읽는 글자는 원래 값으로 되돌린다
        }
    }
    func makeCoordinator() -> Coordinator { Coordinator(self) }
    func makeNSView(context: Context) -> NSTextField {
        let f = NSTextField(string: String(Int(value.rounded())))
        f.alignment = .center
        f.isBordered = false
        f.drawsBackground = false
        f.focusRingType = .none
        f.font = .monospacedDigitSystemFont(ofSize: NSFont.systemFontSize, weight: .regular)
        f.delegate = context.coordinator
        return f
    }
    func updateNSView(_ f: NSTextField, context: Context) {
        context.coordinator.parent = self
        let text = String(Int(value.rounded()))
        if f.currentEditor() == nil, f.stringValue != text { f.stringValue = text } // 입력 중에는 건드리지 않는다
    }
}

// −/+ 단추: 안쪽 여백 4, 글자 칸 16, 모서리 8
private struct StepButton: View {
    let symbol: String
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            Text(symbol).frame(width: 16, height: 16).padding(4)
                .background(RoundedRectangle(cornerRadius: 8).fill(Color(nsColor: .controlBackgroundColor)))
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.secondary.opacity(0.4)))
        }
        .buttonStyle(.plain)
    }
}

// 색 선택은 자체 상태를 둔다: 설정에는 8비트 색만 있어서, 매번 되읽으면 고른 색이 조금씩 튄다.
private struct ColorField: View {
    let label: String
    let id: String
    @State private var chosen: Color

    init(_ label: String, id: String) {
        self.label = label; self.id = id
        _chosen = State(initialValue: Color(nsColor: color(UInt32(valueBinding(id).wrappedValue))))
    }

    var body: some View {
        ColorPicker(label, selection: $chosen, supportsOpacity: false)
            .onChange(of: chosen) { c in
                let rgb = Double(rgbOf(NSColor(c)))
                if rgb != valueBinding(id).wrappedValue { valueBinding(id).wrappedValue = rgb }
            }
            .onReceive(Settings.shared.objectWillChange) { _ in
                // 초기화처럼 밖에서 바뀐 값만 따라간다
                DispatchQueue.main.async {
                    let cur = valueBinding(id).wrappedValue
                    if Double(rgbOf(NSColor(chosen))) != cur { chosen = Color(nsColor: color(UInt32(cur))) }
                }
            }
    }
}

private struct FieldView: View {
    let f: SettingsLayout.Field
    @ObservedObject private var settings = Settings.shared
    var body: some View {
        if case .color = settingKeys[f.id]!.kind { ColorField(f.label, id: f.id) } else { NumberRow(f) }
    }
}

private struct GroupBoxView: View {
    let g: SettingsLayout.Panel
    @ObservedObject private var settings = Settings.shared
    var body: some View {
        Section {
            if let t = g.toggle {
                Toggle(g.title, isOn: flagBinding(t)).font(.headline)
            }
            Group { ForEach(g.fields, id: \.id) { FieldView(f: $0) } }
                .disabled(g.toggle.map { !flagBinding($0).wrappedValue } ?? false)
                .opacity(g.toggle.map { flagBinding($0).wrappedValue ? 1 : 0.45 } ?? 1)
            if let n = g.note { Text(n).font(.callout).foregroundStyle(.secondary) }
        } header: {
            if g.toggle == nil { Text(g.title) }
        }
    }
}

// ---------- 창 ----------

struct SettingsView: View {
    @ObservedObject var s = Settings.shared
    var onSave: () -> Bool
    var onResetWidget: () -> Void
    var onResetAll: () -> Void
    var onClose: () -> Void
    var onQuit: () -> Void
    @State private var saved = false
    @State private var login = LoginItem.state()

    var body: some View {
        VStack(spacing: 0) {
            TabView {
                general.tabItem { Text("일반") }
                focus.tabItem { Text("포커스") }
                drawing.tabItem { Text("드로잉") }
                widget.tabItem { Text("위젯") }
                keys.tabItem { Text("단축키") }
            }
            .padding([.top, .horizontal], 12)

            HStack {
                Button("프로그램 종료", action: onQuit).foregroundStyle(.secondary)
                Spacer()
                Button(saved ? "저장됨" : "저장") { saved = onSave() }
                    .keyboardShortcut(.defaultAction)
                Button("닫기", action: onClose).keyboardShortcut(.cancelAction)
            }
            .padding(12)
        }
        .frame(width: 560, height: 620)
        .onReceive(s.objectWillChange) { _ in saved = false }
    }

    // ---- 일반 ----
    private var general: some View {
        Form {
            Section("시작") {
                Toggle("로그인할 때 자동으로 실행", isOn: Binding(get: { login == .on || login == .needsApproval }, set: setLogin))
                if login == .needsApproval {
                    Text("시스템 설정 › 일반 › 로그인 항목에서 허용해야 켜집니다.").font(.callout).foregroundStyle(.secondary)
                }
            }
            Section("설정 파일") {
                Text(Settings.path.path).font(.caption).foregroundStyle(.secondary).textSelection(.enabled)
                HStack {
                    Button("설정 폴더 열기") { Notice.revealSettingsFolder() }
                    Text("다른 맥으로 옮기려면 이 폴더의 settings.ini를 복사하세요.").font(.callout).foregroundStyle(.secondary)
                }
                Button("모든 설정 초기화...", action: onResetAll)
            }
            Section("정보") {
                Text("Focus & Draw \(AppInfo.displayVersion)")
                Text("제작 maker_SSAM · MIT 라이선스").foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .onAppear { login = LoginItem.state() }
    }

    private func setLogin(_ on: Bool) {
        if on && !LoginItem.isInstalledLocation() && LoginItem.allowed {
            Notice.show(Notice.loginNeedsInstall())
            login = .off
            return
        }
        let r = LoginItem.set(on)
        login = r.state
        if let e = r.error { Notice.show(Notice.loginFailed(e)) }
        else if on && r.state == .needsApproval { Notice.show(Notice.loginNeedsApproval()) }
    }

    // ---- 포커스 ----
    private var focus: some View {
        Form {
            ForEach(SettingsLayout.focus, id: \.title) { GroupBoxView(g: $0) }
            Section {
                Text("강조 중에는 마우스 화살표를 숨기고, 원 한가운데에 작은 십자를 보여 줍니다.").font(.callout).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }

    // ---- 드로잉 ----
    private var drawing: some View {
        Form {
            GroupBoxView(g: SettingsLayout.draw)
            Section("숫자키 색 · 칠판 (색과 진하기 5~100%)") {
                ScrollView {
                    VStack(spacing: 6) {
                        ForEach(SettingsLayout.drawKeys, id: \.color) { r in
                            HStack(spacing: 8) {
                                Text(r.label).frame(width: 54, alignment: .leading)
                                ColorField("", id: r.color).labelsHidden()
                                NumberRow(SettingsLayout.Field(id: r.opacity, label: "", suffix: "%", step: 5))
                            }
                        }
                    }.padding(.vertical, 4)
                }
                .frame(height: 190)
                Text("전체 진하기는 색별 진하기에 곱해집니다. 예: 전체 100%에 3번 키 40%이면 40%로 그려집니다.")
                    .font(.callout).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }

    // ---- 위젯 ----
    private var widget: some View {
        Form {
            Section("위젯") {
                Toggle("위젯 표시", isOn: flagBinding(SettingsLayout.widgetShow))
                ForEach(SettingsLayout.widget.fields, id: \.id) { FieldView(f: $0) }
                Button("처음 자리로 되돌리기", action: onResetWidget)
            }
        }
        .formStyle(.grouped)
    }

    // ---- 단축키 ----
    private var keys: some View {
        Form {
            Section("켜고 끄기") {
                keyLine("강조 켜기/끄기", "Spotlight", "SpotlightAlt")
                keyLine("드로잉 켜기/끄기", "Draw", "DrawAlt")
                Text("맥북 키보드에서는 F8·F9를 fn 키와 함께 누르세요. fn 없이 누르면 음악 재생·건너뛰기가 먼저 동작합니다.")
                    .font(.callout).foregroundStyle(.secondary)
            }
            Section("드로잉 중에 쓰는 키") {
                Text(Self.keyHelp).font(.callout).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }

    private func keyLine(_ title: String, _ a: String, _ b: String) -> some View {
        HStack {
            Text(title)
            Spacer()
            Text([a, b].map { HotkeyDisplay.symbols(s.hotkeys[$0] ?? SettingsSchema.hotkeyDefaults[$0] ?? "") }.joined(separator: "   또는   "))
                .monospaced().foregroundStyle(.secondary)
        }
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

// settings.ini의 AHK 표기("^!1")를 맥 기호("⌃⌥1")로 보여 준다
enum HotkeyDisplay {
    static func symbols(_ ahk: String) -> String {
        var mods = Set<Character>(), rest = Substring(ahk)
        while let c = rest.first, "^!+#".contains(c) { mods.insert(c); rest.removeFirst() }
        let order: [(Character, String)] = [("^", "⌃"), ("!", "⌥"), ("+", "⇧"), ("#", "⌘")]
        return order.filter { mods.contains($0.0) }.map(\.1).joined() + rest.uppercased()
    }
}

@MainActor final class SettingsWindowController: NSObject, NSWindowDelegate {
    private var window: NSWindow?
    private var previousApp: NSRunningApplication?
    var onSave: () -> Bool = { true }
    var onResetWidget: () -> Void = {}
    var onResetAll: () -> Void = {}
    var onQuit: () -> Void = {}

    func show() {
        if window == nil {
            let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 560, height: 620),
                             styleMask: [.titled, .closable], backing: .buffered, defer: false)
            w.title = "Focus & Draw 설정"
            w.isReleasedWhenClosed = false
            w.delegate = self
            w.contentView = NSHostingView(rootView: SettingsView(onSave: { self.onSave() },
                                                                 onResetWidget: { self.onResetWidget() },
                                                                 onResetAll: { self.onResetAll() },
                                                                 onClose: { [weak self] in self?.window?.performClose(nil) },
                                                                 onQuit: { self.onQuit() }))
            w.center()
            window = w
        }
        // 닫을 때 돌아갈 앞 앱을 기억한다 (이미 열려 있으면 처음 것을 그대로)
        if window?.isVisible != true {
            let front = NSWorkspace.shared.frontmostApplication
            previousApp = front?.processIdentifier == getpid() ? nil : front
        }
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }

    // 닫으면 색 패널도 함께 닫고, 앞 앱으로 초점을 돌려준다 (발표 앱에서 바로 이어 쓰도록)
    func windowWillClose(_ notification: Notification) {
        NSColorPanel.shared.orderOut(nil)
        colorPanelHidden = false
        if let p = previousApp, !p.isTerminated { p.activate(options: []) }
        previousApp = nil
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
