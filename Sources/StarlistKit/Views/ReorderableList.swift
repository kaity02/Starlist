import SwiftUI

/// The arithmetic of dragging one row of a vertical stack to a new place.
/// Rows can be different heights: a long task wraps onto several lines.
public struct ReorderLayout: Equatable {
    public let heights: [CGFloat]
    public let spacing: CGFloat

    public init(heights: [CGFloat], spacing: CGFloat) {
        self.heights = heights
        self.spacing = spacing
    }

    func top(of index: Int) -> CGFloat {
        heights.prefix(index).reduce(0) { $0 + $1 + spacing }
    }

    func center(of index: Int) -> CGFloat {
        top(of: index) + heights[index] / 2
    }

    /// Keeps a dragged row between the first place and the last.
    public func clamp(_ travel: CGFloat, dragging index: Int) -> CGFloat {
        guard heights.indices.contains(index) else { return 0 }
        let start = top(of: index)
        let lastPlace = top(of: heights.count) - spacing - heights[index]
        return min(max(travel, -start), max(lastPlace - start, -start))
    }

    /// Where the row would land if it were dropped now. It trades places with
    /// a neighbor once it covers half of it.
    public func destination(dragging index: Int, by travel: CGFloat) -> Int {
        guard heights.indices.contains(index) else { return index }
        let upper = top(of: index) + travel
        let lower = upper + heights[index]
        let passedBelow = heights.indices.filter { $0 > index && lower > center(of: $0) }.count
        let passedAbove = heights.indices.filter { $0 < index && upper < center(of: $0) }.count
        return index + passedBelow - passedAbove
    }

    /// How far another row steps aside to make room.
    public func shift(of row: Int, dragging index: Int, to destination: Int) -> CGFloat {
        guard heights.indices.contains(index) else { return 0 }
        let step = heights[index] + spacing
        if index < row && row <= destination { return -step }
        if destination <= row && row < index { return step }
        return 0
    }
}

/// A scrolling column of task rows. Press a row and drag to move it; the
/// others step aside, and the list scrolls when the row nears an edge.
struct ReorderableList<Row: View>: View {
    let items: [TodoItem]
    /// A row that stays put for now, because its title is being edited.
    var lockedID: UUID?
    /// The task that moved, and its new place in the list.
    let onMove: (UUID, Int) -> Void
    @ViewBuilder let row: (TodoItem) -> Row

    private struct Drag: Equatable {
        let id: UUID
        /// Where the pointer went down. A new press is a new drag, even on the same row.
        let start: CGPoint
        /// How far the list was scrolled when the row was picked up.
        let startScroll: CGFloat
        /// How far the pointer has gone since.
        var pointerTravel: CGFloat = 0
        /// The pointer's distance from the top of the visible list.
        var pointerY: CGFloat = 0
    }

    private struct Viewport: Equatable {
        var offset: CGFloat = 0
        var height: CGFloat = 0
        var contentHeight: CGFloat = 0
    }

    private struct Lift {
        let index: Int
        let travel: CGFloat
        let destination: Int
    }

    @Stored private var heights: [UUID: CGFloat] = [:]
    @Stored private var drag: Drag?
    @Stored private var viewport = Viewport()
    @Stored private var viewportTop: CGFloat = 0
    @Stored private var position = ScrollPosition()
    @GestureState private var isPressed = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private let spacing: CGFloat = 1
    /// One curve for rows stepping aside and for the drop, so the two line up.
    private var settle: Animation? { reduceMotion ? nil : .easeOut(duration: 0.2) }

    private var layout: ReorderLayout {
        ReorderLayout(heights: items.map { heights[$0.id] ?? 0 }, spacing: spacing)
    }

    /// The row in hand: where it started, how far it has gone, where it would land.
    private var lift: Lift? {
        guard let drag, let index = items.firstIndex(where: { $0.id == drag.id }) else { return nil }
        let layout = layout
        // Scrolling under a still pointer moves the row down the list too.
        let travel = layout.clamp(
            drag.pointerTravel + viewport.offset - drag.startScroll, dragging: index
        )
        return Lift(
            index: index, travel: travel,
            destination: layout.destination(dragging: index, by: travel)
        )
    }

