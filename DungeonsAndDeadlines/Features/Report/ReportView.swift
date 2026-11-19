import SwiftUI
import SwiftData
import Charts
import Accessibility
import GameCore
import DDPersistence
import DDDesign

/// End-of-raid report: outcome, HP over time, titles per member, late and open tasks.
/// Doubles as the "group project judge". Shareable as an image with a text description.
struct ReportView: View {
    let raidID: UUID
    @Environment(\.dismiss) private var dismiss

    // Queries keep the report live while teammates' last hits arrive.
    @Query private var attacks: [AttackRecord]
    @Query private var members: [MemberRecord]
    @Query private var tasks: [TaskRecord]
    @Query private var raids: [RaidRecord]

    init(raidID: UUID) {
        self.raidID = raidID
        _attacks = Query(filter: #Predicate<AttackRecord> { $0.raidID == raidID })
        _members = Query(filter: #Predicate<MemberRecord> { $0.raidID == raidID })
        _tasks = Query(filter: #Predicate<TaskRecord> { $0.raidID == raidID && $0.deletedAt == nil })
        _raids = Query(filter: #Predicate<RaidRecord> { $0.id == raidID })
    }

    private var report: RaidReport? {
        guard let raid = raids.first?.model else { return nil }
        return Titles.report(
            raid: raid, members: members.map(\.model), tasks: tasks.map(\.model), attacks: attacks.map(\.model),
            now: .now, config: DDStore.shared.config
        )
    }

    var body: some View {
        NavigationStack {
            Group {
                if let report {
                    ReportContent(report: report)
                } else {
                    ContentUnavailableView("No report", systemImage: "doc")
                }
            }
            .navigationTitle("Raid report")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
                if let report {
                    ToolbarItem(placement: .primaryAction) { ShareReportButton(report: report) }
                }
            }
        }
    }
}

struct ReportContent: View {
    let report: RaidReport

    var body: some View {
        List {
            Section { header }.dungeonRow()
            Section {
                Text("Boss health over time").font(.headline).accessibilityAddTraits(.isHeader)
                HPChart(report: report)
            }
            .dungeonRow()
            Section {
                Text("The party").font(.headline).accessibilityAddTraits(.isHeader)
                ForEach(report.rows) { row in MemberCard(row: row) }
            }
            .dungeonRow()
            if !report.lateTasks.isEmpty {
                Section {
                    Text("Added after the fight started").font(.headline).accessibilityAddTraits(.isHeader)
                    Text("These still dealt damage, but weren't part of the boss's health.").readableFootnote()
                    ForEach(report.lateTasks) { task in
                        Label(task.title, systemImage: "clock.badge.exclamationmark")
                    }
                }
                .dungeonRow()
            }
            if !report.openTasks.isEmpty {
                Section {
                    Text("Left undone").font(.headline).accessibilityAddTraits(.isHeader)
                    ForEach(report.openTasks) { task in
                        Label(task.title, systemImage: "circle")
                    }
                }
                .dungeonRow()
            }
        }
        .dungeonScreen()
    }

    private var header: some View {
        VStack(spacing: 10) {
            BossAvatar(bossName: report.raid.bossName, phase: report.highestPhase, defeated: report.state.outcome == .won)
            Text(report.state.outcome.title)
                .font(.largeTitle.bold())
                .accessibilityAddTraits(.isHeader)
            Text(summary)
                .multilineTextAlignment(.center)
                .foregroundStyle(.readableSecondary)
            ViewThatFits {
                HStack(spacing: 20) { stats }
                VStack(spacing: 8) { stats }
            }
            .padding(.top, 4)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical)
    }

    @ViewBuilder
    private var stats: some View {
        Stat(value: "\(report.state.totalDamage)", label: "damage")
        Stat(value: "\(report.state.currentHP)", label: "HP left")
        Stat(value: "\(report.rows.count)", label: "fighters")
    }

    private var summary: String {
        switch report.state.outcome {
        case .won: String(localized: "\(report.raid.bossName) was defeated.")
        case .lost: String(localized: "\(report.raid.bossName) survived the deadline.")
        default: String(localized: "The fight isn't over yet.")
        }
    }
}

struct Stat: View {
    let value: String
    let label: LocalizedStringKey

    var body: some View {
        VStack {
            Text(value).font(.title2.bold()).monospacedDigit()
            Text(label).font(.caption).foregroundStyle(.readableSecondary)
        }
        .accessibilityElement(children: .combine)
    }
}

struct MemberCard: View {
    let row: RaidReport.Row

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                if let role = row.member.role { Image(systemName: role.symbol).accessibilityHidden(true) }
                Text(row.member.nickname).font(.headline)
                Spacer()
                Text("\(row.stats.total)").font(.headline).monospacedDigit()
            }
            Text("Tasks \(row.stats.tasksCompleted) (\(row.stats.burst) dmg) · Focus \(A11yText.shortDuration(row.stats.focusSeconds)) (\(row.stats.sustained) dmg) · Best streak \(row.longestStreak) d")
                .font(.subheadline)
                .foregroundStyle(.readableSecondary)
            if !row.titles.isEmpty {
                ForEach(row.titles) { title in
                    Label {
                        Text("\(Text(title.name)): \(Text(title.explanation))")
                    } icon: {
                        Image(systemName: title.symbol).foregroundStyle(Theme.gold)
                    }
                    .font(.subheadline.weight(.semibold))
                }
            }
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
    }
}

struct HPChart: View {
    let report: RaidReport

