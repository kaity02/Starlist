import SwiftUI

/// The palette is a clear night just after dusk: indigo overhead, a plum glow
/// at the horizon, and one warm light for anything that is finished.
public enum Sky {
    /// Deep indigo at the top of the panel.
    public static let zenith = Color(rgb: 0x12122B)
    /// Violet through the middle.
    public static let dusk = Color(rgb: 0x2B2352)
    /// Plum glow along the bottom edge.
    public static let horizon = Color(rgb: 0x6A3F72)
    /// Primary text.
    public static let moonlight = Color(rgb: 0xEFEAFB)
    /// Secondary text and quiet controls.
    public static let haze = Color(rgb: 0xA9A3CF)
    /// The accent: stars, finished tasks, focus.
    public static let starlight = Color(rgb: 0xFFD58A)
    /// Problems and destructive hover states.
    public static let ember = Color(rgb: 0xFF9F8E)
}

extension Color {
    init(rgb: UInt32, opacity: Double = 1) {
        self.init(
            .sRGB,
            red: Double((rgb >> 16) & 0xFF) / 255,
            green: Double((rgb >> 8) & 0xFF) / 255,
            blue: Double(rgb & 0xFF) / 255,
            opacity: opacity
        )
    }
}

/// Two families, both installed with macOS. Cochin's italic recalls the engraved
/// lettering on old star charts and is used only for titles; Avenir Next carries
/// everything you read and type.
enum Face {
    enum Weight {
        case regular, medium, demi

        var postScriptName: String {
            switch self {
            case .regular: "AvenirNext-Regular"
            case .medium: "AvenirNext-Medium"
            case .demi: "AvenirNext-DemiBold"
            }
        }
    }

    static func display(_ size: CGFloat) -> Font {
        .custom("Cochin-Italic", fixedSize: size)
    }

    static func text(_ size: CGFloat, _ weight: Weight = .regular) -> Font {
        .custom(weight.postScriptName, fixedSize: size)
    }
}

/// The panel's fixed measurements, shared with the AppKit shell.
public enum PanelMetrics {
    public static let width: CGFloat = 340
    public static let height: CGFloat = 500
    public static let cornerRadius: CGFloat = 18
    /// Left and right edge of the text column.
    static let gutter: CGFloat = 22
}
