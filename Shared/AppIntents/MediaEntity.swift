import AppIntents
import Foundation
#if !os(tvOS)
    import CoreSpotlight
#endif

/// A movie, show or episode of one of the profile's servers, for Siri, Shortcuts and Spotlight.
struct MediaEntity: AppEntity {
    static let typeDisplayRepresentation = TypeDisplayRepresentation(
        name: LocalizedStringResource("intents.media.type"),
    )
    static let defaultQuery = MediaEntityQuery()

    /// The item's `strimr://media` link, which names its server.
    let id: String
    let title: String
    let subtitle: String?
    let kindRawValue: String
    /// Drawn in Spotlight; read from the artwork the app loaded, never from a URL with a token.
    var thumbnail: Data?

    var kind: MediaKind {
        MediaKind(rawValue: kindRawValue) ?? .unknown
    }

    var identity: MediaIdentity? {
        guard let url = URL(string: id), let link = DeepLink(url: url),
              case let .media(.item(identity, _)) = link.destination
        else { return nil }
        return identity
    }

    init(media: MediaItem, thumbnail: Data? = nil) {
        id = DeepLink(.media(.item(media.identity, kind: media.type))).url.absoluteString
        title = media.primaryLabel
        subtitle = media.secondaryLabel
        kindRawValue = media.type.rawValue
        self.thumbnail = thumbnail
    }

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(
            title: "\(title)",
            subtitle: subtitle.map { "\($0)" },
            image: thumbnail.map { .init(data: $0) },
        )
    }

    func link(_ destination: (DeepLink.MediaTarget) -> DeepLink.Destination) -> DeepLink? {
        identity.map { DeepLink(destination(.item($0, kind: kind))) }
    }
}

#if !os(tvOS)
    extension MediaEntity: IndexedEntity {
        var attributeSet: CSSearchableItemAttributeSet {
            let attributes = CSSearchableItemAttributeSet(contentType: .movie)
            attributes.title = title
            attributes.displayName = title
            attributes.contentDescription = subtitle
            attributes.thumbnailData = thumbnail
            return attributes
        }
    }
#endif

struct MediaEntityQuery: EntityStringQuery {
    private static let resultLimit = 20

    @MainActor
    func entities(for identifiers: [MediaEntity.ID]) async throws -> [MediaEntity] {
        guard let sessionManager = await AppIntentsEnvironment.readySessionManager() else { return [] }
        var entities: [MediaEntity] = []
        for identifier in identifiers {
            if let known = AppEntryPoints.shared.entity(id: identifier) {
                entities.append(known)
                continue
            }
            guard let url = URL(string: identifier), let link = DeepLink(url: url),
                  case let .media(.item(identity, _)) = link.destination,
                  let services = sessionManager.registry.services(for: identity.server),
                  let media = try? await services.detail.mediaItem(id: identity.itemID)
            else { continue }
            entities.append(MediaEntity(media: media))
        }
        return entities
    }

    @MainActor
    func entities(matching string: String) async throws -> [MediaEntity] {
        guard let sessionManager = await AppIntentsEnvironment.readySessionManager() else { return [] }
        let result = await sessionManager.aggregation.fanOut(servers: sessionManager.registry.sessions) { services in
            try await services.search.search(query: string, kinds: [.movie, .series, .episode])
        }
        let items = sessionManager.registry.sessions.flatMap { session in
            (result.value[session.identity] ?? []).compactMap(\.playableItem)
        }
        return items.prefix(Self.resultLimit).map { MediaEntity(media: $0) }
    }

    @MainActor
    func suggestedEntities() async throws -> [MediaEntity] {
        AppEntryPoints.shared.entities
    }
}
