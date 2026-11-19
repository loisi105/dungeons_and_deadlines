import SwiftUI
import GameCore
import DDDesign

/// VoiceOver announcements without flooding: your own hits are announced right away,
/// teammates' hits are summarized at most every 30 seconds.
@MainActor
@Observable
final class Announcer {
    private var pendingTeammateDamage = 0
    private var pendingTeammateHits = 0
    private var lastSummary = Date.distantPast
    private var summaryTask: Task<Void, Never>?
    let summaryInterval: TimeInterval = 30

    func announce(_ text: String, important: Bool = false) {
        var announcement = AttributedString(text)
        announcement.accessibilitySpeechAnnouncementPriority = important ? .high : .default
        AccessibilityNotification.Announcement(announcement).post()
    }

    func announceOwnHit(_ attack: Attack?) {
        guard let attack else { return }
        announce(A11yText.attack(attack, by: nil))
    }

    func queueTeammateHit(_ attack: Attack) {
        pendingTeammateDamage += attack.damage
        pendingTeammateHits += 1
        guard summaryTask == nil else { return }
        let wait = max(0, summaryInterval - Date().timeIntervalSince(lastSummary))
        summaryTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(wait))
            self?.flushSummary()
        }
    }

    private func flushSummary() {
        defer {
            summaryTask = nil
            lastSummary = .now
            pendingTeammateDamage = 0
            pendingTeammateHits = 0
        }
        guard pendingTeammateHits > 0 else { return }
        announce(String(localized: "Teammates hit the boss \(pendingTeammateHits) times for \(pendingTeammateDamage) damage."))
    }
}
