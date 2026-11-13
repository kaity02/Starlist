import SwiftUI

/// Every archived list, newest first, read straight from the Markdown files.
struct HistoryScreen: View {
    @ObservedObject var model: AppModel

    var body: some View {
        VStack(spacing: 0) {
            header

            Group {
                if model.archive.lists.isEmpty {
                    if model.archive.hasLoaded {
                        SkyMessage(
                            title: "No archived lists yet",
                            detail: "Choose Archive list and your tasks are saved here as a Markdown file."
                        )
                    } else {
                        Color.clear
                    }
                } else {
                    archiveList
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            HStack {
                GhostButton(title: "Show folder", help: "Open the archive folder in Finder") {
                    model.revealArchiveFolder()
                }
                Spacer()
                GhostButton(title: "Change folder…", help: "Save archives somewhere else") {
                    model.onChooseArchiveFolder()
                }
            }
            .padding(.horizontal, 12)
            .padding(.top, 6)
            .padding(.bottom, 10)
        }
        .task { await model.archive.refresh() }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 1) {
            HStack(alignment: .top) {
                Text("History")
                    .font(Face.display(33))
                    .foregroundStyle(Sky.moonlight)
                Spacer()
                GhostButton(title: "Back to list") { model.showList() }
                    .padding(.trailing, -10)
                    .padding(.top, 4)
            }
            Text("Markdown files in \(model.archive.folderDisplayPath)")
                .font(Face.text(13))
                .foregroundStyle(Sky.haze)
                .lineLimit(1)
                .truncationMode(.middle)
                .help(model.archive.folderURL.path)
        }
        .padding(.horizontal, PanelMetrics.gutter)
        .padding(.top, 18)
        .padding(.bottom, 8)
    }

    private var archiveList: some View {
        ScrollView {
            VStack(spacing: 1) {
                ForEach(model.archive.lists) { list in
                    ArchiveRow(
                        list: list,
                        isExpanded: model.expandedArchive == list.id,
                        model: model
                    )
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
        }
        .mask(
            VStack(spacing: 0) {
                LinearGradient(colors: [.clear, .black], startPoint: .top, endPoint: .bottom)
                    .frame(height: 8)
                Rectangle()
                LinearGradient(colors: [.black, .clear], startPoint: .top, endPoint: .bottom)
                    .frame(height: 8)
            }
        )
    }
}

private struct ArchiveRow: View {
    let list: ArchivedList
    let isExpanded: Bool
    @ObservedObject var model: AppModel

    @Stored private var hovering = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button {
                withAnimation(.easeOut(duration: 0.2)) {
                    model.expandedArchive = isExpanded ? nil : list.id
                }
            } label: {
                HStack(alignment: .center, spacing: 8) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(title)
                            .font(Face.text(14, .medium))
                            .foregroundStyle(Sky.moonlight)
                            .lineLimit(1)
                        Text(summary)
                            .font(Face.text(12))
                            .foregroundStyle(Sky.haze)
                            .lineLimit(1)
                    }
                    Spacer(minLength: 4)
                    Image(systemName: "chevron.right")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(Sky.haze)
                        .rotationEffect(.degrees(isExpanded ? 90 : 0))
                        .accessibilityHidden(true)
                }
                .padding(.vertical, 8)
                .padding(.horizontal, 12)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityHint(isExpanded ? "Hides the tasks" : "Shows the tasks")

            if isExpanded {
                VStack(alignment: .leading, spacing: 7) {
                    ForEach(list.items) { item in
                        HStack(alignment: .top, spacing: 9) {
                            marker(done: item.isDone)
                                .frame(width: 12, height: 17)
                            Text(item.title)
                                .font(Face.text(13))
                                .foregroundStyle(item.isDone ? Sky.moonlight.opacity(0.9) : Sky.haze)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel("\(item.title), \(item.isDone ? "done" : "not done")")
                    }
                    HStack(spacing: 2) {
                        GhostButton(title: "Open file", accent: true) { model.openFile(list.fileURL) }
                        GhostButton(title: "Show in Finder") { model.revealFile(list.fileURL) }
                    }
                    .padding(.leading, -10)
                    .padding(.top, 1)
                }
                .padding(.leading, 12)
                .padding(.trailing, 12)
                .padding(.bottom, 6)
                .transition(.opacity)
            }
        }
        .background(
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .fill(Color.white.opacity(isExpanded ? 0.07 : (hovering ? 0.06 : 0)))
        )
        .onHover { hovering = $0 }
    }

    @ViewBuilder
    private func marker(done: Bool) -> some View {
        if done {
            StarShape().fill(Sky.starlight).frame(width: 11, height: 11)
        } else {
            Circle().strokeBorder(Sky.haze.opacity(0.8), lineWidth: 1.1).frame(width: 9, height: 9)
        }
    }

    private var title: String {
        guard let day = list.day ?? list.savedAt else {
            return list.fileURL.deletingPathExtension().lastPathComponent
        }
        let sameYear = Calendar.current.isDate(day, equalTo: Date(), toGranularity: .year)
        return sameYear
            ? day.formatted(.dateTime.weekday(.wide).month(.wide).day())
            : day.formatted(.dateTime.weekday(.abbreviated).month(.wide).day().year())
    }

    private var summary: String {
        let total = list.items.count
        let done = list.doneCount
        let count = done == total ? "All \(total) done" : "\(done) of \(total) done"
        guard let saved = list.savedAt else { return count }
        return "\(count), saved at \(saved.formatted(.dateTime.hour().minute()))"
    }
}
