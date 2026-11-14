import Foundation
import Security

// MARK: - The integration secret

/// Where the Notion integration secret is kept.
public protocol SecretStore: Sendable {
    func read() -> String?
    func write(_ secret: String) throws
    func delete()
}

public struct SecretStoreError: Error {
    public let status: OSStatus
}

/// The real store: the user's login keychain.
public struct KeychainSecretStore: SecretStore {
    private let service = "com.kaitlyn.Starlist"
    private let account = "notion-integration-secret"

    public init() {}

    private var baseQuery: [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
    }

    public func read() -> String? {
        var query = baseQuery
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    public func write(_ secret: String) throws {
        delete()
        var query = baseQuery
        query[kSecValueData as String] = Data(secret.utf8)
        query[kSecAttrLabel as String] = "Starlist Notion secret"
        let status = SecItemAdd(query as CFDictionary, nil)
        guard status == errSecSuccess else { throw SecretStoreError(status: status) }
    }

    public func delete() {
        SecItemDelete(baseQuery as CFDictionary)
    }
}

/// For `--data-dir` runs and checks, so they never touch the keychain.
public struct FileSecretStore: SecretStore {
    private let fileURL: URL

    public init(fileURL: URL) {
        self.fileURL = fileURL
    }

    public func read() -> String? {
        try? String(contentsOf: fileURL, encoding: .utf8)
    }

    public func write(_ secret: String) throws {
        try FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true
        )
        try Data(secret.utf8).write(to: fileURL, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: fileURL.path)
    }

    public func delete() {
        try? FileManager.default.removeItem(at: fileURL)
    }
}

// MARK: - Talking to Notion

/// The network, as far as the Notion client is concerned. Swapped for a fake in checks.
public protocol NotionTransport: Sendable {
    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse)
}

public struct URLSessionTransport: NotionTransport {
    private static let session: URLSession = {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 20
        configuration.waitsForConnectivity = false
        return URLSession(configuration: configuration)
    }()

    public init() {}

    public func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let (data, response) = try await Self.session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw URLError(.badServerResponse) }
        return (data, http)
    }
}

public enum NotionError: Error, Equatable, Sendable {
    case badLink
    case missingSecret
    case unauthorized
    case notShared
    case cannotInsert
    case unreachable
    case rejected(String)

    /// What to tell the person, and what to do about it.
    public var message: String {
        switch self {
        case .badLink:
            "That doesn't look like a Notion page link. In Notion, open the page's menu and choose Copy link."
        case .missingSecret:
            "Starlist needs your integration secret. Paste it to connect."
        case .unauthorized:
            "Notion didn't accept that secret. Copy it again from your integration's page."
        case .notShared:
            "Notion can't find that page for this integration. On the page, open the menu, choose Connections, and add your integration."
        case .cannotInsert:
            "The integration isn't allowed to add content. Turn on Insert content in its capabilities."
        case .unreachable:
            "Couldn't reach Notion. Starlist will try again."
        case let .rejected(reason):
            "Notion turned the request down: \(reason)"
        }
    }

    /// True when waiting and retrying may be all that's needed.
    public var isTemporary: Bool { self == .unreachable }
}

/// The few kinds of block Starlist writes.
public enum NotionBlock: Equatable, Sendable {
    case heading2(String)
    case heading3(String)
    case paragraph(String)
    case todo(String, checked: Bool)

    var json: [String: Any] {
        func richText(_ text: String) -> [[String: Any]] {
            // Notion caps a single text run at 2,000 characters.
            [["type": "text", "text": ["content": String(text.prefix(2000))]]]
        }
        switch self {
        case let .heading2(text):
            return ["object": "block", "type": "heading_2", "heading_2": ["rich_text": richText(text)]]
        case let .heading3(text):
            return ["object": "block", "type": "heading_3", "heading_3": ["rich_text": richText(text)]]
        case let .paragraph(text):
            return ["object": "block", "type": "paragraph", "paragraph": ["rich_text": richText(text)]]
        case let .todo(text, checked):
            return [
                "object": "block", "type": "to_do",
                "to_do": ["rich_text": richText(text), "checked": checked],
            ]
        }
    }
}

