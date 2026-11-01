import Foundation

@MainActor
final class JellyfinManagementService: MediaManagementService {
    private let context: JellyfinAPIContext

    init(context: JellyfinAPIContext) {
        self.context = context
    }

    var supportsAnalyze: Bool {
        false
    }

    /// Replaces the metadata but keeps the images, which is what a Plex refresh does with chosen artwork.
    func refreshMetadata(itemID: String) async throws {
        try await context.send(
            path: ["Items", itemID, "Refresh"],
            method: "POST",
            query: [
                URLQueryItem(name: "MetadataRefreshMode", value: "FullRefresh"),
                URLQueryItem(name: "ImageRefreshMode", value: "FullRefresh"),
                URLQueryItem(name: "ReplaceAllMetadata", value: "true"),
                URLQueryItem(name: "ReplaceAllImages", value: "false"),
            ],
        )
    }

    func analyze(itemID _: String) async throws {}
}
