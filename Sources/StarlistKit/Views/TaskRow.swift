import SwiftUI

/// The circle you click to finish a task. Finished, it becomes a star.
struct CheckButton: View {
    let title: String
    let isDone: Bool
    let action: () -> Void

    @Stored private var hovering = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Button(action: action) {
            ZStack {
                Circle()
                    .strokeBorder(hovering ? Sky.starlight : Sky.haze.opacity(0.85), lineWidth: 1.3)
                    .frame(width: 17, height: 17)
                    .scaleEffect(isDone ? 0.4 : 1)
                    .opacity(isDone ? 0 : 1)
                StarShape()
                    .fill(Sky.starlight)
                    .frame(width: 19, height: 19)
                    .shadow(color: Sky.starlight.opacity(0.55), radius: 4)
                    .scaleEffect(isDone ? 1 : 0.2)
                    .rotationEffect(.degrees(isDone ? 0 : -72))
                    .opacity(isDone ? 1 : 0)
            }
            .frame(width: 24, height: 24)
            .contentShape(Rectangle())
            .animation(
                reduceMotion ? nil : .spring(response: 0.34, dampingFraction: 0.58),
                value: isDone
            )
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .accessibilityLabel(title)
        .accessibilityValue(isDone ? "Done" : "Not done")
        .accessibilityHint(isDone ? "Marks the task as not done" : "Marks the task as done")
    }
}

struct TaskRow: View {
    let item: TodoItem
    @ObservedObject var model: AppModel

    @Stored private var hovering: Bool
    @Stored private var strike: Double
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private let fontSize: CGFloat = 14

    /// `showsActions` starts the row in its hovered state, for the snapshot tool.
    init(item: TodoItem, model: AppModel, showsActions: Bool = false) {
        self.item = item
        self.model = model
        _hovering = Stored(initialValue: showsActions)
        _strike = Stored(initialValue: item.isDone ? 1 : 0)
    }

    private var isEditing: Bool { model.editingID == item.id }
    private var showsActions: Bool { hovering && !isEditing }

    var body: some View {
        HStack(alignment: .top, spacing: 9) {
            CheckButton(title: item.title, isDone: item.isDone) {
                model.toggle(item.id)
            }
            .padding(.top, -2)

            if isEditing {
                TitleEditor(item: item, model: model, fontSize: fontSize)
            } else {
                title
            }

            HStack(spacing: 0) {
                // A finished task belongs to today; only open ones can be put off.
                IconButton(
                    systemName: "clock",
                    label: "Do later",
                    hoverColor: Sky.starlight,
                    size: 22,
                    symbolSize: 10.5
                ) {
                    withAnimation(.easeOut(duration: 0.18)) { model.moveToLater(item.id) }
                }
                .opacity(showsActions && !item.isDone ? 1 : 0)
                .allowsHitTesting(showsActions && !item.isDone)

                IconButton(
                    systemName: "xmark",
                    label: "Delete task",
                    hoverColor: Sky.ember,
                    size: 22,
                    symbolSize: 9
                ) {
                    withAnimation(.easeOut(duration: 0.18)) { model.store.remove(item.id) }
                }
                .opacity(showsActions ? 1 : 0)
                .allowsHitTesting(showsActions)
            }
            .padding(.top, -1)
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
            Button("Edit") { model.beginEditing(item.id) }
            Button(item.isDone ? "Mark as not done" : "Mark as done") {
                model.toggle(item.id)
            }
            if !item.isDone {
                Button("Do later") { model.moveToLater(item.id) }
            }
            Divider()
            Button("Delete", role: .destructive) { model.store.remove(item.id) }
        }
        .onChange(of: item.isDone) { _, done in
            let target: Double = done ? 1 : 0
            if reduceMotion {
                strike = target
            } else if done {
                // Quick off the mark, then easing out as the comet burns down.
                withAnimation(.timingCurve(0.3, 0.05, 0.25, 1, duration: 0.62)) { strike = target }
            } else {
                withAnimation(.easeOut(duration: 0.2)) { strike = target }
            }
        }
    }

    private var title: some View {
        Text(item.title)
            .font(Face.text(fontSize))
            .foregroundStyle(Sky.moonlight)
            .textRenderer(StrikeRenderer(progress: strike, fontSize: fontSize, showsHead: item.isDone))
            .lineLimit(4)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
            .onTapGesture(count: 2) { model.beginEditing(item.id) }
            .help("Double-click to edit")
            .accessibilityHidden(true)
    }
}

/// The field a task's title turns into while it is being renamed.
struct TitleEditor: View {
    let item: TodoItem
    @ObservedObject var model: AppModel
    var fontSize: CGFloat = 14

    @Stored private var text = ""
    @FocusState private var focused: Bool

    var body: some View {
        TextField("", text: $text)
            .textFieldStyle(.plain)
            .font(Face.text(fontSize))
            .foregroundStyle(Sky.moonlight)
            .tint(Sky.starlight)
            .focused($focused)
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityLabel("Edit task")
            .onSubmit { model.finishEditing(item.id, title: text) }
            .onAppear {
                text = item.title
                DispatchQueue.main.async { focused = true }
            }
            .onChange(of: focused) { wasFocused, isFocused in
                // Clicking away keeps what was typed.
                if wasFocused && !isFocused && model.editingID == item.id {
                    model.finishEditing(item.id, title: text)
                }
            }
    }
}
