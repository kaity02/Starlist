import SwiftUI

/// A small, fast generator so the stars land in the same places every time.
struct SplitMix64: RandomNumberGenerator {
    private var state: UInt64

    init(seed: UInt64) {
        state = seed
    }

    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}

/// Paints the night sky: the gradient, the glow at the horizon, and a scatter of stars.
public enum SkyPainter {
    /// - Parameters:
    ///   - starScale: Multiplies star sizes. The panel uses 1; the app icon scales up.
    public static func paint(
        in context: inout GraphicsContext,
        size: CGSize,
        starCount: Int,
        seed: UInt64,
        starScale: CGFloat = 1
    ) {
        let rect = CGRect(origin: .zero, size: size)

        context.fill(
            Path(rect),
            with: .linearGradient(
                Gradient(stops: [
                    .init(color: Sky.zenith, location: 0),
                    .init(color: Sky.dusk, location: 0.7),
                    .init(color: Color(rgb: 0x3A2A5E), location: 1),
                ]),
                startPoint: .zero,
                endPoint: CGPoint(x: 0, y: size.height)
            )
        )

        // The last light, low and off-center.
        context.fill(
            Path(rect),
            with: .radialGradient(
                Gradient(colors: [Sky.horizon.opacity(0.8), Sky.horizon.opacity(0)]),
                center: CGPoint(x: size.width * 0.38, y: size.height * 1.1),
                startRadius: 0,
                endRadius: size.width * 0.95
            )
        )

        var generator = SplitMix64(seed: seed)
        for _ in 0..<starCount {
            let x = CGFloat.random(in: 0...size.width, using: &generator)
            // Stars thin out toward the horizon, where the glow washes them away.
            let fall = pow(CGFloat.random(in: 0...1, using: &generator), 1.7)
            let y = fall * size.height * 0.84
            let magnitude = pow(CGFloat.random(in: 0...1, using: &generator), 3)
            let radius = (0.45 + magnitude * 0.85) * starScale
            let alpha = (0.14 + magnitude * 0.4) * (1 - fall * 0.6)
            let warm = Int.random(in: 0..<7, using: &generator) == 0
            let color = warm ? Sky.starlight : Color.white

            let dot = CGRect(x: x - radius, y: y - radius, width: radius * 2, height: radius * 2)
            if magnitude > 0.55 {
                let halo = dot.insetBy(dx: -radius * 2.2, dy: -radius * 2.2)
                context.fill(
                    Path(ellipseIn: halo),
                    with: .radialGradient(
                        Gradient(colors: [color.opacity(alpha * 0.35), color.opacity(0)]),
                        center: CGPoint(x: x, y: y),
                        startRadius: 0,
                        endRadius: halo.width / 2
                    )
                )
            }
            context.fill(Path(ellipseIn: dot), with: .color(color.opacity(alpha)))
        }
    }
}

struct SkyBackground: View {
    var body: some View {
        Canvas(rendersAsynchronously: false) { context, size in
            SkyPainter.paint(in: &context, size: size, starCount: 78, seed: 11)
        }
        .accessibilityHidden(true)
    }
}
