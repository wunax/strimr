import SwiftUI
import UIKit

struct PlayerView: View {
    @Environment(\.dismiss) private var dismiss
    @State var viewModel: PlayerViewModel
    @State private var coordinator = MPVPlayerView.Coordinator()
    @State private var controlsVisible = true
    @State private var hideControlsWorkItem: DispatchWorkItem?
    @State private var isScrubbing = false
    @State private var previousOrientationLock = AppDelegate.orientationLock
    @State private var supportsHDR = false

    private let controlsHideDelay: TimeInterval = 3.0
    private let seekInterval: Double = 10

    var body: some View {
        @Bindable var bindableViewModel = viewModel

        ZStack {
            Color.black.ignoresSafeArea()

            MPVPlayerView(coordinator: coordinator)
                .onPropertyChange { player, propertyName, data in
                    bindableViewModel.handlePropertyChange(
                        name: propertyName,
                        data: data,
                        isScrubbing: isScrubbing
                    )

                    if propertyName == MPVProperty.videoParamsSigPeak {
                        let supportsHdr = (data as? Double ?? 1.0) > 1.0
                        supportsHDR = supportsHdr
                        player.hdrEnabled = supportsHdr
                    }
                }
                .onAppear {
                    showControls(temporarily: true)
                }
                .ignoresSafeArea()
                .contentShape(Rectangle())
                .onTapGesture {
                    controlsVisible ? hideControls() : showControls(temporarily: true)
                }

            if bindableViewModel.isBuffering {
                bufferingOverlay
            }

            if controlsVisible {
                PlayerControlsView(
                    media: bindableViewModel.media,
                    isPaused: bindableViewModel.isPaused,
                    isBuffering: bindableViewModel.isBuffering,
                    supportsHDR: supportsHDR,
                    position: positionBinding(for: bindableViewModel),
                    duration: bindableViewModel.duration,
                    bufferedAhead: bindableViewModel.bufferedAhead,
                    onDismiss: dismissPlayer,
                    onSeekBackward: { jump(by: -seekInterval) },
                    onPlayPause: togglePlayPause,
                    onSeekForward: { jump(by: seekInterval) },
                    onScrubbingChanged: handleScrubbing(editing:)
                )
                    .transition(.opacity)
            }
        }
        .statusBarHidden()
        .onAppear {
            previousOrientationLock = AppDelegate.orientationLock
            lockOrientation(.landscape, rotateTo: .landscapeRight)
            showControls(temporarily: true)
        }
        .onDisappear {
            hideControlsWorkItem?.cancel()
            lockOrientation(previousOrientationLock, rotateTo: .portrait)
        }
        .task {
            await bindableViewModel.load()
        }
        .onChange(of: bindableViewModel.playbackURL) { newURL in
            guard let url = newURL else { return }
            coordinator.play(url)
            showControls(temporarily: true)
        }
    }

    private var bufferingOverlay: some View {
        VStack(spacing: 10) {
            ProgressView()
                .progressViewStyle(.circular)
                .tint(.white)

            Text("Buffering")
                .font(.callout.weight(.semibold))
                .foregroundStyle(.white.opacity(0.9))
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 14)
        .background(.black.opacity(0.55), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private func positionBinding(for viewModel: PlayerViewModel) -> Binding<Double> {
        Binding(
            get: { viewModel.position },
            set: { viewModel.position = $0 }
        )
    }

    private func togglePlayPause() {
        coordinator.togglePlayback()
        showControls(temporarily: true)
    }

    private func jump(by seconds: Double) {
        coordinator.seek(by: seconds)
        showControls(temporarily: true)
    }

    private func dismissPlayer() {
        hideControlsWorkItem?.cancel()
        dismiss()
    }

    private func handleScrubbing(editing: Bool) {
        isScrubbing = editing

        if editing {
            hideControlsWorkItem?.cancel()
            withAnimation(.easeInOut) {
                controlsVisible = true
            }
        } else {
            coordinator.seek(to: viewModel.position)
            scheduleControlsHide()
        }
    }

    private func showControls(temporarily: Bool) {
        withAnimation(.easeInOut) {
            controlsVisible = true
        }

        if temporarily && !isScrubbing {
            scheduleControlsHide()
        } else {
            hideControlsWorkItem?.cancel()
        }
    }

    private func hideControls() {
        hideControlsWorkItem?.cancel()
        withAnimation(.easeInOut) {
            controlsVisible = false
        }
    }

    private func scheduleControlsHide() {
        hideControlsWorkItem?.cancel()

        let workItem = DispatchWorkItem {
            withAnimation(.easeInOut) {
                controlsVisible = false
            }
        }

        hideControlsWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + controlsHideDelay, execute: workItem)
    }

    private func lockOrientation(_ orientation: UIInterfaceOrientationMask, rotateTo orientationValue: UIInterfaceOrientation? = nil) {
        AppDelegate.orientationLock = orientation

        if let orientationValue {
            UIDevice.current.setValue(orientationValue.rawValue, forKey: "orientation")

            UIApplication.shared
                .connectedScenes
                .compactMap { $0 as? UIWindowScene }
                .first?
                .keyWindow?
                .rootViewController?
                .setNeedsUpdateOfSupportedInterfaceOrientations()
        }
    }
}

#Preview {
    let context = PlexAPIContext()
    let viewModel = PlayerViewModel(ratingKey: "demo", context: context)
    return PlayerView(viewModel: viewModel)
        .environment(context)
}
