import SwiftUI
import GameCore
import DDPersistence
import DDIntents
import DDDesign

/// Opened from the phase badge: how long the boss stays in its phase, what comes next and
/// when. The raid leader can make the boss angrier or calmer than the deadline says; each
/// step moves the whole remaining timeline (see `Phase.at(start:deadline:now:shift:)`).
struct PhaseDetailsView: View {
    /// The live raid (BossView passes the latest value from its query).
    let raid: Raid
    /// Whether the fight is running (BossView's outcome: not won, lost or planning).
    /// A finished fight shows no mood buttons.
    let isOngoing: Bool

    @Environment(Announcer.self) private var announcer
    @State private var errorMessage: String?

    private var isLeader: Bool { raid.ownerID == LocalIdentity.current.memberID }

    var body: some View {
        // Refreshes often enough that a phase change while this is open shows within seconds.
        TimelineView(.periodic(from: .now, by: 15)) { context in
            details(now: context.date)
        }
    }

    private func details(now: Date) -> some View {
        let phase = raid.phase(at: now)
        let next = raid.nextPhaseChange(after: now)
        return VStack(alignment: .leading, spacing: 14) {
            Label {
                Text("\(raid.bossName) is \(Text(phase.title)).")
            } icon: {
                Image(systemName: phase.symbol)
                    .foregroundStyle(phase.tint)
            }
            .font(.headline)
            .fontDesign(.serif)
            .foregroundStyle(Theme.ink)
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(.isHeader)

            VStack(alignment: .leading, spacing: 4) {
                if let next {
                    Text("Turns \(Text(next.phase.title)) \(next.date.formatted(.relative(presentation: .named, unitsStyle: .wide))).")
                        .foregroundStyle(Theme.ink)
                    Text(next.date.formatted(date: .abbreviated, time: .shortened))
                        .readableFootnote()
                } else {
                    Text("Stays \(Text(phase.title)) until the deadline.")
                        .foregroundStyle(Theme.ink)
                    Text("Deadline \(raid.deadline.formatted(date: .abbreviated, time: .shortened))")
                        .readableFootnote()
                }
            }
            .accessibilityElement(children: .combine)

            if raid.phaseShift != 0 {
                shiftNote
            }

            if !isOngoing || raid.status != .active || now >= raid.deadline {
                Text("The fight is over.")
                    .readableFootnote()
            } else if isLeader {
                buttons(phase: phase, now: now)
            } else {
                Text("Only the raid leader can change the boss's mood.")
                    .readableFootnote()
            }

            if let errorMessage {
                Text(errorMessage)
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(Theme.accent)
            }
        }
        .fixedSize(horizontal: false, vertical: true)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var shiftNote: some View {
        let steps = abs(raid.phaseShift)
        return Label {
            Text(raid.phaseShift > 0
                 ? "Set ^[\(steps) step](inflect: true) angrier than the deadline."
                 : "Set ^[\(steps) step](inflect: true) calmer than the deadline.")
        } icon: {
            Image(systemName: raid.phaseShift > 0 ? "arrow.up.circle.fill" : "arrow.down.circle.fill")
        }
        .readableFootnote()
        .accessibilityElement(children: .combine)
    }

    /// The shift that actually takes effect at `now`. A shift past the cap does nothing
    /// (+3 while the deadline already says Enraged is still Berserk), so steps start from
    /// here and every tap changes the phase.
    private func effectiveShift(phase: Phase, now: Date) -> Int {
        let natural = Phase.at(start: raid.phaseStart, deadline: raid.deadline, now: now)
        return Phase.clampShift(phase.rawValue - natural.rawValue)
    }

    private func buttons(phase: Phase, now: Date) -> some View {
        let shift = effectiveShift(phase: phase, now: now)
        return VStack(spacing: 10) {
            Button {
                setShift(shift + 1, now: now)
            } label: {
                Label("Make angrier", systemImage: "flame.fill")
                    .frame(maxWidth: .infinity)
            }
            .primaryActionStyle()
            .disabled(phase == .berserk || shift >= Phase.shiftRange.upperBound)
            .accessibilityIdentifier("phaseAngrierButton")
            .accessibilityHint(Text("Moves the boss one phase further, now and for the rest of the fight."))

            Button {
                setShift(shift - 1, now: now)
            } label: {
                Label("Calm down", systemImage: "leaf.fill")
                    .frame(maxWidth: .infinity)
            }
            .secondaryActionStyle()
            .disabled(phase == .calm || shift <= Phase.shiftRange.lowerBound)
            .accessibilityIdentifier("phaseCalmerButton")
            .accessibilityHint(Text("Moves the boss one phase back, now and for the rest of the fight."))

            if raid.phaseShift != 0 {
                Button {
                    setShift(0, now: now)
                } label: {
                    Label("Follow the deadline", systemImage: "clock.arrow.circlepath")
                        .frame(maxWidth: .infinity)
                }
                .secondaryActionStyle()
                .accessibilityIdentifier("phaseResetButton")
                .accessibilityHint(Text("The boss's mood follows the time left again."))
            }
        }
    }

    private func setShift(_ shift: Int, now: Date) {
        let old = raid.phase(at: now)
        var changed = raid
        changed.phaseShift = shift
        let new = changed.phase(at: now)
        do {
            // Saves, refreshes widgets and the Live Activity, and uploads in multiplayer raids.
            try GameActions.setPhaseShift(shift, raidID: raid.id)
            errorMessage = nil
            // BossView announces promotions itself (with the haptic); say the rest here.
            if new < old {
                announcer.announce(String(localized: "The boss is now \(String(localized: new.title))."))
            } else if new == old, shift == 0 {
                announcer.announce(String(localized: "The boss follows the deadline again."))
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

/// The phase details in a sheet, for accessibility text sizes where a popover would clip.
struct PhaseDetailsSheet: View {
    let raid: Raid
    let isOngoing: Bool

    var body: some View {
        NavigationStack {
            ScrollView {
                PhaseDetailsView(raid: raid, isOngoing: isOngoing)
                    .dungeonPanel()
                    .padding()
            }
            .dungeonScreen()
            .navigationTitle("Boss mood")
            .navigationBarTitleDisplayMode(.inline)
            .sheetCloseButton(identifier: "phaseDetailsCloseButton")
        }
        .presentationDetents([.large])
    }
}
