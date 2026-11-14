import SwiftUI

/// A calendar of the last few months where every day you finished your whole
/// list shines as a star. Weeks run left to right, weekdays top to bottom.
struct StarMap: View {
    @ObservedObject var stars: StarLog
    let today: Date

    private let weeks = 18
    private let cell: CGFloat = 12
    private let gap: CGFloat = 3
    private let labelWidth: CGFloat = 27

    var body: some View {
        let calendar = StarCalendar(today: today, weeks: weeks)
        let gridWidth = CGFloat(weeks) * cell + CGFloat(weeks - 1) * gap

        VStack(alignment: .leading, spacing: 5) {
            // Months along the top.
            ZStack(alignment: .topLeading) {
                ForEach(calendar.monthLabels) { label in
                    Text(label.text)
                        .font(Face.text(10.5))
                        .foregroundStyle(Sky.haze)
                        .fixedSize()
                        .offset(x: CGFloat(label.column) * (cell + gap))
                }
            }
            .frame(width: gridWidth, height: 13, alignment: .topLeading)
            .padding(.leading, labelWidth)
            .accessibilityHidden(true)

            HStack(alignment: .top, spacing: 0) {
                // Every other weekday down the side.
                VStack(alignment: .leading, spacing: gap) {
                    ForEach(0..<7, id: \.self) { row in
                        Text(row % 2 == 1 ? calendar.weekdaySymbol(row: row) : "")
                            .font(Face.text(10.5))
                            .foregroundStyle(Sky.haze)
                            .frame(width: labelWidth, height: cell, alignment: .leading)
                    }
                }
                .accessibilityHidden(true)

                HStack(spacing: gap) {
                    ForEach(0..<weeks, id: \.self) { week in
                        VStack(spacing: gap) {
                            ForEach(0..<7, id: \.self) { day in
                                dayCell(calendar.date(week: week, day: day))
                            }
                        }
                    }
                }
                .accessibilityHidden(true)
            }

            summary
                .padding(.top, 5)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(summaryText)
    }

    @ViewBuilder
    private func dayCell(_ date: Date?) -> some View {
        ZStack {
            if let date {
                let isToday = Calendar.current.isDate(date, inSameDayAs: today)
                if stars.hasStar(on: date) {
                    StarShape()
                        .fill(Sky.starlight)
                        .frame(width: 12, height: 12)
                        .shadow(color: Sky.starlight.opacity(0.6), radius: 2.5)
                } else if isToday {
                    // Today, still waiting for its star.
                    Circle()
                        .strokeBorder(Sky.haze, lineWidth: 1)
                        .frame(width: 8, height: 8)
                } else {
                    Circle()
                        .fill(Sky.haze.opacity(0.3))
                        .frame(width: 3.5, height: 3.5)
                }
            }
        }
        .frame(width: cell, height: cell)
        .help(date.map(tooltip) ?? "")
    }

    private func tooltip(_ date: Date) -> String {
        let day = date.formatted(.dateTime.weekday(.wide).month(.wide).day())
        return stars.hasStar(on: date) ? "\(day): finished everything" : day
    }

    private var summary: some View {
        HStack(alignment: .firstTextBaseline) {
            if stars.total == 0 {
                Text("Check off everything on your list to earn the day's star.")
                    .font(Face.text(12))
                    .foregroundStyle(Sky.haze)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                Text(stars.total == 1 ? "1 star" : "\(stars.total) stars")
                    .font(Face.text(12.5, .medium))
                    .foregroundStyle(Sky.starlight)
                Spacer()
                let streak = stars.currentStreak(asOf: today)
                if streak >= 2 {
                    Text("\(streak) days in a row")
                        .font(Face.text(12.5))
                        .foregroundStyle(Sky.haze)
                }
            }
        }
    }

    private var summaryText: String {
        guard stars.total > 0 else {
            return "Star calendar. No stars yet. Check off everything on your list to earn the day's star."
        }
        let streak = stars.currentStreak(asOf: today)
        let total = stars.total == 1 ? "1 star" : "\(stars.total) stars"
        return streak >= 2
            ? "Star calendar. \(total), \(streak) days in a row."
            : "Star calendar. \(total)."
    }
}
