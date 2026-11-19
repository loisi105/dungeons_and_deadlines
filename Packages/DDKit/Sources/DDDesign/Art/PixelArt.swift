import SwiftUI

/// A pixel-art image: a grid of palette indices (0 = transparent).
/// Some palette entries are marked as "eyes" so bosses can glow by phase.
public struct PixelArt: Sendable {
    public let width: Int
    public let height: Int
    /// Row-major palette indices; 0 is transparent, n is `colors[n - 1]`.
    public let pixels: [UInt8]
    public let colors: [UInt32]
    /// Palette indices (1-based) that are eyes.
    public let eyeIndices: Set<UInt8>
    /// Horizontal runs of one color, precomputed for fast drawing.
    let runs: [Run]

    struct Run: Sendable {
        let x: Int, y: Int, length: Int, index: UInt8
    }

    public init(width: Int, height: Int, pixels: [UInt8], colors: [UInt32], eyeIndices: Set<UInt8> = []) {
        precondition(pixels.count == width * height, "pixel count must be width × height")
        self.width = width
        self.height = height
        self.pixels = pixels
        self.colors = colors
        self.eyeIndices = eyeIndices
        var runs: [Run] = []
        for y in 0..<height {
            var x = 0
            while x < width {
                let index = pixels[y * width + x]
                var end = x + 1
                while end < width && pixels[y * width + end] == index { end += 1 }
                if index != 0 { runs.append(Run(x: x, y: y, length: end - x, index: index)) }
                x = end
            }
        }
        self.runs = runs
    }

    /// From text rows, where each character of `key` stands for the matching color.
    public init(key: String, colors: [UInt32], eyes: String = "", rows: [String]) {
        let lookup = Dictionary(uniqueKeysWithValues: key.enumerated().map { ($0.element, UInt8($0.offset + 1)) })
        let width = rows.map(\.count).max() ?? 0
        var pixels: [UInt8] = []
        pixels.reserveCapacity(width * rows.count)
        for row in rows {
            let chars = Array(row)
            for x in 0..<width {
                pixels.append(x < chars.count ? (lookup[chars[x]] ?? 0) : 0)
            }
        }
        self.init(
            width: width, height: rows.count, pixels: pixels, colors: colors,
            eyeIndices: Set(eyes.compactMap { lookup[$0] })
        )
    }

    public func color(at x: Int, _ y: Int) -> UInt32? {
        let index = pixels[y * width + x]
        return index == 0 ? nil : colors[Int(index) - 1]
    }

    /// Draws the art into `rect`, keeping square pixels and centering it.
    func draw(in context: GraphicsContext, rect: CGRect, eyeColor: Color?, fill: Bool = false) {
        let scale = fill
            ? max(rect.width / CGFloat(width), rect.height / CGFloat(height))
            : min(rect.width / CGFloat(width), rect.height / CGFloat(height))
        let originX = rect.midX - scale * CGFloat(width) / 2
        let originY = rect.midY - scale * CGFloat(height) / 2
        var palette = colors.map { Color(hex: $0) }
        if let eyeColor {
            for index in eyeIndices { palette[Int(index) - 1] = eyeColor }
        }
        for run in runs {
            // Overlap by a hair so no seams show between runs.
            let cell = CGRect(
                x: originX + CGFloat(run.x) * scale, y: originY + CGFloat(run.y) * scale,
                width: CGFloat(run.length) * scale + 0.5, height: scale + 0.5
            )
            context.fill(Path(cell), with: .color(palette[Int(run.index) - 1]))
        }
    }
}

/// Draws a `PixelArt` crisply at any size. Decorative: hidden from VoiceOver.
public struct PixelArtView: View {
    let art: PixelArt
    let eyeColor: Color?
    let fill: Bool

    /// - Parameter fill: cover the whole frame (cropping) instead of fitting inside it.
    public init(_ art: PixelArt, eyeColor: Color? = nil, fill: Bool = false) {
        self.art = art
        self.eyeColor = eyeColor
        self.fill = fill
    }

    public var body: some View {
        Canvas { context, size in
            art.draw(in: context, rect: CGRect(origin: .zero, size: size), eyeColor: eyeColor, fill: fill)
        }
        .accessibilityHidden(true)
    }
}
