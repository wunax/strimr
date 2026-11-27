import Foundation
@testable import Strimr

extension ExploreItem {
    static func make(
        source: ExploreSourceID = .trakt,
        id: String = "1",
        kind: ExploreItemKind = .movie,
        title: String = "Title",
        originalTitle: String? = nil,
        externalIDs: ExternalIDs = ExternalIDs(tmdb: "100"),
        plexGuid: String? = nil,
    ) -> ExploreItem {
        ExploreItem(
            source: source,
            sourceID: id,
            kind: kind,
            title: title,
            originalTitle: originalTitle,
            externalIDs: externalIDs,
            plexGuid: plexGuid,
        )
    }
}

struct ExploreTestError: Error {}
