import SwiftUI

/// One fixed row of controls (type, filters, sort, view options) and, when filters apply, a summary line of them.
struct LibraryBrowseControlsView<Filters: View>: View {
    typealias ActiveFilter = LibraryBrowseControlsViewModel.ActiveFilter

    let viewModel: LibraryBrowseControlsViewModel
    let showsServerControls: Bool
    var showsBackButton = false
    var onNavigateBack: () -> Void = {}
    let showsFiltersButton: Bool
    let filterCount: Int
    @Binding var isFiltersPresented: Bool
    /// Shown first in the summary, since it changes where the items come from.
    var downloadsFilter: ActiveFilter?
    var canReset = false
    var onReset: () -> Void = {}
    let viewMode: LibraryBrowseViewMode
    let viewModes: [LibraryBrowseViewMode]
    let onSelectViewMode: (LibraryBrowseViewMode) -> Void
    var itemCount: Int?
    @ViewBuilder let filters: () -> Filters

    /// Below this width, the filters button drops its title so the row never has to scroll.
    private static var compactRowWidth: CGFloat {
        460
    }

    @State private var rowWidth: CGFloat = .infinity

    var body: some View {
        VStack(alignment: .leading, spacing: summarySpacing) {
            controlsRow(isCompact: rowWidth < Self.compactRowWidth)
                .padding(rowPadding)
                .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { rowWidth = $0 }

            if hasSummary {
                summaryRow
            }
        }
    }

    private var activeFilters: [ActiveFilter] {
        (downloadsFilter.map { [$0] } ?? []) + (showsServerControls ? viewModel.activeFilters : [])
    }

    private var hasSummary: Bool {
        !activeFilters.isEmpty || (itemCount ?? 0) > 0
    }

    private func controlsRow(isCompact: Bool) -> some View {
        HStack(spacing: LayoutMetrics.chipSpacing) {
            if showsBackButton {
                Button(action: onNavigateBack) {
                    Image(systemName: "chevron.left")
                }
                .modifier(BrowseControlStyle(isActive: false))
                .accessibilityLabel(Text("library.browse.folders.back"))
            }
            if showsServerControls, viewModel.hasDisplayTypes {
                typeMenu
            }
            if showsFiltersButton {
                filtersButton(isCompact: isCompact)
            }
            if showsServerControls, viewModel.showsSortControl {
                sortMenu
            }
            Spacer(minLength: 0)
            if viewModes.count > 1 {
                viewMenu
            }
        }
    }

    private var typeMenu: some View {
        Menu {
            Picker(selection: typeSelection) {
                ForEach(viewModel.displayTypes) { type in
                    Text(verbatim: type.title).tag(type.key)
                }
            } label: {
                Text("library.browse.type.title")
            }
            .pickerStyle(.inline)
        } label: {
            menuLabel(title: viewModel.typeTitle, systemImage: nil)
        }
        .modifier(BrowseControlStyle(isActive: false, isMenu: true))
    }

