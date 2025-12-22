import Observation
import SwiftUI

struct RelatedHubsSection: View {
    @Bindable var viewModel: MediaDetailViewModel
    let onSelectMedia: (MediaItem) -> Void

    var body: some View {
        Section {
            VStack(alignment: .leading, spacing: 12) {
                Divider()

                relatedContent
                    .padding(.horizontal, 8)
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 32)
        }
        .textCase(nil)
    }

    @ViewBuilder
    private var relatedContent: some View {
        if let errorMessage = viewModel.relatedHubsErrorMessage {
            Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                .foregroundStyle(.red)
                .font(.subheadline)
        } else if viewModel.isLoadingRelatedHubs && viewModel.relatedHubs.isEmpty {
            HStack(spacing: 8) {
                ProgressView()
                    .controlSize(.small)
                Text("media.detail.loadingRelated")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        } else if viewModel.relatedHubs.isEmpty {
            Text("media.detail.noRelated")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        } else {
            VStack(alignment: .leading, spacing: 20) {
                ForEach(viewModel.relatedHubs) { hub in
                    VStack(alignment: .leading, spacing: 12) {
                        Text(hub.title)
                            .font(.headline)
                            .fontWeight(.semibold)

                        MediaCarousel(
                            layout: .portrait,
                            items: hub.items,
                            onSelectMedia: onSelectMedia
                        )
                    }
                }
            }
        }
    }
}
