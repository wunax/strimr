import AppIntents
import Observation
import SwiftUI
#if !os(tvOS)
    import CoreSpotlight
#endif

/// What the app offers outside itself for the active profile: quick actions, the Dock menu, Siri suggestions and
/// Spotlight. Nothing is offered when the app asks for the profile on launch, as it would show one profile's titles
/// to the others.
@MainActor
@Observable
final class AppEntryPoints {
    struct Snapshot: Equatable {
        let profileID: String
        /// The first title of Continue Watching.
        let resume: MediaItem?
        /// Continue Watching, then Next Up.
        let watching: [MediaItem]
        let downloads: [DownloadedTitle]
        let hasLiveTV: Bool
    }

    struct DownloadedTitle: Equatable {
        let identity: MediaIdentity
        let title: String
        let subtitle: String?
        let kind: MediaKind
        let posterURL: URL?
    }

    static let shared = AppEntryPoints()

    private static let indexLimit = 60
    private static let thumbnailWidth = 300

    private(set) var snapshot: Snapshot?
    private(set) var entities: [MediaEntity] = []

    @ObservationIgnored private var publishTask: Task<Void, Never>?
    @ObservationIgnored private var thumbnails: [String: Data] = [:]

    func entity(id: String) -> MediaEntity? {
        entities.first { $0.id == id }
    }

    func publish(_ snapshot: Snapshot?, registry: ServerRegistry) {
        guard snapshot != self.snapshot else { return }
        if snapshot?.profileID != self.snapshot?.profileID {
            thumbnails = [:]
        }
        self.snapshot = snapshot
        #if os(iOS)
            QuickActions.update(snapshot)
        #endif
        publishTask?.cancel()
        publishTask = Task { [weak self] in
            // Rows reload in bursts, and artwork downloads would compete with playback.
            try? await Task.sleep(for: .seconds(2))
            while AppIntentsEnvironment.sessionManager?.isPlaybackActive == true, !Task.isCancelled {
                try? await Task.sleep(for: .seconds(10))
            }
            guard let self, !Task.isCancelled else { return }
            let entities = await makeEntities(snapshot, registry: registry)
            guard !Task.isCancelled else { return }
            self.entities = entities
            await Self.index(entities)
            StrimrShortcuts.updateAppShortcutParameters()
        }
    }

    private func makeEntities(_ snapshot: Snapshot?, registry: ServerRegistry) async -> [MediaEntity] {
        guard let snapshot else { return [] }
        var entities: [MediaEntity] = []
        var seen: Set<String> = []
        for media in snapshot.watching {
            let entity = MediaEntity(media: media)
            guard seen.insert(entity.id).inserted else { continue }
            var withThumbnail = entity
            withThumbnail.thumbnail = await thumbnail(for: entity.id) {
                await Self.artwork(of: media, services: registry.services(for: media.identity.server))
            }
            entities.append(withThumbnail)
            if entities.count >= Self.indexLimit {
                return entities
            }
        }
        for download in snapshot.downloads {
            var entity = MediaEntity(
                identity: download.identity,
                title: download.title,
                subtitle: download.subtitle,
                kind: download.kind,
            )
            guard seen.insert(entity.id).inserted else { continue }
            entity.thumbnail = await thumbnail(for: entity.id) {
                await Self.thumbnailData(from: download.posterURL)
            }
            entities.append(entity)
            if entities.count >= Self.indexLimit {
                break
            }
        }
        return entities
    }

    private func thumbnail(for id: String, load: () async -> Data?) async -> Data? {
        if let data = thumbnails[id] {
            return data
        }
        let data = await load()
        thumbnails[id] = data
        return data
    }

    private static func artwork(of media: MediaItem, services: MediaServices?) async -> Data? {
        guard let services,
              let resource = try? await services.artwork.artwork(
                  for: .playable(media),
                  kind: .cardThumb,
                  width: thumbnailWidth,
                  height: nil,
              )
        else { return nil }
        switch resource {
        case let .data(data):
            return data
        case let .url(url):
            return await thumbnailData(from: url)
        }
    }

    /// The bytes are kept, never the URL, which can carry a token.
    private static func thumbnailData(from url: URL?) async -> Data? {
        guard let url else { return nil }
        if url.isFileURL {
            return try? Data(contentsOf: url)
        }
        guard let (data, response) = try? await URLSession.shared.data(from: url),
              (response as? HTTPURLResponse).map({ 200 ..< 300 ~= $0.statusCode }) ?? false
        else { return nil }
        return data
    }

    private static func index(_ entities: [MediaEntity]) async {
        #if !os(tvOS)
            let index = CSSearchableIndex.default()
            do {
                try await index.deleteAppEntities(ofType: MediaEntity.self)
                if !entities.isEmpty {
                    try await index.indexAppEntities(entities)
                }
            } catch {
                guard !Task.isCancelled, !error.isCancellation else { return }
                ErrorReporter.capture(error)
            }
        #endif
    }
}

extension MediaEntity {
    init(identity: MediaIdentity, title: String, subtitle: String?, kind: MediaKind) {
        id = DeepLink(.media(.item(identity, kind: kind))).url.absoluteString
        self.title = title
        self.subtitle = subtitle
        kindRawValue = kind.rawValue
        thumbnail = nil
    }
}

// MARK: - Publishing

extension View {
    /// Publishes the active profile's titles to quick actions, the Dock menu, Siri and Spotlight. Installed on each
    /// platform's main view.
    func publishesAppEntryPoints(homeViewModel: HomeViewModel) -> some View {
        modifier(AppEntryPointsModifier(homeViewModel: homeViewModel))
    }
}

private struct AppEntryPointsModifier: ViewModifier {
    @Environment(SessionManager.self) private var sessionManager
    @Environment(ServerRegistry.self) private var registry
    @Environment(SettingsManager.self) private var settingsManager
    #if !os(tvOS)
        @Environment(DownloadManager.self) private var downloadManager
    #endif

    let homeViewModel: HomeViewModel

    func body(content: Content) -> some View {
        content.onChange(of: snapshot, initial: true) { _, snapshot in
            #if DEBUG
                if DemoMode.isEnabled {
                    return
                }
            #endif
            AppEntryPoints.shared.publish(snapshot, registry: registry)
        }
    }

    private var snapshot: AppEntryPoints.Snapshot? {
        guard let profile = sessionManager.activeProfile,
              !(sessionManager.profileStore.asksProfileOnLaunch && sessionManager.profiles.count > 1)
        else { return nil }
        let rows = homeViewModel.availableRows
        let resume = rows.first { $0.kind == .continueWatching }?.items.lazy.compactMap(\.playableItem).first
        return AppEntryPoints.Snapshot(
            profileID: profile.id,
            resume: resume,
            watching: HomeHeroSlides.watchingItems(in: rows),
            downloads: downloads,
            hasLiveTV: !registry.liveTVServices.isEmpty && settingsManager.interface.displayLiveTVTab,
        )
    }

    private var downloads: [AppEntryPoints.DownloadedTitle] {
        #if os(tvOS)
            []
        #else
            downloadManager.ownedItems
                .filter(\.isPlayable)
                .compactMap { item in
                    guard let identity = item.identity else { return nil }
                    let metadata = item.metadata
                    return AppEntryPoints.DownloadedTitle(
                        identity: identity,
                        title: metadata.grandparentTitle ?? metadata.title,
                        subtitle: metadata.type == .episode ? metadata.title : metadata.year.map(String.init),
                        kind: metadata.type,
                        posterURL: downloadManager.localPosterURL(for: item),
                    )
                }
        #endif
    }
}
