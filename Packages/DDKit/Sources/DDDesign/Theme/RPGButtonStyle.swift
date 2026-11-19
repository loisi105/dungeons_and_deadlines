import SwiftUI

/// Chunky pixel-art buttons: gold for main actions (like the icon's clock bells), cream/night planks for the rest.
/// The button sits on a dark ledge and presses down into it. With Reduce Motion it
/// darkens instead of moving. Labels scale with Dynamic Type; height is at least 44 pt.
public struct RPGButtonStyle: ButtonStyle {
    public enum Kind: Sendable { case primary, secondary, danger }

    let kind: Kind
    public init(_ kind: Kind = .primary) { self.kind = kind }

    public func makeBody(configuration: Configuration) -> some View {
        RPGButton(configuration: configuration, kind: kind)
    }

    struct RPGButton: View {
        let configuration: Configuration
        let kind: Kind
        @Environment(\.isEnabled) private var isEnabled
        @Environment(\.accessibilityReduceMotion) private var reduceMotion
        @Environment(\.colorSchemeContrast) private var contrast

        private let ledge: CGFloat = 4

        var body: some View {
            let pressed = configuration.isPressed
            let shape = PixelCornerShape(step: 3)
            configuration.label
                .font(.headline.weight(.bold))
                .fontDesign(.serif)
                .foregroundStyle(textColor)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 18)
                .padding(.vertical, 10)
                .frame(minHeight: 44)
                .background {
                    shape
                        .fill(LinearGradient(colors: fill, startPoint: .top, endPoint: .bottom))
                        .overlay(alignment: .top) {
                            // Highlight along the top edge, like light catching a bevel.
                            shape.inset(by: 3).stroke(.white.opacity(isEnabled ? 0.25 : 0.1), lineWidth: 1)
                        }
                        .overlay { shape.stroke(Theme.outline, lineWidth: contrast == .increased ? 3 : 2) }
                        .brightness(pressed && reduceMotion ? -0.12 : 0)
                }
                .offset(y: pressed && !reduceMotion ? ledge : 0)
                .background {
                    shape.fill(Theme.outline).offset(y: ledge)
                }
                .padding(.bottom, ledge)
                .contentShape(Rectangle())
                .animation(reduceMotion ? nil : .easeOut(duration: 0.08), value: pressed)
        }

        private var fill: [Color] {
            guard isEnabled else { return [Color(hex: 0xB8AD98), Color(hex: 0x9C917D)] }
            switch kind {
            case .primary: return [Theme.emberTop, Theme.emberBottom]
            case .secondary: return [Theme.woodTop, Theme.woodBottom]
            case .danger: return [Theme.dangerTop, Theme.dangerBottom]
            }
        }

        private var textColor: Color {
            guard isEnabled else { return Color(hex: 0x2B1D0E) }
            switch kind {
            case .primary: return Theme.emberText
            case .danger: return Theme.dangerText
            case .secondary: return Theme.woodText
            }
        }
    }
}

extension View {
    /// The main action on a screen.
    public func primaryActionStyle() -> some View {
        buttonStyle(RPGButtonStyle(.primary))
    }

    /// Secondary actions.
    public func secondaryActionStyle() -> some View {
        buttonStyle(RPGButtonStyle(.secondary))
    }

    /// Destructive actions.
    public func dangerActionStyle() -> some View {
        buttonStyle(RPGButtonStyle(.danger))
    }
}

#Preview("RPG buttons") {
    VStack(spacing: 16) {
        Button("Start fight", systemImage: "flame.fill") {}.primaryActionStyle()
        Button("Add tasks", systemImage: "plus") {}.secondaryActionStyle()
        Button("Leave raid") {}.dangerActionStyle()
        Button("Disabled") {}.primaryActionStyle().disabled(true)
    }
    .padding()
    .background(DungeonBackground())
}