public struct NotionClient: Sendable {
    public static let apiVersion = "2026-03-11"
    private static let base = "https://api.notion.com/v1"
    /// Notion accepts at most this many blocks in one request.
    private static let maxBlocksPerRequest = 100

    private let secret: String
    private let transport: NotionTransport

    public init(secret: String, transport: NotionTransport) {
        self.secret = secret
        self.transport = transport
    }

    /// A page's title and web address. Also the way to check that the secret
    /// works and the page is shared with the integration.
    public func page(_ id: String) async throws -> (title: String, url: String?) {
        let json = try await request("GET", "/pages/\(id)")
        var title = ""
        if let properties = json["properties"] as? [String: Any] {
            for case let property as [String: Any] in properties.values
            where property["type"] as? String == "title" {
                let runs = property["title"] as? [[String: Any]] ?? []
                title = runs.compactMap { $0["plain_text"] as? String }.joined()
            }
        }
        return (title.isEmpty ? "Untitled" : title, json["url"] as? String)
    }

    /// Where a block currently sits, and whether it has been deleted.
    public func block(_ id: String) async throws -> (parentID: String?, isTrashed: Bool) {
        let json = try await request("GET", "/blocks/\(id)")
        let trashed = (json["in_trash"] as? Bool ?? false) || (json["archived"] as? Bool ?? false)
        var parentID: String?
        if let parent = json["parent"] as? [String: Any], let type = parent["type"] as? String {
            parentID = parent[type] as? String
        }
        return (parentID, trashed)
    }

    /// Adds blocks inside `parentID`, after `blockID` if given, otherwise at the end.
    /// Returns the new blocks' IDs in order.
    @discardableResult
    public func append(
        _ blocks: [NotionBlock], to parentID: String, after blockID: String?
    ) async throws -> [String] {
        var created: [String] = []
        var after = blockID
        var index = 0
        while index < blocks.count {
            let chunk = blocks[index..<min(index + Self.maxBlocksPerRequest, blocks.count)]
            index += chunk.count
            var body: [String: Any] = ["children": chunk.map(\.json)]
            if let after {
                body["position"] = ["type": "after_block", "after_block": ["id": after]]
            }
            let json = try await request("PATCH", "/blocks/\(parentID)/children", body: body)
            let ids = (json["results"] as? [[String: Any]] ?? []).compactMap { $0["id"] as? String }
            created += ids
            // The next chunk continues after the last block just added.
            if let last = ids.last { after = last }
        }
        return created
    }

    private func request(
        _ method: String, _ path: String, body: [String: Any]? = nil
    ) async throws -> [String: Any] {
        guard let url = URL(string: Self.base + path) else { throw NotionError.badLink }
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue("Bearer \(secret)", forHTTPHeaderField: "Authorization")
        request.setValue(Self.apiVersion, forHTTPHeaderField: "Notion-Version")
        if let body {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try JSONSerialization.data(withJSONObject: body)
        }

        let data: Data
        let response: HTTPURLResponse
        do {
            (data, response) = try await transport.send(request)
        } catch {
            throw NotionError.unreachable
        }

        let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] ?? [:]
        switch response.statusCode {
        case 200..<300:
            return json
        case 401:
            throw NotionError.unauthorized
        case 403:
            throw NotionError.cannotInsert
        case 404:
            throw NotionError.notShared
        case 429, 500...:
            throw NotionError.unreachable
        default:
            throw NotionError.rejected(json["message"] as? String ?? "status \(response.statusCode)")
        }
    }
}

extension NotionLink {
    /// Pulls the page ID out of a Notion link, or accepts a bare ID.
    /// `https://www.notion.so/team/Work-log-1429989fe8ac4effbc8f57f56486db54?pvs=4`
    public static func pageID(from input: String) -> String? {
        let text = input.trimmingCharacters(in: .whitespacesAndNewlines)
        var candidates: [String] = []
        if let components = URLComponents(string: text), components.host != nil {
            // A page opened as a preview inside a database carries its own ID in `p`.
            if let peek = components.queryItems?.first(where: { $0.name == "p" })?.value {
                candidates.append(peek)
            }
            candidates.append(components.path)
        } else {
            candidates.append(text)
        }
        for candidate in candidates {
            if let id = trailingID(in: candidate) { return id }
        }
        return nil
    }

