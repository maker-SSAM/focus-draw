import AppKit
import Carbon
import Combine

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    let spotlight = Spotlight()
    let clicks = ClickEffect()
    let draw = DrawController()
    let settingsWindow = SettingsWindowController()
    var widget: Widget!
    var statusItem: NSStatusItem!
    var changes: AnyCancellable?

    func applicationDidFinishLaunching(_ n: Notification) {
        let args = CommandLine.arguments
        func arg(_ name: String) -> String? {
            guard let i = args.firstIndex(of: name), i + 1 < args.count else { return nil }
            return args[i + 1]
        }
        let selftest = arg("--selftest"), bench = arg("--bench")
        // 자체 점검·속도 측정은 사용자가 고른 실험 스위치와 진단 기록을 건드리지 않는다
        if selftest != nil || bench != nil {
            Experiments.memoryOnly = [:]
        } else if Diag.wanted || args.contains("--diag") {
            Diag.start(reason: args.contains("--diag") ? "--diag" : "menu")
        }
        Diag.appState = { [weak self] in self?.diagState ?? "" }
        Diag.inkWindowNumbers = { [weak self] in self?.draw.inkWindowNumbers ?? [] }
        Diag.otherWindows = { [weak self] in
            guard let self else { return [] }
            var list: [(String, Int)] = []
            if self.spotlight.isOn, let n = self.spotlight.windowNumber { list.append(("spot", n)) }
            if let w = self.widget?.window { list.append(("widget", w.windowNumber)) }
            return list
        }
        Experiments.onChange = { [weak self] in self?.experimentsChanged() }

        Settings.shared.load()
        widget = Widget()
        widget.view.onAction = { [weak self] part in self?.widgetAction(part) }
        widget.view.contextMenu = { [weak self] in
            let m = NSMenu()
            self?.fillMenu(m)
            return m
        }

        clicks.enabledNow = { [weak self] in
            guard let self else { return false }
            return self.spotlight.isOn && !self.draw.isOn // 드로잉 중에는 강조와 함께 쉰다
        }
        clicks.start()

        draw.onStateChange = { [weak self] on in
            guard let self else { return }
            self.spotlight.suspended = on
            self.widget.view.drawOn = on
            // 위젯을 숨겨 둔 상태라면(showWidget = false) 드로잉을 켜고 꺼도 다시 나타나지 않아야 한다
            self.widget.setVisible(Settings.shared.showWidget) // 보일 때만 드로잉 판보다 위로
            self.updateSpotCursor()
            Diag.setActive(on || self.spotlight.isOn)
        }

        settingsWindow.onSave = { Settings.shared.save() }
        settingsWindow.onResetWidget = { [weak self] in
            self?.widget.moveToDefault()
            if let o = self?.widget.window.frame.origin { Settings.shared.saveWidgetPosition(o) }
        }
        settingsWindow.onQuit = { NSApp.terminate(nil) }

        // 설정 창에서 값을 움직이면 바로 반영
        changes = Settings.shared.objectWillChange.sink { [weak self] _ in
            DispatchQueue.main.async { self?.applySettings() }
        }

        // F8·F9 (맥북은 fn과 함께), 그리고 fn 없이 누를 수 있는 ⌃⌥1·⌃⌥2
        func hotkey(_ code: Int, _ mods: Int, _ name: String, _ action: @escaping () -> Void) {
            HotKeys.register(keyCode: code, modifiers: mods, name: name) {
                Diag.log("HK", "press \(name)")
                action()
            }
        }
        hotkey(kVK_F8, 0, "F8") { [weak self] in self?.toggleSpotlight() }
        hotkey(kVK_F9, 0, "F9") { [weak self] in self?.draw.toggle() }
        hotkey(kVK_ANSI_1, controlKey | optionKey, "⌃⌥1") { [weak self] in self?.toggleSpotlight() }
        hotkey(kVK_ANSI_2, controlKey | optionKey, "⌃⌥2") { [weak self] in self?.draw.toggle() }

        setupStatusItem()

        if let out = selftest { DispatchQueue.main.async { SelfTest.run(self, out: out) } }
        if let out = bench { DispatchQueue.main.async { Bench.run(self, out: out) } }
    }

    // 진단 기록 1초마다 한 줄에 들어가는 앱 상태
    var diagState: String {
        "draw=\(draw.isOn ? 1 : 0) spot=\(spotlight.isOn ? 1 : 0) mode=\(draw.keyMode.rawValue) "
            + "cursor=\(draw.boardCursor ? "board" : "system") hidden=\(SystemCursor.hidden ? 1 : 0) drawkeys=\(draw.carbonKeys.ids.count)"
    }

    // 실험 스위치가 바뀌면: 드로잉은 끄고(다음에 켤 때 새 방식으로 판을 만든다) 떠 있는 창들의 동작 조합을 바꾼다
    func experimentsChanged() {
        if draw.isOn { draw.turnOff(clear: false) }
        for w in NSApp.windows where w.level.rawValue >= OVERLAY_LEVEL.rawValue { w.collectionBehavior = EVERYWHERE }
        updateSpotCursor()
    }

    // 실험: 강조 중에는 화살표를 숨긴다 (드로잉 중에는 드로잉 쪽이 커서를 맡는다)
    func updateSpotCursor() {
        if Experiments.hideSpotCursor && spotlight.isOn && !draw.isOn {
            SystemCursor.hide("spot")
        } else {
            SystemCursor.show("spot")
        }
    }

    func applySettings() {
        spotlight.applySettings()
        widget.applySettings()
        draw.applySettings()
    }

    func toggleSpotlight() {
        spotlight.toggle()
        widget.view.spotOn = spotlight.isOn
        Diag.log("SPOT", spotlight.isOn ? "on" : "off")
        updateSpotCursor()
        Diag.setActive(spotlight.isOn || draw.isOn)
    }

    func widgetAction(_ part: WidgetView.Part) {
        switch part {
        case .spot: toggleSpotlight()
        case .draw: draw.isOn ? draw.turnOff(clear: true) : draw.turnOn() // 위젯으로 끄면 정리하고 나간다 (Esc와 같음)
        case .settings: openSettings()
        case .close:
            Settings.shared.showWidget = false
        case .grip: break
        }
    }

    // 드로잉 판이 화면을 덮고 있으면 설정 창을 누를 수 없으므로 드로잉을 먼저 끈다 (그린 것은 남긴다)
    @objc func openSettings() {
        if draw.isOn { draw.turnOff(clear: false) }
        settingsWindow.show()
    }

    // ---------- 메뉴 막대 아이콘 ----------
    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        if let url = Bundle.main.url(forResource: "icon_draw_dark", withExtension: "png"),
           let img = NSImage(contentsOf: url) {
            img.size = NSSize(width: 18, height: 18)
            img.isTemplate = true // 메뉴 막대 색(밝게/어둡게)에 맞춰 칠해진다
            statusItem.button?.image = img
        } else {
            statusItem.button?.title = "F&D"
        }
        let menu = NSMenu()
        menu.delegate = self
        statusItem.menu = menu
    }

    func menuNeedsUpdate(_ menu: NSMenu) { fillMenu(menu) }

    func fillMenu(_ menu: NSMenu) {
        menu.removeAllItems()
        func add(_ title: String, _ action: Selector, key: String = "", on: Bool = false) {
            let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
            item.target = self
            item.state = on ? .on : .off
            menu.addItem(item)
        }
        add("강조 (F8)", #selector(menuSpot), on: spotlight.isOn)
        add("드로잉 (F9)", #selector(menuDraw), on: draw.isOn)
        menu.addItem(.separator())
        add("위젯 표시", #selector(menuWidget), on: Settings.shared.showWidget)
        add("설정...", #selector(openSettings), key: ",")
        menu.addItem(.separator())
        add("진단 기록", #selector(menuDiag), on: Diag.isOn)
        add("진단 기록 폴더 열기", #selector(menuDiagFolder))
        Experiments.appendMenu(to: menu)
        menu.addItem(.separator())
        add("Focus & Draw 종료", #selector(menuQuit), key: "q")
    }

    @objc func menuSpot() { toggleSpotlight() }
    @objc func menuDraw() { draw.toggle() }
    @objc func menuWidget() { Settings.shared.showWidget.toggle() }
    @objc func menuQuit() { NSApp.terminate(nil) }

    // 켜 두면 앱을 다시 열어도 이어서 기록한다
    @objc func menuDiag() {
        if Diag.isOn {
            Diag.wanted = false
            Diag.stop()
        } else {
            Diag.wanted = true
            Diag.start(reason: "menu")
            Diag.setActive(draw.isOn || spotlight.isOn)
        }
    }

    @objc func menuDiagFolder() {
        try? FileManager.default.createDirectory(at: Diag.folder, withIntermediateDirectories: true)
        NSWorkspace.shared.open(Diag.folder)
    }

    // 수업 중 메뉴 막대에서 종료해도: 그린 것은 그대로 둔 채 드로잉만 끄고(판을 닫고, 커서를 되돌리고,
    // 드로잉 키 단축키를 풀고) 앱이 죽는다. 숨겨 둔 커서도 반드시 되돌린다.
    func applicationWillTerminate(_ n: Notification) {
        draw.turnOff(clear: false)
        SystemCursor.showAll()
        Diag.log("SESSION", "quit")
        Diag.stop()
    }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory) // Dock에 아이콘 없이 메뉴 막대에만
app.run()
