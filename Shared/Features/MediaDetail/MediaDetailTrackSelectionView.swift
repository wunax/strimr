import SwiftUI

struct MediaDetailTrackButtons: View {
    @Bindable var viewModel: MediaDetailViewModel

    var body: some View {
        HStack(spacing: 12) {
            if !viewModel.audioTracks.isEmpty {
                Menu {
                    audioTrackButtons
                } label: {
                    Label(
                        viewModel.selectedAudioTrackTitle ?? String(localized: "player.settings.audio"),
                        systemImage: "waveform",
                    )
                }
                .disabled(viewModel.isUpdatingTracks)
            }

            if !viewModel.subtitleTracks.isEmpty {
                Menu {
                    subtitleTrackButtons
                } label: {
                    Label(viewModel.selectedSubtitleTrackTitle, systemImage: "captions.bubble")
                }
                .disabled(viewModel.isUpdatingTracks)
            }
        }
        .buttonStyle(.bordered)
        .tint(.secondary)
    }

    @ViewBuilder
    private var audioTrackButtons: some View {
        ForEach(viewModel.audioTracks, id: \.self) { track in
            if let id = track.id {
                Button {
                    Task { await viewModel.selectAudioStream(id: id) }
                } label: {
                    trackLabel(track, isSelected: viewModel.selectedAudioStreamID == id)
                }
            }
        }
    }

    @ViewBuilder
    private var subtitleTrackButtons: some View {
        Button {
            Task { await viewModel.selectSubtitleStream(id: nil) }
        } label: {
            trackLabel(
                String(localized: "player.settings.subtitles.off"),
                isSelected: viewModel.selectedSubtitleStreamID == nil,
            )
        }

        ForEach(viewModel.subtitleTracks, id: \.self) { track in
            if let id = track.id {
                Button {
                    Task { await viewModel.selectSubtitleStream(id: id) }
                } label: {
                    trackLabel(track, isSelected: viewModel.selectedSubtitleStreamID == id)
                }
            }
        }
    }

    private func trackLabel(_ track: PlexPartStream, isSelected: Bool) -> some View {
        trackLabel(track.displayTitle, isSelected: isSelected)
    }

    private func trackLabel(_ title: String, isSelected: Bool) -> some View {
        Label(title, systemImage: isSelected ? "checkmark" : "circle")
    }
}

struct MediaDetailTrackEllipsisMenu: View {
    @Bindable var viewModel: MediaDetailViewModel

    var body: some View {
        Menu {
            MediaDetailTrackMenuItems(viewModel: viewModel)
        } label: {
            if viewModel.isUpdatingTracks {
                ProgressView()
            } else {
                Image(systemName: "ellipsis")
                    .font(.title2.weight(.semibold))
            }
        }
        .buttonStyle(.bordered)
        .controlSize(.regular)
        .tint(.secondary)
        .disabled(viewModel.isUpdatingTracks)
        .accessibilityLabel(Text("media.detail.tracks"))
    }
}

struct MediaDetailTrackMenuItems: View {
    @Bindable var viewModel: MediaDetailViewModel
    var ratingKey: String?

    init(viewModel: MediaDetailViewModel, ratingKey: String? = nil) {
        self.viewModel = viewModel
        self.ratingKey = ratingKey
    }

    var body: some View {
        if ratingKey == nil || ratingKey == viewModel.trackRatingKey {
            if !viewModel.audioTracks.isEmpty {
                Menu("player.settings.audio", systemImage: "waveform") {
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
                }
            }

            if !viewModel.subtitleTracks.isEmpty {
                Menu("player.settings.subtitles", systemImage: "captions.bubble") {
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
                }
            }
        }
    }
}

struct MediaDetailTrackSummary: View {
    @Bindable var viewModel: MediaDetailViewModel

    var body: some View {
        HStack(spacing: 16) {
            if let audioTitle = viewModel.selectedAudioTrackTitle {
                Label(audioTitle, systemImage: "waveform")
            }
            if !viewModel.subtitleTracks.isEmpty {
                Label(viewModel.selectedSubtitleTrackTitle, systemImage: "captions.bubble")
            }
        }
        .font(.footnote)
        .foregroundStyle(.secondary)
        .lineLimit(1)
        .accessibilityElement(children: .combine)
    }
}
