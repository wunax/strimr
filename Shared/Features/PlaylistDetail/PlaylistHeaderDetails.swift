import SwiftUI

/// Kind, title, size and summary of a playlist, beside its artwork.
struct PlaylistHeaderDetails: View {
    let viewModel: PlaylistDetailViewModel

    private var spacing: CGFloat {
        #if os(tvOS)
            12
        #else
            8
        #endif
    }

    private var factsText: String? {
        let facts = [viewModel.elementsCountText, viewModel.durationText].compactMap(\.self)
        return facts.isEmpty ? nil : facts.joined(separator: " · ")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: spacing) {
            Text(viewModel.playlist.isSmart ? "playlist.kind.smart" : "playlist.kind.regular")
                .eyebrowStyle()
                .foregroundStyle(.textSecondary)

            Text(viewModel.playlist.title)
                .font(.tileTitle)
                .foregroundStyle(.textPrimary)

            if let factsText {
                Text(factsText)
                    .font(.facts)
                    .foregroundStyle(.textSecondary)
            }

            if let summary = viewModel.playlist.summary, !summary.isEmpty {
                Text(summary)
                    .font(.bodyText)
                    .foregroundStyle(.textSecondary)
                    .lineLimit(4)
            }
        }
    }
}

/// Rename and delete, shared by the playlist page and the menus of playlist cards.
struct PlaylistManagementMenuItems: View {
    let isDisabled: Bool
    let onRename: () -> Void
    let onDelete: () -> Void

    var body: some View {
        Button("playlist.rename.menuTitle", systemImage: "pencil", action: onRename)
            .disabled(isDisabled)
        Button("playlist.delete.menuTitle", systemImage: "trash", role: .destructive, action: onDelete)
            .disabled(isDisabled)
    }
}

/// Stands in for the entries under the header while they load, failed to load or there are none.
struct PlaylistEntriesPlaceholder: View {
    let viewModel: PlaylistDetailViewModel

    var body: some View {
        Group {
            if viewModel.isLoading {
                ProgressView("library.browse.loading")
            } else if let errorMessage = viewModel.errorMessage {
                ContentUnavailableView {
                    Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                        .symbolRenderingMode(.multicolor)
                } description: {
                    Text("common.errors.tryAgainLater")
                } actions: {
                    Button("common.actions.retry") {
                        Task { await viewModel.reload() }
                    }
                }
            } else {
                ContentUnavailableView(
                    "playlist.empty.title",
                    systemImage: "list.bullet",
                    description: Text("playlist.empty.description"),
                )
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 32)
    }
}
