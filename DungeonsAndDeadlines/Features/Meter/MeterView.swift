import SwiftUI
import SwiftData
import Charts
import Accessibility
import GameCore
import DDPersistence
import DDDesign

/// WoW-style damage meter: burst (tasks) vs sustained (focus) per member.
/// Chart with an audio-graph descriptor, plus a plain list that is always available.
struct MeterView: View {
    let raidID: UUID

    @AppStorage("settings.meterAsList", store: AppGroup.defaults) private var asList = false
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @Query private var attacks: [AttackRecord]
    @Query private var members: [MemberRecord]

    init(raidID: UUID) {
        self.raidID = raidID
        _attacks = Query(filter: #Predicate<AttackRecord> { $0.raidID == raidID }, sort: \AttackRecord.createdAt)
        _members = Query(filter: #Predicate<MemberRecord> { $0.raidID == raidID }, sort: \MemberRecord.joinedAt)
    }

    struct Row: Identifiable {
        let id: String
        let name: String
        let role: Role?
        let stats: MemberStats
    }

    private var rows: [Row] {
        let stats = BossEngine.memberStats(attacks: attacks.map(\.model))
        let me = LocalIdentity.current.memberID
        return members.map { m in
            Row(
                id: m.memberID,
                name: m.memberID == me ? String(localized: "\(m.nickname) (you)") : m.nickname,
                role: m.model.role,
                stats: stats.first { $0.memberID == m.memberID } ?? MemberStats(memberID: m.memberID)
            )
        }
        .sorted { $0.stats.total != $1.stats.total ? $0.stats.total > $1.stats.total : $0.name < $1.name }
    }

    private var attacking: [MemberRecord] { members.filter { $0.activeFocusSince != nil } }

    var body: some View {
        NavigationStack {
            List {
                // At accessibility sizes the meter is always a list, so no switch.
                if !dynamicTypeSize.isAccessibilitySize {
                    Section {
                        Picker("Show as", selection: $asList) {
                            Label("Chart", systemImage: "chart.bar.xaxis").tag(false)
                            Label("List", systemImage: "list.number").tag(true)
                        }
                        .pickerStyle(.segmented)
                        .sensoryFeedback(.selection, trigger: asList)
                    }
                    .dungeonRow()
                }

                if rows.allSatisfy({ $0.stats.total == 0 }) {
                    ContentUnavailableView("No damage yet", systemImage: "chart.bar", description: Text("Complete tasks or focus to fill the meter."))
                } else if asList || dynamicTypeSize.isAccessibilitySize {
                    listSection
                } else {
                    chartSection
                }

                if !attacking.isEmpty {
                    Section {
                        Text("Attacking now").font(.headline).accessibilityAddTraits(.isHeader)
                        ForEach(attacking) { member in
                            TimelineView(.everyMinute) { context in
                                let minutes = max(0, Int(context.date.timeIntervalSince(member.activeFocusSince ?? context.date) / 60))
                                Text("\(Image(systemName: "flame.fill")) \(member.nickname), attacking for \(minutes) min")
                            }
                        }
                    }
                    .dungeonRow()
                }
            }
            .headerProminence(.increased)
            .dungeonScreen()
            .readableContentWidth()
            .navigationTitle("Meter")
            // Rows re-rank and numbers tick up as hits arrive.
            .animation(reduceMotion ? nil : .snappy, value: rows.map(\.stats.total))
            .animation(reduceMotion ? nil : .snappy, value: asList)
        }
    }

    private var chartSection: some View {
        Section {
            VStack(alignment: .leading, spacing: 4) {
                Text("Burst and sustained damage").font(.headline).accessibilityAddTraits(.isHeader)
                HStack(spacing: 16) {
                    LegendItem(color: Color(light: Color(hex: 0x7A1426), dark: Color(hex: 0xFFD24A)), title: "Tasks", symbol: "bolt.fill")
                    LegendItem(color: Color(light: Color(hex: 0x3B2A8C), dark: Color(hex: 0xC9B7FF)), title: "Focus", symbol: "timer")
                }
                .font(.subheadline)
            }
            Chart {
                ForEach(rows) { row in
                    BarMark(x: .value("Damage", row.stats.burst), y: .value("Member", row.name))
                        .foregroundStyle(by: .value("Source", String(localized: "Tasks")))
                    BarMark(x: .value("Damage", row.stats.sustained), y: .value("Member", row.name))
                        .foregroundStyle(by: .value("Source", String(localized: "Focus")))
                        .annotation(position: .trailing) {
                            Text("\(row.stats.total)")
                                .font(.caption.bold())
                                .monospacedDigit()
                                .contentTransition(.numericText())
                        }
                }
            }
            .chartForegroundStyleScale([
                String(localized: "Tasks"): Color(light: Color(hex: 0x7A1426), dark: Color(hex: 0xFFD24A)),
                String(localized: "Focus"): Color(light: Color(hex: 0x3B2A8C), dark: Color(hex: 0xC9B7FF)),
            ])
            // Our own legend: the built-in one doesn't scale with Dynamic Type.
            .chartLegend(.hidden)
            .frame(height: CGFloat(max(rows.count, 1)) * 52 + 40)
            // One element that speaks every bar, plus the audio graph for VoiceOver's chart rotor.
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Text("Damage chart"))
            .accessibilityValue(Text(rows.map { "\($0.name): \($0.stats.total), tasks \($0.stats.burst), focus \($0.stats.sustained)" }.joined(separator: ". ")))
            .accessibilityChartDescriptor(MeterChartDescriptor(rows: rows))
            .padding(.vertical, 8)
        }
        .dungeonRow()
    }

    private var listSection: some View {
        Section {
            Text("Ranking").font(.headline).accessibilityAddTraits(.isHeader)
            ForEach(Array(rows.enumerated()), id: \.element.id) { index, row in
                VStack(alignment: .leading, spacing: 6) {
                    Text("\(index + 1). \(row.name): \(row.stats.total)")
                        .font(.headline)
                        .monospacedDigit()
                        .contentTransition(.numericText())
                    Group {
                        if dynamicTypeSize.isAccessibilitySize {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Tasks: \(row.stats.burst)")
                                Text("Focus: \(row.stats.sustained)")
                                Text("Focused: \(A11yText.shortDuration(row.stats.focusSeconds))")
                            }
                        } else {
                            HStack(spacing: 16) { details(row) }
                        }
                    }
                    .font(.subheadline)
                    .foregroundStyle(.readableSecondary)
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(Text("\(index + 1). \(row.name): \(row.stats.total) damage. Tasks \(row.stats.burst), focus \(row.stats.sustained), \(A11yText.duration(row.stats.focusSeconds)) focused."))
            }
        }
        .dungeonRow()
    }

    @ViewBuilder
    private func details(_ row: Row) -> some View {
        Label("\(row.stats.burst)", systemImage: "bolt.fill")
        Label("\(row.stats.sustained)", systemImage: "timer")
        Label(A11yText.shortDuration(row.stats.focusSeconds), systemImage: "hourglass")
    }
}

/// Describes the meter for VoiceOver's audio graphs and chart navigation.
struct MeterChartDescriptor: AXChartDescriptorRepresentable {
    let rows: [MeterView.Row]

