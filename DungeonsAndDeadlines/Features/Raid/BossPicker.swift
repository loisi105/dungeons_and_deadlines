import SwiftUI
import GameCore
import DDDesign

/// All boss looks at a glance. The look comes from the boss name, so tapping a boss
/// fills in one of its names, and typing a name highlights the boss it turns into.
/// On the free plan only `BossKind.freeKinds` can be picked; the others show a lock.
struct BossPicker: View {
    @Binding var bossName: String
    var isPremium: Bool
    /// Called after every tap on an unlocked boss, including the one already chosen.
    var onPick: () -> Void = {}
    /// Called instead of `onPick` for a tap on a locked (Premium) boss; the name stays as it is.
    var onLocked: (BossKind) -> Void = { _ in }
    @ScaledMetric(relativeTo: .caption) private var tileSize: CGFloat = 64
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// Counts taps that pick a boss, so typing a name doesn't buzz on every keystroke.
    @State private var picks = 0

    /// The art stops growing here; only the labels follow larger text sizes.
    private var artSize: CGFloat { min(tileSize, 88) }

    var body: some View {
        // Free bosses on top, then the Premium ones under their own header. Premium players get
        // the same two sections, just without locks.
        VStack(alignment: .leading, spacing: 16) {
            grid(BossKind.freeKinds)
            Label {
                Text("Premium bosses")
            } icon: {
                Image(systemName: "crown.fill").foregroundStyle(Theme.gold)
            }
            .font(.headline)
            .fontDesign(.serif)
            .foregroundStyle(Theme.ink)
            .accessibilityAddTraits(.isHeader)
            .padding(.top, 4)
            grid(BossKind.allCases.filter { !$0.isFree })
        }
        .sensoryFeedback(.selection, trigger: picks)
    }

    private func grid(_ kinds: [BossKind]) -> some View {
        let name = bossName.trimmingCharacters(in: .whitespacesAndNewlines)
        let selected = BossNames.kind(forName: bossName)
        // Columns widen with the text size: two columns at the largest sizes, so names like
        // "Dragon" or "Cyclops" don't break mid-word. At the default size the art sets the width.
        return LazyVGrid(columns: [GridItem(.adaptive(minimum: max(artSize, tileSize * 0.75)), spacing: 10, alignment: .top)], spacing: 12) {
            ForEach(kinds, id: \.self) { kind in
                let isSelected = kind == selected
                let isLocked = !isPremium && !kind.isFree
                Button {
                    if isLocked {
                        onLocked(kind)
                        return
                    }
                    // Keep a name the user typed if it already shows this boss.
                    if !isSelected {
                        picks += 1
                        withAnimation(reduceMotion ? nil : .snappy(duration: 0.2)) {
                            bossName = BossNames.random(for: kind)
                        }
                    }
                    onPick()
                } label: {
                    BossTile(kind: kind, isSelected: isSelected, isLocked: isLocked, size: artSize)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Text(kind.title))
                .accessibilityValue(accessibilityValue(isSelected: isSelected, isLocked: isLocked, name: name))
                .accessibilityHint(isLocked ? Text("Shows Premium") : Text("Names your boss"))
                .accessibilityAddTraits(isSelected ? .isSelected : [])
                .accessibilityIdentifier("bossPick.\(kind.rawValue)")
            }
        }
    }

    private func accessibilityValue(isSelected: Bool, isLocked: Bool, name: String) -> Text {
        switch (isSelected, isLocked) {
        case (true, true): Text("\(name), Premium")
        case (true, false): Text(name)
        case (false, true): Text("Premium")
        case (false, false): Text("")
        }
    }
}

/// The full boss grid as a sheet. Picking a boss (or the chosen one again) closes it;
/// picking a locked one on the free plan opens the paywall on top.
struct BossPickerSheet: View {
    @Binding var bossName: String
    @Environment(\.dismiss) private var dismiss
    @Environment(Entitlements.self) private var entitlements
    @State private var paywall: PaywallReason?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text("The boss's look follows its name. Pick one, or type your own name.")
                        .readableFootnote()
                        .frame(maxWidth: .infinity, alignment: .leading)
                    BossPicker(bossName: $bossName, isPremium: entitlements.isPremium) {
                        dismiss()
                    } onLocked: { _ in
                        paywall = PaywallReason(block: .premiumBoss)
                    }
                }
                .padding(16)
            }
            .dungeonScreen()
            .navigationTitle("Choose your boss")
            .navigationBarTitleDisplayMode(.inline)
            .sheetCloseButton(identifier: "bossPickerDoneButton")
        }
        .sheet(item: $paywall) { PaywallView(reason: $0.block) }
        // Full height: a medium detent clips the grid at large text sizes.
        .presentationDetents([.large])
    }
}

/// Small framed preview of the boss a name turns into, or a question mark for no name.
/// `isLocked` adds the Premium lock badge.
struct BossThumbnail: View {
    let kind: BossKind?
    var isLocked = false
    var size: CGFloat = 44

