import Foundation
import GameCore

/// Spoken and written descriptions shared by the app, widgets and the Live Activity,
/// so VoiceOver says the same thing everywhere.
public enum A11yText {
    public static func hp(_ state: BossState) -> String {
        String(localized: "\(state.currentHP) of \(state.maxHP) health, \(state.percent) percent")
    }

    public static func boss(name: String, state: BossState) -> String {
        switch state.outcome {
        case .planning:
            String(localized: "\(name), planning. Predicted health \(state.maxHP).")
        case .won:
            String(localized: "\(name) defeated. Victory!")
        case .lost:
            String(localized: "\(name) survived the deadline with \(state.currentHP) health left. Defeat.")
        case .ongoing:
            String(localized: "\(name), \(hp(state)), phase \(state.phase.rawValue): \(String(localized: state.phase.title)).")
        }
    }

    public static func attack(_ attack: Attack, by nickname: String?) -> String {
        let who = nickname ?? String(localized: "You")
        switch attack.kind {
        case .task:
            return String(localized: "\(who) completed a task for \(attack.damage) damage.")
        case .focus(let seconds):
            return String(localized: "\(who) focused \(duration(seconds)) for \(attack.damage) damage.")
        }
    }

    /// "1 hour, 5 minutes" style for VoiceOver and labels.
    public static func duration(_ seconds: Int) -> String {
        let formatter = DateComponentsFormatter()
        formatter.unitsStyle = .full
        formatter.allowedUnits = seconds >= 3600 ? [.hour, .minute] : [.minute, .second]
        formatter.zeroFormattingBehavior = .dropAll
        return formatter.string(from: TimeInterval(max(0, seconds))) ?? "\(seconds)s"
    }

    /// "1h 05m" for compact UI.
    public static func shortDuration(_ seconds: Int) -> String {
        let h = seconds / 3600
        let m = (seconds % 3600) / 60
        return h > 0 ? String(format: "%dh %02dm", h, m) : String(format: "%dm", m)
    }
}
