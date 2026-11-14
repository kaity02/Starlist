import SwiftUI

/// Things for another day. They wait here, off today's list, until you
/// move them over.
struct LaterScreen: View {
    @ObservedObject var model: AppModel
    /// A row to draw as if the pointer were over it, for the snapshot tool.
    var highlighted: UUID?

    var body: some View {
        VStack(spacing: 0) {
            header

            Group {
                if model.later.items.isEmpty {
                    SkyMessage(
                        title: "Nothing for later",
                        detail: "Add something you want to get to another day. It stays off today's list."
                    )
                } else {
                    list
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            Composer(
                model: model,
                placeholder: "Add something for later",
                text: $model.laterDraft,
                onAdd: { model.addLaterDraft() }
            )
            .padding(.horizontal, 14)
            .padding(.bottom, 14)
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 1) {
            HStack(alignment: .top) {
                Text("Later")
                    .font(Face.display(33))
                    .foregroundStyle(Sky.moonlight)
                Spacer()
                GhostButton(title: "Back to list") { model.showList() }
                    .padding(.trailing, -10)
                    .padding(.top, 4)
            }
            HStack(alignment: .firstTextBaseline) {
                Text("Kept off today's list")
                    .font(Face.text(13))
                    .foregroundStyle(Sky.haze)
                Spacer()
                if !model.later.items.isEmpty {
                    Text(countText)
                        .font(Face.text(13))
                        .foregroundStyle(Sky.haze)
                        .contentTransition(.numericText())
                        .animation(.easeOut(duration: 0.25), value: countText)
                }
            }
        }
        .padding(.horizontal, PanelMetrics.gutter)
        .padding(.top, 18)
        .padding(.bottom, 8)
    }

    private var countText: String {
        let count = model.later.items.count
        return count == 1 ? "1 task" : "\(count) tasks"
    }

    private var list: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(spacing: 1) {
                    ForEach(model.later.items) { item in
                        LaterRow(item: item, model: model, showsActions: item.id == highlighted)
                            .id(item.id)
                            .transition(.opacity)
                    }
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
                .animation(.easeOut(duration: 0.2), value: model.later.items.map(\.id))
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
            .onChange(of: model.later.items.count) { old, new in
                guard new > old, let last = model.later.items.last else { return }
                withAnimation(.easeOut(duration: 0.2)) {
                    proxy.scrollTo(last.id, anchor: .bottom)
                }
            }
        }
    }
}

/// A task that is waiting. Where today's tasks have a circle to check, it has
/// a faint dot, like the days still to come on the star calendar.
private struct LaterRow: View {
    let item: TodoItem
    @ObservedObject var model: AppModel

    @Stored private var hovering: Bool

    private let fontSize: CGFloat = 14

    init(item: TodoItem, model: AppModel, showsActions: Bool = false) {
        self.item = item
        self.model = model
        _hovering = Stored(initialValue: showsActions)
    }

    private var isEditing: Bool { model.editingID == item.id }
    private var showsActions: Bool { hovering && !isEditing }

    var body: some View {
        HStack(alignment: .top, spacing: 9) {
            Circle()
                .fill(Sky.haze.opacity(hovering ? 0.9 : 0.5))
                .frame(width: 5, height: 5)
                .frame(width: 24, height: 24)
                .padding(.top, -2)
                .accessibilityHidden(true)

            if isEditing {
                TitleEditor(item: item, model: model, fontSize: fontSize)
            } else {
                Text(item.title)
                    .font(Face.text(fontSize))
                    .foregroundStyle(Sky.moonlight.opacity(0.88))
                    .lineLimit(4)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
                    .onTapGesture(count: 2) { model.beginEditing(item.id) }
                    .help("Double-click to edit")
            }

            HStack(spacing: 0) {
                MoveButton(title: "Do today", help: "Move it to today's list") {
                    withAnimation(.easeOut(duration: 0.18)) { model.moveToToday(item.id) }
                }
                IconButton(
                    systemName: "xmark",
                    label: "Delete task",
                    hoverColor: Sky.ember,
                    size: 22,
                    symbolSize: 9
                ) {
                    withAnimation(.easeOut(duration: 0.18)) { model.later.remove(item.id) }
                }
            }
            .padding(.top, -1)
            .opacity(showsActions ? 1 : 0)
            .allowsHitTesting(showsActions)
        }
        .padding(.vertical, 7)
        .padding(.leading, 8)
        .padding(.trailing, 6)
        .background(
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .fill(Color.white.opacity(hovering || isEditing ? 0.06 : 0))
        )
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
        .contextMenu {
            Button("Do today") { model.moveToToday(item.id) }
            Button("Edit") { model.beginEditing(item.id) }
            Divider()
            Button("Delete", role: .destructive) { model.later.remove(item.id) }
        }
    }
}

/// The small text button on a row that sends the task to the other list.
private struct MoveButton: View {
    let title: String
    let help: String
    let action: () -> Void

    @Stored private var hovering = false

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(Face.text(12, .medium))
                .foregroundStyle(Sky.starlight)
                .padding(.horizontal, 7)
                .frame(height: 22)
                .background(
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .fill(Color.white.opacity(hovering ? 0.12 : 0))
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .help(help)
    }
}
