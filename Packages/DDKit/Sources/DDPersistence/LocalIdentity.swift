import Foundation

/// Who "I" am on this device, plus which raid is selected.
/// Stored in the App Group defaults so widgets and intents agree with the app.
public struct LocalIdentity: Sendable, Equatable {
    public var memberID: String
    public var nickname: String

    private enum Keys {
        static let memberID = "identity.memberID"
        static let nickname = "identity.nickname"
        static let currentRaidID = "identity.currentRaidID"
    }

    public static var current: LocalIdentity {
        let defaults = AppGroup.defaults
        let id: String
        if let stored = defaults.string(forKey: Keys.memberID) {
            id = stored
        } else {
            id = "local-" + UUID().uuidString.lowercased()
            defaults.set(id, forKey: Keys.memberID)
        }
        return LocalIdentity(memberID: id, nickname: defaults.string(forKey: Keys.nickname) ?? "")
    }

    public static var hasNickname: Bool {
        !(AppGroup.defaults.string(forKey: Keys.nickname) ?? "").isEmpty
    }

    public static func setNickname(_ name: String) {
        AppGroup.defaults.set(name.trimmingCharacters(in: .whitespacesAndNewlines), forKey: Keys.nickname)
    }

    /// Replaces the local ID, e.g. with the Firebase user ID after sign-in.
    public static func setMemberID(_ id: String) {
        AppGroup.defaults.set(id, forKey: Keys.memberID)
    }

    public static var currentRaidID: UUID? {
        get { AppGroup.defaults.string(forKey: Keys.currentRaidID).flatMap(UUID.init(uuidString:)) }
        set { AppGroup.defaults.set(newValue?.uuidString, forKey: Keys.currentRaidID) }
    }
}
