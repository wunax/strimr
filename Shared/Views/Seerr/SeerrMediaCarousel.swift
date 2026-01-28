import SwiftUI

struct SeerrMediaCarousel: View {
    let items: [SeerrMedia]
    let showsLabels: Bool
    let onSelectMedia: (SeerrMedia) -> Void

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            LazyHStack(alignment: .top, spacing: spacing) {
                ForEach(items, id: \.id) { media in
                    SeerrMediaCard(media: media, showsLabels: showsLabels) {
                        onSelectMedia(media)
                    }
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

    private var spacing: CGFloat {
        #if os(tvOS)
            20
        #else
            12
        #endif
    }
}
