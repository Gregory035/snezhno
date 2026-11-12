import AppKit
import Metal
import QuartzCore
import SpriteKit

/// Drives each screen independently; SKView's display clock can stall on high-refresh external displays.
final class SnowRenderView: NSView {
    let scene: SnowScene
    private let metalLayer = CAMetalLayer()
    private let renderer: SKRenderer
    private let commandQueue: MTLCommandQueue
    private let availableFrames = DispatchSemaphore(value: 2)
    private var timer: Timer?
    private var running = false
    private var frameRate = 30

    init?(frame: CGRect, scene: SnowScene, displayID: CGDirectDisplayID) {
        guard let device = CGDirectDisplayCopyCurrentMetalDevice(displayID) ?? MTLCreateSystemDefaultDevice(),
              let queue = device.makeCommandQueue() else { return nil }
        self.scene = scene
        renderer = SKRenderer(device: device)
        commandQueue = queue
        super.init(frame: frame)
        renderer.scene = scene
        renderer.ignoresSiblingOrder = true
        renderer.shouldCullNonVisibleNodes = true
        metalLayer.device = device
        metalLayer.pixelFormat = .bgra8Unorm
        metalLayer.isOpaque = false
        metalLayer.framebufferOnly = true
        metalLayer.maximumDrawableCount = 2
        metalLayer.presentsWithTransaction = false
        wantsLayer = true
        layer = metalLayer
        scene.hostView = self
    }

    required init?(coder: NSCoder) { nil }
    override var isOpaque: Bool { false }
    override var acceptsFirstResponder: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func layout() {
        super.layout()
        resizeDrawable()
    }

    override func viewDidChangeBackingProperties() {
        super.viewDidChangeBackingProperties()
        resizeDrawable()
    }

    private func resizeDrawable() {
        let scale = window?.backingScaleFactor ?? 1
        let pixels = CGSize(width: max(1, bounds.width * scale), height: max(1, bounds.height * scale))
        if metalLayer.drawableSize != pixels {
            metalLayer.contentsScale = scale
            metalLayer.drawableSize = pixels
            scene.size = bounds.size
        }
    }

    func setRunning(_ enabled: Bool) {
        guard running != enabled else { return }
        running = enabled
        restartTimer()
    }

    func setFrameRate(_ rate: Int) {
        guard frameRate != rate else { return }
        frameRate = rate
        restartTimer()
    }

    private func restartTimer() {
        timer?.invalidate()
        timer = nil
        guard running else { return }
        resizeDrawable()
        let timer = Timer(timeInterval: 1 / Double(frameRate), repeats: true) { [weak self] _ in
            self?.drawFrame()
        }
        timer.tolerance = 0.0005
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    private func drawFrame() {
        guard running, availableFrames.wait(timeout: .now()) == .success else { return }
        autoreleasepool {
            guard let drawable = metalLayer.nextDrawable(),
                  let buffer = commandQueue.makeCommandBuffer() else {
                availableFrames.signal()
                return
            }
            renderer.update(atTime: CACurrentMediaTime())
            let pass = MTLRenderPassDescriptor()
            pass.colorAttachments[0].texture = drawable.texture
            pass.colorAttachments[0].loadAction = .clear
            pass.colorAttachments[0].storeAction = .store
            pass.colorAttachments[0].clearColor = MTLClearColorMake(0, 0, 0, 0)
            renderer.render(withViewport: CGRect(origin: .zero, size: metalLayer.drawableSize),
                            commandBuffer: buffer, renderPassDescriptor: pass)
            let semaphore = availableFrames
            buffer.addCompletedHandler { _ in semaphore.signal() }
            buffer.present(drawable)
            buffer.commit()
        }
    }

    override func mouseDown(with event: NSEvent) { scene.mouseDown(with: event) }
    override func mouseDragged(with event: NSEvent) { scene.mouseDragged(with: event) }
    override func mouseUp(with event: NSEvent) { scene.mouseUp(with: event) }

    deinit { timer?.invalidate() }
}
