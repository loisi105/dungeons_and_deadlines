import Foundation

/// Every boss look. All are 64×64 in the style of the app icon (Nico's alarm clock):
/// one-pixel dark outline, three-tone shading lit from the top-left, gold/cream/night palette.
public enum BossKind: String, CaseIterable, Sendable {
    case alarmClock, dragon, slime, lich, golem, kraken, goblin, mimic, ghost, spider, mushroom, cyclops, bat, knight, yeti

    /// The looks on the free plan; the others need Premium (the rule is
    /// `PlanLimits.check(bossIsFree:plan:)` in GameCore, which can't see this type).
    public static let freeKinds: [BossKind] = [.alarmClock, .dragon, .goblin]

    /// Free-plan players can create raids with this look.
    public var isFree: Bool { Self.freeKinds.contains(self) }

    /// Picks the look from the boss's name ("Thesis Hydra" → dragon). Names without a
    /// keyword always map to the same free look, so a custom name never needs Premium.
    public static func forName(_ name: String) -> BossKind {
        let n = name.lowercased()
        let table: [(BossKind, [String])] = [
            (.alarmClock, ["clock", "alarm", "deadline", "time", "snooze"]),
            (.dragon, ["dragon", "wyrm", "hydra", "basilisk", "drake", "lizard"]),
            (.mimic, ["mimic", "chest", "inbox", "email", "homework"]),
            (.ghost, ["ghost", "phantom", "wifi", "specter", "spirit"]),
            (.lich, ["lich", "wraith", "skeleton", "procrastination", "necro"]),
            (.spider, ["spider", "bug", "web", "syntax"]),
            (.mushroom, ["mushroom", "shroom", "spore", "fungus", "burnout"]),
            (.cyclops, ["cyclops", "proctor", "watcher", "eye"]),
            (.golem, ["golem", "ogre", "troll", "deck", "report", "essay", "giant"]),
            (.kraken, ["kraken", "squid", "octo", "project", "tentacle"]),
            (.goblin, ["goblin", "imp", "citation", "gremlin", "thief"]),
            (.slime, ["slime", "blob", "ooze", "jelly"]),
            (.bat, ["vampire", "scroll"]),
            (.knight, ["knight", "paladin", "bureau", "tape"]),
            (.yeti, ["yeti", "frost", "snow", "winter"]),
        ]
        for (kind, words) in table where words.contains(where: n.contains) { return kind }
        let pool = freeKinds
        return pool[n.unicodeScalars.reduce(0) { ($0 &* 31 &+ Int($1.value)) & 0xFFFF } % pool.count]
    }

    public var art: PixelArt {
        switch self {
        case .alarmClock: PixelArt.alarmClock
        case .dragon: BossArt.dragon
        case .slime: BossArt.slime
        case .lich: BossArt.lich
        case .golem: BossArt.golem
        case .kraken: BossArt.kraken
        case .goblin: BossArt.goblin
        case .mimic: BossArt.mimic
        case .ghost: BossArt.ghost
        case .spider: BossArt.spider
        case .mushroom: BossArt.mushroom
        case .cyclops: BossArt.cyclops
        case .bat: BossArt.bat
        case .knight: BossArt.knight
        case .yeti: BossArt.yeti
        }
    }
}

/// Paints each boss on first use (static lets are lazy and thread-safe).
enum BossArt {
    static let dragon = paintDragon()
    static let slime = paintSlime()
    static let lich = paintLich()
    static let golem = paintGolem()
    static let kraken = paintKraken()
    static let goblin = paintGoblin()
    static let mimic = paintMimic()
    static let ghost = paintGhost()
    static let spider = paintSpider()
    static let mushroom = paintMushroom()
    static let cyclops = paintCyclops()
    static let bat = paintBat()
    static let knight = paintKnight()
    static let yeti = paintYeti()

