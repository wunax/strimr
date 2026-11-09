import SwiftUI

/// The channel list over the player: what is on each channel, to zap without leaving playback.
struct LiveTVChannelPanelView: View {
    let channels: [LiveTVChannel]
    let currentIndex: Int?
    let store: LiveTVStore?
    let onSelect: (Int) -> Void
    let onClose: () -> Void

    @State private var favoritesOnly = false
    @FocusState private var focusedIndex: Int?

    private let shape = RoundedRectangle(cornerRadius: LayoutMetrics.overlayCornerRadius, style: .continuous)

    private var entries: [(index: Int, channel: LiveTVChannel)] {
        channels.enumerated()
            .filter { !favoritesOnly || $0.element.isFavorite }
            .map { ($0.offset, $0.element) }
    }

    var body: some View {
        GeometryReader { proxy in
            HStack(spacing: 0) {
                Spacer(minLength: 0)
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Text("livetv.player.channels")
                            .font(.sectionTitle)
                            .foregroundStyle(.textPrimary)
                        Spacer(minLength: 8)
                        #if !os(tvOS)
                            Button("common.done", systemImage: "xmark", action: onClose)
                                .labelStyle(.iconOnly)
                                .buttonStyle(.borderless)
                                .foregroundStyle(.textSecondary)
                        #endif
                    }
                    HStack(spacing: LayoutMetrics.chipSpacing) {
                        Button { favoritesOnly = false } label: { Text("livetv.guide.filter.all") }
                            .buttonStyle(.chip(isSelected: !favoritesOnly))
                        Button { favoritesOnly = true } label: { Text("livetv.shelf.favorites") }
                            .buttonStyle(.chip(isSelected: favoritesOnly))
                    }
                    #if os(tvOS)
                    .focusSection()
                    #endif
                    ScrollViewReader { reader in
                        ScrollView {
                            LazyVStack(spacing: 8) {
                                ForEach(entries, id: \.index) { entry in
                                    row(entry.channel, index: entry.index)
                                        .id(entry.index)
                                }
                            }
                            .padding(.vertical, 8)
                            .padding(.horizontal, focusLiftInset)
                        }
                        .padding(.horizontal, -focusLiftInset)
                        .onAppear {
                            if let currentIndex {
                                reader.scrollTo(currentIndex, anchor: .center)
                                focusedIndex = currentIndex
                            }
                        }
                    }
                    #if os(tvOS)
                    .focusSection()
                    #endif
                }
                .padding(panelPadding)
                .frame(width: min(panelWidth, proxy.size.width * 0.9))
                .frame(maxHeight: .infinity)
                .overlayPanelSurface(in: shape)
                .padding(.vertical, 24)
                .padding(.trailing, 24)
            }
        }
        .environment(\.colorScheme, .dark)
        #if os(tvOS)
            .onExitCommand(perform: onClose)
        #endif
    }

    private func row(_ channel: LiveTVChannel, index: Int) -> some View {
        let program = store?.currentProgram(on: channel.identity)
        let isCurrent = index == currentIndex
        return Button { onSelect(index) } label: {
            HStack(spacing: 12) {
                ZStack {
                    Rectangle().fill(.surfaceSubtle)
                    if let path = program?.thumbPath ?? program?.artPath {
                        ArtworkPathView(path: path, width: 240, height: 135)
                    } else {
                        LiveTVChannelLogo(channel: channel)
                            .padding(6)
                    }
                }
                .frame(width: thumbnailWidth, height: thumbnailWidth * 9 / 16)
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                VStack(alignment: .leading, spacing: 4) {
                    Text(channel.displayTitle)
                        .font(.cardMetadata)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                    Text(program?.title ?? channel.title)
                        .font(.rowTitle)
                        .lineLimit(1)
                    if let program {
                        CardProgressBar(progress: program.progress)
                    }
                }
                Spacer(minLength: 0)
                if isCurrent {
                    Image(systemName: "checkmark")
                        .foregroundStyle(Color.selectionAccent)
                        .accessibilityLabel(Text("livetv.player.currentChannel"))
                }
            }
            .padding(8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .focused($focusedIndex, equals: index)
        #if os(tvOS)
            .buttonStyle(.bordered)
            .buttonBorderShape(.roundedRectangle(radius: 12))
        #else
            .buttonStyle(.plain)
            .background(isCurrent ? Color.surfaceRaised : .clear, in: RoundedRectangle(cornerRadius: 12))
        #endif
    }

    private var panelWidth: CGFloat {
        #if os(tvOS)
            720
        #else
            400
        #endif
    }

    /// Room for the focused row to grow without being clipped by the list.
    private var focusLiftInset: CGFloat {
        #if os(tvOS)
            12
        #else
            0
        #endif
    }

    private var panelPadding: CGFloat {
        #if os(tvOS)
            32
        #else
            16
        #endif
    }

    private var thumbnailWidth: CGFloat {
        #if os(tvOS)
            160
        #else
            96
        #endif
    }
}

/// What Live TV draws over the video, under the controls: the tuning screen and the zap banner.
struct LiveTVPlayerBackdrop: View {
    let viewModel: PlayerViewModel
    var hidesBanner = false

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// A channel arrived and its banner has not had its time on screen yet.
    @State private var showsZapBanner = false

    var body: some View {
        if viewModel.isLivePlayback, let services = viewModel.artworkServices, let channel = viewModel.liveChannel {
            let store = viewModel.liveStore
            let current = viewModel.liveProgram.flatMap { $0.isCurrentlyAiring ? $0 : nil }
                ?? store?.currentProgram(on: channel.identity)
            ZStack {
                if viewModel.isJoiningLive {
                    LiveTVJoinBackdropView(channel: channel, program: current)
                        .transition(.opacity)
                }
                if isBannerVisible {
                    LiveTVZapBannerView(
                        channel: channel,
                        current: current,
                        next: store?.nextProgram(on: channel.identity, after: current?.endDate ?? Date()),
                    )
                    .padding(32)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
            .allowsHitTesting(false)
            .environment(services)
            .animation(Motion.animation(Motion.controls, reduceMotion: reduceMotion), value: isBannerVisible)
            .animation(Motion.animation(Motion.crossfade, reduceMotion: reduceMotion), value: viewModel.isJoiningLive)
            .onChange(of: viewModel.liveChannelArrivals) { _, _ in
                showsZapBanner = true
            }
            .task(id: isBannerVisible) {
                // The banner waits for the controls to hide, then stays four seconds.
                guard isBannerVisible else { return }
                try? await Task.sleep(for: .seconds(4))
                guard !Task.isCancelled else { return }
                showsZapBanner = false
            }
        }
    }

    private var isBannerVisible: Bool {
        showsZapBanner && !hidesBanner && !viewModel.isJoiningLive
    }
}

/// The channel list over the player and the controls, with a scrim that closes it.
struct LiveTVChannelPanelOverlay: View {
    let viewModel: PlayerViewModel
    @Binding var isPresented: Bool
    let onSelectChannel: (Int) -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            if isPresented, let services = viewModel.artworkServices {
                Color.overlayScrim
                    .ignoresSafeArea()
                    .onTapGesture { isPresented = false }
                    .transition(.opacity)
                LiveTVChannelPanelView(
                    channels: viewModel.liveChannels,
                    currentIndex: viewModel.liveChannelIndex,
                    store: viewModel.liveStore,
                    onSelect: { index in
                        isPresented = false
                        onSelectChannel(index)
                    },
                    onClose: { isPresented = false },
                )
                .environment(services)
                .transition(.move(edge: .trailing))
            }
        }
        .animation(Motion.animation(Motion.panel, reduceMotion: reduceMotion), value: isPresented)
    }
}
