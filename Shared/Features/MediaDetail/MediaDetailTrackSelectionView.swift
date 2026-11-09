import SwiftUI

struct MediaDetailVersionMenuItems: View {
    @Bindable var viewModel: MediaDetailViewModel

    var body: some View {
        Button {
            Task { await viewModel.selectVersion(id: nil) }
        } label: {
            Label("media.versions.automatic", systemImage: viewModel.hasVersionPreference ? "circle" : "checkmark")
            if let automatic = viewModel.automaticVersion {
                Text(automatic.displayLabel(among: viewModel.versions))
            }
        }

        Divider()

        let labels = viewModel.versionLabels
        ForEach(Array(viewModel.versions.enumerated()), id: \.offset) { index, version in
            Button {
                guard let id = version.id else { return }
                Task { await viewModel.selectVersion(id: id) }
            } label: {
                Label(labels[index], systemImage: isChecked(version) ? "checkmark" : "circle")
                if version.isAvailable {
                    Text(verbatim: version.detailLabel)
                } else {
                    Text("media.versions.unavailable")
                }
            }
            .disabled(!version.isAvailable || version.id == nil)
        }

        if viewModel.listsCopiesWithVersions {
            MediaCopiesMenuItems(viewModel: viewModel)
        }
    }

    /// "Automatic" carries the checkmark until a version is picked explicitly.
    private func isChecked(_ version: MediaFileVersion) -> Bool {
        guard viewModel.hasVersionPreference else { return false }
        return viewModel.selectedVersionID.map { version.matchesVersionID($0) } ?? false
    }
}

/// Copies on other servers or libraries open their own page; offline copies are greyed out.
struct MediaCopiesMenuItems: View {
    let viewModel: MediaDetailViewModel

    var body: some View {
        ForEach(viewModel.copiesByServer, id: \.serverName) { group in
            Section(String(localized: "media.availableOn \(group.serverName)")) {
                ForEach(group.copies) { copy in
                    Button {
                        viewModel.selectCopy(copy)
                    } label: {
                        Label(copy.media.playbackResolutionLabel ?? copy.media.title, systemImage: "server.rack")
                        if !copy.isReachable {
                            Text("media.availableOn.offline")
                        }
                    }
                    .disabled(!copy.isReachable)
                }
            }
        }
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
                Menu("media.versions.title", systemImage: "film.stack") {
                    MediaDetailVersionMenuItems(viewModel: viewModel)
                }
            }

            if !viewModel.audioTracks.isEmpty {
                Menu("player.settings.audio", systemImage: "waveform") {
                    MediaDetailAudioMenuItems(viewModel: viewModel)
                }
            }

            if !viewModel.subtitleTracks.isEmpty
                || (onSearchSubtitles != nil && viewModel.canSearchSubtitles)
            {
                Menu("player.settings.subtitles", systemImage: "captions.bubble") {
                    MediaDetailSubtitleMenuItems(viewModel: viewModel, onSearchSubtitles: onSearchSubtitles)
                }
            }
        }
    }
}

struct MediaDetailAudioMenuItems: View {
    @Bindable var viewModel: MediaDetailViewModel

    var body: some View {
        ForEach(viewModel.audioTracks, id: \.self) { track in
            if let id = track.id {
                Button {
                    Task { await viewModel.selectAudioStream(id: id) }
                } label: {
                    MediaTrackMenuLabel(track: track, isSelected: viewModel.selectedAudioStreamID == id)
                }
            }
        }
    }
}

struct MediaDetailSubtitleMenuItems: View {
    @Bindable var viewModel: MediaDetailViewModel
    var onSearchSubtitles: (() -> Void)?

    var body: some View {
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
                    MediaTrackMenuLabel(track: track, isSelected: viewModel.selectedSubtitleStreamID == id)
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

struct MediaTrackMenuLabel: View {
    let track: MediaTrackMetadata
    let isSelected: Bool

    var body: some View {
        Label(track.displayTitle, systemImage: iconName)
        if let secondaryTitle = track.secondaryTitle {
            Text(verbatim: secondaryTitle)
        }
    }

    private var iconName: String {
        isSelected ? "checkmark" : "circle"
    }
}
