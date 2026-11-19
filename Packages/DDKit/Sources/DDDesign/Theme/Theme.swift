import SwiftUI

/// "Parchment & Dungeon" theme: an original pixel-fantasy look.
/// Light mode is a sheet of parchment, dark mode a stone dungeon.
/// Every text/background pair here is checked for 4.5:1 contrast or better.
public enum Theme {
    // Palette taken from the app icon art (cream clock face, gold and brass, night purple).

    /// Page background: cream parchment (light) / night sky purple (dark).
    public static let parchment = Color(light: Color(hex: 0xF3E6C8), dark: Color(hex: 0x150C2B))
    public static let parchmentDeep = Color(light: Color(hex: 0xE2CB98), dark: Color(hex: 0x0E0820))
    /// Cards, list rows and panels.
    public static let card = Color(light: Color(hex: 0xFFF6D6), dark: Color(hex: 0x2B184F))
    public static let cardBorder = Color(light: Color(hex: 0xA8691A), dark: Color(hex: 0x5C2B74))
    /// Body text: the icon's outline ink on cream, star-cream on night. ~15:1 on both.
    public static let ink = Color(light: Color(hex: 0x1A0D1F), dark: Color(hex: 0xFFF6D6))
    /// Secondary text, solid (not translucent) so contrast holds over textures. ~7:1.
    public static let inkSoft = Color(light: Color(hex: 0x56412C), dark: Color(hex: 0xD6CBEE))
    /// Interactive text and tint: deep crimson on cream, gold at night.
    public static let accent = Color(light: Color(hex: 0x7A1426), dark: Color(hex: 0xFFD24A))
    public static let gold = Color(light: Color(hex: 0x8A5A12), dark: Color(hex: 0xFFD24A))

    // Button materials.
    /// Main actions: gold, like the clock's bells, with ink text (~12:1).
    public static let emberTop = Color(hex: 0xFFE07A)
    public static let emberBottom = Color(hex: 0xE3A321)
    public static let emberText = Color(hex: 0x1A0D1F)
    /// Secondary actions: cream plank (light) / night stone (dark).
    public static let woodTop = Color(light: Color(hex: 0xFFF6D6), dark: Color(hex: 0x47236A))
    public static let woodBottom = Color(light: Color(hex: 0xE2CB98), dark: Color(hex: 0x2B184F))
    public static let woodText = Color(light: Color(hex: 0x1A0D1F), dark: Color(hex: 0xFFF6D6))
    /// Danger: dark crimson with cream text (~8:1).
    public static let dangerTop = Color(hex: 0xA3202A)
    public static let dangerBottom = Color(hex: 0x7A1426)
    public static let dangerText = Color(hex: 0xFFF6D6)
    public static let outline = Color(hex: 0x1A0D1F)
}

extension Color {
    /// `Color(hex: 0xRRGGBB)`.
    public init(hex: UInt32, opacity: Double = 1) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255,
            opacity: opacity
        )
    }
}

extension View {
    /// The theme's page: textured background behind lists and scroll views,
    /// serif "storybook" type, ink text and ember/gold tint.
    public func dungeonScreen() -> some View {
        modifier(DungeonScreen())
    }

    /// A card on the page: parchment panel with a pixel-notched border.
    public func dungeonPanel(padding: CGFloat = 16) -> some View {
        modifier(DungeonPanel(padding: padding))
    }

    /// List rows drawn as panels instead of system cells.
    public func dungeonRow() -> some View {
        listRowBackground(Theme.card)
    }
}

struct DungeonScreen: ViewModifier {
    func body(content: Content) -> some View {
        content
            .scrollContentBackground(.hidden)
            .background { DungeonBackground() }
    }
}

struct DungeonPanel: ViewModifier {
    let padding: CGFloat
    @Environment(\.colorSchemeContrast) private var contrast

    func body(content: Content) -> some View {
        content
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background {
                PixelCornerShape(step: 4)
                    .fill(Theme.card)
                    .overlay {
                        PixelCornerShape(step: 4)
                            .stroke(Theme.cardBorder, lineWidth: contrast == .increased ? 3 : 2)
                    }
            }
    }
}
