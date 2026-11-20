import AppIntents
import SwiftUI
import WidgetKit
import GameCore
import DDIntents
import DDDesign

/// Home Screen (small, medium), Lock Screen (circular, rectangular, inline) and StandBy.
struct BossWidget: Widget {
    static let kind = "at.fhooe.sail.dungeonsanddeadlines.boss"

    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: Self.kind, intent: SelectRaidIntent.self, provider: BossTimelineProvider()) { entry in
            BossWidgetView(entry: entry)
        }
        .configurationDisplayName("Boss")
        .description("Your boss's health, phase and next tasks.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge, .accessoryCircular, .accessoryRectangular, .accessoryInline])
    }
}

struct BossWidgetView: View {
    let entry: BossEntry
    @Environment(\.widgetFamily) private var family
    @Environment(\.widgetRenderingMode) private var renderingMode

    var body: some View {
        Group {
            if let snapshot = entry.snapshot {
                switch family {
                case .systemMedium: MediumBossView(snapshot: snapshot, date: entry.date)
                case .systemLarge: LargeBossView(snapshot: snapshot, date: entry.date)
                case .accessoryCircular: CircularBossView(snapshot: snapshot)
                case .accessoryRectangular: RectangularBossView(snapshot: snapshot, date: entry.date)
                case .accessoryInline: InlineBossView(snapshot: snapshot, date: entry.date)
                default: SmallBossView(snapshot: snapshot, date: entry.date)
                }
            } else {
                NoRaidView()
            }
        }
        .containerBackground(for: .widget) {
            if entry.snapshot != nil, renderingMode == .fullColor {
                PixelArtView(.nightSky, fill: true)
            } else {
                Theme.parchment
            }
        }
    }
}

// MARK: - Home Screen

struct SmallBossView: View {
    let snapshot: BossSnapshot
    let date: Date
    @Environment(\.widgetRenderingMode) private var renderingMode

    var body: some View {
        VStack(spacing: 4) {
            BossArt(snapshot: snapshot)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            VStack(spacing: 4) {
                Text(snapshot.bossName)
                    .font(.caption.weight(.bold))
                    .fontDesign(.serif)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                    .foregroundStyle(renderingMode == .fullColor ? Color(hex: 0xFFF6D6) : .primary)
                    .widgetAccentable()
                MiniHPBar(state: snapshot.state)
                StatusLine(snapshot: snapshot, date: date)
                    .font(.caption2)
                    .foregroundStyle(renderingMode == .fullColor ? Color(hex: 0xD6CBEE) : .secondary)
            }
            .nameplate()
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(A11yText.boss(name: snapshot.bossName, state: snapshot.state))
    }
}

/// Segmented HP bar sized for widgets.
struct MiniHPBar: View {
    let state: BossState
    @Environment(\.widgetRenderingMode) private var renderingMode

    var body: some View {
        let filled = state.currentHP <= 0 ? 0 : max(1, Int((state.fraction * 10).rounded(.up)))
        HStack(spacing: 1.5) {
            ForEach(0..<10, id: \.self) { i in
                Rectangle()
                    .fill(i < filled ? AnyShapeStyle(renderingMode == .fullColor ? state.phase.tint : Color.primary) : AnyShapeStyle(renderingMode == .fullColor ? Color(hex: 0x47236A) : Color.primary.opacity(0.2)))
                    .widgetAccentable(i < filled)
            }
        }
        .frame(height: 6)
        .padding(2)
        .background(Rectangle().stroke(Color(hex: 0x1A0D1F), lineWidth: renderingMode == .fullColor ? 1.5 : 0))
    }
}

/// The boss as an image rather than a `Canvas`: in tinted and clear Home Screens a
/// desaturated image keeps its detail, where a drawing turns into a flat silhouette.
struct BossArt: View {
    let snapshot: BossSnapshot

