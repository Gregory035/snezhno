import AppKit
import SpriteKit

final class SnowScene: SKScene {
    private struct Flake {
        let node: SKSpriteNode
        let radius: CGFloat
        let speed: CGFloat
        let phase: CGFloat
        var point: CGPoint
    }

    private struct Powder {
        let node: SKSpriteNode
        var velocity: CGVector
        var life: CGFloat
    }

    private struct Ball {
        let bankID: CGWindowID
        let offset: CGFloat
        let elevation: CGFloat
        let radius: CGFloat
        let tier: Int
        let node: SKSpriteNode
    }

    private let settings: SnowSettings
    private let root = SKNode()
    private var banks: [CGWindowID: Snowbank] = [:]
    private var landingSurfaces: [Snowbank] = []
    private var foregroundSurfaces: [Snowbank] = []
    private var surfaceRows: [[Snowbank]] = []
    private let rowHeight: CGFloat = 48
    private var appWindowRects: [CGRect] = []
    private var lastWindows: [DesktopWindow] = []
    private var lastDisplay: CGRect = .null
    private var lastSurfaceOptions: [Bool] = []
    private var lastDepth: CGFloat = 0
    private var lastGeometrySample: TimeInterval?
    private var powder: [Powder] = []
    private var flakes: [Flake] = []
    private var balls: [Ball] = []
    private var dragNode: SKSpriteNode?
    private var dragRadius: CGFloat = 0
    private var lastDragPoint = CGPoint.zero
    private var previousCursor: CGPoint?
    private var lastFrame: TimeInterval?
    private var lastBankRender: TimeInterval = 0
    private var powerSaving = false

    var isDragging: Bool { dragNode != nil }

    func canStartSnowball(at cursor: CGPoint) -> Bool {
        guard let window = view?.window, window.frame.contains(cursor) else { return false }
        return isNearSnow(CGPoint(x: cursor.x - window.frame.minX, y: window.frame.maxY - cursor.y))
    }

    private func isNearSnow(_ point: CGPoint) -> Bool {
        landingSurfaces.contains {
            $0.contains(x: point.x) && abs($0.surface(at: point.x) - point.y) < 36
        }
    }

    private lazy var flakeTexture = Self.texture(snowball: false)
    private lazy var ballTexture = Self.texture(snowball: true)

    init(size: CGSize, settings: SnowSettings) {
        self.settings = settings
        super.init(size: size)
        backgroundColor = .clear
        scaleMode = .resizeFill
        addChild(root)
        root.yScale = -1
        root.position.y = size.height
    }

    required init?(coder: NSCoder) { nil }

    override func didChangeSize(_ oldSize: CGSize) {
        root.position.y = size.height
    }

    func setPowerSaving(_ enabled: Bool) {
        powerSaving = enabled
    }

    func refreshSurfaces(windows: [DesktopWindow], display: CGRect,
                         at time: TimeInterval = CACurrentMediaTime()) {
        let elapsed = time - (lastGeometrySample ?? time)
        lastGeometrySample = time
        let options = [settings.snowOnWindows, settings.snowOnDock, settings.snowOnFloor]
        let depth = CGFloat(settings.bankDepth)
        guard windows != lastWindows || display != lastDisplay
                || options != lastSurfaceOptions || depth != lastDepth else { return }
        let sameDisplay = display == lastDisplay
        lastWindows = windows
        lastDisplay = display
        lastSurfaceOptions = options
        lastDepth = depth

        var occluders: [CGRect] = []
        var next: [CGWindowID: Snowbank] = [:]
        var surfaces: [Snowbank] = []
        var windowRects: [CGRect] = []
        let viewport = CGRect(origin: .zero, size: size)
        for window in windows where window.frame.intersects(display) {
            let rect = window.frame.offsetBy(dx: -display.minX, dy: -display.minY)
            if !window.isDock { windowRects.append(rect) }
            if rect.minY >= 24 {
                let bankFrame = rect.insetBy(dx: window.isDock ? 6 : 8, dy: 0)
                let bank = banks[window.id] ?? makeBank(id: window.id)
                let previousFrame = bank.frame
                let enabled = window.isDock ? settings.snowOnDock : settings.snowOnWindows
                bank.node.isHidden = !enabled
                bank.update(frame: bankFrame, occludedBy: occluders, screen: viewport, maximumDepth: depth)
                if enabled {
                    surfaces.append(bank)
                    if sameDisplay && settings.shakeOffSnow && !window.isDock {
                        shake(bank, previousFrame: previousFrame, elapsed: elapsed, time: time)
                    }
                }
                next[window.id] = bank
            }
            occluders.append(rect)
        }
        let floorID = Snowbank.floorID
        let floor = banks[floorID] ?? makeBank(id: floorID)
        floor.node.isHidden = !settings.snowOnFloor
        floor.update(frame: CGRect(x: 0, y: size.height - 1, width: size.width, height: 1),
                     occludedBy: occluders, screen: viewport, maximumDepth: depth)
        next[floorID] = floor
        if settings.snowOnFloor { surfaces.append(floor) }
        for (id, bank) in banks where next[id] == nil { bank.node.removeFromParent() }
        banks = next
        appWindowRects = windowRects
        foregroundSurfaces = surfaces
        landingSurfaces = surfaces.sorted { $0.frame.minY < $1.frame.minY }
        rebuildSurfaceRows()
        if landingSurfaces.isEmpty { cancelDrag() }
        refreshBalls()
    }

