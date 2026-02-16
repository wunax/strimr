import Foundation
import GroupActivities

struct StrimrSharePlayActivity: GroupActivity {
    static let activityIdentifier = "com.strimr.shareplay.watch"

    let ratingKey: String
    let type: PlexItemType
    let title: String
    let thumbPath: String?

    var metadata: GroupActivityMetadata {
        var meta = GroupActivityMetadata()
        meta.title = title
        meta.type = .watchTogether
        return meta
    }
}
