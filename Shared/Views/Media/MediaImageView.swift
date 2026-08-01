import SwiftUI

struct MediaImageView: View {
    @Environment(SettingsManager.self) private var settingsManager
    @State var viewModel: MediaImageViewModel

    private var spoilerProtection: SpoilerProtectionLevel {
        settingsManager.interface.spoilerProtection
    }

    private var isSpoilerProtected: Bool {
        viewModel.media.playableItem?.isSpoilerProtected(at: spoilerProtection) == true
    }

    var body: some View {
        Group {
            if let url = viewModel.imageURL {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .empty:
                        ProgressView()
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    case let .success(image):
                        image
                            .resizable()
                            .scaledToFill()
                    case .failure:
                        placeholder
                    @unknown default:
                        EmptyView()
                    }
                }
            } else {
                placeholder
            }
        }
        .overlay(alignment: .topLeading) {
            if isSpoilerProtected {
                SpoilerProtectionIndicator()
                    .padding(8)
            }
        }
        .task(id: "\(viewModel.media.id)-\(viewModel.artworkKind.rawValue)-\(spoilerProtection.rawValue)") {
            viewModel.spoilerProtection = spoilerProtection
            await viewModel.load()
        }
    }

    private var placeholder: some View {
        VStack {
            Image(systemName: "film")
                .font(.title2)
                .foregroundStyle(.secondary)
            Text("media.placeholder.noArtwork")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct SpoilerProtectionIndicator: View {
    var body: some View {
        Image(systemName: "eye.slash.fill")
            .font(.caption.weight(.semibold))
            .foregroundStyle(.primary)
            .padding(7)
            .background(.ultraThinMaterial, in: Circle())
            .accessibilityLabel("media.spoilerProtection.artworkHidden")
    }
}
