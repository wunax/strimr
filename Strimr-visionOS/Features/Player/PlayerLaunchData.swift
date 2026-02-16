import Foundation

struct PlayerLaunchData: Codable, Hashable {
    let playQueueId: Int
    let selectedRatingKey: String
    let shouldResumeFromOffset: Bool
    let selectedItemID: Int?
    let selectedMetadataItemID: String?

    init(playQueue: PlayQueueState, shouldResumeFromOffset: Bool) {
        playQueueId = playQueue.id
        selectedRatingKey = playQueue.selectedRatingKey ?? ""
        self.shouldResumeFromOffset = shouldResumeFromOffset
        selectedItemID = playQueue.selectedItemID
        selectedMetadataItemID = playQueue.selectedMetadataItemID
    }

    var playQueueState: PlayQueueState {
        PlayQueueState(localRatingKey: selectedRatingKey)
    }
}
