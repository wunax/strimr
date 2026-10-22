import Observation
import SwiftUI

struct ExtrasSection: View {
    @Bindable var viewModel: MediaDetailViewModel
    let onPlay: (MediaItem) -> Void

    var body: some View {
        if !viewModel.extras.isEmpty {
            Section {
                VStack(alignment: .leading, spacing: 12) {
                    Divider()

                    MediaHubSection(title: String(localized: "media.detail.extras")) {
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
                }
                .padding(.horizontal, LayoutMetrics.detailSectionMargin)
                .environment(\.railPageMargin, LayoutMetrics.detailSectionMargin)
            }
            .textCase(nil)
        }
    }
}
