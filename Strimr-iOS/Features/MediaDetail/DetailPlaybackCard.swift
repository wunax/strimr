import SwiftUI

/// Version, audio and subtitle choices for what will play, as Settings-style rows that open the existing menus.
struct DetailPlaybackCard: View {
    @Bindable var viewModel: MediaDetailViewModel
    let isServerUnreachable: Bool
    let onSearchSubtitles: () -> Void

    var body: some View {
        if showsSkeleton {
            skeleton
        } else if !rows.isEmpty {
            VStack(spacing: 0) {
                ForEach(Array(rows.enumerated()), id: \.element) { index, row in
                    if index > 0 {
                        Divider()
                            .padding(.leading, 52)
                    }
                    menu(for: row)
                }
            }
            .background(.surfaceSubtle, in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .disabled(viewModel.isUpdatingTracks)
        }
    }

    private enum Row: Hashable { case version, audio, subtitles }

    private let cornerRadius: CGFloat = 14
    private let rowHeight: CGFloat = 48

    private var rows: [Row] {
        var rows: [Row] = []
        if viewModel.showsVersionSelection {
            rows.append(.version)
        }
        if !viewModel.audioTracks.isEmpty {
            rows.append(.audio)
        }
        if !viewModel.subtitleTracks.isEmpty || (viewModel.canSearchSubtitles && !isServerUnreachable) {
            rows.append(.subtitles)
        }
        return rows
    }

    /// Keeps the space of the card while the tracks of a playable item load, so the page does not jump.
    private var showsSkeleton: Bool {
        rows.isEmpty && viewModel.isLoadingTracks && [.movie, .episode].contains(viewModel.media.type)
    }

    private var skeleton: some View {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            .fill(.surfaceSubtle)
            .frame(height: rowHeight * 2)
            .accessibilityLabel(Text("common.loading"))
    }

    @ViewBuilder
    private func menu(for row: Row) -> some View {
        switch row {
        case .version:
            Menu {
                MediaDetailVersionMenuItems(viewModel: viewModel)
            } label: {
                rowLabel("media.versions.title", systemImage: "film.stack", value: viewModel.selectedVersionShortLabel)
            }
        case .audio:
            Menu {
                audioMenuItems
            } label: {
                rowLabel(
                    "player.settings.audio",
                    systemImage: "waveform",
                    value: viewModel.selectedAudioTrackTitle ?? "",
                )
            }
        case .subtitles:
            Menu {
                subtitleMenuItems
            } label: {
                rowLabel(
                    "player.settings.subtitles",
                    systemImage: "captions.bubble",
                    value: viewModel.selectedSubtitleTrackTitle,
                )
            }
        }
    }

    private func rowLabel(_ title: LocalizedStringKey, systemImage: String, value: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: systemImage)
                .font(.body.weight(.semibold))
                .foregroundStyle(.textSecondary)
                .frame(width: 28)
            Text(title)
                .foregroundStyle(.textPrimary)
            Spacer(minLength: 12)
            if viewModel.isUpdatingTracks {
                ProgressView()
            } else {
                Text(verbatim: value)
                    .foregroundStyle(.textSecondary)
                    .lineLimit(1)
            }
            Image(systemName: "chevron.up.chevron.down")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.textTertiary)
        }
        .font(.subheadline)
        .padding(.horizontal, 12)
        .frame(minHeight: rowHeight)
        .contentShape(Rectangle())
    }

    private var audioMenuItems: some View {
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

    @ViewBuilder
    private var subtitleMenuItems: some View {
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
        }
    }
}
