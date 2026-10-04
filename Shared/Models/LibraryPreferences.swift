import Foundation

/// Library settings of one profile, keyed by `LibraryIdentity` so libraries of different servers never collide.
struct LibraryPreferences: Codable, Equatable {
    var hiddenLibraries: [LibraryIdentity] = []
    var libraryOrder: [LibraryIdentity] = []
    /// Libraries pinned in the tab bar or the sidebar, in their pinned order.
    var navigationLibraries: [LibraryIdentity] = []

    init() {}

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        hiddenLibraries = try container.decodeIfPresent([LibraryIdentity].self, forKey: .hiddenLibraries) ?? []
        libraryOrder = try container.decodeIfPresent([LibraryIdentity].self, forKey: .libraryOrder) ?? []
        navigationLibraries = try container.decodeIfPresent([LibraryIdentity].self, forKey: .navigationLibraries) ?? []
    }

    var isEmpty: Bool {
        hiddenLibraries.isEmpty && libraryOrder.isEmpty && navigationLibraries.isEmpty
    }

    func isHidden(_ library: LibraryIdentity) -> Bool {
        hiddenLibraries.contains(library)
    }

    func ordered(_ libraries: [Library]) -> [Library] {
        PreferenceOrder.sorted(libraries, id: \.identity, order: libraryOrder)
    }

    mutating func setHidden(_ library: LibraryIdentity, hidden: Bool) {
        hiddenLibraries.removeAll { $0 == library }
        if hidden {
            hiddenLibraries.append(library)
        }
    }

    mutating func setOrder(_ available: [LibraryIdentity]) {
        libraryOrder = PreferenceOrder.merged(stored: libraryOrder, available: available)
    }

    mutating func removeLibraries(of servers: Set<ServerIdentity>) {
        let belongs: (LibraryIdentity) -> Bool = { servers.contains($0.server) }
        hiddenLibraries.removeAll(where: belongs)
        libraryOrder.removeAll(where: belongs)
        navigationLibraries.removeAll(where: belongs)
    }

    /// Drops the libraries of `server` that it no longer returns. Only call it after a successful load of the server.
    mutating func pruneLibraries(of server: ServerIdentity, keeping libraryIDs: Set<String>) {
        let isGone: (LibraryIdentity) -> Bool = { $0.server == server && !libraryIDs.contains($0.libraryID) }
        hiddenLibraries.removeAll(where: isGone)
        libraryOrder.removeAll(where: isGone)
        navigationLibraries.removeAll(where: isGone)
    }
}
