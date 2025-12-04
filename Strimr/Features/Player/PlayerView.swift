import SwiftUI
import UIKit

struct PlayerView: View {
    @Environment(\.dismiss) private var dismiss

    @State private var coordinator = MPVPlayerView.Coordinator()
    @State private var isBuffering = false
    @State private var isPlaying = true
    @State private var hdrEnabled = false
    @State private var previousOrientationLock = AppDelegate.orientationLock

    private let demoUrl = URL(string: "https://commondatastorage.googleapis.com/gtv-videos-bucket/sample/BigBuckBunny.mp4")!

    var body: some View {
        ZStack {
            Color.black
                .ignoresSafeArea()

            MPVPlayerView(coordinator: coordinator)
                .onPropertyChange { player, propertyName, data in
                    switch propertyName {
                    case MPVProperty.pausedForCache:
                        isBuffering = (data as? Bool) ?? false
                    case MPVProperty.videoParamsSigPeak:
                        let supportsHdr = (data as? Double ?? 1.0) > 1.0
                        hdrEnabled = supportsHdr
                        player.hdrEnabled = supportsHdr
                    default:
                        break
                    }
                }
                .onAppear {
                    coordinator.play(demoUrl)
                }
                .ignoresSafeArea()

            overlayControls
        }
        .statusBarHidden()
    }

    private var overlayControls: some View {
        VStack {
            HStack {
                Button(action: {
                    dismiss()
                }) {
                    Image(systemName: "xmark")
                        .font(.headline)
                        .padding(10)
                        .background(.ultraThinMaterial)
                        .clipShape(Circle())
                }

                Spacer()

                if hdrEnabled {
                    Label("HDR", systemImage: "sparkles")
                        .padding(10)
                        .background(.ultraThinMaterial)
                        .clipShape(Capsule())
                }
            }
            .padding()

            Spacer()

            VStack(spacing: 12) {
                if isBuffering {
                    Label("Buffering...", systemImage: "wifi.exclamationmark")
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)
                        .background(.ultraThinMaterial)
                        .clipShape(Capsule())
                }

                HStack(spacing: 16) {
                    Button {
                        coordinator.player?.togglePause()
                        isPlaying.toggle()
                    } label: {
                        Image(systemName: isPlaying ? "pause.fill" : "play.fill")
                            .font(.title2)
                            .frame(width: 56, height: 56)
                            .background(.ultraThinMaterial)
                            .clipShape(Circle())
                    }

                    Button {
                        coordinator.play(demoUrl)
                        isPlaying = true
                    } label: {
                        Label("Replay", systemImage: "gobackward")
                            .font(.headline)
                            .padding(.horizontal, 18)
                            .padding(.vertical, 12)
                            .background(.ultraThinMaterial)
                            .clipShape(Capsule())
                    }
                }
            }
            .padding(.bottom, 24)
        }
        .onAppear {
            previousOrientationLock = AppDelegate.orientationLock
            lockOrientation(.landscape, rotateTo: .landscapeRight)
        }
        .onDisappear {
            lockOrientation(previousOrientationLock, rotateTo: .portrait)
        }
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
