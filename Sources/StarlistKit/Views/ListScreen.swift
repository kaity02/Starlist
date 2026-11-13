import SwiftUI

/// The main screen: today's date, the tasks, the field for a new one.
struct ListScreen: View {
    @ObservedObject var model: AppModel

    var body: some View {
        VStack(spacing: 0) {
            ListHeader(model: model)

            Group {
                if model.store.items.isEmpty {
                    SkyMessage(
                        title: "Nothing on the list",
                        detail: "Type a task below and press Return."
                    )
                } else {
                    TaskList(model: model)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            VStack(spacing: 8) {
                if let banner = model.banner {
                    BannerView(banner: banner, model: model)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
                Composer(model: model)
            }
            .padding(.horizontal, 14)
            .animation(.easeOut(duration: 0.22), value: model.banner)

            HStack {
                GhostButton(
                    title: "Archive list",
                    help: "Save this list to History as a Markdown file"
                ) {
                    Task { await model.archiveList() }
                }
                .disabled(model.store.items.isEmpty || model.isArchiving)
                Spacer()
                GhostButton(title: "History", help: "See the lists you've archived") {
                    model.showHistory()
                }
            }
            .padding(.horizontal, 12)
            .padding(.top, 6)
            .padding(.bottom, 10)
        }
    }
}

private struct ListHeader: View {
    @ObservedObject var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            HStack(alignment: .top) {
                Text(model.today.formatted(.dateTime.weekday(.wide)))
                    .font(Face.display(33))
                    .foregroundStyle(Sky.moonlight)
                Spacer()
                IconButton(systemName: "ellipsis", label: "Settings") {
                    model.onShowSettingsMenu()
                }
                .padding(.trailing, -8)
                .padding(.top, 2)
            }
            HStack(alignment: .firstTextBaseline) {
                Text(model.today.formatted(.dateTime.month(.wide).day()))
                    .font(Face.text(13))
                    .foregroundStyle(Sky.haze)
                Spacer()
                if let progress {
                    Text(progress.text)
                        .font(Face.text(13, progress.complete ? .medium : .regular))
                        .foregroundStyle(progress.complete ? Sky.starlight : Sky.haze)
                        .contentTransition(.numericText())
                        .animation(.easeOut(duration: 0.25), value: progress.text)
                }
            }
        }
        .padding(.horizontal, PanelMetrics.gutter)
        .padding(.top, 18)
        .padding(.bottom, 8)
    }

    private var progress: (text: String, complete: Bool)? {
        let total = model.store.items.count
        guard total > 0 else { return nil }
        let done = model.store.doneCount
        if done == total { return ("All done", true) }
        return ("\(done) of \(total) done", false)
    }
}

private struct TaskList: View {
    @ObservedObject var model: AppModel

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(spacing: 1) {
                    ForEach(model.store.items) { item in
                        TaskRow(item: item, model: model)
                            .id(item.id)
                            .transition(.opacity)
                    }
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
                .animation(.easeOut(duration: 0.2), value: model.store.items.map(\.id))
            }
            // Rows dissolve into the sky at the edges instead of being cut off.
            .mask(
                VStack(spacing: 0) {
                    LinearGradient(colors: [.clear, .black], startPoint: .top, endPoint: .bottom)
                        .frame(height: 8)
                    Rectangle()
                    LinearGradient(colors: [.black, .clear], startPoint: .top, endPoint: .bottom)
                        .frame(height: 8)
                }
            )
            .onChange(of: model.store.items.count) { old, new in
                guard new > old, let last = model.store.items.last else { return }
                withAnimation(.easeOut(duration: 0.2)) {
                    proxy.scrollTo(last.id, anchor: .bottom)
                }
            }
        }
    }
}

/// The "Add a task" field. It takes the keyboard whenever the panel opens.
private struct Composer: View {
    @ObservedObject var model: AppModel
    @FocusState private var focused: Bool

    private var hasText: Bool {
        !model.draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        HStack(spacing: 9) {
            Image(systemName: "plus")
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(focused ? Sky.starlight : Sky.haze)
                .accessibilityHidden(true)

            ZStack(alignment: .leading) {
                if model.draft.isEmpty {
                    Text("Add a task")
                        .font(Face.text(14))
                        .foregroundStyle(Sky.haze.opacity(0.8))
                        .allowsHitTesting(false)
                        .accessibilityHidden(true)
                }
                TextField("", text: $model.draft)
                    .textFieldStyle(.plain)
                    .font(Face.text(14))
                    .foregroundStyle(Sky.moonlight)
                    .tint(Sky.starlight)
                    .focused($focused)
                    .accessibilityLabel("Add a task")
                    .onSubmit(add)
            }

            if hasText {
                Button("Add", action: add)
                    .buttonStyle(.plain)
                    .font(Face.text(12.5, .demi))
                    .foregroundStyle(Sky.starlight)
                    .transition(.opacity)
            }
        }
        .padding(.horizontal, 12)
        .frame(height: 40)
        .background(
            RoundedRectangle(cornerRadius: 11, style: .continuous)
                .fill(Color.white.opacity(focused ? 0.1 : 0.07))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 11, style: .continuous)
                .strokeBorder(
                    focused ? Sky.starlight.opacity(0.55) : Color.white.opacity(0.13),
                    lineWidth: 1
                )
        )
        .contentShape(Rectangle())
        .onTapGesture { focused = true }
        .animation(.easeOut(duration: 0.15), value: hasText)
        .onAppear { takeFocus() }
        .onChange(of: model.composerFocusRequest) { takeFocus() }
    }

    private func add() {
        model.addDraft()
        takeFocus()
    }

    private func takeFocus() {
        // After the current event, so a field that is still ending its edit doesn't win.
        DispatchQueue.main.async { focused = true }
    }
}
