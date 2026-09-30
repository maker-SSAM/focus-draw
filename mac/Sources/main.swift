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
    var statusVisibility: NSKeyValueObservation?

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

        // 자체 점검·속도 측정은 사용자 settings.ini를 읽지 않는다 (기본값, 또는 --settings <고정 파일>)
        var loadResult = Settings.LoadResult.missing
        if let f = arg("--settings") { Settings.overridePath = URL(fileURLWithPath: f); loadResult = Settings.shared.load() }
        else if normalRun { loadResult = Settings.shared.load() }
        AppLog.write("SESSION", "start version=\(AppInfo.version) macOS=\(ProcessInfo.processInfo.operatingSystemVersionString) app=\((Bundle.main.bundlePath as NSString).abbreviatingWithTildeInPath)")
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
        if normalRun { showStartupNotices(loadResult) }

        if let out = selftest { DispatchQueue.main.async { SelfTest.run(self, out: out) } }
        if let out = bench { DispatchQueue.main.async { Bench.run(self, out: out) } }
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
            widget.setVisible(true)
        }
        return false
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
        // ⌘를 누른 채 끌어서 아이콘을 치울 수 있게 두되(막으면 메뉴 막대가 좁은 맥북에서 곤란하다), 빠졌는지는 기록해 둔다
        statusItem.autosaveName = "FocusDrawStatusItem"
        statusItem.behavior = .removalAllowed
        statusVisibility = statusItem.observe(\.isVisible, options: [.new]) { _, change in
            AppLog.write("STATUSITEM", "visible=\(change.newValue ?? true)")
        }
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
        let help = NSMenuItem(title: "도움말", action: nil, keyEquivalent: "")
        let sub = NSMenu()
        let ver = NSMenuItem(title: "Focus & Draw \(AppInfo.displayVersion)", action: nil, keyEquivalent: "")
        ver.isEnabled = false
        sub.addItem(ver)
        for (t, a) in [("진단 정보 복사", #selector(menuCopyDiag)), ("처음 안내 다시 보기", #selector(menuFirstRun))] {
            let i = NSMenuItem(title: t, action: a, keyEquivalent: "")
            i.target = self
            sub.addItem(i)
        }
        help.submenu = sub
        menu.addItem(help)
        Experiments.appendMenu(to: menu)
        menu.addItem(.separator())
        add("Focus & Draw 종료", #selector(menuQuit), key: "q")
    }

    @objc func menuSpot() { toggleSpotlight() }
    @objc func menuDraw() { draw.toggle() }
    @objc func menuWidget() { Settings.shared.showWidget.toggle() }
    @objc func menuFirstRun() { Notice.show(Notice.firstRun()) }

    // 문제가 생겼을 때 붙여 보낼 글을 클립보드에 복사한다 (이름·컴퓨터 이름은 들어 있지 않다)
    @objc func menuCopyDiag() {
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(DiagReport.build(), forType: .string)
        Notice.show(NoticeContent(
            title: "진단 정보를 복사했습니다",
            body: ["메모나 메신저에 붙여 넣어(⌘V) 보내 주세요.",
                   "버전, macOS, 맥 모델, 화면 크기, 기본값과 다른 설정, 최근 기록이 들어 있습니다. 사용자·컴퓨터 이름과 입력한 글자는 들어 있지 않습니다."]))
    }

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
        AppLog.write("SESSION", "quit")
        Diag.log("SESSION", "quit")
        Diag.stop()
    }
}

// 그림 기준 점검(--golden)은 창도 앱 실행 고리도 없이 한 번 돌고 끝난다 (화면 없는 컴퓨터에서도 돈다)
if CommandLine.arguments.contains("--golden") {
    _ = NSApplication.shared
    exit(Golden.run(CommandLine.arguments))
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory) // Dock에 아이콘 없이 메뉴 막대에만
app.run()
