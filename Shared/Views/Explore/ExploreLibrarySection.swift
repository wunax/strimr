import SwiftUI

/// Where a catalog title sits in the libraries, each copy opening its server page.
struct ExploreLibrarySection: View {
    let viewModel: ExploreDetailViewModel
    let onSelectCopy: (MediaItem) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("explore.detail.inLibraries")
                .font(.sectionTitle)
                .foregroundStyle(.textPrimary)

            switch viewModel.libraryState {
            case .checking:
                HStack(spacing: 10) {
                    ProgressView()
                    Text("explore.detail.checking")
                        .font(.bodyText)
                        .foregroundStyle(.textSecondary)
                }
            case .notFound:
                note("explore.detail.notInLibrary", systemImage: "info.circle")
            case let .unchecked(count):
                note("explore.detail.uncheckedServers \(count)", systemImage: "icloud.slash")
            case .found:
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(viewModel.copies) { copy in
                        copyRow(copy)
                    }
                }
                #if os(tvOS)
                .focusSection()
                #endif
                if viewModel.uncheckedServers > 0 {
                    note("explore.detail.uncheckedServers \(viewModel.uncheckedServers)", systemImage: "icloud.slash")
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func note(_ key: LocalizedStringKey, systemImage: String) -> some View {
        Label(key, systemImage: systemImage)
            .font(.bodyText)
            .foregroundStyle(.textSecondary)
    }

    /// Hierarchical styles rather than the fixed text tokens: the focused tvOS button turns white and they invert.
    private func copyRow(_ copy: MediaCopy) -> some View {
        Button {
            onSelectCopy(copy.media)
        } label: {
            HStack(spacing: 12) {
                Image(systemName: "play.rectangle.fill")
                    .font(.title3)
                    .foregroundStyle(.secondary)
                VStack(alignment: .leading, spacing: 2) {
                    Text(copy.media.primaryLabel)
                        .font(.rowTitle)
                        .lineLimit(1)
                    Text(copy.serverName)
                        .font(.facts)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer(minLength: 8)
                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
            .padding(14)
            .frame(maxWidth: rowMaxWidth, alignment: .leading)
            #if !os(tvOS)
                .background(
                    RoundedRectangle(cornerRadius: LayoutMetrics.cardCornerRadius, style: .continuous)
                        .fill(.surfaceSubtle),
                )
            #endif
        }
        #if os(tvOS)
        .buttonStyle(.bordered)
        .buttonBorderShape(.roundedRectangle(radius: LayoutMetrics.cardCornerRadius))
        #else
        .buttonStyle(.plain)
        #endif
    }

    private var rowMaxWidth: CGFloat {
        #if os(tvOS)
            900
        #else
            560
        #endif
    }
}

/// The catalog title's own watchlist, shown only when its source has one.
struct ExploreWatchlistButton: View {
    let viewModel: ExploreDetailViewModel

    var body: some View {
        if viewModel.watchlist != nil {
            Button {
                Task { await viewModel.toggleWatchlist() }
            } label: {
                Label(viewModel.watchlistActionTitle, systemImage: viewModel.watchlistActionIcon)
                    .font(.facts.weight(.semibold))
                    .padding(.horizontal, 12)
            }
            .actionButtonStyle(.secondary)
            .disabled(!viewModel.isWatchlistReady)
            .exploreWatchlistAlert(viewModel)
        }
    }
}

extension View {
    func exploreWatchlistAlert(_ viewModel: ExploreDetailViewModel) -> some View {
        @Bindable var viewModel = viewModel
        return alert(
            "explore.watchlist.error.title",
            isPresented: Binding(
                get: { viewModel.watchlistErrorMessage != nil },
                set: {
                    if !$0 {
                        viewModel.watchlistErrorMessage = nil
                    }
                },
            ),
        ) {
            Button("common.actions.done") {}
        } message: {
            Text(viewModel.watchlistErrorMessage ?? "")
        }
    }
}
