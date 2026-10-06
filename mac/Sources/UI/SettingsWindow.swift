import AppKit
import Carbon.HIToolbox
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
    struct KeyRow { let label: String; let color: String; let opacity: String; var step: String? = nil }

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
        Field(id: "Draw.Opacity", label: "드로잉 진하기", suffix: "%", step: 5),
        Field(id: "Draw.EraserStep", label: "지우개 크기", suffix: "단계"),
        Field(id: "Draw.LaserHold", label: "레이저 유지됨", suffix: "ms", step: 100),
        Field(id: "Draw.LaserFade", label: "레이저 사라짐", suffix: "ms", step: 100),
        Field(id: "Draw.LaserGlow", label: "레이저 빛 번짐", suffix: "%", step: 10)])

    static let drawKeys: [KeyRow] =
        (1...9).map { KeyRow(label: "\($0)", color: "DrawKeys.Color\($0)", opacity: "DrawKeys.Opacity\($0)", step: "DrawKeys.Step\($0)") }
        + ["W", "E", "R"].map { KeyRow(label: "\($0) 칠판", color: "Boards.Color\($0)", opacity: "Boards.Opacity\($0)") }

    static let widget = Panel(title: "위젯", toggle: nil, fields: [
        Field(id: "Common.WidgetScale", label: "크기", suffix: "%", step: 10),
        Field(id: "Common.WidgetColor", label: "배경색"),
        Field(id: "Common.WidgetOpacity", label: "진하기", suffix: "%", step: 5)])
    static let widgetShow = "Common.ShowWidget"
    static let trayShow = "Common.ShowTrayIcons"

    // 칸이 있는 모든 키 (자체 점검: 표의 키와 같아야 한다)
    static var allIDs: Set<String> {
        var ids = Set<String>()
        for g in focus { ids.formUnion(g.fields.map(\.id)); if let t = g.toggle { ids.insert(t) } }
        ids.formUnion(draw.fields.map(\.id))
        for r in drawKeys { ids.insert(r.color); ids.insert(r.opacity); if let s = r.step { ids.insert(s) } }
        ids.formUnion(widget.fields.map(\.id)); ids.insert(widgetShow); ids.insert(trayShow)
        return ids
    }
}

// ---------- 칸 하나하나 ----------

private let settingKeys: [String: SettingKey] = Dictionary(uniqueKeysWithValues: SettingsSchema.keys.map { ($0.id, $0) })

func valueBinding(_ id: String) -> Binding<Double> {
    let k = settingKeys[id]!
    return Binding(get: { k.read(Settings.shared) },
                   set: { v in
                       // 색은 16진 글자가 아니라 숫자 그대로 자른다 (글자로 바꿔 읽으면 못 읽어 기본값으로 돌아간다)
                       let w: Double
                       switch k.kind {
                       case .int(let r): w = max(r.lowerBound, min(r.upperBound, v.rounded()))
                       case .flag: w = v >= 1 ? 1 : 0
                       case .color: w = max(0, min(16_777_215, v.rounded()))
                       }
                       k.write(Settings.shared, w) // 일반 값은 Settings의 @Published가 알린다
                       // 배열에 든 값(숫자키 색 등)은 @Published가 모르므로 바뀐 뒤 한 번만 알린다
                       if k.section == "DrawKeys" || k.section == "Boards" { DispatchQueue.main.async { Settings.shared.objectWillChange.send() } }
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
            // −/+는 1씩, 시간(ms)은 1ms로는 차이를 느낄 수 없어 슬라이더 간격(100ms)씩
            let tick: Double = f.suffix == "ms" ? f.step : 1
            StepButton(symbol: "−") { value = max(range.lowerBound, value - tick) }
            SliderBar(value: Binding(get: { value },
                                     set: { value = (f.step > 1 ? ($0 / f.step).rounded() * f.step : $0).clamped(to: range) }),
                      range: range)
            StepButton(symbol: "+") { value = min(range.upperBound, value + tick) }
            NumberBox(value: $value)
                .frame(width: 60, height: 28)
                .background(RoundedRectangle(cornerRadius: 8).fill(Color(nsColor: .textBackgroundColor)))
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.secondary.opacity(0.4)))
            Text(f.suffix).frame(width: 32, alignment: .leading).foregroundStyle(.secondary)
        }
    }
}