    private func rebuildSurfaceRows() {
        let count = max(1, Int(ceil(size.height / rowHeight)) + 1)
        surfaceRows = Array(repeating: [], count: count)
        for bank in landingSurfaces {
            let first = max(0, Int((bank.frame.minY - bank.maximumDepth) / rowHeight))
            let last = min(count - 1, Int((bank.frame.minY + 7) / rowHeight))
            if first <= last {
                for row in first...last { surfaceRows[row].append(bank) }
            }
        }
    }

    private func shake(_ bank: Snowbank, previousFrame: CGRect, elapsed: TimeInterval, time: TimeInterval) {
        guard !previousFrame.isEmpty, bank.frame.size == previousFrame.size,
              elapsed > 0, elapsed < 0.4 else { return }
        let dx = bank.frame.minX - previousFrame.minX
        let dy = bank.frame.minY - previousFrame.minY
        let distance = hypot(dx, dy)
        let speed = distance / elapsed
        guard distance >= 18 && speed >= 410 else { return }
        let strength = min(0.92, 0.57 + (speed - 410) / 1300)
        let points = bank.shake(strength: strength, at: time)
        for point in points.prefix(max(0, 72 - powder.count)) {
            let width = CGFloat.random(in: 3...6)
            let node = SKSpriteNode(texture: flakeTexture, size: CGSize(width: width, height: width))
            node.position = point
            node.alpha = 0.85
            node.zPosition = 3
            root.addChild(node)
            powder.append(Powder(node: node,
                                 velocity: CGVector(dx: -dx / distance * 95 + .random(in: -32...32),
                                                    dy: -dy / distance * 58 + .random(in: -24...12)),
                                 life: .random(in: 0.55...1.0)))
        }
    }

    private func updatePowder(elapsed: CGFloat, masked: Bool) {
        for index in powder.indices.reversed() {
            powder[index].life -= elapsed
            let particle = powder[index]
            if particle.life <= 0 {
                particle.node.removeFromParent()
                powder.remove(at: index)
                continue
            }
            powder[index].velocity.dy += 220 * elapsed
            let position = CGPoint(x: particle.node.position.x + particle.velocity.dx * elapsed,
                                   y: particle.node.position.y + particle.velocity.dy * elapsed)
            particle.node.position = position
            particle.node.alpha = min(0.85, particle.life * 1.6)
            particle.node.isHidden = masked && appWindowRects.contains { $0.contains(position) }
        }
    }

    private func makeBank(id: CGWindowID) -> Snowbank {
        let bank = Snowbank(id: id)
        bank.node.zPosition = 2
        root.addChild(bank.node)
        return bank
    }

    @discardableResult
    func addSnowman() -> Bool {
        for bank in foregroundSurfaces where bank.frame.minY > 88 {
            for fraction in [0.60, 0.36, 0.78, 0.20] {
                let x = bank.frame.minX + bank.frame.width * fraction
                guard bank.contains(x: x - 16), bank.contains(x: x + 16),
                      !balls.contains(where: { $0.bankID == bank.id && abs($0.offset - x + bank.frame.minX) < 38 })
                else { continue }
                let base = placeBall(on: bank, x: x, radius: 15, elevation: 0, tier: 1)
                let body = placeBall(on: bank, x: x, radius: 11.5, elevation: 2 * base.radius - 1, tier: 2)
                let head = placeBall(on: bank, x: x, radius: 8.7,
                                     elevation: body.elevation + 2 * body.radius - 1, tier: 3)
                decorate(head: head, body: body)
                refreshBalls()
                return true
            }
        }
        return false
    }

