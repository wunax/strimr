import SwiftUI

struct HeroBackdrop {
    var resource: ArtworkResource?
    var colors: [Color] = []
}

struct HeroBackdropView<Key: Equatable>: View {
    let key: Key
    let load: () async -> HeroBackdrop

    @State private var layers: [Layer] = []
    @State private var nextLayerID = 0

    private let settleDelay: Duration = .milliseconds(100)
    private let fadeDuration: TimeInterval = 0.5

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                MediaBackdropGradient(colors: [])
                    .ignoresSafeArea()

                ForEach(layers) { layer in
                    layerView(layer.backdrop, proxy: proxy)
                        .transition(.opacity)
                }
            }
        }
        .task(id: key) {
            await update()
        }
    }

    private func layerView(_ backdrop: HeroBackdrop, proxy: GeometryProxy) -> some View {
        ZStack {
            MediaBackdropGradient(colors: backdrop.colors)
                .ignoresSafeArea()

            ArtworkResourceView(resource: backdrop.resource)
                .frame(
                    width: (proxy.size.width + proxy.safeAreaInsets.leading + proxy.safeAreaInsets.trailing) * 0.66,
                    height: (proxy.size.height + proxy.safeAreaInsets.top + proxy.safeAreaInsets.bottom) * 0.66,
                )
                .clipped()
                .overlay(Color.black.opacity(0.2))
                .mask(HeroMaskView())
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                .ignoresSafeArea()
        }
    }

    /// The new backdrop is only committed once its artwork and colors are ready, then fades in over the
    /// previous one, which stays opaque underneath so the crossfade never dips to the plain background.
    /// The settle delay skips loading every item crossed during a fast focus scroll.
    private func update() async {
        if !layers.isEmpty {
            try? await Task.sleep(for: settleDelay)
            guard !Task.isCancelled else { return }
        }

        let backdrop = await load()
        guard !Task.isCancelled else { return }

        let layer = Layer(id: nextLayerID, backdrop: backdrop)
        nextLayerID += 1
        withAnimation(.easeInOut(duration: fadeDuration)) {
            layers.append(layer)
        }

        try? await Task.sleep(for: .seconds(fadeDuration))
        guard !Task.isCancelled else { return }
        layers.removeAll { $0.id != layer.id }
    }

    private struct Layer: Identifiable {
        let id: Int
        let backdrop: HeroBackdrop
    }
}
