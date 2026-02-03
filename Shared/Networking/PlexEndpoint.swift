import Foundation

struct PlexEndpoint: Equatable {
    let path: String
    let queryItems: [URLQueryItem]

    init(path: String, queryItems: [URLQueryItem]) {
        self.path = path
        self.queryItems = queryItems
    }

    init?(key: String) {
        guard let components = URLComponents(string: "https://localhost\(key)") else { return nil }
        let resolvedPath = components.path.isEmpty ? key : components.path
        let resolvedItems = components.queryItems ?? []
        self.init(path: resolvedPath, queryItems: resolvedItems)
    }
}
