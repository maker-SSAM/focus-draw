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
        Settings.shared.load()
        widget = Widget()
        widget.view.onAction = { [weak self] part in self?.widgetAction(part) }

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
        HotKeys.register(keyCode: kVK_F8) { [weak self] in self?.toggleSpotlight() }
        HotKeys.register(keyCode: kVK_F9) { [weak self] in self?.draw.toggle() }
        HotKeys.register(keyCode: kVK_ANSI_1, modifiers: controlKey | optionKey) { [weak self] in self?.toggleSpotlight() }
        HotKeys.register(keyCode: kVK_ANSI_2, modifiers: controlKey | optionKey) { [weak self] in self?.draw.toggle() }

        setupStatusItem()

        let args = CommandLine.arguments
        if let i = args.firstIndex(of: "--selftest"), i + 1 < args.count {
            DispatchQueue.main.async { SelfTest.run(self, out: args[i + 1]) }
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

    func menuNeedsUpdate(_ menu: NSMenu) {
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
        add("Focus & Draw 종료", #selector(menuQuit), key: "q")
    }

    @objc func menuSpot() { toggleSpotlight() }
    @objc func menuDraw() { draw.toggle() }
    @objc func menuWidget() { Settings.shared.showWidget.toggle() }
    @objc func menuQuit() { NSApp.terminate(nil) }

    // 수업 중 메뉴 막대에서 종료해도: 그린 것은 그대로 둔 채 드로잉만 끄고(판을 닫고, 커서를 되돌리고)
    // 앱이 죽는다. draw.turnOff가 이미 판 닫기·커서 복구·이전 앱 활성화를 다 한다.
    func applicationWillTerminate(_ n: Notification) {
        draw.turnOff(clear: false)
    }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory) // Dock에 아이콘 없이 메뉴 막대에만
app.run()
