// starlist-dev: the build-time helper.
//
//   starlist-dev icon <iconset-dir>     Renders the app icon at every size macOS wants.
//   starlist-dev snapshot <out-dir>     Renders the panel in its main states, plus the glyphs.
//   starlist-dev check                  Runs the logic checks (store, Markdown, archive,
//                                       stars, and Notion against a stand-in server).

import AppKit
import StarlistKit
import SwiftUI

struct DevError: Error, CustomStringConvertible {
    let description: String
}

// MARK: - Images

@MainActor
func writePNG(_ image: CGImage, to url: URL) throws {
    let rep = NSBitmapImageRep(cgImage: image)
    guard let data = rep.representation(using: .png, properties: [:]) else {
        throw DevError(description: "Couldn't encode \(url.lastPathComponent)")
    }
    try data.write(to: url)
}

@MainActor
func render<V: View>(_ view: V, scale: CGFloat = 1) throws -> CGImage {
    let renderer = ImageRenderer(content: view)
    renderer.scale = scale
    renderer.isOpaque = false
    guard let image = renderer.cgImage else {
        throw DevError(description: "ImageRenderer produced no image")
    }
    return image
}

@MainActor
func renderIcon(into directory: URL) throws {
    let sizes: [(name: String, pixels: CGFloat)] = [
        ("icon_16x16", 16), ("icon_16x16@2x", 32),
        ("icon_32x32", 32), ("icon_32x32@2x", 64),
        ("icon_128x128", 128), ("icon_128x128@2x", 256),
        ("icon_256x256", 256), ("icon_256x256@2x", 512),
        ("icon_512x512", 512), ("icon_512x512@2x", 1024),
    ]
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    for size in sizes {
        let image = try render(AppIconView(size: size.pixels))
        try writePNG(image, to: directory.appendingPathComponent("\(size.name).png"))
    }
    print("Wrote \(sizes.count) icon sizes to \(directory.path)")
}

/// Hosts a view in an offscreen window so real AppKit-backed controls
/// (text fields, scroll views) are part of the picture.
@MainActor
func snapshot<V: View>(_ view: V, size: CGSize, to url: URL) async throws {
    let host = NSHostingView(rootView: view)
    host.frame = CGRect(origin: .zero, size: size)
    let window = NSWindow(
        contentRect: host.frame, styleMask: [.borderless], backing: .buffered, defer: false
    )
    window.isReleasedWhenClosed = false
    window.backgroundColor = .clear
    window.isOpaque = false
    window.appearance = NSAppearance(named: .darkAqua)
    window.contentView = host
    host.layoutSubtreeIfNeeded()
    try await Task.sleep(for: .milliseconds(450))
    host.layoutSubtreeIfNeeded()

    guard let rep = host.bitmapImageRepForCachingDisplay(in: host.bounds) else {
        throw DevError(description: "No bitmap for \(url.lastPathComponent)")
    }
    host.cacheDisplay(in: host.bounds, to: rep)
    guard let data = rep.representation(using: .png, properties: [:]) else {
        throw DevError(description: "Couldn't encode \(url.lastPathComponent)")
    }
    try data.write(to: url)
    window.close()
    print("Wrote \(url.lastPathComponent)")
}

/// The menu bar glyph on both menu bar colors: large, at true size, and with
/// the red dot that shows while tasks are unfinished.
struct GlyphSheet: View {
    var body: some View {
        HStack(spacing: 0) {
            swatch(background: Color(white: 0.93), ink: .black)
            swatch(background: Color(white: 0.12), ink: .white)
        }
    }

    private func swatch(background: Color, ink: Color) -> some View {
        VStack(spacing: 22) {
            glyph(ink: ink, size: 150, badge: true)
            HStack(spacing: 22) {
                glyph(ink: ink, size: 18, badge: false)
                glyph(ink: ink, size: 18, badge: true)
                glyph(ink: ink, size: 36, badge: true)
            }
        }
        .frame(width: 240, height: 290)
        .background(background)
    }

    /// Same placement as the app: a 5.5-point dot whose center is 10 points
    /// right and 7.2 points up from the middle of an 18-point glyph.
    private func glyph(ink: Color, size: CGFloat, badge: Bool) -> some View {
        Canvas { context, canvasSize in
            let geometry = ShootingStarGeometry(
                in: CGRect(origin: .zero, size: canvasSize), separated: true
            )
            context.fill(geometry.star, with: .color(ink))
            for trail in geometry.trails {
                context.fill(trail.path, with: .color(ink))
            }
        }
        .frame(width: size, height: size)
        .overlay {
            if badge {
                Circle()
                    .fill(Color(nsColor: .systemRed))
                    .frame(width: size * 5.5 / 18, height: size * 5.5 / 18)
                    .offset(x: size * 10 / 18, y: size * -7.2 / 18)
            }
        }
        .padding(size * 0.25)
    }
}