// 숫자키 굵기 칸: 숫자 + 위아래 화살표 (Windows 판과 같은 모양). 슬라이더 줄 오른쪽에 붙는다.
private struct StepBox: View {
    static let width: CGFloat = 44 + 8 + 16 // 숫자 칸 + 간격 + 화살표
    let id: String
    @ObservedObject private var settings = Settings.shared
    var body: some View {
        let value = valueBinding(id)
        HStack(spacing: 8) {
            NumberBox(value: value)
                .frame(width: 44, height: 28)
                .background(RoundedRectangle(cornerRadius: 8).fill(Color(nsColor: .textBackgroundColor)))
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.secondary.opacity(0.4)))
            Stepper("", value: value, in: 1...Double(STEP_MAX), step: 1).labelsHidden()
        }
        .help("이 숫자키를 누르면 바뀌는 굵기 단계")
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

// 단축키 녹화 칸: 눌러서 초점을 주면 "키를 누르세요"가 되고, 다음에 누른 조합을 알려 준다.
// 글자가 아니라 키 자리 번호로 읽으므로 한글 입력 상태와 상관없다. 보조 키만 누른 것은 무시하고, 키를 누르고 있어 되풀이되는 것도 무시한다.
// ⌘ 조합이 메뉴(⌘W 등)로 새지 않도록 performKeyEquivalent에서 먼저 받는다.
final class HotkeyCaptureView: NSView {
    var display = ""
    var onCapture: (HotkeyNotation.Combo) -> Void = { _ in }
    private(set) var recording = false
    static var onRecording: (Bool) -> Void = { _ in } // 녹화 시작·끝 (앱 단축키를 내리고 올리는 데 쓴다)

    // 눌렀을 때만 초점을 받는다 (창이 열릴 때 첫 칸이 저절로 "키를 누르세요" 상태가 되지 않게)
    private var armed = false
    override var acceptsFirstResponder: Bool { armed }
    override var intrinsicContentSize: NSSize { NSSize(width: 160, height: 28) }
    override func mouseDown(with event: NSEvent) { armed = true; window?.makeFirstResponder(self) }
    override func becomeFirstResponder() -> Bool { recording = true; needsDisplay = true; Self.onRecording(true); return true }
    override func resignFirstResponder() -> Bool {
        if recording { Self.onRecording(false) }
        recording = false; armed = false; needsDisplay = true
        return true
    }

    override func performKeyEquivalent(with event: NSEvent) -> Bool { recording ? handle(event) : false }
    override func keyDown(with event: NSEvent) { if !handle(event) { super.keyDown(with: event) } }

    private func handle(_ e: NSEvent) -> Bool {
        guard recording else { return false }
        if e.isARepeat { return true }
        let f = e.modifierFlags.intersection(.deviceIndependentFlagsMask)
        if e.keyCode == 53 && f.intersection([.command, .control, .option, .shift]).isEmpty { // Esc만: 취소
            window?.makeFirstResponder(nil)
            return true
        }
        var mods = 0
        if f.contains(.command) { mods |= cmdKey }
        if f.contains(.control) { mods |= controlKey }
        if f.contains(.option) { mods |= optionKey }
        if f.contains(.shift) { mods |= shiftKey }
        window?.makeFirstResponder(nil)
        onCapture(HotkeyNotation.Combo(code: Int(e.keyCode), mods: mods))
        return true
    }

    override func draw(_ dirtyRect: NSRect) {
        effectiveAppearance.performAsCurrentDrawingAppearance { self.drawCap() }
    }

