import Foundation

/// The channels a user last watched on one server, most recent first, kept on this device only.
struct LiveTVRecentChannels {
    static let limit = 10
    /// A channel counts as watched once it has played this long in the player.
    static let watchThreshold: TimeInterval = 60

    private let defaults: UserDefaults
    private let key: String

    init(server: ServerIdentity, userID: String?, defaults: UserDefaults = .standard) {
        self.defaults = defaults
        key = "strimr.liveTV.recentChannels.\(server.provider.rawValue).\(server.id).\(userID ?? "default")"
    }

    var channelKeys: [String] {
        defaults.stringArray(forKey: key) ?? []
    }

    func record(_ channel: LiveTVChannelIdentity) {
        defaults.set(Self.inserting(channel.storageKey, into: channelKeys), forKey: key)
    }

    static func inserting(_ channelKey: String, into keys: [String]) -> [String] {
        Array(([channelKey] + keys.filter { $0 != channelKey }).prefix(limit))
    }
}
