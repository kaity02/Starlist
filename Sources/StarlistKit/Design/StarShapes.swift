import AppKit
import SwiftUI

/// A five-point star with softened tips. The same star is the app icon, the
/// menu bar glyph, and the mark on a finished task.
public struct StarShape: Shape {
    public var innerRatio: CGFloat
    public var rounding: CGFloat
    public var rotation: CGFloat

    public init(innerRatio: CGFloat = 0.5, rounding: CGFloat = 0.14, rotation: CGFloat = 0) {
        self.innerRatio = innerRatio
        self.rounding = rounding
        self.rotation = rotation
    }

    public func path(in rect: CGRect) -> Path {
        let radius = min(rect.width, rect.height) / 2
        // An upright star's points sit low in its circle; nudge it to look centered.
        let center = CGPoint(x: rect.midX, y: rect.midY + radius * 0.05)
        return Self.path(
            center: center, radius: radius,
            innerRatio: innerRatio, rounding: rounding, rotation: rotation
        )
    }

    /// - Parameters:
    ///   - rounding: Tip radius as a fraction of the star's radius.
    ///   - rotation: Radians, clockwise. Zero puts one point straight up.
    public static func path(
        center: CGPoint,
        radius: CGFloat,
        innerRatio: CGFloat = 0.5,
        rounding: CGFloat = 0.14,
        rotation: CGFloat = 0
    ) -> Path {
        let count = 10
        let vertices: [CGPoint] = (0..<count).map { index in
            let angle = rotation - .pi / 2 + CGFloat(index) * .pi / 5
            let reach = index.isMultiple(of: 2) ? radius : radius * innerRatio
            return CGPoint(x: center.x + cos(angle) * reach, y: center.y + sin(angle) * reach)
        }
        var path = Path()
        let first = vertices[0]
        let last = vertices[count - 1]
        path.move(to: CGPoint(x: (first.x + last.x) / 2, y: (first.y + last.y) / 2))
        for index in 0..<count {
            let next = vertices[(index + 1) % count]
            let corner = index.isMultiple(of: 2) ? radius * rounding : radius * rounding * 0.55
            path.addArc(tangent1End: vertices[index], tangent2End: next, radius: corner)
        }
        path.closeSubpath()
        return path
    }
}

/// The shooting star: a tilted star with three tapering trails behind it.
public struct ShootingStarGeometry {
    public struct Trail {
        public let path: Path
        /// Where the trail leaves the star.
        public let start: CGPoint
        /// Where it thins to nothing.
        public let end: CGPoint
    }

    public let star: Path
    public let trails: [Trail]
    public let starCenter: CGPoint
    public let starRadius: CGFloat

    /// - Parameter separated: Leaves a sliver of space between the star and its
    ///   trails. That keeps the silhouette readable when everything is one flat
    ///   color, as in the menu bar. The app icon tucks the trails under the star.
    public init(in rect: CGRect, separated: Bool) {
        let side = min(rect.width, rect.height)
        let origin = CGPoint(x: rect.midX - side / 2, y: rect.midY - side / 2)

        // Flying up and to the right, 38 degrees above level.
        let travel: CGFloat = -38 * .pi / 180
        let tail = CGVector(dx: -cos(travel), dy: -sin(travel))
        let normal = CGVector(dx: -tail.dy, dy: tail.dx)

        let center = CGPoint(x: origin.x + 0.69 * side, y: origin.y + 0.365 * side)
        // The flat menu bar version gets a slightly larger star so it holds up at 18 points.
        let radius = (separated ? 0.285 : 0.27) * side
        starCenter = center
        starRadius = radius
        // One point leads; the notch opposite it is where the middle trail leaves.
        star = StarShape.path(center: center, radius: radius, rotation: travel + .pi / 2)

        // A point `distance` star-radii behind the star and `offset` radii to the side.
        func behind(_ distance: CGFloat, _ offset: CGFloat) -> CGPoint {
            CGPoint(
                x: center.x + (tail.dx * distance + normal.dx * offset) * radius,
                y: center.y + (tail.dy * distance + normal.dy * offset) * radius
            )
        }

        func trail(offset: CGFloat, from near: CGFloat, to far: CGFloat, width: CGFloat) -> Trail {
            var path = Path()
            path.move(to: behind(near, offset + width / 2))
            path.addLine(to: behind(far, offset))
            path.addLine(to: behind(near, offset - width / 2))
            path.addQuadCurve(
                to: behind(near, offset + width / 2),
                control: behind(near - width * 0.7, offset)
            )
            path.closeSubpath()
            return Trail(path: path, start: behind(near, offset), end: behind(far, offset))
        }

        // The two rear points sit 36 degrees either side of the tail.
        let spread = sin(36 * CGFloat.pi / 180)
        if separated {
            trails = [
                trail(offset: 0, from: 0.86, to: 2.6, width: 0.44),
                trail(offset: spread, from: 1.16, to: 2.15, width: 0.32),
                trail(offset: -spread, from: 1.16, to: 2.15, width: 0.32),
            ]
        } else {
            trails = [
                trail(offset: 0, from: 0.3, to: 2.9, width: 0.44),
                trail(offset: spread, from: 0.6, to: 2.35, width: 0.27),
                trail(offset: -spread, from: 0.6, to: 2.35, width: 0.27),
            ]
        }
    }
}

