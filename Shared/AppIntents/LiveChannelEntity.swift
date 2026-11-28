import AppIntents
import Foundation

/// A Live TV channel of one of the profile's servers.
struct LiveChannelEntity: AppEntity {
    static let typeDisplayRepresentation = TypeDisplayRepresentation(
        name: LocalizedStringResource("intents.channel.type"),
    )
    static let defaultQuery = LiveChannelEntityQuery()

    /// The channel's `strimr://live` link.
    let id: String
    let name: String
    let number: String?

    init(channel: LiveTVChannel, server: ServerIdentity) {
        id = DeepLink.liveChannelLink(channel, server: server, profile: nil).url.absoluteString
        name = channel.name
        number = channel.number
    }

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(name)", subtitle: number.map { "\($0)" })
    }

    var link: DeepLink? {
        guard let url = URL(string: id) else { return nil }
        return DeepLink(url: url)
    }
}

struct LiveChannelEntityQuery: EntityStringQuery {
    @MainActor
    func entities(for identifiers: [LiveChannelEntity.ID]) async throws -> [LiveChannelEntity] {
        try await allChannels().filter { identifiers.contains($0.id) }
    }

    @MainActor
    func entities(matching string: String) async throws -> [LiveChannelEntity] {
        try await allChannels().filter {
            $0.name.localizedCaseInsensitiveContains(string) || $0.number == string
        }
    }

    /// Favorites first, as the guide lists them.
    @MainActor
    func suggestedEntities() async throws -> [LiveChannelEntity] {
        try await allChannels()
    }

    @MainActor
    private func allChannels() async throws -> [LiveChannelEntity] {
        guard let sessionManager = await AppIntentsEnvironment.readySessionManager() else { return [] }
        let registry = sessionManager.registry
        if registry.liveTVServices.isEmpty {
            await registry.refreshLiveTVAvailability()
        }
        var entities: [LiveChannelEntity] = []
        for services in registry.liveTVServices {
            let channels = await services.liveTVStore.channels.isEmpty
                ? (try? services.liveTV.channels()) ?? []
                : services.liveTVStore.channels
            let ordered = channels.filter(\.isFavorite) + channels.filter { !$0.isFavorite }
            entities += ordered.map { LiveChannelEntity(channel: $0, server: services.identity) }
        }
        return entities
    }
}