    /// Paints a boss without caching (tests and benchmarks).
    static func paint(_ kind: BossKind) -> PixelArt {
        switch kind {
        case .alarmClock: PixelArt.alarmClock
        case .dragon: paintDragon()
        case .slime: paintSlime()
        case .lich: paintLich()
        case .golem: paintGolem()
        case .kraken: paintKraken()
        case .goblin: paintGoblin()
        case .mimic: paintMimic()
        case .ghost: paintGhost()
        case .spider: paintSpider()
        case .mushroom: paintMushroom()
        case .cyclops: paintCyclops()
        case .bat: paintBat()
        case .knight: paintKnight()
        case .yeti: paintYeti()
        }
    }

    // MARK: Shared features

    /// Angry eyes: white, a glowing iris, a slanted brow.
    static func angryEyes(_ p: inout PixelPainter, x: Int, y: Int, size: Int = 4) {
        let white = p.flat(Palette.white), eye = p.eye(), ink = p.flat(Palette.black)
        p.rect(x, y, x + size, y + size - 1, white, mirror: true)
        p.rect(x + size / 2, y + 1, x + size - 1, y + size - 1, eye, mirror: true)
        for i in 0...size { p.pixel(x - 1 + i, y - 2 - (size - i) / 2, ink, mirror: true) }
    }

    static func fangs(_ p: inout PixelPainter, from x0: Int, to x1: Int, y: Int, every: Int = 3) {
        let tooth = p.flat(0xFFFBEA)
        var x = x0
        while x <= x1 {
            p.pixel(x, y, tooth)
            p.pixel(x, y + 1, tooth)
            x += every
        }
    }

    // MARK: Bosses

    static func paintDragon() -> PixelArt {
        var p = PixelPainter()
        _ = p.eye() // registers the glowing eye color
        let wing = p.material(Palette.ember), body = p.material(Palette.moss)
        let belly = p.material(Palette.bone), horn = p.material(Palette.gold)
        p.polygon([(4, 12), (20, 26), (16, 44), (8, 40), (2, 30)], wing, mirror: true)
        p.ellipse(32, 54, 15, 10, body)
        p.ellipse(32, 56, 8, 7, belly)
        p.ellipse(32, 28, 17, 15, body)
        p.polygon([(18, 18), (14, 2), (24, 14)], horn, mirror: true)
        p.ellipse(32, 38, 12, 7, belly)
        let mouth = p.flat(Palette.mouth)
        p.rect(24, 39, 39, 41, mouth)
        fangs(&p, from: 25, to: 38, y: 39)
        angryEyes(&p, x: 21, y: 25)
        let nostril = p.flat(Palette.black)
        p.pixel(29, 34, nostril, mirror: true)
        return p.render()
    }

    static func paintSlime() -> PixelArt {
        var p = PixelPainter()
        _ = p.eye() // registers the glowing eye color
        let goo = p.material(Palette.ocean)
        p.ellipse(32, 44, 26, 20, goo)
        p.erase(0, 58, 63, 63)
        p.rect(8, 50, 55, 57, goo)
        p.ellipse(18, 60, 3, 3, goo)
        p.ellipse(44, 61, 2, 3, goo)
        let shine = p.flat(0xE8F7FF)
        p.rect(16, 30, 19, 33, shine)
        p.rect(21, 28, 22, 29, shine)
        angryEyes(&p, x: 20, y: 38, size: 5)
        let mouth = p.flat(Palette.mouth)
        p.rect(27, 48, 36, 51, mouth)
        fangs(&p, from: 28, to: 35, y: 48)
        return p.render()
    }

