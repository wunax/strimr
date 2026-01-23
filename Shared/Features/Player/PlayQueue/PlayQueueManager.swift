import Foundation

final class PlayQueueManager {
    private let repository: PlayQueueRepository

    init(context: PlexAPIContext) throws {
        repository = try PlayQueueRepository(context: context)
    }

    func createQueue(for ratingKey: String, continuous: Bool = false) async throws -> PlayQueueState {
        let response = try await repository.createQueue(for: ratingKey, continuous: continuous)
        return PlayQueueState(response: response)
    }

    func fetchQueue(id: Int) async throws -> PlayQueueState {
        let response = try await repository.getQueue(id: id)
        return PlayQueueState(response: response)
    }
}