/// Draws the shooting star in full color, for the app icon and empty states.
public enum ShootingStarPainter {
    public static func paint(in context: inout GraphicsContext, rect: CGRect, glow: Bool = true) {
        let geometry = ShootingStarGeometry(in: rect, separated: false)
        let gold = Sky.starlight

        for trail in geometry.trails {
            context.fill(
                trail.path,
                with: .linearGradient(
                    Gradient(stops: [
                        .init(color: gold.opacity(0.95), location: 0),
                        .init(color: gold.opacity(0.4), location: 0.5),
                        .init(color: gold.opacity(0), location: 1),
                    ]),
                    startPoint: trail.start,
                    endPoint: trail.end
                )
            )
        }

        var starContext = context
        if glow {
            starContext.addFilter(.shadow(
                color: gold.opacity(0.65),
                radius: geometry.starRadius * 0.32
            ))
        }
        let radius = geometry.starRadius
        starContext.fill(
            geometry.star,
            with: .linearGradient(
                Gradient(colors: [Color(rgb: 0xFFF7DC), Color(rgb: 0xFFC55A)]),
                startPoint: CGPoint(
                    x: geometry.starCenter.x - radius * 0.6,
                    y: geometry.starCenter.y - radius * 0.8
                ),
                endPoint: CGPoint(
                    x: geometry.starCenter.x + radius * 0.6,
                    y: geometry.starCenter.y + radius * 0.9
                )
            )
        )
    }
}

/// A small full-color shooting star for use inside the panel.
struct ShootingStarMark: View {
    var size: CGFloat = 56

    var body: some View {
        Canvas { context, canvasSize in
            ShootingStarPainter.paint(
                in: &context,
                rect: CGRect(origin: .zero, size: canvasSize)
            )
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}

/// The menu bar icon: a template image, so macOS tints it for light and dark menu bars.
public enum StatusGlyph {
    /// - Parameters:
    ///   - time: The focus timer's time left, drawn to the right of the star.
    ///     It is part of the image, so it is tinted along with the star and
    ///     the star stays where it is when the time appears.
    ///   - dimmed: Draws the time faintly, for a paused timer.
    public static func image(
        pointSize: CGFloat = 18, time: String? = nil, dimmed: Bool = false
    ) -> NSImage {
        // Digits of equal width, so the time doesn't shiver as it counts down.
        let font = NSFont.monospacedDigitSystemFont(ofSize: pointSize * 13 / 18, weight: .medium)
        let label = time.map {
            NSAttributedString(string: $0, attributes: [
                .font: font,
                .foregroundColor: NSColor.black.withAlphaComponent(dimmed ? 0.5 : 1),
            ])
        }
        let gap = pointSize * 4 / 18
        let labelWidth = label.map { ceil($0.size().width) + gap } ?? 0

        let size = NSSize(width: pointSize + labelWidth, height: pointSize)
        let image = NSImage(size: size, flipped: true) { rect in
            guard let context = NSGraphicsContext.current?.cgContext else { return false }
            let square = CGRect(x: rect.minX, y: rect.minY, width: pointSize, height: pointSize)
            let geometry = ShootingStarGeometry(in: square, separated: true)
            context.setFillColor(NSColor.black.cgColor)
            context.addPath(geometry.star.cgPath)
            context.fillPath()
            for trail in geometry.trails {
                context.addPath(trail.path.cgPath)
                context.fillPath()
            }
            if let label {
                // The digits' middle on the star's middle.
                let baseline = rect.midY + font.capHeight / 2
                label.draw(at: CGPoint(x: square.maxX + gap, y: baseline - font.ascender))
            }
            return true
        }
        image.isTemplate = true
        image.accessibilityDescription = "Starlist"
        return image
    }
}
