import SwiftUI

/// A quiet text button: no chrome until the pointer is over it.
struct GhostButton: View {
    let title: String
    var accent = false
    var help: String?
    let action: () -> Void

    @Stored private var hovering = false
    @Environment(\.isEnabled) private var isEnabled

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(Face.text(12.5, .medium))
                .foregroundStyle(color)
                .padding(.horizontal, 10)
                .frame(height: 28)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(Color.white.opacity(hovering && isEnabled ? 0.1 : 0))
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .help(help ?? "")
    }

    private var color: Color {
        if !isEnabled { return Sky.haze.opacity(0.45) }
        if accent { return Sky.starlight }
        return hovering ? Sky.moonlight : Sky.haze
    }
}

/// A round icon button. The label is read by VoiceOver and shown as a tooltip.
struct IconButton: View {
    let systemName: String
    let label: String
    var hoverColor: Color = Sky.moonlight
    var size: CGFloat = 28
    var symbolSize: CGFloat = 13
    let action: () -> Void

    @Stored private var hovering = false

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: symbolSize, weight: .semibold))
                .foregroundStyle(hovering ? hoverColor : Sky.haze)
                .frame(width: size, height: size)
                .background(Circle().fill(Color.white.opacity(hovering ? 0.1 : 0)))
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .help(label)
        .accessibilityLabel(label)
    }
}

/// Centered words for an empty screen: what's going on, and what to do next.
struct SkyMessage: View {
    let title: String
    let detail: String

    var body: some View {
        VStack(spacing: 6) {
            ShootingStarMark(size: 60)
                .padding(.bottom, 6)
            Text(title)
                .font(Face.display(22))
                .foregroundStyle(Sky.moonlight)
            Text(detail)
                .font(Face.text(13))
                .foregroundStyle(Sky.haze)
                .multilineTextAlignment(.center)
                .lineSpacing(3)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 36)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityElement(children: .combine)
    }
}

/// Feedback after archiving, or an explanation when something went wrong.
struct BannerView: View {
    let banner: AppModel.Banner
    @ObservedObject var model: AppModel

    var body: some View {
        HStack(alignment: .center, spacing: 4) {
            switch banner {
            case let .archived(count, fileURL):
                StarShape()
                    .fill(Sky.starlight)
                    .frame(width: 13, height: 13)
                    .padding(.trailing, 4)
                    .accessibilityHidden(true)
                Text(count == 1 ? "Saved 1 task to History" : "Saved \(count) tasks to History")
                    .font(Face.text(12.5, .medium))
                    .foregroundStyle(Sky.moonlight)
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
                Spacer(minLength: 2)
                GhostButton(title: "Show file", help: "Show the Markdown file in Finder") {
                    model.revealFile(fileURL)
                }
                GhostButton(title: "Undo", accent: true, help: "Put the tasks back and remove the file") {
                    Task { await model.undoArchive() }
                }

            case let .failure(message, offersFolderChoice):
                Text(message)
                    .font(Face.text(12.5))
                    .foregroundStyle(Sky.ember)
                    .lineSpacing(2)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.vertical, 8)
                Spacer(minLength: 2)
                if offersFolderChoice {
                    GhostButton(title: "Choose folder", accent: true) {
                        model.onChooseArchiveFolder()
                    }
                } else {
                    IconButton(systemName: "xmark", label: "Dismiss", size: 24, symbolSize: 9) {
                        model.dismissBanner()
                    }
                }
            }
        }
        .padding(.leading, 12)
        .padding(.trailing, 4)
        .frame(minHeight: 38)
        .background(
            RoundedRectangle(cornerRadius: 11, style: .continuous)
                .fill(Sky.zenith.opacity(0.72))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 11, style: .continuous)
                .strokeBorder(borderColor, lineWidth: 1)
        )
    }

    private var borderColor: Color {
        switch banner {
        case .archived: Sky.starlight.opacity(0.35)
        case .failure: Sky.ember.opacity(0.45)
        }
    }
}
