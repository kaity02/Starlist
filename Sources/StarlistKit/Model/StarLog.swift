import Foundation

/// The days on which everything on the list got finished.
///
/// A day earns its star the moment the last unfinished task is checked off.
/// Un-checking that task takes the star back, so a stray click doesn't count.
@MainActor
public final class StarLog: ObservableObject {
    /// Day (`2026-11-13`) to the number of times the list was cleared that day.
    @Published public private(set) var clears: [String: Int] = [:]

    private let fileURL: URL
    private let calendar: Calendar

    public init(fileURL: URL, calendar: Calendar = .current) {
        self.fileURL = fileURL
        self.calendar = calendar
        if let data = try? Data(contentsOf: fileURL),
           let stored = try? JSONDecoder().decode([String: Int].self, from: data) {
            clears = stored
        }
    }

    public var total: Int { clears.count }

    public func hasStar(on date: Date) -> Bool {
        clears[Self.key(for: date, calendar: calendar)] != nil
    }

    public func recordClear(on date: Date = Date()) {
        clears[Self.key(for: date, calendar: calendar), default: 0] += 1
        save()
    }

    public func revokeClear(on date: Date = Date()) {
        let key = Self.key(for: date, calendar: calendar)
        guard let count = clears[key] else { return }
        clears[key] = count > 1 ? count - 1 : nil
        save()
    }

    /// Starred days in a row, ending today. If today's star isn't earned yet,
    /// the run ending yesterday still counts: the streak is alive until midnight.
    public func currentStreak(asOf today: Date = Date()) -> Int {
        var day = calendar.startOfDay(for: today)
        if !hasStar(on: day) {
            guard let yesterday = calendar.date(byAdding: .day, value: -1, to: day) else { return 0 }
            day = yesterday
        }
        var streak = 0
        while hasStar(on: day) {
            streak += 1
            guard let previous = calendar.date(byAdding: .day, value: -1, to: day) else { break }
            day = previous
        }
        return streak
    }

    public static func key(for date: Date, calendar: Calendar = .current) -> String {
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)
    }

    private func save() {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try? FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try? encoder.encode(clears).write(to: fileURL, options: .atomic)
    }
}

/// The layout of the star calendar: weeks as columns, weekdays as rows,
/// ending with the current week.
public struct StarCalendar {
    public struct MonthLabel: Identifiable, Equatable {
        public let column: Int
        public let text: String
        public var id: Int { column }
    }

    public let weeks: Int
    public let today: Date
    private let firstDay: Date
    private let calendar: Calendar

    public init(today: Date = Date(), weeks: Int = 18, calendar: Calendar = .current) {
        self.weeks = weeks
        self.calendar = calendar
        let startOfToday = calendar.startOfDay(for: today)
        self.today = startOfToday
        let weekday = calendar.component(.weekday, from: startOfToday)
        let daysIntoWeek = (weekday - calendar.firstWeekday + 7) % 7
        let thisWeek = calendar.date(byAdding: .day, value: -daysIntoWeek, to: startOfToday) ?? startOfToday
        firstDay = calendar.date(byAdding: .day, value: -(weeks - 1) * 7, to: thisWeek) ?? thisWeek
    }

    /// The date in a cell, or nil for days that haven't happened yet.
    public func date(week: Int, day: Int) -> Date? {
        guard let date = calendar.date(byAdding: .day, value: week * 7 + day, to: firstDay),
              date <= today else { return nil }
        return date
    }

    /// The short weekday name for a row ("Mon"), following the calendar's first weekday.
    public func weekdaySymbol(row: Int) -> String {
        guard let date = calendar.date(byAdding: .day, value: row, to: firstDay) else { return "" }
        return date.formatted(labelStyle.weekday(.abbreviated))
    }

    /// Names come from a date formatter, not the calendar's symbol tables,
    /// which are placeholders ("M07") when the calendar has no locale.
    private var labelStyle: Date.FormatStyle {
        Date.FormatStyle(
            date: .omitted, time: .omitted,
            locale: calendar.locale ?? .current, calendar: calendar, timeZone: calendar.timeZone
        )
    }

    /// A label above the first column of each month.
    public var monthLabels: [MonthLabel] {
        var labels: [MonthLabel] = []
        var previousMonth: Int?
        for week in 0..<weeks {
            guard let start = calendar.date(byAdding: .day, value: week * 7, to: firstDay) else { continue }
            let month = calendar.component(.month, from: start)
            defer { previousMonth = month }
            guard month != previousMonth else { continue }
            // A partial first month would collide with the label that follows it.
            if week == 0,
               let next = calendar.date(byAdding: .day, value: 14, to: firstDay),
               calendar.component(.month, from: next) != month {
                continue
            }
            labels.append(MonthLabel(
                column: week,
                text: start.formatted(labelStyle.month(.abbreviated))
            ))
        }
        return labels
    }
}
