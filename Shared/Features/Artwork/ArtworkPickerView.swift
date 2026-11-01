#if os(iOS)
    import PhotosUI
#endif
import SwiftUI
import UniformTypeIdentifiers

struct ArtworkPickerView: View {
    @Environment(\.dismiss) private var dismiss
    @State var viewModel: ArtworkPickerViewModel
    #if os(iOS)
        @State private var photoSelection: PhotosPickerItem?
    #elseif os(macOS)
        @State private var isImportingFile = false
    #endif

    var body: some View {
        @Bindable var bindableViewModel = viewModel

        TaskModalNavigationView {
            content
                .taskModalTitle("media.artwork.title")
                .taskModalActions {
                    Button("common.actions.done") { dismiss() }
                } actions: {
                    uploadButton
                }
                .alert(item: $bindableViewModel.failure) { failure in
                    Alert(
                        title: Text("media.artwork.error"),
                        message: Text(failure.message),
                        dismissButton: .default(Text("common.actions.done")),
                    )
                }
        }
        #if os(macOS)
        .frame(minWidth: 720, minHeight: 560)
        #endif
        .task(id: viewModel.selectedKind) {
            await viewModel.load()
        }
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: 16) {
            if viewModel.kinds.count > 1 {
                kindPicker
            }
            if viewModel.hasOtherLanguages {
                Toggle("media.artwork.allLanguages", isOn: $viewModel.includesAllLanguages)
                    .padding(.horizontal, horizontalMargin)
            }
            options
        }
        .padding(.top, 8)
    }

    private var kindPicker: some View {
        ScrollView(.horizontal) {
            HStack(spacing: LayoutMetrics.chipSpacing) {
                ForEach(viewModel.kinds, id: \.self) { kind in
                    Button(kind.title) {
                        viewModel.selectedKind = kind
                    }
                    .buttonStyle(.chip(isSelected: kind == viewModel.selectedKind))
                }
            }
            .padding(.horizontal, horizontalMargin)
            .padding(.vertical, 8)
        }
        .scrollIndicators(.hidden)
        #if os(tvOS)
            .focusSection()
        #endif
    }

    @ViewBuilder
    private var options: some View {
        if let errorMessage = viewModel.errorMessage {
            ContentUnavailableView {
                Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                    .symbolRenderingMode(.multicolor)
            } description: {
                Text("common.errors.tryAgainLater")
            } actions: {
                Button("common.actions.retry") {
                    Task { await viewModel.load(force: true) }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if !viewModel.hasLoadedOptions {
            ProgressView()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if viewModel.visibleOptions.isEmpty {
            ContentUnavailableView("media.artwork.empty", systemImage: "photo")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            ScrollView {
                LazyVGrid(
                    columns: [GridItem(.adaptive(minimum: tileWidth), spacing: tileSpacing)],
                    spacing: tileSpacing,
                ) {
                    ForEach(viewModel.visibleOptions) { option in
                        ArtworkOptionTile(
                            option: option,
                            kind: viewModel.selectedKind,
                            isApplying: viewModel.applyingOptionID == option.id,
                        ) {
                            Task { await viewModel.select(option) }
                        }
                        .disabled(viewModel.isBusy)
                    }
                }
                .padding(.horizontal, horizontalMargin)
                .padding(.vertical, gridVerticalPadding)
            }
            #if os(tvOS)
            // tvOS modals let scroll views overflow so focused tiles can grow; the grid must still not scroll over
            // the kind picker and the title above it.
            .mask {
                Rectangle()
                    .padding(.horizontal, -40)
            }
            .focusSection()
            #endif
        }
    }

    /// Leaves room for the focus lift of the first and last rows, which the tvOS mask would cut.
    private var gridVerticalPadding: CGFloat {
        #if os(tvOS)
            28
        #else
            12
        #endif
    }

    @ViewBuilder
    private var uploadButton: some View {
        #if os(iOS)
            PhotosPicker(selection: $photoSelection, matching: .images) {
                uploadLabel
            }
            .disabled(viewModel.isBusy)
            .onChange(of: photoSelection) {
                guard let selection = photoSelection else { return }
                photoSelection = nil
                Task {
                    guard let data = try? await selection.loadTransferable(type: Data.self) else {
                        viewModel.failure = .init(message: String(localized: "media.artwork.upload.invalidImage"))
                        return
                    }
                    await viewModel.upload(data)
                }
            }
        #elseif os(macOS)
            Button {
                isImportingFile = true
            } label: {
                uploadLabel
            }
            .disabled(viewModel.isBusy)
            .fileImporter(isPresented: $isImportingFile, allowedContentTypes: [.image]) { result in
                guard case let .success(url) = result else { return }
                Task {
                    guard let data = await Self.contents(of: url) else {
                        viewModel.failure = .init(message: String(localized: "media.artwork.upload.invalidImage"))
                        return
                    }
                    await viewModel.upload(data)
                }
            }
        #endif
    }

    @ViewBuilder
    private var uploadLabel: some View {
        if viewModel.isUploading {
            ProgressView()
        } else {
            Label("media.artwork.upload", systemImage: "square.and.arrow.up")
        }
    }

    #if os(macOS)
        @concurrent
        private nonisolated static func contents(of url: URL) async -> Data? {
            let isAccessing = url.startAccessingSecurityScopedResource()
            defer {
                if isAccessing {
                    url.stopAccessingSecurityScopedResource()
                }
            }
            return try? Data(contentsOf: url)
        }
    #endif

    private var horizontalMargin: CGFloat {
        #if os(tvOS)
            24
        #else
            LayoutMetrics.pageMargin
        #endif
    }

    private var tileSpacing: CGFloat {
        #if os(tvOS)
            32
        #else
            16
        #endif
    }

    private var tileWidth: CGFloat {
        let posterWidth: CGFloat
        #if os(tvOS)
            posterWidth = 170
        #elseif os(macOS)
            posterWidth = 140
        #else
            posterWidth = 104
        #endif
        switch viewModel.selectedKind {
        case .poster: return posterWidth
        case .background, .thumb, .logo: return posterWidth * 1.6
        case .banner: return posterWidth * 2.6
        }
    }
}

private struct ArtworkOptionTile: View {
    let option: ArtworkOption
    let kind: EditableArtworkKind
    let isApplying: Bool
    let action: () -> Void

    private let shape = RoundedRectangle(cornerRadius: LayoutMetrics.cardCornerRadius, style: .continuous)

    private var selectionLineWidth: CGFloat {
        #if os(tvOS)
            4
        #else
            3
        #endif
    }

    var body: some View {
        Button(action: action) {
            Color.surfaceSubtle
                .aspectRatio(kind.aspectRatio, contentMode: .fit)
                .overlay {
                    ArtworkResourceView(resource: .url(option.previewURL), contentMode: kind == .logo ? .fit : .fill)
                        .padding(kind == .logo ? 12 : 0)
                }
                .overlay(alignment: .bottomLeading) { badges }
                .overlay {
                    if isApplying {
                        ZStack {
                            Color.overlayScrim
                            ProgressView()
                        }
                    }
                }
                .clipShape(shape)
                .overlay {
                    if option.isSelected {
                        shape.strokeBorder(Color.selectionAccent, lineWidth: selectionLineWidth)
                    }
                }
                .overlay(alignment: .topTrailing) {
                    if option.isSelected {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.title3)
                            .symbolRenderingMode(.palette)
                            .foregroundStyle(.white, Color.selectionAccent)
                            .padding(8)
                    }
                }
        }
        // The system card style clips the label to its own shape, which cut the selection border on tvOS.
        .buttonStyle(.cardLift)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityAddTraits(option.isSelected ? .isSelected : [])
    }

    @ViewBuilder
    private var badges: some View {
        let labels = [option.provider.map(Self.providerName), option.language?.uppercased()].compactMap(\.self)
        if !labels.isEmpty {
            HStack(spacing: 4) {
                ForEach(labels, id: \.self) { label in
                    Text(verbatim: label)
                        .font(.badge)
                        .foregroundStyle(.textPrimary)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 3)
                        .background(.badgeBackground, in: Capsule(style: .continuous))
                }
            }
            .padding(6)
        }
    }

    private var accessibilityLabel: Text {
        guard let provider = option.provider else { return Text(kind.title) }
        return Text(verbatim: "\(kind.title), \(Self.providerName(provider))")
    }

    /// Plex sends lowercase identifiers; Jellyfin sends display names, kept as they are.
    private nonisolated static func providerName(_ provider: String) -> String {
        switch provider.lowercased() {
        case "tmdb": "TMDB"
        case "tvdb": "TVDB"
        case "imdb": "IMDb"
        case "fanarttv": "Fanart.tv"
        case "gracenote": "Gracenote"
        default: provider
        }
    }
}
