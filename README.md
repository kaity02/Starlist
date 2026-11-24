# Starlist

A to-do list that lives in the macOS menu bar. Click the shooting star, type a task, press Return.

## What it does

- **Add a task.** The field is ready for typing as soon as the panel opens.
- **Check it off.** Click the circle. It becomes a star, a small comet crosses the task out, and the task drops to the bottom of the list, below everything still to do. New tasks land above the finished ones.
- **Finish everything.** Checking off the last task sets off a burst of stars and earns the day's star.
- **See what's left at a glance.** The menu bar icon carries a red dot while any task is unfinished.
- **Focus with a timer.** Click the timer at the top of the list and choose 25, 40 or 60 minutes of focus. A 5-minute break follows. When the break is over, click the timer again for the next session. The time left shows in the menu bar beside the star.
- **Keep things for later.** The Later list holds tasks for another day. They don't count toward today: no red dot, no star, and Archive leaves them alone. Hover a task and click the clock to put it off, or "Do today" to bring it back.
- **Archive the list.** Nothing is archived until you press "Archive list". Then the whole list, finished or not, is saved as a Markdown file. Finished tasks leave the list; unfinished ones stay on it for another day. A banner offers **Undo** for a few seconds.
- **History.** A calendar with a star on every day you finished your whole list, and below it every archived list, which you can open in your Markdown editor or show in Finder.
- **Notion (optional).** Each archived list is also added to a page in your Notion workspace.

Also: double-click a task to edit it, drag it up or down to reorder the list, hover to delete it, right-click to edit or delete. In today's field, Command-Return sends what you typed to Later instead. Escape closes the panel. Right-click the menu bar icon for settings and Quit. If the icon is hidden by a crowded menu bar, open Starlist again from Spotlight and the panel appears.

## Build and install

Needs macOS 15 or later and the Xcode Command Line Tools (`xcode-select --install`). Xcode itself is not required.

```sh
Scripts/build-app.sh             # builds build/Starlist.app
Scripts/build-app.sh --install   # builds, copies to /Applications, launches
```

To start Starlist when you log in, choose "Open at login" from the "..." menu.

## Connecting Notion

Choose "Connect Notion…" from the "..." menu. You need two things:

1. **An integration secret.** In Notion, go to Settings, Connections, "Develop or manage integrations" (or open <https://www.notion.so/profile/integrations>), create an internal integration with permission to read and insert content, and copy its secret.
2. **A page shared with that integration.** Open the page you want updated, open the menu at its top right, choose Connections, and add the integration. Then copy the page's link.

Paste both into Starlist and press Connect.

From then on, archiving works like this:

- The Markdown file is saved first, always.
- When Undo expires (about ten seconds later), the list is added to the Notion page: the date as a heading, a one-line summary, and the tasks as Notion to-dos.
- Lists go directly under a "Starlist" heading that the app adds to the page the first time. Newest is on top. Move that heading anywhere on the page and new lists follow it; delete it and the app makes a new one.
- If Notion can't be reached, the list waits in a queue on disk and is sent the next time you open the panel, archive, or launch the app.

The secret is stored in a file only your account can read, `~/Library/Application Support/Starlist/notion-secret`. It never leaves your Mac except to go to Notion.

Earlier versions kept the secret in your login keychain. The first time a newer build needs it, macOS asks once for your login keychain password, which is the password you use to log in to your Mac, not the Notion secret. Starlist then moves the secret into the file and macOS doesn't ask again, including after rebuilding the app.

## The focus timer

Clicking the timer shows three lengths: 25, 40 or 60 minutes. Click one to start, or click the timer again to put them away. The break is 5 minutes whichever you choose.

The timer keeps running with the panel closed. When a focus session ends, a notification says so and the break starts by itself. When the break ends, another notification says so and the timer waits: the next session starts when you click the timer again. In the panel, Pause holds the time where it is and Stop clears the timer.

- The first time you start it, macOS asks whether Starlist may send notifications. If you say no, you hear a chime instead.
- If the Mac is asleep when a session or a break runs out, the timer stops, so it doesn't run on without you.
- The timer isn't saved. Quitting Starlist ends it.

## Where things are kept

| What | Where |
| --- | --- |
| Current list | `~/Library/Application Support/Starlist/tasks.json` |
| Later list | `~/Library/Application Support/Starlist/later.json` |
| Stars (days you finished everything) | `~/Library/Application Support/Starlist/stars.json` |
| Settings | `~/Library/Application Support/Starlist/settings.json` |
| Lists waiting for Notion | `~/Library/Application Support/Starlist/notion-outbox.json` |
| Notion integration secret | `~/Library/Application Support/Starlist/notion-secret` |
| Archived lists | `~/Documents/Starlist/` (change it from History, "Change folder…") |

The first time you archive, macOS asks whether Starlist may use your Documents folder.

Each archive is one file, named by day: `2026-11-13 To-do list.md`. A second archive on the same day becomes `2026-11-13 To-do list 2.md`.

```markdown
# To-do list for Friday, November 13, 2026

Archived at 3:32 PM. 2 of 3 tasks done.

## Done

- [x] Buy oat milk
- [x] Email Sam

## Not done

- [ ] Call the dentist
```

History reads the folder directly, so moving, editing, or deleting files in Finder is reflected in the app.

### How a day earns its star

A day gets its star the moment you check off the last unfinished task on the list. Un-checking that task takes the star back, so a stray click doesn't count. Deleting tasks, or putting them off until later, never earns one.

## Project layout

```
Sources/StarlistKit/   Model (tasks, stars, focus timer, settings, Markdown archive, Notion), design, SwiftUI views
Sources/Starlist/      The menu bar app: status item, panel, menus
Sources/StarlistDev/   Build-time helper: icon renderer, snapshots, logic checks
Resources/Info.plist   Bundle settings (menu bar only, no Dock icon)
Scripts/build-app.sh   Assembles and signs Starlist.app
```

## Development

```sh
swift build
.build/debug/starlist-dev check              # logic checks, including Notion against a stand-in server
.build/debug/starlist-dev snapshot /tmp/out  # PNGs of every screen, the glyph, and the icon

# Run against a throwaway folder instead of your real list:
.build/debug/starlist-dev sample /tmp/starlist-test   # optional: fill it with sample tasks
build/Starlist.app/Contents/MacOS/Starlist --data-dir /tmp/starlist-test --show
```

Three things worth knowing:

- The app icon and menu bar glyph are drawn in code (`Design/StarShapes.swift`, `Design/AppIconView.swift`). The build script renders the icon at every size and packs the `.icns`.
- Views use `@Stored` instead of `@State`. In the macOS 27 SDK `@State` is a compiler macro whose plugin ships only with Xcode; `Stored` is an alias for the same SwiftUI type that builds with the Command Line Tools alone. See `Design/Stored.swift`.
- Notion requests use API version `2026-03-11` (`Model/Notion.swift`). The secret is kept in a file in the data folder, not the keychain: the build is ad-hoc signed, so macOS would treat each rebuild as a different app and ask for the keychain password again. With `--data-dir`, the keychain is never touched at all.

## License

MIT. See [LICENSE](LICENSE).
