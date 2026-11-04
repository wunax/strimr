import SwiftUI

#if os(macOS)
    /// The guide grid in SwiftUI, for the Mac: rows build lazily and the pointer is forgiving enough without a custom
    /// focus engine.
    struct LiveTVGuideSwiftUIGrid: View {
        let model: LiveTVGuideGridModel
        let services: MediaServices
        let scrollRequest: LiveTVGuideScrollRequest?
        let actions: LiveTVGuideGridActions

        @State private var position = ScrollPosition()
        @State private var offset = CGPoint.zero
        @State private var viewportSize = CGSize.zero
        @State private var contentInsets = EdgeInsets()
        @State private var hoveredProgram: LiveTVProgramIdentity?

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
                    offset = rect.origin
                    viewportSize = rect.size
                    reportEdges(rect)
                }
                .onChange(of: model.start) { previous, start in
                    guard start < previous else { return }
                    // Earlier hours were added on the left: keep the same times on screen.
                    let shift = LiveTVGuideMetrics.width(of: previous.timeIntervalSince(start))
                    position.scrollTo(point: CGPoint(
                        x: offset.x + shift - contentInsets.leading,
                        y: offset.y - contentInsets.top,
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
                    let span = geometry.frame(of: program)
                    let frame = LiveTVGuideGeometry.visibleCellFrame(
                        CGRect(
                            x: span.x + 2,
                            y: 0,
                            width: max(span.width - 4, 2),
                            height: LiveTVGuideMetrics.rowHeight,
                        ),
                        scrollX: offset.x,
                    )
                    Button { actions.openProgram(program) } label: {
                        LiveTVGuideProgramCell(
                            program: program,
                            geometry: geometry,
                            tintsCategory: model.tintsCategories,
                            isFocused: hoveredProgram == program.identity,
                            now: now,
                        )
                    }
                    .buttonStyle(.plain)
                    .frame(width: frame.width, height: frame.height)
                    .offset(x: frame.minX)
                    .onHover { hovering in
                        if hovering {
                            hoveredProgram = program.identity
                            actions.focusProgram(program)
                        } else if hoveredProgram == program.identity {
                            hoveredProgram = nil
                        }
                    }
                    .contextMenu {
                        if program.isAiring(at: now) {
                            Button("livetv.watchLive", systemImage: "play.fill") { actions.openProgram(program) }
                        }
                        Button("livetv.program.details", systemImage: "info.circle") { actions.showDetails(program) }
                    }
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
                .offset(x: offset.x)
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
            guard viewportSize.width > 0 else { return programs }
            let margin = viewportSize.width / 2
            let minX = offset.x - margin
            let maxX = offset.x + viewportSize.width + margin
            return programs.filter { program in
                let span = geometry.frame(of: program)
                return span.x + span.width >= minX && span.x <= maxX
            }
        }

        private var ruler: some View {
            ZStack(alignment: .topLeading) {
                ForEach(geometry.slots, id: \.self) { slot in
                    LiveTVGuideRulerCell(date: slot)
                        .frame(width: LiveTVGuideMetrics.width(of: 1800), height: LiveTVGuideMetrics.rulerHeight)
                        .offset(x: geometry.x(for: slot))
                }
                LiveTVGuideCornerCell(date: geometry.date(atX: offset.x + LiveTVGuideMetrics.channelColumnWidth))
                    .frame(width: LiveTVGuideMetrics.channelColumnWidth, height: LiveTVGuideMetrics.rulerHeight)
                    .background(Color("Background"))
                    .offset(x: offset.x)
                    .zIndex(1)
            }
            .frame(width: geometry.contentWidth, height: LiveTVGuideMetrics.rulerHeight, alignment: .topLeading)
            .background(Color("Background"))
        }

        @ViewBuilder
        private func nowLine(now: Date) -> some View {
            let x = geometry.x(for: now)
            if now >= model.start, now < model.end, x >= offset.x + LiveTVGuideMetrics.channelColumnWidth {
                Rectangle()
                    .fill(.liveIndicator)
                    .frame(width: 2, height: max(viewportSize.height, 0))
                    .offset(x: x - 1, y: offset.y)
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
            }
        }

        private func scroll(to request: LiveTVGuideScrollRequest) {
            let visibleWidth = max(viewportSize.width - LiveTVGuideMetrics.channelColumnWidth, 0)
            let x = max(0, geometry.x(for: request.date) - LiveTVGuideMetrics.channelColumnWidth - visibleWidth * 0.1)
            var y = offset.y
            if let channel = request.channel, let row = model.row(of: channel) {
                y = max(
                    0,
                    CGFloat(row) * (LiveTVGuideMetrics.rowHeight + LiveTVGuideMetrics.rowSpacing) - viewportSize
                        .height / 3,
                )
            }
            position.scrollTo(point: CGPoint(x: x - contentInsets.leading, y: y - contentInsets.top))
        }

        private func reportEdges(_ rect: CGRect) {
            guard rect.width > 0 else { return }
            if rect.maxX > geometry.contentWidth - rect.width {
                actions.reachEdge(true)
            } else if rect.minX < rect.width / 2, model.start > Date().addingTimeInterval(-6 * 3600) {
                actions.reachEdge(false)
            }
        }
    }
#endif
