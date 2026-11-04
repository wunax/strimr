import SwiftUI

#if os(macOS)
    /// The stretch of the guide that rows build, which only moves every half viewport so that scrolling does not
    /// rebuild them. It always reaches at least half a viewport past the visible part.
    struct LiveTVGuideVisibleWindow: Equatable {
        let bucket: Int
        let viewportWidth: CGFloat

        init(visibleRect: CGRect) {
            viewportWidth = visibleRect.width
            bucket = Int((visibleRect.minX / (visibleRect.width / 2)).rounded(.down))
        }

        func contains(x: CGFloat, width: CGFloat) -> Bool {
            let step = viewportWidth / 2
            return x + width >= CGFloat(bucket - 1) * step && x <= CGFloat(bucket + 4) * step
        }
    }

    /// The guide grid in SwiftUI, for the Mac: rows build lazily and the pointer is forgiving enough without a custom
    /// focus engine. The scroll position stays out of the view's state: what follows it is drawn by `visualEffect`,
    /// so a scroll tick does not run any body.
    struct LiveTVGuideSwiftUIGrid: View {
        let model: LiveTVGuideGridModel
        let services: MediaServices
        let scrollRequest: LiveTVGuideScrollRequest?
        let actions: LiveTVGuideGridActions

        @State private var position = ScrollPosition()
        @State private var tracker = ScrollTracker()
        @State private var visibleWindow: LiveTVGuideVisibleWindow?
        @State private var visibleDay: Date?
        @State private var contentInsets = EdgeInsets()

        private var geometry: LiveTVGuideGeometry {
            model.geometry
        }

        var body: some View {
            TimelineView(.periodic(from: .now, by: 30)) { context in
                ScrollView([.horizontal, .vertical]) {
                    LazyVStack(
                        alignment: .leading,
                        spacing: LiveTVGuideMetrics.rowSpacing,
                        pinnedViews: [.sectionHeaders],
                    ) {
                        Section {
                            ForEach(Array(model.channels.enumerated()), id: \.element.id) { row, channel in
                                rowView(row: row, channel: channel, now: context.date)
                            }
                        } header: {
                            ruler
                        }
                    }
                    .frame(width: geometry.contentWidth, alignment: .leading)
                    .overlay(alignment: .topLeading) {
                        nowLine(now: context.date)
                    }
                }
                .scrollPosition($position)
                .onScrollGeometryChange(for: EdgeInsets.self, of: \.contentInsets) { _, insets in
                    contentInsets = insets
                }
                .onScrollGeometryChange(for: CGRect.self, of: { geometry in
                    // The sidebar floats over the grid: the visible part starts after the content insets.
                    CGRect(
                        x: geometry.contentOffset.x + geometry.contentInsets.leading,
                        y: geometry.contentOffset.y + geometry.contentInsets.top,
                        width: geometry.containerSize.width - geometry.contentInsets.leading,
                        height: geometry.containerSize.height - geometry.contentInsets.top,
                    )
                }) { _, rect in
                    tracker.visibleRect = rect
                    guard rect.width > 0 else { return }
                    let window = LiveTVGuideVisibleWindow(visibleRect: rect)
                    if window != visibleWindow {
                        visibleWindow = window
                    }
                    let day = Calendar.current.startOfDay(
                        for: geometry.date(atX: rect.minX + LiveTVGuideMetrics.channelColumnWidth),
                    )
                    if day != visibleDay {
                        visibleDay = day
                    }
                    reportEdges(rect)
                }
                .onChange(of: model.start) { previous, start in
                    guard start < previous else { return }
                    // Earlier hours were added on the left: keep the same times on screen.
                    let shift = LiveTVGuideMetrics.width(of: previous.timeIntervalSince(start))
                    position.scrollTo(point: CGPoint(
                        x: tracker.visibleRect.minX + shift - contentInsets.leading,
                        y: tracker.visibleRect.minY - contentInsets.top,
                    ))
                }
                .onChange(of: scrollRequest) { _, request in
                    guard let request else { return }
                    scroll(to: request)
                }
                .onAppear {
                    if let scrollRequest {
                        scroll(to: scrollRequest)
                    }
                }
            }
        }

        private func rowView(row: Int, channel: LiveTVChannel, now: Date) -> some View {
            ZStack(alignment: .topLeading) {
                ForEach(visiblePrograms(in: row), id: \.identity) { program in
                    LiveTVGuideSwiftUIProgramButton(
                        program: program,
                        geometry: geometry,
                        tintsCategory: model.tintsCategories,
                        tracker: tracker,
                        now: now,
                        actions: actions,
                    )
                }

                Button { actions.tuneChannel(channel) } label: {
                    LiveTVGuideChannelCell(
                        channel: channel,
                        isPlaying: channel.identity == model.playingChannel,
                        isFocused: false,
                    )
                }
                .buttonStyle(.plain)
                .frame(
                    width: LiveTVGuideMetrics.channelColumnWidth - LiveTVGuideMetrics.channelColumnGap,
                    height: LiveTVGuideMetrics.rowHeight,
                )
                .frame(width: LiveTVGuideMetrics.channelColumnWidth, alignment: .leading)
                // Programs scroll under the fixed column.
                .background(Color("Background"))
                .pinnedToLeadingEdge()
                .contextMenu {
                    Button("livetv.watchLive", systemImage: "play.fill") { actions.tuneChannel(channel) }
                    Button(
                        channel.isFavorite ? "livetv.favorite.remove" : "livetv.favorite.add",
                        systemImage: channel.isFavorite ? "star.slash" : "star",
                    ) { actions.toggleFavorite(channel) }
                }
                .zIndex(1)
            }
            .frame(width: geometry.contentWidth, height: LiveTVGuideMetrics.rowHeight, alignment: .topLeading)
        }

        /// Rows only build the programs near the viewport: the loaded window can span a day of programs per channel.
        private func visiblePrograms(in row: Int) -> [LiveTVProgram] {
            let programs = model.rows[row]
            guard let visibleWindow else { return programs }
            return programs.filter { program in
                let span = geometry.frame(of: program)
                return visibleWindow.contains(x: span.x, width: span.width)
            }
        }

        private var ruler: some View {
            ZStack(alignment: .topLeading) {
                ForEach(visibleSlots, id: \.self) { slot in
                    LiveTVGuideRulerCell(date: slot)
                        .frame(width: LiveTVGuideMetrics.width(of: 1800), height: LiveTVGuideMetrics.rulerHeight)
                        .offset(x: geometry.x(for: slot))
                }
                LiveTVGuideCornerCell(date: visibleDay ?? model.start)
                    .frame(width: LiveTVGuideMetrics.channelColumnWidth, height: LiveTVGuideMetrics.rulerHeight)
                    .background(Color("Background"))
                    .pinnedToLeadingEdge()
                    .zIndex(1)
            }
            .frame(width: geometry.contentWidth, height: LiveTVGuideMetrics.rulerHeight, alignment: .topLeading)
            .background(Color("Background"))
        }

        private var visibleSlots: [Date] {
            let slots = geometry.slots
            guard let visibleWindow else { return slots }
            let width = LiveTVGuideMetrics.width(of: 1800)
            return slots.filter { visibleWindow.contains(x: geometry.x(for: $0), width: width) }
        }

        @ViewBuilder
        private func nowLine(now: Date) -> some View {
            if now >= model.start, now < model.end {
                let columnEdge = LiveTVGuideMetrics.channelColumnWidth
                Rectangle()
                    .fill(.liveIndicator)
                    .frame(width: 2)
                    .frame(maxHeight: .infinity)
                    // Hidden once scrolled behind the fixed column.
                    .visualEffect { content, proxy in
                        content.opacity(proxy.frame(in: .scrollView).minX >= columnEdge ? 1 : 0)
                    }
                    .offset(x: geometry.x(for: now) - 1)
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
            }
        }

        private func scroll(to request: LiveTVGuideScrollRequest) {
            let visible = tracker.visibleRect
            let visibleWidth = max(visible.width - LiveTVGuideMetrics.channelColumnWidth, 0)
            let x = max(0, geometry.x(for: request.date) - LiveTVGuideMetrics.channelColumnWidth - visibleWidth * 0.1)
            var y = visible.minY
            if let channel = request.channel, let row = model.row(of: channel) {
                y = max(
                    0,
                    CGFloat(row) * (LiveTVGuideMetrics.rowHeight + LiveTVGuideMetrics.rowSpacing) - visible.height / 3,
                )
            }
            position.scrollTo(point: CGPoint(x: x - contentInsets.leading, y: y - contentInsets.top))
        }

        private func reportEdges(_ rect: CGRect) {
            if rect.maxX > geometry.contentWidth - rect.width {
                actions.reachEdge(true)
            } else if rect.minX < rect.width / 2, model.start > Date().addingTimeInterval(-6 * 3600) {
                actions.reachEdge(false)
            }
        }
    }

    /// The last scroll geometry. A view reading it from its body redraws on every scroll tick, so only the hovered
    /// program does.
    @Observable
    private final class ScrollTracker {
        var visibleRect = CGRect.zero
    }

    /// A program of the grid. It keeps its hover state to itself, so that moving the pointer only redraws this cell.
    private struct LiveTVGuideSwiftUIProgramButton: View {
        let program: LiveTVProgram
        let geometry: LiveTVGuideGeometry
        let tintsCategory: Bool
        let tracker: ScrollTracker
        let now: Date
        let actions: LiveTVGuideGridActions

        @State private var isHovered = false

        /// At rest the cell runs under the channel column; hovered, it stops at its edge to keep its highlight whole.
        private var frame: CGRect {
            let span = geometry.frame(of: program)
            let frame = CGRect(
                x: span.x + 2,
                y: 0,
                width: max(span.width - 4, 2),
                height: LiveTVGuideMetrics.rowHeight,
            )
            guard isHovered else { return frame }
            return LiveTVGuideGeometry.visibleCellFrame(frame, scrollX: tracker.visibleRect.minX)
        }

        var body: some View {
            let frame = frame
            Button { actions.openProgram(program) } label: {
                LiveTVGuideProgramCell(
                    program: program,
                    geometry: geometry,
                    tintsCategory: tintsCategory,
                    isFocused: isHovered,
                    now: now,
                    stickyTitleEdge: LiveTVGuideMetrics.channelColumnWidth,
                )
            }
            .buttonStyle(.plain)
            .frame(width: frame.width, height: frame.height)
            .offset(x: frame.minX)
            .onHover { hovering in
                isHovered = hovering
                if hovering {
                    actions.focusProgram(program)
                }
            }
            .contextMenu {
                if program.isAiring(at: now) {
                    Button("livetv.watchLive", systemImage: "play.fill") { actions.openProgram(program) }
                }
                Button("livetv.program.details", systemImage: "info.circle") { actions.showDetails(program) }
            }
        }
    }

    private extension View {
        /// Keeps a view at the leading edge of the visible part of the scroll view. The scroll view's coordinates
        /// already start after its content insets, so the floating sidebar needs no correction here.
        func pinnedToLeadingEdge() -> some View {
            visualEffect { content, proxy in
                content.offset(x: -proxy.frame(in: .scrollView).minX)
            }
        }
    }
#endif
