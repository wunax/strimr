import Foundation
import Observation
import SwiftUI

@MainActor
@Observable
final class SeriesDownloadViewModel {
    let series: MediaItem
    private let context: PlexAPIContext
    
    var seasons: [MediaItem] = []
    var episodesBySeason: [String: [MediaItem]] = [:]
    
    var selectedEpisodeIds: Set<String> = []
    var expandedSeasonIds: Set<String> = []
    
    var isLoading = false
    var errorMessage: String?
    
    init(series: MediaItem, context: PlexAPIContext) {
        self.series = series
        self.context = context
    }
    
    func loadData() async {
        guard let repository = try? MetadataRepository(context: context) else {
            errorMessage = String(localized: "errors.selectServer.loadDetails")
            return
        }
        
        isLoading = true
        errorMessage = nil
        
        do {
            // Load Seasons
            let seasonsResponse = try await repository.getMetadataChildren(ratingKey: series.metadataRatingKey)
            seasons = (seasonsResponse.mediaContainer.metadata ?? []).map(MediaItem.init)
            
            // Load all episodes for all seasons in parallel
            await withTaskGroup(of: (String, [MediaItem]?).self) { group in
                for season in seasons {
                    group.addTask {
                        do {
                            let episodesResponse = try await repository.getMetadataChildren(ratingKey: season.id)
                            let episodes = (episodesResponse.mediaContainer.metadata ?? []).map(MediaItem.init)
                            return (season.id, episodes)
                        } catch {
                            return (season.id, nil)
                        }
                    }
                }
                
                for await (seasonId, episodes) in group {
                    if let episodes = episodes {
                        episodesBySeason[seasonId] = episodes
                    }
                }
            }
        } catch {
            errorMessage = error.localizedDescription
        }
        
        isLoading = false
    }
    
    func isSeasonSelected(_ seasonId: String) -> Bool {
        guard let episodes = episodesBySeason[seasonId], !episodes.isEmpty else { return false }
        return episodes.allSatisfy { selectedEpisodeIds.contains($0.id) }
    }
    
    func isSeasonIndeterminate(_ seasonId: String) -> Bool {
        guard let episodes = episodesBySeason[seasonId], !episodes.isEmpty else { return false }
        let selectedCount = episodes.filter { selectedEpisodeIds.contains($0.id) }.count
        return selectedCount > 0 && selectedCount < episodes.count
    }
    
    func toggleSeason(_ seasonId: String) {
        guard let episodes = episodesBySeason[seasonId] else { return }
        
        if isSeasonSelected(seasonId) {
            // Deselect all
            for episode in episodes {
                selectedEpisodeIds.remove(episode.id)
            }
        } else {
            // Select all
            for episode in episodes {
                selectedEpisodeIds.insert(episode.id)
            }
        }
    }
    
    func toggleEpisode(_ episodeId: String) {
        if selectedEpisodeIds.contains(episodeId) {
            selectedEpisodeIds.remove(episodeId)
        } else {
            selectedEpisodeIds.insert(episodeId)
        }
    }
    
    func toggleExpandSeason(_ seasonId: String) {
        if expandedSeasonIds.contains(seasonId) {
            expandedSeasonIds.remove(seasonId)
        } else {
            expandedSeasonIds.insert(seasonId)
        }
    }
    
    var canDownload: Bool {
        !selectedEpisodeIds.isEmpty
    }
    
    func startDownloads() {
        let allEpisodes = episodesBySeason.values.flatMap { $0 }
        let selectedEpisodes = allEpisodes.filter { selectedEpisodeIds.contains($0.id) }
        
        for episode in selectedEpisodes {
            if let url = downloadURL(for: episode) {
                DownloadManager.shared.startDownload(media: episode, url: url)
            }
        }
    }
    
    func imageURL(for item: MediaItem, width: Int = 300, height: Int = 450) -> URL? {
        guard let imageRepository = try? ImageRepository(context: context) else { return nil }
        let path = item.thumbPath ?? item.parentThumbPath ?? item.grandparentThumbPath
        return path.flatMap { imageRepository.transcodeImageURL(path: $0, width: width, height: height) }
    }
    
    private func downloadURL(for item: MediaItem) -> URL? {
        guard let downloadPath = item.downloadPath else { return nil }
        guard let baseURL = context.baseURLServer, let token = context.authTokenServer else { return nil }
        
        var components = URLComponents(url: baseURL, resolvingAgainstBaseURL: false)
        let normalizedPath = downloadPath.hasPrefix("/") ? downloadPath : "/\(downloadPath)"
        components?.path = normalizedPath
        components?.queryItems = [
            URLQueryItem(name: "X-Plex-Token", value: token),
            URLQueryItem(name: "download", value: "1")
        ]
        return components?.url
    }
}
