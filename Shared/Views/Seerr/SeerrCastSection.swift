import Observation
import SwiftUI

struct SeerrCastSection: View {
    @Bindable var viewModel: SeerrMediaDetailViewModel

    var body: some View {
        if viewModel.isLoading || !viewModel.cast.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                Divider()

                MediaHubSection(title: String(localized: "media.detail.cast.title")) {
                    if viewModel.cast.isEmpty {
                        CastSkeleton()
                    } else {
                        SeerrCastCarousel(viewModel: viewModel)
                    }
                }
            }
            .padding(.horizontal, LayoutMetrics.detailSectionMargin)
            .environment(\.railPageMargin, LayoutMetrics.detailSectionMargin)
            .padding(.bottom, 32)
        }
    }
}

private struct SeerrCastCarousel: View {
    @Environment(\.railPageMargin) private var pageMargin
    @Bindable var viewModel: SeerrMediaDetailViewModel

    private let imageSize = LayoutMetrics.castAvatarSize * 2

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            LazyHStack(alignment: .top, spacing: LayoutMetrics.railSpacing(for: .portrait)) {
                ForEach(viewModel.cast) { member in
                    // Seerr people have no page in the app, so the cards are not selectable.
                    CastCard(
                        member: CastMember(
                            id: String(member.id),
                            personID: nil,
                            name: member.name ?? "",
                            character: member.character,
                            thumbPath: nil,
                        ),
                        imageURL: viewModel.castImageURL(for: member, width: imageSize, height: imageSize),
                        artworkPath: nil,
                        onSelect: nil,
                    )
                }
            }
            .padding(.vertical, LayoutMetrics.railVerticalInset)
        }
        #if !os(tvOS)
        .padding(.vertical, -LayoutMetrics.railVerticalInset)
        #endif
        .railBleed(pageMargin: pageMargin)
        .mouseDragScrolling()
        #if os(tvOS)
            .scrollClipDisabled()
        #endif
    }
}
