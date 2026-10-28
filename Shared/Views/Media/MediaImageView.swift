import SwiftUI

enum MediaArtworkMetrics {
    static let compactCornerRadius: CGFloat = 12
    static let cornerRadius: CGFloat = 14
    static let largeDetailCornerRadius: CGFloat = 24
}

enum MediaArtworkStyle {
    case compact
    case standard
    case largeDetail

    fileprivate var cornerRadius: CGFloat {
        switch self {
        case .compact:
            MediaArtworkMetrics.compactCornerRadius
        case .standard:
            MediaArtworkMetrics.cornerRadius
        case .largeDetail:
            MediaArtworkMetrics.largeDetailCornerRadius
        }
    }
}

private struct MediaArtworkStyleModifier: ViewModifier {
    let style: MediaArtworkStyle
    let borderColor: Color

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: style.cornerRadius, style: .continuous)

        content
            .containerShape(shape)
            .clipShape(shape)
            // Clipping does not limit hit testing: a scaled-to-fill image would take taps meant for its neighbors.
            .contentShape(shape)
            .overlay {
                shape.strokeBorder(borderColor, lineWidth: 1)
            }
    }
}

extension View {
    func mediaArtworkStyle(
        _ style: MediaArtworkStyle = .standard,
        borderColor: Color = Color.primary.opacity(0.08),
    ) -> some View {
        modifier(MediaArtworkStyleModifier(style: style, borderColor: borderColor))
    }
}

struct MediaArtworkPlaceholder: View {
    let mediaKind: MediaKind?

    init(mediaKind: MediaKind? = nil) {
        self.mediaKind = mediaKind
    }

    var body: some View {
        GeometryReader { proxy in
            let shortestSide = min(proxy.size.width, proxy.size.height)
            let iconSize = min(max(shortestSide * 0.2, 18), 42)
            let showsLabel = proxy.size.width >= 110 && proxy.size.height >= 100

            ZStack {
                ContainerRelativeShape()
                    .fill(.surfaceSubtle)

                VStack(spacing: 10) {
                    Image(systemName: systemImage)
                        .font(.system(size: iconSize, weight: .semibold))
                        .foregroundStyle(.textTertiary)
                        .frame(width: iconSize * 2, height: iconSize * 2)
                        .background(.surfaceSubtle, in: Circle())

                    if showsLabel {
                        Text("media.placeholder.noArtwork")
                            .font(.cardMetadata.weight(.medium))
                            .foregroundStyle(.textTertiary)
                            .multilineTextAlignment(.center)
                    }
                }
                .padding(12)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("media.placeholder.noArtwork")
    }

    private var systemImage: String {
        switch mediaKind {
        case .movie:
            "film.stack.fill"
        case .series:
            "tv.fill"
        case .season, .collection:
            "rectangle.stack.fill"
        case .episode, .clip:
            "play.rectangle.fill"
        case .playlist:
            "music.note.list"
        case .folder:
            "folder.fill"
        case .unknown, nil:
            "film.fill"
        }
    }
}

struct MediaImageView: View {
    @Environment(SettingsManager.self) private var settingsManager
    @State private var viewModel: MediaImageViewModel

    init(viewModel: MediaImageViewModel) {
        _viewModel = State(initialValue: viewModel)
    }

    private var spoilerProtection: SpoilerProtectionLevel {
        settingsManager.interface.spoilerProtection
    }

    private var isSpoilerProtected: Bool {
        viewModel.media.playableItem?.isSpoilerProtected(at: spoilerProtection) == true
    }

    var body: some View {
        Group {
            if viewModel.resource != nil {
                ArtworkResourceView(resource: viewModel.resource)
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
        MediaArtworkPlaceholder(mediaKind: viewModel.media.type)
    }
}

struct SpoilerProtectionIndicator: View {
    var body: some View {
        Image(systemName: "eye.slash.fill")
            .font(.caption.weight(.semibold))
            .foregroundStyle(.primary)
            .padding(7)
            .glassSurface(in: Circle())
            .accessibilityLabel("media.spoilerProtection.artworkHidden")
    }
}
