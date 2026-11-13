# Starlist

A to-do list that lives in the macOS menu bar. Click the shooting star, type a task, press Return.

## What it does

- **Add a task.** The field is ready for typing as soon as the panel opens.
- **Check it off.** Click the circle. It becomes a star, and a small comet crosses the task out.
- **Archive the list.** "Archive list" saves the whole list as a Markdown file and clears the finished tasks. Unfinished tasks stay on the list (you can turn that off in the "..." menu). A banner offers **Undo** for a few seconds.
- **History.** Browse archived lists inside the app, open any of them in your Markdown editor, or show them in Finder.

Also: double-click a task to edit it, hover to delete it, right-click for both. Escape closes the panel. Right-click the menu bar icon for settings and Quit. If the icon is hidden by a crowded menu bar, open Starlist again from Spotlight and the panel appears.

## Build and install

Needs macOS 15 or later and the Xcode Command Line Tools (`xcode-select --install`). Xcode itself is not required.

```sh
Scripts/build-app.sh             # builds build/Starlist.app
Scripts/build-app.sh --install   # builds, copies to /Applications, launches
```

To start Starlist when you log in, choose "Open at login" from the "..." menu.

## Where things are kept

| What | Where |
| --- | --- |
| Current list | `~/Library/Application Support/Starlist/tasks.json` |
| Settings | `~/Library/Application Support/Starlist/settings.json` |
| Archived lists | `~/Documents/Starlist/` (change it from History, "Change folder…") |

The first time you archive, macOS asks whether Starlist may use your Documents folder.

Each archive is one file, named by day: `2026-11-13 To-do list.md`. A second archive on the same day becomes `2026-11-13 To-do list 2.md`.

```markdown
# To-do list for Friday, November 13, 2026

Archived at 3:32 PM. 2 of 3 tasks done.

## Done

- [x] Buy oat milk
- [x] Email Sam

## Carried over

- [ ] Call the dentist
```

History reads the folder directly, so moving, editing, or deleting files in Finder is reflected in the app.

## Project layout

```
Sources/StarlistKit/   Model (tasks, settings, Markdown archive), design, SwiftUI views
Sources/Starlist/      The menu bar app: status item, panel, menus
Sources/StarlistDev/   Build-time helper: icon renderer, snapshots, logic checks
Resources/Info.plist   Bundle settings (menu bar only, no Dock icon)
Scripts/build-app.sh   Assembles and signs Starlist.app
```

## Development

```sh
swift build
.build/debug/starlist-dev check              # logic checks: store, Markdown, archive, undo
.build/debug/starlist-dev snapshot /tmp/out  # PNGs of every screen, the glyph, and the icon

# Run against a throwaway folder instead of your real list:
build/Starlist.app/Contents/MacOS/Starlist --data-dir /tmp/starlist-test --show
```

Two things worth knowing:

- The app icon and menu bar glyph are drawn in code (`Design/StarShapes.swift`, `Design/AppIconView.swift`). The build script renders the icon at every size and packs the `.icns`.
- Views use `@Stored` instead of `@State`. In the macOS 27 SDK `@State` is a compiler macro whose plugin ships only with Xcode; `Stored` is an alias for the same SwiftUI type that builds with the Command Line Tools alone. See `Design/Stored.swift`.

## License

MIT. See [LICENSE](LICENSE).
