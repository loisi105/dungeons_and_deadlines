import SwiftUI
import GameCore
#if canImport(UIKit)
import UIKit
#endif

/// The boss health bar. Content layer: deliberately not glass.
/// VoiceOver sees it as a progress indicator with a spoken value.
public struct HPBar: View {
    let current: Int
    let max: Int
    let phase: Phase
    let bossName: String

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorSchemeContrast) private var contrast
    @Environment(\.accessibilityDifferentiateWithoutColor) private var differentiateWithoutColor
    @ScaledMetric(relativeTo: .body) private var height: CGFloat = 22

    public init(current: Int, max: Int, phase: Phase, bossName: String) {
        self.current = current
        self.max = max
        self.phase = phase
        self.bossName = bossName
    }

    var fraction: Double { max > 0 ? Double(current) / Double(max) : 0 }

    public var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.primary.opacity(0.12))
                Capsule()
                    .fill(phase.tint)
                    .frame(width: proxy.size.width * fraction)
                    .overlay {
                        if differentiateWithoutColor {
                            // Stripes so the fill reads without relying on hue.
                            Capsule().fill(.clear).overlay(
                                Image(systemName: "line.diagonal")
                                    .resizable(resizingMode: .tile)
                                    .foregroundStyle(.black.opacity(0.25))
                            ).clipShape(Capsule())
                        }
                    }
                Capsule().strokeBorder(.primary.opacity(contrast == .increased ? 0.9 : 0.15), lineWidth: contrast == .increased ? 2 : 1)
            }
        }
        .frame(height: height)
        .animation(reduceMotion ? nil : .spring(duration: 0.5), value: current)
        .accessibilityRepresentation {
            ProgressView(value: Double(current), total: Double(Swift.max(max, 1))) {
                Text("\(bossName) health")
            }
            .accessibilityValue(Text("\(current) of \(max), \(Int((fraction * 100).rounded())) percent"))
        }
    }
}

/// Phase as symbol + text. Never color only.
public struct PhaseBadge: View {
    let phase: Phase

    public init(_ phase: Phase) { self.phase = phase }

    public var body: some View {
        Label {
            Text(phase.title)
        } icon: {
            Image(systemName: phase.symbol)
                .foregroundStyle(phase.tint)
        }
        .font(.subheadline.weight(.semibold))
        .padding(.horizontal, 14)
        .frame(minHeight: 44)
        .background(phase.tint.opacity(0.15), in: Capsule())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("Phase \(phase.rawValue): \(Text(phase.title)). \(Text(phase.hint))"))
    }
}

/// Placeholder boss art until final illustrations exist (see open decisions).
public struct BossAvatar: View {
    let phase: Phase
    let defeated: Bool
    @ScaledMetric(relativeTo: .largeTitle) private var size: CGFloat = 120

    public init(phase: Phase, defeated: Bool = false) {
        self.phase = phase
        self.defeated = defeated
    }

    public var body: some View {
        Image(systemName: defeated ? "lizard" : "lizard.fill")
            .resizable()
            .scaledToFit()
            .frame(width: size, height: size)
            .foregroundStyle(defeated ? AnyShapeStyle(.secondary) : AnyShapeStyle(phase.tint.gradient))
            .rotationEffect(defeated ? .degrees(180) : .zero)
            .accessibilityHidden(true)
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
            .background(.thinMaterial, in: Capsule())
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
        BossAvatar(phase: .angry)
    }
    .padding()
}

/// Footnote text that meets contrast guidelines on grouped backgrounds
/// (the system's secondary color only "nearly passes").
public struct ReadableFootnote: ViewModifier {
    @Environment(\.colorSchemeContrast) private var contrast

    public func body(content: Content) -> some View {
        content
            .font(.footnote)
            .foregroundStyle(Color.primary.opacity(contrast == .increased ? 1 : 0.75))
    }
}

extension View {
    public func readableFootnote() -> some View { modifier(ReadableFootnote()) }
}

extension Color {
    /// Fill for prominent actions. Dark enough that white labels reach 4.5:1 in both modes.
    public static let actionTint = Color(red: 0.60, green: 0.16, blue: 0.03)
}

extension View {
    /// The main action on a screen: Liquid Glass prominent style with an accessible tint.
    public func primaryActionStyle() -> some View {
        buttonStyle(.glassProminent).tint(.actionTint).fontWeight(.semibold)
    }
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
    public static var readableSecondary: Color { Color.primary.opacity(0.72) }
}

extension View {
    /// Secondary actions: Liquid Glass with full-contrast labels.
    public func secondaryActionStyle() -> some View {
        buttonStyle(.glass).foregroundStyle(.primary)
    }
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
