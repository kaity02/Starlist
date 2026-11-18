import Foundation

/// A list of tasks, saved to disk after every change. The app keeps two:
/// today's list and the Later list.
@MainActor
public final class TaskStore: ObservableObject {
    @Published public private(set) var items: [TodoItem] = []
    /// Set when the list could not be written; cleared by the next good save.
    @Published public private(set) var saveError: String?

    public let fileURL: URL

    public init(fileURL: URL) {
        self.fileURL = fileURL
        load()
    }

    public var doneCount: Int { items.filter(\.isDone).count }

    /// True when there is at least one task and none are left unfinished.
    public var isAllDone: Bool { !items.isEmpty && items.allSatisfy(\.isDone) }

    @discardableResult
    public func add(_ rawTitle: String) -> TodoItem? {
        let title = Self.clean(rawTitle)
        guard !title.isEmpty else { return nil }
        let item = TodoItem(title: title)
        items.append(item)
        save()
        return item
    }

    public func toggle(_ id: UUID) {
        guard let index = items.firstIndex(where: { $0.id == id }) else { return }
        items[index].isDone.toggle()
        items[index].completedAt = items[index].isDone ? Date() : nil
        save()
    }

    /// Renames a task. An empty title leaves the task as it was.
    public func rename(_ id: UUID, to rawTitle: String) {
        let title = Self.clean(rawTitle)
        guard !title.isEmpty, let index = items.firstIndex(where: { $0.id == id }) else { return }
        guard items[index].title != title else { return }
        items[index].title = title
        save()
    }

    public func remove(_ id: UUID) {
        guard let index = items.firstIndex(where: { $0.id == id }) else { return }
        items.remove(at: index)
        save()
    }

    /// Takes a task off this list and hands it back, so it can go on another.
    public func take(_ id: UUID) -> TodoItem? {
        guard let index = items.firstIndex(where: { $0.id == id }) else { return nil }
        let item = items.remove(at: index)
        save()
        return item
    }

    /// Adds a task that already exists (moved here from another list) at the end.
    public func insert(_ item: TodoItem) {
        items.append(item)
        save()
    }

    /// Moves a task so that it ends up at `index`, counting from the top.
    public func move(_ id: UUID, to index: Int) {
        guard let from = items.firstIndex(where: { $0.id == id }) else { return }
        let target = min(max(index, 0), items.count - 1)
        guard target != from else { return }
        items.insert(items.remove(at: from), at: target)
        save()
    }

    public func replaceAll(_ newItems: [TodoItem]) {
        items = newItems
        save()
    }

    /// Task titles are a single line with no stray whitespace.
    nonisolated static func clean(_ text: String) -> String {
        text.components(separatedBy: .newlines)
            .joined(separator: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: Disk

    // Dates use the coders' default numeric form, which reloads exactly.
    // (ISO 8601 text would drop fractions of a second.)
    private static var encoder: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }

    private static var decoder: JSONDecoder { JSONDecoder() }

    private func load() {
        let fm = FileManager.default
        guard fm.fileExists(atPath: fileURL.path) else { return }
        do {
            let data = try Data(contentsOf: fileURL)
            items = try Self.decoder.decode([TodoItem].self, from: data)
        } catch {
            // Never overwrite a file we couldn't read: set it aside so it can be recovered.
            let stamp = Int(Date().timeIntervalSince1970)
            let name = fileURL.deletingPathExtension().lastPathComponent
            let aside = fileURL.deletingLastPathComponent()
                .appendingPathComponent("\(name).unreadable-\(stamp).json")
            try? fm.moveItem(at: fileURL, to: aside)
            items = []
        }
    }

    private func save() {
        do {
            try FileManager.default.createDirectory(
                at: fileURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try Self.encoder.encode(items).write(to: fileURL, options: .atomic)
            saveError = nil
        } catch {
            saveError = error.localizedDescription
        }
    }
}