    func makeChartDescriptor() -> AXChartDescriptor {
        let names = rows.map(\.name)
        let maxValue = Double(rows.map(\.stats.total).max() ?? 1)
        let xAxis = AXCategoricalDataAxisDescriptor(title: String(localized: "Member"), categoryOrder: names)
        let yAxis = AXNumericDataAxisDescriptor(title: String(localized: "Damage"), range: 0...max(maxValue, 1), gridlinePositions: []) { "\(Int($0))" }
        let tasks = AXDataSeriesDescriptor(name: String(localized: "Tasks"), isContinuous: false, dataPoints: rows.map {
            AXDataPoint(x: $0.name, y: Double($0.stats.burst))
        })
        let focus = AXDataSeriesDescriptor(name: String(localized: "Focus"), isContinuous: false, dataPoints: rows.map {
            AXDataPoint(x: $0.name, y: Double($0.stats.sustained))
        })
        return AXChartDescriptor(
            title: String(localized: "Damage meter"),
            summary: rows.first.map { String(localized: "\($0.name) leads with \($0.stats.total) damage.") },
            xAxis: xAxis, yAxis: yAxis, additionalAxes: [], series: [tasks, focus]
        )
    }
}

struct LegendItem: View {
    let color: Color
    let title: LocalizedStringKey
    let symbol: String

    var body: some View {
        Label {
            Text(title).foregroundStyle(Theme.ink)
        } icon: {
            Image(systemName: symbol).foregroundStyle(color)
        }
    }
}
