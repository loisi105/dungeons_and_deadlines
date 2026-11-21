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
        case .tank: String(localized: "You smash your hammer for \(damage) damage.")
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

/// Plays one class attack over the boss, then calls `onImpact`. Each class has its own weapon and motion,
/// taken from classic RPGs:
/// - No class: the sword swings down across the boss and leaves a slash.
/// - Mage: raises a staff and fires a magic orb with a sparkle trail; a rune circle flares on impact.
/// - Tank (knight): a warhammer swings down in an overhead smash; a shockwave rolls out.
/// - Rogue: two daggers slash in from opposite corners and leave a crossed cut.
/// - Healer: a holy cross descends in a beam of light; halos and sparkles rise.
/// Reduce Motion: the weapon appears at the boss and fades with a soft flash (no travel).
struct AttackEffect: View {
    let cast: AttackCast
    let onImpact: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var startedAt = Date.now

    /// Everything is drawn from the elapsed time, once per frame. (A `withAnimation` between a start and
    /// an end value can't express flights with several stages, trails or an arc.)
    var body: some View {
        TimelineView(.animation) { context in
            let elapsed = context.date.timeIntervalSince(startedAt)
            let linear = CGFloat(min(1, max(0, elapsed / travelDuration)))
            let progress = eased(linear)
            let flash = CGFloat(min(1, max(0, (elapsed - travelDuration) / flashDuration)))
            GeometryReader { geo in
                let size = geo.size
                let target = CGPoint(x: size.width / 2, y: size.height * 0.45)
                ZStack {
                    if linear < 1 || (reduceMotion && flash < 1) {
                        weapon(in: size, target: target, progress: progress, flash: flash)
                    }
                    if flash > 0 && flash < 1 {
                        impact(target: target, flash: flash)
                    }
                }
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
        .task {
            try? await Task.sleep(for: .seconds(travelDuration))
            onImpact()
        }
    }

    // MARK: Travel

    @ViewBuilder
    private func weapon(in size: CGSize, target: CGPoint, progress: CGFloat, flash: CGFloat) -> some View {
        let art = SpellArt.art(for: cast.role)
        if reduceMotion {
            PixelArtView(art).frame(width: 64, height: 64).position(target).opacity(Double(1 - flash))
        } else {
            switch cast.role {
            case nil: swordSlash(art: art, target: target, progress: progress)
            case .mage: magicBolt(art: art, size: size, target: target, progress: progress)
            case .tank: warhammerSmash(art: art, target: target, progress: progress)
            case .rogue: daggerFlurry(art: art, target: target, progress: progress)
            case .healer: holyLight(art: art, size: size, target: target, progress: progress)
            }
        }
    }

    private func swordSlash(art: PixelArt, target: CGPoint, progress: CGFloat) -> some View {
        ZStack {
            Capsule()
                .fill(.white.opacity(0.85))
                .frame(width: 190 * progress, height: 8)
                .rotationEffect(.degrees(-38))
                .position(target)
                .opacity(progress < 0.9 ? 1 : Double(1 - progress) * 10)
            PixelArtView(art)
                .frame(width: 110, height: 110)
                .rotationEffect(.degrees(-80 + 150 * Double(progress)), anchor: .bottomTrailing)
                .position(x: target.x + 34, y: target.y - 14)
                .opacity(0.4 + Double(progress) * 0.6)
        }
    }

    private func magicBolt(art: PixelArt, size: CGSize, target: CGPoint, progress: CGFloat) -> some View {
        let start = CGPoint(x: size.width * 0.16, y: size.height * 0.88)
        // The orb leaves the staff's tip and arcs up onto the boss.
        func position(_ t: CGFloat) -> CGPoint {
            CGPoint(x: lerp(start.x + 24, target.x, t), y: lerp(start.y - 24, target.y, t) - sin(t * .pi) * size.height * 0.32)
        }
        let launch = min(1, progress / 0.25)
        let flight = max(0, (progress - 0.2) / 0.8)
        return ZStack {
            PixelArtView(SpellArt.staff)
                .frame(width: 96, height: 96)
                .rotationEffect(.degrees(-30 + 45 * Double(launch)), anchor: .bottomLeading)
                .position(start)
                .opacity(1 - Double(max(0, flight - 0.4)) * 1.6)
            if flight > 0 {
                ForEach(0..<6, id: \.self) { i in
                    PixelArtView(art)
                        .frame(width: 60 - CGFloat(i) * 7, height: 60 - CGFloat(i) * 7)
                        .position(position(max(0, flight - CGFloat(i) * 0.05)))
                        .opacity(i == 0 ? 1 : 0.5 - Double(i) * 0.07)
                }
            }
        }
    }

    private func warhammerSmash(art: PixelArt, target: CGPoint, progress: CGFloat) -> some View {
        // Pivots around the handle's end, below the boss: raised back, then down onto it.
        PixelArtView(art)
            .frame(width: 112, height: 112)
            .rotationEffect(.degrees(-72 + 72 * Double(progress)), anchor: .bottom)
            .position(x: target.x, y: target.y + 40)
            .opacity(0.5 + Double(progress) * 0.5)
    }

    private func daggerFlurry(art: PixelArt, target: CGPoint, progress: CGFloat) -> some View {
        // Two quick strikes from opposite top corners; the second lands as the first fades.
        let first = clamp(progress / 0.6)
        let second = clamp((progress - 0.4) / 0.6)
        return ZStack {
            dagger(art: art, t: first, from: CGPoint(x: target.x - 170, y: target.y - 190), to: target, degrees: 48, flipped: false)
            dagger(art: art, t: second, from: CGPoint(x: target.x + 170, y: target.y - 190), to: target, degrees: 132, flipped: true)
        }
    }

    private func dagger(art: PixelArt, t: CGFloat, from: CGPoint, to: CGPoint, degrees: Double, flipped: Bool) -> some View {
        PixelArtView(art)
            .frame(width: 70, height: 70)
            .scaleEffect(x: 1, y: flipped ? -1 : 1)
            .rotationEffect(.degrees(degrees))
            .position(x: lerp(from.x, to.x, t), y: lerp(from.y, to.y, t))
            .opacity(t > 0 && t < 1 ? 1 : 0)
    }

    private func holyLight(art: PixelArt, size: CGSize, target: CGPoint, progress: CGFloat) -> some View {
        let crossY = lerp(-40, target.y - 6, progress)
        return ZStack {
            // The beam falls from the top of the scene onto the boss.
            LinearGradient(colors: [Color(hex: 0xFFF0A8).opacity(0), Color(hex: 0xFFD24A).opacity(0.75)], startPoint: .top, endPoint: .bottom)
                .frame(width: 54, height: max(0, crossY + 20))
                .position(x: target.x, y: max(0, crossY + 20) / 2)
            PixelArtView(art)
                .frame(width: 92, height: 92)
                .shadow(color: Color(hex: 0xFFD24A), radius: 12)
                .position(x: target.x, y: crossY)
        }
    }

    // MARK: Impact

    @ViewBuilder
    private func impact(target: CGPoint, flash: CGFloat) -> some View {
        ZStack {
            // Flash in the class color.
            Circle()
                .fill(cast.glow)
                .frame(width: 90, height: 90)
                .scaleEffect(0.3 + flash * 1.7)
                .opacity(Double(1 - flash))
                .blendMode(.screen)
            if !reduceMotion {
                classImpact(flash: flash)
                // Pixel sparks flying outward.
                ForEach(0..<12, id: \.self) { i in
                    let angle = Double(i) / 12 * 2 * .pi
                    Rectangle()
                        .fill(cast.glow)
                        .frame(width: 8, height: 8)
                        .offset(x: cos(angle) * (24 + flash * 96), y: sin(angle) * (24 + flash * 96))
                        .opacity(Double(1 - flash))
                }
            }
        }
        .position(target)
    }

    @ViewBuilder
    private func classImpact(flash: CGFloat) -> some View {
        switch cast.role {
        case .mage:
            // A rune circle flares around the boss.
            Circle()
                .strokeBorder(Color(hex: 0x9B6BFF), style: StrokeStyle(lineWidth: 5, dash: [8, 6]))
                .frame(width: 120, height: 120)
                .scaleEffect(0.4 + flash * 1.4)
                .rotationEffect(.degrees(Double(flash) * 140))
                .opacity(Double(1 - flash))
        case .tank:
            // A shockwave rolls out along the ground.
            Ellipse()
                .stroke(Color(hex: 0xC8D8F0), lineWidth: 6)
                .frame(width: 110, height: 40)
                .scaleEffect(0.3 + flash * 2.6)
                .offset(y: 70)
                .opacity(Double(1 - flash))
        case .rogue:
            // The two cuts cross.
            ZStack {
                Capsule().frame(width: 170, height: 7).rotationEffect(.degrees(42))
                Capsule().frame(width: 170, height: 7).rotationEffect(.degrees(-42))
            }
            .foregroundStyle(Color(hex: 0xFF5A4F))
            .scaleEffect(0.7 + flash * 0.3)
            .opacity(Double(1 - flash))
        case .healer:
            // Two halos and a rising shimmer.
            ZStack {
                Circle().strokeBorder(Color(hex: 0xFFD24A), lineWidth: 5)
                    .frame(width: 100, height: 100).scaleEffect(0.4 + flash * 1.6)
                Circle().strokeBorder(Color(hex: 0xFFF0A8), lineWidth: 3)
                    .frame(width: 100, height: 100).scaleEffect(0.2 + flash * 1.1)
                ForEach(0..<5, id: \.self) { i in
                    Image(systemName: "plus")
                        .font(.system(size: 18, weight: .black))
                        .foregroundStyle(Color(hex: 0xFFF0A8))
                        .offset(x: CGFloat(i - 2) * 30, y: 30 - flash * 90 - CGFloat(i % 2) * 14)
                }
            }
            .opacity(Double(1 - flash))
        case nil:
            EmptyView()
        }
    }

    // MARK: Timing

    /// `-slowMotion` (debug) stretches the effect 5× to inspect it frame by frame.
    static var timeScale: Double {
        #if DEBUG
        ProcessInfo.processInfo.arguments.contains("-slowMotion") ? 5 : 1
        #else
        1
        #endif
    }

    private var travelDuration: Double {
        let base: Double = switch cast.role {
        case .rogue: 0.75
        case .mage, .healer: 0.95
        case .tank: 0.7
        case nil: 0.65
        }
        return (reduceMotion ? 0.35 : base) * (cast.quick ? 0.55 : 1) * Self.timeScale
    }

    private var flashDuration: Double { (cast.quick ? 0.35 : 0.6) * Self.timeScale }

    /// Daggers and hammers speed up into the hit; the mage's orb and the healer's light glide.
    private func eased(_ x: CGFloat) -> CGFloat {
        switch cast.role {
        case .mage, .healer: x * x * (3 - 2 * x)
        default: x * x
        }
    }

    private func lerp(_ a: CGFloat, _ b: CGFloat, _ t: CGFloat) -> CGFloat { a + (b - a) * t }
    private func clamp(_ t: CGFloat) -> CGFloat { min(1, max(0, t)) }
}