    /// The 32 hex digits at the end of the text, written as a dashed UUID.
    private static func trailingID(in text: String) -> String? {
        var digits: [Character] = []
        for character in text.reversed() {
            if character == "-" || (character == "/" && digits.isEmpty) { continue }
            guard character.isHexDigit, character.isASCII else { break }
            digits.append(character)
            if digits.count == 32 { break }
        }
        guard digits.count == 32 else { return nil }
        let hex = String(digits.reversed()).lowercased()
        let cuts = [8, 12, 16, 20]
        var dashed = ""
        for (offset, character) in hex.enumerated() {
            if cuts.contains(offset) { dashed.append("-") }
            dashed.append(character)
        }
        return dashed
    }
}

// MARK: - The outbox

/// One archived list waiting to be added to Notion.
public struct NotionEntry: Codable, Equatable, Sendable, Identifiable {
    public struct Item: Codable, Equatable, Sendable {
        public let title: String
        public let isDone: Bool

        public init(title: String, isDone: Bool) {
            self.title = title
            self.isDone = isDone
        }
    }

    public let id: UUID
    public let archivedAt: Date
    /// Not sent before this moment, so Undo never has to reach into Notion.
    public let sendAfter: Date
    public let items: [Item]

    public init(id: UUID, archivedAt: Date, sendAfter: Date, items: [Item]) {
        self.id = id
        self.archivedAt = archivedAt
        self.sendAfter = sendAfter
        self.items = items
    }

    /// A dated heading, a one-line summary, then the tasks as Notion to-dos.
    public func blocks(locale: Locale = .current, timeZone: TimeZone = .current) -> [NotionBlock] {
        var calendar = locale.calendar
        calendar.timeZone = timeZone
        let base = Date.FormatStyle(
            date: .omitted, time: .omitted, locale: locale, calendar: calendar, timeZone: timeZone
        )
        let day = archivedAt.formatted(base.weekday(.wide).month(.wide).day().year())
        let time = archivedAt.formatted(base.hour().minute())
            .replacingOccurrences(of: "\u{202F}", with: " ")
        let done = items.filter(\.isDone)
        let open = items.filter { !$0.isDone }
        let noun = items.count == 1 ? "task" : "tasks"

        var blocks: [NotionBlock] = [
            .heading3(day),
            .paragraph("\(done.count) of \(items.count) \(noun) done. Archived at \(time)."),
        ]
        blocks += done.map { .todo($0.title, checked: true) }
        blocks += open.map { .todo($0.title, checked: false) }
        return blocks
    }
}

/// Keeps a Notion page up to date with archived lists.
///
/// Lists wait in an outbox on disk until they have been added, so nothing is
/// lost if the Mac is offline or the app quits first.
@MainActor
public final class NotionSync: ObservableObject {
    public enum Outcome: Equatable {
        case nothingToSend
        case added(Int)
        case failed(NotionError)
    }

    @Published public private(set) var link: NotionLink?
    @Published public private(set) var pending: [NotionEntry] = []
    @Published public private(set) var isWorking = false
    @Published public private(set) var lastError: NotionError?

    private let settings: SettingsStore
    private let secrets: SecretStore
    private let transport: NotionTransport
    private let outboxURL: URL
    private var cachedSecret: String?

    public init(
        settings: SettingsStore,
        secrets: SecretStore,
        transport: NotionTransport,
        outboxURL: URL
    ) {
        self.settings = settings
        self.secrets = secrets
        self.transport = transport
        self.outboxURL = outboxURL
        link = settings.value.notion
        if let data = try? Data(contentsOf: outboxURL),
           let stored = try? JSONDecoder().decode([NotionEntry].self, from: data) {
            pending = stored
        }
    }

    public var isConnected: Bool { link != nil }

