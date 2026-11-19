import Foundation

/// Lifecycle of a raid. A solo game is a raid with one member.
public enum RaidStatus: String, Codable, Sendable, CaseIterable {
    /// Tasks are being planned and members invited. HP is not locked yet.
    case planning
    /// The fight has started; max HP is locked.
    case active
    case won
    case lost
}

public enum TaskSize: String, Codable, Sendable, CaseIterable, Identifiable {
    case s, m, l
    public var id: String { rawValue }
}

/// Flavor classes. They only change icons and animations, never damage.
public enum Role: String, Codable, Sendable, CaseIterable, Identifiable {
    case mage    // writer
    case tank    // researcher
    case rogue   // designer
    case healer  // presenter
    public var id: String { rawValue }
}

public struct Raid: Identifiable, Codable, Sendable, Hashable {
    public var id: UUID
    public var name: String
    public var bossName: String
    public var ownerID: String
    public var createdAt: Date
    public var deadline: Date
    public var startedAt: Date?
    public var lockedMaxHP: Int?
    public var status: RaidStatus
    public var inviteCode: String?
    public var isMultiplayer: Bool

    public init(
        id: UUID = UUID(), name: String, bossName: String, ownerID: String,
        createdAt: Date, deadline: Date, startedAt: Date? = nil, lockedMaxHP: Int? = nil,
        status: RaidStatus = .planning, inviteCode: String? = nil, isMultiplayer: Bool = false
    ) {
        self.id = id
        self.name = name
        self.bossName = bossName
        self.ownerID = ownerID
        self.createdAt = createdAt
        self.deadline = deadline
        self.startedAt = startedAt
        self.lockedMaxHP = lockedMaxHP
        self.status = status
        self.inviteCode = inviteCode
        self.isMultiplayer = isMultiplayer
    }
}

public struct Member: Identifiable, Codable, Sendable, Hashable {
    public var id: String
    public var raidID: UUID
    public var nickname: String
    public var role: Role?
    public var joinedAt: Date
    public var activeFocusSince: Date?

    public init(id: String, raidID: UUID, nickname: String, role: Role? = nil, joinedAt: Date, activeFocusSince: Date? = nil) {
        self.id = id
        self.raidID = raidID
        self.nickname = nickname
        self.role = role
        self.joinedAt = joinedAt
        self.activeFocusSince = activeFocusSince
    }
}

public struct RaidTask: Identifiable, Codable, Sendable, Hashable {
    public var id: UUID
    public var raidID: UUID
    public var title: String
    public var size: TaskSize
    public var assigneeID: String?
    public var createdAt: Date
    public var completedAt: Date?
    public var completedBy: String?
    public var sortIndex: Int

    public init(
        id: UUID = UUID(), raidID: UUID, title: String, size: TaskSize, assigneeID: String? = nil,
        createdAt: Date, completedAt: Date? = nil, completedBy: String? = nil, sortIndex: Int = 0
    ) {
        self.id = id
        self.raidID = raidID
        self.title = title
        self.size = size
        self.assigneeID = assigneeID
        self.createdAt = createdAt
        self.completedAt = completedAt
        self.completedBy = completedBy
        self.sortIndex = sortIndex
    }

    public var isDone: Bool { completedAt != nil }

    /// A task added after the fight started. It still deals damage but is flagged in the report.
    public func isLate(startedAt: Date?) -> Bool {
        guard let startedAt else { return false }
        return createdAt > startedAt
    }
}

public enum AttackKind: Codable, Sendable, Hashable {
    case task(UUID)
    case focus(seconds: Int)

    public var isTask: Bool { if case .task = self { true } else { false } }
    public var focusSeconds: Int { if case .focus(let s) = self { s } else { 0 } }
}

/// One hit on the boss. Attacks are only ever added, never edited.
public struct Attack: Identifiable, Codable, Sendable, Hashable {
    /// Client-generated; also the Firestore document ID so retries can't double count.
    public var id: UUID
    public var raidID: UUID
    public var memberID: String
    public var kind: AttackKind
    /// Frozen at creation, so retuning `DamageConfig` never rewrites history.
    public var damage: Int
    public var createdAt: Date
    /// `yyyy-MM-dd` in the creating device's time zone. Daily caps use this.
    public var localDay: String

    public init(id: UUID = UUID(), raidID: UUID, memberID: String, kind: AttackKind, damage: Int, createdAt: Date, localDay: String) {
        self.id = id
        self.raidID = raidID
        self.memberID = memberID
        self.kind = kind
        self.damage = damage
        self.createdAt = createdAt
        self.localDay = localDay
    }
}

public enum LocalDay {
    /// `yyyy-MM-dd` for `date` in `calendar`'s time zone.
    public static func key(for date: Date, calendar: Calendar = .current) -> String {
        let c = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
    }

    /// The key `offset` days before `date` (offset 0 = same day).
    public static func key(daysBefore offset: Int, from date: Date, calendar: Calendar = .current) -> String {
        let shifted = calendar.date(byAdding: .day, value: -offset, to: date) ?? date
        return key(for: shifted, calendar: calendar)
    }
}
