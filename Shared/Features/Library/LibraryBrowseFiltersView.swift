import SwiftUI

/// Every filter of a library in one form: a popover on iPad and macOS, a sheet on iPhone, a side panel on tvOS.
struct LibraryBrowseFiltersView: View {
    enum ServerFilters {
        case available
        /// Server filters do not apply to the local downloads.
        case downloads
        case unreachable
    }

    let viewModel: LibraryBrowseControlsViewModel
    var showsDownloadsToggle = false
    var isDownloadedOnly: Binding<Bool> = .constant(false)
    let serverFilters: ServerFilters
    let canReset: Bool
    let onReset: () -> Void
    let onDone: () -> Void

    var body: some View {
        NavigationStack {
            Form {
                if showsDownloadsToggle {
                    Section {
                        Toggle(isOn: isDownloadedOnly) {
                            Label("library.browse.filters.downloadedOnly", systemImage: "arrow.down.circle")
                        }
                    } header: {
                        Text("library.browse.filters.availability")
                    }
                }

                if viewModel.hasControls, viewModel.showsFilterControl {
                    Section {
                        if viewModel.isJellyfinBrowse {
                            jellyfinRows
                        } else {
                            plexRows
                        }
                    } header: {
                        Text("library.browse.filters.title")
                    } footer: {
                        serverFiltersFooter
                    }
                    .disabled(serverFilters != .available)
                }

                if canReset {
                    Section {
                        Button("library.browse.filters.reset", role: .destructive, action: onReset)
                    }
                }
            }
            #if os(macOS)
            .formStyle(.grouped)
            .navigationTitle(Text("library.browse.filters.title"))
            #endif
            #if os(iOS)
            .navigationTitle(Text("library.browse.filters.title"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("common.actions.done", action: onDone)
                }
            }
            #endif
        }
        #if os(tvOS)
        // Focused rows grow past the form's bounds; let them spill into the panel padding sideways only.
        .scrollClipDisabled()
        .mask {
            Rectangle()
                .padding(.horizontal, -24)
        }
        #endif
    }

    @ViewBuilder
    private var serverFiltersFooter: some View {
        switch serverFilters {
        case .available:
            EmptyView()
        case .downloads:
            Text("library.browse.filters.downloadsFooter")
        case .unreachable:
            Text("library.browse.filters.unreachableFooter")
        }
    }

    private var plexRows: some View {
        ForEach(viewModel.availableFilters, id: \.filter) { filter in
            if filter.isBoolean {
                Toggle(
                    filter.title,
                    isOn: Binding(
                        get: { viewModel.isFilterOn(filter) },
                        set: { viewModel.setFilter(filter, isOn: $0) },
                    ),
                )
            } else {
                NavigationLink {
                    PlexFilterOptionsView(viewModel: viewModel, filter: filter)
                } label: {
                    LabeledContent(
                        filter.title,
                        value: viewModel.filterSelection(for: filter)?.selectedOption?.title
                            ?? String(localized: "library.browse.filters.all"),
                    )
                }
            }
        }
    }

    @ViewBuilder
    private var jellyfinRows: some View {
        Picker(
            LibraryBrowseControlsViewModel.JellyfinFilter.watchStatus.title,
            selection: Binding(
                get: { viewModel.jellyfinWatchStatus },
                set: { viewModel.setJellyfinWatchStatus($0) },
            ),
        ) {
            Text("library.browse.filters.all").tag(LibraryBrowseWatchStatus.all)
            Text("library.browse.filters.unplayed").tag(LibraryBrowseWatchStatus.unplayed)
            Text("library.browse.filters.played").tag(LibraryBrowseWatchStatus.played)
        }

        ForEach([LibraryBrowseControlsViewModel.JellyfinFilter.inProgress, .favorites]) { filter in
            Toggle(
                filter.title,
                isOn: Binding(
                    get: { viewModel.jellyfinFilterIsSelected(filter) },
                    set: { viewModel.setJellyfinFlag(filter, isOn: $0) },
                ),
            )
        }

        ForEach([LibraryBrowseControlsViewModel.JellyfinFilter.genres, .years]) { filter in
            NavigationLink {
                JellyfinFilterOptionsView(viewModel: viewModel, filter: filter)
            } label: {
                LabeledContent(filter.title, value: jellyfinSelectionSummary(filter))
            }
        }
    }

