import SwiftUI

/// The libraries as backdrop tiles, with the hidden ones folded under their own header.
struct LibraryTileGrid: View {
    let viewModel: LibraryViewModel
    @State private var isHiddenExpanded = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    #if os(tvOS)
        @FocusState private var focusedLibrary: LibraryIdentity?
    #endif

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: sectionSpacing) {
                grid(viewModel.visibleLibraries)

                if !viewModel.hiddenLibraries.isEmpty {
                    VStack(alignment: .leading, spacing: LayoutMetrics.libraryTileSpacing) {
                        hiddenHeader
                        if isHiddenExpanded {
                            grid(viewModel.hiddenLibraries)
                                .compositingGroup()
                                .opacity(0.6)
                        }
                    }
                }
            }
            .padding(.horizontal, horizontalPadding)
            .padding(.vertical, verticalPadding)
            #if os(macOS)
                .frame(maxWidth: 1400, alignment: .leading)
                .frame(maxWidth: .infinity, alignment: .topLeading)
            #endif
        }
        #if os(tvOS)
        .scrollClipDisabled()
        #endif
        .overlay {
            if viewModel.isLoading, viewModel.libraries.isEmpty {
                ProgressView("library.loading")
            } else if let errorMessage = viewModel.errorMessage, viewModel.libraries.isEmpty {
                ContentUnavailableView(
                    errorMessage,
                    systemImage: "exclamationmark.triangle.fill",
                    description: Text("library.error.description"),
                )
                .symbolRenderingMode(.multicolor)
            } else if viewModel.libraries.isEmpty {
                ContentUnavailableView(
                    "library.empty.title",
                    systemImage: "rectangle.stack.fill",
                    description: Text("library.empty.description"),
                )
            }
        }
        .task {
            await viewModel.load()
        }
    }

    private func grid(_ libraries: [Library]) -> some View {
        LazyVGrid(
            columns: LayoutMetrics.libraryGridColumns,
            alignment: .leading,
            spacing: LayoutMetrics.libraryTileSpacing,
        ) {
            ForEach(libraries, id: \.identity) { library in
                NavigationLink(value: library) {
                    LibraryTile(
                        library: library,
                        caption: viewModel.caption(for: library),
                        artworks: viewModel.artworks(for: library),
                    )
                }
                .buttonStyle(.cardLift)
                .contextMenu { contextMenu(for: library) }
                #if os(tvOS)
                    .focused($focusedLibrary, equals: library.identity)
                #endif
                    // Pinning rebuilds the tvOS tab bar, which leaves the focused tile stuck pressed.
                    .id("\(library.identity.stableKey):\(viewModel.isPinned(library))")
                    .task {
                        await viewModel.ensurePreview(for: library)
                    }
            }
        }
    }

    @ViewBuilder
    private func contextMenu(for library: Library) -> some View {
        if viewModel.isPinned(library) {
            Button("library.menu.unpin", systemImage: "pin.slash") {
                setPinned(library, pinned: false)
            }
        } else {
            Button("library.menu.pin", systemImage: "pin") {
                setPinned(library, pinned: true)
            }
        }

        if viewModel.isHidden(library) {
            Button("library.menu.show", systemImage: "eye") {
                viewModel.setHidden(library, hidden: false)
            }
        } else {
            Button("library.menu.hide", systemImage: "eye.slash") {
                viewModel.setHidden(library, hidden: true)
            }
        }
    }

    private func setPinned(_ library: Library, pinned: Bool) {
        viewModel.setPinned(library, pinned: pinned)
        #if os(tvOS)
            // The rebuilt tile does not inherit the focus of the one it replaces.
            Task { focusedLibrary = library.identity }
        #endif
    }

    private var hiddenHeader: some View {
        Button {
            withAnimation(reduceMotion ? nil : Motion.crossfade) {
                isHiddenExpanded.toggle()
            }
        } label: {
            HStack(spacing: 10) {
                Text("library.hidden.title")
                    .font(.sectionTitle)
                    .foregroundStyle(.textPrimary)
                Text(viewModel.hiddenLibraries.count, format: .number)
                    .font(.sectionTitle)
                    .foregroundStyle(.textTertiary)
                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.bold))
                    .foregroundStyle(.textTertiary)
                    .rotationEffect(.degrees(isHiddenExpanded ? 90 : 0))
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var sectionSpacing: CGFloat {
        #if os(tvOS)
            56
        #else
            32
        #endif
    }

    private var horizontalPadding: CGFloat {
        #if os(macOS)
            28
        #elseif os(tvOS)
            0
        #else
            LayoutMetrics.pageMargin
        #endif
    }

    private var verticalPadding: CGFloat {
        #if os(tvOS)
            LayoutMetrics.railVerticalInset
        #else
            24
        #endif
    }
}

