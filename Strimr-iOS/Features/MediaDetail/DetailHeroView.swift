import SwiftUI

/// Backdrop at the top of the detail page.
struct DetailHeroView: View {
    @Environment(SettingsManager.self) private var settingsManager
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Bindable var viewModel: MediaDetailViewModel
    let heroHeight: CGFloat
    let onSelectParentSeries: () -> Void

    var body: some View {
        heroBackground
    }

    private var heroBackground: some View {
        ZStack(alignment: .top) {
            GeometryReader { proxy in
                if let heroURL = viewModel.heroImageURL(
                    spoilerProtection: settingsManager.interface.spoilerProtection,
                ) {
                    AsyncImage(url: heroURL) { phase in
                        switch phase {
                        case let .success(image):
                            image
                                .resizable()
                                .scaledToFill()
                                .frame(width: proxy.size.width, height: heroHeight, alignment: .center)
                                .clipped()
                                .overlay(Color.black.opacity(0.2))
                                .mask(heroMask)
                        case .empty:
                            Color.gray.opacity(0.15)
                                .mask(heroMask)
                        case .failure:
                            Color.gray.opacity(0.15)
                                .mask(heroMask)
                        @unknown default:
                            Color.gray.opacity(0.15)
                                .mask(heroMask)
                        }
                    }
                } else if let artworkPath = viewModel.heroArtworkPath(
                    spoilerProtection: settingsManager.interface.spoilerProtection,
                ) {
                    ArtworkPathView(path: artworkPath, width: 1400, height: 800)
                        .frame(width: proxy.size.width, height: heroHeight, alignment: .center)
                        .clipped()
                        .overlay(Color.black.opacity(0.2))
                        .mask(heroMask)
                } else {
                    Color.gray.opacity(0.12)
                        .frame(width: proxy.size.width, height: heroHeight)
                        .mask(heroMask)
                }
            }
            .frame(height: heroHeight)
            // Pulling down zooms the backdrop to fill the gap; scrolling up moves it at half speed. Computed in
            // `visualEffect` so scrolling publishes no state.
            .visualEffect { [reduceMotion, heroHeight] content, proxy in
                let minY = reduceMotion ? 0 : proxy.frame(in: .scrollView(axis: .vertical)).minY
                return content
                    .scaleEffect(minY > 0 ? 1 + minY / heroHeight : 1, anchor: .bottom)
                    .offset(y: minY < 0 ? -minY * 0.5 : 0)
            }
            .overlay(alignment: .topLeading) {
                if viewModel.media.mediaItem.isSpoilerProtected(
                    at: settingsManager.interface.spoilerProtection,
                ) {
                    SpoilerProtectionIndicator()
                        .padding(16)
                }
            }
        }
        .frame(maxWidth: .infinity, minHeight: heroHeight, maxHeight: heroHeight)
        .ignoresSafeArea(edges: .horizontal)
        .contentShape(Rectangle())
        .onTapGesture {
            guard viewModel.parentSeries != nil else { return }
            onSelectParentSeries()
        }
        .accessibilityAddTraits(viewModel.parentSeries == nil ? [] : .isButton)
        .accessibilityHint(
            viewModel.parentSeries == nil
                ? Text(verbatim: "")
                : Text("media.detail.openSeries"),
        )
    }

    private var heroMask: some View {
        LinearGradient(
            colors: [
                .white,
                .white,
                .clear,
            ],
            startPoint: .top,
            endPoint: .bottom,
        )
    }
}

/// Logo or title centered over the bottom of the backdrop, with the facts and ratings under it.
struct DetailHeroTitle: View {
    @Bindable var viewModel: MediaDetailViewModel

    var body: some View {
        VStack(spacing: 10) {
            TitleLogoView(
                media: viewModel.media.mediaItem,
                title: logoTitle,
                logoPath: viewModel.media.mediaItem.preferredLogoPath ?? seriesLogoPath,
                maxSize: LayoutMetrics.heroLogoMaxSize,
                alignment: .bottom,
            )
            .frame(maxWidth: .infinity, minHeight: LayoutMetrics.heroLogoMaxSize.height / 2, alignment: .bottom)

            if let subtitle {
                Text(subtitle)
                    .font(.headline)
                    .foregroundStyle(.textPrimary)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
            }

            MediaFactsLine(facts: facts, badges: badges)
                .frame(maxWidth: .infinity)

            if !viewModel.media.ratings.isEmpty {
                HStack(spacing: 12) {
                    ForEach(Array(viewModel.media.ratings.enumerated()), id: \.offset) { _, rating in
                        MediaRatingLabel(rating: rating, iconHeight: 16)
                            .font(.footnote)
                    }
                }
                .foregroundStyle(.textSecondary)
            }
        }
        .frame(maxWidth: .infinity)
    }

    private var isChildItem: Bool {
        [.season, .episode].contains(viewModel.media.type)
    }

    /// Episodes and seasons show their series' logo or name, with their own title under it.
    private var logoTitle: String {
        isChildItem ? viewModel.detailSecondaryLabel ?? viewModel.detailPrimaryLabel : viewModel.detailPrimaryLabel
    }

    private var subtitle: String? {
        isChildItem ? viewModel.detailPrimaryLabel : nil
    }

    private var seriesLogoPath: String? {
        viewModel.parentSeries?.mediaItem.logoPath
    }

    private var facts: MediaFacts {
        MediaFactsFormatter.facts(
            for: viewModel.media.mediaItem,
            seasonCount: viewModel.seasons.isEmpty ? nil : viewModel.seasons.count,
        )
    }

    private var badges: [String] {
        guard viewModel.activeVersionID(for: nil) != nil else { return [] }
        return viewModel.selectedVersion?.badgeLabels ?? []
    }
}
