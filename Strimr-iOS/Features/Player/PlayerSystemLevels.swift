import AVFoundation
import MediaPlayer
import SwiftUI

/// Screen brightness and system volume driven by the player's vertical swipes.
@MainActor
@Observable
final class PlayerSystemLevels {
    /// Called when the system volume changes, from a swipe or the hardware buttons.
    @ObservationIgnored var onVolumeChange: ((Double) -> Void)?
    @ObservationIgnored fileprivate weak var hostView: UIView?
    @ObservationIgnored private var originalBrightness: CGFloat?
    @ObservationIgnored private var appliedBrightness: CGFloat?
    @ObservationIgnored private var suspendedBrightness: CGFloat?
    @ObservationIgnored private var volumeObservation: NSKeyValueObservation?

    private var screen: UIScreen? {
        hostView?.window?.windowScene?.screen
    }

    private var volumeSlider: UISlider? {
        hostView?.subviews.first { $0 is MPVolumeView }?.subviews.lazy.compactMap { $0 as? UISlider }.first
    }

    /// Nil until the host view is in a window, when the screen cannot be adjusted yet.
    var brightness: Double? {
        screen.map { Double($0.brightness) }
    }

    /// Nil when the volume slider cannot be found, since the volume then cannot be set.
    var volume: Double? {
        volumeSlider.map { _ in Double(AVAudioSession.sharedInstance().outputVolume) }
    }

    func setBrightness(_ level: Double) {
        guard let screen else { return }
        if originalBrightness == nil {
            originalBrightness = screen.brightness
        }
        screen.brightness = CGFloat(level)
        appliedBrightness = screen.brightness
    }

    /// Gives the screen back the brightness it had before the first swipe, unless the user changed it since, for
    /// example from Control Center.
    func restoreBrightness() {
        if let screen, let originalBrightness, let appliedBrightness,
           abs(screen.brightness - appliedBrightness) < 0.01
        {
            screen.brightness = originalBrightness
        }
        originalBrightness = nil
        appliedBrightness = nil
    }

    /// Leaves the rest of the system at its own brightness while the app is away, and remembers the swiped level
    /// for `resumeBrightness()`.
    func suspendBrightness() {
        guard let appliedBrightness else { return }
        suspendedBrightness = appliedBrightness
        restoreBrightness()
    }

    func resumeBrightness() {
        guard let suspendedBrightness else { return }
        self.suspendedBrightness = nil
        setBrightness(Double(suspendedBrightness))
    }

    func setVolume(_ level: Double) {
        volumeSlider?.value = Float(level)
    }

    fileprivate func startObservingVolume() {
        guard volumeObservation == nil else { return }
        volumeObservation = AVAudioSession.sharedInstance()
            .observe(\.outputVolume, options: [.new]) { [weak self] _, change in
                guard let volume = change.newValue else { return }
                Task { @MainActor in
                    self?.onVolumeChange?(Double(volume))
                }
            }
    }

    func detach() {
        volumeObservation?.invalidate()
        volumeObservation = nil
        restoreBrightness()
        suspendedBrightness = nil
        hostView = nil
    }
}

/// Hosts the hidden `MPVolumeView` whose slider is the only public way to set the system volume. While it is on
/// screen, the system hides its own volume HUD, so the player shows its level indicator instead.
struct PlayerSystemLevelsHost: UIViewRepresentable {
    let levels: PlayerSystemLevels

    func makeUIView(context _: Context) -> UIView {
        let view = UIView(frame: CGRect(x: 0, y: 0, width: 1, height: 1))
        view.isUserInteractionEnabled = false
        view.alpha = 0.01
        view.accessibilityElementsHidden = true
        view.addSubview(MPVolumeView(frame: view.bounds))
        levels.hostView = view
        levels.startObservingVolume()
        return view
    }

    func updateUIView(_: UIView, context _: Context) {}

    func sizeThatFits(_: ProposedViewSize, uiView _: UIView, context _: Context) -> CGSize? {
        CGSize(width: 1, height: 1)
    }
}