    var body: some View {
        let won = snapshot.state.outcome == .won
        if let image = BossKind.forName(snapshot.bossName).art.cgImage(eyeColor: won ? nil : snapshot.state.phase.eyeColor) {
            Image(decorative: image, scale: 1)
                .resizable()
                .interpolation(.none)
                .widgetAccentedRenderingMode(.desaturated)
                .aspectRatio(contentMode: .fit)
                .grayscale(won ? 1 : 0)
                .widgetAccentable(false)
        }
    }
}

/// A solid night plate behind widget text. Text never sits on the starry
/// background, where stars, windows and the moon would cut through it.
struct Nameplate: ViewModifier {
    @Environment(\.widgetRenderingMode) private var renderingMode

    func body(content: Content) -> some View {
        if renderingMode == .fullColor {
            content
                .padding(.horizontal, 6)
                .padding(.vertical, 4)
                .background(PixelCornerShape(step: 2).fill(Color(hex: 0x150C2B)))
        } else {
            content
        }
    }
}

/// The cream task card. In tinted and clear Home Screens a solid card turns white
/// under white text, so there it's a faint plate and the text keeps the system color.
struct TaskCard: ViewModifier {
    @Environment(\.widgetRenderingMode) private var renderingMode

    func body(content: Content) -> some View {
        if renderingMode == .fullColor {
            content
                .background(PixelCornerShape(step: 2).fill(Theme.card))
                .foregroundStyle(Theme.ink)
        } else {
            content
                .background(PixelCornerShape(step: 2).fill(Color.primary.opacity(0.12)))
                .foregroundStyle(.primary)
        }
    }
}

extension View {
    func nameplate() -> some View { modifier(Nameplate()) }
    func taskCard() -> some View { modifier(TaskCard()) }
}

struct MediumBossView: View {
    let snapshot: BossSnapshot
    let date: Date

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            SmallBossView(snapshot: snapshot, date: date)
                .frame(maxWidth: 130)
            VStack(alignment: .leading, spacing: 6) {
                Text(snapshot.state.outcome == .planning ? "Planned quests" : "Next hits")
                    .font(.caption.weight(.bold))
                    .fontDesign(.serif)
                    .foregroundStyle(.secondary)
                if snapshot.openTasks.isEmpty {
                    Text("No open tasks").font(.caption).foregroundStyle(.secondary)
                }
                ForEach(snapshot.openTasks.prefix(3)) { task in
                    TaskButton(task: task, snapshot: snapshot)
                }
                Spacer(minLength: 0)
            }
            .padding(8)
            .taskCard()
        }
    }
}

/// iPad Home Screen: a big boss, its health, and up to 6 tasks to complete with a tap.
struct LargeBossView: View {
    let snapshot: BossSnapshot
    let date: Date
    @Environment(\.widgetRenderingMode) private var renderingMode

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .center, spacing: 12) {
                BossArt(snapshot: snapshot)
                    .frame(width: 96, height: 96)
                VStack(alignment: .leading, spacing: 4) {
                    Text(snapshot.bossName)
                        .font(.title3.weight(.black))
                        .fontDesign(.serif)
                        .foregroundStyle(renderingMode == .fullColor ? Color(hex: 0xFFF6D6) : .primary)
                        .widgetAccentable()
                    Text(snapshot.raidName)
                        .font(.subheadline)
                        .foregroundStyle(renderingMode == .fullColor ? Color(hex: 0xD6CBEE) : .secondary)
                    MiniHPBar(state: snapshot.state)
                    StatusLine(snapshot: snapshot, date: date)
                        .font(.caption)
                        .foregroundStyle(renderingMode == .fullColor ? Color(hex: 0xD6CBEE) : .secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .nameplate()
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(A11yText.boss(name: snapshot.bossName, state: snapshot.state))

            VStack(alignment: .leading, spacing: 8) {
                Text(snapshot.state.outcome == .planning ? "Planned quests" : "Next hits")
                    .font(.caption.weight(.bold))
                    .fontDesign(.serif)
                    .foregroundStyle(.secondary)
                if snapshot.openTasks.isEmpty {
                    Text("No open tasks").font(.caption).foregroundStyle(.secondary)
                }
                ForEach(snapshot.openTasks) { task in
                    TaskButton(task: task, snapshot: snapshot)
                }
                Spacer(minLength: 0)
            }
            .padding(10)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .taskCard()
        }
    }
}