    var body: some View {
        if report.timeline.count < 2 {
            Text("No hits yet.").foregroundStyle(.readableSecondary)
        } else {
            Chart {
                ForEach(Array(report.timeline.enumerated()), id: \.offset) { _, point in
                    LineMark(x: .value("Time", point.date), y: .value("HP", point.hp))
                        .interpolationMethod(.stepEnd)
                    AreaMark(x: .value("Time", point.date), y: .value("HP", point.hp))
                        .interpolationMethod(.stepEnd)
                        .foregroundStyle(report.highestPhase.tint.opacity(0.2))
                }
                RuleMark(x: .value("Deadline", report.raid.deadline))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4]))
                    .annotation(position: .top, alignment: .trailing) { Text("Deadline").font(.caption2) }
            }
            .foregroundStyle(report.highestPhase.tint)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Text("Boss health over time"))
            .accessibilityValue(Text("From \(report.state.maxHP) to \(report.state.currentHP) HP"))
            .chartYScale(domain: 0...max(report.state.maxHP, 1))
            .frame(height: 180)
            .accessibilityChartDescriptor(HPChartDescriptor(report: report))
        }
    }
}

struct HPChartDescriptor: AXChartDescriptorRepresentable {
    let report: RaidReport

    func makeChartDescriptor() -> AXChartDescriptor {
        let points = report.timeline
        let start = points.first?.date.timeIntervalSince1970 ?? 0
        let end = max(points.last?.date.timeIntervalSince1970 ?? 1, start + 1)
        let x = AXNumericDataAxisDescriptor(title: String(localized: "Time"), range: start...end, gridlinePositions: []) {
            Date(timeIntervalSince1970: $0).formatted(date: .abbreviated, time: .shortened)
        }
        let y = AXNumericDataAxisDescriptor(title: String(localized: "Health"), range: 0...Double(max(report.state.maxHP, 1)), gridlinePositions: []) { "\(Int($0)) HP" }
        let series = AXDataSeriesDescriptor(name: String(localized: "Boss health"), isContinuous: true, dataPoints: points.map {
            AXDataPoint(x: $0.date.timeIntervalSince1970, y: Double($0.hp))
        })
        return AXChartDescriptor(
            title: String(localized: "Boss health over time"),
            summary: String(localized: "From \(report.state.maxHP) to \(report.state.currentHP) HP."),
            xAxis: x, yAxis: y, additionalAxes: [], series: [series]
        )
    }
}

/// Shares a rendered image of the report together with a full text version,
/// so the shared content is accessible too.
struct ShareReportButton: View {
    let report: RaidReport
    @Environment(\.displayScale) private var displayScale

    var body: some View {
        if let image = renderedImage {
            ShareLink(item: image, message: Text(textSummary), preview: SharePreview(String(localized: "Raid report"), image: image)) {
                Label("Share", systemImage: "square.and.arrow.up")
            }
        } else {
            ShareLink(item: textSummary) { Label("Share", systemImage: "square.and.arrow.up") }
        }
    }

    private var renderedImage: Image? {
        let renderer = ImageRenderer(content: ShareCard(report: report).frame(width: 390))
        renderer.scale = displayScale
        return renderer.uiImage.map { Image(uiImage: $0) }
    }

    private var textSummary: String {
        var lines = [String(localized: "\(report.raid.name) vs \(report.raid.bossName): \(String(localized: report.state.outcome.title))")]
        for row in report.rows {
            let titles = row.titles.map { String(localized: $0.name) }.joined(separator: ", ")
            lines.append("• \(row.member.nickname): \(row.stats.total)" + (titles.isEmpty ? "" : " (\(titles))"))
        }
        return lines.joined(separator: "\n")
    }
}

/// The image version of the report.
struct ShareCard: View {
    let report: RaidReport

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                PixelArtView(BossKind.forName(report.raid.bossName).art)
                    .grayscale(report.state.outcome == .won ? 1 : 0)
                    .frame(width: 60, height: 60)
                VStack(alignment: .leading) {
                    Text(report.state.outcome.title).font(.title.bold())
                    Text("\(report.raid.name) vs \(report.raid.bossName)").font(.subheadline)
                }
            }
            ForEach(report.rows) { row in
                HStack {
                    Text(row.member.nickname).bold()
                    ForEach(row.titles) { Image(systemName: $0.symbol) }
                    Spacer()
                    Text("\(row.stats.total)").monospacedDigit()
                }
            }
            Text("Dungeons & Deadlines").font(.caption).foregroundStyle(Theme.inkSoft)
        }
        .padding(20)
        .foregroundStyle(Theme.ink)
        .background(Theme.card)
        .fontDesign(.serif)
    }
}
