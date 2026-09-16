import Observation
import SwiftUI

struct ExtrasSection: View {
    @Bindable var viewModel: MediaDetailViewModel
    let onPlay: (MediaItem) -> Void

    init(
        viewModel: MediaDetailViewModel,
        onPlay: @escaping (MediaItem) -> Void,
    ) {
        self.viewModel = viewModel
        self.onPlay = onPlay
    }

    var body: some View {
        if !viewModel.extras.isEmpty {
            Section {
                VStack(alignment: .leading, spacing: 12) {
                    Divider()

                    Text("media.detail.extras")
                        .font(.headline)
                        .fontWeight(.semibold)

                    MediaCarousel(
                        layout: .landscape,
                        items: viewModel.extras.map(MediaDisplayItem.playable),
                        showsLabels: true,
                        onSelectMedia: { media in
                            guard let item = media.playableItem else { return }
                            onPlay(item)
                        },
                    )
                }
                .padding(.horizontal, extrasSectionHorizontalPadding)
            }
            .textCase(nil)
        }
    }
}

private var extrasSectionHorizontalPadding: CGFloat {
    #if os(macOS)
        28
    #elseif os(iOS)
        16
    #else
        0
    #endif
}
