import SwiftUI
import GameCore

// Display names, SF Symbols and colors for game types.
// Phases and roles always pair a symbol with text, never color alone.

extension Phase {
    public var title: LocalizedStringResource {
        switch self {
        case .calm: "Calm"
        case .angry: "Angry"
        case .enraged: "Enraged"
        case .berserk: "Berserk"
        }
    }

    public var symbol: String {
        switch self {
        case .calm: "leaf.fill"
        case .angry: "flame"
        case .enraged: "flame.fill"
        case .berserk: "exclamationmark.triangle.fill"
        }
    }

    /// Phase colors with at least 3:1 contrast against the HP bar track in both modes.
    public var tint: Color {
        switch self {
        case .calm: Color(light: Color(red: 0.07, green: 0.39, blue: 0.15), dark: Color(red: 0.29, green: 0.87, blue: 0.50))
        case .angry: Color(light: Color(red: 0.49, green: 0.32, blue: 0.00), dark: Color(red: 0.98, green: 0.80, blue: 0.08))
        case .enraged: Color(light: Color(red: 0.64, green: 0.19, blue: 0.03), dark: Color(red: 0.98, green: 0.57, blue: 0.24))
        case .berserk: Color(light: Color(red: 0.64, green: 0.08, blue: 0.08), dark: Color(red: 0.97, green: 0.44, blue: 0.44))
        }
    }

    public var hint: LocalizedStringResource {
        switch self {
        case .calm: "More than half the time is left."
        case .angry: "Less than half the time is left."
        case .enraged: "Less than a quarter of the time is left."
        case .berserk: "Less than 10 percent of the time is left."
        }
    }
}

extension TaskSize {
    public var title: LocalizedStringResource {
        switch self {
        case .s: "Small"
        case .m: "Medium"
        case .l: "Large"
        }
    }

    public var shortTitle: String {
        switch self {
        case .s: "S"
        case .m: "M"
        case .l: "L"
        }
    }

    public var symbol: String {
        switch self {
        case .s: "circle.fill"
        case .m: "square.fill"
        case .l: "hexagon.fill"
        }
    }
}

extension Role {
    public var title: LocalizedStringResource {
        switch self {
        case .mage: "Mage (writer)"
        case .tank: "Tank (researcher)"
        case .rogue: "Rogue (designer)"
        case .healer: "Healer (presenter)"
        }
    }

    public var symbol: String {
        switch self {
        case .mage: "wand.and.stars"
        case .tank: "shield.fill"
        case .rogue: "paintbrush.pointed.fill"
        case .healer: "cross.case.fill"
        }
    }
}

extension Title {
    public var name: LocalizedStringResource {
        switch self {
        case .mvp: "MVP"
        case .sniper: "Sniper"
        case .grinder: "Grinder"
        case .consistent: "Consistent"
        case .lastMinuteHero: "Last-Minute Hero"
        case .afkLegend: "AFK Legend"
        }
    }

    public var explanation: LocalizedStringResource {
        switch self {
        case .mvp: "Most total damage"
        case .sniper: "Most damage from tasks"
        case .grinder: "Most focus time"
        case .consistent: "Longest daily focus streak"
        case .lastMinuteHero: "Most damage in the final phase"
        case .afkLegend: "Least damage dealt"
        }
    }

    public var symbol: String {
        switch self {
        case .mvp: "crown.fill"
        case .sniper: "scope"
        case .grinder: "hourglass"
        case .consistent: "calendar"
        case .lastMinuteHero: "alarm.fill"
        case .afkLegend: "zzz"
        }
    }
}

extension Outcome {
    public var title: LocalizedStringResource {
        switch self {
        case .planning: "Planning"
        case .ongoing: "Fighting"
        case .won: "Victory"
        case .lost: "Defeat"
        }
    }
}

extension BossKind {
    public var title: LocalizedStringResource {
        switch self {
        case .alarmClock: "Clock"
        case .dragon: "Dragon"
        case .slime: "Slime"
        case .lich: "Lich"
        case .golem: "Golem"
        case .kraken: "Kraken"
        case .goblin: "Goblin"
        case .mimic: "Mimic"
        case .ghost: "Ghost"
        case .spider: "Spider"
        case .mushroom: "Shroom"
        case .cyclops: "Cyclops"
        }
    }
}
