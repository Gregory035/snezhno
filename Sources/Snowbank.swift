import SpriteKit

final class Snowbank {
    static let floorID = CGWindowID.max
    static let dockID = CGWindowID.max - 1
    private static let sampleWidth: CGFloat = 4
    private static let depositWeights: [CGFloat] = [0.10, 0.26, 0.54, 1, 0.54, 0.26, 0.10]

    let id: CGWindowID
    let node = SKShapeNode()
    private let shadow = SKShapeNode()
    private let grain = SKShapeNode()
    private(set) var frame: CGRect = .zero
    private(set) var maximumDepth: CGFloat = 16
    private var amounts: [CGFloat] = []
    private var capacity: [CGFloat] = []
    private var clearance: [CGFloat] = []
    private var taper: [CGFloat] = []
    private var needsRendering = true
    private var changeSinceRender: CGFloat = 0
    private var lastShake: TimeInterval = -.infinity
    private var binWidth: CGFloat { frame.width / CGFloat(max(1, amounts.count)) }

    init(id: CGWindowID) {
        self.id = id
        node.fillColor = .white
        node.fillTexture = Self.snowTexture
        node.strokeColor = .clear
        shadow.fillColor = SKColor(red: 0.19, green: 0.28, blue: 0.39, alpha: 0.26)
        shadow.strokeColor = .clear
        shadow.position.y = 0.85
        shadow.zPosition = -1
        node.addChild(shadow)
        grain.fillColor = SKColor(white: 1, alpha: 0.30)
        grain.strokeColor = .clear
        grain.zPosition = 1
        node.addChild(grain)
    }

    func update(frame: CGRect, occludedBy occluders: [CGRect], screen: CGRect, maximumDepth: CGFloat) {
        let count = max(1, Int(ceil(frame.width / Self.sampleWidth)))
        if count != amounts.count {
            if count < amounts.count {
                amounts.removeLast(amounts.count - count)
                capacity.removeLast(capacity.count - count)
            } else {
                for bin in amounts.count..<count {
                    amounts.append(0)
                    let phase = CGFloat(bin)
                    capacity.append(0.78 + 0.13 * sin(phase * 0.19) + 0.07 * sin(phase * 0.67 + 1.4))
                }
            }
            needsRendering = true
        }
        if self.frame.width != frame.width || self.maximumDepth != maximumDepth { needsRendering = true }
        self.frame = frame
        self.maximumDepth = maximumDepth
        node.position = frame.origin

        let step = binWidth
        let candidates = occluders.filter {
            $0.minY < frame.minY && $0.maxY > frame.minY - maximumDepth
                && $0.minX < frame.maxX && $0.maxX > frame.minX
        }
        let clearances: [CGFloat] = amounts.indices.map { bin in
            let left = frame.minX + CGFloat(bin) * step
            let right = left + step
            guard right > screen.minX, left < screen.maxX else { return 0 }
            return candidates.reduce(maximumDepth) { depth, rect in
                guard rect.minX < right, rect.maxX > left else { return depth }
                return min(depth, max(0, frame.minY - rect.maxY - 0.8))
            }
        }
        if clearances != clearance {
            clearance = clearances
            taper = amounts.indices.map { bin in
                // Round off the lip at corners and against overlapping windows.
                for distance in 0...3 {
                    let left = bin - distance
                    let right = bin + distance
                    if left < 0 || right >= count || min(clearance[left], clearance[right]) < 0.35 {
                        return [0, 0.45, 0.75, 0.93][distance]
                    }
                }
                return 1
            }
            needsRendering = true
        }
    }

    func contains(x: CGFloat) -> Bool {
        guard !node.isHidden, x >= frame.minX, x < frame.maxX, !clearance.isEmpty else { return false }
        return clearance[index(at: x)] >= 0.35
    }

    func surface(at x: CGFloat) -> CGFloat {
        guard !amounts.isEmpty else { return frame.minY }
        return frame.minY - depth(at: index(at: x))
    }

    func deposit(at x: CGFloat, amount: CGFloat) {
        let center = index(at: x)
        for (offset, weight) in Self.depositWeights.enumerated() {
            let bin = center + offset - 3
            guard amounts.indices.contains(bin), clearance[bin] >= 0.35 else { continue }
            // Packed snow collects progressively less, preserving variations in a full drift.
            let added = min(capacity[bin] - amounts[bin],
                            weight * amount / 16 * (1 - amounts[bin] / capacity[bin]))
            amounts[bin] += added
            changeSinceRender += added * maximumDepth
        }
    }

