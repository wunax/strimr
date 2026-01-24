import SwiftUI

struct MediaCarousel: View {
    enum Layout { case portrait, landscape }

    let layout: Layout
    let items: [MediaDisplayItem]
    let showsLabels: Bool
    let onSelectMedia: (MediaDisplayItem) -> Void

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            LazyHStack(alignment: .top, spacing: spacing(for: layout)) {
                ForEach(items, id: \.id) { item in
                    card(for: item)
                }
            }
            #if os(tvOS)
            .padding(.vertical, 14)
            .padding(.horizontal, 8)
            #else
            .padding(.horizontal, 2)
            #endif
        }
        #if os(tvOS)
        .focusSection()
        #endif
    }

    @ViewBuilder
    private func card(for media: MediaDisplayItem) -> some View {
        switch layout {
        case .portrait:
            PortraitMediaCard(media: media, showsLabels: showsLabels) {
                onSelectMedia(media)
            }
        case .landscape:
            LandscapeMediaCard(media: media, showsLabels: showsLabels) {
                onSelectMedia(media)
            }
        }
    }

    private func spacing(for layout: Layout) -> CGFloat {
        switch layout {
        case .portrait:
            #if os(tvOS)
                20
            #else
                12
            #endif
        case .landscape:
            #if os(tvOS)
                24
            #else
                16
            #endif
        }
    }
}
