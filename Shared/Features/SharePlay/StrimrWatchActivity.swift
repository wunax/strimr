import Foundation
import GroupActivities

struct StrimrWatchActivity: GroupActivity, Hashable, Sendable {
    static let activityIdentifier = "com.github.wunax.strimr.watch"

    let activityID: UUID
    let serverIdentifier: String
    let ratingKey: String
    let mediaType: PlexItemType
    let title: String
    let initialPosition: Double

    var metadata: GroupActivityMetadata {
        get async {
            var metadata = GroupActivityMetadata()
            metadata.type = .watchTogether
            metadata.title = title
            metadata.subtitle = String(localized: "sharePlay.activity.subtitle")
            metadata.supportsContinuationOnTV = true
            return metadata
        }
    }
}
