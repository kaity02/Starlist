import SwiftUI

/// The app icon, drawn in code so it stays sharp at every size.
///
/// It follows the macOS icon grid: on a 1024 canvas, an 824 rounded square
/// with a soft shadow beneath it.
public struct AppIconView: View {
    private let size: CGFloat

    public init(size: CGFloat) {
        self.size = size
    }

    public var body: some View {
        let side = size * 824 / 1024
        let tile = RoundedRectangle(cornerRadius: side * 0.225, style: .continuous)

        ZStack {
            Canvas(rendersAsynchronously: false) { context, canvasSize in
                SkyPainter.paint(
                    in: &context,
                    size: canvasSize,
                    starCount: size >= 128 ? 26 : 0,
                    seed: 5,
                    starScale: canvasSize.width / 150
                )
                let inset = canvasSize.width * 0.045
                ShootingStarPainter.paint(
                    in: &context,
                    rect: CGRect(origin: .zero, size: canvasSize).insetBy(dx: inset, dy: inset)
                )
            }
            .frame(width: side, height: side)
            .clipShape(tile)
            .overlay(
                // A faint rim of light along the top edge.
                tile.strokeBorder(
                    LinearGradient(
                        colors: [Color.white.opacity(0.28), Color.white.opacity(0.02)],
                        startPoint: .top,
                        endPoint: .bottom
                    ),
                    lineWidth: max(side * 0.006, 0.5)
                )
            )
            .shadow(color: .black.opacity(0.3), radius: size * 0.012, y: size * 0.01)
        }
        .frame(width: size, height: size)
    }
}