/// Completes the task right from the widget (runs in the app's process).
struct TaskButton: View {
    let task: BossSnapshot.TaskInfo
    let snapshot: BossSnapshot

    var body: some View {
        let entity = TaskEntity(id: task.id, title: task.title, sizeLetter: task.sizeLetter, raidName: snapshot.raidName)
        Button(intent: CompleteTaskIntent(task: entity)) {
            HStack(spacing: 6) {
                Image(systemName: "circle")
                    .foregroundStyle(.secondary)
                Text(task.title)
                    .font(.caption)
                    .lineLimit(1)
                Spacer(minLength: 0)
                Text(task.sizeLetter)
                    .font(.caption2.bold())
                    .foregroundStyle(.secondary)
            }
        }
        .buttonStyle(.plain)
        .disabled(!snapshot.canComplete)
        .accessibilityLabel("Complete \(task.title), \(task.damage) damage")
    }
}

struct BossRing: View {
    let state: BossState

    var body: some View {
        Gauge(value: state.fraction) {
            Image(systemName: "flame.fill")
        } currentValueLabel: {
            Text("\(state.percent)")
                .font(.caption.bold())
        }
        .gaugeStyle(.accessoryCircularCapacity)
        .tint(state.phase.tint)
        .widgetAccentable()
    }
}

struct PhaseIcon: View {
    let phase: Phase

    var body: some View {
        Image(systemName: phase.symbol)
            .foregroundStyle(phase.tint)
            .widgetAccentable()
            .accessibilityLabel(Text(phase.title))
    }
}

struct StatusLine: View {
    let snapshot: BossSnapshot
    let date: Date

    var body: some View {
        switch snapshot.state.outcome {
        case .planning: Text("Planning")
        case .won: Text("Defeated!")
        case .lost: Text("Deadline passed")
        case .ongoing:
            if snapshot.deadline > date {
                Text(snapshot.deadline, style: .relative)
            } else {
                Text("Deadline passed")
            }
        }
    }
}

struct NoRaidView: View {
    var body: some View {
        VStack(spacing: 6) {
            PixelArtView(BossKind.slime.art)
                .frame(width: 44, height: 44)
            Text("No boss yet")
                .font(.headline)
            Text("Create a raid in the app.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .multilineTextAlignment(.center)
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Lock Screen

struct CircularBossView: View {
    let snapshot: BossSnapshot

    var body: some View {
        Gauge(value: snapshot.state.fraction) {
            Image(systemName: "flame.fill")
        } currentValueLabel: {
            Text("\(snapshot.state.percent)")
        }
        .gaugeStyle(.accessoryCircular)
        .accessibilityLabel(A11yText.boss(name: snapshot.bossName, state: snapshot.state))
    }
}

struct RectangularBossView: View {
    let snapshot: BossSnapshot
    let date: Date

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Label(snapshot.bossName, systemImage: snapshot.state.phase.symbol)
                .font(.headline)
                .widgetAccentable()
                .lineLimit(1)
            ProgressView(value: snapshot.state.fraction)
            StatusLine(snapshot: snapshot, date: date)
                .font(.caption)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(A11yText.boss(name: snapshot.bossName, state: snapshot.state))
    }
}

struct InlineBossView: View {
    let snapshot: BossSnapshot
    let date: Date

    var body: some View {
        ViewThatFits {
            Label("\(snapshot.bossName) \(snapshot.state.percent)%", systemImage: "flame.fill")
            Text("\(snapshot.state.percent)%")
        }
    }
}

#Preview("Small", as: .systemSmall) { BossWidget() } timeline: { BossEntry.preview }
#Preview("Medium", as: .systemMedium) { BossWidget() } timeline: { BossEntry.preview }
#Preview("Large", as: .systemLarge) { BossWidget() } timeline: { BossEntry.preview }
#Preview("Circular", as: .accessoryCircular) { BossWidget() } timeline: { BossEntry.preview }
#Preview("Rectangular", as: .accessoryRectangular) { BossWidget() } timeline: { BossEntry.preview }
