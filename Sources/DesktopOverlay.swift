import AppKit
import SpriteKit

private final class SnowPanel: NSPanel {
    override var canBecomeKey: Bool { !ignoresMouseEvents }
    var exitTool: (() -> Void)?

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 {
            exitTool?()
        } else {
            super.keyDown(with: event)
        }
    }
}

private final class SnowView: SKView {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

final class DesktopOverlay {
    let scene: SnowScene
    private let panel: SnowPanel
    private let view: SnowView
    private(set) var display: CGRect
    private var hidden = true

    var windowNumber: Int { panel.windowNumber }

    init(screen: NSScreen, display: CGRect, settings: SnowSettings) {
        self.display = display
        panel = SnowPanel(contentRect: screen.frame, styleMask: [.borderless, .nonactivatingPanel],
                          backing: .buffered, defer: false, screen: screen)
        scene = SnowScene(size: screen.frame.size, settings: settings)
        view = SnowView(frame: CGRect(origin: .zero, size: screen.frame.size))
        view.allowsTransparency = true
        view.ignoresSiblingOrder = true
        view.preferredFramesPerSecond = 60
        view.presentScene(scene)
        view.isPaused = true
        panel.contentView = view
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.isMovable = false
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.ignoresMouseEvents = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        panel.level = .init(rawValue: Int(CGWindowLevelForKey(.mainMenuWindow)) - 1)
        panel.exitTool = { [weak settings] in settings?.tool = .cursor }
        updateFrame(screen: screen, display: display)
    }

    func updateFrame(screen: NSScreen, display: CGRect) {
        self.display = display
        panel.setFrame(screen.frame, display: true)
    }

    func setHidden(_ hidden: Bool) {
        guard hidden != self.hidden else { return }
        self.hidden = hidden
        view.isPaused = hidden
        if hidden {
            panel.ignoresMouseEvents = true
            scene.cancelDrag()
            panel.orderOut(nil)
        } else {
            panel.orderFrontRegardless()
        }
    }

    func setPowerSaving(_ enabled: Bool) {
        view.preferredFramesPerSecond = enabled ? 30 : 60
        scene.setPowerSaving(enabled)
    }

    func updateMouse(tool: SnowTool, cursor: CGPoint, overSettings: Bool) {
        let capture = !hidden && tool == .snowball &&
            (scene.isDragging || (!overSettings && scene.canStartSnowball(at: cursor)))
        if panel.ignoresMouseEvents == capture { panel.ignoresMouseEvents = !capture }
    }

    func contains(cursor: CGPoint) -> Bool { panel.frame.contains(cursor) }

    func addSnowman() -> Bool { !hidden && scene.addSnowman() }

    func close() {
        panel.close()
    }
}
