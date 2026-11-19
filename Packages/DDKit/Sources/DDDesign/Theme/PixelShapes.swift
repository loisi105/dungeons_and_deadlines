import SwiftUI

/// A rectangle with stepped, pixel-art corners (two steps of `step` points).
public struct PixelCornerShape: InsettableShape {
    public var step: CGFloat
    var inset: CGFloat = 0

    public init(step: CGFloat = 4) { self.step = step }

    public func inset(by amount: CGFloat) -> PixelCornerShape {
        var copy = self
        copy.inset += amount
        return copy
    }

    public func path(in rect: CGRect) -> Path {
        let r = rect.insetBy(dx: inset, dy: inset)
        let s = min(step, r.width / 4, r.height / 4)
        var p = Path()
        p.move(to: CGPoint(x: r.minX + 2 * s, y: r.minY))
        p.addLine(to: CGPoint(x: r.maxX - 2 * s, y: r.minY))
        p.addLine(to: CGPoint(x: r.maxX - 2 * s, y: r.minY + s))
        p.addLine(to: CGPoint(x: r.maxX - s, y: r.minY + s))
        p.addLine(to: CGPoint(x: r.maxX - s, y: r.minY + 2 * s))
        p.addLine(to: CGPoint(x: r.maxX, y: r.minY + 2 * s))
        p.addLine(to: CGPoint(x: r.maxX, y: r.maxY - 2 * s))
        p.addLine(to: CGPoint(x: r.maxX - s, y: r.maxY - 2 * s))
        p.addLine(to: CGPoint(x: r.maxX - s, y: r.maxY - s))
        p.addLine(to: CGPoint(x: r.maxX - 2 * s, y: r.maxY - s))
        p.addLine(to: CGPoint(x: r.maxX - 2 * s, y: r.maxY))
        p.addLine(to: CGPoint(x: r.minX + 2 * s, y: r.maxY))
        p.addLine(to: CGPoint(x: r.minX + 2 * s, y: r.maxY - s))
        p.addLine(to: CGPoint(x: r.minX + s, y: r.maxY - s))
        p.addLine(to: CGPoint(x: r.minX + s, y: r.maxY - 2 * s))
        p.addLine(to: CGPoint(x: r.minX, y: r.maxY - 2 * s))
        p.addLine(to: CGPoint(x: r.minX, y: r.minY + 2 * s))
        p.addLine(to: CGPoint(x: r.minX + s, y: r.minY + 2 * s))
        p.addLine(to: CGPoint(x: r.minX + s, y: r.minY + s))
        p.addLine(to: CGPoint(x: r.minX + 2 * s, y: r.minY + s))
        p.closeSubpath()
        return p
    }
}

/// Parchment with a soft vignette (light) or dungeon bricks (dark), very subtle so
/// text on the page keeps its contrast. Plain color with Increase Contrast or Reduce Transparency.
public struct DungeonBackground: View {
    @Environment(\.colorScheme) private var scheme
    @Environment(\.colorSchemeContrast) private var contrast
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    public init() {}

    public var body: some View {
        ZStack {
            Theme.parchment
            if contrast != .increased && !reduceTransparency {
                // Only the dungeon gets a pattern. Specks on parchment made text
                // measure as low-contrast, so light mode keeps just the vignette.
                if scheme == .dark {
                    Canvas(rendersAsynchronously: true) { context, size in
                        drawBricks(context: context, size: size)
                    }
                }
                RadialGradient(
                    colors: [.clear, Theme.parchmentDeep.opacity(scheme == .dark ? 0.7 : 0.55)],
                    center: .center, startRadius: 200, endRadius: 700
                )
            }
        }
        .ignoresSafeArea()
        .accessibilityHidden(true)
    }

    private func drawBricks(context: GraphicsContext, size: CGSize) {
        let brickW: CGFloat = 48
        let brickH: CGFloat = 24
        var rng = SeededGenerator(seed: 7)
        var y: CGFloat = 0
        var row = 0
        while y < size.height {
            var x: CGFloat = row.isMultiple(of: 2) ? 0 : -brickW / 2
            while x < size.width {
                let rect = CGRect(x: x + 1, y: y + 1, width: brickW - 2, height: brickH - 2)
                let shade = Double.random(in: 0.02...0.045, using: &rng)
                context.fill(Path(rect), with: .color(Color(hex: 0xC9B7FF).opacity(shade)))
                x += brickW
            }
            y += brickH
            row += 1
        }
    }
}

/// Deterministic random numbers so the texture doesn't change between redraws.
struct SeededGenerator: RandomNumberGenerator {
    private var state: UInt64
    init(seed: UInt64) { state = seed &* 0x9E3779B97F4A7C15 | 1 }
    mutating func next() -> UInt64 {
        state ^= state << 13
        state ^= state >> 7
        state ^= state << 17
        return state
    }
}