    func clear() {
        for bank in banks.values { bank.clear() }
        for ball in balls { ball.node.removeFromParent() }
        balls.removeAll()
        for particle in powder { particle.node.removeFromParent() }
        powder.removeAll()
        cancelDrag()
    }

    override func update(_ currentTime: TimeInterval) {
        let dt = CGFloat(min(currentTime - (lastFrame ?? currentTime), 0.05))
        lastFrame = currentTime
        guard dt > 0 else { return }
        let count = Int(max(45, min(1500, size.width * size.height * settings.snowfall.density))
                        * (powerSaving ? 0.50 : 1))
        resizeFlakes(to: count)
        let time = CGFloat(currentTime.truncatingRemainder(dividingBy: 3600))
        let wind = CGFloat(settings.wind) * 150
        let speed = settings.snowfall.speed
        let buildup = CGFloat(settings.buildup)
        let masked = !settings.flakesOverWindows
        for index in flakes.indices {
            let flake = flakes[index]
            let old = flake.point
            var new = CGPoint(
                x: old.x + (wind + 17 * sin(time * 1.25 + flake.phase)) * dt,
                y: old.y + flake.speed * speed * dt
            )
            if new.x < -12 { new.x = size.width + 11 }
            if new.x > size.width + 12 { new.x = -11 }
            var landed = false
            let row = max(0, Int(new.y / rowHeight))
            let nearby = surfaceRows.indices.contains(row) ? surfaceRows[row] : []
            for bank in nearby {
                // Skip banks far outside the flake's vertical step.
                guard bank.frame.minY >= old.y, bank.frame.minY - bank.maximumDepth <= new.y,
                      bank.contains(x: new.x) else { continue }
                let y = bank.surface(at: new.x)
                if old.y <= y && new.y >= y {
                    bank.deposit(at: new.x, amount: (0.58 + flake.radius * 0.55) * buildup)
                    landed = true
                    break
                }
            }
            if landed || new.y > size.height + 6 {
                new = CGPoint(x: CGFloat.random(in: 0...size.width), y: CGFloat.random(in: -45 ... -6))
            }
            flakes[index].point = new
            flake.node.position = new
            let hidden = masked && appWindowRects.contains { $0.contains(new) }
            if flake.node.isHidden != hidden { flake.node.isHidden = hidden }
        }
        updatePowder(elapsed: dt, masked: masked)
        brushWithCursor()
        if currentTime - lastBankRender >= 1.0 / 10 {
            for bank in landingSurfaces { bank.render() }
            refreshBalls()
            lastBankRender = currentTime
        }
    }

    private func resizeFlakes(to count: Int) {
        if flakes.count > count {
            for flake in flakes.suffix(flakes.count - count) { flake.node.removeFromParent() }
            flakes.removeLast(flakes.count - count)
        }
        while flakes.count < count {
            let depth = CGFloat.random(in: 0...1)
            let radius = 0.54 + pow(depth, 1.8) * 1.44
            let point = CGPoint(x: CGFloat.random(in: 0...size.width), y: CGFloat.random(in: 0...size.height))
            let node = SKSpriteNode(texture: flakeTexture,
                                    size: CGSize(width: radius * 3.6, height: radius * 3.6))
            node.position = point
            node.alpha = 0.42 + depth * 0.57
            node.zPosition = depth > 0.82 ? 6 : 1
            root.addChild(node)
            flakes.append(Flake(node: node, radius: radius, speed: 28 + depth * 61,
                                phase: CGFloat.random(in: 0...(2 * .pi)), point: point))
        }
    }

