import AppKit
import Combine
import Foundation

/// Everything the panel shows and does. The AppKit shell owns one of these and
/// fills in the hooks for things only it can do (closing the panel, menus).
@MainActor
public final class AppModel: ObservableObject {
    public enum Screen: Equatable {
        case list
        case later
        case history
        case notion
    }

    public enum BannerAction: Equatable {
        case chooseFolder
        case notionSettings
    }

    public enum Banner: Equatable {
        case archived(count: Int, fileURL: URL)
        case notice(String)
        case failure(message: String, action: BannerAction?)
    }

    public let store: TaskStore
    /// Things for another day. They are not part of today's list: no star,
    /// no red dot, and Archive leaves them alone.
    public let later: TaskStore
    public let archive: ArchiveStore
    public let stars: StarLog
    public let notion: NotionSync
    /// The Pomodoro timer. Its changes are not passed along like the other
    /// parts': it ticks every second, so only the views that show it watch it.
    public let focus = FocusTimer()
    private let settings: SettingsStore

    @Published public var screen: Screen = .list
    @Published public var today = Date()
    @Published public var draft = ""
    @Published public var laterDraft = ""
    @Published public var editingID: UUID?
    @Published public var expandedArchive: URL?
    @Published public private(set) var banner: Banner?
    @Published public private(set) var isArchiving = false
    /// Bumped whenever the "Add a task" field should take the keyboard.
    @Published public private(set) var composerFocusRequest = 0
    /// Bumped each time the last unfinished task is checked off.
    @Published public private(set) var celebration = 0
    /// What has been typed into the Notion setup form. Kept here, not in the
    /// view, so it survives the panel closing while you fetch the other half
    /// from Notion. Never written to disk.
    @Published public var notionSecretDraft = ""
    @Published public var notionLinkDraft = ""

    /// How long after the panel closes it still reopens on Notion setup,
    /// when nothing has been typed there yet.
    public var setupResumeWindow: TimeInterval = 30 * 60

    public var isFirstLaunch: Bool { settings.isFirstLaunch }

    // Hooks for the app shell.
    public var onRequestClose: () -> Void = {}
    public var onShowSettingsMenu: () -> Void = {}
    public var onChooseArchiveFolder: () -> Void = {}

    /// How long the "Saved to History" banner, and with it Undo, stays up.
    public var bannerDuration: Duration = .seconds(9)

    private var lastArchive: (fileURL: URL, snapshot: [TodoItem], notionEntry: UUID?)?
    private var bannerTask: Task<Void, Never>?
    private var panelClosedAt: Date?
    private var cancellables: Set<AnyCancellable> = []

    public init(paths: AppPaths = .standard, transport: NotionTransport = URLSessionTransport()) {
        let data = paths.dataDirectory
        let settings = SettingsStore(fileURL: data.appendingPathComponent("settings.json"))
        self.settings = settings
        store = TaskStore(fileURL: data.appendingPathComponent("tasks.json"))
        later = TaskStore(fileURL: data.appendingPathComponent("later.json"))
        stars = StarLog(fileURL: data.appendingPathComponent("stars.json"))
        let folder = settings.value.archiveFolderPath
            .map { URL(fileURLWithPath: $0, isDirectory: true) } ?? paths.defaultArchiveFolder
        archive = ArchiveStore(folderURL: folder)
        let secrets: SecretStore = paths.keepsSecretInKeychain
            ? KeychainSecretStore()
            : FileSecretStore(fileURL: data.appendingPathComponent("notion-secret"))
        notion = NotionSync(
            settings: settings,
            secrets: secrets,
            transport: transport,
            outboxURL: data.appendingPathComponent("notion-outbox.json")
        )

        // Views observe this one object; pass along changes from the parts.
        let parts: [ObservableObjectPublisher] = [
            store.objectWillChange, later.objectWillChange, archive.objectWillChange,
            stars.objectWillChange, notion.objectWillChange,
        ]
        for part in parts {
            part.sink { [weak self] _ in self?.objectWillChange.send() }
                .store(in: &cancellables)
        }
    }

    // MARK: Panel lifecycle

    /// `requested` is the screen a menu item asked for. Without one the panel
    /// opens on the list, unless Notion setup was left half done.
    public func panelWillAppear(showing requested: Screen? = nil) {
        today = Date()
        editingID = nil
        screen = requested ?? (resumesNotionSetup ? .notion : .list)
        if screen == .list || screen == .later { focusComposer() }
        // Anything still waiting for Notion (offline earlier, app quit) goes now.
        Task { await sendToNotion(announcing: false) }
    }

    public func panelDidClose() {
        panelClosedAt = Date()
    }

    /// Setting up Notion means leaving the panel to copy a secret and a link,
    /// and every trip closes it. Come back to the form, not the list.
    private var resumesNotionSetup: Bool {
        guard screen == .notion, !notion.isConnected else { return false }
        if !notionSecretDraft.isEmpty || !notionLinkDraft.isEmpty { return true }
        guard let panelClosedAt else { return false }
        return Date().timeIntervalSince(panelClosedAt) < setupResumeWindow
    }

    public func focusComposer() {
        composerFocusRequest += 1
    }

    // MARK: Tasks

    public func addDraft() {
        guard store.add(draft) != nil else { return }
        draft = ""
    }

    /// Checks or un-checks a task. Finishing the last one earns the day's star.
    public func toggle(_ id: UUID) {
        let wasClear = store.isAllDone
        store.toggle(id)
        let isClear = store.isAllDone
        if !wasClear && isClear {
            stars.recordClear()
            celebration += 1
        } else if wasClear && !isClear {
            stars.revokeClear()
        }
    }

