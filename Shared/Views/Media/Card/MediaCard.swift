import SwiftUI

struct MediaCard: View {
    @Environment(PlexAPIContext.self) private var plexApiContext
    #if os(tvOS)
        @Environment(MediaFocusModel.self) private var focusModel
        @FocusState private var isFocused: Bool
    #endif

    let size: CGSize
    let media: MediaItem
    let artworkKind: MediaImageViewModel.ArtworkKind
    let showsLabels: Bool
    let onTap: () -> Void

    private var progress: Double? {
        media.viewProgressPercentage.map { $0 / 100 }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            MediaImageView(
                viewModel: MediaImageViewModel(
                    context: plexApiContext,
                    artworkKind: artworkKind,
                    media: media,
                ),
            )
            .frame(width: size.width, height: size.height)
            .clipShape(
                RoundedRectangle(cornerRadius: 14, style: .continuous),
            )
            .overlay(alignment: .topTrailing) {
                WatchStatusBadge(media: media)
            }
            .overlay(alignment: .bottomLeading) {
                if let progress {
                    ProgressView(value: progress)
                        .progressViewStyle(.linear)
                        .tint(.brandPrimary)
                        .padding(.horizontal, 10)
                        .padding(.bottom, 10)
                }
            }

            if showsLabels {
                VStack(alignment: .leading, spacing: 4) {
                    Text(media.primaryLabel)
                        .font(.headline)
                        .lineLimit(1)
                    Text(media.secondaryLabel ?? "")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                    Text(media.tertiaryLabel ?? "")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
        }
        .frame(width: size.width, alignment: .leading)
        #if os(tvOS)
        .focusable()
        .focused($isFocused)
        .overlay {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(
                    isFocused ? Color.brandSecondary : .clear,
                    lineWidth: 4,
                )
        }
        .animation(.easeOut(duration: 0.15), value: isFocused)
        .onChange(of: isFocused) { _, focused in
            if focused {
                focusModel.focusedMedia = media
            }
        }
        .onPlayPauseCommand(perform: onTap)
        #endif
        .onTapGesture(perform: onTap)
    }
}