    static func paintLich() -> PixelArt {
        var p = PixelPainter()
        let eyeID = p.eye()
        let robe = p.material(Palette.violet), skull = p.material(Palette.bone)
        let crown = p.material(Palette.gold), staff = p.material(Palette.wood)
        p.stroke([(54, 12), (54, 62)], width: 3, staff)
        p.ellipse(54, 10, 4, 4, eyeID)
        p.polygon([(14, 63), (22, 34), (42, 34), (50, 63)], robe)
        p.ellipse(32, 24, 13, 13, skull)
        p.rect(24, 32, 39, 38, skull)
        p.polygon([(19, 14), (20, 4), (25, 10), (32, 2), (39, 10), (44, 4), (45, 14)], crown)
        let socket = p.flat(Palette.black)
        p.rect(22, 21, 29, 27, socket, mirror: true)
        p.rect(25, 23, 27, 25, eyeID, mirror: true)
        p.rect(31, 29, 32, 31, socket)
        for x in stride(from: 25, through: 38, by: 2) { p.rect(x, 34, x, 37, socket) }
        return p.render()
    }

    static func paintGolem() -> PixelArt {
        var p = PixelPainter()
        let eyeID = p.eye()
        let rock = p.material(Palette.stone), rune = p.material(Palette.jade)
        p.rect(4, 26, 14, 50, rock, mirror: true)
        p.rect(16, 24, 47, 54, rock)
        p.rect(18, 55, 28, 63, rock, mirror: true)
        p.rect(20, 4, 43, 22, rock)
        p.rect(28, 34, 35, 44, rune)
        p.rect(30, 30, 33, 48, rune)
        let socket = p.flat(Palette.black)
        p.rect(23, 11, 30, 15, socket, mirror: true)
        p.rect(26, 12, 29, 14, eyeID, mirror: true)
        p.rect(27, 18, 36, 19, socket)
        return p.render()
    }

    static func paintKraken() -> PixelArt {
        var p = PixelPainter()
        let eyeID = p.eye()
        let skin = p.material(Palette.plum)
        for i in 0..<3 {
            let x = 26.0 - Double(i) * 6
            p.stroke([(x, 34), (x - 4 - Double(i) * 3, 46), (x - 2 - Double(i) * 6, 56), (x - 7 - Double(i) * 6, 60)], width: 5, skin, mirror: true)
        }
        p.stroke([(32, 36), (32, 60)], width: 5, skin)
        p.ellipse(32, 22, 20, 19, skin)
        p.rect(14, 22, 49, 38, skin)
        let spot = p.flat(0xB07CC6)
        p.ellipse(22, 10, 2, 2, spot)
        p.ellipse(41, 8, 3, 2, spot)
        _ = eyeID
        angryEyes(&p, x: 20, y: 22, size: 5)
        let mouth = p.flat(Palette.mouth)
        p.rect(28, 32, 35, 35, mouth)
        fangs(&p, from: 28, to: 35, y: 32, every: 2)
        return p.render()
    }

    static func paintGoblin() -> PixelArt {
        var p = PixelPainter()
        _ = p.eye() // registers the glowing eye color
        let skin = p.material(Palette.moss), hood = p.material(Palette.wood), dagger = p.material(Palette.steel)
        p.polygon([(14, 63), (20, 44), (44, 44), (50, 63)], hood)
        p.polygon([(16, 24), (0, 14), (6, 30)], skin, mirror: true)
        p.ellipse(32, 30, 16, 16, skin)
        p.polygon([(16, 22), (32, 4), (48, 22), (32, 16)], hood)
        p.ellipse(32, 34, 3, 4, skin)
        angryEyes(&p, x: 22, y: 26)
        let mouth = p.flat(Palette.mouth)
        p.rect(24, 40, 39, 42, mouth)
        fangs(&p, from: 25, to: 38, y: 40, every: 4)
        let hilt = p.material(Palette.brass)
        p.polygon([(51, 50), (57, 50), (54, 24)], dagger)
        p.rect(49, 50, 59, 52, hilt)
        p.rect(53, 53, 55, 59, hilt)
        return p.render()
    }

