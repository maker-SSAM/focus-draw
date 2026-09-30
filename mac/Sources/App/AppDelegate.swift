import AppKit
import Combine

// 조립만 한다. "무엇이 켜져 있는가"는 AppState가, 설정값은 Settings가 든다.
// 상태가 바뀌면 applyState() 하나가 강조·클릭 링·위젯·설정 창의 보임을 다시 정하고,
// 설정이 바뀌면 applySettings()가 바뀐 묶음만 다시 적용한다.
@MainActor final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    let state = AppState.shared
    let spotlight = Spotlight()
    let clicks = ClickEffect()
    let draw = DrawSession(state: AppState.shared)
    let settingsWindow = SettingsWindowController()
    var widget: Widget!
    var statusItem: NSStatusItem!
    var changes: AnyCancellable?
    var statusVisibility: NSKeyValueObservation?

    // 마지막으로 적용한 설정 묶음 (바뀐 묶음만 다시 적용하려고)
    private struct Applied: Equatable {
        var spot: [Double]
        var widget: [Double]
        var draw: DrawConfig
        init(_ s: Settings) {
            spot = [s.spotSize, s.spotOpacity, Double(s.spotColor)]
            widget = [s.widgetScale, s.widgetOpacity, Double(s.widgetColor)]
            draw = DrawConfig(s)
        }
    }
    private var applied = Applied(Settings.shared)

    func applicationDidFinishLaunching(_ n: Notification) {
        let args = CommandLine.arguments
        func arg(_ name: String) -> String? {
            guard let i = args.firstIndex(of: name), i + 1 < args.count else { return nil }
            return args[i + 1]
        }
        let selftest = arg("--selftest"), bench = arg("--bench")
        // 자체 점검·속도 측정은 사용자가 고른 실험 스위치와 진단 기록을 건드리지 않는다
        let normalRun = selftest == nil && bench == nil
        if !normalRun {
            AppLog.folder = nil // 사용자 기록에는 적지 않는다
            Experiments.memoryOnly = [:]
        } else if Log.wanted || args.contains("--diag") {
            Log.start(reason: args.contains("--diag") ? "--diag" : "menu")
        }
        Log.appState = { [weak self] in self?.diagState ?? "" }
        Log.inkWindowNumbers = { [weak self] in self?.draw.inkWindowNumbers ?? [] }
        Log.otherWindows = { [weak self] in
            guard let self else { return [] }
            var list: [(String, Int)] = []
            if self.state.highlightVisible, let n = self.spotlight.windowNumber { list.append(("spot", n)) }
            if let w = self.widget?.window { list.append(("widget", w.windowNumber)) }
            return list
        }
        Experiments.onChange = { [weak self] in self?.updateSpotCursor() }

        // 자체 점검·속도 측정은 사용자 settings.ini를 읽지 않는다 (기본값, 또는 --settings <고정 파일>)
        var loadResult = Settings.LoadResult.missing
        if let f = arg("--settings") { Settings.overridePath = URL(fileURLWithPath: f); loadResult = Settings.shared.load() }
        else if normalRun { loadResult = Settings.shared.load() }
        applied = Applied(Settings.shared)
        AppLog.write("SESSION", "start version=\(AppInfo.version) macOS=\(ProcessInfo.processInfo.operatingSystemVersionString) app=\((Bundle.main.bundlePath as NSString).abbreviatingWithTildeInPath)")
        widget = Widget(state: state)
        widget.view.onAction = { [weak self] part in self?.widgetAction(part) }
        widget.view.contextMenu = { [weak self] in
            let m = NSMenu()
            self?.fillMenu(m)
            return m
        }

        clicks.enabledNow = { [weak self] in self?.state.highlightVisible ?? false } // 드로잉 중에는 강조와 함께 쉰다
        clicks.start()
        draw.makeConfig = { DrawConfig(Settings.shared) }

        state.widgetVisible = Settings.shared.showWidget
        state.onChange = { [weak self] in self?.applyState() }
        applyState()

        settingsWindow.onSave = {
            if let e = Settings.shared.save() {
                Notice.show(Notice.saveFailed(e))
                return false
            }
            return true
        }
        settingsWindow.onResetWidget = { [weak self] in
            self?.widget.moveToDefault()
            if let o = self?.widget.window.frame.origin { Settings.shared.saveWidgetPosition(o) }
        }
        settingsWindow.onQuit = { NSApp.terminate(nil) }

        // 설정 창에서 값을 움직이면 바로 반영
        changes = Settings.shared.objectWillChange.sink { [weak self] _ in
            DispatchQueue.main.async { self?.applySettings() }
        }

        // 앱이 도는 동안 늘 있는 단축키 (묶음 app): settings.ini [Hotkeys]의 Spotlight·Draw(기본 F8·F9)와,
        // fn 없이 누를 수 있는 맥 전용 SpotlightAlt·DrawAlt(기본 ⌃⌥1·⌃⌥2). 못 잡은 것은 기록에만 남긴다.
        draw.keys.blockExcluding = {
            Set(SettingsSchema.hotkeys.compactMap { HotkeyNotation.parse(Settings.shared.hotkeys[$0.name] ?? $0.def) })
        }
        draw.onKeysFailed = { r in Notice.show(Notice.drawKeysFailed(r)) }
        registerAppHotkeys()

        setupStatusItem()
        if normalRun { showStartupNotices(loadResult) }

        if let out = selftest { DispatchQueue.main.async { SelfTest.run(self, out: out) } }
        if let out = bench { DispatchQueue.main.async { Bench.run(self, out: out) } }
    }

    func registerAppHotkeys() {
        let actions: [String: () -> Void] = [
            "Spotlight": { [weak self] in self?.toggleSpotlight() }, "SpotlightAlt": { [weak self] in self?.toggleSpotlight() },
            "Draw": { [weak self] in self?.draw.toggle() }, "DrawAlt": { [weak self] in self?.draw.toggle() },
        ]
        let entries: [HotKeyEntry] = SettingsSchema.hotkeys.compactMap { h in
            guard let combo = HotkeyNotation.parse(Settings.shared.hotkeys[h.name] ?? h.def), let action = actions[h.name] else { return nil }
            return HotKeyEntry(name: h.name, combo: combo, press: { _ in Log.log("HK", "press \(h.name)"); action() })
        }
        HotKeyRegistry.shared.registerGroup(.app, entries, policy: .skipFailures)
    }

    // 처음 열었을 때·문제가 있을 때만 안내 창을 띄운다 (자체 점검·측정 실행에서는 부르지 않는다)
    func showStartupNotices(_ load: Settings.LoadResult) {
        if case .unreadable(let reason, let backup) = load {
            Notice.show(Notice.unreadable(reason: reason, backup: backup))
        }
        if Notice.isTranslocated() {
            AppLog.write("SESSION", "translocated")
            Notice.show(Notice.translocated())
        }
        if !UserDefaults.standard.bool(forKey: "firstRunNoticeShown") {
            UserDefaults.standard.set(true, forKey: "firstRunNoticeShown")
            Notice.show(Notice.firstRun())
        }
    }

    // 앱을 Finder·Spotlight·Launchpad로 다시 열면: 위젯이 숨겨져 있으면 위젯을 보이고, 이미 보이면 설정을 연다
    // (메뉴 막대 아이콘을 치웠거나 위젯을 숨겨 둔 채 앱을 잊었을 때 다시 찾는 길)
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        AppLog.write("REOPEN", "widget=\(Settings.shared.showWidget ? "shown" : "hidden")")
        if Settings.shared.showWidget {
            openSettings()
        } else {
            Settings.shared.showWidget = true
            state.widgetVisible = true
        }
        return false
    }

    // 진단 기록 1초마다 한 줄에 들어가는 앱 상태
    var diagState: String {
        "draw=\(state.drawOn ? 1 : 0) spot=\(state.spotOn ? 1 : 0) "
            + "hidden=\(SystemCursor.hidden ? 1 : 0) drawkeys=\(draw.keys.ids.count) blockkeys=\(draw.keys.blockIDs.count)"
    }

    // ---------- 상태가 바뀌면 보임을 한 곳에서 다시 정한다 ----------
    func applyState() {
        spotlight.visible = state.highlightVisible
        widget.setVisible(state.widgetVisible)
        widget.view.needsDisplay = true
        updateSpotCursor()
        Log.setActive(state.drawOn || state.spotOn)
        // 드로잉 판이 설정 창을 덮으므로 드로잉 동안만 숨겼다가, 끝나면 되돌린다
        if state.drawOn {
            if !state.settingsHiddenByDraw, settingsWindow.hideForDraw() { state.settingsHiddenByDraw = true }
        } else if state.settingsHiddenByDraw {
            state.settingsHiddenByDraw = false
            settingsWindow.restoreAfterDraw()
        }
    }

    // 실험: 강조 중에는 화살표를 숨긴다 (드로잉 중에는 드로잉 쪽이 커서를 맡는다)
    func updateSpotCursor() {
        if Experiments.hideSpotCursor && state.highlightVisible {
            SystemCursor.hide(.spot)
        } else {
            SystemCursor.show(.spot)
        }
    }

    // 바뀐 묶음만 다시 적용한다
    func applySettings() {
        let now = Applied(Settings.shared)
        if now.spot != applied.spot { spotlight.applySettings() }
        if now.widget != applied.widget { widget.applySettings() }
        if now.draw != applied.draw { draw.applySettings() }
        applied = now
        state.widgetVisible = Settings.shared.showWidget
    }

    func toggleSpotlight() {
        state.spotOn.toggle()
        Log.log("SPOT", state.spotOn ? "on" : "off")
    }

    func widgetAction(_ part: WidgetView.Part) {
        switch part {
        case .spot: toggleSpotlight()
        case .draw: draw.isOn ? draw.turnOff(.widgetButton) : draw.turnOn() // 위젯으로 끄면 정리하고 나간다 (Esc와 같음)
        case .settings: openSettings()
        case .close:
            Settings.shared.showWidget = false
        case .grip: break
        }
    }

    // 드로잉 판이 화면을 덮고 있으면 설정 창을 누를 수 없으므로 드로잉을 먼저 끈다 (그린 것은 남긴다)
    @objc func openSettings() {
        if draw.isOn { draw.turnOff(.settings) }
        settingsWindow.show()
    }

    // 수업 중 메뉴 막대에서 종료해도: 그린 것은 그대로 둔 채 드로잉만 끄고(판을 닫고, 커서를 되돌리고,
    // 드로잉 키 단축키를 풀고) 앱이 죽는다. 숨겨 둔 커서도 반드시 되돌린다.
    func applicationWillTerminate(_ n: Notification) {
        draw.turnOff(.quit)
        HotKeyRegistry.shared.unregisterAll()
        SystemCursor.showAll()
        AppLog.write("SESSION", "quit")
        Log.log("SESSION", "quit")
        Log.stop()
    }
}
