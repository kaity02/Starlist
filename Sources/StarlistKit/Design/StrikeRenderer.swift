import SwiftUI

/// Draws a task title and crosses it out with a shooting star.
///
/// `progress` runs from 0 (untouched) to 1 (struck through). In between, a
/// small comet travels along each line of text and the strike-through is the
/// trail it leaves. At rest the trail cools to a quiet lavender line.
struct StrikeRenderer: TextRenderer {
    var progress: Double
    var fontSize: CGFloat
    /// The comet only appears when a task is being finished, not un-finished.
    var showsHead: Bool

    var animatableData: Double {
        get { progress }
        set { progress = newValue }
    }

    /// Room for the comet's glow outside the text bounds.
    var displayPadding: EdgeInsets {
        EdgeInsets(top: 10, leading: 4, bottom: 10, trailing: 12)
    }

    func draw(layout: Text.Layout, in context: inout GraphicsContext) {
        let amount = min(max(progress, 0), 1)

        var textContext = context
        textContext.opacity = 1 - 0.48 * amount
        for line in layout {
            textContext.draw(line)
        }
        guard amount > 0 else { return }

        let bounds = layout.map(\.typographicBounds)
        let total = bounds.reduce(0) { $0 + $1.width }
        guard total > 0 else { return }

        // Brightest mid-flight, gone at both ends.
        let heat = showsHead ? sin(amount * .pi) : 0
        let settled = Sky.haze.opacity(0.85)
        var remaining = total * amount

        for line in bounds {
            guard remaining > 0.01 else { break }
            let length = min(line.width, remaining)
            remaining -= length
            let isLeadingLine = remaining <= 0.01

            // Through the middle of the lowercase letters.
            let y = line.origin.y - fontSize * 0.27
            let start = CGPoint(x: line.origin.x - 1, y: y)
            let end = CGPoint(x: line.origin.x + length + (length >= line.width ? 1 : 0), y: y)
            var path = Path()
            path.move(to: start)
            path.addLine(to: end)

            if isLeadingLine && heat > 0.01 {
                let warmFrom = CGPoint(x: max(start.x, end.x - 90), y: y)
                context.stroke(
                    path,
                    with: .linearGradient(
                        Gradient(colors: [settled, Sky.haze.mix(with: Sky.starlight, by: heat)]),
                        startPoint: warmFrom,
                        endPoint: end
                    ),
                    style: StrokeStyle(lineWidth: 1.3 + heat * 0.7, lineCap: .round)
                )
                drawHead(at: end, heat: heat, in: &context)
            } else {
                context.stroke(
                    path,
                    with: .color(settled),
                    style: StrokeStyle(lineWidth: 1.3, lineCap: .round)
                )
            }
        }
    }

    private func drawHead(at point: CGPoint, heat: Double, in context: inout GraphicsContext) {
        var glow = context
        glow.blendMode = .plusLighter

        let reach: CGFloat = 10
        glow.fill(
            Path(ellipseIn: CGRect(
                x: point.x - reach, y: point.y - reach, width: reach * 2, height: reach * 2
            )),
            with: .radialGradient(
                Gradient(colors: [Sky.starlight.opacity(0.6 * heat), Sky.starlight.opacity(0)]),
                center: point,
                startRadius: 0,
                endRadius: reach
            )
        )

        // Four short rays, like a star seen through glass.
        let ray = 6.5 * heat
        var rays = Path()
        rays.move(to: CGPoint(x: point.x - ray, y: point.y))
        rays.addLine(to: CGPoint(x: point.x + ray, y: point.y))
        rays.move(to: CGPoint(x: point.x, y: point.y - ray))
        rays.addLine(to: CGPoint(x: point.x, y: point.y + ray))
        glow.stroke(
            rays,
            with: .color(Sky.starlight.opacity(0.9 * heat)),
            style: StrokeStyle(lineWidth: 0.9, lineCap: .round)
        )

        let core: CGFloat = 1.9
        glow.fill(
            Path(ellipseIn: CGRect(
                x: point.x - core, y: point.y - core, width: core * 2, height: core * 2
            )),
            with: .color(Color.white.opacity(heat))
        )
    }
}