// MARK: - A stand-in for Notion

/// Answers Notion API requests from memory and records what was asked.
final class FakeNotion: NotionTransport, @unchecked Sendable {
    struct Call {
        let method: String
        let path: String
        let headers: [String: String]
        let body: [String: Any]
    }

    private let lock = NSLock()
    private var recorded: [Call] = []
    private var parents: [String: String] = [:]
    private var counter = 0

    var isOffline = false
    var forcedStatus: Int?
    var deletedBlocks: Set<String> = []

    var calls: [Call] { lock.withLock { recorded } }
    var appends: [Call] { calls.filter { $0.method == "PATCH" } }

    func move(_ block: String, into parent: String) {
        lock.withLock { parents[block] = parent }
    }

    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let path = request.url?.path ?? ""
        let body = request.httpBody
            .flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] } ?? [:]
        lock.withLock {
            recorded.append(Call(
                method: request.httpMethod ?? "GET",
                path: path,
                headers: request.allHTTPHeaderFields ?? [:],
                body: body
            ))
        }
        if isOffline { throw URLError(.notConnectedToInternet) }
        if let forcedStatus { return reply(["message": "refused"], status: forcedStatus, for: request) }

        let parts = path.split(separator: "/").map(String.init)   // v1, blocks|pages, id, [children]
        guard parts.count >= 3 else { return reply(["message": "bad path"], status: 400, for: request) }
        let id = parts[2]

        if parts[1] == "pages" {
            return reply([
                "url": "https://www.notion.so/Work-progress-\(id.replacingOccurrences(of: "-", with: ""))",
                "properties": ["Name": ["type": "title", "title": [["plain_text": "Work "], ["plain_text": "progress"]]]],
            ], status: 200, for: request)
        }
        if request.httpMethod == "GET" {
            let parent = lock.withLock { parents[id] }
            guard let parent, !deletedBlocks.contains(id) else {
                return reply(["message": "Could not find block"], status: 404, for: request)
            }
            return reply(
                ["id": id, "in_trash": false, "parent": ["type": "page_id", "page_id": parent]],
                status: 200, for: request
            )
        }
        let children = body["children"] as? [[String: Any]] ?? []
        let ids: [String] = lock.withLock {
            children.map { _ in
                counter += 1
                let new = "block-\(counter)"
                parents[new] = id
                return new
            }
        }
        return reply(["results": ids.map { ["id": $0] }], status: 200, for: request)
    }

    private func reply(_ json: [String: Any], status: Int, for request: URLRequest) -> (Data, HTTPURLResponse) {
        let data = (try? JSONSerialization.data(withJSONObject: json)) ?? Data()
        let response = HTTPURLResponse(
            url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil
        )!
        return (data, response)
    }
}

/// The plain text and checked state of the blocks in an append request.
func describe(_ call: FakeNotion.Call) -> [String] {
    (call.body["children"] as? [[String: Any]] ?? []).map { block in
        let type = block["type"] as? String ?? "?"
        let content = block[type] as? [String: Any] ?? [:]
        let text = (content["rich_text"] as? [[String: Any]] ?? [])
            .compactMap { ($0["text"] as? [String: Any])?["content"] as? String }
            .joined()
        if type == "to_do" {
            return (content["checked"] as? Bool ?? false ? "[x] " : "[ ] ") + text
        }
        return "\(type): \(text)"
    }
}

func afterBlock(_ call: FakeNotion.Call) -> String? {
    guard let position = call.body["position"] as? [String: Any],
          position["type"] as? String == "after_block" else { return nil }
    return (position["after_block"] as? [String: Any])?["id"] as? String
}

// MARK: - Sample data

@MainActor
func scratchDirectory(_ name: String) throws -> URL {
    let url = FileManager.default.temporaryDirectory
        .appendingPathComponent("starlist-dev-\(ProcessInfo.processInfo.processIdentifier)")
        .appendingPathComponent(name)
    try? FileManager.default.removeItem(at: url)
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
}

@MainActor
func sampleModel(
    _ name: String, tasks: [(String, Bool)], transport: NotionTransport = FakeNotion()
) throws -> AppModel {
    let model = AppModel(paths: .contained(in: try scratchDirectory(name)), transport: transport)
    for (title, done) in tasks {
        if let item = model.store.add(title), done {
            model.store.toggle(item.id)
        }
    }
    return model
}

