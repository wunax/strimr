import SwiftUI

#if os(iOS)
    import UIKit
#endif

#if os(iOS)
    private final class GuideScrollViewConfiguratorView: UIView {
        override func didMoveToWindow() {
            super.didMoveToWindow()
            configureScrollView()
        }

        override func layoutSubviews() {
            super.layoutSubviews()
            configureScrollView()
        }

        private func configureScrollView() {
            var ancestor = superview
            while let current = ancestor {
                if let scrollView = current as? UIScrollView {
                    scrollView.bounces = false
                    scrollView.alwaysBounceHorizontal = false
                    scrollView.alwaysBounceVertical = false
                    scrollView.isDirectionalLockEnabled = true
                    return
                }
                ancestor = current.superview
            }
        }
    }

    private struct GuideScrollViewConfigurator: UIViewRepresentable {
        func makeUIView(context _: Context) -> GuideScrollViewConfiguratorView {
            GuideScrollViewConfiguratorView(frame: .zero)
        }

        func updateUIView(_ view: GuideScrollViewConfiguratorView, context _: Context) {
            view.setNeedsLayout()
        }
    }
#endif

struct LiveTVGuideView: View {
    private enum FocusItem: Hashable {
        case favorite(LiveTVChannelIdentity)
        case channel(LiveTVChannelIdentity)
        case program(LiveTVProgramIdentity)
    }

    @Bindable var store: LiveTVStore
    let favoritesOnly: Bool
    let onTuneChannel: (LiveTVChannel) -> Void
    let onSelectProgram: (LiveTVProgram) -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    #if os(tvOS)
        @FocusState private var focusedGuideItem: FocusItem?
    #endif

    private var displayedChannels: [LiveTVChannel] {
        favoritesOnly ? store.channels.filter(\.isFavorite) : store.channels
    }

    var body: some View {
        VStack(spacing: 8) {
            guideNavigation

            if displayedChannels.isEmpty {
                LiveTVEmptyState("livetv.empty.favorites", systemImage: "star", message: store.errorMessage)
            } else {
                ScrollView([.horizontal, .vertical]) {
                    LazyVStack(alignment: .leading, spacing: 4, pinnedViews: [.sectionHeaders]) {
                        Section {
                            ForEach(displayedChannels) { channel in guideRow(channel) }
                        } header: {
                            guideHeader
                                .glassSurface(in: Rectangle())
                        }
                    }
                    .padding(.horizontal)
                    .overlay(alignment: .topLeading) {
                        TimelineView(.periodic(from: .now, by: 60)) { context in
                            if store.guideStart <= context.date, context.date < store.guideEnd {
                                Rectangle()
                                    .fill(.red)
                                    .frame(width: 2, height: CGFloat(displayedChannels.count * 68 + 28))
                                    .offset(
                                        x: 186 + context.date.timeIntervalSince(store.guideStart) / 15,
                                        y: 24,
                                    )
                                    .accessibilityHidden(true)
                            }
                        }
                    }
                    #if os(iOS)
                    .background(GuideScrollViewConfigurator())
                    #endif
                }
            }
        }
    }

    private var guideNavigation: some View {
        ViewThatFits(in: .horizontal) {
            ZStack {
                guideDateLabel
                    .fixedSize(horizontal: true, vertical: false)
                HStack(spacing: 12) {
                    Button("livetv.guide.previous", systemImage: "chevron.left") {
                        shiftGuide(hours: -6)
                    }
                    .fixedSize(horizontal: true, vertical: false)
                    Spacer(minLength: 8)
                    HStack(spacing: 12) {
                        Button("livetv.guide.now") {
                            Task { await store.jumpToNow() }
                        }
                        .fixedSize(horizontal: true, vertical: false)
                        Button("livetv.guide.next", systemImage: "chevron.right") {
                            shiftGuide(hours: 6)
                        }
                        .fixedSize(horizontal: true, vertical: false)
                    }
                }
            }

            ZStack {
                guideDateLabel
                    .minimumScaleFactor(0.8)
                HStack {
                    guideArrowButton(systemName: "chevron.left", label: "livetv.guide.previous") {
                        shiftGuide(hours: -6)
                    }
                    Spacer(minLength: 0)
                    HStack(spacing: 8) {
                        Button {
                            Task { await store.jumpToNow() }
                        } label: {
                            Image(systemName: "dot.circle")
                                .frame(minWidth: 44, minHeight: 44)
                        }
                        .accessibilityLabel(Text("livetv.guide.now"))
                        guideArrowButton(systemName: "chevron.right", label: "livetv.guide.next") {
                            shiftGuide(hours: 6)
                        }
                    }
                }
            }
        }
        .padding(.horizontal)
    }

