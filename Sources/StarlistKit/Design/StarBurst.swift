import SwiftUI

/// The celebration when the last task is checked off: one star swells in the
/// middle of the panel, then bursts into a flurry of small ones.
///
/// It is a pure function of time, so any moment can be drawn (and checked) on its own.
public enum StarBurstPainter {
    /// From trigger to the last star fading out.
    public static let duration: Double = 2.5
    /// Lets the strike-through comet cross the task first.
    static let startDelay: Double = 0.34
    private static let swell: Double = 0.42
    private static let starCount = 38

    public static func paint(
        in context: inout GraphicsContext,
        size: CGSize,
        time: Double,
        reduceMotion: Bool = false
    ) {
        let t = time - startDelay
        guard t >= 0, time < duration else { return }
        let center = CGPoint(x: size.width / 2, y: size.height * 0.44)

        if reduceMotion {
            // No movement: a single star that brightens and fades in place.
            let alpha = sin(min(t / 1.5, 1) * .pi)
            star(in: &context, at: center, radius: 30, rotation: 0, alpha: alpha, glow: true)
            return
        }

        // The big star swells with a little overshoot, then pops.
        let pop = max(0, (t - swell) / 0.16)
        if pop < 1 {
            let p = min(t / swell, 1)
            let overshoot = 1.70158
            let scale = 1 + (overshoot + 1) * pow(p - 1, 3) + overshoot * pow(p - 1, 2)
            star(
                in: &context,
                at: center,
                radius: 34 * (0.15 + 0.85 * scale) * (1 + 0.5 * pop),
                rotation: (1 - p) * -0.7,
                alpha: 1 - pop,
                glow: true
            )
        }

        let burst = t - swell
        guard burst >= 0 else { return }

        // A flash of light where the star was.
        if burst < 0.35 {
            let reach = 34 + 240 * burst
            var flash = context
            flash.blendMode = .plusLighter
            flash.fill(
                Path(ellipseIn: CGRect(
                    x: center.x - reach, y: center.y - reach, width: reach * 2, height: reach * 2
                )),
                with: .radialGradient(
                    Gradient(colors: [
                        Sky.starlight.opacity(0.5 * (1 - burst / 0.35)),
                        Sky.starlight.opacity(0),
                    ]),
                    center: center,
                    startRadius: 0,
                    endRadius: reach
                )
            )
        }

        // The flurry. Every star's path is fixed by the seed, so frames agree.
        var generator = SplitMix64(seed: 0x57A2)
        for index in 0..<starCount {
            let angle = Double(index) / Double(starCount) * 2 * .pi
                + Double.random(in: -0.14...0.14, using: &generator)
            let speed = Double.random(in: 110...420, using: &generator)
            let life = Double.random(in: 1.0...1.75, using: &generator)
            let radius = CGFloat.random(in: 2.6...6.8, using: &generator)
            let spin = Double.random(in: -5...5, using: &generator)
            let pale = Int.random(in: 0..<4, using: &generator) == 0
            guard burst < life else { continue }

            // Thrown outward, slowed by drag, pulled gently down.
            let drag = 3.4
            let travel = speed * (1 - exp(-drag * burst)) / drag
            let position = CGPoint(
                x: center.x + cos(angle) * travel,
                y: center.y + sin(angle) * travel + 46 * burst * burst
            )
            let age = burst / life
            let fade = 1 - smoothstep(0.5, 1, age)
            let twinkle = 0.78 + 0.22 * sin(burst * 15 + Double(index) * 1.7)
            star(
                in: &context,
                at: position,
                radius: radius * (1 - 0.35 * age),
                rotation: spin * burst,
                alpha: fade * twinkle,
                color: pale ? Color(rgb: 0xFFF7DC) : Sky.starlight,
                glow: false
            )
        }
    }

    private static func star(
        in context: inout GraphicsContext,
        at center: CGPoint,
        radius: CGFloat,
        rotation: Double,
        alpha: Double,
        color: Color = Sky.starlight,
        glow: Bool
    ) {
        guard alpha > 0.01, radius > 0.2 else { return }
        var layer = context
        layer.opacity = alpha
        if glow {
            layer.addFilter(.shadow(color: Sky.starlight.opacity(0.8), radius: radius * 0.5))
        }
        layer.fill(
            StarShape.path(center: center, radius: radius, rotation: rotation),
            with: .color(color)
        )
    }

    private static func smoothstep(_ low: Double, _ high: Double, _ value: Double) -> Double {
        let x = min(max((value - low) / (high - low), 0), 1)
        return x * x * (3 - 2 * x)
    }
}

/// Plays the burst over the panel each time `trigger` changes.
struct StarBurstOverlay: View {
    let trigger: Int

    @Stored private var startedAt: Date?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            if let startedAt {
                TimelineView(.animation) { timeline in
                    Canvas { context, size in
                        StarBurstPainter.paint(
                            in: &context,
                            size: size,
                            time: timeline.date.timeIntervalSince(startedAt),
                            reduceMotion: reduceMotion
                        )
                    }
                }
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
        .onChange(of: trigger) {
            let began = Date()
            startedAt = began
            DispatchQueue.main.asyncAfter(deadline: .now() + StarBurstPainter.duration + 0.1) {
                if startedAt == began { startedAt = nil }
            }
        }
    }
}

/// The burst at several moments, side by side. Used by the snapshot tool.
public struct StarBurstFrames: View {
    private let times: [Double] = [0.55, 0.8, 1.0, 1.5]

    public init() {}

    public var body: some View {
        HStack(spacing: 0) {
            ForEach(times, id: \.self) { time in
                Canvas { context, size in
                    SkyPainter.paint(in: &context, size: size, starCount: 40, seed: 11)
                    StarBurstPainter.paint(in: &context, size: size, time: time)
                }
                .frame(width: PanelMetrics.width, height: 360)
            }
        }
    }
}
