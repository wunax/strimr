import SwiftUI

struct SeerrMediaCard: View {
    let media: SeerrMedia
    let height: CGFloat?
    let width: CGFloat?
    let showsLabels: Bool
    let onTap: () -> Void

    @Environment(\.horizontalSizeClass) private var sizeClass
    #if os(tvOS)
        @Environment(SeerrFocusModel.self) private var focusModel
        @FocusState private var isFocused: Bool
    #endif

    private let aspectRatio: CGFloat = 2 / 3

    init(
        media: SeerrMedia,
        height: CGFloat? = nil,
        width: CGFloat? = nil,
        showsLabels: Bool = true,
        onTap: @escaping () -> Void,
    ) {
        self.media = media
        self.height = height
        self.width = width
        self.showsLabels = showsLabels
        self.onTap = onTap
    }

    private var defaultHeight: CGFloat {
        if sizeClass == .compact {
            180
        } else {
            240
        }
    }

    var body: some View {
        let resolvedHeight = height ?? (width.map { $0 / aspectRatio } ?? defaultHeight)
        let resolvedWidth = width ?? (height.map { $0 * aspectRatio } ?? resolvedHeight * aspectRatio)

        VStack(alignment: .leading, spacing: labelSpacing) {
            SeerrMediaArtworkView(
                media: media,
                width: resolvedWidth,
                height: resolvedHeight,
            )
            #if os(tvOS)
            .scaleEffect(isFocused ? 1.12 : 1)
            .animation(.easeOut(duration: 0.15), value: isFocused)
            #endif

            if showsLabels {
                VStack(alignment: .leading, spacing: 4) {
                    Text(primaryLabel)
                        .font(primaryLabelFont)
                        .lineLimit(1)
                    if let secondaryLabel {
                        Text(secondaryLabel)
                            .font(secondaryLabelFont)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
            }
        }
        .frame(width: resolvedWidth, alignment: .leading)
        #if os(tvOS)
            .focusable()
            .focused($isFocused)
            .onChange(of: isFocused) { _, focused in
                if focused {
                    focusModel.focusedMedia = media
                }
            }
            .onPlayPauseCommand(perform: onTap)
        #endif
        .onTapGesture(perform: onTap)
    }

    private var primaryLabel: String {
        switch media.mediaType {
        case .movie:
            media.title ?? media.name ?? ""
        case .tv, .person:
            media.name ?? media.title ?? ""
        case .none:
            media.title ?? media.name ?? ""
        }
    }

    private var secondaryLabel: String? {
        switch media.mediaType {
        case .movie:
            year(from: media.releaseDate)
        case .tv:
            year(from: media.firstAirDate)
        case .person, .none:
            nil
        }
    }

    private func year(from dateString: String?) -> String? {
        guard let dateString, dateString.count >= 4 else {
            return nil
        }

        return String(dateString.prefix(4))
    }

    private var labelSpacing: CGFloat {
        #if os(tvOS)
            16
        #else
            8
        #endif
    }

    private var primaryLabelFont: Font {
        #if os(tvOS)
            .subheadline
        #else
            .subheadline
        #endif
    }

    private var secondaryLabelFont: Font {
        #if os(tvOS)
            .footnote
        #else
            .footnote
        #endif
    }
}