    static func paintMimic() -> PixelArt {
        var p = PixelPainter()
        _ = p.eye() // registers the glowing eye color
        let wood = p.material(Palette.wood), metal = p.material(Palette.gold)
        p.rect(8, 36, 55, 60, wood)
        p.polygon([(8, 30), (12, 8), (52, 8), (56, 30)], wood)
        p.rect(8, 28, 55, 31, metal)
        p.rect(8, 56, 55, 58, metal)
        p.rect(28, 30, 35, 40, metal)
        let mouth = p.flat(Palette.mouth), tongue = p.flat(Palette.tongue)
        p.rect(10, 32, 53, 37, mouth)
        p.rect(26, 35, 37, 44, tongue)
        fangs(&p, from: 11, to: 52, y: 32, every: 3)
        let tooth = p.flat(0xFFFBEA)
        var x = 12
        while x < 52 { p.pixel(x, 37, tooth); p.pixel(x, 36, tooth); x += 4 }
        angryEyes(&p, x: 18, y: 16, size: 5)
        return p.render()
    }

    static func paintGhost() -> PixelArt {
        var p = PixelPainter()
        let eyeID = p.eye()
        let sheet = p.material(Palette.ghost)
        p.ellipse(32, 26, 20, 20, sheet)
        p.rect(12, 26, 51, 54, sheet)
        for i in 0..<5 { p.ellipse(14 + Double(i) * 9, 56, 4.5, 5, sheet) }
        p.polygon([(12, 32), (2, 40), (12, 44)], sheet, mirror: true)
        let hole = p.flat(Palette.black)
        p.rect(20, 22, 27, 30, hole, mirror: true)
        p.rect(23, 25, 25, 27, eyeID, mirror: true)
        p.ellipse(32, 41, 5, 6, hole)
        return p.render()
    }

    static func paintSpider() -> PixelArt {
        var p = PixelPainter()
        let eyeID = p.eye()
        let shell = p.material(Palette.night), leg = p.material(Palette.night)
        for (i, y) in [24.0, 32, 40, 48].enumerated() {
            let reach = 30.0 - Double(i) * 2
            p.stroke([(24, y), (24 - reach / 2, y - 10), (24 - reach, y + 10)], width: 3, leg, mirror: true)
        }
        let thread = p.flat(0xD8D8E8)
        p.stroke([(32, 0), (32, 14)], width: 1.5, thread)
        p.ellipse(32, 44, 16, 14, shell)
        p.ellipse(32, 26, 12, 10, shell)
        let mark = p.flat(0xE0342F)
        p.rect(30, 40, 33, 47, mark)
        p.rect(28, 43, 35, 44, mark)
        let eye = eyeID
        for (x, y) in [(26, 24), (29, 22), (34, 22), (37, 24)] { p.rect(x, y, x + 1, y + 1, eye) }
        fangs(&p, from: 29, to: 34, y: 33, every: 5)
        return p.render()
    }

    static func paintMushroom() -> PixelArt {
        var p = PixelPainter()
        _ = p.eye() // registers the glowing eye color
        let cap = p.material(Palette.mushroomRed), stem = p.material(Palette.bone)
        p.rect(20, 34, 43, 60, stem)
        p.ellipse(32, 26, 28, 18, cap)
        p.erase(0, 34, 63, 36)
        p.rect(4, 30, 59, 33, cap)
        let dot = p.flat(0xFFF6D6)
        for (x, y, r) in [(18.0, 20.0, 4.0), (34, 14, 5), (48, 24, 3.5), (26, 28, 2.5)] { p.ellipse(x, y, r, r, dot) }
        angryEyes(&p, x: 23, y: 42)
        let mouth = p.flat(Palette.mouth)
        p.rect(28, 52, 35, 54, mouth)
        return p.render()
    }

    static func paintCyclops() -> PixelArt {
        var p = PixelPainter()
        let eyeID = p.eye()
        let skin = p.material(Palette.skin), cloth = p.material(Palette.brass), horn = p.material(Palette.bone)
        p.rect(14, 46, 49, 63, cloth)
        p.ellipse(32, 30, 20, 20, skin)
        p.polygon([(22, 14), (20, 2), (27, 11)], horn, mirror: true)
        let white = p.flat(Palette.white), ink = p.flat(Palette.black)
        p.ellipse(32, 26, 9, 7, white)
        p.ellipse(32, 27, 4, 4, eyeID)
        p.rect(31, 26, 32, 28, ink)
        p.rect(22, 17, 41, 18, ink)
        let mouth = p.flat(Palette.mouth)
        p.rect(24, 38, 39, 41, mouth)
        fangs(&p, from: 25, to: 38, y: 38, every: 4)
        return p.render()
    }