let sampleTasks: [(String, Bool)] = [
    ("Send the invoice to the studio", true),
    ("Book flights for the conference", false),
    ("Water the fig tree", true),
    ("Draft the case study intro and send it to Priya for a first read", false),
    ("Renew passport", false),
    ("Call the dentist", false),
]

let sampleLater = [
    "Renew passport",
    "Look into pottery classes",
    "Back up the photo library to the external drive before it fills up",
    "Plan a weekend in Lisbon",
]

/// Fills a folder with a list to try the app on: `Starlist --data-dir <dir>`.
@MainActor
func writeSampleData(into directory: URL) throws {
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    let model = AppModel(paths: .contained(in: directory), transport: FakeNotion())
    model.store.replaceAll([])
    model.later.replaceAll([])
    for (title, done) in sampleTasks.prefix(4) {
        if let item = model.store.add(title), done { model.store.toggle(item.id) }
    }
    for title in sampleLater { model.later.add(title) }
    print("Wrote sample lists to \(directory.path)")
}

let samplePage = "https://www.notion.so/team/Work-progress-1429989fe8ac4effbc8f57f56486db54?pvs=4"
let samplePageID = "1429989f-e8ac-4eff-bc8f-57f56486db54"

@MainActor
func renderSnapshots(into directory: URL) async throws {
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    let panel = CGSize(width: PanelMetrics.width, height: PanelMetrics.height)
    func out(_ name: String) -> URL { directory.appendingPathComponent(name) }

    let list = try sampleModel("list", tasks: sampleTasks)
    try await snapshot(RootView(model: list), size: panel, to: out("1-list.png"))

    let empty = try sampleModel("empty", tasks: [])
    try await snapshot(RootView(model: empty), size: panel, to: out("2-empty.png"))

    let archived = try sampleModel("archived", tasks: sampleTasks)
    archived.bannerDuration = .seconds(60)
    await archived.archiveList()
    try await snapshot(RootView(model: archived), size: panel, to: out("3-after-archive.png"))

    // A few days of history and a few months of stars to browse.
    let history = try sampleModel("history", tasks: sampleTasks)
    let day: TimeInterval = 86_400
    for (offset, doneCount) in [(3.0, 2), (2.0, 6), (1.0, 3)] {
        let items = sampleTasks.enumerated().map { index, task in
            TodoItem(title: task.0, isDone: index < doneCount)
        }
        _ = try await history.archive.save(items: items, at: Date().addingTimeInterval(-offset * day))
    }
    for offset in [0, 1, 2, 3, 6, 7, 9, 10, 13, 14, 15, 20, 22, 23, 27, 28, 29, 30, 34, 37, 41,
                   42, 43, 48, 50, 55, 56, 57, 62, 64, 69, 70, 71, 77, 83, 84, 90, 97, 104] {
        history.stars.recordClear(on: Date().addingTimeInterval(-Double(offset) * day))
    }
    history.screen = .history
    await history.archive.refresh()
    try await snapshot(RootView(model: history), size: panel, to: out("4-history.png"))

    let noHistory = try sampleModel("no-history", tasks: [])
    noHistory.screen = .history
    await noHistory.archive.refresh()
    try await snapshot(RootView(model: noHistory), size: panel, to: out("5-history-empty.png"))

    try await snapshot(
        StrikeGallery(),
        size: CGSize(width: PanelMetrics.width, height: 320),
        to: out("6-strike.png")
    )

    try writePNG(try render(GlyphSheet(), scale: 2), to: out("7-glyph.png"))
    print("Wrote 7-glyph.png")
    try writePNG(try render(AppIconView(size: 512)), to: out("8-icon.png"))
    print("Wrote 8-icon.png")

    let notionSetup = try sampleModel("notion-setup", tasks: [])
    notionSetup.screen = .notion
    try await snapshot(RootView(model: notionSetup), size: panel, to: out("9-notion-setup.png"))

    let notionOn = try sampleModel("notion-on", tasks: sampleTasks)
    try await notionOn.notion.connect(secret: "secret_example", pageLink: samplePage)
    notionOn.bannerDuration = .milliseconds(20)
    await notionOn.archiveList()
    try await Task.sleep(for: .milliseconds(900))
    notionOn.dismissBanner()
    notionOn.screen = .notion
    try await snapshot(RootView(model: notionOn), size: panel, to: out("10-notion-connected.png"))

    try writePNG(try render(StarBurstFrames(), scale: 1), to: out("11-burst.png"))
    print("Wrote 11-burst.png")

    // The Later list: its button on today's list, the list, and the hover actions.
    let today = try sampleModel("later-today", tasks: Array(sampleTasks.prefix(4)))
    for title in sampleLater { today.later.add(title) }
    today.draft = "Try the new ramen place"
    try await snapshot(
        RootView(model: today, highlighted: today.store.items[1].id),
        size: panel, to: out("12-today-with-later.png")
    )

    let later = try sampleModel("later-list", tasks: Array(sampleTasks.prefix(4)))
    for title in sampleLater { later.later.add(title) }
    later.screen = .later
    try await snapshot(
        RootView(model: later, highlighted: later.later.items[1].id),
        size: panel, to: out("13-later.png")
    )

    let laterEmpty = try sampleModel("later-empty", tasks: [])
    laterEmpty.screen = .later
    try await snapshot(RootView(model: laterEmpty), size: panel, to: out("14-later-empty.png"))
}

