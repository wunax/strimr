import Observation
import SwiftUI

struct PersonDetailView: View {
    @State var viewModel: PersonDetailViewModel
    let onSelectMedia: (MediaDisplayItem) -> Void

    private var gridColumns: [GridItem] {
        #if os(tvOS)
            [GridItem(.adaptive(minimum: 200, maximum: 200), spacing: 32, alignment: .top)]
        #else
            [GridItem(.adaptive(minimum: 112, maximum: 112), spacing: 12, alignment: .top)]
        #endif
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: contentSpacing) {
                header
                mediaContent
            }
            .padding(.horizontal, horizontalPadding)
            .padding(.vertical, verticalPadding)
        }
        .navigationTitle(viewModel.person.name)
        #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
        #endif
            .task {
                await viewModel.load()
            }
    }

    private var header: some View {
        HStack(spacing: headerSpacing) {
            portrait

            Text(viewModel.person.name)
                .font(headerFont)
                .fontWeight(.bold)
                .lineLimit(3)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private var mediaContent: some View {
        if viewModel.isLoading, viewModel.items.isEmpty {
            ProgressView("person.detail.loading")
                .frame(maxWidth: .infinity, minHeight: 180)
        } else if let errorMessage = viewModel.mediaErrorMessage, viewModel.items.isEmpty {
            ContentUnavailableView(
                errorMessage,
                systemImage: "exclamationmark.triangle.fill",
                description: Text("common.errors.tryAgainLater"),
            )
            .symbolRenderingMode(.multicolor)
            .frame(maxWidth: .infinity, minHeight: 240)
        } else if viewModel.items.isEmpty {
            ContentUnavailableView(
                "person.detail.empty",
                systemImage: "film.stack",
            )
            .frame(maxWidth: .infinity, minHeight: 240)
        } else {
            LazyVGrid(columns: gridColumns, spacing: gridSpacing) {
                ForEach(viewModel.items, id: \.id) { item in
                    PortraitMediaCard(
                        media: item,
                        width: cardWidth,
                        showsLabels: true,
                    ) {
                        onSelectMedia(item)
                    }
                }
            }
        }
    }

    private var portrait: some View {
        ZStack {
            Circle()
                .fill(Color.white.opacity(0.08))

            if viewModel.imageResource != nil {
                ArtworkResourceView(resource: viewModel.imageResource)
            } else {
                portraitPlaceholder
            }
        }
        .frame(width: portraitSize, height: portraitSize)
        .clipShape(Circle())
    }

    private var portraitPlaceholder: some View {
        VStack(spacing: 8) {
            Image(systemName: "person.fill")
                .font(.title)
                .foregroundStyle(.secondary)
            Text("media.detail.cast.noPhoto")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var cardWidth: CGFloat {
        #if os(tvOS)
            200
        #else
            112
        #endif
    }

    private var portraitSize: CGFloat {
        #if os(tvOS)
            180
        #elseif os(macOS)
            140
        #else
            112
        #endif
    }

    private var portraitPixels: Int {
        Int(portraitSize * 2)
    }

    private var headerFont: Font {
        #if os(tvOS)
            .largeTitle
        #else
            .title
        #endif
    }

    private var headerSpacing: CGFloat {
        #if os(tvOS)
            32
        #else
            20
        #endif
    }

    private var contentSpacing: CGFloat {
        #if os(tvOS)
            48
        #else
            24
        #endif
    }

    private var gridSpacing: CGFloat {
        #if os(tvOS)
            32
        #else
            16
        #endif
    }

    private var horizontalPadding: CGFloat {
        #if os(tvOS)
            48
        #else
            16
        #endif
    }

    private var verticalPadding: CGFloat {
        #if os(tvOS)
            48
        #else
            16
        #endif
    }
}
