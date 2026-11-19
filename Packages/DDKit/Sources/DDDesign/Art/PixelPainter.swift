import Foundation

/// A tiny pixel-art painter for bosses in the style of the icon art:
/// a 64×64 grid, simple shapes with three-tone cel shading (light from the
/// top-left) and a one-pixel dark outline added automatically around everything.
struct PixelPainter {
    /// Light, base and shadow tones of one surface.
    struct Material {
        let light: UInt32, base: UInt32, dark: UInt32
        init(_ light: UInt32, _ base: UInt32, _ dark: UInt32) {
            self.light = light
            self.base = base
            self.dark = dark
        }
    }

    static let outlineColor: UInt32 = 0x1A0D1F

    let size: Int
    /// Material id per cell (0 = empty). Ids above `flatBase` are flat detail colors.
    private var cells: [Int]
    private var materials: [Material] = []
    private var flats: [UInt32] = []
    private var eyeFlat: Int?
    private let flatBase = 1000

    init(size: Int = 64) {
        self.size = size
        cells = Array(repeating: 0, count: size * size)
    }

    // MARK: Palette

    mutating func material(_ m: Material) -> Int {
        materials.append(m)
        return materials.count
    }

    /// A flat (unshaded) detail color, e.g. teeth, pupils.
    mutating func flat(_ color: UInt32) -> Int {
        if let i = flats.firstIndex(of: color) { return flatBase + i + 1 }
        flats.append(color)
        return flatBase + flats.count
    }

    /// The color that glows with the boss phase.
    mutating func eye() -> Int {
        if let eyeFlat { return eyeFlat }
        let id = flat(0xE0342F)
        eyeFlat = id
        return id
    }

    // MARK: Shapes (coordinates in cells; `mirror` repeats across the vertical center)

    mutating func set(_ x: Int, _ y: Int, _ id: Int) {
        guard x >= 0, y >= 0, x < size, y < size else { return }
        cells[y * size + x] = id
    }

    mutating func pixel(_ x: Int, _ y: Int, _ id: Int, mirror: Bool = false) {
        set(x, y, id)
        if mirror { set(size - 1 - x, y, id) }
    }

    mutating func rect(_ x0: Int, _ y0: Int, _ x1: Int, _ y1: Int, _ id: Int, mirror: Bool = false) {
        for y in min(y0, y1)...max(y0, y1) {
            for x in min(x0, x1)...max(x0, x1) { pixel(x, y, id, mirror: mirror) }
        }
    }

    mutating func ellipse(_ cx: Double, _ cy: Double, _ rx: Double, _ ry: Double, _ id: Int, mirror: Bool = false) {
        // Only visit cells inside the bounding box.
        let ys = clamp(Int(cy - ry - 1))...clamp(Int(cy + ry + 1))
        let xs = clamp(Int(cx - rx - 1))...clamp(Int(cx + rx + 1))
        for y in ys {
            for x in xs {
                let dx = (Double(x) + 0.5 - cx) / rx
                let dy = (Double(y) + 0.5 - cy) / ry
                if dx * dx + dy * dy <= 1 { pixel(x, y, id, mirror: mirror) }
            }
        }
    }

    mutating func polygon(_ points: [(Double, Double)], _ id: Int, mirror: Bool = false) {
        let ys = clamp(Int(points.map(\.1).min()! - 1))...clamp(Int(points.map(\.1).max()! + 1))
        let xs = clamp(Int(points.map(\.0).min()! - 1))...clamp(Int(points.map(\.0).max()! + 1))
        for y in ys {
            for x in xs where Self.contains(points, Double(x) + 0.5, Double(y) + 0.5) {
                pixel(x, y, id, mirror: mirror)
            }
        }
    }

    private func clamp(_ v: Int) -> Int { min(max(v, 0), size - 1) }

    /// A thick line made of discs, for tentacles, legs and staffs.
    mutating func stroke(_ points: [(Double, Double)], width: Double, _ id: Int, mirror: Bool = false) {
        guard points.count > 1 else { return }
        for i in 0..<(points.count - 1) {
            let (x0, y0) = points[i]
            let (x1, y1) = points[i + 1]
            let steps = max(1, Int(hypot(x1 - x0, y1 - y0).rounded(.up)))
            for s in 0...steps {
                let t = Double(s) / Double(steps)
                ellipse(x0 + (x1 - x0) * t, y0 + (y1 - y0) * t, width / 2, width / 2, id, mirror: mirror)
            }
        }
    }

