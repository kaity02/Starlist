import Foundation

public struct Settings: Codable, Equatable, Sendable {
    /// When archiving, unfinished tasks stay on the list instead of leaving with the rest.
    public var keepsUnfinishedOnArchive = true
    /// Nil means the default archive folder.
    public var archiveFolderPath: String?

    public init() {}

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        keepsUnfinishedOnArchive =
            try container.decodeIfPresent(Bool.self, forKey: .keepsUnfinishedOnArchive) ?? true
        archiveFolderPath = try container.decodeIfPresent(String.self, forKey: .archiveFolderPath)
    }
}

@MainActor
public final class SettingsStore {
    public private(set) var value: Settings
    /// True when no settings file existed yet, which is how the app spots its first launch.
    public let isFirstLaunch: Bool

    private let fileURL: URL

    public init(fileURL: URL) {
        self.fileURL = fileURL
        if let data = try? Data(contentsOf: fileURL),
           let stored = try? JSONDecoder().decode(Settings.self, from: data) {
            value = stored
            isFirstLaunch = false
        } else {
            value = Settings()
            isFirstLaunch = !FileManager.default.fileExists(atPath: fileURL.path)
            save()
        }
    }

    public func update(_ change: (inout Settings) -> Void) {
        var copy = value
        change(&copy)
        guard copy != value else { return }
        value = copy
        save()
    }

    private func save() {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try? FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try? encoder.encode(value).write(to: fileURL, options: .atomic)
    }
}
