import AppKit
import SwiftUI

/// Connects Starlist to one Notion page, and shows how that connection is doing.
struct NotionScreen: View {
    @ObservedObject var model: AppModel

    @Stored private var connectError: String?

    private let integrationsURL = URL(string: "https://www.notion.so/profile/integrations")!

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top) {
                Text("Notion")
                    .font(Face.display(33))
                    .foregroundStyle(Sky.moonlight)
                Spacer()
                GhostButton(title: "Back to list") { model.showList() }
                    .padding(.trailing, -10)
                    .padding(.top, 4)
            }
            .padding(.top, 18)

            if let link = model.notion.link {
                connected(link)
            } else {
                setup
            }
        }
        .padding(.horizontal, PanelMetrics.gutter)
        .padding(.bottom, 12)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    // MARK: Not connected

    private var setup: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Add each list you archive to a page in your Notion workspace.")
                .font(Face.text(13))
                .foregroundStyle(Sky.haze)
                .lineSpacing(3)
                .fixedSize(horizontal: false, vertical: true)

            VStack(alignment: .leading, spacing: 9) {
                step(1, "Create an internal integration in Notion and copy its secret.")
                step(2, "On your page, open the menu at the top right, choose Connections, and add the integration.")
                step(3, "Paste the secret and the page's link here.")
            }
            .padding(.top, 2)

            GhostButton(title: "Open Notion integrations", accent: true) {
                NSWorkspace.shared.open(integrationsURL)
            }
            .padding(.leading, -10)
            .padding(.vertical, -4)

            SkyField(placeholder: "Integration secret", text: $model.notionSecretDraft, isSecret: true)
            SkyField(placeholder: "Page link", text: $model.notionLinkDraft)

            if let connectError {
                Text(connectError)
                    .font(Face.text(12))
                    .foregroundStyle(Sky.ember)
                    .lineSpacing(2)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 0)

            HStack {
                Spacer()
                PrimaryButton(title: model.notion.isWorking ? "Connecting…" : "Connect") {
                    connect()
                }
                .disabled(
                    model.notion.isWorking
                        || model.notionSecretDraft.isEmpty || model.notionLinkDraft.isEmpty
                )
            }
        }
        .padding(.top, 2)
    }

    private func step(_ number: Int, _ text: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 9) {
            Text("\(number)")
                .font(Face.text(12, .demi))
                .foregroundStyle(Sky.starlight)
                .frame(width: 10, alignment: .leading)
            Text(text)
                .font(Face.text(12.5))
                .foregroundStyle(Sky.moonlight.opacity(0.92))
                .lineSpacing(2.5)
                .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .combine)
    }

    private func connect() {
        connectError = nil
        Task {
            do {
                try await model.notion.connect(
                    secret: model.notionSecretDraft, pageLink: model.notionLinkDraft
                )
                model.notionSecretDraft = ""
                model.notionLinkDraft = ""
            } catch let error as NotionError {
                connectError = error.message
            } catch {
                connectError = NotionError.unreachable.message
            }
        }
    }

    // MARK: Connected

    private func connected(_ link: NotionLink) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline, spacing: 7) {
                StarShape()
                    .fill(Sky.starlight)
                    .frame(width: 12, height: 12)
                    .accessibilityHidden(true)
                Text("Connected to \(link.pageTitle)")
                    .font(Face.text(14, .medium))
                    .foregroundStyle(Sky.moonlight)
                    .lineLimit(2)
            }
            .padding(.top, 4)

            Text("Each list you archive is added under a Starlist heading on that page, newest first. Move the heading anywhere and new lists follow it.")
                .font(Face.text(13))
                .foregroundStyle(Sky.haze)
                .lineSpacing(3)
                .fixedSize(horizontal: false, vertical: true)

            VStack(alignment: .leading, spacing: 6) {
                Text(lastAdded(link))
                    .font(Face.text(13))
                    .foregroundStyle(Sky.moonlight.opacity(0.92))

                if !model.notion.pending.isEmpty {
                    HStack(spacing: 2) {
                        Text(waitingText)
                            .font(Face.text(13))
                            .foregroundStyle(Sky.moonlight.opacity(0.92))
                        Spacer()
                        GhostButton(
                            title: model.notion.isWorking ? "Sending…" : "Send now",
                            accent: true
                        ) {
                            Task { await model.sendToNotion(announcing: false) }
                        }
                        .disabled(model.notion.isWorking)
                        .padding(.trailing, -10)
                    }
                }

                if let error = model.notion.lastError {
                    Text(error.message)
                        .font(Face.text(12))
                        .foregroundStyle(Sky.ember)
                        .lineSpacing(2)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(.top, 2)

            Spacer(minLength: 0)

            HStack {
                GhostButton(title: "Open page") { model.openNotionPage() }
                    .disabled(link.pageURL == nil)
                Spacer()
                GhostButton(title: "Disconnect", help: "Forget the secret and stop adding lists") {
                    model.notion.disconnect()
                }
            }
            .padding(.horizontal, -10)
        }
    }

    private func lastAdded(_ link: NotionLink) -> String {
        guard let date = link.lastAddedAt else { return "Nothing added yet." }
        let day = Calendar.current.isDateInToday(date)
            ? "today"
            : date.formatted(.dateTime.month(.wide).day())
        return "Last added \(day) at \(date.formatted(.dateTime.hour().minute()))."
    }

    private var waitingText: String {
        let count = model.notion.pending.count
        return count == 1 ? "1 list waiting to be added." : "\(count) lists waiting to be added."
    }
}
