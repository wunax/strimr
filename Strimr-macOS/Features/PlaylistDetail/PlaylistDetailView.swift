import Observation
import SwiftUI

struct PlaylistDetailView: View {
    @Environment(MediaServices.self) private var mediaServices
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.dismiss) private var dismiss
    @State var viewModel: PlaylistDetailViewModel
    @State private var selection: PlaylistEntry.ID?
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

    private var rowInsets: EdgeInsets {
        EdgeInsets(
            top: 0,
            leading: LayoutMetrics.detailSectionMargin,
            bottom: 0,
            trailing: LayoutMetrics.detailSectionMargin,
        )
    }

    var body: some View {
        @Bindable var bindableViewModel = viewModel

        entriesList
            .onDeleteCommand {
                guard viewModel.canEdit, let entry = selection.flatMap(selectedEntry(id:)) else { return }
                Task { await viewModel.remove(entry) }
            }
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

    private var entriesList: some View {
        List(selection: $selection) {
            Section {
                VStack(alignment: .leading, spacing: 20) {
                    headerSection
                    playButtonsRow
                }
                .padding(.vertical, 20)
            }
            .listRowInsets(rowInsets)
            .listRowSeparator(.hidden)

            Section {
                if viewModel.entries.isEmpty {
                    PlaylistEntriesPlaceholder(viewModel: viewModel)
                        .listRowSeparator(.hidden)
                } else {
                    ForEach(Array(viewModel.entries.enumerated()), id: \.element.id) { index, entry in
                        PlaylistEntryRow(entry: entry, position: index + 1, lastPosition: viewModel.entries.count)
                            .tag(entry.id)
                    }
                    .onMove(perform: moveAction)
                }
            }
            .listRowInsets(rowInsets)
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .contextMenu(forSelectionType: PlaylistEntry.ID.self) { ids in
            if let selected = selectedEntry(in: ids) {
                entryMenu(selected)
            }
        } primaryAction: { ids in
            if let selected = selectedEntry(in: ids) {
                onPlayEntry(selected)
            }
        }
    }

    private var headerSection: some View {
        HStack(alignment: .top, spacing: 16) {
            MediaImageView(
                viewModel: MediaImageViewModel(
                    services: mediaServices,
                    artworkKind: .thumb,
                    media: viewModel.playlistDisplayItem,
                ),
            )
            .frame(width: 140, height: 210)
            .mediaArtworkStyle()

            PlaylistHeaderDetails(viewModel: viewModel)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var playButtonsRow: some View {
        HStack(spacing: 12) {
            Button {
                onPlay(viewModel.playlist.id)
            } label: {
                Label("common.actions.play", systemImage: "play.fill")
            }
            .actionButtonStyle(.primary)
            .disabled(viewModel.entries.isEmpty)

            Button {
                onShuffle(viewModel.playlist.id)
            } label: {
                Label("common.actions.shuffle", systemImage: "shuffle")
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
                }
                .menuStyle(.button)
                .menuIndicator(.hidden)
                .actionButtonStyle(.secondary)
                .fixedSize()
                .help(Text("common.actions.more"))
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
            Divider()
            Button("playlist.actions.remove", systemImage: "minus.circle", role: .destructive) {
                Task { await viewModel.remove(entry) }
            }
            .disabled(!viewModel.canMutate)
        }
    }

    private func selectedEntry(in ids: Set<PlaylistEntry.ID>) -> PlaylistEntry? {
        ids.first.flatMap(selectedEntry(id:))
    }

    private func selectedEntry(id: PlaylistEntry.ID) -> PlaylistEntry? {
        viewModel.entries.first { $0.id == id }
    }

    private var moveAction: ((IndexSet, Int) -> Void)? {
        guard viewModel.canEdit else { return nil }
        return { [viewModel] source, destination in
            Task { await viewModel.move(fromOffsets: source, toOffset: destination) }
        }
    }
}