    var body: some View {
        let layout = layout
        let lift = lift

        ScrollViewReader { proxy in
            ScrollView {
                VStack(spacing: spacing) {
                    ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                        let isLifted = lift?.index == index
                        row(item)
                            .background(LiftedBacking().opacity(isLifted ? 1 : 0))
                            .onGeometryChange(for: CGFloat.self) { $0.size.height } action: {
                                heights[item.id] = $0
                            }
                            .offset(y: offset(of: index, lift: lift, in: layout))
                            .zIndex(isLifted ? 1 : 0)
                            // The row in hand follows the pointer exactly; the rest glide.
                            .animation(isLifted ? nil : settle, value: lift?.destination)
                            .gesture(
                                dragGesture(for: item.id),
                                including: item.id == lockedID ? .subviews : .all
                            )
                            .id(item.id)
                            .transition(.opacity)
                    }
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
                .animation(settle, value: items.map(\.id))
            }
            .scrollPosition($position)
            .onScrollGeometryChange(for: Viewport.self) { geometry in
                Viewport(
                    offset: geometry.contentOffset.y,
                    height: geometry.containerSize.height,
                    contentHeight: geometry.contentSize.height
                )
            } action: { _, new in
                viewport = new
            }
            .onGeometryChange(for: CGFloat.self) { $0.frame(in: .global).minY } action: {
                viewportTop = $0
            }
            // Rows dissolve into the sky at the edges instead of being cut off.
            .mask(
                VStack(spacing: 0) {
                    LinearGradient(colors: [.clear, .black], startPoint: .top, endPoint: .bottom)
                        .frame(height: 8)
                    Rectangle()
                    LinearGradient(colors: [.black, .clear], startPoint: .top, endPoint: .bottom)
                        .frame(height: 8)
                }
            )
            .onChange(of: items.count) { old, new in
                guard new > old, let last = items.last else { return }
                withAnimation(.easeOut(duration: 0.2)) {
                    proxy.scrollTo(last.id, anchor: .bottom)
                }
            }
            .onChange(of: isPressed) { _, pressed in
                // A drag that was interrupted (the panel closed) never reports
                // its end. Let a normal drop go first, then put the row back.
                guard !pressed else { return }
                DispatchQueue.main.async { drag = nil }
            }
            .task(id: drag?.id) {
                guard drag != nil else { return }
                while !Task.isCancelled {
                    try? await Task.sleep(for: .milliseconds(16))
                    scrollIfNearEdge()
                }
            }
        }
    }

    private func offset(of index: Int, lift: Lift?, in layout: ReorderLayout) -> CGFloat {
        guard let lift else { return 0 }
        if lift.index == index { return lift.travel }
        return layout.shift(of: index, dragging: lift.index, to: lift.destination)
    }

    private func dragGesture(for id: UUID) -> some Gesture {
        // Measured against the window: the row itself moves under the pointer.
        DragGesture(minimumDistance: 4, coordinateSpace: .global)
            .updating($isPressed) { _, pressed, _ in pressed = true }
            .onChanged { value in
                if drag?.id != id || drag?.start != value.startLocation {
                    drag = Drag(id: id, start: value.startLocation, startScroll: viewport.offset)
                }
                drag?.pointerTravel = value.translation.height
                drag?.pointerY = value.location.y - viewportTop
            }
            .onEnded { _ in drop() }
    }

    private func drop() {
        guard let id = drag?.id, let lift else {
            drag = nil
            return
        }
        // Clearing the drag and moving the task in one update lets every row
        // settle from where it is on screen.
        drag = nil
        if lift.destination != lift.index { onMove(id, lift.destination) }
    }

    /// Scrolls a long list while the row is held near its top or bottom edge,
    /// faster the closer the pointer gets.
    private func scrollIfNearEdge() {
        guard let drag, viewport.height > 0 else { return }
        let reach: CGFloat = 32
        let fromTop = drag.pointerY
        let fromBottom = viewport.height - drag.pointerY
        var pull: CGFloat = 0
        if fromTop < reach {
            pull = -(reach - fromTop)
        } else if fromBottom < reach {
            pull = reach - fromBottom
        }
        pull = min(max(pull, -reach * 1.5), reach * 1.5)
        let furthest = max(0, viewport.contentHeight - viewport.height)
        let target = min(max(viewport.offset + pull * 0.2, 0), furthest)
        guard abs(target - viewport.offset) > 0.01 else { return }
        position.scrollTo(y: target)
    }
}

/// What a row rests on while it is in hand, so the tasks it passes over
/// don't show through.
private struct LiftedBacking: View {
    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 9, style: .continuous)
        shape
            .fill(Sky.dusk)
            .overlay(shape.fill(Color.white.opacity(0.07)))
            .overlay(shape.strokeBorder(Color.white.opacity(0.16), lineWidth: 1))
            .shadow(color: .black.opacity(0.4), radius: 9, y: 4)
    }
}
