#if os(iOS) || os(macOS)
    import AetherEngine
    import AVKit
    import Combine
    import CoreMedia
    import Foundation

    @MainActor
    final class PictureInPictureCoordinator: NSObject {
        var onAvailabilityChanged: ((Bool, Bool) -> Void)?
        var onActivityChanged: ((Bool, Bool) -> Void)?
        var onRestoreUserInterface: (() -> Void)?
        var onStartFailed: (() -> Void)?

        private enum PlaybackSource {
            case native(AVPlayerLayer)
            case software(SoftwarePiPSource)

            func matches(_ other: PlaybackSource) -> Bool {
                switch (self, other) {
                case let (.native(lhs), .native(rhs)):
                    lhs === rhs
                case let (.software(lhs), .software(rhs)):
                    lhs === rhs
                default:
                    false
                }
            }
        }

        private let engine: AetherEngine
        private var controller: AVPictureInPictureController?
        private var playbackSource: PlaybackSource?
        private var possibleObservation: NSKeyValueObservation?
        private var cancellables: Set<AnyCancellable> = []
        private var needsSourceRebuildAfterStop = false
        private var isTransitioning = false

        init(engine: AetherEngine) {
            self.engine = engine
            super.init()
            observePlaybackSources()
            rebuildSource()
        }

        func start() {
            guard let controller,
                  controller.isPictureInPicturePossible,
                  !controller.isPictureInPictureActive,
                  !isTransitioning
            else { return }
            controller.startPictureInPicture()
        }

        func stop() {
            if controller?.isPictureInPictureActive == true || isTransitioning {
                controller?.stopPictureInPicture()
            }
            resetEnginePictureInPictureState()
            possibleObservation?.invalidate()
            possibleObservation = nil
            controller?.delegate = nil
            controller = nil
            playbackSource = nil
            needsSourceRebuildAfterStop = false
            setTransitioning(false)
            publishAvailability()
        }

        private func observePlaybackSources() {
            Publishers.CombineLatest3(
                engine.$currentAVPlayer,
                engine.$softwarePiPSource,
                engine.$videoRoute,
            )
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _, _, _ in
                self?.rebuildSource()
            }
            .store(in: &cancellables)
        }

        private func rebuildSource() {
            let nextSource: PlaybackSource? = if let softwareSource = engine.softwarePiPSource {
                .software(softwareSource)
            } else if let playerLayer = engine.nativePlayerLayer {
                .native(playerLayer)
            } else {
                nil
            }

            if let playbackSource, let nextSource, playbackSource.matches(nextSource) {
                publishAvailability()
                return
            }

            if controller?.isPictureInPictureActive == true || isTransitioning {
                needsSourceRebuildAfterStop = true
                controller?.stopPictureInPicture()
                return
            }

            install(nextSource)
        }

        private func install(_ source: PlaybackSource?) {
            possibleObservation?.invalidate()
            possibleObservation = nil
            controller?.delegate = nil
            controller = nil
            playbackSource = source

            guard AVPictureInPictureController.isPictureInPictureSupported(), let source else {
                publishAvailability()
                return
            }

            let contentSource = switch source {
            case let .native(playerLayer):
                AVPictureInPictureController.ContentSource(playerLayer: playerLayer)
            case let .software(softwareSource):
                AVPictureInPictureController.ContentSource(
                    sampleBufferDisplayLayer: softwareSource.layer,
                    playbackDelegate: self,
                )
            }

            let controller = AVPictureInPictureController(contentSource: contentSource)
            controller.delegate = self
            #if os(iOS)
                controller.canStartPictureInPictureAutomaticallyFromInline = true
            #endif
            self.controller = controller
            possibleObservation = controller.observe(
                \.isPictureInPicturePossible,
                options: [.initial, .new],
            ) { [weak self] _, _ in
                Task { @MainActor in
                    self?.publishAvailability()
                }
            }
        }

        private func publishAvailability() {
            onAvailabilityChanged?(
                playbackSource != nil && AVPictureInPictureController.isPictureInPictureSupported(),
                controller?.isPictureInPicturePossible == true && !isTransitioning,
            )
        }

        private func setTransitioning(_ transitioning: Bool) {
            isTransitioning = transitioning
            onActivityChanged?(controller?.isPictureInPictureActive == true, transitioning)
            publishAvailability()
        }

        private func activateEnginePictureInPictureState() {
            engine.pictureInPictureActive = true
            if case .native = playbackSource {
                engine.setNativeSubtitleRendering(true)
            }
        }

        private func resetEnginePictureInPictureState() {
            if case .native = playbackSource {
                engine.setNativeSubtitleRendering(false)
            }
            engine.pictureInPictureActive = false
        }
    }

    extension PictureInPictureCoordinator: AVPictureInPictureControllerDelegate {
        func pictureInPictureControllerWillStartPictureInPicture(
            _: AVPictureInPictureController,
        ) {
            setTransitioning(true)
            activateEnginePictureInPictureState()
        }

        func pictureInPictureControllerDidStartPictureInPicture(
            _: AVPictureInPictureController,
        ) {
            setTransitioning(false)
            onActivityChanged?(true, false)
        }

        func pictureInPictureController(
            _: AVPictureInPictureController,
            failedToStartPictureInPictureWithError error: any Error,
        ) {
            resetEnginePictureInPictureState()
            setTransitioning(false)
            ErrorReporter.capture(error)
            onStartFailed?()
        }

        func pictureInPictureControllerWillStopPictureInPicture(
            _: AVPictureInPictureController,
        ) {
            setTransitioning(true)
        }

        func pictureInPictureControllerDidStopPictureInPicture(
            _: AVPictureInPictureController,
        ) {
            resetEnginePictureInPictureState()
            setTransitioning(false)
            onActivityChanged?(false, false)
            if needsSourceRebuildAfterStop {
                needsSourceRebuildAfterStop = false
                rebuildSource()
            }
        }

        func pictureInPictureController(
            _: AVPictureInPictureController,
            restoreUserInterfaceForPictureInPictureStopWithCompletionHandler completionHandler: @escaping (Bool)
                -> Void,
        ) {
            onRestoreUserInterface?()
            completionHandler(true)
        }
    }

    extension PictureInPictureCoordinator: AVPictureInPictureSampleBufferPlaybackDelegate {
        func pictureInPictureController(
            _ pictureInPictureController: AVPictureInPictureController,
            setPlaying playing: Bool,
        ) {
            guard case let .software(source) = playbackSource else { return }
            source.setPlaying(playing)
            pictureInPictureController.invalidatePlaybackState()
        }

        func pictureInPictureControllerTimeRangeForPlayback(
            _: AVPictureInPictureController,
        ) -> CMTimeRange {
            guard case let .software(source) = playbackSource else { return .invalid }
            return source.timeRange()
        }

        func pictureInPictureControllerIsPlaybackPaused(
            _: AVPictureInPictureController,
        ) -> Bool {
            guard case let .software(source) = playbackSource else { return true }
            return source.isPaused
        }

        func pictureInPictureController(
            _: AVPictureInPictureController,
            didTransitionToRenderSize _: CMVideoDimensions,
        ) {}

        func pictureInPictureController(
            _ pictureInPictureController: AVPictureInPictureController,
            skipByInterval skipInterval: CMTime,
            completion completionHandler: @escaping () -> Void,
        ) {
            defer { completionHandler() }
            guard case let .software(source) = playbackSource else { return }
            let seconds = skipInterval.seconds
            guard seconds.isFinite else { return }
            source.skip(by: seconds)
            pictureInPictureController.invalidatePlaybackState()
        }
    }
#endif
