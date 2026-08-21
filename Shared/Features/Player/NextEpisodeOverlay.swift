import SwiftUI

@MainActor
struct NextEpisodeOverlay: View {
    let presentation: NextEpisodePresentation
    let services: MediaServices
    let onPlay: (PlayerViewModel) async -> Void
    let onClose: () -> Void

    @FocusState private var focusedAction: Action?

    private enum Action: Hashable {
        case play
        case close
    }

    private var media: MediaItem? {
        presentation.nextMedia
    }

    var body: some View {
        ZStack {
            Color.black.opacity(0.62)
                .ignoresSafeArea()
                .contentShape(Rectangle())

            #if os(tvOS)
                tvLayout
            #elseif os(macOS)
                macLayout
            #else
                mobileLayout
            #endif
        }
        .task(id: presentation.generation) {
            presentation.startCountdown(onComplete: onPlay)
        }
        .onDisappear {
            presentation.cancelCountdown()
        }
        .zIndex(100)
    }

    private var artwork: some View {
        Group {
            if let media {
                MediaImageView(
                    viewModel: MediaImageViewModel(
                        services: services,
                        artworkKind: .art,
                        media: .playable(media),
                    ),
                )
            } else {
                Color.clear
            }
        }
        .environment(services)
        .mediaArtworkStyle(.standard)
    }

    private var episodeDetails: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("player.nextEpisode.upNext")
                .font(.headline)
                .foregroundStyle(.secondary)

            if let media {
                Text(media.primaryLabel)
                    .font(.title3.weight(.semibold))
                    .lineLimit(2)

                Text(media.title)
                    .font(.title2.weight(.bold))
                    .lineLimit(2)

                HStack(spacing: 8) {
                    if let episodeLabel = media.tertiaryLabel {
                        Text(episodeLabel)
                    }
                    if let duration = media.duration {
                        Text(duration.mediaDurationText())
                    }
                }
                .font(.subheadline)
                .foregroundStyle(.secondary)

                if let remaining = presentation.remainingSeconds {
                    Text(String(localized: "player.nextEpisode.playingIn \(remaining)"))
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.secondary)
                        .contentTransition(.numericText())
                }
            }
        }
    }

    private var actions: some View {
        HStack(spacing: 12) {
            Button {
                guard let next = presentation.playNow() else { return }
                Task { await onPlay(next) }
            } label: {
                Label("player.nextEpisode.playNow", systemImage: "play.fill")
            }
            .buttonStyle(.borderedProminent)
            #if os(tvOS)
                .focused($focusedAction, equals: .play)
            #endif
            #if os(macOS)
            .keyboardShortcut(.return, modifiers: [])
            .keyboardShortcut(.space, modifiers: [])
            #endif

            Button {
                presentation.cancel()
                onClose()
            } label: {
                Text("player.nextEpisode.close")
            }
            .buttonStyle(.bordered)
            .tint(.secondary)
            #if os(tvOS)
                .focused($focusedAction, equals: .close)
            #endif
        }
        .frame(maxWidth: .infinity)
        #if os(tvOS)
            .onMoveCommand { direction in
                switch direction {
                case .left where focusedAction == .close:
                    focusedAction = .play
                case .right where focusedAction == .play:
                    focusedAction = .close
                case .left, .right, .up, .down:
                    focusedAction = focusedAction ?? .play
                default:
                    break
                }
            }
        #endif
    }

    private var mobileLayout: some View {
        VStack {
            Spacer()

            mobileCard
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var mobileCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top, spacing: 16) {
                artwork
                    .frame(width: 180, height: 102)

                episodeDetails
            }

            actions
        }
        .padding(20)
        .frame(maxWidth: 520)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .padding(16)
    }

    private var tvLayout: some View {
        VStack {
            Spacer()

            HStack(alignment: .center, spacing: 28) {
                artwork
                    .frame(width: 300, height: 169)

                VStack(alignment: .leading, spacing: 18) {
                    episodeDetails
                    actions
                }
            }
            .padding(30)
            .frame(maxWidth: 1100)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 28, style: .continuous))
            .padding(.horizontal, 60)
            .padding(.bottom, 48)
        }
        .onAppear {
            DispatchQueue.main.async {
                focusedAction = .play
            }
        }
        .focusSection()
    }

    private var macLayout: some View {
        VStack {
            Spacer()
            HStack(alignment: .center, spacing: 16) {
                artwork
                    .frame(width: 210, height: 118)

                VStack(alignment: .leading, spacing: 12) {
                    episodeDetails
                    actions
                }
            }
            .padding(18)
            .frame(maxWidth: 580)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .padding(24)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
    }
}
