// starlist-dev: the build-time helper.
//
//   starlist-dev icon <iconset-dir>     Renders the app icon at every size macOS wants.
//   starlist-dev snapshot <out-dir>     Renders the panel in its main states, plus the glyphs.
//   starlist-dev check                  Runs the logic checks (store, Markdown, archive, undo).

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

/// The menu bar glyph, large on both menu bar colors and again at true size.
struct GlyphSheet: View {
    var body: some View {
        HStack(spacing: 0) {
            swatch(background: Color(white: 0.93), ink: .black)
            swatch(background: Color(white: 0.12), ink: .white)
        }
    }

    private func swatch(background: Color, ink: Color) -> some View {
        VStack(spacing: 18) {
            glyph(ink: ink).frame(width: 180, height: 180)
            HStack(spacing: 14) {
                glyph(ink: ink).frame(width: 18, height: 18)
                glyph(ink: ink).frame(width: 36, height: 36)
            }
        }
        .frame(width: 240, height: 290)
        .background(background)
    }

    private func glyph(ink: Color) -> some View {
        Canvas { context, size in
            let geometry = ShootingStarGeometry(
                in: CGRect(origin: .zero, size: size), separated: true
            )
            context.fill(geometry.star, with: .color(ink))
            for trail in geometry.trails {
                context.fill(trail.path, with: .color(ink))
            }
        }
    }
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
func sampleModel(_ name: String, tasks: [(String, Bool)]) throws -> AppModel {
    let model = AppModel(paths: .contained(in: try scratchDirectory(name)))
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

    // A few days of history to browse.
    let history = try sampleModel("history", tasks: sampleTasks)
    let day: TimeInterval = 86_400
    for (offset, doneCount) in [(3.0, 2), (2.0, 5), (1.0, 3)] {
        let items = sampleTasks.enumerated().map { index, task in
            TodoItem(title: task.0, isDone: index < doneCount)
        }
        _ = try await history.archive.save(
            items: items, keepsUnfinished: true, at: Date().addingTimeInterval(-offset * day)
        )
    }
    history.screen = .history
    await history.archive.refresh()
    history.expandedArchive = history.archive.lists.first?.id
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
    let small = HStack(spacing: 12) {
        AppIconView(size: 128)
        AppIconView(size: 64)
        AppIconView(size: 32)
        AppIconView(size: 16)
    }
    .padding(16)
    .background(Color(white: 0.9))
    try writePNG(try render(small, scale: 2), to: out("9-icon-small.png"))
    print("Wrote 9-icon-small.png")
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
        expect(store.items.isEmpty, "starts empty")
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

    print("Markdown")
    do {
        let items = [
            TodoItem(title: "Buy oat milk", isDone: true),
            TodoItem(title: "Call the dentist"),
            TodoItem(title: "Email Sam", isDone: true),
        ]
        var components = DateComponents()
        (components.year, components.month, components.day) = (2026, 11, 13)
        (components.hour, components.minute) = (15, 32)
        let zone = TimeZone(identifier: "America/Los_Angeles")!
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = zone
        let date = calendar.date(from: components)!
        let text = ArchiveMarkdown.render(
            items: items, archivedAt: date, keepsUnfinished: true,
            locale: Locale(identifier: "en_US"), timeZone: zone
        )
        let expected = """
        # To-do list for Friday, November 13, 2026

        Archived at 3:32 PM. 2 of 3 tasks done.

        ## Done

        - [x] Buy oat milk
        - [x] Email Sam

        ## Carried over

        - [ ] Call the dentist

        """
        expect(text == expected, "renders the expected file")
        if text != expected { print(text) }

        let dropped = ArchiveMarkdown.render(
            items: [TodoItem(title: "Only one")], archivedAt: date, keepsUnfinished: false,
            locale: Locale(identifier: "en_US"), timeZone: zone
        )
        expect(dropped.contains("0 of 1 task done."), "says \"1 task\", not \"1 tasks\"")
        expect(dropped.contains("## Not done") && !dropped.contains("## Done"),
               "labels dropped tasks and leaves out an empty Done section")

        let parsed = ArchiveMarkdown.parseItems(text)
        expect(parsed.map(\.title) == ["Buy oat milk", "Email Sam", "Call the dentist"],
               "reads the tasks back")
        expect(parsed.map(\.isDone) == [true, true, false], "reads back what was done")
        expect(ArchiveMarkdown.parseItems("# Notes\n- plain bullet\n* [X] Star bullet\n").count == 1,
               "ignores lines that aren't checklist items")

        expect(ArchiveMarkdown.fileName(for: date, attempt: 1, timeZone: zone)
               == "2026-11-13 To-do list.md", "names the file by day")
        expect(ArchiveMarkdown.fileName(for: date, attempt: 3, timeZone: zone)
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
        expect(model.store.items.count == 4 && model.store.doneCount == 0,
               "finished tasks leave the list, unfinished ones stay")
        if case let .archived(count, _) = model.banner {
            expect(count == 6, "confirms how many tasks were saved")
        } else {
            expect(false, "confirms how many tasks were saved")
        }
        expect(model.archive.lists.first?.items.count == 6 && model.archive.lists.first?.doneCount == 2,
               "History shows the archived list")

        model.store.add("Added after archiving")
        await model.undoArchive()
        expect(model.store.items.count == 7 && model.store.doneCount == 2,
               "undo restores the list and keeps tasks added since")
        expect(((try? fm.contentsOfDirectory(atPath: folder.path)) ?? []).isEmpty,
               "undo removes the file it wrote")
        expect(model.banner == nil && model.archive.lists.isEmpty, "undo clears the banner and History")

        await model.archiveList()
        await model.archiveList()
        let names = (try? fm.contentsOfDirectory(atPath: folder.path)) ?? []
        expect(names.count == 2 && names.contains { $0.hasSuffix("To-do list 2.md") },
               "a second archive the same day gets its own file")
        expect(model.archive.lists.count == 2, "History lists both")

        model.keepsUnfinished = false
        await model.archiveList()
        expect(model.store.items.isEmpty, "with carry-over off, archiving clears the whole list")
        await model.archiveList()
        expect(((try? fm.contentsOfDirectory(atPath: folder.path)) ?? []).count == 3,
               "archiving an empty list writes nothing")

        let relaunched = AppModel(paths: .contained(in: folder.deletingLastPathComponent()))
        expect(relaunched.keepsUnfinished == false, "the carry-over setting is remembered")
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
}

// MARK: - Entry point

_ = NSApplication.shared
let arguments = Array(CommandLine.arguments.dropFirst())

do {
    switch arguments.first {
    case "icon" where arguments.count == 2:
        try renderIcon(into: URL(fileURLWithPath: arguments[1], isDirectory: true))
    case "snapshot" where arguments.count == 2:
        try await renderSnapshots(into: URL(fileURLWithPath: arguments[1], isDirectory: true))
    case "check":
        try await runChecks()
        print(failures == 0 ? "\nAll checks passed." : "\n\(failures) check(s) failed.")
        if failures > 0 { exit(1) }
    default:
        print("usage: starlist-dev icon <iconset-dir> | snapshot <out-dir> | check")
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