    private func brushWithCursor() {
        guard settings.tool == .mitten, let window = view?.window else {
            previousCursor = nil
            return
        }
        let cursor = NSEvent.mouseLocation
        guard window.frame.contains(cursor) else {
            previousCursor = nil
            return
        }
        let point = CGPoint(x: cursor.x - window.frame.minX, y: window.frame.maxY - cursor.y)
        defer { previousCursor = point }
        guard let last = previousCursor else { return }
        let distance = hypot(last.x - point.x, last.y - point.y)
        guard distance > 0.25 else { return }
        let samples = min(24, max(1, Int(ceil(distance / 9))))
        for sample in 1...samples {
            let progress = CGFloat(sample) / CGFloat(samples)
            let x = last.x + (point.x - last.x) * progress
            let y = last.y + (point.y - last.y) * progress
            for bank in landingSurfaces where abs(bank.frame.minY - y) < 29 {
                bank.scoop(at: x, radius: 27, strength: 3.5 + min(distance, 25) * 0.23)
            }
        }
    }

    private func point(for event: NSEvent) -> CGPoint {
        let point = event.location(in: self)
        return CGPoint(x: point.x, y: size.height - point.y)
    }

    override func mouseDown(with event: NSEvent) {
        guard settings.tool == .snowball else { return }
        cancelDrag()
        let point = point(for: event)
        guard isNearSnow(point) else { return }
        view?.window?.makeKey()
        dragRadius = 5
        lastDragPoint = point
        let node = makeBallNode(radius: dragRadius)
        node.position = CGPoint(x: point.x, y: point.y - dragRadius)
        root.addChild(node)
        dragNode = node
    }

    override func mouseDragged(with event: NSEvent) {
        guard let node = dragNode else { return }
        let point = point(for: event)
        let distance = hypot(point.x - lastDragPoint.x, point.y - lastDragPoint.y)
        for bank in landingSurfaces where bank.contains(x: point.x)
            && abs(bank.surface(at: point.x) - point.y) < 34 {
            let removed = bank.scoop(at: point.x, radius: max(13, dragRadius),
                                     strength: min(8, distance * 0.25))
            dragRadius = min(24, sqrt(dragRadius * dragRadius + removed * 0.42))
            break
        }
        node.size = CGSize(width: 2 * dragRadius, height: 2 * dragRadius)
        node.position = CGPoint(x: point.x, y: point.y - dragRadius)
        lastDragPoint = point
    }

    override func mouseUp(with event: NSEvent) {
        guard isDragging else { return }
        let point = point(for: event)
        defer { cancelDrag() }
        guard dragRadius >= 6 else { return }
        if let support = balls.reversed().first(where: { candidate in
            !candidate.node.isHidden && candidate.tier < 3 && dragRadius <= candidate.radius * 1.05
                && abs(candidate.node.position.x - point.x) < candidate.radius + 15
                && abs(candidate.node.position.y - candidate.radius - point.y) < 26
                && !balls.contains { other in
                    other.bankID == candidate.bankID && other.offset == candidate.offset && other.tier > candidate.tier
                }
        }), let bank = banks[support.bankID] {
            let radius = min(dragRadius, support.radius * 0.80)
            let ball = placeBall(on: bank, x: support.node.position.x, radius: radius,
                                 elevation: support.elevation + 2 * support.radius - 1,
                                 tier: support.tier + 1)
            if ball.tier == 3 { decorate(head: ball, body: support) }
        } else if let bank = landingSurfaces
            .filter({ $0.contains(x: point.x) && abs($0.surface(at: point.x) - point.y) < 120 })
            .min(by: { abs($0.surface(at: point.x) - point.y) < abs($1.surface(at: point.x) - point.y) }) {
            placeBall(on: bank, x: point.x, radius: dragRadius, elevation: 0, tier: 1)
        }
        refreshBalls()
    }

    func cancelDrag() {
        dragNode?.removeFromParent()
        dragNode = nil
    }

    private func makeBallNode(radius: CGFloat) -> SKSpriteNode {
        let node = SKSpriteNode(texture: ballTexture, size: CGSize(width: 2 * radius, height: 2 * radius))
        node.zPosition = 5
        return node
    }

    @discardableResult
    private func placeBall(on bank: Snowbank, x: CGFloat, radius: CGFloat,
                           elevation: CGFloat, tier: Int) -> Ball {
        let node = makeBallNode(radius: radius)
        let ball = Ball(bankID: bank.id, offset: x - bank.frame.minX,
                        elevation: elevation, radius: radius, tier: tier, node: node)
        root.addChild(node)
        balls.append(ball)
        return ball
    }

