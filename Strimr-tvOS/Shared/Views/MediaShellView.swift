import SwiftUI

struct MediaShellView<Content: View>: View {
    @Environment(MediaFocusModel.self) private var focusModel

    let media: MediaItem
    let content: Content

    init(media: MediaItem, @ViewBuilder content: () -> Content) {
        self.media = media
        self.content = content()
    }

    var body: some View {
        GeometryReader { proxy in
            HStack(alignment: .top, spacing: 0) {
                content
                    .frame(width: proxy.size.width * 0.52, alignment: .leading)
                    .padding(.leading, 48)
                    .padding(.vertical, 40)

                VStack(alignment: .leading, spacing: 0) {
                    MediaHeroView(media: focusModel.focusedMedia ?? media)
                        .frame(height: proxy.size.height * 0.5)
                    Spacer()
                }
                .frame(width: proxy.size.width * 0.48, alignment: .topLeading)
                .padding(.trailing, 48)
                .padding(.vertical, 40)
            }
        }
    }
}

#Preview {
    let sample = MediaItem(
        id: "sample",
        summary: nil,
        title: String(localized: "tabs.home"),
        type: .show,
        parentRatingKey: nil,
        grandparentRatingKey: nil,
        genres: ["Sci-Fi"],
        year: 2024,
        duration: nil,
        rating: nil,
        contentRating: nil,
        studio: nil,
        tagline: nil,
        thumbPath: nil,
        artPath: nil,
        ultraBlurColors: nil,
        viewOffset: nil,
        viewCount: nil,
        childCount: 2,
        leafCount: nil,
        viewedLeafCount: nil,
        grandparentTitle: nil,
        parentTitle: nil,
        parentIndex: nil,
        index: nil,
        grandparentThumbPath: nil,
        grandparentArtPath: nil,
        parentThumbPath: nil
    )

    return MediaShellView(media: sample) {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("tabs.home")
                    .font(.largeTitle.bold())
                ForEach(0..<6, id: \.self) { _ in
                    RoundedRectangle(cornerRadius: 18)
                        .fill(Color.white.opacity(0.1))
                        .frame(height: 140)
                }
            }
        }
    }
    .environment(MediaFocusModel(focusedMedia: sample))
    .environment(PlexAPIContext())
    .background(Color("Background"))
}
