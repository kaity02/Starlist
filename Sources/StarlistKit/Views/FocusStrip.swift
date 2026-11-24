import SwiftUI

// These two views watch the timer directly, not through the model. It changes
// every second, and nothing else on the list needs to be redrawn for that.

/// The button in the list's header for the timer. It brings out the lengths
/// to choose from in the strip below, and puts them away again. Once the
/// timer is in use it steps aside for the strip, which has the controls.
struct FocusStartButton: View {
    @ObservedObject var timer: FocusTimer
    /// True while the lengths are showing.
    let isChoosing: Bool
    let action: () -> Void

    var body: some View {
        if timer.phase == nil {
            IconButton(
                systemName: "timer",
                label: isChoosing ? "Hide the focus timer" : "Start a focus timer"
            ) {
                withAnimation(.easeOut(duration: 0.22)) { action() }
            }
            .transition(.opacity)
        }
    }
}

/// The timer's place under the header. Before a session it offers the
/// lengths to choose from; during one it shows which phase, the time left,
/// how far along, and the buttons to pause or stop. Takes up no room otherwise.
struct FocusStrip: View {
    @ObservedObject var timer: FocusTimer
    /// True while the lengths to choose from should show.
    var isChoosing = false
    /// Called with the minutes of focus that were chosen.
    var onChoose: (Int) -> Void = { _ in }

    var body: some View {
        if timer.phase != nil || isChoosing {
            HStack(spacing: 10) {
                if let phase = timer.phase {
                    running(phase)
                } else {
                    choices
                }
            }
            .padding(.leading, 12)
            .padding(.trailing, 6)
            .frame(height: 38)
            .background(
                RoundedRectangle(cornerRadius: 11, style: .continuous)
                    .fill(Color.white.opacity(0.07))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 11, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.13), lineWidth: 1)
            )
            .padding(.horizontal, 14)
            .padding(.bottom, 2)
            .transition(.opacity)
        }
    }

    /// "Focus for", then a button for each length.
    @ViewBuilder
    private var choices: some View {
        Text("Focus for")
            .font(Face.text(12.5, .medium))
            .foregroundStyle(Sky.haze)
            .fixedSize()
        Spacer(minLength: 0)
        HStack(spacing: 6) {
            ForEach(FocusTimer.focusChoices, id: \.self) { minutes in
                FocusLengthButton(minutes: minutes) {
                    withAnimation(.easeOut(duration: 0.22)) { onChoose(minutes) }
                }
            }
        }
        .padding(.trailing, 1)
    }

    @ViewBuilder
    private func running(_ phase: FocusTimer.Phase) -> some View {
        HStack(spacing: 8) {
            // Each text sits in the space of its widest value, so the
            // track beside them never changes length.
            Text("Paused")
                .font(Face.text(12.5, .medium))
                .hidden()
                .overlay(alignment: .leading) {
                    Text(timer.isPaused ? "Paused" : phase == .focus ? "Focus" : "Break")
                        .font(Face.text(12.5, .medium))
                        .foregroundStyle(Sky.haze)
                        .fixedSize()
                }
            Text("00:00")
                .font(Face.text(14, .medium))
                .monospacedDigit()
                .hidden()
                .overlay(alignment: .leading) {
                    Text(timer.timeText)
                        .font(Face.text(14, .medium))
                        .monospacedDigit()
                        .foregroundStyle(Sky.moonlight.opacity(timer.isPaused ? 0.55 : 1))
                        .fixedSize()
                }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(phase == .focus ? "Focus timer" : "Break timer")
        .accessibilityValue(spokenTime)

        FocusTrack(
            progress: timer.progress,
            // Warm light for work, cool light for rest.
            tint: phase == .focus ? Sky.starlight : Sky.moonlight
        )
        .opacity(timer.isPaused ? 0.55 : 1)

        HStack(spacing: 0) {
            IconButton(
                systemName: timer.isPaused ? "play.fill" : "pause.fill",
                label: timer.isPaused ? "Resume timer" : "Pause timer",
                hoverColor: Sky.starlight,
                size: 24,
                symbolSize: 9
            ) {
                if timer.isPaused { timer.resume() } else { timer.pause() }
            }
            IconButton(
                systemName: "stop.fill",
                label: "Stop timer",
                hoverColor: Sky.ember,
                size: 24,
                symbolSize: 9
            ) {
                withAnimation(.easeOut(duration: 0.22)) { timer.stop() }
            }
        }
    }

    private var spokenTime: String {
        let minutes = timer.secondsLeft / 60
        let seconds = timer.secondsLeft % 60
        let left = "\(minutes) min \(seconds) sec left"
        return timer.isPaused ? "Paused, \(left)" : left
    }
}

/// One length of focus to choose: "40 min". Choosing it starts the timer.
private struct FocusLengthButton: View {
    let minutes: Int
    let action: () -> Void

    @Stored private var hovering = false

    var body: some View {
        Button(action: action) {
            Text("\(minutes) min")
                .font(Face.text(12.5, .medium))
                .monospacedDigit()
                .foregroundStyle(hovering ? Sky.starlight : Sky.moonlight)
                .padding(.horizontal, 9)
                .frame(height: 26)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(Color.white.opacity(hovering ? 0.14 : 0.08))
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .help("Start \(minutes) minutes of focus")
        .accessibilityLabel("Focus for \(minutes) minutes")
    }
}

/// A star crossing from left to right as the time runs, trailing light
/// behind it like the comet that crosses out a finished task.
private struct FocusTrack: View {
    let progress: Double
    let tint: Color

    var body: some View {
        Canvas { context, size in
            let radius: CGFloat = 5
            let y = size.height / 2
            let start = radius
            let end = max(start, size.width - radius)
            let x = start + (end - start) * min(max(progress, 0), 1)
            let line = StrokeStyle(lineWidth: 1.5, lineCap: .round)

            // The way still to go.
            var ahead = Path()
            ahead.move(to: CGPoint(x: x, y: y))
            ahead.addLine(to: CGPoint(x: end, y: y))
            context.stroke(ahead, with: .color(Color.white.opacity(0.16)), style: line)

            if x > start {
                var trail = Path()
                trail.move(to: CGPoint(x: start, y: y))
                trail.addLine(to: CGPoint(x: x, y: y))
                context.stroke(
                    trail,
                    with: .linearGradient(
                        Gradient(colors: [tint.opacity(0.08), tint.opacity(0.9)]),
                        startPoint: CGPoint(x: start, y: y),
                        endPoint: CGPoint(x: x, y: y)
                    ),
                    style: line
                )
            }

            var starContext = context
            starContext.addFilter(.shadow(color: tint.opacity(0.6), radius: 3))
            starContext.fill(
                StarShape.path(center: CGPoint(x: x, y: y + radius * 0.05), radius: radius),
                with: .color(tint)
            )
        }
        .frame(maxWidth: .infinity)
        .frame(height: 16)
        .accessibilityHidden(true)
    }
}