    private func drawCap() {
        let r = bounds.insetBy(dx: 0.5, dy: 0.5)
        let path = NSBezierPath(roundedRect: r, xRadius: 8, yRadius: 8)
        NSColor.textBackgroundColor.setFill(); path.fill()
        (recording ? NSColor.controlAccentColor : NSColor.secondaryLabelColor.withAlphaComponent(0.5)).setStroke()
        path.lineWidth = recording ? 2 : 1
        path.stroke()
        let text = recording ? "키를 누르세요 (Esc: 취소)" : display
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedSystemFont(ofSize: recording ? 11 : 13, weight: .regular),
            .foregroundColor: recording ? NSColor.secondaryLabelColor : NSColor.labelColor,
        ]
        let str = NSAttributedString(string: text, attributes: attrs)
        let sz = str.size()
        str.draw(at: NSPoint(x: bounds.midX - sz.width / 2, y: bounds.midY - sz.height / 2))
    }
}

private struct HotkeyField: NSViewRepresentable {
    let display: String
    let onCapture: (HotkeyNotation.Combo) -> Void
    func makeNSView(context: Context) -> HotkeyCaptureView { HotkeyCaptureView() }
    func updateNSView(_ v: HotkeyCaptureView, context: Context) {
        v.display = display
        v.onCapture = onCapture
        v.needsDisplay = true
    }
}

// −/+ 단추: 안쪽 여백 4, 글자 칸 16, 모서리 8
private struct StepButton: View {
    let symbol: String
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            Text(symbol).frame(width: 16, height: 16).padding(4)
                .background(RoundedRectangle(cornerRadius: 8).fill(Color(nsColor: .windowBackgroundColor))) // 설정 배경과 같은 색
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.secondary.opacity(0.4)))
        }
        .buttonStyle(.plain)
    }
}

// 색 칸: 맥 기본 색 칸(NSColorWell). 설정에는 8비트 색만 있으므로, 밖에서 바뀐 값(초기화 등)만 따라가고
// 같은 색이면 되읽지 않는다 (되읽으면 고른 색이 조금씩 튄다). 이름 바로 옆에 왼쪽 정렬.
private struct ColorWell: NSViewRepresentable {
    @Binding var value: Double

    final class Coordinator: NSObject {
        var parent: ColorWell
        init(_ p: ColorWell) { parent = p }
        @objc func changed(_ w: NSColorWell) {
            let rgb = Double(rgbOf(w.color))
            if rgb != parent.value { parent.value = rgb }
        }
    }
    func makeCoordinator() -> Coordinator { Coordinator(self) }
    func makeNSView(context: Context) -> NSColorWell {
        let w = NSColorWell(frame: .zero)
        w.colorWellStyle = .default
        w.color = color(UInt32(value))
        w.target = context.coordinator
        w.action = #selector(Coordinator.changed(_:))
        return w
    }
    func updateNSView(_ w: NSColorWell, context: Context) {
        context.coordinator.parent = self
        if Double(rgbOf(w.color)) != value { w.color = color(UInt32(value)) }
    }
}

private struct ColorField: View {
    let label: String
    let id: String
    var labelWidth: CGFloat = 96
    var compact = false // 목록 줄 안에서는 남는 자리를 먹지 않는다
    @ObservedObject private var settings = Settings.shared

    init(_ label: String, id: String, compact: Bool = false) { self.label = label; self.id = id; self.compact = compact }

    var body: some View {
        HStack(spacing: 8) {
            if !label.isEmpty { Text(label).frame(width: labelWidth, alignment: .leading) }
            ColorWell(value: valueBinding(id)).frame(width: 48, height: 28)
            if !compact { Spacer(minLength: 0) }
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

// 묶음 하나 = 상자 하나. 안쪽 여백 12, 줄 사이 8 (4의 배수)
private struct Card<Content: View>: View {
    var title: String? = nil
    var toggle: Binding<Bool>? = nil
    @ViewBuilder var content: Content
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let t = toggle, let title {
                HStack {
                    Text(title).font(.headline)
                    Spacer()
                    Toggle("", isOn: t).labelsHidden().toggleStyle(.switch)
                }
            } else if let title {
                Text(title).font(.headline)
            }
            content
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 8).fill(Color.white.opacity(0.10))) // 설정 배경보다 10% 연하게
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.primary.opacity(0.10)))
    }
}

