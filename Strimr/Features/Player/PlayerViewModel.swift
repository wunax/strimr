import Foundation
import Observation

@MainActor
@Observable
final class PlayerViewModel {
    var media: MediaItem?
    var isLoading = false
    var errorMessage: String?
    var isBuffering = false
    var duration: Double?
    var position = 0.0
    var bufferedAhead = 0.0
    var playbackURL: URL?
    var isPaused = false
    var preferredAudioStreamFFIndex: Int?
    var preferredSubtitleStreamFFIndex: Int?

    @ObservationIgnored private let ratingKey: String
    @ObservationIgnored private let context: PlexAPIContext

    init(ratingKey: String, context: PlexAPIContext) {
        self.ratingKey = ratingKey
        self.context = context
    }

    func load() async {
        guard let metadataRepository = try? MetadataRepository(context: context) else {
            errorMessage = "Select a server to play media."
            return
        }

        isLoading = true
        errorMessage = nil
        preferredAudioStreamFFIndex = nil
        preferredSubtitleStreamFFIndex = nil
        defer { isLoading = false }

        do {
            let params = MetadataRepository.PlexMetadataParams(
                checkFiles: true,
                includeChapters: true,
                includeMarkers: true
            )
            let response = try await metadataRepository.getMetadata(
                ratingKey: ratingKey,
                params: params
            )
            let metadata = response.mediaContainer.metadata?.first
            media = metadata.map(MediaItem.init)
            resolvePreferredStreams(from: metadata)
            playbackURL = resolvePlaybackURL(from: metadata)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func handlePropertyChange(
        name: String,
        data: Any?,
        isScrubbing: Bool
    ) {
        switch name {
        case MPVProperty.pause:
            isPaused = (data as? Bool) ?? false
        case MPVProperty.pausedForCache:
            isBuffering = (data as? Bool) ?? false
        case MPVProperty.timePos:
            guard !isScrubbing else { return }
            position = data as? Double ?? 0.0
        case MPVProperty.duration:
            duration = data as? Double
        case MPVProperty.demuxerCacheDuration:
            bufferedAhead = data as? Double ?? 0.0
        default:
            break
        }
    }

    private func resolvePlaybackURL(from metadata: PlexItem?) -> URL? {
        guard
            let partPath = metadata?.media?.first?.parts.first?.key,
            let mediaRepository = try? MediaRepository(context: context)
        else {
            return nil
        }

        return mediaRepository.mediaURL(path: partPath)
    }

    private func resolvePreferredStreams(from metadata: PlexItem?) {
        let streams = metadata?.media?.first?.parts.first?.stream ?? []

        preferredAudioStreamFFIndex = streams.first {
            $0.streamType == .audio && $0.selected == true
        }?.index

        preferredSubtitleStreamFFIndex = streams.first {
            $0.streamType == .subtitle && $0.selected == true
        }?.index
    }
}
