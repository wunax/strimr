import SwiftUI

struct LibraryScrollMetrics: Equatable {
    var offset: CGFloat = 0
    var maximumOffset: CGFloat = 0
    var contentHeight: CGFloat = 0
    var containerSize: CGSize = .zero

    init() {}

    init(_ geometry: ScrollGeometry) {
        let insets = geometry.contentInsets
        offset = geometry.contentOffset.y + insets.top
        maximumOffset = geometry.contentSize.height + insets.top + insets.bottom - geometry.containerSize.height
        contentHeight = geometry.contentSize.height
        containerSize = geometry.containerSize
    }

    /// Over a few screens, regular scrolling is quick enough.
    var isLongEnoughToScrub: Bool {
        containerSize.height > 0 && contentHeight > containerSize.height * 3
    }

    var fraction: Double {
        LibraryScrubberMapping.fraction(contentOffset: offset, maximumOffset: maximumOffset)
    }
}

/// Draggable handle on the trailing edge that reaches any position of a long listing at once.
struct LibraryScrubber: View {
    let totalCount: Int
    let sectionIndex: LibrarySectionIndex?
    let scrollFraction: Double
    let isScrolling: Bool
    let isPointerNearby: Bool
    let onBegin: () -> Void
    let onScrub: (Int) -> Void
    let onEnd: (Int) -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isRevealed = false
    @State private var dragFraction: Double?
    @State private var scrubIndex = 0
    @State private var reachedEdge: VerticalEdge?
    @State private var hideTask: Task<Void, Never>?

    private let hitSize = CGSize(width: 44, height: 56)
    private let thumbHeight: CGFloat = 44
    private let trackSpace = "libraryScrubberTrack"

    private var isDragging: Bool {
        dragFraction != nil
    }

    private var isShown: Bool {
        isRevealed || isDragging || isPointerNearby
    }

    private var scrubSection: LibrarySectionIndex.Section? {
        guard isDragging else { return nil }
        return sectionIndex?.section(containing: scrubIndex)
    }

    var body: some View {
        GeometryReader { proxy in
            let travel = max(proxy.size.height - hitSize.height, 1)
            let thumbOffset = CGFloat(dragFraction ?? scrollFraction) * travel

            ZStack(alignment: .topTrailing) {
                if isDragging {
                    bubble
                        .frame(height: hitSize.height)
                        .offset(x: -hitSize.width, y: thumbOffset)
                        .transition(.opacity)
                }
                thumb
                    .offset(y: thumbOffset)
                    .gesture(dragGesture(travel: travel))
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
        }
        .coordinateSpace(.named(trackSpace))
        .padding(.vertical, 8)
        .opacity(isShown ? 1 : 0)
        .allowsHitTesting(isShown)
        .animation(Motion.animation(Motion.controls, reduceMotion: reduceMotion), value: isShown)
        .animation(Motion.animation(Motion.controls, reduceMotion: reduceMotion), value: isDragging)
        .sensoryFeedback(.selection, trigger: scrubSection) { old, new in
            old != nil && new != nil && old != new
        }
        .sensoryFeedback(.impact(weight: .light), trigger: reachedEdge) { _, new in new != nil }
        .onChange(of: isScrolling) { _, scrolling in
            if scrolling {
                reveal()
            } else {
                scheduleHide()
            }
        }
        .onDisappear { hideTask?.cancel() }
        // VoiceOver users scroll with the system three-finger swipe.
        .accessibilityHidden(true)
    }

    private var thumb: some View {
        Capsule(style: .continuous)
            .fill(.textSecondary)
            .frame(width: isDragging ? 8 : 6, height: thumbHeight)
            .shadow(color: .black.opacity(0.3), radius: 4)
            .frame(width: hitSize.width, height: hitSize.height, alignment: .trailing)
            .padding(.trailing, 4)
            .contentShape(Rectangle())
    }

    @ViewBuilder
    private var bubble: some View {
        if let scrubSection {
            Text(verbatim: scrubSection.title)
                .font(.sectionTitle)
                .foregroundStyle(.textPrimary)
                .frame(width: 56, height: 56)
                .glassSurface(in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        } else {
            Text("library.browse.scrubber.position \(scrubIndex + 1, format: .number) \(totalCount, format: .number)")
                .font(.cardMetadata)
                .monospacedDigit()
                .foregroundStyle(.textPrimary)
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .glassSurface()
                .fixedSize()
        }
    }

    private func dragGesture(travel: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 0, coordinateSpace: .named(trackSpace))
            .onChanged { value in
                let isStart = !isDragging
                if isStart {
                    hideTask?.cancel()
                    onBegin()
                }
                let fraction = min(max(Double((value.location.y - hitSize.height / 2) / travel), 0), 1)
                dragFraction = fraction
                reachedEdge = fraction == 0 ? .top : fraction == 1 ? .bottom : nil
                let index = LibraryScrubberMapping.index(forFraction: fraction, totalCount: totalCount)
                guard isStart || index != scrubIndex else { return }
                scrubIndex = index
                onScrub(index)
            }
            .onEnded { _ in
                dragFraction = nil
                reachedEdge = nil
                onEnd(scrubIndex)
                scheduleHide()
            }
    }

    private func reveal() {
        hideTask?.cancel()
        isRevealed = true
    }

    private func scheduleHide() {
        hideTask?.cancel()
        hideTask = Task {
            try? await Task.sleep(for: .seconds(1.5))
            guard !Task.isCancelled else { return }
            isRevealed = false
        }
    }
}
