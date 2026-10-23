import SwiftUI

/// Backdrop at the top of the detail page.
struct DetailHeroView: View {
    @Environment(SettingsManager.self) private var settingsManager
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
                            Color.surfaceSubtle
                                .mask(heroMask)
                        case .failure:
                            Color.surfaceSubtle
                                .mask(heroMask)
                        @unknown default:
                            Color.surfaceSubtle
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
                    Color.surfaceSubtle
                        .frame(width: proxy.size.width, height: heroHeight)
                        .mask(heroMask)
                }
            }
            .frame(height: heroHeight)
            .heroParallax(height: heroHeight)
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

extension View {
    /// Pulling down zooms the backdrop to fill the gap; scrolling up moves it at half speed. Computed in
    /// `visualEffect` so scrolling publishes no state.
    func heroParallax(height: CGFloat) -> some View {
        modifier(HeroParallax(height: height))
    }
}

private struct HeroParallax: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let height: CGFloat

    func body(content: Content) -> some View {
        content.visualEffect { [reduceMotion, height] content, proxy in
            let minY = reduceMotion ? 0 : proxy.frame(in: .scrollView(axis: .vertical)).minY
            return content
                .scaleEffect(minY > 0 ? 1 + minY / height : 1, anchor: .bottom)
                .offset(y: minY < 0 ? -minY * 0.5 : 0)
        }
    }
}
