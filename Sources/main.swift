import AppKit
import Combine
import SwiftUI

final class SnowApp: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private let settings = SnowSettings()
    private var status: NSStatusItem!
    private var overlays: [CGDirectDisplayID: DesktopOverlay] = [:]
    private var settingsWindow: NSWindow?
    private var geometryTimer: Timer?
    private var mouseTimer: Timer?
    private var keyMonitor: Any?
    private var lastGeometryRefresh: TimeInterval = 0
    private var dockAnimationUntil: TimeInterval = 0
    private var lastDockFrames: [CGRect] = []
    private var subscriptions = Set<AnyCancellable>()

    func applicationDidFinishLaunching(_ notification: Notification) {
        status = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        status.autosaveName = "Snezhno"
        status.isVisible = true
        updateStatusIcon()
        let menu = NSMenu()
        menu.delegate = self
        menu.autoenablesItems = false
        status.menu = menu

        NotificationCenter.default.addObserver(self, selector: #selector(rebuildDisplays),
                                               name: NSApplication.didChangeScreenParametersNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(updatePower),
                                               name: .NSProcessInfoPowerStateDidChange, object: nil)
        NSWorkspace.shared.notificationCenter.addObserver(self, selector: #selector(refreshGeometry),
                                                          name: NSWorkspace.activeSpaceDidChangeNotification, object: nil)

        settings.$paused.dropFirst().sink { [weak self] paused in
            DispatchQueue.main.async {
                guard let self, self.settings.paused == paused else { return }
                if paused { self.settings.tool = .cursor }
                self.updateStatusIcon()
                self.refreshGeometry()
            }
        }.store(in: &subscriptions)
        settings.$tool.dropFirst().sink { [weak self] tool in
            DispatchQueue.main.async {
                guard let self else { return }
                if tool != .snowball { self.overlays.values.forEach { $0.scene.cancelDrag() } }
                self.mouseTimer?.invalidate()
                self.mouseTimer = tool == .snowball
                    ? self.startTimer(interval: 1.0 / 30, selector: #selector(self.refreshMouse))
                    : nil
                self.refreshMouse()
            }
        }.store(in: &subscriptions)
        settings.$smoothAnimation.dropFirst().sink { [weak self] _ in
            DispatchQueue.main.async { self?.updatePower() }
        }.store(in: &subscriptions)

        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard event.keyCode == 53, let self, self.settings.tool != .cursor else { return event }
            self.settings.tool = .cursor
            return nil
        }
        rebuildDisplays()
        geometryTimer = startTimer(interval: 1.0 / 30, selector: #selector(refreshGeometry))
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? ""
        if UserDefaults.standard.string(forKey: "settingsShownForVersion") != version {
            UserDefaults.standard.set(version, forKey: "settingsShownForVersion")
            showSettings()
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        geometryTimer?.invalidate()
        mouseTimer?.invalidate()
        if let keyMonitor { NSEvent.removeMonitor(keyMonitor) }
        for overlay in overlays.values { overlay.close() }
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        showSettings()
        return true
    }

    private func startTimer(interval: TimeInterval, selector: Selector) -> Timer {
        let timer = Timer(timeInterval: interval, target: self, selector: selector, userInfo: nil, repeats: true)
        timer.tolerance = interval * 0.2
        RunLoop.main.add(timer, forMode: .common)
        return timer
    }

    @objc private func rebuildDisplays() {
        var previous = overlays
        var next: [CGDirectDisplayID: DesktopOverlay] = [:]
        for screen in NSScreen.screens {
            guard let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber else {
                continue
            }
            let id = CGDirectDisplayID(number.uint32Value)
            let display = CGDisplayBounds(id)
            guard let overlay = previous.removeValue(forKey: id)
                ?? DesktopOverlay(screen: screen, display: display, settings: settings) else { continue }
            overlay.updateFrame(screen: screen, display: display)
            next[id] = overlay
        }
        for overlay in previous.values { overlay.close() }
        overlays = next
        updatePower()
        refreshGeometry()
    }

    @objc private func updatePower() {
        let enabled = ProcessInfo.processInfo.isLowPowerModeEnabled
        for overlay in overlays.values {
            overlay.updateAnimation(powerSaving: enabled, smooth: settings.smoothAnimation)
        }
    }

    @objc private func refreshGeometry() {
        guard !settings.paused else {
            for overlay in overlays.values { overlay.setHidden(true) }
            return
        }
        let now = CACurrentMediaTime()
        guard now - lastGeometryRefresh >= 1.0 / 12 || now < dockAnimationUntil else { return }
        lastGeometryRefresh = now
        let windows = WindowTracking.snapshot(overlayIDs: Set(overlays.values.map(\.windowNumber)))
        let dockFrames = windows.filter(\.isDock).map(\.frame)
        if dockFrames != lastDockFrames {
            dockAnimationUntil = now + 0.4
            lastDockFrames = dockFrames
        }
        for overlay in overlays.values {
            let hidden = settings.fullscreenPause && WindowTracking.isFullscreen(windows, on: overlay.display)
            overlay.setHidden(hidden)
            if !hidden { overlay.scene.refreshSurfaces(windows: windows, display: overlay.display) }
        }
    }

    @objc private func refreshMouse() {
        let cursor = NSEvent.mouseLocation
        let overSettings = settingsWindow?.isVisible == true && settingsWindow?.frame.contains(cursor) == true
        for overlay in overlays.values { overlay.updateMouse(tool: settings.tool, cursor: cursor, overSettings: overSettings) }
    }

    private func updateStatusIcon() {
        let image = NSImage(systemSymbolName: settings.paused ? "pause.circle" : "snowflake",
                            accessibilityDescription: settings.paused ? "Снежно на паузе" : "Снежно")
        image?.isTemplate = true
        status.button?.image = image
        status.button?.toolTip = "Снежно"
        status.button?.setAccessibilityLabel("Снежно")
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        item(settings.paused ? "Продолжить снегопад" : "Приостановить снегопад",
             action: #selector(togglePause), key: "", menu: menu)
        item("Настройки…", action: #selector(showSettings), key: ",", menu: menu)
        menu.addItem(.separator())

        let weather = NSMenuItem(title: "Снегопад", action: nil, keyEquivalent: "")
        let presets = NSMenu()
        weather.submenu = presets
        for preset in Snowfall.allCases {
            let row = item(preset.label, action: #selector(selectSnowfall(_:)), key: "", menu: presets)
            row.representedObject = preset.rawValue
            row.state = preset == settings.snowfall ? .on : .off
        }
        menu.addItem(weather)

        let tools = NSMenuItem(title: "Инструмент", action: nil, keyEquivalent: "")
        let toolMenu = NSMenu()
        tools.submenu = toolMenu
        for tool in SnowTool.allCases {
            let row = item(tool.label, action: #selector(selectTool(_:)), key: "", menu: toolMenu)
            row.image = NSImage(systemSymbolName: tool.symbol, accessibilityDescription: nil)
            row.representedObject = tool.rawValue
            row.state = tool == settings.tool ? .on : .off
        }
        menu.addItem(tools)
        item("Поставить снеговика", action: #selector(addSnowman), key: "", menu: menu)
            .isEnabled = settings.hasSnowSurfaces
        item("Очистить снег", action: #selector(clearSnow), key: "", menu: menu)
        menu.addItem(.separator())
        item("Выйти из «Снежно»", action: #selector(quit), key: "q", menu: menu)
    }

    @discardableResult
    private func item(_ title: String, action: Selector, key: String, menu: NSMenu) -> NSMenuItem {
        let row = NSMenuItem(title: title, action: action, keyEquivalent: key)
        row.target = self
        menu.addItem(row)
        return row
    }

    @objc private func togglePause() { settings.paused.toggle() }
    @objc private func quit() { NSApp.terminate(nil) }
    @objc private func addSnowman() {
        settings.paused = false
        refreshGeometry()
        let cursor = NSEvent.mouseLocation
        let preferred = overlays.values.first { $0.contains(cursor: cursor) }
        if preferred?.addSnowman() == true { return }
        for overlay in overlays.values where overlay !== preferred {
            if overlay.addSnowman() { return }
        }
        NSSound.beep()
    }

    @objc private func clearSnow() { overlays.values.forEach { $0.scene.clear() } }

    @objc private func selectSnowfall(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String, let preset = Snowfall(rawValue: raw) else { return }
        settings.snowfall = preset
    }

    @objc private func selectTool(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String, let tool = SnowTool(rawValue: raw) else { return }
        if tool != .cursor { settings.paused = false }
        settings.tool = tool
    }

    @objc private func showSettings() {
        status.isVisible = true
        if settingsWindow == nil {
            let content = NSHostingView(rootView: SettingsView(settings: settings, clear: { [weak self] in
                self?.clearSnow()
            }))
            let window = NSWindow(contentRect: CGRect(origin: .zero, size: content.fittingSize),
                                  styleMask: [.titled, .closable], backing: .buffered, defer: false)
            window.contentView = content
            window.title = "Снежно"
            window.appearance = NSAppearance(named: .darkAqua)
            window.isReleasedWhenClosed = false
            window.isMovableByWindowBackground = true
            window.center()
            settingsWindow = window
        }
        settingsWindow?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}

let app = NSApplication.shared
let delegate = SnowApp()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
