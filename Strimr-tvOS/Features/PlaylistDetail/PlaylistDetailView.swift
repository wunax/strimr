import Observation
import SwiftUI

struct PlaylistDetailView: View {
    @Environment(MediaServices.self) private var mediaServices
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.dismiss) private var dismiss
    @State var viewModel: PlaylistDetailViewModel
    @State private var isRenaming = false
    @State private var isConfirmingDeletion = false
    let onSelectMedia: (MediaDisplayItem) -> Void
    let onPlay: (String) -> Void
    let onShuffle: (String) -> Void
    let onPlayEntry: (PlaylistEntry) -> Void

    init(
        viewModel: PlaylistDetailViewModel,
        onSelectMedia: @escaping (MediaDisplayItem) -> Void = { _ in },
        onPlay: @escaping (String) -> Void = { _ in },
        onShuffle: @escaping (String) -> Void = { _ in },
        onPlayEntry: @escaping (PlaylistEntry) -> Void = { _ in },
    ) {
        _viewModel = State(initialValue: viewModel)
        self.onSelectMedia = onSelectMedia
        self.onPlay = onPlay
        self.onShuffle = onShuffle
        self.onPlayEntry = onPlayEntry
    }

    var body: some View {
        @Bindable var bindableViewModel = viewModel

        ScrollView {
            VStack(alignment: .leading, spacing: 48) {
                headerSection

                if viewModel.entries.isEmpty {
                    PlaylistEntriesPlaceholder(viewModel: viewModel)
                        .focusSection()
                } else {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        ForEach(Array(viewModel.entries.enumerated()), id: \.element.id) { index, entry in
                            PlaylistEntryRow(entry: entry, position: index + 1, lastPosition: viewModel.entries.count) {
                                onPlayEntry(entry)
                            }
                            .contextMenu { entryMenu(entry) }
                        }
                    }
                    .focusSection()
                }
            }
            .padding(.trailing, LayoutMetrics.pageMargin)
            .padding(.top, 32)
            .padding(.bottom, 48)
        }
        .toolbar(.hidden, for: .tabBar)
        .playlistNamePrompt(
            isPresented: $isRenaming,
            title: "playlist.rename.title",
            confirmTitle: "playlist.rename.action",
            initialName: viewModel.playlist.title,
        ) { title in
            Task { await viewModel.rename(to: title) }
        }
        .playlistDeleteConfirmation(isPresented: $isConfirmingDeletion, playlistTitle: viewModel.playlist.title) {
            Task {
                if await viewModel.delete() {
                    dismiss()
                }
            }
        }
        .playlistActionFailureAlert($bindableViewModel.actionFailure)
        .task {
            await viewModel.load()
        }
        .onAppear {
            Task { await viewModel.refreshIfNeeded() }
        }
        .onChange(of: scenePhase) { _, newValue in
            guard newValue == .active else { return }
            Task { await viewModel.refreshIfNeeded() }
        }
    }

    private var headerSection: some View {
        HStack(alignment: .top, spacing: 32) {
            MediaImageView(
                viewModel: MediaImageViewModel(
                    services: mediaServices,
                    artworkKind: .thumb,
                    media: viewModel.playlistDisplayItem,
                ),
            )
            .frame(width: 280, height: 420)
            .mediaArtworkStyle(.largeDetail, borderColor: .white.opacity(0.08))

            VStack(alignment: .leading, spacing: 32) {
                PlaylistHeaderDetails(viewModel: viewModel)

                playButtonsRow
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .focusSection()
    }

    private var playButtonsRow: some View {
        HStack(spacing: 16) {
            Button {
                onPlay(viewModel.playlist.id)
            } label: {
                Label("common.actions.play", systemImage: "play.fill")
                    .font(.facts.weight(.semibold))
                    .padding(.horizontal, 12)
            }
            .actionButtonStyle(.primary)
            .disabled(viewModel.entries.isEmpty)

            Button {
                onShuffle(viewModel.playlist.id)
            } label: {
                Label("common.actions.shuffle", systemImage: "shuffle")
                    .font(.facts.weight(.semibold))
                    .padding(.horizontal, 12)
            }
            .actionButtonStyle(.secondary)
            .disabled(viewModel.entries.isEmpty)

            if viewModel.canEdit {
                Menu {
                    PlaylistManagementMenuItems(
                        isDisabled: !viewModel.canMutate,
                        onRename: { isRenaming = true },
                        onDelete: { isConfirmingDeletion = true },
                    )
                } label: {
                    Image(systemName: "ellipsis")
                        .font(.facts.weight(.semibold))
                }
                .actionButtonStyle(.secondary)
                .accessibilityLabel(Text("common.actions.more"))
            }
        }
    }

    @ViewBuilder
    private func entryMenu(_ entry: PlaylistEntry) -> some View {
        Button("playlist.actions.playFromHere", systemImage: "play.fill") {
            onPlayEntry(entry)
        }
        Button("playlist.actions.showDetails", systemImage: "info.circle") {
            onSelectMedia(entry.media)
        }
        if viewModel.canEdit {
            Button("playlist.actions.moveUp", systemImage: "arrow.up") {
                Task { await viewModel.move(entry, by: -1) }
            }
            .disabled(!viewModel.canMove(entry, by: -1))
            Button("playlist.actions.moveDown", systemImage: "arrow.down") {
                Task { await viewModel.move(entry, by: 1) }
            }
            .disabled(!viewModel.canMove(entry, by: 1))
            Button("playlist.actions.remove", systemImage: "minus.circle", role: .destructive) {
                Task { await viewModel.remove(entry) }
            }
            .disabled(!viewModel.canMutate)
        }
    }
}
