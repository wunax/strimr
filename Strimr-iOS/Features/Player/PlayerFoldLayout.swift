import SwiftUI

/// Places the video in the upright half and the controls in the half lying flat when a foldable is propped up
/// like a laptop, and the video full screen otherwise. The video keeps its identity across both layouts so the
/// player surface and Picture in Picture survive a fold.
struct PlayerFoldLayout<Video: View, VideoOverlay: View, Controls: View>: View {
    @Binding var mode: PlayerLayoutMode
    @Binding var hinge: PlayerHingeState
    var isPictureInPictureActive: Bool
    @ViewBuilder var video: Video
    @ViewBuilder var videoOverlay: VideoOverlay
    @ViewBuilder var controls: Controls

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var geometry = FoldGeometry()

    var body: some View {
        if #available(iOS 27.1, *) {
            foldAwareContent
                .onHingeChange { _, context in
                    let state = PlayerHingeState(context.hinge)
                    if state != hinge {
                        hinge = state
                    }
                }
        } else {
            video
        }
    }

    @available(iOS 27.1, *)
    private var foldAwareContent: some View {
        let videoFrame: CGRect? = if case let .tabletop(frame, _) = mode {
            frame
        } else {
            nil
        }

        return ZStack(alignment: .topLeading) {
            Color.black

            ZStack {
                video
                if mode.isTabletop {
                    videoOverlay
                }
            }
            .frame(width: videoFrame?.width, height: videoFrame?.height)
            .offset(x: videoFrame?.minX ?? 0, y: videoFrame?.minY ?? 0)

            if case let .tabletop(_, controlsFrame) = mode {
                controls
                    .frame(width: controlsFrame.width, height: controlsFrame.height)
                    .offset(x: controlsFrame.minX, y: controlsFrame.minY)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        // The fold region keeps moving while the hinge settles, so only the switch between layouts is animated.
        .animation(Motion.animation(Motion.panel, reduceMotion: reduceMotion), value: mode.isTabletop)
        .onGeometryChange(for: FoldGeometry.self) { proxy in
            FoldGeometry(size: proxy.size, divisions: proxy.reservedRegions(kind: .division).map(\.frame))
        } action: { geometry = $0 }
        .ignoresSafeArea()
        .onChange(
            of: FoldInputs(hinge: hinge, geometry: geometry, isPictureInPictureActive: isPictureInPictureActive),
            initial: true,
        ) { _, inputs in
            let resolved = PlayerLayoutMode.resolve(
                hinge: inputs.hinge,
                divisions: inputs.geometry.divisions,
                containerSize: inputs.geometry.size,
                isPictureInPictureActive: inputs.isPictureInPictureActive,
            )
            if resolved != mode {
                mode = resolved
            }
        }
    }
}

private nonisolated struct FoldGeometry: Equatable, Sendable {
    var size: CGSize = .zero
    var divisions: [CGRect] = []
}

private struct FoldInputs: Equatable {
    var hinge: PlayerHingeState
    var geometry: FoldGeometry
    var isPictureInPictureActive: Bool
}

@available(iOS 27.1, *)
private extension PlayerHingeState {
    init(_ hinge: DeviceHinge?) {
        switch hinge?.status {
        case .closed?: self = .closed
        case .partiallyOpen?: self = .partiallyOpen
        case .fullyOpen?: self = .fullyOpen
        default: self = .unavailable
        }
    }
}
