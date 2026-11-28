import AppIntents
import Foundation

/// A library of one of the profile's servers.
struct LibraryEntity: AppEntity {
    static let typeDisplayRepresentation = TypeDisplayRepresentation(
        name: LocalizedStringResource("intents.library.type"),
    )
    static let defaultQuery = LibraryEntityQuery()

    /// The library's `strimr://library` link.
    let id: String
    let title: String
    let serverName: String?

    init(library: Library, serverName: String?) {
        id = DeepLink(.library(library.identity)).url.absoluteString
        title = library.title
        self.serverName = serverName
    }

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(title)", subtitle: serverName.map { "\($0)" })
    }

    var link: DeepLink? {
        URL(string: id).flatMap(DeepLink.init(url:))
    }
}

struct LibraryEntityQuery: EntityStringQuery {
    @MainActor
    func entities(for identifiers: [LibraryEntity.ID]) async throws -> [LibraryEntity] {
        await libraries(includingHidden: true).filter { identifiers.contains($0.id) }
    }

    @MainActor
    func entities(matching string: String) async throws -> [LibraryEntity] {
        await libraries(includingHidden: false).filter { $0.title.localizedCaseInsensitiveContains(string) }
    }

    @MainActor
    func suggestedEntities() async throws -> [LibraryEntity] {
        await libraries(includingHidden: false)
    }

    /// In the order of the Libraries tab. A shortcut made before a library was hidden still finds it.
    @MainActor
    private func libraries(includingHidden: Bool) async -> [LibraryEntity] {
        guard await AppIntentsEnvironment.readySessionManager() != nil,
              let store = AppIntentsEnvironment.libraryStore
        else { return [] }
        if store.libraries.isEmpty {
            try? await store.loadLibraries()
        }
        let libraries = includingHidden ? store.libraries : store.visibleLibraries
        return libraries.map { library in
            LibraryEntity(library: library, serverName: store.showsServerNames ? store.serverName(for: library) : nil)
        }
    }
}
