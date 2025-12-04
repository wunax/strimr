import SwiftUI
import UIKit

struct PlayerView: View {
    @State private var coordinator = MPVPlayerView.Coordinator()
    @State private var isBuffering = false
    @State private var duration: Double?
    @State private var position = 0.0
    @State private var controlsVisible = true
    @State private var hideControlsWorkItem: DispatchWorkItem?
    @State private var isScrubbing = false
    @State private var previousOrientationLock = AppDelegate.orientationLock

    private let demoUrl = URL(string: "https://commondatastorage.googleapis.com/gtv-videos-bucket/sample/BigBuckBunny.mp4")!
    private let controlsHideDelay: TimeInterval = 3.0

    var body: some View {
        ZStack {
            Color.black
                .ignoresSafeArea()

            MPVPlayerView(coordinator: coordinator)
                .onPropertyChange { player, propertyName, data in
                    switch propertyName {
                    case MPVProperty.pausedForCache:
                        isBuffering = (data as? Bool) ?? false
                    case MPVProperty.timePos:
                        guard !isScrubbing else { return }
                        position = data as? Double ?? 0.0
                    case MPVProperty.duration:
                        duration = data as? Double
                    case MPVProperty.videoParamsSigPeak:
                        let supportsHdr = (data as? Double ?? 1.0) > 1.0
                        player.hdrEnabled = supportsHdr
                    default:
                        break
                    }
                }
                .onAppear {
                    coordinator.play(demoUrl)
                    showControls(temporarily: true)
                }
                .ignoresSafeArea()
                .contentShape(Rectangle())
                .onTapGesture {
                    controlsVisible ? hideControls() : showControls(temporarily: true)
                }

            if isBuffering {
                ProgressView()
                    .progressViewStyle(.circular)
                    .tint(.white)
            }

            if controlsVisible {
                VStack {
                    Spacer()
                    PlayerControlsView(position: $position, duration: duration) { editing in
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
    }

    private func handleScrubbing(editing: Bool) {
        isScrubbing = editing

        if editing {
            hideControlsWorkItem?.cancel()
            withAnimation(.easeInOut) {
                controlsVisible = true
            }
        } else {
            coordinator.player?.seek(to: position)
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
    PlayerView()
}