private struct Page<Content: View>: View {
    @ViewBuilder var content: Content
    var body: some View {
        ScrollView { VStack(spacing: 12) { content }.padding(12) }
    }
}

private struct GroupBoxView: View {
    let g: SettingsLayout.Panel
    @ObservedObject private var settings = Settings.shared
    var body: some View {
        let on = g.toggle.map { flagBinding($0).wrappedValue } ?? true
        Card(title: g.title, toggle: g.toggle.map(flagBinding)) {
            VStack(alignment: .leading, spacing: 8) { ForEach(g.fields, id: \.id) { FieldView(f: $0) } }
                .disabled(!on).opacity(on ? 1 : 0.45)
            if let n = g.note { Text(n).font(.callout).foregroundStyle(.secondary) }
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
    var onShowKeyboard: () -> Void = {}
    var onHotkey: (String, HotkeyNotation.Combo?) -> String? = { _, _ in nil } // 이름, 새 조합(nil = 기본값) → 거절 이유(없으면 nil)
    var startTab = 0 // 자체 점검이 탭마다 그림을 뽑으려고
    @State private var tab = -1
    @State private var hotkeyMessage: [String: String] = [:]
    @State private var saved = false
    @State private var login = LoginItem.state()

    var body: some View {
        VStack(spacing: 0) {
            TabView(selection: Binding(get: { tab < 0 ? startTab : tab }, set: { tab = $0 })) {
                general.tabItem { Text("일반") }.tag(0)
                focus.tabItem { Text("포커스") }.tag(1)
                drawing.tabItem { Text("드로잉") }.tag(2)
                widget.tabItem { Text("위젯") }.tag(3)
                keys.tabItem { Text("단축키") }.tag(4)
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
        Page {
            Card(title: "시작") {
                Toggle("로그인할 때 자동으로 실행", isOn: Binding(get: { login == .on || login == .needsApproval }, set: setLogin))
                if login == .needsApproval {
                    Text("시스템 설정 › 일반 › 로그인 항목에서 허용해야 켜집니다.").font(.callout).foregroundStyle(.secondary)
                }
            }
            Card(title: "설정 파일") {
                Text(Settings.path.path).font(.caption).foregroundStyle(.secondary).textSelection(.enabled)
                HStack {
                    Button("설정 폴더 열기") { Notice.revealSettingsFolder() }
                    Text("다른 맥으로 옮기려면 이 폴더의 settings.ini를 복사하세요.").font(.callout).foregroundStyle(.secondary)
                }
                Button("모든 설정 초기화...", action: onResetAll)
            }
            Card(title: "정보") {
                Text("Focus & Draw \(AppInfo.displayVersion)")
                Text("제작 maker_SSAM · MIT 라이선스").foregroundStyle(.secondary)
            }
        }
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
        Page {
            ForEach(SettingsLayout.focus, id: \.title) { GroupBoxView(g: $0) }
            Text("강조 중에는 마우스 화살표를 숨기고, 원 한가운데에 작은 십자를 보여 줍니다.")
                .font(.callout).foregroundStyle(.secondary).frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    // ---- 드로잉 ----
    private var drawing: some View {
        Page {
            GroupBoxView(g: SettingsLayout.draw)
            Card(title: "숫자키 · 칠판 (색, 진하기 5~100%, 숫자키 굵기 1~\(STEP_MAX)단계)") {
                VStack(spacing: 8) {
                    ForEach(SettingsLayout.drawKeys, id: \.color) { r in
                        if r.color == "Boards.ColorW" { Divider() } // 숫자키와 칠판 사이
                        HStack(spacing: 8) {
                            Text(r.label).frame(width: 48, alignment: .leading)
                            ColorField("", id: r.color, compact: true)
                            NumberRow(SettingsLayout.Field(id: r.opacity, label: "", suffix: "%", step: 5))
                            if let s = r.step { StepBox(id: s) } else { Color.clear.frame(width: StepBox.width, height: 1) } // 칠판 줄도 칸을 맞춘다
                        }
                    }
                }
                Text("드로잉을 켜거나 숫자키를 누르면 \"드로잉 진하기 × 색별 진하기\"로 시작합니다(예: 50%에 3번 키 40%이면 20%). 그린 뒤 마우스 휠로 바꾸는 숫자가 실제 진하기입니다(100%면 불투명).")
                    .font(.callout).foregroundStyle(.secondary)
            }
        }
    }

    // ---- 위젯 ----
    private var widget: some View {
        Page {
            Card(title: "위젯 표시", toggle: flagBinding(SettingsLayout.widgetShow)) {
                ForEach(SettingsLayout.widget.fields, id: \.id) { FieldView(f: $0) }
                Button("처음 자리로 되돌리기", action: onResetWidget)
            }
            Card(title: "메뉴 막대 아이콘을 위젯처럼 표시", toggle: flagBinding(SettingsLayout.trayShow)) {
                Text("켜면 메뉴 막대에 위젯처럼 강조 · 드로잉 · 설정이 테두리로 묶여 보입니다. 강조·드로잉은 누를 때마다 켜고 끄고(켜진 것은 파랑), 설정을 누르면 메뉴가 열립니다.")
                    .font(.callout).foregroundStyle(.secondary)
            }
        }
    }

    // ---- 단축키 ----
    private var keys: some View {
        Page {
            Card(title: "켜고 끄기 (칸을 누른 뒤 바꿀 키를 누르세요)") {
                ForEach(SettingsSchema.hotkeys, id: \.name) { h in hotkeyRow(h.name, def: h.def) }
                Text("맥북 키보드에서는 F8·F9를 fn 키와 함께 누르세요. fn 없이 누르면 음악 재생·건너뛰기가 먼저 동작합니다.")
                    .font(.callout).foregroundStyle(.secondary)
                Text("글자·숫자는 ⌃(Control)를 함께 눌러야 합니다. 드로잉 중에 쓰는 키와 macOS가 쓰는 조합은 바꿀 수 없습니다.")
                    .font(.callout).foregroundStyle(.secondary)
            }
            HStack { Button("드로잉 모드 단축키 보기", action: onShowKeyboard); Spacer(minLength: 0) }
        }
    }

    private func hotkeyRow(_ name: String, def: String) -> some View {
        let current = s.hotkeys[name] ?? def
        return VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                Text(HotkeyRules.label(name)).frame(width: 168, alignment: .leading)
                HotkeyField(display: HotkeyDisplay.symbols(current)) { combo in
                    hotkeyMessage[name] = onHotkey(name, combo)
                }
                .frame(width: 160, height: 28)
                Button("기본값") { hotkeyMessage[name] = onHotkey(name, nil) }.disabled(current == def)
                Spacer(minLength: 0)
            }
            if let m = hotkeyMessage[name] {
                Text(m).font(.callout).foregroundStyle(.red).fixedSize(horizontal: false, vertical: true)
            }
        }
    }
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
    var onHotkey: (String, HotkeyNotation.Combo?) -> String? = { _, _ in nil }
    var onQuit: () -> Void = {}
    var onShowKeyboard: () -> Void = {}

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
                                                                 onQuit: { self.onQuit() },
                                                                 onShowKeyboard: { self.onShowKeyboard() },
                                                                 onHotkey: { self.onHotkey($0, $1) }))
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

    // 창이 키를 잃거나(다른 앱으로 감) 닫히면 녹화 중이던 칸을 풀어 앱 단축키를 되살린다
    func windowDidResignKey(_ notification: Notification) { window?.makeFirstResponder(nil) }

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
