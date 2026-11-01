import Foundation

/// What deleting a media removes from the server's disk, announced before the user confirms.
enum MediaDeletionImpact: Equatable, Sendable {
    /// A movie or an episode, with every file of all its versions.
    case files(count: Int, totalSize: Int64?)
    /// A series or a season, whose files are not listed with it.
    case episodes(count: Int)

    var summary: String {
        switch self {
        case let .files(count, totalSize):
            let files = String(localized: "media.manage.delete.countFile \(count)")
            guard let totalSize, totalSize > 0 else { return files }
            let size = ByteCountFormatter.string(fromByteCount: totalSize, countStyle: .file)
            return String(localized: "media.manage.delete.filesWithSize \(files) \(size)")
        case let .episodes(count):
            return String(localized: "media.labels.countEpisode \(count)")
        }
    }
}
