import SwiftUI

struct LibraryTVView: View {
    @State var viewModel: LibraryViewModel
    @Environment(SettingsManager.self) private var settingsManager
    let onSelectMedia: (MediaDisplayItem) -> Void
    private let cardMinHeight: CGFloat = 240
    private let cardMaxHeight: CGFloat = 380
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
                LazyVGrid(columns: gridColumns, spacing: 48) {
                    ForEach(visibleLibraries) { library in
                        NavigationLink(value: library) {
                            libraryCard(for: library)
                        }
                        .buttonStyle(.plain)
                        .task {
                            await viewModel.ensureArtwork(for: library)
                        }
                    }
                }

                if !hiddenLibraries.isEmpty {
                    VStack(alignment: .leading, spacing: 24) {
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
                            LazyVGrid(columns: gridColumns, spacing: 48) {
                                ForEach(hiddenLibraries) { library in
                                    NavigationLink(value: library) {
                                        libraryCard(for: library)
                                    }
                                    .buttonStyle(.plain)
                                    .task {
                                        await viewModel.ensureArtwork(for: library)
                                    }
                                }
                            }
                        }
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 20)
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
            GridItem(.flexible(minimum: 140), spacing: 48),
            GridItem(.flexible(minimum: 140), spacing: 48),
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
                        Color.gray.opacity(0.1)
                    case .failure:
                        Color.gray.opacity(0.1)
                    @unknown default:
                        Color.gray.opacity(0.1)
                    }
                }
                .frame(maxWidth: .infinity, minHeight: cardMinHeight, maxHeight: cardMaxHeight)
                .clipped()
            } else {
                Color.gray.opacity(0.08)
                    .frame(maxWidth: .infinity, minHeight: cardMinHeight, maxHeight: cardMaxHeight)
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
            .frame(maxWidth: .infinity, minHeight: cardMinHeight, maxHeight: cardMaxHeight)

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
        .frame(maxWidth: .infinity, minHeight: cardMinHeight, maxHeight: cardMaxHeight, alignment: .leading)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .shadow(color: .black.opacity(0.08), radius: 8, x: 0, y: 4)
    }
}
