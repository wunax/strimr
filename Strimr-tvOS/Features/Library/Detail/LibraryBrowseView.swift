import SwiftUI

struct LibraryBrowseView: View {
    @State var viewModel: LibraryBrowseViewModel
    let onSelectMedia: (MediaItem) -> Void

    @FocusState private var focusedCharacterId: String?

    private let gridColumns = [
        GridItem(.adaptive(minimum: 200, maximum: 280), spacing: 32),
    ]

    init(
        viewModel: LibraryBrowseViewModel,
        onSelectMedia: @escaping (MediaItem) -> Void = { _ in }
    ) {
        _viewModel = State(initialValue: viewModel)
        self.onSelectMedia = onSelectMedia
    }

    var body: some View {
        ScrollViewReader { proxy in
            HStack(alignment: .top, spacing: 32) {
                ScrollView {
                    LazyVGrid(columns: gridColumns, spacing: 32) {
                        ForEach(0 ..< viewModel.totalItemCount, id: \.self) { index in
                            Group {
                                if let media = viewModel.itemsByIndex[index] {
                                    PortraitMediaCard(media: media, showsLabels: true) {
                                        onSelectMedia(media)
                                    }
                                } else {
                                    ProgressView()
                                }
                            }
                            .frame(maxWidth: .infinity, minHeight: 300)
                            .id(index)
                            .onAppear {
                                Task {
                                    await viewModel.loadPagesAround(index: index)
                                }
                            }
                        }
                    }
                    .padding(.horizontal, 48)
                    .padding(.top, 32)
                    .padding(.bottom, 48)
                }
                .frame(maxWidth: .infinity)

                characterColumn(proxy: proxy)
            }
            .overlay {
                if viewModel.isLoading && viewModel.itemsByIndex.isEmpty {
                    ProgressView("library.browse.loading")
                } else if let errorMessage = viewModel.errorMessage, viewModel.itemsByIndex.isEmpty {
                    ContentUnavailableView(
                        errorMessage,
                        systemImage: "exclamationmark.triangle.fill",
                        description: Text("common.errors.tryAgainLater")
                    )
                    .symbolRenderingMode(.multicolor)
                } else if viewModel.totalItemCount == 0 && !viewModel.isLoading {
                    ContentUnavailableView(
                        "library.browse.empty.title",
                        systemImage: "square.grid.2x2.fill",
                        description: Text("library.browse.empty.description")
                    )
                }
            }
            .task {
                await viewModel.load()
            }
        }
    }

    private func characterColumn(proxy: ScrollViewProxy) -> some View {
        VStack(spacing: 4) {
            ForEach(viewModel.sectionCharacters) { character in
                characterButton(character, proxy: proxy)
            }
        }
        .padding(.trailing, 20)
        .padding(.top, 20)
        .frame(width: 44, alignment: .top)
    }

    private func characterButton(
        _ character: LibraryBrowseViewModel.SectionCharacter,
        proxy: ScrollViewProxy
    ) -> some View {
        let isFocused = focusedCharacterId == character.id
        return Button {
            Task {
                await viewModel.loadPagesAround(index: character.startIndex)
                withAnimation(.easeInOut(duration: 0.2)) {
                    proxy.scrollTo(character.startIndex, anchor: .top)
                }
            }
        } label: {
            Text(character.title)
                .font(.caption2)
                .frame(width: 32, height: 32)
                .background(isFocused ? Color.white.opacity(0.2) : Color.clear)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .buttonStyle(.plain)
        .focused($focusedCharacterId, equals: character.id)
        .animation(.easeInOut(duration: 0.2), value: isFocused)
    }
}
