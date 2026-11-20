import SwiftUI
import UserNotifications
import GameCore
import DDPersistence
import DDDesign

/// Local notifications for upcoming boss phase changes ("Syntax Spider is now Angry").
///
/// No server: every ongoing fight gets one pending request per upcoming phase change.
/// `setNeedsReschedule()` throws away this service's pending requests and adds them again
/// from the store, so it's safe to call after any change. `RootView` calls it whenever a
/// raid's status, deadline, start or phase shift changes (local, intent or sync), when the
/// app becomes active, and when the setting changes.
@MainActor
@Observable
final class PhaseNotifications: NSObject {
    /// `AppGroup.defaults` key of the "Phase alerts" toggle (default on).
    static let enabledKey = "settings.phaseAlerts"
    /// Every request of this service starts with this, so it removes only its own.
    nonisolated static let idPrefix = "phase."
    /// iOS keeps at most 64 pending requests per app; leave room for anything else.
    static let totalLimit = 60
    static let perRaidLimit = 4

    /// Last known permission, for the settings row.
    private(set) var authorization: UNAuthorizationStatus = .notDetermined

    /// Set by `AppEnvironment`: opens a raid's Boss tab (tapping a notification).
    @ObservationIgnored var openRaid: (UUID) -> Void = { _ in }
    /// Set by `AppEnvironment`: whether that raid's Boss tab is on screen right now.
    @ObservationIgnored var isShowingBoss: (UUID) -> Bool = { _ in false }

    private var store: RaidStore { DDStore.shared }
    @ObservationIgnored private var debounce: Task<Void, Never>?
    @ObservationIgnored private var isRescheduling = false
    @ObservationIgnored private var needsAnotherPass = false

    private var center: UNUserNotificationCenter { .current() }

    static var isEnabled: Bool {
        AppGroup.defaults.object(forKey: enabledKey) as? Bool ?? true
    }

    var isDenied: Bool { authorization == .denied }

    /// Call once at launch, before the app finishes launching, so a tap that launched
    /// the app reaches `didReceive`.
    func start() {
        center.delegate = self
    }

    // MARK: Permission

    func refreshAuthorization() async {
        authorization = await center.notificationSettings().authorizationStatus
    }

    /// Asks for permission if it was never asked. Returns whether alerts may be shown.
    @discardableResult
    func requestAuthorizationIfNeeded() async -> Bool {
        await refreshAuthorization()
        if authorization == .notDetermined {
            _ = try? await center.requestAuthorization(options: [.alert, .sound])
            await refreshAuthorization()
        }
        return Self.canAlert(authorization)
    }

    private static func canAlert(_ status: UNAuthorizationStatus) -> Bool {
        switch status {
        case .authorized, .provisional, .ephemeral: true
        default: false
        }
    }

    // MARK: Scheduling