    private func refreshBalls() {
        // Keep balls for temporarily hidden windows, such as a minimized Finder window.
        for ball in balls {
            guard let bank = banks[ball.bankID], !bank.node.isHidden else {
                ball.node.isHidden = true
                continue
            }
            let x = bank.frame.minX + ball.offset
            ball.node.isHidden = !bank.contains(x: x)
            ball.node.position = CGPoint(x: x, y: bank.surface(at: x) - ball.radius - ball.elevation)
        }
    }

    private func decorate(head: Ball, body: Ball) {
        let coal = SKColor(red: 0.13, green: 0.17, blue: 0.22, alpha: 1)
        let scarf = SKColor(red: 0.84, green: 0.15, blue: 0.24, alpha: 1)
        let orange = SKColor(red: 1, green: 0.51, blue: 0.21, alpha: 1)
        let r = head.radius
        func dot(_ x: CGFloat, _ y: CGFloat, radius: CGFloat, parent: SKNode) {
            let node = SKShapeNode(circleOfRadius: radius)
            node.position = CGPoint(x: x, y: y)
            node.fillColor = coal
            node.strokeColor = .clear
            node.zPosition = 1
            parent.addChild(node)
        }
        for x in [-r * 0.28, r * 0.28] { dot(x, -r * 0.22, radius: max(0.85, r * 0.09), parent: head.node) }
        for offset in -2...2 {
            let x = CGFloat(offset)
            dot(x * r * 0.13, r * (0.36 - abs(x) * 0.035), radius: max(0.46, r * 0.053), parent: head.node)
        }
        for y in [-body.radius * 0.02, body.radius * 0.39] {
            dot(0, y, radius: max(0.9, body.radius * 0.08), parent: body.node)
        }
        let nose = CGMutablePath()
        nose.move(to: CGPoint(x: -r * 0.08, y: -r * 0.04))
        nose.addLine(to: CGPoint(x: r * 0.58, y: r * 0.14))
        nose.addLine(to: CGPoint(x: -r * 0.07, y: r * 0.18))
        nose.closeSubpath()
        let carrot = SKShapeNode(path: nose)
        carrot.fillColor = orange
        carrot.strokeColor = .clear
        carrot.zPosition = 1
        head.node.addChild(carrot)
        let wrap = SKShapeNode(rectOf: CGSize(width: r * 1.70, height: r * 0.30), cornerRadius: r * 0.14)
        wrap.position = CGPoint(x: 0, y: r * 0.85)
        wrap.fillColor = scarf
        wrap.strokeColor = .clear
        wrap.zPosition = 1
        head.node.addChild(wrap)
        let end = SKShapeNode(rectOf: CGSize(width: r * 0.35, height: r * 0.9), cornerRadius: r * 0.08)
        end.position = CGPoint(x: r * 0.55, y: r * 1.28)
        end.zRotation = -0.24
        end.fillColor = scarf
        end.strokeColor = .clear
        end.zPosition = 1
        head.node.addChild(end)
    }

    private static func texture(snowball: Bool) -> SKTexture {
        let size = 64
        let space = CGColorSpace(name: CGColorSpace.sRGB)!
        let context = CGContext(data: nil, width: size, height: size, bitsPerComponent: 8,
                                bytesPerRow: 0, space: space,
                                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        let center = CGPoint(x: 32, y: 32)
        let colors = snowball
            ? [CGColor(red: 1, green: 1, blue: 1, alpha: 1),
               CGColor(red: 0.93, green: 0.97, blue: 1, alpha: 1),
               CGColor(red: 0.65, green: 0.76, blue: 0.87, alpha: 1)]
            : [CGColor(red: 1, green: 1, blue: 1, alpha: 1),
               CGColor(red: 0.96, green: 0.98, blue: 1, alpha: 0.95),
               CGColor(red: 0.8, green: 0.9, blue: 1, alpha: 0)]
        let gradient = CGGradient(colorsSpace: space, colors: colors as CFArray,
                                  locations: snowball ? [0, 0.48, 1] : [0, 0.39, 1])!
        context.drawRadialGradient(gradient,
                                   startCenter: snowball ? CGPoint(x: 24, y: 40) : center, startRadius: 0,
                                   endCenter: center, endRadius: 31, options: [])
        return SKTexture(cgImage: context.makeImage()!)
    }
}
