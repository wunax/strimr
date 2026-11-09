import SwiftUI

/// Version, audio and subtitle choices under the detail actions. Each pill shows what will play and opens its own
/// list; a pill only appears when there is something to choose. Other editions follow, as they open another page.
struct DetailTrackPickers: View {
    @Bindable var viewModel: MediaDetailViewModel
    let onSearchSubtitles: () -> Void

    var body: some View {
        if showsVersion || showsAudio || showsSubtitles || showsEditions {
            HStack(spacing: 16) {
                if showsVersion {
                    pill(title: versionTitle, systemImage: "film.stack", accessibilityLabel: "media.versions.title") {
                        MediaDetailVersionMenuItems(viewModel: viewModel)
                    }
                }
                if showsAudio, let audioTitle = viewModel.selectedAudioTrackTitle {
                    pill(
                        title: audioTitle,
                        systemImage: "speaker.wave.2.fill",
                        accessibilityLabel: "player.settings.audio",
                    ) {
                        MediaDetailAudioMenuItems(viewModel: viewModel)
                    }
                }
                if showsSubtitles {
                    pill(
                        title: viewModel.selectedSubtitleTrackTitle,
                        systemImage: "captions.bubble.fill",
                        accessibilityLabel: "player.settings.subtitles",
                    ) {
                        MediaDetailSubtitleMenuItems(viewModel: viewModel, onSearchSubtitles: onSearchSubtitles)
                    }
                }
                OtherEditionsButton(viewModel: viewModel)
            }
            .disabled(viewModel.isUpdatingTracks)
            // Full width so moving up from the right side of a rail below still lands on a pill.
            .frame(maxWidth: .infinity, alignment: .leading)
            .focusSection()
        }
    }

    private var showsVersion: Bool {
        viewModel.showsVersionSelection
    }

    private var showsEditions: Bool {
        !viewModel.otherEditions.isEmpty
    }

    private var showsAudio: Bool {
        viewModel.audioTracks.count > 1
    }

    private var showsSubtitles: Bool {
        !viewModel.subtitleTracks.isEmpty || viewModel.canSearchSubtitles
    }

    private var versionTitle: String {
        let badges = viewModel.selectedVersion?.badgeLabels ?? []
        return badges.isEmpty ? viewModel.selectedVersionShortLabel : badges.joined(separator: " · ")
    }

    private func pill(
        title: String,
        systemImage: String,
        accessibilityLabel: LocalizedStringKey,
        @ViewBuilder content: () -> some View,
    ) -> some View {
        Menu(content: content) {
            // Hierarchical styles, not the white theme tokens, so the content turns dark with the focused pill.
            HStack(spacing: 10) {
                Image(systemName: systemImage)
                    .foregroundStyle(.secondary)
                Text(verbatim: title)
                    .lineLimit(1)
                Image(systemName: "chevron.down")
                    .font(.cardMetadata.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
            .font(.cardMetadata)
        }
        .buttonStyle(.bordered)
        .buttonBorderShape(.capsule)
        .controlSize(.small)
        .menuIndicator(.hidden)
        .accessibilityLabel(Text(accessibilityLabel))
        .accessibilityValue(Text(verbatim: title))
    }
}
