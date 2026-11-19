import Foundation
import GameCore

/// 16×16 pixel-art projectiles for task attacks, one per class, in the boss art style
/// (auto outline, three-tone shading). The sword for players without a class is Nico's.
public enum SpellArt {
    public static func art(for role: Role?) -> PixelArt {
        switch role {
        case .mage: arcaneOrb
        case .tank: shield
        case .rogue: dagger
        case .healer: holyCross
        case nil: .sword
        }
    }

    static let arcaneOrb: PixelArt = {
        var p = PixelPainter(size: 16)
        let orb = p.material(PixelPainter.Material(0xE8D8FF, 0x9B6BFF, 0x5B2FB8))
        p.ellipse(8, 8, 6, 6, orb)
        let spark = p.flat(0xFFFFFF)
        for (x, y) in [(6, 5), (7, 5), (6, 6), (10, 9), (9, 10)] { p.pixel(x, y, spark) }
        return p.render()
    }()

    static let shield: PixelArt = {
        var p = PixelPainter(size: 16)
        let steel = p.material(Palette.steel), rim = p.material(Palette.gold)
        p.polygon([(2, 1), (14, 1), (14, 8), (8, 15), (2, 8)], rim)
        p.polygon([(4, 3), (12, 3), (12, 8), (8, 13), (4, 8)], steel)
        let emblem = p.flat(0xE0342F)
        p.rect(7, 5, 8, 10, emblem)
        p.rect(6, 6, 9, 7, emblem)
        return p.render()
    }()

    static let dagger: PixelArt = {
        var p = PixelPainter(size: 16)
        let blade = p.material(Palette.steel), hilt = p.material(Palette.brass)
        // Pointing right, so it can fly from left to right.
        p.polygon([(5, 6.5), (15, 8), (5, 9.5)], blade)
        p.rect(3, 4, 4, 11, hilt)
        p.rect(0, 7, 2, 8, hilt)
        return p.render()
    }()

    static let holyCross: PixelArt = {
        var p = PixelPainter(size: 16)
        let gold = p.material(Palette.gold)
        p.rect(6, 1, 9, 14, gold)
        p.rect(2, 5, 13, 8, gold)
        let shine = p.flat(0xFFFFFF)
        p.pixel(7, 3, shine)
        p.pixel(7, 4, shine)
        return p.render()
    }()
}
