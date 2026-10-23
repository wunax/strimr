import SwiftUI

@MainActor
struct NextEpisodeOverlay: View {
    let presentation: NextEpisodePresentation
    let services: MediaServices
    let onPlay: (PlayerViewModel) async -> Void
    let onClose: () -> Void

    private var media: MediaItem? {
        presentation.nextMedia
    }

    var body: some View {
        PlayerPromptCard {
            episodeDetails
        } primaryAction: {
            Button {
                guard let next = presentation.playNow() else { return }
                Task { await onPlay(next) }
            } label: {
                Label("player.nextEpisode.playNow", systemImage: "play.fill")
            }
            #if os(macOS)
            .keyboardShortcut(.return, modifiers: [])
            .keyboardShortcut(.space, modifiers: [])
            #endif
        } secondaryAction: {
            Button {
                presentation.cancel()
                onClose()
            } label: {
                Text("player.nextEpisode.close")
            }
        } artwork: {
            artwork
        }
        .task(id: presentation.generation) {
            presentation.startCountdown(onComplete: onPlay)
        }
        .onDisappear {
            presentation.cancelCountdown()
        }
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
                .eyebrowStyle()
                .foregroundStyle(.textSecondary)

            if let media {
                Text(media.primaryLabel)
                    .font(.sectionTitle)
                    .lineLimit(2)

                Text(media.title)
                    .font(.tileTitle)
                    .lineLimit(2)

                HStack(spacing: 8) {
                    if let episodeLabel = media.tertiaryLabel {
                        Text(episodeLabel)
                    }
                    if let duration = media.duration {
                        Text(duration.mediaDurationText())
                    }
                }
                .font(.facts)
                .foregroundStyle(.textSecondary)

                if let remaining = presentation.remainingSeconds {
                    Text(String(localized: "player.nextEpisode.playingIn \(remaining)"))
                        .font(.facts.weight(.medium))
                        .foregroundStyle(.textSecondary)
                        .contentTransition(.numericText())
                }
            }
        }
        .foregroundStyle(.textPrimary)
    }
}
