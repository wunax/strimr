import SwiftUI

struct MediaDetailTrackButtons: View {
    @Bindable var viewModel: MediaDetailViewModel
    var onSearchSubtitles: (() -> Void)?

    var body: some View {
        HStack(spacing: 12) {
            if viewModel.showsVersionSelection {
                Menu {
                    MediaDetailVersionMenuItems(viewModel: viewModel)
                } label: {
                    Label(viewModel.selectedVersionShortLabel, systemImage: "square.stack")
                }
                .disabled(viewModel.isUpdatingTracks)
                .help(Text("media.versions.title"))
                .accessibilityLabel(Text("media.versions.title"))
                .accessibilityValue(Text(viewModel.selectedVersionShortLabel))
            }

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
                .help(Text("player.settings.audio"))
                .accessibilityLabel(
                    Text(viewModel.selectedAudioTrackTitle ?? String(localized: "player.settings.audio")),
                )
            }

            if !viewModel.subtitleTracks.isEmpty
                || (onSearchSubtitles != nil && viewModel.canSearchSubtitles)
            {
                Menu {
                    subtitleTrackButtons
                } label: {
                    Label(viewModel.selectedSubtitleTrackTitle, systemImage: "captions.bubble")
                }
                .disabled(viewModel.isUpdatingTracks)
                .help(Text("player.settings.subtitles"))
                .accessibilityLabel(Text(viewModel.selectedSubtitleTrackTitle))
            }
        }
        .buttonStyle(.bordered)
        .tint(.secondary)
    }

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

        if let onSearchSubtitles, viewModel.canSearchSubtitles {
            Divider()
            Button(action: onSearchSubtitles) {
                Label("subtitles.search.action", systemImage: "magnifyingglass")
            }
            .tint(.secondary)
        }
    }

    private func trackLabel(_ track: MediaTrackMetadata, isSelected: Bool) -> some View {
        trackLabel(track.displayTitle, isSelected: isSelected)
    }

    private func trackLabel(_ title: String, isSelected: Bool) -> some View {
        Label(title, systemImage: isSelected ? "checkmark" : "circle")
    }
}

struct MediaDetailVersionMenuItems: View {
    @Bindable var viewModel: MediaDetailViewModel

    var body: some View {
        Button {
            Task { await viewModel.selectVersion(id: nil) }
        } label: {
            Label {
                if let automatic = viewModel.automaticVersion {
                    #if os(tvOS)
                        // tvOS menus drop the second line, so the target goes into the title.
                        Text("media.versions.automaticTarget \(automatic.displayLabel(among: viewModel.versions))")
                    #else
                        Text("media.versions.automatic")
                        Text(automatic.displayLabel(among: viewModel.versions))
                    #endif
                } else {
                    Text("media.versions.automatic")
                }
            } icon: {
                Image(systemName: viewModel.hasVersionPreference ? "circle" : "checkmark")
            }
        }

        Divider()

        let labels = viewModel.versionLabels
        ForEach(Array(viewModel.versions.enumerated()), id: \.offset) { index, version in
            Button {
                guard let id = version.id else { return }
                Task { await viewModel.selectVersion(id: id) }
            } label: {
                Label {
                    Text(verbatim: labels[index])
                    if version.isAvailable {
                        Text(verbatim: version.detailLabel)
                    } else {
                        Text("media.versions.unavailable")
                    }
                } icon: {
                    Image(systemName: isChecked(version) ? "checkmark" : "circle")
                }
            }
            .disabled(!version.isAvailable || version.id == nil)
        }
    }

    /// "Automatic" carries the checkmark until a version is picked explicitly.
    private func isChecked(_ version: MediaFileVersion) -> Bool {
        guard viewModel.hasVersionPreference else { return false }
        return viewModel.selectedVersionID.map { version.matchesVersionID($0) } ?? false
    }
}

struct MediaDetailTrackEllipsisMenu: View {
    @Bindable var viewModel: MediaDetailViewModel
    var onSearchSubtitles: (() -> Void)?

    var body: some View {
        Menu {
            MediaDetailTrackMenuItems(
                viewModel: viewModel,
                onSearchSubtitles: onSearchSubtitles,
            )
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
    var onSearchSubtitles: (() -> Void)?

    init(
        viewModel: MediaDetailViewModel,
        ratingKey: String? = nil,
        onSearchSubtitles: (() -> Void)? = nil,
    ) {
        self.viewModel = viewModel
        self.ratingKey = ratingKey
        self.onSearchSubtitles = onSearchSubtitles
    }

    var body: some View {
        if ratingKey == nil || ratingKey == viewModel.trackRatingKey {
            if viewModel.showsVersionSelection {
                Menu("media.versions.title", systemImage: "square.stack") {
                    MediaDetailVersionMenuItems(viewModel: viewModel)
                }
            }

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

            if !viewModel.subtitleTracks.isEmpty
                || (onSearchSubtitles != nil && viewModel.canSearchSubtitles)
            {
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

                    if let onSearchSubtitles, viewModel.canSearchSubtitles {
                        Divider()
                        Button(action: onSearchSubtitles) {
                            Label("subtitles.search.action", systemImage: "magnifyingglass")
                        }
                        .tint(.secondary)
                    }
                }
            }
        }
    }
}

struct MediaDetailTrackSummary: View {
    @Bindable var viewModel: MediaDetailViewModel
    var spacing: CGFloat = 16

    var body: some View {
        HStack(spacing: spacing) {
            if viewModel.showsVersionSelection {
                Label(viewModel.selectedVersionShortLabel, systemImage: "square.stack")
            }
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