    @discardableResult
    func scoop(at x: CGFloat, radius: CGFloat, strength: CGFloat) -> CGFloat {
        guard !amounts.isEmpty, x + radius >= frame.minX, x - radius < frame.maxX else { return 0 }
        let start = index(at: x - radius)
        let end = index(at: x + radius)
        var total: CGFloat = 0
        for bin in start...end where clearance[bin] >= 0.35 && amounts[bin] > 0 {
            let center = frame.minX + (CGFloat(bin) + 0.5) * binWidth
            let falloff = max(0, 1 - abs(center - x) / radius)
            let removed = min(amounts[bin] * maximumDepth, strength * falloff)
            amounts[bin] -= removed / maximumDepth
            total += removed
        }
        if total > 0 { needsRendering = true }
        return total
    }

    func shake(strength: CGFloat, at time: TimeInterval) -> [CGPoint] {
        guard time - lastShake > 0.18 else { return [] }
        var points: [CGPoint] = []
        let strideWidth = max(4, amounts.count / 18)
        for bin in amounts.indices {
            let depth = depth(at: bin)
            if depth >= 1 && bin % strideWidth == strideWidth / 2 {
                points.append(CGPoint(x: frame.minX + (CGFloat(bin) + 0.5) * binWidth,
                                      y: frame.minY - depth * 0.68))
            }
        }
        guard !points.isEmpty else { return [] }
        lastShake = time
        for bin in amounts.indices { amounts[bin] *= 1 - strength }
        needsRendering = true
        return points
    }

    func transferSnow(to target: Snowbank) {
        guard !target.amounts.isEmpty else { return }
        for bin in amounts.indices where amounts[bin] > 0 {
            let x = frame.minX + (CGFloat(bin) + 0.5) * binWidth
            guard x >= target.frame.minX, x < target.frame.maxX else { continue }
            let destination = target.index(at: x)
            let amount = amounts[bin] * maximumDepth / target.maximumDepth * binWidth / target.binWidth
            target.amounts[destination] = min(target.capacity[destination], target.amounts[destination] + amount)
            amounts[bin] = 0
        }
        needsRendering = true
        target.needsRendering = true
    }

    func clear() {
        amounts = Array(repeating: 0, count: amounts.count)
        needsRendering = true
        render()
    }

    func render() {
        guard needsRendering || changeSinceRender >= 0.45 else { return }
        needsRendering = false
        changeSinceRender = 0
        let body = CGMutablePath()
        let flecks = CGMutablePath()
        let depths = amounts.indices.map { depth(at: $0) }
        let step = binWidth
        var bin = 0
        while bin < depths.count {
            guard depths[bin] >= 0.24 else {
                bin += 1
                continue
            }
            let start = CGFloat(bin) * step
            body.move(to: CGPoint(x: start, y: 0))
            var previous = CGPoint(x: start, y: 0)
            while bin < depths.count && depths[bin] >= 0.24 {
                let depth = depths[bin]
                let x = (CGFloat(bin) + 0.5) * step
                let point = CGPoint(x: x, y: -depth)
                let middle = CGPoint(x: (point.x + previous.x) / 2, y: (point.y + previous.y) / 2)
                body.addQuadCurve(to: middle, control: previous)
                previous = point
                if depth > 3.5 && bin % 3 == 1 {
                    let width = min(4.2, depth * 0.45)
                    flecks.addEllipse(in: CGRect(x: x - width / 2, y: -depth * 0.63,
                                                 width: width, height: min(1.4, depth * 0.17)))
                }
                bin += 1
            }
            body.addQuadCurve(to: CGPoint(x: CGFloat(bin) * step, y: 0), control: previous)
            body.closeSubpath()
        }
        node.path = body.isEmpty ? nil : body
        shadow.path = node.path
        grain.path = flecks.isEmpty ? nil : flecks
    }

    private func depth(at bin: Int) -> CGFloat {
        let center = amounts[bin]
        let left = bin > 0 && clearance[bin - 1] >= 0.35 ? amounts[bin - 1] : center
        let right = bin + 1 < amounts.count && clearance[bin + 1] >= 0.35 ? amounts[bin + 1] : center
        return min(clearance[bin], maximumDepth * taper[bin] * (0.72 * center + 0.14 * (left + right)))
    }

    private func index(at x: CGFloat) -> Int {
        min(amounts.count - 1, max(0, Int((x - frame.minX) / binWidth)))
    }

    private static let snowTexture: SKTexture = {
        let width = 64
        let height = 64
        var bytes: [UInt8] = []
        for y in 0..<height {
            let shade = pow(Double(y) / Double(height - 1), 1.8)
            for x in 0..<width {
                let grain = Double((x * 173 + y * 337 + x * y * 29) % 11 - 5) * 0.6
                for base in [42.0, 26, 12] {
                    bytes.append(UInt8(clamping: Int((254 - base * shade + grain).rounded())))
                }
                bytes.append(255)
            }
        }
        let provider = CGDataProvider(data: Data(bytes) as CFData)!
        let image = CGImage(width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32,
                            bytesPerRow: width * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                            bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.last.rawValue),
                            provider: provider, decode: nil, shouldInterpolate: true,
                            intent: .defaultIntent)!
        return SKTexture(cgImage: image)
    }()
}
