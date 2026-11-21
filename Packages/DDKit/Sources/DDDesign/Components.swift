import SwiftUI
import GameCore
#if canImport(UIKit)
import UIKit
#endif

/// The boss health bar: 20 pixel segments in a notched frame. VoiceOver sees it as a
/// progress indicator with a spoken value. Segments plus the HP text mean it never
/// relies on color alone.
public struct HPBar: View {
    let current: Int
    let max: Int
    let phase: Phase
    let bossName: String

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorSchemeContrast) private var contrast
    @ScaledMetric(relativeTo: .body) private var height: CGFloat = 24
    static let segments = 20

    public init(current: Int, max: Int, phase: Phase, bossName: String) {
        self.current = current
        self.max = max
        self.phase = phase
        self.bossName = bossName
    }

    var fraction: Double { max > 0 ? Double(current) / Double(max) : 0 }
    var filled: Int { current <= 0 ? 0 : Swift.max(1, Int((fraction * Double(Self.segments)).rounded(.up))) }

    public var body: some View {
        HStack(spacing: 2) {
            ForEach(0..<Self.segments, id: \.self) { i in
                if i < filled {
                    Rectangle().fill(phase.tint)
                } else {
                    // Empty slots are outlined so the bar stays readable at 0 HP.
                    Rectangle().strokeBorder(Theme.inkSoft, lineWidth: 1.5)
                }
            }
        }
        .padding(4)
        .frame(height: height)
        .background(PixelCornerShape(step: 3).fill(Theme.card))
        .overlay(PixelCornerShape(step: 3).stroke(Theme.outline, lineWidth: contrast == .increased ? 3 : 2))
        .animation(reduceMotion ? nil : .smooth(duration: 0.35), value: filled)
        .accessibilityRepresentation {
            // Label set directly (no hidden Text child that the audit would measure).
            ProgressView(value: Double(current), total: Double(Swift.max(max, 1)))
                .accessibilityLabel(Text("\(bossName) health"))
                .accessibilityValue(Text("\(current) of \(max), \(Int((fraction * 100).rounded())) percent"))
        }
    }
}

/// Phase as symbol + text. Never color only.
public struct PhaseBadge: View {
    let phase: Phase
    /// The raid leader shifted the phase (`Raid.phaseShift != 0`), so the time rule in
    /// `phase.hint` doesn't hold; VoiceOver says who set it instead.
    let isShifted: Bool
    /// Tapping the badge opens details; a small info mark says so.
    let showsInfoMark: Bool

    public init(_ phase: Phase, isShifted: Bool = false, showsInfoMark: Bool = false) {
        self.phase = phase
        self.isShifted = isShifted
        self.showsInfoMark = showsInfoMark
    }

    public var body: some View {
        HStack(spacing: 8) {
            Label {
                Text(phase.title)
            } icon: {
                Image(systemName: phase.symbol)
                    .foregroundStyle(phase.tint)
            }
            if showsInfoMark {
                Image(systemName: "info.circle")
                    .imageScale(.small)
                    .foregroundStyle(Theme.inkSoft)
            }
        }
        .font(.subheadline.weight(.bold))
        .fontDesign(.serif)
        .foregroundStyle(Theme.ink)
        .padding(.horizontal, 14)
        .frame(minHeight: 44)
        .background(PixelCornerShape(step: 3).fill(phase.tint.opacity(0.18)))
        .overlay(PixelCornerShape(step: 3).stroke(phase.tint, lineWidth: 2))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(isShifted
            ? Text("Phase \(phase.rawValue): \(Text(phase.title)). Set by the raid leader.")
            : Text("Phase \(phase.rawValue): \(Text(phase.title)). \(Text(phase.hint))"))
    }
}

/// Size chip for tasks: symbol + letter, with the damage in the accessibility label.
public struct SizeChip: View {
    let size: TaskSize
    let damage: Int

    public init(_ size: TaskSize, damage: Int) {
        self.size = size
        self.damage = damage
    }

    public var body: some View {
        Label(size.shortTitle, systemImage: size.symbol)
            .labelStyle(.titleAndIcon)
            .font(.caption.weight(.bold))
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .foregroundStyle(Theme.ink)
            .background(PixelCornerShape(step: 2).fill(Theme.parchmentDeep))
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Text("\(Text(size.title)), \(damage) damage"))
    }
}

#Preview("HP bar") {
    VStack(spacing: 20) {
        HPBar(current: 800, max: 1000, phase: .calm, bossName: "Exam Dragon")
        HPBar(current: 400, max: 1000, phase: .enraged, bossName: "Exam Dragon")
        PhaseBadge(.berserk)
        SizeChip(.l, damage: 400)
        BossAvatar(bossName: "Exam Dragon", phase: .angry)
    }
    .padding()
    .background(DungeonBackground())
}

/// Footnote text that meets contrast guidelines on grouped backgrounds
/// (the system's secondary color only "nearly passes").
public struct ReadableFootnote: ViewModifier {
    @Environment(\.colorSchemeContrast) private var contrast

    public func body(content: Content) -> some View {
        content
            .font(.footnote)
            .foregroundStyle(contrast == .increased ? Theme.ink : Theme.inkSoft)
    }
}

extension View {
    public func readableFootnote() -> some View { modifier(ReadableFootnote()) }
}

extension Color {
    /// Fill for prominent actions. Dark enough that white labels reach 4.5:1 in both modes.
    public static let actionTint = Theme.emberBottom
}

extension Color {
    /// A color with separate light and dark values (light values are darker for contrast on white).
    public init(light: Color, dark: Color) {
        #if canImport(UIKit)
        self.init(uiColor: UIColor { traits in
            traits.userInterfaceStyle == .dark ? UIColor(dark) : UIColor(light)
        })
        #else
        self = light
        #endif
    }
}

extension ShapeStyle where Self == Color {
    /// Secondary text that still reaches 4.5:1 on white, grouped and filled backgrounds.
    public static var readableSecondary: Color { Theme.inkSoft }
}

/// Title + value row that stacks vertically at large text sizes instead of truncating.
public struct InfoRow<Value: View>: View {
    let title: LocalizedStringKey
    let value: Value

    public init(_ title: LocalizedStringKey, @ViewBuilder value: () -> Value) {
        self.title = title
        self.value = value()
    }

    public var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .firstTextBaseline) {
                Text(title)
                Spacer(minLength: 12)
                value.foregroundStyle(.readableSecondary).multilineTextAlignment(.trailing)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                value.foregroundStyle(.readableSecondary)
            }
        }
        .accessibilityElement(children: .combine)
    }
}

extension InfoRow where Value == Text {
    public init(_ title: LocalizedStringKey, value: String) {
        self.init(title) { Text(value) }
    }
}
