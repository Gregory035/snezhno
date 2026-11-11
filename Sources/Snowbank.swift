import SpriteKit

final class Snowbank {
    static let floorID = CGWindowID.max
    private static let binWidth: CGFloat = 5
    private static let maxDepth: CGFloat = 23

    let id: CGWindowID
    let node = SKShapeNode()
    private let shadow = SKShapeNode()
    private(set) var frame: CGRect = .zero
    private var amounts: [CGFloat] = []
    private var visible: [Bool] = []
    private var needsRendering = true
    private var binWidth: CGFloat { frame.width / CGFloat(max(1, amounts.count)) }

    init(id: CGWindowID) {
        self.id = id
        node.fillColor = SKColor(red: 0.95, green: 0.98, blue: 1, alpha: 1)
        node.strokeColor = .clear
        shadow.fillColor = SKColor(red: 0.52, green: 0.65, blue: 0.81, alpha: 0.68)
        shadow.strokeColor = .clear
        shadow.position.y = 1.5
        shadow.zPosition = -1
        node.addChild(shadow)
    }

    func update(frame: CGRect, occludedBy occluders: [CGRect], screen: CGRect) {
        let count = max(1, Int(ceil(frame.width / Self.binWidth)))
        if count != amounts.count {
            if count < amounts.count {
                amounts.removeLast(amounts.count - count)
            } else {
                amounts.append(contentsOf: repeatElement(0, count: count - amounts.count))
            }
            needsRendering = true
        }
        if self.frame.width != frame.width { needsRendering = true }
        self.frame = frame
        node.position = frame.origin

        let step = binWidth
        let candidates = occluders.filter {
            $0.minY < frame.minY && $0.maxY > frame.minY - Self.maxDepth
                && $0.minX < frame.maxX && $0.maxX > frame.minX
        }
        let visibility = amounts.indices.map { index in
            let point = CGPoint(x: frame.minX + (CGFloat(index) + 0.5) * step, y: frame.minY - 0.5)
            return point.x >= screen.minX && point.x <= screen.maxX
                && !candidates.contains { $0.contains(point) }
        }
        if visibility != visible {
            visible = visibility
            needsRendering = true
        }
    }

    func contains(x: CGFloat) -> Bool {
        guard x >= frame.minX, x < frame.maxX, !visible.isEmpty else { return false }
        return visible[index(at: x)]
    }

    func surface(at x: CGFloat) -> CGFloat {
        guard !amounts.isEmpty else { return frame.minY }
        return frame.minY - amounts[index(at: x)]
    }

    func deposit(at x: CGFloat, amount: CGFloat) {
        guard contains(x: x) else { return }
        let center = index(at: x)
        for (offset, weight) in [(-1, 0.35), (0, 1.0), (1, 0.35)] {
            let bin = center + offset
            if amounts.indices.contains(bin) {
                amounts[bin] = min(Self.maxDepth, amounts[bin] + amount * weight)
            }
        }
        needsRendering = true
    }

    @discardableResult
    func scoop(at x: CGFloat, radius: CGFloat, strength: CGFloat) -> CGFloat {
        guard !amounts.isEmpty, x + radius >= frame.minX, x - radius < frame.maxX else { return 0 }
        let start = index(at: x - radius)
        let end = index(at: x + radius)
        var total: CGFloat = 0
        for bin in start...end where visible[bin] && amounts[bin] > 0 {
            let center = frame.minX + (CGFloat(bin) + 0.5) * binWidth
            let falloff = max(0, 1 - abs(center - x) / radius)
            let removed = min(amounts[bin], strength * falloff)
            amounts[bin] -= removed
            total += removed
        }
        if total > 0 { needsRendering = true }
        return total
    }

    func clear() {
        amounts = Array(repeating: 0, count: amounts.count)
        needsRendering = true
        render()
    }

    func render() {
        guard needsRendering else { return }
        needsRendering = false
        let path = CGMutablePath()
        let step = binWidth
        var index = 0
        while index < amounts.count {
            guard visible[index], amounts[index] > 0.15 else {
                index += 1
                continue
            }
            let start = CGFloat(index) * step
            path.move(to: CGPoint(x: start, y: 0))
            var previous = CGPoint(x: start, y: 0)
            while index < amounts.count && visible[index] && amounts[index] > 0.15 {
                let point = CGPoint(x: (CGFloat(index) + 0.5) * step, y: -amounts[index])
                path.addQuadCurve(to: CGPoint(x: (point.x + previous.x) / 2,
                                              y: (point.y + previous.y) / 2), control: previous)
                previous = point
                index += 1
            }
            path.addQuadCurve(to: CGPoint(x: CGFloat(index) * step, y: 0), control: previous)
            path.closeSubpath()
        }
        node.path = path.isEmpty ? nil : path
        shadow.path = node.path
    }

    private func index(at x: CGFloat) -> Int {
        min(amounts.count - 1, max(0, Int((x - frame.minX) / binWidth)))
    }
}