    /// Coalesces bursts of changes (a sync merge touches several rows) into one pass.
    func setNeedsReschedule() {
        debounce?.cancel()
        debounce = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(500))
            guard !Task.isCancelled else { return }
            await self?.reschedule()
        }
    }

    /// Removes this service's pending requests and adds them again from the store.
    /// Passes never overlap: a call during a pass runs one more pass afterwards.
    func reschedule() async {
        if isRescheduling {
            needsAnotherPass = true
            return
        }
        isRescheduling = true
        defer { isRescheduling = false }
        repeat {
            needsAnotherPass = false
            await reschedulePass()
        } while needsAnotherPass
    }

    private func reschedulePass() async {
        let ours = await center.pendingNotificationRequests()
            .map(\.identifier)
            .filter { $0.hasPrefix(Self.idPrefix) }
        center.removePendingNotificationRequests(withIdentifiers: ours)

        guard Self.isEnabled, !LaunchOptions.isUITesting else { return }
        let now = Date.now
        // Only fights still on: an active raid whose boss is already slain (or out of time)
        // but not settled yet gets no alerts.
        let raids = store.raids().filter {
            PhaseSchedule.isOngoing($0, now: now) && store.bossState($0.id, at: now)?.outcome == .ongoing
        }
        let plan = PhaseSchedule.plan(
            raids: raids, now: now, perRaid: Self.perRaidLimit, total: Self.totalLimit
        ) { raid, after in
            raid.nextPhaseChange(after: after)
        }
        guard !plan.isEmpty else { return }

        // Never prompts here: a pass runs on launch, sync and timers, when a system prompt
        // would come out of nowhere. Permission is asked when the user turns "Phase alerts"
        // on and when a fight starts on this phone (see `RootView`).
        await refreshAuthorization()
        guard Self.canAlert(authorization) else { return }

        let byID = Dictionary(raids.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        for change in plan {
            let interval = change.date.timeIntervalSince(.now)
            guard interval >= 1 else { continue }
            let content = UNMutableNotificationContent()
            let raid = byID[change.raidID]
            let boss = raid?.bossName ?? ""
            let phase = String(localized: change.phase.title)
            content.title = String(localized: "\(boss) is now \(phase)", comment: "Phase alert title: boss name, then the phase (Angry, Enraged, Berserk)")
            // The hint describes the time rule ("Less than half the time is left"), which
            // doesn't hold once the leader shifted the mood.
            content.body = (raid?.phaseShift ?? 0) == 0
                ? String(localized: change.phase.hint)
                : String(localized: "The raid leader set the boss's mood.")
            content.sound = .default
            content.threadIdentifier = change.raidID.uuidString
            content.targetContentIdentifier = change.raidID.uuidString
            content.userInfo = ["raidID": change.raidID.uuidString]
            let request = UNNotificationRequest(
                identifier: Self.identifier(raidID: change.raidID, phase: change.phase),
                content: content,
                trigger: UNTimeIntervalNotificationTrigger(timeInterval: interval, repeats: false)
            )
            try? await center.add(request)
        }
    }

    /// The parts of a raid its alerts depend on. `RootView` reschedules when any of these change.
    struct Key: Hashable {
        let id: UUID
        let bossName: String
        let status: RaidStatus
        let start: Date
        let deadline: Date
        let phaseShift: Int

        init(_ raid: Raid) {
            id = raid.id
            bossName = raid.bossName
            status = raid.status
            start = raid.startedAt ?? raid.createdAt
            deadline = raid.deadline
            phaseShift = raid.phaseShift
        }
    }

    /// `phase.<raidID>.<phase>`: one request per raid and phase, so re-adding replaces it.
    nonisolated static func identifier(raidID: UUID, phase: Phase) -> String {
        "\(idPrefix)\(raidID.uuidString).\(phase.rawValue)"
    }

    /// The raid a request of this service belongs to.
    nonisolated static func raidID(fromIdentifier identifier: String) -> UUID? {
        guard identifier.hasPrefix(idPrefix) else { return nil }
        let rest = identifier.dropFirst(idPrefix.count)
        guard let dot = rest.firstIndex(of: ".") else { return nil }
        return UUID(uuidString: String(rest[..<dot]))
    }
}

extension PhaseNotifications: UNUserNotificationCenterDelegate {
    /// In the foreground, show the banner unless that boss is already on screen (its
    /// phase banner, haptic and VoiceOver announcement already cover it).
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter, willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        guard let raidID = Self.raidID(fromIdentifier: notification.request.identifier) else {
            return [.banner, .list, .sound]
        }
        let onScreen = await MainActor.run { self.isShowingBoss(raidID) }
        return onScreen ? [.list] : [.banner, .list, .sound]
    }

    /// Tapping an alert opens that raid's Boss tab.
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse
    ) async {
        guard response.actionIdentifier == UNNotificationDefaultActionIdentifier,
              let raidID = Self.raidID(fromIdentifier: response.notification.request.identifier)
        else { return }
        await MainActor.run { self.openRaid(raidID) }
    }
}

/// "Phase alerts" toggle for the Party tab's settings, next to Haptics. Turning it on asks
/// for permission; if notifications are off for the app, a note links to its Settings page.
struct PhaseAlertsSetting: View {
    @Environment(PhaseNotifications.self) private var notifications
    @Environment(\.openURL) private var openURL
    @Environment(\.scenePhase) private var scenePhase
    @AppStorage(PhaseNotifications.enabledKey, store: AppGroup.defaults) private var isOn = true

    var body: some View {
        Toggle("Phase alerts", isOn: $isOn)
            .accessibilityHint("Sends a notification when a boss changes phase.")
            .accessibilityIdentifier("phaseAlertsToggle")
            .onChange(of: isOn) { _, on in
                Task {
                    if on { await notifications.requestAuthorizationIfNeeded() }
                    notifications.setNeedsReschedule()
                }
            }
            .task(id: scenePhase) { await notifications.refreshAuthorization() }

        if isOn && notifications.isDenied {
            Text("Notifications are off for Dungeons & Deadlines in Settings.")
                .readableFootnote()
            Button("Open Settings", systemImage: "gear") {
                if let url = URL(string: UIApplication.openNotificationSettingsURLString) { openURL(url) }
            }
        }
    }
}
