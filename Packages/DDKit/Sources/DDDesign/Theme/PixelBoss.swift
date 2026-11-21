import SwiftUI
import GameCore

extension Phase {
    /// Eye glow: calm gold to furious red.
    public var eyeColor: Color {
        switch self {
        case .calm: Color(hex: 0xFFD24A)
        case .angry: Color(hex: 0xF59E0B)
        case .enraged: Color(hex: 0xF97316)
        case .berserk: Color(hex: 0xE0342F)
        }
    }
}

/// The boss, drawn as 64×64 pixel art. Eyes glow with the phase, it bobs while idle
/// (not with Reduce Motion), flashes when hit, and lies greyed out when defeated.
public struct BossAvatar: View {
    let kind: BossKind
    let phase: Phase
    let defeated: Bool
    let hitCount: Int
    @ScaledMetric(relativeTo: .largeTitle) private var baseSize: CGFloat = 160
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    /// Bigger on iPad, where there's room for it.
    private var size: CGFloat { horizontalSizeClass == .regular ? baseSize * 1.6 : baseSize }
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    public init(bossName: String = "Deadline", phase: Phase, defeated: Bool = false, hitCount: Int = 0) {
        self.kind = BossKind.forName(bossName)
        self.phase = phase
        self.defeated = defeated
        self.hitCount = hitCount
    }

    public var body: some View {
        TimelineView(.periodic(from: .now, by: 0.5)) { context in
            let frame = Int(context.date.timeIntervalSinceReferenceDate / 0.5) % 2
            PixelArtView(kind.art, eyeColor: defeated ? Color(hex: 0x1A0D1F) : phase.eyeColor)
                .frame(width: size, height: size)
                .grayscale(defeated ? 1 : 0)
                .opacity(defeated ? 0.8 : 1)
                .rotationEffect(defeated ? .degrees(90) : .zero)
                .offset(y: !reduceMotion && !defeated && frame == 1 ? -size / 64 * 2 : 0)
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}

#Preview("Bosses") {
    ScrollView {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 170))]) {
            ForEach(BossKind.allCases, id: \.self) { kind in
                VStack {
                    BossAvatar(bossName: kind.rawValue, phase: .enraged)
                    Text(kind.rawValue)
                }
            }
        }
    }
    .background(DungeonBackground())
}