    private func filtersButton(isCompact: Bool) -> some View {
        Button {
            isFiltersPresented.toggle()
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "line.3.horizontal.decrease")
                if !isCompact || filterCount == 0 {
                    Text("library.browse.filters.title")
                }
                if filterCount > 0 {
                    Text(verbatim: String(filterCount))
                        .monospacedDigit()
                }
            }
        }
        .modifier(BrowseControlStyle(isActive: filterCount > 0))
        #if os(tvOS)
            .taskPresentation(isPresented: $isFiltersPresented, style: .contextual, content: filters)
        #else
            // A popover rather than an inspector: an inspector inside a pushed destination resets the navigation
            // stack on macOS. On iPhone the popover becomes a sheet.
            .popover(isPresented: $isFiltersPresented, arrowEdge: .bottom) {
                filters()
                    .frame(minWidth: 340, idealWidth: 380, minHeight: 440, idealHeight: 520)
                #if os(iOS)
                    .presentationDetents([.medium, .large])
                    .presentationCompactAdaptation(.sheet)
                #endif
            }
        #endif
            .accessibilityLabel(Text("library.browse.filters.title"))
            .accessibilityValue(filterCount > 0 ? Text(verbatim: String(filterCount)) : Text(verbatim: ""))
    }

    private var sortMenu: some View {
        Menu {
            Picker(selection: sortSelection) {
                ForEach(viewModel.sortChoices) { choice in
                    Text(verbatim: choice.title).tag(choice.id)
                }
            } label: {
                Text("library.browse.sort.title")
            }
            .pickerStyle(.inline)

            if viewModel.isSortAscending != nil {
                Picker(selection: sortDirection) {
                    Label("library.browse.sort.direction.asc", systemImage: "arrow.up").tag(true)
                    Label("library.browse.sort.direction.desc", systemImage: "arrow.down").tag(false)
                } label: {
                    Text("library.browse.sort.direction")
                }
                .pickerStyle(.inline)
            }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: sortImage)
                Text(verbatim: viewModel.selectedSortTitle ?? String(localized: "library.browse.sort.title"))
            }
        }
        // The only control allowed to shrink: a long sort name truncates instead of pushing the row off screen.
        .modifier(BrowseControlStyle(isActive: false, isMenu: true, isFlexible: true))
        .accessibilityLabel(Text("library.browse.sort.title"))
        .accessibilityValue(Text(verbatim: viewModel.selectedSortTitle ?? ""))
    }

    private var viewMenu: some View {
        Menu {
            Picker(selection: viewModeSelection) {
                ForEach(viewModes) { mode in
                    Label(mode.title, systemImage: mode.systemImage).tag(mode)
                }
            } label: {
                Text("library.browse.view.title")
            }
            .pickerStyle(.inline)
        } label: {
            Image(systemName: viewMode.systemImage)
        }
        .modifier(BrowseControlStyle(isActive: false, isMenu: true))
        .accessibilityLabel(Text("library.browse.view.title"))
        .accessibilityValue(Text(viewMode.title))
    }

    private func menuLabel(title: String, systemImage: String?) -> some View {
        HStack(spacing: 6) {
            if let systemImage {
                Image(systemName: systemImage)
            }
            Text(verbatim: title)
            Image(systemName: "chevron.down")
                .font(.caption2)
                .opacity(0.7)
        }
    }

    private var sortImage: String {
        switch viewModel.isSortAscending {
        case true?: "arrow.up"
        case false?: "arrow.down"
        case nil: "arrow.up.arrow.down"
        }
    }

    private var summaryRow: some View {
        #if os(tvOS)
            // Plain text: removable chips would add a focus row between the controls and the grid.
            Text(verbatim: summaryText)
                .font(.facts)
                .foregroundStyle(.textSecondary)
                .lineLimit(1)
                .padding(.horizontal, rowPadding.leading)
        #else
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: LayoutMetrics.chipSpacing) {
                    if let itemCount, itemCount > 0 {
                        Text(String(localized: "library.browse.count.items \(itemCount)"))
                            .font(.facts)
                            .foregroundStyle(.textSecondary)
                    }
                    ForEach(activeFilters) { filter in
                        Button(action: filter.remove) {
                            HStack(spacing: 6) {
                                Text(verbatim: filter.title)
                                Image(systemName: "xmark")
                                    .font(.caption2.weight(.bold))
                            }
                        }
                        .buttonStyle(.chip(isSelected: true))
                        .accessibilityLabel(Text("library.browse.filters.remove \(filter.title)"))
                    }
                    if canReset, !activeFilters.isEmpty {
                        Button("library.browse.filters.reset", action: onReset)
                            .buttonStyle(.plain)
                            .font(.facts.weight(.semibold))
                            .foregroundStyle(.textSecondary)
                    }
                }
                .padding(rowPadding)
            }
            .mouseDragScrolling()
        #endif
    }

    private var summaryText: String {
        var parts = activeFilters.map(\.title)
        if let itemCount, itemCount > 0 {
            parts.append(String(localized: "library.browse.count.items \(itemCount)"))
        }
        return parts.joined(separator: " · ")
    }

    private var typeSelection: Binding<String> {
        Binding(
            get: { viewModel.selectedDisplayType?.key ?? "" },
            set: { key in
                guard let type = viewModel.displayTypes.first(where: { $0.key == key }) else { return }
                viewModel.selectDisplayType(type)
            },
        )
    }

    private var sortSelection: Binding<String> {
        Binding(
            get: { viewModel.selectedSortID ?? "" },
            set: { viewModel.selectSort(id: $0) },
        )
    }

    private var sortDirection: Binding<Bool> {
        Binding(
            get: { viewModel.isSortAscending ?? true },
            set: { viewModel.setSortAscending($0) },
        )
    }

    private var viewModeSelection: Binding<LibraryBrowseViewMode> {
        Binding(get: { viewMode }, set: onSelectViewMode)
    }

    private var summarySpacing: CGFloat {
        #if os(tvOS)
            8
        #else
            10
        #endif
    }

    /// Room inside the row so focused controls are not clipped as they scale up.
    private var rowPadding: EdgeInsets {
        #if os(tvOS)
            EdgeInsets(top: 12, leading: 12, bottom: 12, trailing: 12)
        #else
            EdgeInsets(top: 0, leading: 2, bottom: 0, trailing: 2)
        #endif
    }
}

private struct BrowseControlStyle: ViewModifier {
    let isActive: Bool
    var isMenu = false
    var isFlexible = false

    func body(content: Content) -> some View {
        #if os(tvOS)
            // Bordered keeps the native focus lift; hierarchical styles invert once focused.
            content
                .buttonStyle(.bordered)
                .buttonBorderShape(.capsule)
                .foregroundStyle(isActive ? HierarchicalShapeStyle.primary : .secondary)
                .menuIndicator(.hidden)
        #else
            if isMenu {
                content
                    .menuStyle(.button)
                    .menuIndicator(.hidden)
                    .buttonStyle(.chip(isSelected: isActive))
                    .fixedSize(horizontal: !isFlexible, vertical: true)
            } else {
                content
                    .buttonStyle(.chip(isSelected: isActive))
                    .fixedSize()
            }
        #endif
    }
}
