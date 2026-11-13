import AppKit
import Combine
import Foundation

/// Everything the panel shows and does. The AppKit shell owns one of these and
/// fills in the hooks for things only it can do (closing the panel, menus).
@MainActor
public final class AppModel: ObservableObject {
    public enum Screen: Equatable {
        case list
        case history
    }

    public enum Banner: Equatable {
        case archived(count: Int, fileURL: URL)
        case failure(message: String, offersFolderChoice: Bool)
    }

    public let store: TaskStore
    public let archive: ArchiveStore
    private let settings: SettingsStore

    @Published public var screen: Screen = .list
    @Published public var today = Date()
    @Published public var draft = ""
    @Published public var editingID: UUID?
    @Published public var expandedArchive: URL?
    @Published public private(set) var banner: Banner?
    @Published public private(set) var isArchiving = false
    /// Bumped whenever the "Add a task" field should take the keyboard.
    @Published public private(set) var composerFocusRequest = 0
    @Published public var keepsUnfinished: Bool {
        didSet {
            let value = keepsUnfinished
            settings.update { $0.keepsUnfinishedOnArchive = value }
        }
    }

    public var isFirstLaunch: Bool { settings.isFirstLaunch }

    // Hooks for the app shell.
    public var onRequestClose: () -> Void = {}
    public var onShowSettingsMenu: () -> Void = {}
    public var onChooseArchiveFolder: () -> Void = {}

    /// How long the "Saved to History" banner stays up.
    public var bannerDuration: Duration = .seconds(9)

    private var lastArchive: (fileURL: URL, snapshot: [TodoItem])?
    private var bannerTask: Task<Void, Never>?
    private var cancellables: Set<AnyCancellable> = []

    public init(paths: AppPaths = .standard) {
        let settings = SettingsStore(
            fileURL: paths.dataDirectory.appendingPathComponent("settings.json")
        )
        self.settings = settings
        store = TaskStore(fileURL: paths.dataDirectory.appendingPathComponent("tasks.json"))
        let folder = settings.value.archiveFolderPath
            .map { URL(fileURLWithPath: $0, isDirectory: true) } ?? paths.defaultArchiveFolder
        archive = ArchiveStore(folderURL: folder)
        keepsUnfinished = settings.value.keepsUnfinishedOnArchive

        // Views observe this one object; pass along changes from the two stores.
        store.objectWillChange
            .sink { [weak self] _ in self?.objectWillChange.send() }
            .store(in: &cancellables)
        archive.objectWillChange
            .sink { [weak self] _ in self?.objectWillChange.send() }
            .store(in: &cancellables)
    }

    // MARK: Panel lifecycle

    public func panelWillAppear(showing screen: Screen = .list) {
        today = Date()
        editingID = nil
        self.screen = screen
        if screen == .list { focusComposer() }
    }

    public func focusComposer() {
        composerFocusRequest += 1
    }

    // MARK: Tasks

    public func addDraft() {
        guard store.add(draft) != nil else { return }
        draft = ""
    }

    public func beginEditing(_ id: UUID) {
        editingID = id
    }

    public func finishEditing(_ id: UUID, title: String) {
        store.rename(id, to: title)
        if editingID == id { editingID = nil }
        focusComposer()
    }

    public func cancelEditing() {
        editingID = nil
        focusComposer()
    }

    // MARK: Archive

    /// Saves the whole list as a Markdown file, then clears what was archived.
    /// Unfinished tasks stay on the list when `keepsUnfinished` is on.
    public func archiveList() async {
        let snapshot = store.items
        guard !snapshot.isEmpty, !isArchiving else { return }
        isArchiving = true
        defer { isArchiving = false }

        do {
            let url = try await archive.save(items: snapshot, keepsUnfinished: keepsUnfinished)
            // Decide from the snapshot, and keep anything added while the file was saving.
            let archived = Dictionary(uniqueKeysWithValues: snapshot.map { ($0.id, $0) })
            let remaining = store.items.filter { item in
                guard let saved = archived[item.id] else { return true }
                return keepsUnfinished && !saved.isDone
            }
            store.replaceAll(remaining)
            lastArchive = (url, snapshot)
            show(.archived(count: snapshot.count, fileURL: url))
        } catch {
            lastArchive = nil
            show(.failure(
                message: "Couldn't save to \(archive.folderDisplayPath). Your list is unchanged.",
                offersFolderChoice: true
            ))
        }
    }

    /// Puts the archived tasks back and removes the file that was just written.
    public func undoArchive() async {
        guard let last = lastArchive else { return }
        lastArchive = nil
        dismissBanner()
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

    public func setArchiveFolder(_ url: URL) {
        settings.update { $0.archiveFolderPath = url.path }
        archive.setFolder(url)
        expandedArchive = nil
        Task { await archive.refresh() }
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

    public func showFailure(_ message: String) {
        show(.failure(message: message, offersFolderChoice: false))
    }

    public func dismissBanner() {
        bannerTask?.cancel()
        banner = nil
    }

    private func show(_ newBanner: Banner) {
        bannerTask?.cancel()
        banner = newBanner
        let duration = bannerDuration
        bannerTask = Task { [weak self] in
            try? await Task.sleep(for: duration)
            guard !Task.isCancelled else { return }
            self?.banner = nil
        }
    }
}