    private func jellyfinSelectionSummary(_ filter: LibraryBrowseControlsViewModel.JellyfinFilter) -> String {
        let count = viewModel.jellyfinSelectionCount(filter)
        return count == 0 ? String(localized: "library.browse.filters.all") : String(count)
    }
}

private struct PlexFilterOptionsView: View {
    @Environment(\.dismiss) private var dismiss
    let viewModel: LibraryBrowseControlsViewModel
    let filter: PlexSectionItemFilter

    var body: some View {
        FilterOptionsContent(
            isLoading: viewModel.isLoadingOptions(for: filter)
                || (viewModel.filterOptions[filter.filter] == nil && viewModel.optionsError(for: filter) == nil),
            errorMessage: viewModel.optionsError(for: filter),
            isEmpty: viewModel.options(for: filter).isEmpty,
        ) {
            List {
                FilterOptionRow(
                    title: String(localized: "library.browse.filters.all"),
                    isSelected: viewModel.filterSelection(for: filter) == nil,
                ) {
                    viewModel.clearFilter(filter)
                    dismiss()
                }
                ForEach(viewModel.options(for: filter)) { option in
                    FilterOptionRow(
                        title: option.title,
                        isSelected: viewModel.filterSelection(for: filter)?.selectedOption?.id == option.id,
                    ) {
                        viewModel.selectFilterOption(option, for: filter)
                        dismiss()
                    }
                }
            }
        }
        .navigationTitle(Text(verbatim: filter.title))
        .task { await viewModel.loadFilterOptionsIfNeeded(for: filter) }
    }
}

private struct JellyfinFilterOptionsView: View {
    let viewModel: LibraryBrowseControlsViewModel
    let filter: LibraryBrowseControlsViewModel.JellyfinFilter
    @State private var searchText = ""

    var body: some View {
        FilterOptionsContent(
            isLoading: viewModel.isLoadingJellyfinFilterOptions
                ||
                (viewModel.jellyfinFilterOptions == LibraryBrowseFilterOptions() && viewModel
                    .jellyfinFilterOptionsError == nil),
            errorMessage: viewModel.jellyfinFilterOptionsError,
            isEmpty: viewModel.jellyfinOptions(for: filter).isEmpty,
        ) {
            List {
                if searchText.isEmpty {
                    FilterOptionRow(
                        title: String(localized: "library.browse.filters.all"),
                        isSelected: !viewModel.jellyfinFilterIsSelected(filter),
                    ) {
                        viewModel.clearJellyfinFilter(filter)
                    }
                }
                ForEach(filteredOptions) { option in
                    FilterOptionRow(
                        title: option.title,
                        isSelected: viewModel.jellyfinOptionIsSelected(option, for: filter),
                    ) {
                        viewModel.selectJellyfinOption(option, for: filter)
                    }
                }
            }
            .searchable(text: $searchText, prompt: Text("library.browse.filters.search"))
        }
        .navigationTitle(Text(verbatim: filter.title))
        .task { await viewModel.loadJellyfinFilterOptionsIfNeeded() }
    }

    private var filteredOptions: [LibraryBrowseValueOption] {
        let options = viewModel.jellyfinOptions(for: filter)
        guard !searchText.isEmpty else { return options }
        return options.filter { $0.title.localizedCaseInsensitiveContains(searchText) }
    }
}

private struct FilterOptionsContent<Content: View>: View {
    let isLoading: Bool
    let errorMessage: String?
    let isEmpty: Bool
    @ViewBuilder let content: () -> Content

    var body: some View {
        if isLoading {
            VStack(spacing: 12) {
                ProgressView()
                Text("library.browse.filters.loading")
                    .font(.facts)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if let errorMessage {
            ContentUnavailableView(
                errorMessage,
                systemImage: "exclamationmark.triangle.fill",
                description: Text("common.errors.tryAgainLater"),
            )
            .symbolRenderingMode(.multicolor)
        } else if isEmpty {
            ContentUnavailableView(
                "common.empty.nothingToShow",
                systemImage: "line.3.horizontal.decrease",
            )
        } else {
            content()
        }
    }
}

private struct FilterOptionRow: View {
    let title: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack {
                Text(verbatim: title)
                Spacer()
                if isSelected {
                    Image(systemName: "checkmark")
                        .foregroundStyle(.selectionAccent)
                }
            }
            .contentShape(Rectangle())
        }
        #if !os(tvOS)
        .buttonStyle(.plain)
        #endif
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}
