import Foundation

/// The Notion page that archived lists are added to.
public struct NotionLink: Codable, Equatable, Sendable {
    public var pageID: String
    public var pageTitle: String
    public var pageURL: String?
    /// The "Starlist" heading on the page. New lists are inserted right under it.
    public var anchorBlockID: String?
    public var lastAddedAt: Date?

    public init(
        pageID: String,
        pageTitle: String,
        pageURL: String? = nil,
        anchorBlockID: String? = nil,
        lastAddedAt: Date? = nil
    ) {
        self.pageID = pageID
        self.pageTitle = pageTitle
        self.pageURL = pageURL
        self.anchorBlockID = anchorBlockID
        self.lastAddedAt = lastAddedAt
    }
}

public struct Settings: Codable, Equatable, Sendable {
    /// Nil means the default archive folder.
    public var archiveFolderPath: String?
    /// Nil until Notion is connected. The secret itself lives in the Keychain, not here.
    public var notion: NotionLink?

    public init() {}

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        archiveFolderPath = try container.decodeIfPresent(String.self, forKey: .archiveFolderPath)
        notion = try container.decodeIfPresent(NotionLink.self, forKey: .notion)
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
