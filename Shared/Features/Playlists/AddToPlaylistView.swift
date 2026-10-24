import SwiftUI

extension View {
    /// Presents the playlist picker for the media held by `media`.
    func addToPlaylistPresentation(media: Binding<MediaItem?>, services: MediaServices?) -> some View {
        taskPresentation(item: media, style: .compactModal) { item in
            if let services {
                AddToPlaylistView(viewModel: AddToPlaylistViewModel(media: item, services: services))
            }
        }
    }
}

struct AddToPlaylistView: View {
    @Environment(\.dismiss) private var dismiss
    @State var viewModel: AddToPlaylistViewModel
    @State private var isNamingPlaylist = false

    var body: some View {
        @Bindable var bindableViewModel = viewModel

        TaskModalNavigationView {
            content
                .taskModalTitle("playlist.add.title")
                .taskModalActions {
                    Button("common.actions.cancel") { dismiss() }
                }
                .playlistNamePrompt(
                    isPresented: $isNamingPlaylist,
                    title: "playlist.create.title",
                    confirmTitle: "playlist.create.action",
                ) { title in
                    Task {
                        if await viewModel.createPlaylist(named: title) {
                            dismiss()
                        }
                    }
                }
                .playlistActionFailureAlert($bindableViewModel.failure)
                .disabled(viewModel.isSaving)
        }
        #if os(macOS)
        .frame(minWidth: 420, minHeight: 360)
        #endif
        .task {
            await viewModel.load()
        }
    }

    @ViewBuilder
    private var content: some View {
        if viewModel.isLoading, viewModel.playlists.isEmpty {
            ProgressView("library.browse.loading")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if let errorMessage = viewModel.errorMessage {
            ContentUnavailableView {
                Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                    .symbolRenderingMode(.multicolor)
            } description: {
                Text("common.errors.tryAgainLater")
            } actions: {
                Button("common.actions.retry") {
                    Task { await viewModel.load() }
                }
            }
        } else {
            List {
                Section {
                    row {
                        isNamingPlaylist = true
                    } label: {
                        Label("playlist.add.new", systemImage: "plus")
                    }
                }

                if !viewModel.playlists.isEmpty {
                    Section("playlist.add.existing") {
                        ForEach(viewModel.playlists) { playlist in
                            row {
                                Task {
                                    if await viewModel.add(to: playlist) {
                                        dismiss()
                                    }
                                }
                            } label: {
                                playlistLabel(playlist)
                            }
                        }
                    }
                }
            }
            #if os(tvOS)
            .padding(.horizontal, 16)
            #endif
        }
    }

    private func row(action: @escaping () -> Void, @ViewBuilder label: () -> some View) -> some View {
        Button(action: action) {
            label()
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        #if os(tvOS)
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
        #endif
    }

    /// Hierarchical styles, so the text inverts with the focused row on tvOS.
    private func playlistLabel(_ playlist: PlaylistMediaItem) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(playlist.title)
                .foregroundStyle(.primary)
            if let leafCount = playlist.leafCount {
                Text("media.labels.elementsCount \(leafCount)")
                    .font(.facts)
                    .foregroundStyle(.secondary)
            }
        }
    }
}
