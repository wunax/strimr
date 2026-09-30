import Foundation

struct MediaOwner: Codable, Hashable, Sendable {
    let server: ServerIdentity
    let userID: String

    nonisolated var id: String {
        [server.provider.rawValue, server.id, userID].joined(separator: "|")
    }
}

extension MediaServices {
    var owner: MediaOwner {
        MediaOwner(server: identity, userID: trackSelectionAccountIdentifier ?? "default")
    }
}

enum ServerAvailability: Equatable, Sendable {
    case reachable
    case unreachable(since: Date)
    case unknown

    var isUnreachable: Bool {
        if case .unreachable = self {
            return true
        }
        return false
    }
}

struct MediaUnavailableOffline: LocalizedError, ExpectedConnectivityError {
    var errorDescription: String? {
        String(localized: "offline.unavailable")
    }
}

enum DownloadEnrichmentState: String, Codable, Sendable {
    case pending
    case done
    case orphaned
}

enum ProgressJournalEvent: String, Codable, Sendable {
    case start
    case pause
    case progress
    case stop
    case watched
}

enum WatchStateSource: String, Codable, Sendable {
    case server
    case local
}

struct OfflineWatchState: Equatable, Sendable {
    var viewOffset: TimeInterval?
    var viewCount: Int
    var played: Bool
    var lastViewedAt: Date?
    var source: WatchStateSource
}

enum OfflineCacheLimit: Int, CaseIterable, Identifiable, Codable {
    case mb250 = 250
    case mb500 = 500
    case gb1 = 1000

    var id: Int {
        rawValue
    }

    var bytes: Int64 {
        Int64(rawValue) * 1_000_000
    }

    var title: String {
        ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }
}

extension Error {
    var isTransportFailure: Bool {
        if let urlError = self as? URLError {
            switch urlError.code {
            case .timedOut, .cannotFindHost, .cannotConnectToHost, .networkConnectionLost,
                 .dnsLookupFailed, .notConnectedToInternet, .secureConnectionFailed,
                 .serverCertificateUntrusted, .serverCertificateHasBadDate, .serverCertificateNotYetValid,
                 .serverCertificateHasUnknownRoot, .clientCertificateRejected, .cannotLoadFromNetwork,
                 .internationalRoamingOff, .dataNotAllowed, .callIsActive, .resourceUnavailable:
                return true
            default:
                return false
            }
        }
        if let jellyfinError = self as? JellyfinAPIError {
            return jellyfinError == .serverUnreachable
        }
        if case PlexAPIError.unreachableServer? = self as? PlexAPIError {
            return true
        }
        if let recoveryError = self as? PlexServerAccessRecoveryError {
            return recoveryError == .connectionFailed
        }
        return false
    }

    var isNotFound: Bool {
        if case let PlexAPIError.requestFailed(statusCode)? = self as? PlexAPIError {
            return statusCode == 404
        }
        if let jellyfinError = self as? JellyfinAPIError {
            return jellyfinError == .httpStatus(404) || jellyfinError == .itemUnavailable
        }
        return false
    }

    var isAuthenticationFailure: Bool {
        if let plexError = self as? PlexAPIError {
            return plexError.isUnauthorized
        }
        if let jellyfinError = self as? JellyfinAPIError {
            return jellyfinError == .authenticationRequired
        }
        if let recoveryError = self as? PlexServerAccessRecoveryError {
            return recoveryError == .accountUnauthorized
        }
        return false
    }
}

enum OfflineArtworkPath {
    private static let downloadPosterPrefix = "strimr-download://"

    static func downloadPoster(_ downloadID: String) -> String {
        downloadPosterPrefix + downloadID
    }

    static func downloadID(fromPosterPath path: String) -> String? {
        guard path.hasPrefix(downloadPosterPrefix) else { return nil }
        return String(path.dropFirst(downloadPosterPrefix.count))
    }
}
