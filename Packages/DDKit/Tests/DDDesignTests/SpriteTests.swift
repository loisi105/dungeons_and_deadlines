import Foundation
import Testing
import GameCore
@testable import DDDesign
#if canImport(AppKit)
import AppKit
#endif

@Suite("Pixel art")
struct SpriteTests {
    @Test("Every boss is 64x64, has an outline, and glowing eyes", arguments: BossKind.allCases)
    func bossArt(kind: BossKind) {
        let art = kind.art
        #expect(art.width == 64 && art.height == 64)
        #expect(art.colors.contains(PixelPainter.outlineColor))
        #expect(!art.eyeIndices.isEmpty, "\(kind) has no eyes to glow")
        let filled = art.pixels.filter { $0 != 0 }.count
        #expect(filled > 900, "\(kind) looks empty (\(filled) pixels)")
    }

    @Test("Icon layers convert to 64x64 grids")
    func iconLayers() {
        for art in [PixelArt.nightSky, .alarmClock, .sword] {
            #expect(art.width == 64 && art.height == 64)
        }
        #expect(PixelArt.nightSky.pixels.allSatisfy { $0 != 0 }, "the background should be fully opaque")
    }

    @Test("Boss names pick a look", arguments: [
        ("Exam Dragon", BossKind.dragon), ("Thesis Hydra", .dragon), ("Deadline Lich", .alarmClock),
        ("Procrastination Wraith", .lich), ("Slide Deck Golem", .golem), ("Group Project Kraken", .kraken),
        ("Citation Goblin", .goblin), ("Midterm Mimic", .mimic), ("Wifi Phantom", .ghost),
        ("Syntax Spider", .spider), ("Burnout Shroom", .mushroom), ("Proctor Cyclops", .cyclops),
    ])
    func mapping(name: String, kind: BossKind) {
        #expect(BossKind.forName(name) == kind)
    }

    @Test("Unknown names always get the same look")
    func stableFallback() {
        #expect(BossKind.forName("Mysterious Thing") == BossKind.forName("Mysterious Thing"))
    }

    /// Writes every boss as a PNG for visual review: `DD_DUMP_ART=/some/dir swift test`.
    @Test("Dump art to PNG", .enabled(if: ProcessInfo.processInfo.environment["DD_DUMP_ART"] != nil))
    func dump() throws {
        #if canImport(AppKit)
        let dir = URL(fileURLWithPath: ProcessInfo.processInfo.environment["DD_DUMP_ART"]!)
        let items = BossKind.allCases.map { ($0.rawValue, $0.art) } + [("nightSky", PixelArt.nightSky), ("sword", PixelArt.sword)]
        for (name, art) in items {
            try png([art], scale: 6).write(to: dir.appendingPathComponent("\(name).png"))
        }
        try png(BossKind.allCases.map(\.art), scale: 4, columns: 4).write(to: dir.appendingPathComponent("sheet.png"))
        #endif
    }

    #if canImport(AppKit)
    func png(_ arts: [PixelArt], scale: Int, columns: Int = 1) throws -> Data {
        let cell = 64 * scale + 8
        let rows = (arts.count + columns - 1) / columns
        let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: cell * min(columns, arts.count), pixelsHigh: cell * rows,
                                   bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                   colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
        let bg: [Int] = [243, 230, 200]
        let data = rep.bitmapData!
        let stride = rep.bytesPerRow
        for py in 0..<(cell * rows) {
            for px in 0..<(cell * min(columns, arts.count)) {
                let i = (py / cell) * columns + px / cell
                let lx = (px % cell) - 4, ly = (py % cell) - 4
                var rgb = bg
                if i < arts.count, lx >= 0, ly >= 0, lx < 64 * scale, ly < 64 * scale, let c = arts[i].color(at: lx / scale, ly / scale) {
                    rgb = [Int((c >> 16) & 0xFF), Int((c >> 8) & 0xFF), Int(c & 0xFF)]
                }
                let o = py * stride + px * 4
                data[o] = UInt8(rgb[0]); data[o + 1] = UInt8(rgb[1]); data[o + 2] = UInt8(rgb[2]); data[o + 3] = 255
            }
        }
        return rep.representation(using: .png, properties: [:])!
    }
    #endif
}

@Suite("Pixel art performance")
struct ArtPerformanceTests {
    @Test("Painting every boss is fast enough for launch")
    func paintSpeed() {
        let clock = ContinuousClock()
        let elapsed = clock.measure {
            for kind in BossKind.allCases { _ = BossArt.paint(kind) }
        }
        print("Painted \(BossKind.allCases.count) bosses in \(elapsed)")
        #expect(elapsed < .milliseconds(500))
    }
}