    public func beginEditing(_ id: UUID) {
        editingID = id
    }

    public func finishEditing(_ id: UUID, title: String) {
        // The task is on one list or the other; renaming is a no-op on the wrong one.
        store.rename(id, to: title)
        later.rename(id, to: title)
        if editingID == id { editingID = nil }
        focusComposer()
    }

    public func cancelEditing() {
        editingID = nil
        focusComposer()
    }

    // MARK: Later

    public func showLater() {
        editingID = nil
        screen = .later
        focusComposer()
    }

    public func addLaterDraft() {
        guard later.add(laterDraft) != nil else { return }
        laterDraft = ""
    }

    /// Sends what is typed in today's field straight to the Later list.
    public func addDraftToLater() {
        guard later.add(draft) != nil else { return }
        draft = ""
    }

    /// Puts an unfinished task off. Like deleting, this never earns the day's star.
    public func moveToLater(_ id: UUID) {
        guard let item = store.items.first(where: { $0.id == id }), !item.isDone,
              let taken = store.take(id) else { return }
        if editingID == id { editingID = nil }
        later.insert(taken)
    }

    public func moveToToday(_ id: UUID) {
        guard let taken = later.take(id) else { return }
        if editingID == id { editingID = nil }
        store.insert(taken)
    }

    // MARK: Archive

    /// Saves the whole list as a Markdown file and leaves the list empty.
    /// If Notion is connected, the list is added there once Undo has expired.
    public func archiveList() async {
        let snapshot = store.items
        guard !snapshot.isEmpty, !isArchiving else { return }
        isArchiving = true
        defer { isArchiving = false }

        let now = Date()
        do {
            let url = try await archive.save(items: snapshot, at: now)
            // Keep anything that was added while the file was saving.
            let archived = Set(snapshot.map(\.id))
            store.replaceAll(store.items.filter { !archived.contains($0.id) })

            let hold = bannerDuration.seconds + 0.5
            let entry = notion.enqueue(items: snapshot, archivedAt: now, holdFor: hold)
            lastArchive = (url, snapshot, entry)
            show(.archived(count: snapshot.count, fileURL: url))
            if entry != nil {
                Task { [weak self] in
                    try? await Task.sleep(for: .seconds(hold + 0.1))
                    await self?.sendToNotion(announcing: true)
                }
            }
        } catch {
            lastArchive = nil
            showFailure(
                "Couldn't save to \(archive.folderDisplayPath). Your list is unchanged.",
                action: .chooseFolder
            )
        }
    }

    /// Puts the archived tasks back, removes the file that was just written,
    /// and takes the list out of the queue for Notion.
    public func undoArchive() async {
        guard let last = lastArchive else { return }
        lastArchive = nil
        dismissBanner()
        if let entry = last.notionEntry { notion.cancel(entry) }
        let restored = Set(last.snapshot.map(\.id))
        let addedSince = store.items.filter { !restored.contains($0.id) }
        store.replaceAll(last.snapshot + addedSince)
        await archive.delete(last.fileURL)
    }

    public func showHistory() {
        screen = .history
        Task { await archive.refresh() }
    }

    public func showList() {
        screen = .list
        focusComposer()
    }

    public func showNotion() {
        screen = .notion
    }

    public func setArchiveFolder(_ url: URL) {
        settings.update { $0.archiveFolderPath = url.path }
        archive.setFolder(url)
        expandedArchive = nil
        Task { await archive.refresh() }
    }

    // MARK: Notion

    /// Sends queued lists to Notion. `announcing` shows the result in a banner;
    /// quiet runs leave it to the Notion screen.
    public func sendToNotion(announcing: Bool) async {
        let outcome = await notion.flush()
        guard announcing else { return }
        // Never push an Undo banner off the screen.
        if case .archived = banner { return }
        switch outcome {
        case .nothingToSend:
            break
        case .added:
            show(.notice("Added to your Notion page"), for: .seconds(4))
        case let .failed(error):
            showFailure(error.message, action: error.isTemporary ? nil : .notionSettings)
        }
    }

    public func openNotionPage() {
        guard let address = notion.link?.pageURL, let url = URL(string: address) else { return }
        NSWorkspace.shared.open(url)
    }

    // MARK: Finder

    public func openFile(_ url: URL) {
        NSWorkspace.shared.open(url)
    }

    public func revealFile(_ url: URL) {
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    public func revealArchiveFolder() {
        let folder = archive.folderURL
        // Before the first archive the folder doesn't exist yet; show where it will be.
        if !NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: folder.path) {
            NSWorkspace.shared.selectFile(
                nil, inFileViewerRootedAtPath: folder.deletingLastPathComponent().path
            )
        }
    }

    // MARK: Banner

    /// Problems stay up longer than confirmations: there is more to read.
    public func showFailure(_ message: String, action: BannerAction? = nil) {
        show(.failure(message: message, action: action), for: .seconds(14))
    }

    public func dismissBanner() {
        bannerTask?.cancel()
        banner = nil
    }

    private func show(_ newBanner: Banner, for duration: Duration? = nil) {
        bannerTask?.cancel()
        banner = newBanner
        let duration = duration ?? bannerDuration
        bannerTask = Task { [weak self] in
            try? await Task.sleep(for: duration)
            guard !Task.isCancelled else { return }
            self?.banner = nil
        }
    }
}

private extension Duration {
    var seconds: TimeInterval {
        TimeInterval(components.seconds) + TimeInterval(components.attoseconds) / 1e18
    }
}
