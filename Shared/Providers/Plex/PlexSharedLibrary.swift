import Foundation

/// Plex's view of the items shared one by one with the user, which belong to sections the user cannot open.
nonisolated enum PlexSharedLibrary {
    static let id = "shared"
    static let browsePath = "/library/shared/all"
    /// Without a type, the view also lists every fully shared section as an item.
    static let videoTypes = "1,2,3,4"

    static func isSharedPath(_ path: String) -> Bool {
        path.hasPrefix("/library/shared/")
    }

    /// Keeps the video display types, and restricts the untyped "All" one to videos.
    static func videoMeta(_ meta: PlexSectionItemMeta) -> PlexSectionItemMeta {
        let allowedTypes = Set(videoTypes.split(separator: ","))
        let types = meta.type.compactMap { metaType -> PlexSectionItemMetaType? in
            guard let endpoint = PlexEndpoint(key: metaType.key), endpoint.path == browsePath else { return nil }
            guard let type = endpoint.queryItems.first(where: { $0.name == "type" })?.value else {
                return metaType.withKey("\(browsePath)?type=\(videoTypes)")
            }
            return Set(type.split(separator: ",")).isSubset(of: allowedTypes) ? metaType : nil
        }
        return PlexSectionItemMeta(type: types)
    }
}

private extension PlexSectionItemMetaType {
    func withKey(_ key: String) -> PlexSectionItemMetaType {
        PlexSectionItemMetaType(key: key, type: type, title: title, active: active, filter: filter, sort: sort)
    }
}
