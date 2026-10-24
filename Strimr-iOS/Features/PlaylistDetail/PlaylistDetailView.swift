import Observation
import SwiftUI

struct PlaylistDetailView: View {
    @Environment(MediaServices.self) private var mediaServices
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.dismiss) private var dismiss
    @State var viewModel: PlaylistDetailViewModel
    @State private var editMode: EditMode = .inactive
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
        EdgeInsets(top: 0, leading: LayoutMetrics.pageMargin, bottom: 0, trailing: LayoutMetrics.pageMargin)
    }

    var body: some View {
        @Bindable var bindableViewModel = viewModel

        List {
            Section {
                VStack(alignment: .leading, spacing: 20) {
                    headerSection
                    playButtonsRow
                }
                .padding(.vertical, 16)
            }
            .listRowInsets(rowInsets)
            .listRowSeparator(.hidden)
            .listRowBackground(Color.clear)

            Section {
                if viewModel.entries.isEmpty {
                    PlaylistEntriesPlaceholder(viewModel: viewModel)
                        .listRowSeparator(.hidden)
                } else {
                    ForEach(Array(viewModel.entries.enumerated()), id: \.element.id) { index, entry in
                        PlaylistEntryRow(entry: entry, position: index + 1, lastPosition: viewModel.entries.count) {
                            guard !editMode.isEditing else { return }
                            onPlayEntry(entry)
                        }
                        .contextMenu { entryMenu(entry) }
                    }
                    .onDelete(perform: deleteAction)
                    .onMove(perform: moveAction)
                }
            }
            .listRowInsets(rowInsets)
            .listRowBackground(Color.clear)
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .environment(\.editMode, $editMode)
        .toolbar {
            if viewModel.canEdit, viewModel.entries.count > 1 {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(editMode.isEditing ? "common.actions.done" : "playlist.actions.reorder") {
                        withAnimation { editMode = editMode.isEditing ? .inactive : .active }
                    }
                }
            }
        }
        .toolbar(.hidden, for: .tabBar)
        .onChange(of: viewModel.entries.count) { _, count in
            if count < 2 {
                editMode = .inactive
            }
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
                    .frame(maxWidth: .infinity)
            }
            .actionButtonStyle(.primary)
            .disabled(viewModel.entries.isEmpty)

            Button {
                onShuffle(viewModel.playlist.id)
            } label: {
                Image(systemName: "shuffle")
            }
            .actionButtonStyle(.secondary)
            .disabled(viewModel.entries.isEmpty)
            .accessibilityLabel(Text("common.actions.shuffle"))

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
            Divider()
            Button("playlist.actions.remove", systemImage: "minus.circle", role: .destructive) {
                Task { await viewModel.remove(entry) }
            }
            .disabled(!viewModel.canMutate)
        }
    }

    private var deleteAction: ((IndexSet) -> Void)? {
        guard viewModel.canEdit else { return nil }
        return { [viewModel] offsets in
            guard let index = offsets.first, viewModel.entries.indices.contains(index) else { return }
            let entry = viewModel.entries[index]
            Task { await viewModel.remove(entry) }
        }
    }

    private var moveAction: ((IndexSet, Int) -> Void)? {
        guard viewModel.canEdit else { return nil }
        return { [viewModel] source, destination in
            Task { await viewModel.move(fromOffsets: source, toOffset: destination) }
        }
    }
}
