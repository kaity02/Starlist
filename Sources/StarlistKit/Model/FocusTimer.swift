import Foundation

/// The Pomodoro timer: 25 minutes of focus, then a 5-minute break. After the
/// break it waits to be started again, so it never runs on with nobody there.
/// It lives in memory only, so quitting the app ends it.
@MainActor
public final class FocusTimer: ObservableObject {
    public enum Phase: Equatable, Sendable {
        case focus
        /// The break after a focus session.
        case rest
    }

    public static let focusLength: TimeInterval = 25 * 60
    public static let breakLength: TimeInterval = 5 * 60

    /// Nil while the timer is not in use.
    @Published public private(set) var phase: Phase?
    /// Whole seconds left in the current phase.
    @Published public private(set) var secondsLeft = 0
    @Published public private(set) var isPaused = false

    /// Called with the phase that just ran out: focus once the break has
    /// begun, the break once the timer has gone back to waiting.
    public var onPhaseEnd: (Phase) -> Void = { _ in }
    /// Where the timer reads the time. The checks swap in a clock they can wind forward.
    public var clock: () -> Date = { Date() }

    /// A phase found to have ended longer ago than this means the Mac was
    /// asleep. Nobody was there for it, so the timer stops instead of running on.
    private let longestOverrun: TimeInterval = 60

    private var endsAt: Date?
    private var leftWhenPaused: TimeInterval = 0
    private var ticker: Timer?
    private var activity: NSObjectProtocol?

    public init() {}

    deinit {
        ticker?.invalidate()
        if let activity { ProcessInfo.processInfo.endActivity(activity) }
    }

    /// How far through the current phase, from 0 to 1.
    public var progress: Double {
        guard let phase else { return 0 }
        return 1 - Double(secondsLeft) / Self.length(of: phase)
    }

    public var timeText: String { Self.clockText(secondsLeft) }

    public static func length(of phase: Phase) -> TimeInterval {
        phase == .focus ? focusLength : breakLength
    }

    /// Minutes and seconds, as on a kitchen timer: "25:00", "4:59".
    public static func clockText(_ seconds: Int) -> String {
        "\(seconds / 60):" + String(format: "%02d", seconds % 60)
    }

    // MARK: Controls

    /// Begins a focus session, whatever the timer was doing before.
    public func start() {
        begin(.focus)
    }

    /// Holds the time where it is. The display keeps showing the same second.
    public func pause() {
        guard let endsAt, !isPaused else { return }
        leftWhenPaused = max(0, endsAt.timeIntervalSince(clock()))
        self.endsAt = nil
        isPaused = true
        stopTicking()
    }

    public func resume() {
        guard phase != nil, isPaused else { return }
        endsAt = clock().addingTimeInterval(leftWhenPaused)
        isPaused = false
        startTicking()
    }

    public func stop() {
        stopTicking()
        endsAt = nil
        isPaused = false
        phase = nil
        secondsLeft = 0
    }

    /// Brings the display up to date and, when this phase has run out, moves
    /// from focus to the break or from the break back to waiting. Called once
    /// a second while the timer runs.
    public func tick() {
        guard let phase, let endsAt else { return }
        // Ticks land on the second, give or take a few milliseconds either
        // way, so the nearest whole number is the second to show.
        let left = Int(endsAt.timeIntervalSince(clock()).rounded())
        if left > 0 {
            if secondsLeft != left { secondsLeft = left }
        } else if TimeInterval(-left) > longestOverrun {
            stop()
        } else {
            switch phase {
            case .focus:
                // The break gets its full length from now, not from when
                // focus should have ended.
                begin(.rest)
            case .rest:
                // The next session is yours to start.
                stop()
            }
            onPhaseEnd(phase)
        }
    }

    // MARK: Running

    private func begin(_ next: Phase) {
        let length = Self.length(of: next)
        endsAt = clock().addingTimeInterval(length)
        isPaused = false
        // The time first, so nothing ever shows the new phase with the old time.
        secondsLeft = Int(length)
        phase = next
        startTicking()
    }

    private func startTicking() {
        stopTicking()
        guard let endsAt else { return }
        // Fire as each second runs out, so the display changes on the second.
        let left = endsAt.timeIntervalSince(clock())
        let untilNextSecond = left - left.rounded(.down)
        let timer = Timer(
            fire: Date().addingTimeInterval(untilNextSecond), interval: 1, repeats: true
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
        timer.tolerance = 0.05
        // Common modes, so the time keeps moving while a menu is open.
        RunLoop.main.add(timer, forMode: .common)
        ticker = timer
        // A menu bar app with its panel closed is a candidate for App Nap,
        // which would hold the ticks back. The Mac may still go to sleep.
        activity = ProcessInfo.processInfo.beginActivity(
            options: .userInitiatedAllowingIdleSystemSleep, reason: "Focus timer running"
        )
    }

    private func stopTicking() {
        ticker?.invalidate()
        ticker = nil
        if let activity { ProcessInfo.processInfo.endActivity(activity) }
        activity = nil
    }
}