// MARK: - Checks

var failures = 0

@MainActor
func expect(_ condition: Bool, _ label: String) {
    if condition {
        print("  ok    \(label)")
    } else {
        failures += 1
        print("  FAIL  \(label)")
    }
}

@MainActor
func runChecks() async throws {
    let fm = FileManager.default

    print("Task store")
    do {
        let dir = try scratchDirectory("check-store")
        let url = dir.appendingPathComponent("tasks.json")
        let store = TaskStore(fileURL: url)
        expect(store.items.isEmpty && !store.isAllDone, "starts empty, and empty is not \"all done\"")
        expect(store.add("   ") == nil, "ignores a blank title")
        let milk = store.add("  Buy oat milk\n")
        expect(milk?.title == "Buy oat milk", "trims the title to one clean line")
        let call = store.add("Call the dentist")!
        store.toggle(call.id)
        expect(store.doneCount == 1, "toggling marks a task done")
        expect(store.items[1].completedAt != nil, "records when it was finished")
        store.rename(milk!.id, to: "Buy oat milk and bread")
        store.rename(milk!.id, to: "  ")
        expect(store.items[0].title == "Buy oat milk and bread", "renames, and ignores an empty rename")

        let reloaded = TaskStore(fileURL: url)
        expect(reloaded.items == store.items, "the list survives a relaunch")
        reloaded.toggle(call.id)
        expect(reloaded.items[1].completedAt == nil, "un-finishing clears the finish time")
        reloaded.remove(milk!.id)
        expect(TaskStore(fileURL: url).items.map(\.title) == ["Call the dentist"], "deleting is saved")

        try Data("not json".utf8).write(to: url)
        let recovered = TaskStore(fileURL: url)
        let setAside = try fm.contentsOfDirectory(atPath: dir.path)
            .contains { $0.hasPrefix("tasks.unreadable-") }
        expect(recovered.items.isEmpty && setAside, "an unreadable file is set aside, not overwritten")
    }

    let zone = TimeZone(identifier: "America/Los_Angeles")!
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = zone
    calendar.locale = Locale(identifier: "en_US")
    var components = DateComponents()
    (components.year, components.month, components.day) = (2026, 11, 13)
    (components.hour, components.minute) = (15, 32)
    let friday = calendar.date(from: components)!
    let english = Locale(identifier: "en_US")

    print("Markdown")
    do {
        let items = [
            TodoItem(title: "Buy oat milk", isDone: true),
            TodoItem(title: "Call the dentist"),
            TodoItem(title: "Email Sam", isDone: true),
        ]
        let text = ArchiveMarkdown.render(
            items: items, archivedAt: friday, locale: english, timeZone: zone
        )
        let expected = """
        # To-do list for Friday, November 13, 2026

        Archived at 3:32 PM. 2 of 3 tasks done.

        ## Done

        - [x] Buy oat milk
        - [x] Email Sam

        ## Not done

        - [ ] Call the dentist

        """
        expect(text == expected, "renders the expected file")
        if text != expected { print(text) }

        let single = ArchiveMarkdown.render(
            items: [TodoItem(title: "Only one")], archivedAt: friday, locale: english, timeZone: zone
        )
        expect(single.contains("0 of 1 task done."), "says \"1 task\", not \"1 tasks\"")
        expect(!single.contains("## Done"), "leaves out an empty Done section")

        let parsed = ArchiveMarkdown.parseItems(text)
        expect(parsed.map(\.title) == ["Buy oat milk", "Email Sam", "Call the dentist"],
               "reads the tasks back")
        expect(parsed.map(\.isDone) == [true, true, false], "reads back what was done")
        expect(ArchiveMarkdown.parseItems("# Notes\n- plain bullet\n* [X] Star bullet\n").count == 1,
               "ignores lines that aren't checklist items")

        expect(ArchiveMarkdown.fileName(for: friday, attempt: 1, timeZone: zone)
               == "2026-11-13 To-do list.md", "names the file by day")
        expect(ArchiveMarkdown.fileName(for: friday, attempt: 3, timeZone: zone)
               == "2026-11-13 To-do list 3.md", "numbers later archives from the same day")
        let day = ArchiveMarkdown.day(fromFileName: "2026-11-13 To-do list 3.md", timeZone: zone)
        expect(day.map { calendar.component(.day, from: $0) } == 13, "reads the day from a file name")
        expect(ArchiveMarkdown.day(fromFileName: "notes.md") == nil, "tolerates other file names")
    }

    print("Archive and undo")
    do {
        let model = try sampleModel("check-archive", tasks: sampleTasks)
        let folder = model.archive.folderURL
        await model.archiveList()
        let files = (try? fm.contentsOfDirectory(atPath: folder.path)) ?? []
        expect(files.count == 1 && files[0].hasSuffix("To-do list.md"), "writes one Markdown file")
        expect(model.store.items.isEmpty, "archiving leaves the list empty, unfinished tasks included")
        if case let .archived(count, _) = model.banner {
            expect(count == 6, "confirms how many tasks were saved")
        } else {
            expect(false, "confirms how many tasks were saved")
        }
        expect(model.archive.lists.first?.items.count == 6 && model.archive.lists.first?.doneCount == 2,
               "History shows all six tasks, two of them done")

        model.store.add("Added after archiving")
        await model.undoArchive()
        expect(model.store.items.count == 7 && model.store.doneCount == 2,
               "undo restores the list and keeps tasks added since")
        expect(((try? fm.contentsOfDirectory(atPath: folder.path)) ?? []).isEmpty,
               "undo removes the file it wrote")
        expect(model.banner == nil && model.archive.lists.isEmpty, "undo clears the banner and History")

        await model.archiveList()
        model.store.add("A new day's task")
        await model.archiveList()
        let names = (try? fm.contentsOfDirectory(atPath: folder.path)) ?? []
        expect(names.count == 2 && names.contains { $0.hasSuffix("To-do list 2.md") },
               "a second archive the same day gets its own file")
        expect(model.archive.lists.count == 2, "History lists both")
        await model.archiveList()
        expect(((try? fm.contentsOfDirectory(atPath: folder.path)) ?? []).count == 2,
               "archiving an empty list writes nothing")

        let relaunched = AppModel(
            paths: .contained(in: folder.deletingLastPathComponent()), transport: FakeNotion()
        )
        expect(relaunched.isFirstLaunch == false, "only the first launch counts as first")
    }

    print("Archive failures")
    do {
        let model = try sampleModel("check-failure", tasks: sampleTasks)
        // A file where the folder should be makes the save fail.
        let blocker = try scratchDirectory("check-failure-blocker").appendingPathComponent("file")
        try Data("x".utf8).write(to: blocker)
        model.setArchiveFolder(blocker)
        await model.archiveList()
        expect(model.store.items.count == 6, "a failed save leaves the list untouched")
        if case .failure = model.banner {
            expect(true, "a failed save is reported")
        } else {
            expect(false, "a failed save is reported")
        }
    }

    print("Stars")
    do {
        let model = try sampleModel("check-stars", tasks: [])
        let a = model.store.add("First")!
        let b = model.store.add("Second")!
        model.toggle(a.id)
        expect(model.stars.total == 0 && model.celebration == 0, "one of two done earns nothing yet")
        model.toggle(b.id)
        expect(model.stars.hasStar(on: Date()) && model.celebration == 1,
               "checking off the last task earns today's star and the celebration")
        model.toggle(b.id)
        expect(model.stars.total == 0, "un-checking it takes the star back")
        model.toggle(b.id)
        expect(model.stars.total == 1 && model.celebration == 2, "finishing again earns it again")

        let c = model.store.add("Third")!
        model.toggle(a.id)
        expect(model.stars.total == 1, "un-checking when the list wasn't clear leaves the star alone")
        model.store.remove(a.id)
        model.store.remove(c.id)
        expect(model.celebration == 2, "deleting unfinished tasks is not a celebration")

        let reloaded = StarLog(fileURL: model.store.fileURL.deletingLastPathComponent()
            .appendingPathComponent("stars.json"))
        expect(reloaded.total == 1, "stars survive a relaunch")

        let log = StarLog(
            fileURL: try scratchDirectory("check-streak").appendingPathComponent("stars.json"),
            calendar: calendar
        )
        func daysAgo(_ n: Int) -> Date { calendar.date(byAdding: .day, value: -n, to: friday)! }
        log.recordClear(on: daysAgo(1))
        log.recordClear(on: daysAgo(2))
        log.recordClear(on: daysAgo(4))
        expect(log.currentStreak(asOf: friday) == 2, "a streak ending yesterday is still alive today")
        log.recordClear(on: friday)
        expect(log.currentStreak(asOf: friday) == 3, "today's star extends it")
        expect(log.currentStreak(asOf: daysAgo(-2)) == 0, "a missed day ends it")
        expect(log.total == 4, "counts starred days")

        let grid = StarCalendar(today: friday, weeks: 18, calendar: calendar)
        let weekdayIndex = (calendar.component(.weekday, from: friday) - calendar.firstWeekday + 7) % 7
        expect(grid.date(week: 17, day: weekdayIndex).map { calendar.isDate($0, inSameDayAs: friday) } == true,
               "the calendar's last column holds today")
        expect(grid.date(week: 17, day: weekdayIndex + 1) == nil, "days that haven't happened are blank")
        expect(grid.date(week: 0, day: 0).map { calendar.dateComponents([.day], from: $0, to: friday).day } == 17 * 7 + weekdayIndex,
               "the first column starts seventeen weeks before this week")
        expect(grid.monthLabels.map(\.text).suffix(3) == ["Sep", "Oct", "Nov"], "months are labeled")
        expect(grid.weekdaySymbol(row: 1) == "Mon" && grid.weekdaySymbol(row: 5) == "Fri",
               "weekdays are labeled")
    }

    print("Later list")
    do {
        let model = try sampleModel("check-later", tasks: [("One", true), ("Two", false)])
        let two = model.store.items[1]
        model.laterDraft = "  Someday  "
        model.addLaterDraft()
        expect(model.later.items.map(\.title) == ["Someday"] && model.laterDraft.isEmpty,
               "a task can be added straight to Later")
        expect(model.store.items.count == 2, "it is not on today's list")
        model.draft = "Park this"
        model.addDraftToLater()
        expect(model.later.items.map(\.title) == ["Someday", "Park this"]
               && model.draft.isEmpty && model.store.items.count == 2,
               "today's field can send a task to Later instead")

        model.moveToLater(model.store.items[0].id)
        expect(model.store.items.count == 2, "a finished task stays on today's list")
        model.moveToLater(two.id)
        expect(model.store.items.map(\.title) == ["One"] && model.later.items.last?.id == two.id,
               "an unfinished task can be put off until later")
        expect(model.stars.total == 0 && model.celebration == 0,
               "putting off the last unfinished task does not earn the star")

        model.moveToToday(two.id)
        expect(model.store.items.last?.id == two.id && !model.later.items.contains { $0.id == two.id },
               "and brought back to today")
        model.toggle(two.id)
        expect(model.stars.total == 1, "finishing it today earns the star")

        model.beginEditing(model.later.items[0].id)
        model.finishEditing(model.later.items[0].id, title: "One day")
        expect(model.later.items[0].title == "One day", "tasks on Later can be renamed")

        await model.archiveList()
        expect(model.store.items.isEmpty && model.later.items.count == 2,
               "Archive leaves the Later list alone")

        let relaunched = AppModel(
            paths: .contained(in: model.store.fileURL.deletingLastPathComponent()),
            transport: FakeNotion()
        )
        expect(relaunched.later.items.map(\.title) == ["One day", "Park this"],
               "the Later list survives a relaunch")
    }

    print("Notion links")
    do {
        expect(NotionLink.pageID(from: samplePage) == samplePageID, "reads the ID from a page link")
        expect(NotionLink.pageID(from: " \(samplePageID) ") == samplePageID, "accepts a bare ID")
        expect(NotionLink.pageID(from:
            "https://www.notion.so/team/Tasks-aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa?p=1429989fe8ac4effbc8f57f56486db54&pm=s")
            == samplePageID, "prefers the previewed page inside a database link")
        expect(NotionLink.pageID(from: "https://www.notion.so/team/Decaf-cafe-1429989fe8ac4effbc8f57f56486db54")
            == samplePageID, "is not confused by hex-looking words in the title")
        expect(NotionLink.pageID(from: "https://example.com/nothing-here") == nil, "rejects other links")
    }

    print("Notion sync")
    do {
        let notionServer = FakeNotion()
        let model = try sampleModel("check-notion", tasks: sampleTasks, transport: notionServer)
        model.bannerDuration = .milliseconds(60)

        await model.archiveList()
        expect(model.notion.pending.isEmpty, "nothing is queued while Notion isn't connected")
        try await Task.sleep(for: .milliseconds(100))

        // Setting up means leaving the panel to copy things from Notion.
        model.panelWillAppear(showing: .notion)
        model.panelDidClose()
        model.panelWillAppear()
        expect(model.screen == .notion, "reopening the panel during Notion setup returns to the form")
        model.notionSecretDraft = "secret_abc"
        model.setupResumeWindow = 0
        model.panelDidClose()
        model.panelWillAppear()
        expect(model.screen == .notion && model.notionSecretDraft == "secret_abc",
               "a pasted secret is still there after the panel closes and reopens")
        model.showList()
        model.panelDidClose()
        model.panelWillAppear()
        expect(model.screen == .list && model.notionSecretDraft == "secret_abc",
               "going back to the list stays on the list, and keeps what was pasted")
        model.notionSecretDraft = ""
        model.panelWillAppear(showing: .notion)
        model.panelDidClose()
        model.panelWillAppear()
        expect(model.screen == .list, "an untouched setup form is not reopened long afterwards")
        model.setupResumeWindow = 30 * 60

        do {
            try await model.notion.connect(secret: "  secret_abc\n", pageLink: "not a link")
            expect(false, "rejects a bad page link")
        } catch {
            expect(error as? NotionError == .badLink, "rejects a bad page link")
        }
        try await model.notion.connect(secret: "  secret_abc\n", pageLink: samplePage)
        expect(model.notion.link?.pageTitle == "Work progress" && model.notion.link?.pageID == samplePageID,
               "connecting reads the page's title")
        model.panelWillAppear(showing: .notion)
        model.panelDidClose()
        model.panelWillAppear()
        expect(model.screen == .list, "once connected, the panel opens on the list again")
        let first = notionServer.calls.last!
        expect(first.headers["Authorization"] == "Bearer secret_abc"
               && first.headers["Notion-Version"] == "2026-03-11",
               "sends the trimmed secret and the API version")

        for (title, done) in sampleTasks.prefix(3) {
            if let item = model.store.add(title), done { model.store.toggle(item.id) }
        }
        await model.archiveList()
        expect(model.notion.pending.count == 1, "an archived list is queued for Notion")
        expect(await model.notion.flush() == .nothingToSend && notionServer.appends.isEmpty,
               "it is held back while Undo is still possible")
        try await Task.sleep(for: .milliseconds(900))
        expect(model.notion.pending.isEmpty, "once Undo expires it is sent")
        expect(model.banner == .notice("Added to your Notion page"), "and the banner says so")

        let appends = notionServer.appends
        expect(appends.count == 2 && appends[0].path == "/v1/blocks/\(samplePageID)/children"
               && describe(appends[0]) == ["heading_2: Starlist"] && afterBlock(appends[0]) == nil,
               "the first time, a Starlist heading is added at the end of the page")
        let anchor = model.notion.link?.anchorBlockID
        expect(anchor == "block-1" && afterBlock(appends[1]) == anchor,
               "the list goes directly under that heading")
        let blocks = describe(appends[1])
        expect(blocks.count == 5 && blocks[0].hasPrefix("heading_3: ")
               && blocks[1].hasPrefix("paragraph: 2 of 3 tasks done. Archived at "),
               "it starts with the date and a summary")
        expect(Array(blocks.suffix(3)) == [
            "[x] Send the invoice to the studio", "[x] Water the fig tree",
            "[ ] Book flights for the conference",
        ], "then the tasks as to-dos, finished ones checked")
        expect(model.notion.link?.lastAddedAt != nil, "remembers when it last added something")

        // Undo before the hold expires.
        model.store.add("Changed my mind")
        await model.archiveList()
        await model.undoArchive()
        try await Task.sleep(for: .milliseconds(900))
        expect(model.notion.pending.isEmpty && notionServer.appends.count == 2,
               "an undone archive never reaches Notion")
        model.store.replaceAll([])

        // Offline, then back.
        notionServer.isOffline = true
        model.store.add("Written on a plane")
        await model.archiveList()
        try await Task.sleep(for: .milliseconds(900))
        expect(model.notion.pending.count == 1 && model.notion.lastError == .unreachable,
               "offline, the list stays queued")
        if case let .failure(message, action) = model.banner {
            expect(message.contains("try again") && action == nil, "and the banner says it will retry")
        } else {
            expect(false, "and the banner says it will retry")
        }
        let relaunched = AppModel(
            paths: .contained(in: model.store.fileURL.deletingLastPathComponent()),
            transport: notionServer
        )
        expect(relaunched.notion.pending.count == 1 && relaunched.notion.link?.anchorBlockID == anchor,
               "the queue and the connection survive a relaunch")
        notionServer.isOffline = false
        await model.sendToNotion(announcing: false)
        expect(model.notion.pending.isEmpty && model.notion.lastError == nil,
               "back online, the next attempt sends it")
        expect(afterBlock(notionServer.appends.last!) == anchor,
               "newer lists are inserted above older ones, under the same heading")

        // The heading was moved into another block.
        notionServer.move("block-1", into: "toggle-9")
        model.store.add("After moving the heading")
        await model.archiveList()
        try await Task.sleep(for: .milliseconds(900))
        expect(notionServer.appends.last!.path == "/v1/blocks/toggle-9/children",
               "if the heading is moved, lists follow it")

        // The heading was deleted.
        notionServer.deletedBlocks.insert("block-1")
        model.store.add("After deleting the heading")
        await model.archiveList()
        try await Task.sleep(for: .milliseconds(900))
        let recent = notionServer.appends.suffix(2)
        expect(describe(recent.first!) == ["heading_2: Starlist"]
               && model.notion.link?.anchorBlockID != anchor
               && afterBlock(recent.last!) == model.notion.link?.anchorBlockID,
               "if the heading is deleted, a new one is made")

        // A secret that stopped working.
        notionServer.forcedStatus = 401
        model.store.add("With a revoked secret")
        await model.archiveList()
        try await Task.sleep(for: .milliseconds(900))
        expect(model.notion.pending.count == 1 && model.notion.lastError == .unauthorized,
               "a rejected secret keeps the list queued")
        if case let .failure(_, action) = model.banner {
            expect(action == .notionSettings, "and the banner offers to fix the connection")
        } else {
            expect(false, "and the banner offers to fix the connection")
        }
        notionServer.forcedStatus = nil
        await model.sendToNotion(announcing: false)

        // More tasks than fit in one request.
        let before = notionServer.appends.count
        for index in 1...150 { model.store.add("Task \(index)") }
        await model.archiveList()
        try await Task.sleep(for: .milliseconds(1100))
        let chunks = Array(notionServer.appends.dropFirst(before))
        expect(chunks.count == 2 && describe(chunks[0]).count == 100 && describe(chunks[1]).count == 52,
               "a long list is split into requests of at most 100 blocks")
        expect(afterBlock(chunks[1]) != nil && afterBlock(chunks[1]) != afterBlock(chunks[0]),
               "and the second part continues after the first")

        model.notion.disconnect()
        expect(!model.notion.isConnected && model.notion.pending.isEmpty, "disconnecting forgets everything")
        let secretFile = model.store.fileURL.deletingLastPathComponent().appendingPathComponent("notion-secret")
        expect(!fm.fileExists(atPath: secretFile.path), "including the secret")
    }

    print("Notion entry")
    do {
        let entry = NotionEntry(
            id: UUID(), archivedAt: friday, sendAfter: friday,
            items: [.init(title: String(repeating: "x", count: 2500), isDone: false)]
        )
        let blocks = entry.blocks(locale: english, timeZone: zone)
        expect(blocks[0] == .heading3("Friday, November 13, 2026"), "is headed by the day")
        expect(blocks[1] == .paragraph("0 of 1 task done. Archived at 3:32 PM."), "summarizes the list")
    }
}