    /// Checks the secret and page with Notion, then remembers both.
    public func connect(secret rawSecret: String, pageLink: String) async throws {
        let secret = rawSecret.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !secret.isEmpty else { throw NotionError.missingSecret }
        guard let pageID = NotionLink.pageID(from: pageLink) else { throw NotionError.badLink }

        isWorking = true
        defer { isWorking = false }
        let page = try await NotionClient(secret: secret, transport: transport).page(pageID)
        do {
            try secrets.write(secret)
        } catch {
            throw NotionError.rejected("the secret couldn't be saved to your keychain.")
        }
        cachedSecret = secret
        lastError = nil
        setLink(NotionLink(pageID: pageID, pageTitle: page.title, pageURL: page.url))
    }

    public func disconnect() {
        secrets.delete()
        cachedSecret = nil
        lastError = nil
        pending = []
        saveOutbox()
        setLink(nil)
    }

    /// Queues an archived list. Returns nil when Notion isn't connected.
    @discardableResult
    public func enqueue(items: [TodoItem], archivedAt: Date, holdFor delay: TimeInterval) -> UUID? {
        guard isConnected else { return nil }
        let entry = NotionEntry(
            id: UUID(),
            archivedAt: archivedAt,
            sendAfter: archivedAt.addingTimeInterval(delay),
            items: items.map { .init(title: $0.title, isDone: $0.isDone) }
        )
        pending.append(entry)
        saveOutbox()
        return entry.id
    }

    /// Drops a queued list (the archive was undone).
    public func cancel(_ id: UUID) {
        pending.removeAll { $0.id == id }
        saveOutbox()
    }

    /// Adds every list that is due, oldest first, so the newest ends up on top.
    @discardableResult
    public func flush(now: Date = Date()) async -> Outcome {
        guard var working = link, !isWorking else { return .nothingToSend }
        let due = pending.filter { $0.sendAfter <= now }
        guard !due.isEmpty else { return .nothingToSend }
        guard let secret = cachedSecret ?? secrets.read() else {
            lastError = .missingSecret
            return .failed(.missingSecret)
        }
        cachedSecret = secret

        isWorking = true
        defer { isWorking = false }
        let client = NotionClient(secret: secret, transport: transport)
        var added = 0
        do {
            for entry in due {
                let spot = try await insertionSpot(for: &working, using: client)
                try await client.append(entry.blocks(), to: spot.parentID, after: spot.anchorID)
                pending.removeAll { $0.id == entry.id }
                saveOutbox()
                working.lastAddedAt = Date()
                keep(working)
                added += 1
            }
            lastError = nil
            return .added(added)
        } catch {
            let failure = error as? NotionError ?? .unreachable
            keep(working)
            lastError = failure
            return .failed(failure)
        }
    }

    /// Finds the "Starlist" heading, wherever it has been moved to, and makes
    /// a new one at the end of the page if it is gone.
    private func insertionSpot(
        for link: inout NotionLink, using client: NotionClient
    ) async throws -> (parentID: String, anchorID: String) {
        if let anchor = link.anchorBlockID {
            do {
                let found = try await client.block(anchor)
                if !found.isTrashed, let parent = found.parentID {
                    return (parent, anchor)
                }
            } catch NotionError.notShared {
                // The heading was deleted. Fall through and make a new one.
            }
        }
        let created = try await client.append([.heading2("Starlist")], to: link.pageID, after: nil)
        guard let anchor = created.first else {
            throw NotionError.rejected("the page didn't accept a new heading.")
        }
        link.anchorBlockID = anchor
        return (link.pageID, anchor)
    }

    /// Saves progress, unless the connection was changed while a request was out.
    private func keep(_ updated: NotionLink) {
        guard link?.pageID == updated.pageID else { return }
        setLink(updated)
    }

    private func setLink(_ newLink: NotionLink?) {
        link = newLink
        settings.update { $0.notion = newLink }
    }

    private func saveOutbox() {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try? FileManager.default.createDirectory(
            at: outboxURL.deletingLastPathComponent(), withIntermediateDirectories: true
        )
        try? encoder.encode(pending).write(to: outboxURL, options: .atomic)
    }
}