    var body: some View {
        Group {
            if let kind {
                BossFrame(kind: kind, isSelected: false, size: size)
                    .overlay(alignment: .bottomTrailing) {
                        if isLocked { PremiumLockBadge(size: size).offset(x: 4, y: 4) }
                    }
            } else {
                Image(systemName: "questionmark")
                    .font(.system(size: size * 0.45, weight: .bold))
                    .foregroundStyle(Theme.inkSoft)
                    .frame(width: size, height: size)
                    .background(Theme.card)
                    .clipShape(PixelCornerShape(step: 3))
                    .overlay {
                        PixelCornerShape(step: 3)
                            .strokeBorder(BossFrame.outline, lineWidth: 1.5)
                    }
            }
        }
        .contentShape(Rectangle())
    }
}

/// The boss art in its pixel frame, without a label.
private struct BossFrame: View {
    let kind: BossKind
    let isSelected: Bool
    let size: CGFloat

    /// Theme.outline disappears on the dark page, so dark mode gets a lighter edge (5.9:1).
    static let outline = Color(light: Color(hex: 0x1A0D1F), dark: Color(hex: 0x9A86C4))

    var body: some View {
        PixelArtView(kind.art)
            .padding(size * 0.08)
            .frame(width: size, height: size)
            .background(PixelArtView(.nightSky, fill: true))
            .clipShape(PixelCornerShape(step: 3))
            .overlay {
                PixelCornerShape(step: 3)
                    .strokeBorder(isSelected ? Theme.accent : Self.outline, lineWidth: isSelected ? 3 : 1.5)
            }
    }
}

/// Marks a Premium boss on the free plan: a solid gold disc (`Theme.emberTop`) with a dark pixel
/// lock and ring (`Theme.outline`), the same in both modes. The lock is ~14:1 on the gold; the ring
/// is ~15:1 on the light page, and the gold is well over 3:1 on the dark page and the night-sky art.
/// Drawn as a shape sized from the art (which already follows Dynamic Type). An SF Symbol at a
/// fixed size is reported by the accessibility audit as text that ignores the text size.
struct PremiumLockBadge: View {
    /// The framed art's size; the badge scales with it.
    let size: CGFloat

    var body: some View {
        let disc = max(17, size * 0.32)
        PixelGlyph.lock
            .fill(Theme.outline, style: FillStyle(eoFill: true))
            .padding(disc * 0.24)
            .frame(width: disc, height: disc)
            .background(Theme.emberTop, in: Circle())
            .overlay { Circle().strokeBorder(Theme.outline, lineWidth: 1.5) }
            .accessibilityHidden(true)
    }
}

/// The chosen boss: a pixel checkmark in card color on an accent disc.
private struct SelectedBadge: View {
    let size: CGFloat

    var body: some View {
        let disc = max(16, size * 0.28)
        PixelGlyph.check
            .fill(Theme.card)
            .padding(disc * 0.22)
            .frame(width: disc, height: disc)
            .background(Theme.accent, in: Circle())
            .accessibilityHidden(true)
    }
}

/// Tiny 8x8 pixel icons that match the boss art.
nonisolated private struct PixelGlyph: Shape {
    /// Filled cells as (x, y, width, height) on an 8x8 grid.
    let cells: [(CGFloat, CGFloat, CGFloat, CGFloat)]

    /// Shackle, body, and a keyhole cut out with the even-odd rule.
    static let lock = PixelGlyph(cells: [(2, 0, 4, 1), (2, 1, 1, 2), (5, 1, 1, 2), (1, 3, 6, 5), (3, 5, 2, 1)])
    /// A two-pixel-thick tick.
    static let check = PixelGlyph(cells: [
        (0, 4, 1, 2), (1, 5, 1, 2), (2, 6, 1, 2), (3, 5, 1, 2), (4, 4, 1, 2), (5, 3, 1, 2), (6, 2, 1, 2), (7, 1, 1, 2),
    ])

    func path(in rect: CGRect) -> Path {
        let unit = min(rect.width, rect.height) / 8
        let origin = CGPoint(x: rect.midX - unit * 4, y: rect.midY - unit * 4)
        var path = Path()
        for (x, y, w, h) in cells {
            path.addRect(CGRect(x: origin.x + x * unit, y: origin.y + y * unit, width: w * unit, height: h * unit))
        }
        return path
    }
}

private struct BossTile: View {
    let kind: BossKind
    let isSelected: Bool
    let isLocked: Bool
    let size: CGFloat
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(spacing: 4) {
            BossFrame(kind: kind, isSelected: isSelected, size: size)
                .overlay(alignment: .topTrailing) {
                    if isSelected { SelectedBadge(size: size).offset(x: 5, y: -5) }
                }
                .overlay(alignment: .bottomTrailing) {
                    // Bottom corner, so it never collides with the selection checkmark (top) or the label.
                    if isLocked { PremiumLockBadge(size: size).offset(x: 5, y: 2) }
                }
                .scaleEffect(isSelected && !reduceMotion ? 1.06 : 1)
            Text(kind.title)
                // Not .caption2: it stays 11pt from the smallest text size up to the default,
                // which the accessibility audit reports as partially ignoring Dynamic Type.
                .font(.caption.weight(isSelected ? .bold : .regular))
                .foregroundStyle(isSelected ? Theme.ink : Theme.inkSoft)
                // No shrink-to-fit; the columns widen with the text size so the names fit at AX5.
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity)
        .contentShape(Rectangle())
    }
}

#Preview {
    @Previewable @State var name = "Exam Dragon"
    BossPickerSheet(bossName: $name)
        .environment(Entitlements())
}