    static func paintBat() -> PixelArt {
        var p = PixelPainter()
        _ = p.eye() // registers the glowing eye color
        let wing = p.material(Palette.plum), body = p.material(Palette.night), chest = p.material(Palette.bone)
        // Wings with a scalloped lower edge.
        p.polygon([(22, 28), (3, 10), (1, 30), (7, 27), (9, 40), (15, 34), (19, 46)], wing, mirror: true)
        p.ellipse(32, 42, 11, 15, body)
        p.ellipse(32, 46, 6, 8, chest)
        p.ellipse(32, 24, 11, 10, body)
        p.polygon([(23, 20), (20, 4), (30, 16)], body, mirror: true)
        angryEyes(&p, x: 24, y: 21)
        let mouth = p.flat(Palette.mouth)
        p.rect(27, 30, 36, 32, mouth)
        fangs(&p, from: 28, to: 35, y: 30, every: 7)
        let foot = p.flat(Palette.black)
        p.rect(27, 56, 28, 60, foot, mirror: true)
        return p.render()
    }

    static func paintKnight() -> PixelArt {
        var p = PixelPainter()
        let eyeID = p.eye()
        let plate = p.material(Palette.stone), helm = p.material(Palette.steel)
        let plume = p.material(Palette.ember), trim = p.material(Palette.gold), blade = p.material(Palette.steel)
        p.rect(20, 56, 28, 63, plate, mirror: true)
        p.rect(17, 34, 46, 58, plate)
        p.ellipse(14, 38, 8, 7, helm, mirror: true)
        p.polygon([(28, 14), (22, 4), (34, 0), (42, 6), (36, 14)], plume)
        p.rect(21, 12, 42, 36, helm)
        p.ellipse(32, 15, 12, 9, helm)
        let slit = p.flat(Palette.black)
        p.rect(22, 21, 41, 26, slit)
        p.rect(25, 22, 29, 25, eyeID, mirror: true)
        for y in [29, 31, 33] { p.pixel(28, y, slit, mirror: true) }
        p.rect(30, 38, 33, 54, trim)
        p.rect(24, 42, 39, 45, trim)
        p.polygon([(51, 50), (57, 50), (54, 14)], blade)
        p.rect(49, 50, 59, 52, trim)
        p.rect(53, 53, 55, 58, plume)
        return p.render()
    }

    static func paintYeti() -> PixelArt {
        var p = PixelPainter()
        _ = p.eye() // registers the glowing eye color
        let fur = p.material(Palette.ghost), face = p.material(Palette.ocean), horn = p.material(Palette.bone)
        p.rect(17, 54, 28, 63, fur, mirror: true)
        p.ellipse(32, 44, 22, 18, fur)
        p.ellipse(9, 46, 8, 14, fur, mirror: true)
        p.polygon([(18, 28), (6, 26), (16, 38)], fur, mirror: true)
        p.ellipse(32, 24, 15, 14, fur)
        p.polygon([(19, 14), (14, 2), (25, 11)], horn, mirror: true)
        p.ellipse(32, 28, 10, 9, face)
        angryEyes(&p, x: 24, y: 23)
        let mouth = p.flat(Palette.mouth)
        p.rect(26, 35, 37, 38, mouth)
        fangs(&p, from: 27, to: 36, y: 35, every: 3)
        let claw = p.flat(0xFFFBEA)
        for x in [2, 5, 8] { p.rect(x, 58, x, 60, claw, mirror: true) }
        return p.render()
    }
}
