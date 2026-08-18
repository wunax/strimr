import Observation
import SwiftUI

@MainActor
@Observable
final class LibraryGenresViewModel {
    let library: Library
    var genres: [LibraryGenre] = []
    var isLoading = false
    var errorMessage: String?

    @ObservationIgnored private let service: any AdvancedLibraryBrowseService

    init?(library: Library, services: MediaServices) {
        guard let service = services.library as? any AdvancedLibraryBrowseService else { return nil }
        self.library = library
        self.service = service
    }

    func load() async {
        guard genres.isEmpty, !isLoading else { return }
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            genres = try await service.genres(in: library)
        } catch {
            guard !error.isCancellation else { return }
            ErrorReporter.capture(error)
            errorMessage = error.localizedDescription
        }
    }
}

struct LibraryGenresView: View {
    @State var viewModel: LibraryGenresViewModel
    let onSelectGenre: (LibraryGenre) -> Void

    private var columns: [GridItem] {
        #if os(tvOS)
            [GridItem(.adaptive(minimum: 280, maximum: 360), spacing: 32)]
        #else
            [GridItem(.adaptive(minimum: 180, maximum: 260), spacing: 16)]
        #endif
    }

    var body: some View {
        ScrollView {
            LazyVGrid(columns: columns, spacing: gridSpacing) {
                ForEach(viewModel.genres) { genre in
                    LibraryGenreCard(genre: genre, height: cardHeight) {
                        onSelectGenre(genre)
                    }
                }
            }
            .padding(contentPadding)
        }
        .overlay {
            if viewModel.isLoading, viewModel.genres.isEmpty {
                ProgressView("library.genres.loading")
            } else if let errorMessage = viewModel.errorMessage, viewModel.genres.isEmpty {
                ContentUnavailableView(
                    errorMessage,
                    systemImage: "exclamationmark.triangle.fill",
                    description: Text("common.errors.tryAgainLater"),
                )
                .symbolRenderingMode(.multicolor)
            } else if viewModel.genres.isEmpty {
                ContentUnavailableView(
                    "library.genres.empty.title",
                    systemImage: "theatermasks.fill",
                    description: Text("library.genres.empty.description"),
                )
            }
        }
        .task { await viewModel.load() }
    }

    private var gridSpacing: CGFloat {
        #if os(tvOS)
            32
        #else
            16
        #endif
    }

    private var cardHeight: CGFloat {
        #if os(tvOS)
            150
        #else
            110
        #endif
    }

    private var contentPadding: EdgeInsets {
        #if os(tvOS)
            EdgeInsets(top: 32, leading: 48, bottom: 48, trailing: 48)
        #else
            EdgeInsets(top: 16, leading: 16, bottom: 24, trailing: 16)
        #endif
    }
}

private struct LibraryGenreCard: View {
    let genre: LibraryGenre
    let height: CGFloat
    let action: () -> Void
    #if os(tvOS)
        @FocusState private var isFocused: Bool
    #endif

    var body: some View {
        Button(action: action) {
            Text(genre.title)
                .font(.headline)
                .fontWeight(.semibold)
                .lineLimit(2)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity, minHeight: height)
                .padding(.horizontal, 16)
                .background {
                    LinearGradient(
                        colors: [Color.brandPrimary.opacity(0.55), Color.brandPrimary.opacity(0.18)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing,
                    )
                }
                .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        }
        .buttonStyle(.plain)
        #if os(tvOS)
            .focused($isFocused)
            .scaleEffect(isFocused ? 1.08 : 1)
            .overlay {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(.white.opacity(isFocused ? 0.9 : 0), lineWidth: 3)
            }
            .animation(.easeOut(duration: 0.15), value: isFocused)
        #endif
    }
}