    /// Clears cells (cut-outs such as mouths).
    mutating func erase(_ x0: Int, _ y0: Int, _ x1: Int, _ y1: Int, mirror: Bool = false) {
        rect(x0, y0, x1, y1, 0, mirror: mirror)
    }

    static func contains(_ poly: [(Double, Double)], _ x: Double, _ y: Double) -> Bool {
        var inside = false
        var j = poly.count - 1
        for i in 0..<poly.count {
            let (xi, yi) = poly[i]
            let (xj, yj) = poly[j]
            if (yi > y) != (yj > y), x < (xj - xi) * (y - yi) / (yj - yi) + xi { inside.toggle() }
            j = i
        }
        return inside
    }

    // MARK: Output

    /// Shades every material, adds the outline and returns the image.
    func render() -> PixelArt {
        var colors: [UInt32] = []
        var colorIndex: [UInt32: UInt8] = [:]
        func index(_ c: UInt32) -> UInt8 {
            if let i = colorIndex[c] { return i }
            colors.append(c)
            let i = UInt8(colors.count)
            colorIndex[c] = i
            return i
        }
        func id(_ x: Int, _ y: Int) -> Int {
            guard x >= 0, y >= 0, x < size, y < size else { return 0 }
            return cells[y * size + x]
        }

        var pixels = [UInt8](repeating: 0, count: size * size)
        for y in 0..<size {
            for x in 0..<size {
                let c = id(x, y)
                if c == 0 {
                    // Outline: empty cells touching anything.
                    if id(x - 1, y) != 0 || id(x + 1, y) != 0 || id(x, y - 1) != 0 || id(x, y + 1) != 0 {
                        pixels[y * size + x] = index(Self.outlineColor)
                    }
                    continue
                }
                if c > flatBase {
                    pixels[y * size + x] = index(flats[c - flatBase - 1])
                    continue
                }
                let m = materials[c - 1]
                // Light from the top-left: edges facing it are light, the opposite edges dark.
                let lit = id(x, y - 1) != c || id(x - 1, y) != c || id(x, y - 2) != c
                let shadowed = id(x, y + 1) != c || id(x + 1, y) != c || id(x + 1, y + 2) != c
                let tone = shadowed ? m.dark : (lit ? m.light : m.base)
                pixels[y * size + x] = index(tone)
            }
        }
        let eyes: Set<UInt8> = eyeFlat.flatMap { colorIndex[flats[$0 - flatBase - 1]] }.map { [$0] } ?? []
        return PixelArt(width: size, height: size, pixels: pixels, colors: colors, eyeIndices: eyes)
    }
}

/// Shared palette, matched to the icon art.
enum Palette {
    static let gold = PixelPainter.Material(0xFFF0A8, 0xFFD24A, 0xE3A321)
    static let brass = PixelPainter.Material(0xE3A321, 0xA8691A, 0x6B3D12)
    static let bone = PixelPainter.Material(0xFFFBEA, 0xF6E6BD, 0xC9AE78)
    static let steel = PixelPainter.Material(0xF4F8FF, 0xC8D8F0, 0x7E94BA)
    static let stone = PixelPainter.Material(0xB9B1A3, 0x8D8478, 0x5E574F)
    static let moss = PixelPainter.Material(0x8FD16A, 0x4E9A3A, 0x2C6328)
    static let jade = PixelPainter.Material(0x7BE0B0, 0x3FA77F, 0x22684F)
    static let ocean = PixelPainter.Material(0xA6DCF5, 0x4FA3D9, 0x2D6E9E)
    static let violet = PixelPainter.Material(0xC9A0E8, 0x8A54B8, 0x55307A)
    static let plum = PixelPainter.Material(0xB07CC6, 0x7A3E8E, 0x4E2560)
    static let ember = PixelPainter.Material(0xFF8A5B, 0xE0342F, 0x7A1426)
    static let wood = PixelPainter.Material(0xC98A4B, 0x8A4A22, 0x5A2E12)
    static let ghost = PixelPainter.Material(0xFFFFFF, 0xE6ECFF, 0xA9B6E0)
    static let night = PixelPainter.Material(0x5C4A7A, 0x3A2B55, 0x231736)
    static let mushroomRed = PixelPainter.Material(0xFF7A6B, 0xD4382C, 0x8A1C17)
    static let skin = PixelPainter.Material(0xF6D7B0, 0xE2B07E, 0xA8764A)
    static let black: UInt32 = 0x1A0D1F
    static let white: UInt32 = 0xFFFFFF
    static let mouth: UInt32 = 0x7A1426
    static let tongue: UInt32 = 0xE86A7A
}