// MARK: - Entry point

// Unbuffered, so output isn't lost if a check crashes.
setvbuf(stdout, nil, _IONBF, 0)
_ = NSApplication.shared
let arguments = Array(CommandLine.arguments.dropFirst())

do {
    switch arguments.first {
    case "icon" where arguments.count == 2:
        try renderIcon(into: URL(fileURLWithPath: arguments[1], isDirectory: true))
    case "snapshot" where arguments.count == 2:
        try await renderSnapshots(into: URL(fileURLWithPath: arguments[1], isDirectory: true))
    case "sample" where arguments.count == 2:
        try writeSampleData(into: URL(fileURLWithPath: arguments[1], isDirectory: true))
    case "check":
        try await runChecks()
        print(failures == 0 ? "\nAll checks passed." : "\n\(failures) check(s) failed.")
        if failures > 0 { exit(1) }
    default:
        print("usage: starlist-dev icon <iconset-dir> | snapshot <out-dir> | sample <data-dir> | check")
        exit(64)
    }
    // Clean up sample data.
    try? FileManager.default.removeItem(
        at: FileManager.default.temporaryDirectory
            .appendingPathComponent("starlist-dev-\(ProcessInfo.processInfo.processIdentifier)")
    )
} catch {
    FileHandle.standardError.write(Data("starlist-dev: \(error)\n".utf8))
    exit(1)
}
