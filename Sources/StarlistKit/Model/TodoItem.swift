import Foundation

/// One task on the current list.
public struct TodoItem: Identifiable, Codable, Equatable, Sendable {
    public let id: UUID
    public var title: String
    public var isDone: Bool
    public var createdAt: Date
    public var completedAt: Date?

    public init(
        id: UUID = UUID(),
        title: String,
        isDone: Bool = false,
        createdAt: Date = Date(),
        completedAt: Date? = nil
    ) {
        self.id = id
        self.title = title
        self.isDone = isDone
        self.createdAt = createdAt
        self.completedAt = completedAt
    }
}

/// Where the app keeps its files. Swappable so development runs and checks
/// never touch the real list.
public struct AppPaths: Sendable {
    /// Holds `tasks.json` and `settings.json`.
    public var dataDirectory: URL
    /// Where archived lists go until the user picks another folder.
    public var defaultArchiveFolder: URL
    /// The Notion secret is kept in a file in the data directory. Earlier
    /// versions kept it in the login keychain; when this is true, a secret
    /// still there is moved into the file. Contained runs never touch the keychain.
    public var movesSecretFromKeychain: Bool

    public init(dataDirectory: URL, defaultArchiveFolder: URL, movesSecretFromKeychain: Bool) {
        self.dataDirectory = dataDirectory
        self.defaultArchiveFolder = defaultArchiveFolder
        self.movesSecretFromKeychain = movesSecretFromKeychain
    }

    public static var standard: AppPaths {
        let fm = FileManager.default
        let support = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let documents = fm.urls(for: .documentDirectory, in: .userDomainMask)[0]
        return AppPaths(
            dataDirectory: support.appendingPathComponent("Starlist", isDirectory: true),
            defaultArchiveFolder: documents.appendingPathComponent("Starlist", isDirectory: true),
            movesSecretFromKeychain: true
        )
    }

    /// Keeps everything, archives included, inside one directory.
    public static func contained(in directory: URL) -> AppPaths {
        AppPaths(
            dataDirectory: directory,
            defaultArchiveFolder: directory.appendingPathComponent("Archive", isDirectory: true),
            movesSecretFromKeychain: false
        )
    }
}
