import SwiftUI
import UIKit

struct PlayerView: View {
    @State var viewModel: PlayerViewModel
    @State private var coordinator = MPVPlayerView.Coordinator()
    @State private var controlsVisible = true
    @State private var hideControlsWorkItem: DispatchWorkItem?
    @State private var isScrubbing = false
    @State private var previousOrientationLock = AppDelegate.orientationLock

    private let controlsHideDelay: TimeInterval = 3.0

    var body: some View {
        @Bindable var bindableViewModel = viewModel

        ZStack {
            Color.black
                .ignoresSafeArea()

            MPVPlayerView(coordinator: coordinator)
                .onPropertyChange { player, propertyName, data in
                    bindableViewModel.handlePropertyChange(
                        name: propertyName,
                        data: data,
                        isScrubbing: isScrubbing
                    )

                    if propertyName == MPVProperty.videoParamsSigPeak {
                        let supportsHdr = (data as? Double ?? 1.0) > 1.0
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
                ProgressView()
                    .progressViewStyle(.circular)
                    .tint(.white)
            }

            if controlsVisible {
                VStack {
                    Spacer()
                    PlayerControlsView(
                        position: $bindableViewModel.position,
                        duration: bindableViewModel.duration,
                        bufferedAhead: bindableViewModel.bufferedAhead
                    ) { editing in
                        handleScrubbing(editing: editing)
                    }
                }
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

    private func handleScrubbing(editing: Bool) {
        isScrubbing = editing

        if editing {
            hideControlsWorkItem?.cancel()
            withAnimation(.easeInOut) {
                controlsVisible = true
            }
        } else {
            coordinator.player?.seek(to: viewModel.position)
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
