import SwiftUI

struct LibraryVisionView: View {
    @State var viewModel: LibraryViewModel
    @Environment(SettingsManager.self) private var settingsManager
    let onSelectMedia: (MediaDisplayItem) -> Void
    @State private var isHiddenExpanded = false

    init(
        viewModel: LibraryViewModel,
        onSelectMedia: @escaping (MediaDisplayItem) -> Void = { _ in },
    ) {
        _viewModel = State(initialValue: viewModel)
        self.onSelectMedia = onSelectMedia
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 32) {
                LazyVGrid(columns: gridColumns, spacing: 24) {
                    ForEach(visibleLibraries) { library in
                        NavigationLink(value: library) {
                            libraryCard(for: library)
                        }
                        .buttonStyle(.plain)
                        .hoverEffect()
                        .task {
                            await viewModel.ensureArtwork(for: library)
                        }
                    }
                }

                if !hiddenLibraries.isEmpty {
                    VStack(alignment: .leading, spacing: 20) {
                        Button {
                            isHiddenExpanded.toggle()
                        } label: {
                            HStack(spacing: 12) {
                                Image(systemName: isHiddenExpanded ? "chevron.down" : "chevron.right")
                                    .font(.headline)
                                    .foregroundStyle(.secondary)
                                Text("library.hidden.title")
                                    .font(.title3.weight(.semibold))
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .buttonStyle(.plain)

                        if isHiddenExpanded {
                            LazyVGrid(columns: gridColumns, spacing: 24) {
                                ForEach(hiddenLibraries) { library in
                                    NavigationLink(value: library) {
                                        libraryCard(for: library)
                                    }
                                    .buttonStyle(.plain)
                                    .hoverEffect()
                                    .task {
                                        await viewModel.ensureArtwork(for: library)
                                    }
                                }
                            }
                        }
                    }
                }
            }
            .padding(24)
        }
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

    private var hiddenLibraryIds: Set<String> {
        Set(settingsManager.interface.hiddenLibraryIds)
    }

    private var visibleLibraries: [Library] {
        viewModel.libraries.filter { !hiddenLibraryIds.contains($0.id) }
    }

    private var hiddenLibraries: [Library] {
        viewModel.libraries.filter { hiddenLibraryIds.contains($0.id) }
    }

    private var gridColumns: [GridItem] {
        [
            GridItem(.flexible(minimum: 200), spacing: 24),
            GridItem(.flexible(minimum: 200), spacing: 24),
            GridItem(.flexible(minimum: 200), spacing: 24),
        ]
    }

    private func libraryCard(for library: Library) -> some View {
        ZStack(alignment: .bottomLeading) {
            if let artwork = viewModel.artworkURL(for: library) {
                AsyncImage(url: artwork) { phase in
                    switch phase {
                    case let .success(image):
                        image
                            .resizable()
                            .scaledToFill()
                            .transition(.opacity)
                    case .empty:
                        Color.secondary.opacity(0.1)
                    case .failure:
                        Color.secondary.opacity(0.1)
                    @unknown default:
                        Color.secondary.opacity(0.1)
                    }
                }
                .frame(maxWidth: .infinity, minHeight: 200, maxHeight: 280)
                .clipped()
            } else {
                Color.secondary.opacity(0.08)
                    .frame(maxWidth: .infinity, minHeight: 200, maxHeight: 280)
            }

            LinearGradient(
                colors: [
                    Color.black.opacity(0.6),
                    Color.black.opacity(0.3),
                    .clear,
                ],
                startPoint: .bottom,
                endPoint: .top,
            )
            .frame(maxWidth: .infinity, minHeight: 200, maxHeight: 280)

            HStack(spacing: 12) {
                Image(systemName: library.iconName)
                    .font(.title3)
                    .foregroundStyle(.white)
                    .padding(10)
                    .background(.ultraThinMaterial, in: Circle())

                VStack(alignment: .leading, spacing: 4) {
                    Text(library.title)
                        .font(.headline)
                        .foregroundStyle(.white)

                    Text(library.type.rawValue.capitalized)
                        .font(.subheadline)
                        .foregroundStyle(.white.opacity(0.8))
                }
            }
            .padding(16)
        }
        .frame(maxWidth: .infinity, minHeight: 200, maxHeight: 280, alignment: .leading)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}
