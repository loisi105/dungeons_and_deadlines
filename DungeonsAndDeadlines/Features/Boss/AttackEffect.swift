import SwiftUI
import GameCore
import DDDesign

/// A task attack that the Boss tab should play: who hit, how hard, with which class.
struct AttackCast: Equatable, Identifiable {
    let id: UUID          // the attack's ID
    let raidID: UUID
    let damage: Int
    let role: Role?
    let taskTitle: String
    /// Spoken aloud when it lands: only for tasks you completed yourself (teammates' hits are
    /// announced by the `Announcer`).
    var announces = false
    /// Several attacks in a row play a faster version.
    var quick = false

    /// Spoken after the hit lands.
    var announcement: String {
        switch role {
        case .mage: String(localized: "You cast a spell for \(damage) damage.")
        case .tank: String(localized: "You slam your shield for \(damage) damage.")
        case .rogue: String(localized: "Your daggers strike for \(damage) damage.")
        case .healer: String(localized: "Holy light hits for \(damage) damage.")
        case nil: String(localized: "Your sword hits for \(damage) damage.")
        }
    }

    var glow: Color {
        switch role {
        case .mage: Color(hex: 0x9B6BFF)
        case .tank: Color(hex: 0xC8D8F0)
        case .rogue: Color(hex: 0xE0342F)
        case .healer: Color(hex: 0xFFD24A)
        case nil: Color(hex: 0xF4F8FF)
        }
    }
}

/// Plays one class attack over the boss, then calls `onImpact`.
/// One distinct attack per class. Mage: an arcane orb flies in on an arc. Rogue: three daggers.
/// Tank: a shield slams up. Healer: a beam of holy light with a cross. No class: the sword slashes.
/// - Reduce Motion: the sprite appears at the boss and fades with a soft flash (no travel).
struct AttackEffect: View {
    let cast: AttackCast
    let onImpact: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var progress: CGFloat = 0
    @State private var flash: CGFloat = 0
    @State private var finished = false

    var body: some View {
        GeometryReader { geo in
            let size = geo.size
            let target = CGPoint(x: size.width / 2, y: size.height * 0.45)
            ZStack {
                if !finished {
                    projectile(in: size, target: target)
                }
                // Impact flash in the class color.
                Circle()
                    .fill(cast.glow)
                    .frame(width: 80, height: 80)
                    .scaleEffect(0.3 + flash * 1.6)
                    .opacity(flash > 0 ? Double(1 - flash) : 0)
                    .position(target)
                    .blendMode(.screen)
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
        .onAppear(perform: play)
    }

    @ViewBuilder
    private func projectile(in size: CGSize, target: CGPoint) -> some View {
        let art = SpellArt.art(for: cast.role)
        let sprite = PixelArtView(art).frame(width: 56, height: 56)
        if reduceMotion {
            sprite.position(target).opacity(Double(1 - flash))
        } else {
            switch cast.role {
            case .rogue:
                ForEach(0..<3, id: \.self) { i in
                    let delay = CGFloat(i) * 0.15
                    let t = min(1, max(0, (progress - delay) / (1 - 0.3)))
                    PixelArtView(art).frame(width: 40, height: 40)
                        .position(x: lerp(-30, target.x, t), y: lerp(size.height * (0.3 + CGFloat(i) * 0.15), target.y, t))
                        .opacity(t > 0 && t < 1 ? 1 : 0)
                }
            case .tank:
                sprite
                    .scaleEffect(0.6 + progress * 0.8)
                    .position(x: target.x, y: lerp(size.height + 40, target.y + 20, progress))
            case .healer:
                ZStack {
                    LinearGradient(colors: [Color(hex: 0xFFF0A8).opacity(0), Color(hex: 0xFFD24A).opacity(0.7)], startPoint: .top, endPoint: .bottom)
                        .frame(width: 44, height: target.y * progress)
                        .position(x: target.x, y: target.y * progress / 2)
                    sprite.position(target).opacity(Double(progress))
                }
            case .mage:
                // An arcane orb on an arc from the lower left onto the boss.
                let x = lerp(size.width * 0.1, target.x, progress)
                let y = lerp(size.height * 0.95, target.y, progress) - sin(progress * .pi) * size.height * 0.35
                sprite.position(x: x, y: y)
            case nil:
                // No class: the sword swings down across the boss and leaves a slash.
                ZStack {
                    Capsule()
                        .fill(.white.opacity(0.85))
                        .frame(width: 170 * progress, height: 7)
                        .rotationEffect(.degrees(-38))
                        .position(target)
                        .opacity(Double(progress) < 0.9 ? 1 : Double(1 - progress) * 10)
                    PixelArtView(art)
                        .frame(width: 84, height: 84)
                        .rotationEffect(.degrees(-80 + 150 * Double(progress)), anchor: .bottomTrailing)
                        .position(x: target.x + 26, y: target.y - 10)
                        .opacity(0.4 + Double(progress) * 0.6)
                }
            }
        }
    }

    /// `-slowMotion` (debug) stretches the effect 5× to inspect it frame by frame.
    static var timeScale: Double {
        #if DEBUG
        ProcessInfo.processInfo.arguments.contains("-slowMotion") ? 5 : 1
        #else
        1
        #endif
    }

    private func play() {
        let travel = (reduceMotion ? 0.35 : (cast.role == .rogue ? 0.9 : 0.8)) * (cast.quick ? 0.55 : 1) * Self.timeScale
        withAnimation(.easeIn(duration: travel)) {
            progress = 1
        } completion: {
            onImpact()
            withAnimation(.easeOut(duration: (cast.quick ? 0.3 : 0.5) * Self.timeScale)) {
                flash = 1
            } completion: {
                finished = true
            }
        }
    }

    private func lerp(_ a: CGFloat, _ b: CGFloat, _ t: CGFloat) -> CGFloat { a + (b - a) * t }
}