/// A library as a 16:9 backdrop with its name and size over the bottom, like the detail hero. The backdrop slowly
/// cycles through a few titles of the library, except while the tile is focused or hovered.
struct LibraryTile: View {
    let library: Library
    let caption: String?
    let artworks: [ArtworkResource]

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    #if os(tvOS)
        @Environment(\.isFocused) private var isFocused
    #endif
    @State private var isPaused = false
    @State private var artworkIndex = 0

    private static let rotationInterval: Duration = .seconds(8)

    var body: some View {
        Color.clear
            .aspectRatio(16 / 9, contentMode: .fit)
            .overlay { backdrop }
            .overlay {
                LinearGradient(
                    stops: [
                        .init(color: .black.opacity(0.8), location: 0),
                        .init(color: .black.opacity(0.35), location: 0.45),
                        .init(color: .clear, location: 0.75),
                    ],
                    startPoint: .bottom,
                    endPoint: .top,
                )
            }
            .overlay(alignment: .bottomLeading) {
                labels
                    .padding(labelPadding)
            }
            .mediaArtworkStyle(borderColor: .strokeSubtle)
            .accessibilityElement(children: .combine)
            .task(id: artworks.count) { await rotateArtworks() }
        #if os(tvOS)
            .onChange(of: isFocused) { _, focused in isPaused = focused }
        #elseif os(macOS)
            .onHover { isPaused = $0 }
        #endif
    }

    private var currentArtwork: ArtworkResource? {
        artworks.isEmpty ? nil : artworks[artworkIndex % artworks.count]
    }

    private func rotateArtworks() async {
        guard artworks.count > 1, !reduceMotion else { return }
        // Tiles start at different times so they never all change together.
        try? await Task.sleep(for: .milliseconds(Int.random(in: 0 ... 4000)))
        while !Task.isCancelled {
            try? await Task.sleep(for: Self.rotationInterval)
            guard !Task.isCancelled, !isPaused else { continue }
            let next = (artworkIndex + 1) % artworks.count
            // Decoded first so the fade never goes through an empty frame.
            await ArtworkResourceView.preload(artworks[next])
            guard !Task.isCancelled else { return }
            withAnimation(Motion.ambient) {
                artworkIndex = next
            }
        }
    }

    private var backdrop: some View {
        ZStack {
            Rectangle()
                .fill(.surfaceSubtle)
            Image(systemName: library.iconName)
                .font(.system(size: 44, weight: .medium))
                .foregroundStyle(.textTertiary)
            if let currentArtwork {
                ArtworkResourceView(resource: currentArtwork)
                    .id(artworkIndex)
                    .transition(.opacity)
            }
        }
        .animation(Motion.crossfade, value: artworks.isEmpty)
    }

    private var labels: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline, spacing: iconSpacing) {
                Image(systemName: library.iconName)
                    .font(iconFont)
                    .foregroundStyle(.textSecondary)
                Text(library.title)
                    .font(.tileTitle)
                    .foregroundStyle(.textPrimary)
                    .lineLimit(1)
            }
            Text(caption ?? " ")
                .font(.facts)
                .foregroundStyle(.textSecondary)
                .lineLimit(1)
                // Kept while the count loads so the name does not move up and back down.
                .opacity(caption == nil ? 0 : 1)
        }
        .shadow(color: .black.opacity(0.4), radius: 8)
    }

    private var iconFont: Font {
        #if os(tvOS)
            .system(size: 28, weight: .semibold)
        #else
            .title3.weight(.semibold)
        #endif
    }

    private var iconSpacing: CGFloat {
        #if os(tvOS)
            14
        #else
            8
        #endif
    }

    private var labelPadding: CGFloat {
        #if os(tvOS)
            28
        #else
            16
        #endif
    }
}
