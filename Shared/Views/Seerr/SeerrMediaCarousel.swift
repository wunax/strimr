import SwiftUI

struct SeerrMediaCarousel: View {
    @Environment(\.railPageMargin) private var pageMargin

    let items: [SeerrMedia]
    let showsLabels: Bool
    let onSelectMedia: (SeerrMedia) -> Void

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            LazyHStack(alignment: .top, spacing: LayoutMetrics.railSpacing(for: .portrait)) {
                ForEach(items, id: \.id) { media in
                    SeerrMediaCard(media: media, showsLabels: showsLabels) {
                        onSelectMedia(media)
                    }
                }
            }
            .padding(.vertical, LayoutMetrics.railVerticalInset)
        }
        #if !os(tvOS)
        // Gives the lifted card room inside the clipping scroll view without moving the rail.
        .padding(.vertical, -LayoutMetrics.railVerticalInset)
        #endif
        .railBleed(pageMargin: pageMargin)
        .mouseDragScrolling()
        #if os(tvOS)
            .scrollClipDisabled()
            .focusSection()
        #endif
    }
}