    private var guideDateLabel: some View {
        Text(store.guideStart, format: .dateTime.weekday().month().day())
            .font(.facts.weight(.semibold))
            .foregroundStyle(.textPrimary)
            .lineLimit(1)
    }

    private func guideArrowButton(
        systemName: String,
        label: LocalizedStringKey,
        action: @escaping () -> Void,
    ) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .frame(minWidth: 44, minHeight: 44)
        }
        .accessibilityLabel(Text(label))
    }

    private func shiftGuide(hours: Int) {
        Task { await store.shiftGuide(hours: hours) }
    }

    private var guideHeader: some View {
        HStack(spacing: 0) {
            Text("livetv.channel").frame(width: 170, alignment: .leading)
            ForEach(0 ..< 12, id: \.self) { index in
                Text(store.guideStart.addingTimeInterval(Double(index) * 1800), format: .dateTime.hour().minute())
                    .frame(width: 120, alignment: .leading)
            }
        }
        .font(.cardMetadata)
        .foregroundStyle(.textSecondary)
    }

    private func guideRow(_ channel: LiveTVChannel) -> some View {
        #if os(tvOS)
            let isFavoriteFocused = focusedGuideItem == .favorite(channel.identity)
            let isChannelFocused = focusedGuideItem == .channel(channel.identity)
        #else
            let isFavoriteFocused = false
            let isChannelFocused = false
        #endif

        return HStack(spacing: 0) {
            HStack(spacing: 8) {
                Group {
                    #if os(tvOS)
                        guideFavoriteLabel(channel, isFocused: isFavoriteFocused)
                            .focusable()
                            .focused($focusedGuideItem, equals: .favorite(channel.identity))
                            .onTapGesture { Task { await store.toggleFavorite(channel) } }
                            .accessibilityAddTraits(.isButton)
                    #else
                        Button { Task { await store.toggleFavorite(channel) } } label: {
                            guideFavoriteLabel(channel, isFocused: false)
                        }
                        .buttonStyle(.plain)
                    #endif
                }
                .animation(Motion.focus, value: isFavoriteFocused)
                .accessibilityLabel(
                    Text(channel.isFavorite ? "livetv.favorite.remove" : "livetv.favorite.add"),
                )

                Group {
                    #if os(tvOS)
                        guideChannelLabel(channel, isFocused: isChannelFocused)
                            .focusable()
                            .focused($focusedGuideItem, equals: .channel(channel.identity))
                            .onTapGesture { onTuneChannel(channel) }
                            .accessibilityAddTraits(.isButton)
                    #else
                        Button { onTuneChannel(channel) } label: {
                            guideChannelLabel(channel, isFocused: false)
                        }
                        .buttonStyle(.plain)
                    #endif
                }
                .animation(Motion.focus, value: isChannelFocused)
                .accessibilityLabel(Text("livetv.channel.watch \(channel.displayTitle)"))
            }
            .frame(width: 160, alignment: .leading)

            let programs = store.programs
                .filter {
                    $0.channelIdentity == channel.identity && $0.endDate > store.guideStart && $0.startDate < store
                        .guideEnd
                }
            ZStack(alignment: .leading) {
                if programs.isEmpty {
                    Text("livetv.guide.noData")
                        .font(.cardMetadata)
                        .foregroundStyle(.textTertiary)
                } else {
                    ForEach(programs, id: \.identity) { program in
                        let visibleStart = max(program.startDate, store.guideStart)
                        let visibleEnd = min(program.endDate, store.guideEnd)
                        #if os(tvOS)
                            let isFocused = focusedGuideItem == .program(program.identity)
                        #else
                            let isFocused = false
                        #endif
                        Group {
                            #if os(tvOS)
                                guideProgramLabel(
                                    program,
                                    width: max(4, visibleEnd.timeIntervalSince(visibleStart) / 15 - 4),
                                    isFocused: isFocused,
                                )
                                .focusable()
                                .focused($focusedGuideItem, equals: .program(program.identity))
                                .onTapGesture { onSelectProgram(program) }
                                .accessibilityAddTraits(.isButton)
                            #else
                                Button { onSelectProgram(program) } label: {
                                    guideProgramLabel(
                                        program,
                                        width: max(4, visibleEnd.timeIntervalSince(visibleStart) / 15 - 4),
                                        isFocused: false,
                                    )
                                }
                                .buttonStyle(.plain)
                            #endif
                        }
                        .offset(x: visibleStart.timeIntervalSince(store.guideStart) / 15)
                        .zIndex(isFocused ? 1 : 0)
                        .animation(Motion.focus, value: isFocused)
                    }
                }
            }
            .frame(width: 1440, height: 64, alignment: .leading)
            .clipped()
        }
    }

    private func guideFavoriteLabel(_ channel: LiveTVChannel, isFocused: Bool) -> some View {
        Image(systemName: channel.isFavorite ? "star.fill" : "star")
            .foregroundStyle(channel.isFavorite ? .yellow : .textTertiary)
            .frame(width: 34, height: 34)
            .guideFocusAppearance(in: Circle(), isFocused: isFocused, scale: 1.08, reduceMotion: reduceMotion)
    }

    private func guideChannelLabel(_ channel: LiveTVChannel, isFocused: Bool) -> some View {
        Text(channel.displayTitle)
            .font(.cardTitle)
            .foregroundStyle(.textPrimary)
            .lineLimit(2)
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .frame(maxWidth: .infinity, alignment: .leading)
            .guideFocusAppearance(in: guideCellShape, isFocused: isFocused, scale: 1.025, reduceMotion: reduceMotion)
    }

    private func guideProgramLabel(_ program: LiveTVProgram, width: CGFloat, isFocused: Bool) -> some View {
        VStack(alignment: .leading) {
            HStack {
                Text(program.title)
                    .font(.cardTitle)
                    .foregroundStyle(.textPrimary)
                    .lineLimit(1)
                if program.recordingID != nil || program.seriesRecordingID != nil {
                    Image(systemName: "record.circle.fill").foregroundStyle(.red)
                }
            }
            Text(program.startDate, format: .dateTime.hour().minute())
                .font(.cardMetadata)
                .foregroundStyle(.textSecondary)
        }
        .padding(8)
        .frame(width: width, height: 64, alignment: .leading)
        .background(program.isCurrentlyAiring ? Color.surfaceRaised : Color.surfaceSubtle)
        .overlay(alignment: .bottomLeading) {
            if program.isCurrentlyAiring {
                Rectangle()
                    .fill(.progressFill)
                    .frame(width: width * min(max(program.progress, 0), 1), height: 3)
                    .accessibilityHidden(true)
            }
        }
        .clipShape(guideCellShape)
        .guideFocusAppearance(in: guideCellShape, isFocused: isFocused, scale: 1.025, reduceMotion: reduceMotion)
        .shadow(color: .black.opacity(isFocused ? 0.35 : 0), radius: 10, y: 5)
    }

    private var guideCellShape: RoundedRectangle {
        RoundedRectangle(cornerRadius: MediaArtworkMetrics.compactCornerRadius, style: .continuous)
    }
}

private extension View {
    /// Focus treatment of guide cells on tvOS, where they are focusable views rather than buttons.
    func guideFocusAppearance(
        in shape: some Shape,
        isFocused: Bool,
        scale: CGFloat,
        reduceMotion: Bool,
    ) -> some View {
        background {
            shape.fill(isFocused ? Color.surfaceRaised : Color.clear)
        }
        .overlay {
            shape.stroke(.textPrimary, lineWidth: isFocused ? 2 : 0)
        }
        .scaleEffect(isFocused && !reduceMotion ? scale : 1)
        .contentShape(shape)
    }
}
