import Foundation
import Observation
import SwiftUI

@MainActor
@Observable
final class MediaDetailViewModel {
    private let plexApiManager: PlexAPIManager

    var media: MediaItem
    var heroImageURL: URL?
    var isLoading = false
    var errorMessage: String?
    var backdropGradient: [Color] = []

    init(media: MediaItem, plexApiManager: PlexAPIManager) {
        self.media = media
        self.plexApiManager = plexApiManager
        resolveArtwork()
    }

    func loadDetails() async {
        guard let api = plexApiManager.server else {
            errorMessage = "Select a server to load details."
            return
        }

        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        do {
            let response = try await api.getMetadata(ratingKey: media.metadataRatingKey)
            if let item = response.mediaContainer.metadata?.first {
                media = MediaItem(plexItem: item)
                resolveArtwork()
                resolveGradient()
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func resolveArtwork() {
        guard let api = plexApiManager.server else {
            heroImageURL = nil
            return
        }

        heroImageURL = media.artPath.flatMap {
            api.transcodeImageURL(path: $0, width: 1400, height: 800)
        } ?? media.thumbPath.flatMap {
            api.transcodeImageURL(path: $0, width: 1400, height: 800)
        }
        resolveGradient()
    }

    private func resolveGradient() {
        guard let blur = media.ultraBlurColors else {
            backdropGradient = []
            return
        }

        backdropGradient = [
            Color(hex: blur.topLeft),
            Color(hex: blur.topRight),
            Color(hex: blur.bottomRight),
            Color(hex: blur.bottomLeft),
        ]
    }

    var runtimeText: String? {
        guard let duration = media.duration else { return nil }
        let minutes = Int(duration / 60)
        let hours = minutes / 60
        let remainingMinutes = minutes % 60
        if hours > 0 {
            return "\(hours)h \(remainingMinutes)m"
        }
        return "\(remainingMinutes)m"
    }

    var yearText: String? {
        media.year.map(String.init)
    }

    var ratingText: String? {
        media.rating.map { String(format: "%.1f", $0) }
    }
}

private extension Color {
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let a, r, g, b: UInt64
        switch hex.count {
        case 3: // RGB (12-bit)
            (a, r, g, b) = (255, (int >> 8) * 17, (int >> 4 & 0xF) * 17, (int & 0xF) * 17)
        case 6: // RGB (24-bit)
            (a, r, g, b) = (255, int >> 16, int >> 8 & 0xFF, int & 0xFF)
        case 8: // ARGB (32-bit)
            (a, r, g, b) = (int >> 24, int >> 16 & 0xFF, int >> 8 & 0xFF, int & 0xFF)
        default:
            (a, r, g, b) = (255, 0, 0, 0)
        }

        self.init(
            .sRGB,
            red: Double(r) / 255,
            green: Double(g) / 255,
            blue: Double(b) / 255,
            opacity: Double(a) / 255
        )
    }
}
