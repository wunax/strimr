import SwiftUI

/// Version, audio and subtitle choices for what will play.
struct DetailPlaybackCard: View {
    @Bindable var viewModel: MediaDetailViewModel
    let isServerUnreachable: Bool
    let onSearchSubtitles: () -> Void

    var body: some View {
        if viewModel.showsVersionSelection {
            versionButton
        }

        if !viewModel.audioTracks.isEmpty {
            audioTrackButton
        }

        if !viewModel.subtitleTracks.isEmpty || (viewModel.canSearchSubtitles && !isServerUnreachable) {
            subtitleTrackButton
        }
    }

    private var versionButton: some View {
        VStack(spacing: 2) {
            Menu {
                MediaDetailVersionMenuItems(viewModel: viewModel)
            } label: {
                if viewModel.isUpdatingTracks {
                    ProgressView()
                } else {
                    Image(systemName: "film.stack")
                        .font(.headline.weight(.semibold))
                }
            }
            .frame(width: 48, height: 44)
            .buttonStyle(.bordered)
            .controlSize(.regular)
            .tint(.brandSecondary)
            .disabled(viewModel.isUpdatingTracks)
            .accessibilityLabel(Text("media.versions.title"))
            .accessibilityValue(Text(viewModel.selectedVersionShortLabel))

            Text(verbatim: viewModel.selectedVersionShortLabel)
                .font(.caption2)
                .foregroundStyle(.primary)
                .frame(maxWidth: 56)
                .multilineTextAlignment(.center)
                .lineLimit(2)
        }
    }

    private var audioTrackButton: some View {
        VStack(spacing: 2) {
            Menu {
                ForEach(viewModel.audioTracks, id: \.self) { track in
                    if let id = track.id {
                        Button {
                            Task { await viewModel.selectAudioStream(id: id) }
                        } label: {
                            Label(
                                track.displayTitle,
                                systemImage: viewModel.selectedAudioStreamID == id ? "checkmark" : "circle",
                            )
                        }
                    }
                }
            } label: {
                if viewModel.isUpdatingTracks {
                    ProgressView()
                } else {
                    Image(systemName: "waveform")
                        .font(.headline.weight(.semibold))
                }
            }
            .frame(width: 48, height: 44)
            .buttonStyle(.bordered)
            .controlSize(.regular)
            .tint(.brandSecondary)
            .disabled(viewModel.isUpdatingTracks)

            Text("player.settings.audio")
                .font(.caption2)
                .foregroundStyle(.primary)
                .frame(maxWidth: 48)
                .multilineTextAlignment(.center)
                .lineLimit(2)
        }
    }

    private var subtitleTrackButton: some View {
        VStack(spacing: 2) {
            Menu {
                Button {
                    Task { await viewModel.selectSubtitleStream(id: nil) }
                } label: {
                    Label(
                        String(localized: "player.settings.subtitles.off"),
                        systemImage: viewModel.selectedSubtitleStreamID == nil ? "checkmark" : "circle",
                    )
                }

                ForEach(viewModel.subtitleTracks, id: \.self) { track in
                    if let id = track.id {
                        Button {
                            Task { await viewModel.selectSubtitleStream(id: id) }
                        } label: {
                            Label(
                                track.displayTitle,
                                systemImage: viewModel.selectedSubtitleStreamID == id ? "checkmark" : "circle",
                            )
                        }
                    }
                }

                if viewModel.canSearchSubtitles {
                    Divider()
                    Button(action: onSearchSubtitles) {
                        Label("subtitles.search.action", systemImage: "magnifyingglass")
                    }
                    .tint(.secondary)
                }
            } label: {
                if viewModel.isUpdatingTracks {
                    ProgressView()
                } else {
                    Image(systemName: "captions.bubble")
                        .font(.headline.weight(.semibold))
                }
            }
            .frame(width: 48, height: 44)
            .buttonStyle(.bordered)
            .controlSize(.regular)
            .tint(.brandSecondary)
            .disabled(viewModel.isUpdatingTracks)

            Text("player.settings.subtitles")
                .font(.caption2)
                .foregroundStyle(.primary)
                .frame(maxWidth: 56)
                .multilineTextAlignment(.center)
                .lineLimit(2)
        }
    }
}
