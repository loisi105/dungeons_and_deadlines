import Foundation

extension BossKind {
    /// Ready-made boss names for this look. Each one maps back to this kind via
    /// `forName`, so picking a look in the app just picks one of these names.
    public var suggestedNames: [String] {
        switch self {
        case .alarmClock: ["Deadline Clock", "Snooze Alarm", "Overtime Clock"]
        case .dragon: ["Exam Dragon", "Thesis Hydra", "Essay Wyrm"]
        case .slime: ["Overdue Ooze", "Busywork Slime", "Jelly of Chores"]
        case .lich: ["Procrastination Wraith", "Lich of Lost Notes", "Skeleton Draft"]
        case .golem: ["Slide Deck Golem", "Lab Report Ogre", "Paperwork Troll"]
        case .kraken: ["Group Project Kraken", "Backlog Squid", "Tentacle of Tabs"]
        case .goblin: ["Citation Goblin", "Gremlin of Typos", "Footnote Thief", "Unfinished Citation Goblin"]
        case .mimic: ["Midterm Mimic", "Inbox Mimic", "Homework Chest"]
        case .ghost: ["Wifi Phantom", "Unread Specter", "Ghost of Office Hours"]
        case .spider: ["Syntax Spider", "Merge Bug", "Web of Sources"]
        case .mushroom: ["Burnout Shroom", "Spore of Stress", "Fungus of Fatigue"]
        case .cyclops: ["Proctor Cyclops", "Watcher of Grades", "Eye of the Grader"]
        }
    }
}
