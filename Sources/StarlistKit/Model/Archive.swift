import Foundation

// MARK: - Values

public struct ArchivedItem: Identifiable, Equatable, Sendable {
    public let id: Int
    public let title: String
    public let isDone: Bool
}

/// One archived list, read back from its Markdown file.
public struct ArchivedList: Identifiable, Equatable, Sendable {
    public var id: URL { fileURL }
    public let fileURL: URL
    /// The day in the file name, e.g. `2026-11-13 To-do list.md`.
    public let day: Date?
    /// When the file was created.
    public let savedAt: Date?
    public let items: [ArchivedItem]

    public var doneCount: Int { items.filter(\.isDone).count }
}

// MARK: - Markdown

/// The archive format: a plain Markdown checklist that reads well in any editor
/// and that the app can parse back for the History screen.
public enum ArchiveMarkdown {
    public static func render(
        items: [TodoItem],
        archivedAt: Date,
        locale: Locale = .current,
        timeZone: TimeZone = .current
    ) -> String {
        var calendar = locale.calendar
        calendar.timeZone = timeZone
        let base = Date.FormatStyle(
            date: .omitted, time: .omitted, locale: locale, calendar: calendar, timeZone: timeZone
        )
        let day = archivedAt.formatted(base.weekday(.wide).month(.wide).day().year())
        // Some locales put a narrow no-break space before AM/PM; keep the file plain.
        let time = archivedAt.formatted(base.hour().minute())
            .replacingOccurrences(of: "\u{202F}", with: " ")

        let done = items.filter(\.isDone)
        let open = items.filter { !$0.isDone }
        let noun = items.count == 1 ? "task" : "tasks"

        var lines = [
            "# To-do list for \(day)",
            "",
            "Archived at \(time). \(done.count) of \(items.count) \(noun) done.",
        ]
        if !done.isEmpty {
            lines += ["", "## Done", ""]
            lines += done.map { "- [x] \(TaskStore.clean($0.title))" }
        }
        if !open.isEmpty {
            lines += ["", "## Not done", ""]
            lines += open.map { "- [ ] \(TaskStore.clean($0.title))" }
        }
        return lines.joined(separator: "\n") + "\n"
    }

    /// Reads every checklist line, whatever heading it sits under.
    public static func parseItems(_ text: String) -> [ArchivedItem] {
        var items: [ArchivedItem] = []
        for rawLine in text.components(separatedBy: .newlines) {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            guard let marker = line.first, marker == "-" || marker == "*" || marker == "+" else {
                continue
            }
            let rest = line.dropFirst().trimmingCharacters(in: .whitespaces)
            let isDone: Bool
            if rest.hasPrefix("[x]") || rest.hasPrefix("[X]") {
                isDone = true
            } else if rest.hasPrefix("[ ]") {
                isDone = false
            } else {
                continue
            }
            let title = rest.dropFirst(3).trimmingCharacters(in: .whitespaces)
            guard !title.isEmpty else { continue }
            items.append(ArchivedItem(id: items.count, title: title, isDone: isDone))
        }
        return items
    }

    /// `2026-11-13 To-do list.md`, then `2026-11-13 To-do list 2.md` and so on.
    public static func fileName(for date: Date, attempt: Int, timeZone: TimeZone = .current) -> String {
        let day = dayFormatter(timeZone: timeZone).string(from: date)
        return attempt <= 1 ? "\(day) To-do list.md" : "\(day) To-do list \(attempt).md"
    }

    public static func day(fromFileName name: String, timeZone: TimeZone = .current) -> Date? {
        guard name.count >= 10 else { return nil }
        return dayFormatter(timeZone: timeZone).date(from: String(name.prefix(10)))
    }

    private static func dayFormatter(timeZone: TimeZone) -> DateFormatter {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = timeZone
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }
}

// MARK: - Files

public enum ArchiveError: LocalizedError {
    case noFreeFileName

    public var errorDescription: String? {
        "There are too many archives for this day in the folder."
    }
}

