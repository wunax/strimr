import SwiftUI

struct LibraryView: View {
    @State var viewModel: LibraryViewModel
    @Environment(SettingsManager.self) private var settingsManager
    let onSelectMedia: (MediaDisplayItem) -> Void

    @State private var isHiddenExpanded = false

    private let contentSpacing: CGFloat = 28
    private let gridSpacing: CGFloat = 20

    init(
        viewModel: LibraryViewModel,
        onSelectMedia: @escaping (MediaDisplayItem) -> Void = { _ in },
    ) {
        _viewModel = State(initialValue: viewModel)
        self.onSelectMedia = onSelectMedia
    }

    var body: some View {
        Group {
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
            } else {
                libraryGrid
            }
        }
        .navigationTitle("tabs.libraries")
        .task {
            await viewModel.load()
        }
    }

    private var libraryGrid: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: contentSpacing) {
                LazyVGrid(columns: columns, alignment: .leading, spacing: gridSpacing) {
                    ForEach(visibleLibraries) { library in
                        libraryLink(for: library)
                    }
                }

                if !hiddenLibraries.isEmpty {
                    hiddenLibrariesSection
                }
            }
            .padding(.horizontal, 28)
            .padding(.top, 24)
            .padding(.bottom, 32)
            .frame(maxWidth: 1400, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
    }

    private var hiddenLibrariesSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            Button {
                isHiddenExpanded.toggle()
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.semibold))
                        .rotationEffect(.degrees(isHiddenExpanded ? 90 : 0))
                        .animation(.easeInOut(duration: 0.12), value: isHiddenExpanded)

                    Label("library.hidden.title", systemImage: "eye.slash")
                        .font(.headline)

                    Spacer()

                    Text(hiddenLibraries.count, format: .number)
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(.quaternary, in: Capsule())
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)

            if isHiddenExpanded {
                LazyVGrid(columns: columns, alignment: .leading, spacing: gridSpacing) {
                    ForEach(hiddenLibraries) { library in
                        libraryLink(for: library)
                    }
                }
            }
        }
        .padding(.top, 4)
    }

    private var columns: [GridItem] {
        [
            GridItem(.adaptive(minimum: 260, maximum: 380), spacing: gridSpacing, alignment: .top),
        ]
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

    private func libraryLink(for library: Library) -> some View {
        NavigationLink(value: library) {
            LibraryCard(
                library: library,
                artworkURL: viewModel.artworkURL(for: library),
            )
        }
        .buttonStyle(.plain)
        .task {
            await viewModel.ensureArtwork(for: library)
        }
    }
}

private struct LibraryCard: View {
    let library: Library
    let artworkURL: URL?

    @State private var isHovering = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            artwork
                .aspectRatio(16 / 9, contentMode: .fit)
                .overlay(alignment: .topLeading) {
                    typeBadge
                        .padding(12)
                }

            HStack(spacing: 12) {
                Image(systemName: library.iconName)
                    .font(.body.weight(.semibold))
                    .foregroundStyle(.tint)
                    .frame(width: 30, height: 30)
                    .background(.tint.opacity(0.12), in: RoundedRectangle(cornerRadius: 8))

                Text(library.title)
                    .font(.headline)
                    .lineLimit(1)
                    .help(library.title)

                Spacer(minLength: 8)

                Image(systemName: "chevron.right")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.tertiary)
                    .offset(x: isHovering ? 2 : 0)
            }
            .padding(14)
        }
        .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(isHovering ? Color.accentColor.opacity(0.55) : .white.opacity(0.08), lineWidth: 1)
        }
        .shadow(
            color: .black.opacity(isHovering ? 0.18 : 0.08),
            radius: isHovering ? 14 : 6,
            y: isHovering ? 7 : 3
        )
        .scaleEffect(isHovering ? 1.015 : 1)
        .animation(.easeOut(duration: 0.16), value: isHovering)
        .onHover { isHovering = $0 }
        .accessibilityElement(children: .combine)
    }

    private var artwork: some View {
        ZStack {
            LinearGradient(
                colors: [.accentColor.opacity(0.22), .black.opacity(0.28)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing,
            )

            Image(systemName: library.iconName)
                .font(.system(size: 42, weight: .medium))
                .foregroundStyle(.white.opacity(0.35))

            if let artworkURL {
                AsyncImage(url: artworkURL) { phase in
                    switch phase {
                    case let .success(image):
                        image
                            .resizable()
                            .scaledToFill()
                            .transition(.opacity)
                    case .empty:
                        ProgressView()
                            .controlSize(.small)
                            .tint(.white.opacity(0.8))
                    case .failure:
                        EmptyView()
                    @unknown default:
                        EmptyView()
                    }
                }
            }
        }
        .clipped()
    }

    private var typeBadge: some View {
        Text(typeTitle)
            .font(.caption.weight(.semibold))
            .foregroundStyle(.white)
            .padding(.horizontal, 9)
            .padding(.vertical, 5)
            .background(.black.opacity(0.48), in: Capsule())
            .overlay {
                Capsule()
                    .strokeBorder(.white.opacity(0.15))
            }
    }

    private var typeTitle: LocalizedStringKey {
        switch library.type {
        case .movie:
            "search.filter.movies"
        case .show:
            "search.filter.shows"
        default:
            "tabs.libraries"
        }
    }
}
