import SwiftUI

/// The whole panel: a window of night sky with the list or History in front.
public struct RootView: View {
    @ObservedObject private var model: AppModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    public init(model: AppModel) {
        self.model = model
    }

    public var body: some View {
        let outline = RoundedRectangle(cornerRadius: PanelMetrics.cornerRadius, style: .continuous)

        ZStack {
            SkyBackground()

            switch model.screen {
            case .list:
                ListScreen(model: model)
                    .transition(.move(edge: .leading).combined(with: .opacity))
            case .history:
                HistoryScreen(model: model)
                    .transition(.move(edge: .trailing).combined(with: .opacity))
            case .notion:
                NotionScreen(model: model)
                    .transition(.move(edge: .trailing).combined(with: .opacity))
            }

            StarBurstOverlay(trigger: model.celebration)
        }
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.26), value: model.screen)
        .frame(width: PanelMetrics.width, height: PanelMetrics.height)
        .clipShape(outline)
        .overlay(outline.strokeBorder(Color.white.opacity(0.14), lineWidth: 1))
        .environment(\.colorScheme, .dark)
    }
}

/// The strike-through at several points in its flight. Used by the snapshot
/// tool to check the animation frame by frame.
public struct StrikeGallery: View {
    public init() {}

    public var body: some View {
        ZStack {
            SkyBackground()
            VStack(alignment: .leading, spacing: 20) {
                ForEach([0.0, 0.3, 0.62, 0.9, 1.0], id: \.self) { progress in
                    Text("Send the invoice to the studio before Friday so it clears in time")
                        .font(Face.text(14))
                        .foregroundStyle(Sky.moonlight)
                        .textRenderer(
                            StrikeRenderer(progress: progress, fontSize: 14, showsHead: true)
                        )
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(24)
        }
        .frame(width: PanelMetrics.width, height: 320)
    }
}
