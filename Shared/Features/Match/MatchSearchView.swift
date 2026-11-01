import SwiftUI

struct MatchSearchView: View {
    @Environment(\.dismiss) private var dismiss
    @State var viewModel: MatchSearchViewModel
    /// Plex says "fix match", Jellyfin "identify".
    let title: String
    /// Offered once a match is applied; nil when the artwork cannot be changed.
    var onChoosePoster: (() -> Void)?

    var body: some View {
        @Bindable var bindableViewModel = viewModel

        TaskModalNavigationView {
            Group {
                if viewModel.appliedCandidate != nil {
                    appliedContent
                } else {
                    searchContent
                    #if !os(tvOS)
                        .toolbar {
                            ToolbarItem(placement: .cancellationAction) {
                                Button("common.actions.cancel") { dismiss() }
                            }
                        }
                    #endif
                }
            }
            .taskModalTitle(verbatim: title)
            .alert(item: $bindableViewModel.failure) { failure in
                Alert(
                    title: Text("media.match.error"),
                    message: Text(failure.message),
                    dismissButton: .default(Text("common.actions.done")),
                )
            }
        }
        #if os(macOS)
        .frame(minWidth: 560, minHeight: 560)
        #endif
        .task {
            guard !viewModel.hasSearched else { return }
            await viewModel.search()
        }
    }

    /// Offers a new poster, since the one of the previous match may not suit the new one.
    private var appliedContent: some View {
        ContentUnavailableView {
            Label("media.match.applied", systemImage: "checkmark.circle.fill")
        } description: {
            Text(onChoosePoster == nil ? "media.match.applied.updating" : "media.match.applied.message")
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .taskModalActions {
            if let onChoosePoster {
                Button("media.match.choosePoster", action: onChoosePoster)
            }
        } actions: {
            Button("common.actions.done") { dismiss() }
        }
    }

    private var searchContent: some View {
        #if os(tvOS)
            HStack(alignment: .top, spacing: 40) {
                VStack(alignment: .leading, spacing: 28) {
                    searchFields
                }
                .padding(24)
                .frame(width: 500)
                .focusSection()
                Divider()
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 16) {
                        results
                    }
                    .padding(24)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .focusSection()
            }
        #else
            List {
                Section {
                    searchFields
                }
                results
            }
        #endif
    }

    @ViewBuilder
    private var searchFields: some View {
        TextField("media.match.titleField", text: $viewModel.title)
            .onSubmit(search)
        TextField("media.match.yearField", text: $viewModel.year)
        #if os(iOS) || os(tvOS)
            .keyboardType(.numberPad)
        #endif
            .onSubmit(search)
        Button(action: search) {
            if viewModel.isSearching {
                ProgressView()
            } else {
                Label("media.match.search", systemImage: "magnifyingglass")
            }
        }
        .disabled(!viewModel.canSearch)
        .tint(.secondary)
    }

    @ViewBuilder
    private var results: some View {
        if let errorMessage = viewModel.errorMessage {
            ContentUnavailableView {
                Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                    .symbolRenderingMode(.multicolor)
            } description: {
                Text("common.errors.tryAgainLater")
            }
        } else if viewModel.hasSearched, viewModel.results.isEmpty, !viewModel.isSearching {
            ContentUnavailableView(
                "media.match.empty",
                systemImage: "magnifyingglass",
                description: Text("media.match.empty.description"),
            )
        } else if !viewModel.results.isEmpty {
            Section("media.match.results") {
                ForEach(viewModel.results) { candidate in
                    Button {
                        Task { await viewModel.apply(candidate) }
                    } label: {
                        MatchCandidateRow(
                            candidate: candidate,
                            isApplying: viewModel.applyingCandidateID == candidate.id,
                        )
                    }
                    .disabled(viewModel.applyingCandidateID != nil || viewModel.isSearching)
                }
            }
        } else {
            ProgressView()
                .frame(maxWidth: .infinity, minHeight: 160)
        }
    }

    private func search() {
        Task { await viewModel.search() }
    }
}

private struct MatchCandidateRow: View {
    let candidate: MatchCandidate
    let isApplying: Bool

    private var posterWidth: CGFloat {
        #if os(tvOS)
            80
        #else
            48
        #endif
    }

    var body: some View {
        HStack(spacing: 16) {
            Color.surfaceSubtle
                .aspectRatio(2 / 3, contentMode: .fit)
                .frame(width: posterWidth)
                .overlay {
                    if let posterURL = candidate.posterURL {
                        ArtworkResourceView(resource: .url(posterURL), contentMode: .fill)
                    } else {
                        Image(systemName: "film")
                            .foregroundStyle(.secondary)
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
            VStack(alignment: .leading, spacing: 4) {
                Text(candidate.title)
                    .foregroundStyle(primaryStyle)
                    .multilineTextAlignment(.leading)
                if let detail {
                    Text(verbatim: detail)
                        .font(.caption)
                        .foregroundStyle(secondaryStyle)
                }
                if candidate.isCurrent {
                    HStack(spacing: 4) {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(accentStyle)
                        Text("media.match.current")
                            .foregroundStyle(secondaryStyle)
                    }
                    .font(.caption)
                }
            }
            Spacer(minLength: 0)
            if isApplying {
                ProgressView()
            }
        }
        .contentShape(Rectangle())
    }

    /// List buttons draw their label in the tint, and focused tvOS buttons turn white, where only hierarchical
    /// styles stay legible.
    private var primaryStyle: AnyShapeStyle {
        #if os(tvOS)
            AnyShapeStyle(.primary)
        #else
            AnyShapeStyle(Color.textPrimary)
        #endif
    }

    private var secondaryStyle: AnyShapeStyle {
        #if os(tvOS)
            AnyShapeStyle(.secondary)
        #else
            AnyShapeStyle(Color.textSecondary)
        #endif
    }

    private var accentStyle: AnyShapeStyle {
        #if os(tvOS)
            AnyShapeStyle(.secondary)
        #else
            AnyShapeStyle(Color.selectionAccent)
        #endif
    }

    private var detail: String? {
        let parts = [candidate.year.map(String.init), candidate.provider.map(MetadataProviderName.displayName)]
            .compactMap(\.self)
        return parts.isEmpty ? nil : parts.joined(separator: " • ")
    }
}
