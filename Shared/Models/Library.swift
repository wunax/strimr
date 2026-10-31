import Foundation

struct Library: Identifiable, Equatable, Hashable, Codable {
    let id: String
    let title: String
    let type: MediaKind
    let sectionId: Int?
    /// Plex's items shared one by one with the user, browsed like a library without a section.
    let isShared: Bool
    private(set) var server: ServerIdentity

    var identity: LibraryIdentity {
        LibraryIdentity(server: server, libraryID: id)
    }

    var plexBrowsePath: String? {
        if let sectionId {
            return "/library/sections/\(sectionId)/all"
        }
        return isShared ? PlexSharedLibrary.browsePath : nil
    }

    var iconName: String {
        if isShared {
            return "person.2.fill"
        }
        return switch type {
        case .movie:
            "film.fill"
        case .series:
            "tv.fill"
        case .season, .episode:
            "play.rectangle.fill"
        case .collection:
            "rectangle.stack.fill"
        case .playlist:
            "music.note.list"
        case .clip:
            "play.rectangle.fill"
        case .folder, .unknown:
            "questionmark.square.fill"
        }
    }

    init(
        id: String,
        title: String,
        type: MediaKind,
        sectionId: Int? = nil,
        isShared: Bool = false,
        server: ServerIdentity,
    ) {
        self.id = id
        self.title = title
        self.type = type
        self.sectionId = sectionId
        self.isShared = isShared
        self.server = server
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        title = try container.decode(String.self, forKey: .title)
        type = try container.decode(MediaKind.self, forKey: .type)
        sectionId = try container.decodeIfPresent(Int.self, forKey: .sectionId)
        isShared = try container.decodeIfPresent(Bool.self, forKey: .isShared) ?? false
        server = try container.decodeIfPresent(ServerIdentity.self, forKey: .server) ?? .unassigned
    }

    func assigning(server: ServerIdentity) -> Library {
        var library = self
        library.server = server
        return library
    }
}

extension Library {
    init(plexSection: PlexSection, server: ServerIdentity) {
        self.init(
            id: plexSection.key,
            title: plexSection.title,
            type: plexSection.type.mediaKind,
            sectionId: Int(plexSection.key),
            server: server,
        )
    }
}