/// Blocking file work for the archive folder. Called off the main thread, because
/// the folder may sit behind a permission prompt or a slow cloud drive.
public enum ArchiveFiles {
    /// Writes a new Markdown file and never overwrites an existing one.
    public static func save(
        items: [TodoItem],
        archivedAt: Date,
        in folder: URL
    ) throws -> URL {
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let markdown = ArchiveMarkdown.render(items: items, archivedAt: archivedAt)
        let data = Data(markdown.utf8)
        for attempt in 1...999 {
            let url = folder.appendingPathComponent(
                ArchiveMarkdown.fileName(for: archivedAt, attempt: attempt)
            )
            do {
                try data.write(to: url, options: .withoutOverwriting)
                return url
            } catch let error as CocoaError where error.code == .fileWriteFileExists {
                continue
            }
        }
        throw ArchiveError.noFreeFileName
    }

    /// Every Markdown checklist in the folder, newest first.
    public static func list(in folder: URL) -> [ArchivedList] {
        let fm = FileManager.default
        guard let urls = try? fm.contentsOfDirectory(
            at: folder,
            includingPropertiesForKeys: [.creationDateKey],
            options: [.skipsHiddenFiles]
        ) else { return [] }

        var lists: [ArchivedList] = []
        for url in urls where url.pathExtension.lowercased() == "md" {
            guard let text = try? String(contentsOf: url, encoding: .utf8) else { continue }
            let items = ArchiveMarkdown.parseItems(text)
            // Other notes may live in the same folder; only checklists are history.
            guard !items.isEmpty else { continue }
            lists.append(ArchivedList(
                fileURL: url,
                day: ArchiveMarkdown.day(fromFileName: url.lastPathComponent),
                savedAt: try? url.resourceValues(forKeys: [.creationDateKey]).creationDate,
                items: items
            ))
        }
        lists.sort { a, b in
            let aDay = a.day ?? a.savedAt ?? .distantPast
            let bDay = b.day ?? b.savedAt ?? .distantPast
            if aDay != bDay { return aDay > bDay }
            let aSaved = a.savedAt ?? .distantPast
            let bSaved = b.savedAt ?? .distantPast
            if aSaved != bSaved { return aSaved > bSaved }
            return a.fileURL.lastPathComponent
                .localizedStandardCompare(b.fileURL.lastPathComponent) == .orderedDescending
        }
        return lists
    }

    public static func delete(_ url: URL) throws {
        try FileManager.default.removeItem(at: url)
    }
}

// MARK: - Store

/// The History screen's view of the archive folder. The folder is the source of
/// truth: move or delete files in Finder and History follows.
@MainActor
public final class ArchiveStore: ObservableObject {
    @Published public private(set) var lists: [ArchivedList] = []
    @Published public private(set) var folderURL: URL
    @Published public private(set) var hasLoaded = false

    public init(folderURL: URL) {
        self.folderURL = folderURL
    }

    /// The folder as people write it: `~/Documents/Starlist`.
    public var folderDisplayPath: String {
        (folderURL.path as NSString).abbreviatingWithTildeInPath
    }

    public func setFolder(_ url: URL) {
        folderURL = url
        lists = []
        hasLoaded = false
    }

    public func refresh() async {
        let folder = folderURL
        let found = await Task.detached(priority: .userInitiated) {
            ArchiveFiles.list(in: folder)
        }.value
        // The folder may have been changed while the scan ran.
        guard folder == folderURL else { return }
        lists = found
        hasLoaded = true
    }

    public func save(items: [TodoItem], at date: Date = Date()) async throws -> URL {
        let folder = folderURL
        let url = try await Task.detached(priority: .userInitiated) {
            try ArchiveFiles.save(items: items, archivedAt: date, in: folder)
        }.value
        await refresh()
        return url
    }

    public func delete(_ url: URL) async {
        _ = await Task.detached(priority: .userInitiated) {
            try? ArchiveFiles.delete(url)
        }.value
        await refresh()
    }
}
